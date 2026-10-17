import Foundation
import RippleKit

// The wearer's iPhone: setup, the sync heartbeat, and temporary contacts.

extension Engine {
    public func authenticateWearer(token: String?) throws -> String {
        guard let token, !token.isEmpty,
              let userId = db.deviceTokens[Secrets.hash(token)],
              db.users[userId] != nil
        else { throw EngineError.unauthorized }
        return userId
    }

    public func setup(_ request: SetupRequest) throws -> SetupResponse {
        let name = request.displayName.trimmed
        guard !name.isEmpty else { throw EngineError.invalid("Enter the name your contacts will see.") }
        let token = Secrets.randomToken()
        let user = WearerRecord(
            id: newId(),
            displayName: String(name.prefix(60)),
            pairingCode: uniquePairingCode(),
            runId: newId(),
            createdAt: now(),
            lastSyncAt: nil,
            status: nil
        )
        db.users[user.id] = user
        db.deviceTokens[Secrets.hash(token)] = user.id
        log(user.id, "Ripple was set up on \(user.displayName)'s iPhone.")
        persistIfDirty()
        return SetupResponse(userId: user.id, deviceToken: token, pairingCode: user.pairingCode, runId: user.runId)
    }

    func uniquePairingCode() -> String {
        while true {
            let code = Secrets.randomDigits(6)
            if !db.users.values.contains(where: { $0.pairingCode == code }) { return code }
        }
    }

    /// The phone's heartbeat. It reports its status and alarm, and gets back
    /// admin commands, acknowledgments and anything the backup sent.
    public func sync(userId: String, _ request: SyncRequest) throws -> SyncResponse {
        var user = try requireUser(userId)
        let t = now()
        if let last = user.lastSyncAt, t.timeIntervalSince(last) > grace {
            log(userId, "The wearer's iPhone is back after \(Int(t.timeIntervalSince(last))) s of silence.")
        }
        user.lastSyncAt = t
        user.status = request.status
        let name = request.status.displayName.trimmed
        if !name.isEmpty { user.displayName = String(name.prefix(60)) }
        db.users[userId] = user
        dirty = true

        guard request.runId == user.runId else {
            // The demo was reset while the phone held an older run.
            persistIfDirty()
            return SyncResponse(
                serverTime: t, runId: user.runId, resetRequired: true, commands: [],
                temporaryContacts: temporaryViews(userId), feedback: nil,
                publicBaseURL: config.publicBaseURL, pairingCode: user.pairingCode
            )
        }

        for result in request.commandResults {
            guard var command = db.commands[result.commandId], command.userId == userId,
                  command.state == .queued || command.state == .delivered
            else { continue }
            command.state = result.ok ? .done : .rejected
            command.finishedAt = t
            command.result = result.message
            db.commands[command.id] = command
            log(userId, "\(command.command.kind.label): \(result.ok ? "done" : "refused") on the iPhone (\(result.message)).")
        }

        var feedback: AlarmFeedback?
        if let alarm = request.alarm, alarm.runId == user.runId {
            upsertAlarm(alarm, userId: userId)
            feedback = makeFeedback(alarm.id)
        }

        var commands: [DeviceCommand] = []
        for (id, command) in db.commands where command.userId == userId && command.runId == user.runId
            && (command.state == .queued || command.state == .delivered) {
            if command.state == .queued {
                db.commands[id]?.state = .delivered
                db.commands[id]?.deliveredAt = t
                log(userId, "\(command.command.kind.label) reached the wearer's iPhone.")
            }
            commands.append(command.command)
        }
        commands.sort { $0.createdAt < $1.createdAt }

        persistIfDirty()
        return SyncResponse(
            serverTime: t, runId: user.runId, resetRequired: false, commands: commands,
            temporaryContacts: temporaryViews(userId), feedback: feedback,
            publicBaseURL: config.publicBaseURL, pairingCode: user.pairingCode
        )
    }

    func upsertAlarm(_ alarm: Alarm, userId: String) {
        let t = now()
        if var record = db.alarms[alarm.id] {
            guard record.userId == userId else { return }
            let previous = record.snapshot
            record.snapshot = alarm
            record.updatedAt = t
            if previous.isOpen && !alarm.isOpen {
                record.closedAt = t
                log(userId, "Alarm closed on the iPhone: \(alarm.closeReason?.label ?? "closed").")
            }
            if !previous.duress && alarm.duress {
                log(userId, "Duress hold on the Watch. The wearer's screens show a normal dismissal; escalation continues.")
            }
            db.alarms[alarm.id] = record
            logMessageChanges(from: previous, to: alarm, userId: userId)
        } else {
            db.alarms[alarm.id] = AlarmRecord(
                id: alarm.id, userId: userId, runId: alarm.runId, snapshot: alarm, firstSeenAt: t, updatedAt: t,
                acknowledgment: nil, closedByAdmin: false, closedAt: alarm.isOpen ? nil : t
            )
            log(userId, "Alarm registered by the iPhone (\(alarm.source.rawValue)). Response countdown ends \(timeText(alarm.deadline)).")
            if alarm.duress {
                log(userId, "Duress hold on the Watch. The wearer's screens show a normal dismissal; escalation continues.")
            }
            logMessageChanges(from: nil, to: alarm, userId: userId)
        }
        for recipient in alarm.recipients {
            let hash = Secrets.hash(recipient.ackToken)
            if db.ackTokens[hash] == nil {
                db.ackTokens[hash] = AckTokenRecord(alarmId: alarm.id, recipientId: recipient.id, userId: userId, runId: alarm.runId)
            }
        }
        dirty = true
    }

    func logMessageChanges(from previous: Alarm?, to alarm: Alarm, userId: String) {
        for message in alarm.messages {
            let before = previous?.message(message.id)
            guard before?.status != message.status else { continue }
            guard message.status != .pending else { continue }
            log(userId, "\(message.kind.label) to \(message.recipientName): \(message.status.label.lowercased()) (\(message.path.label)).")
        }
    }

    func makeFeedback(_ alarmId: String) -> AlarmFeedback? {
        guard let record = db.alarms[alarmId] else { return nil }
        let backups = db.backups.values
            .filter { $0.message.alarmId == alarmId }
            .map { $0.message }
            .sorted { $0.createdAt < $1.createdAt }
        return AlarmFeedback(alarmId: alarmId, acknowledgment: record.acknowledgment, backupMessages: backups, closedByAdmin: record.closedByAdmin)
    }

    // MARK: Temporary contacts

    func temporaryViews(_ userId: String) -> [TemporaryContactView] {
        guard let user = db.users[userId] else { return [] }
        let t = now()
        return db.temporaryContacts.values
            .filter { $0.userId == userId && $0.runId == user.runId }
            .sorted { $0.invitedAt < $1.invitedAt }
            .map { temporaryView($0, at: t) }
    }

    func temporaryView(_ record: TemporaryContactRecord, at t: Date) -> TemporaryContactView {
        var state = record.state
        if state == .active, let expires = record.expiresAt, expires <= t {
            state = .expired
        }
        return TemporaryContactView(
            id: record.id, name: record.name, phone: record.phone, shareLocation: record.shareLocation, state: state,
            invitedAt: record.invitedAt, consentAt: record.consentAt, expiresAt: record.expiresAt
        )
    }

    public func inviteTemporary(userId: String, _ request: InviteTemporaryRequest, key: String?) throws -> InviteTemporaryResponse {
        try once(key, scope: "\(userId):invite") {
            let user = try requireUser(userId)
            let name = request.name.trimmed
            guard !name.isEmpty else { throw EngineError.invalid("Enter the temporary contact's name.") }
            guard let phone = Phone.normalize(request.phone) else {
                throw EngineError.invalid("That phone number doesn't look right. Include the area code.")
            }
            let raw = Secrets.randomToken()
            let record = TemporaryContactRecord(
                id: newId(), userId: userId, runId: user.runId, name: String(name.prefix(60)), phone: phone,
                shareLocation: request.shareLocation, state: .invited, invitedAt: now(), consentAt: nil, expiresAt: nil
            )
            db.temporaryContacts[record.id] = record
            db.inviteTokens[Secrets.hash(raw)] = record.id
            log(userId, "Invited \(record.name) to be a temporary contact. Not active until they agree.")
            dirty = true
            return InviteTemporaryResponse(contact: temporaryView(record, at: now()), inviteURL: link("/t/\(raw)"))
        }
    }

    public func removeTemporary(userId: String, contactId: String) throws -> TemporaryContactsResponse {
        guard var record = db.temporaryContacts[contactId], record.userId == userId else {
            throw EngineError.notFound("That temporary contact doesn't exist.")
        }
        if record.state == .invited || record.state == .active {
            record.state = .removed
            db.temporaryContacts[contactId] = record
            db.inviteTokens = db.inviteTokens.filter { $0.value != contactId }
            log(userId, "\(record.name) was removed as a temporary contact. They won't receive new alerts.")
            dirty = true
        }
        persistIfDirty()
        return TemporaryContactsResponse(contacts: temporaryViews(userId))
    }
}
