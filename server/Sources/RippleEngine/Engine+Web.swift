import Foundation
import RippleKit

// The one-page websites contacts open from a text: the acknowledge page and
// the temporary contact consent page. No app, account or login.

extension Engine {
    func ackAccess(_ raw: String) throws -> (AckTokenRecord, AlarmRecord, AlarmRecipient) {
        guard let token = db.ackTokens[Secrets.hash(raw)],
              let record = db.alarms[token.alarmId],
              let recipient = record.snapshot.recipients.first(where: { $0.id == token.recipientId })
        else { throw EngineError.notFound("This link isn't valid.") }
        guard db.users[token.userId]?.runId == token.runId else {
            throw EngineError.gone("This alert has closed.")
        }
        return (token, record, recipient)
    }

    func ackView(_ record: AlarmRecord, recipient: AlarmRecipient) -> AckView {
        let ack = record.acknowledgment
        return AckView(
            wearerName: record.snapshot.wearerName,
            alertTime: alertTime(record) ?? record.snapshot.startedAt,
            open: isOpen(record),
            acknowledged: ack != nil,
            youAcknowledged: ack?.recipientId == recipient.id,
            responderName: ack?.name
        )
    }

    /// The page stops working once the alarm closes.
    public func ackPage(token raw: String) throws -> AckView {
        let (_, record, recipient) = try ackAccess(raw)
        guard isOpen(record) else { throw EngineError.gone("This alert has closed. No action is needed.") }
        return ackView(record, recipient: recipient)
    }

    /// "I'm checking on [Name]": records who responded and when.
    public func acknowledge(token raw: String) throws -> AckView {
        let (_, record, recipient) = try ackAccess(raw)
        guard isOpen(record) else { throw EngineError.gone("This alert has closed. No action is needed.") }
        var updated = record
        let t = now()
        if updated.acknowledgment == nil {
            updated.acknowledgment = Acknowledgment(recipientId: recipient.id, name: recipient.name, at: t)
            db.alarms[record.id] = updated
            log(record.userId, "\(recipient.name) tapped \"I'm checking on \(record.snapshot.wearerName)\". That means they took responsibility, not that help has arrived.")
            dirty = true
        } else if updated.acknowledgment?.recipientId != recipient.id {
            log(record.userId, "\(recipient.name) also tapped the acknowledge link.")
            dirty = true
        }
        persistIfDirty()
        return ackView(updated, recipient: recipient)
    }

    // MARK: Temporary contact consent

    func inviteAccess(_ raw: String) throws -> TemporaryContactRecord {
        guard let id = db.inviteTokens[Secrets.hash(raw)], let record = db.temporaryContacts[id] else {
            throw EngineError.notFound("This invitation link isn't valid.")
        }
        guard db.users[record.userId]?.runId == record.runId, record.state != .removed else {
            throw EngineError.gone("This invitation was withdrawn.")
        }
        return record
    }

    func inviteView(_ record: TemporaryContactRecord) -> TemporaryInviteView {
        let view = temporaryView(record, at: now())
        return TemporaryInviteView(
            wearerName: db.users[record.userId]?.displayName ?? "A Ripple user",
            contactName: record.name,
            phoneHint: Phone.hint(record.phone),
            shareLocation: record.shareLocation,
            state: view.state,
            durationMinutes: Int(config.temporarySessionSeconds / 60),
            expiresAt: record.expiresAt
        )
    }

    public func invitePage(token raw: String) throws -> TemporaryInviteView {
        inviteView(try inviteAccess(raw))
    }

    /// Records consent and starts the one-hour session.
    public func acceptInvite(token raw: String) throws -> TemporaryInviteView {
        var record = try inviteAccess(raw)
        guard record.state == .invited else { return inviteView(record) }
        let t = now()
        record.state = .active
        record.consentAt = t
        record.expiresAt = t.addingTimeInterval(config.temporarySessionSeconds)
        db.temporaryContacts[record.id] = record
        log(record.userId, "\(record.name) agreed to be a temporary contact until \(timeText(record.expiresAt!)). They join Tier 1 until then.")
        dirty = true
        persistIfDirty()
        return inviteView(record)
    }
}
