import Foundation
import RippleKit

// The declared backup sender. The phone always sends first; the backend texts
// only when a message is overdue by the grace period, or the phone has gone
// quiet, and marks every backup text "Sent by Ripple backup".

extension Engine {
    /// Called by the worker about twice a second. Returns backup texts to send now.
    public func tick() -> [OutboundMessage] {
        let t = now()
        var outbound: [OutboundMessage] = []
        for record in db.alarms.values where isOpen(record) {
            guard let user = db.users[record.userId], user.runId == record.runId else { continue }
            evaluateBackup(record, user: user, at: t, outbound: &outbound)
        }
        if t.timeIntervalSince(lastPrune) > 60 {
            prune(at: t)
            lastPrune = t
        }
        persistIfDirty()
        return outbound
    }

    func evaluateBackup(_ record: AlarmRecord, user: WearerRecord, at t: Date, outbound: inout [OutboundMessage]) {
        let alarm = record.snapshot
        let silent = phoneSilent(user, at: t)
        let merged = mergedMessages(record)
        let eligible: (AlarmRecipient) -> Bool = { recipient in
            !recipient.temporary || self.temporaryEligible(recipient.id, at: t)
        }

        func overdue(_ dueAt: Date) -> Bool {
            t >= dueAt.addingTimeInterval(grace) || (silent && t >= dueAt)
        }

        func needsBackup(_ id: String, dueAt: Date) -> Bool {
            guard let message = merged[id] else { return overdue(dueAt) }
            if message.path == .backup { return false }
            switch message.status {
            case .submitted, .unknown, .cancelled:
                return false
            case .failed:
                return true
            case .pending:
                // Handed to the Shortcuts app: it may have gone out.
                if message.launchedAt != nil { return false }
                return silent || t.timeIntervalSince(message.updatedAt) > grace
            }
        }

        // 1. Alert to Tier 1. Due at the end of the countdown, or right away after a duress hold.
        let alertDueAt = min(alarm.alertedAt ?? alarm.deadline, alarm.deadline)
        var sentAlerts: [String] = []
        for recipient in RecipientRules.alertRecipients(alarm, isEligible: eligible) {
            let id = OutMessage.makeId(alarmId: alarm.id, recipientId: recipient.id, kind: .alert)
            if needsBackup(id, dueAt: alertDueAt) {
                queueBackup(record, recipient: recipient, kind: .alert, text: recipient.alertText, outbound: &outbound)
                sentAlerts.append(recipient.name)
            }
        }
        if !sentAlerts.isEmpty {
            let reason = silent ? "the iPhone went quiet" : "the iPhone didn't report the alert in time"
            log(record.userId, "Backup sender: \(reason), so the backend texted the alert to \(sentAlerts.joined(separator: ", ")) by SMS.")
        }

        // 2. Escalation to Tier 2 when nobody acknowledged within the window.
        let ack = record.acknowledgment ?? alarm.acknowledgment
        let current = db.alarms[record.id] ?? record
        if ack == nil, let alertedAt = alertTime(current) {
            let escalationDueAt = alertedAt.addingTimeInterval(TimeInterval(alarm.ackWindowSeconds))
            var escalated: [String] = []
            for recipient in RecipientRules.escalationRecipients(alarm, isEligible: eligible) {
                let id = OutMessage.makeId(alarmId: alarm.id, recipientId: recipient.id, kind: .escalation)
                if needsBackup(id, dueAt: escalationDueAt) {
                    queueBackup(record, recipient: recipient, kind: .escalation, text: recipient.escalationText, outbound: &outbound)
                    escalated.append(recipient.name)
                }
            }
            if !escalated.isEmpty {
                log(record.userId, "Backup sender: nobody acknowledged, so the backend texted Tier 2 (\(escalated.joined(separator: ", "))).")
            }
        }

        // 3. "Someone responding" to everyone else already texted.
        if let ack {
            let texted = Set(mergedMessages(current).values
                .filter { ($0.kind == .alert || $0.kind == .escalation) && $0.mayHaveBeenSent }
                .map { $0.recipientId })
            var told: [String] = []
            for recipient in alarm.recipients where texted.contains(recipient.id) && recipient.id != ack.recipientId {
                let id = OutMessage.makeId(alarmId: alarm.id, recipientId: recipient.id, kind: .responding)
                if needsBackup(id, dueAt: ack.at) {
                    let text = MessageTemplates.responding(contact: ack.name, name: alarm.wearerName)
                    queueBackup(record, recipient: recipient, kind: .responding, text: text, outbound: &outbound)
                    told.append(recipient.name)
                }
            }
            if !told.isEmpty {
                log(record.userId, "Backup sender: told \(told.joined(separator: ", ")) that \(ack.name) is checking.")
            }
        }
    }

    func queueBackup(_ record: AlarmRecord, recipient: AlarmRecipient, kind: MessageKind, text: String, outbound: inout [OutboundMessage]) {
        let t = now()
        var message = OutMessage(
            alarmId: record.id, recipientId: recipient.id, recipientName: recipient.name, phone: recipient.phone,
            kind: kind, text: text + MessageTemplates.backupNote, status: .pending, path: .backup, createdAt: t
        )
        message.launchedAt = t
        if let allowed = config.demoRecipients, !allowed.contains(recipient.phone) {
            message.status = .failed
            message.detail = "Not a designated demo recipient"
            db.backups[message.id] = BackupRecord(message: message, userId: record.userId, providerMessageId: nil)
            log(record.userId, "Backup text to \(recipient.name) refused: not a designated demo recipient.")
            dirty = true
            return
        }
        db.backups[message.id] = BackupRecord(message: message, userId: record.userId, providerMessageId: nil)
        outbound.append(OutboundMessage(messageId: message.id, to: recipient.phone, body: message.text))
        dirty = true
    }

    /// What the SMS provider said. Submission is not proof a person received it.
    public func recordSendResult(messageId: String, result: SendResult) {
        guard var backup = db.backups[messageId] else { return }
        backup.message.status = result.status
        backup.message.detail = result.error
        backup.message.updatedAt = now()
        backup.providerMessageId = result.providerMessageId
        db.backups[messageId] = backup
        log(backup.userId, "Backup \(backup.message.kind.label.lowercased()) to \(backup.message.recipientName): \(result.status.label.lowercased())\(result.error.map { " (\($0))" } ?? "").")
        dirty = true
        persistIfDirty()
    }

    /// Delivery evidence from Twilio's status callback.
    public func recordProviderStatus(providerMessageId: String, status: String) {
        guard let match = db.backups.first(where: { $0.value.providerMessageId == providerMessageId }) else { return }
        db.backups[match.key]?.message.detail = "Carrier status: \(status)"
        if status == "failed" || status == "undelivered" {
            db.backups[match.key]?.message.status = .failed
        }
        db.backups[match.key]?.message.updatedAt = now()
        dirty = true
        persistIfDirty()
    }

    /// The next time the backend would text if the phone stays quiet. Shown in the admin app.
    func nextBackupAt(_ record: AlarmRecord, user: WearerRecord, at t: Date) -> Date? {
        guard isOpen(record) else { return nil }
        let alarm = record.snapshot
        let silent = phoneSilent(user, at: t)
        let pad: TimeInterval = silent ? 0 : grace
        if alertTime(record) == nil {
            return min(alarm.alertedAt ?? alarm.deadline, alarm.deadline).addingTimeInterval(pad)
        }
        if record.acknowledgment == nil, alarm.acknowledgment == nil, let alertedAt = alertTime(record),
           !RecipientRules.escalationRecipients(alarm, isEligible: { !$0.temporary || self.temporaryEligible($0.id, at: t) }).isEmpty,
           alarm.escalatedAt == nil {
            return alertedAt.addingTimeInterval(TimeInterval(alarm.ackWindowSeconds) + pad)
        }
        return nil
    }

    func prune(at t: Date) {
        db.idempotency = db.idempotency.filter { $0.value.createdAt > t.addingTimeInterval(-3600) }
        if db.events.count > 5000 {
            db.events.removeFirst(db.events.count - 5000)
        }
        // Keep only open alarms and those closed in the last two hours.
        let cutoff = t.addingTimeInterval(-2 * 3600)
        let stale = Set(db.alarms.values.filter { !isOpen($0) && ($0.closedAt ?? $0.updatedAt) < cutoff }.map { $0.id })
        if !stale.isEmpty {
            db.alarms = db.alarms.filter { !stale.contains($0.key) }
            db.backups = db.backups.filter { !stale.contains($0.value.message.alarmId) }
            db.ackTokens = db.ackTokens.filter { !stale.contains($0.value.alarmId) }
        }
        dirty = true
    }
}
