import Foundation
import RippleKit

// The demo admin app. An admin can only control wearers it paired with.
// Commands go through the same alarm behaviour as the wearer's own actions.

extension Engine {
    public func adminLogin(_ request: AdminLoginRequest) throws -> AdminLoginResponse {
        guard !config.adminSecret.isEmpty, request.secret == config.adminSecret else {
            throw EngineError.forbidden("That admin secret isn't right.")
        }
        let name = request.name.trimmed.isEmpty ? "Demo admin" : String(request.name.trimmed.prefix(40))
        let token = Secrets.randomToken()
        let admin = AdminRecord(id: newId(), name: name, createdAt: now())
        db.admins[Secrets.hash(token)] = admin
        dirty = true
        persistIfDirty()
        return AdminLoginResponse(adminId: admin.id, adminToken: token)
    }

    public func authenticateAdmin(token: String?) throws -> String {
        guard let token, !token.isEmpty, let admin = db.admins[Secrets.hash(token)] else {
            throw EngineError(status: 401, code: "unauthorized", message: "Sign in to the demo admin app again.")
        }
        return admin.id
    }

    func adminName(_ adminId: String) -> String {
        db.admins.values.first { $0.id == adminId }?.name ?? "Demo admin"
    }

    public func pair(adminId: String, _ request: PairRequest) throws -> PairResponse {
        let code = request.pairingCode.filter { $0.isNumber }
        guard let user = db.users.values.first(where: { $0.pairingCode == code }) else {
            throw EngineError.notFound("No wearer has that pairing code.")
        }
        db.assignments[adminId, default: []].insert(user.id)
        log(user.id, "\(adminName(adminId)) paired with this wearer for demo control.")
        persistIfDirty()
        return PairResponse(wearer: summary(user))
    }

    public func adminWearers(adminId: String) -> [AdminWearerSummary] {
        (db.assignments[adminId] ?? [])
            .compactMap { db.users[$0] }
            .sorted { $0.createdAt < $1.createdAt }
            .map { summary($0) }
    }

    func summary(_ user: WearerRecord) -> AdminWearerSummary {
        AdminWearerSummary(
            userId: user.id,
            displayName: user.displayName,
            online: isOnline(user, at: now()),
            monitoring: user.status?.monitoring ?? false,
            alarmOpen: db.alarms.values.contains { $0.userId == user.id && $0.runId == user.runId && isOpen($0) }
        )
    }

    /// Every admin command goes through this check. Refusals are recorded.
    func requireAssignment(_ adminId: String, _ userId: String) throws -> WearerRecord {
        guard let user = db.users[userId] else { throw EngineError.notFound("No such wearer.") }
        guard db.assignments[adminId]?.contains(userId) == true else {
            log(userId, "Blocked a demo command from an admin who isn't paired with this wearer.")
            persistIfDirty()
            throw EngineError.forbidden("This admin isn't paired with that wearer.")
        }
        return user
    }

    func currentAlarm(_ user: WearerRecord) -> AlarmRecord? {
        let alarms = db.alarms.values.filter { $0.userId == user.id && $0.runId == user.runId }
        if let open = alarms.filter({ isOpen($0) }).max(by: { $0.firstSeenAt < $1.firstSeenAt }) {
            return open
        }
        return alarms.max(by: { $0.firstSeenAt < $1.firstSeenAt })
    }

    public func adminView(adminId: String, userId: String) throws -> AdminWearerView {
        let user = try requireAssignment(adminId, userId)
        return buildAdminView(user)
    }

    func buildAdminView(_ user: WearerRecord) -> AdminWearerView {
        let t = now()
        let record = currentAlarm(user)
        var messages: [OutMessage] = []
        if let record {
            messages = mergedMessages(record).values.sorted { $0.createdAt < $1.createdAt }
        }
        let commands = db.commands.values
            .filter { $0.userId == user.id && $0.runId == user.runId }
            .sorted { $0.command.createdAt > $1.command.createdAt }
            .prefix(15)
            .map { CommandView(id: $0.id, kind: $0.command.kind, state: $0.state, createdAt: $0.command.createdAt, deliveredAt: $0.deliveredAt, result: $0.result) }
        let events = db.events
            .filter { $0.userId == user.id && $0.runId == user.runId }
            .suffix(60)
            .reversed()
            .map { EventView(id: $0.id, at: $0.at, text: $0.text) }
        return AdminWearerView(
            serverTime: t,
            runId: user.runId,
            wearer: summary(user),
            status: user.status,
            lastSyncAt: user.lastSyncAt,
            alarm: record?.snapshot,
            messages: messages,
            acknowledgment: record?.acknowledgment ?? record?.snapshot.acknowledgment,
            closedByAdmin: record?.closedByAdmin ?? false,
            nextBackupAt: record.flatMap { nextBackupAt($0, user: user, at: t) },
            temporaryContacts: temporaryViews(user.id),
            commands: Array(commands),
            events: Array(events)
        )
    }

    /// Queues a command for the wearer's iPhone. The admin view shows whether it arrived.
    public func sendCommand(adminId: String, userId: String, _ request: AdminCommandRequest, key: String?) throws -> AdminWearerView {
        let user = try requireAssignment(adminId, userId)
        return try once(key, scope: "\(adminId):command") {
            let t = now()
            var command = DeviceCommand(id: newId(), kind: request.kind, countdownSeconds: nil, ackWindowSeconds: nil, durationSeconds: nil, createdAt: t)
            switch request.kind {
            case .triggerAlarm:
                command.countdownSeconds = request.countdownSeconds.map { min(max($0, 5), 600) }
            case .cutConnection:
                command.durationSeconds = min(max(request.durationSeconds ?? 90, 10), 600)
            case .setTimers:
                command.countdownSeconds = request.countdownSeconds.map { min(max($0, 5), 600) }
                command.ackWindowSeconds = request.ackWindowSeconds.map { min(max($0, 5), 1800) }
            case .disableAlarm:
                // Close the backend mirror right away, so the backup can't fire
                // even if the phone never picks the command up.
                if let record = currentAlarm(user), isOpen(record) {
                    db.alarms[record.id]?.closedByAdmin = true
                    db.alarms[record.id]?.closedAt = t
                    log(userId, "\(adminName(adminId)) disabled the current alarm. Pending backup texts are cancelled.")
                }
            }
            db.commands[command.id] = CommandRecord(
                id: command.id, userId: userId, runId: user.runId, adminId: adminId, command: command,
                state: .queued, deliveredAt: nil, finishedAt: nil, result: nil
            )
            log(userId, "\(adminName(adminId)) sent: \(request.kind.label).")
            dirty = true
            return buildAdminView(db.users[userId] ?? user)
        }
    }

    /// "Expire temporary contact now." Applies on the backend immediately.
    public func expireTemporary(adminId: String, userId: String, _ request: ExpireTemporaryRequest) throws -> AdminWearerView {
        let user = try requireAssignment(adminId, userId)
        let t = now()
        var names: [String] = []
        for (id, record) in db.temporaryContacts where record.userId == userId && record.runId == user.runId {
            if let wanted = request.contactId, wanted != id { continue }
            guard record.state == .active || record.state == .invited else { continue }
            db.temporaryContacts[id]?.state = .expired
            db.temporaryContacts[id]?.expiresAt = t
            names.append(record.name)
        }
        if names.isEmpty {
            throw EngineError.conflict("no_temporary_contact", "There's no active temporary contact to expire.")
        }
        log(userId, "\(adminName(adminId)) expired \(names.joined(separator: ", ")) as a temporary contact. They won't receive new alerts.")
        dirty = true
        persistIfDirty()
        return buildAdminView(db.users[userId] ?? user)
    }

    /// Starts a new demo run and deletes the old run's alarms, messages,
    /// links, commands and temporary contacts, so nothing old can fire.
    public func resetDemo(adminId: String, userId: String, key: String?) throws -> AdminWearerView {
        _ = try requireAssignment(adminId, userId)
        return try once(key, scope: "\(adminId):reset") {
            let alarmIds = Set(db.alarms.values.filter { $0.userId == userId }.map { $0.id })
            db.alarms = db.alarms.filter { $0.value.userId != userId }
            db.backups = db.backups.filter { !alarmIds.contains($0.value.message.alarmId) }
            db.ackTokens = db.ackTokens.filter { $0.value.userId != userId }
            db.commands = db.commands.filter { $0.value.userId != userId }
            let contactIds = Set(db.temporaryContacts.values.filter { $0.userId == userId }.map { $0.id })
            db.temporaryContacts = db.temporaryContacts.filter { $0.value.userId != userId }
            db.inviteTokens = db.inviteTokens.filter { !contactIds.contains($0.value) }
            db.events = db.events.filter { $0.userId != userId }
            db.users[userId]?.runId = newId()
            log(userId, "Demo reset by \(adminName(adminId)). Old alarms, timers, links and temporary contacts were deleted.")
            dirty = true
            return buildAdminView(db.users[userId]!)
        }
    }
}
