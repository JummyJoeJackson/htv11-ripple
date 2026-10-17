import Foundation
import KazeKit

// Demo admin commands (PRD §3). An admin can only control wearers it was
// paired with, and admin access never grants responder access.

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
            throw EngineError(status: 401, code: "unauthorized", message: "Sign in to the admin app again.")
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
        log(user.id, actor: .admin, type: "admin.paired", text: "\(adminName(adminId)) paired with this wearer for demo control.",
            wearer: true, responders: false)
        bump(user.id)
        persistIfDirty()
        return PairResponse(wearer: summary(user))
    }

    public func adminWearers(adminId: String) -> [AdminWearerSummary] {
        (db.assignments[adminId] ?? [])
            .compactMap { db.users[$0] }
            .sorted { $0.createdAt < $1.createdAt }
            .map { summary($0) }
    }

    func summary(_ user: UserRecord) -> AdminWearerSummary {
        AdminWearerSummary(
            userId: user.id,
            displayName: user.displayName,
            sessionActive: activeSession(for: user.id) != nil,
            openIncident: openIncident(for: user.id) != nil
        )
    }

    /// Every admin command goes through this check. Refusals are recorded.
    func requireAssignment(_ adminId: String, _ userId: String) throws -> UserRecord {
        guard let user = db.users[userId] else { throw EngineError.notFound("No such wearer.") }
        guard db.assignments[adminId]?.contains(userId) == true else {
            log(userId, actor: .admin, type: "admin.denied",
                text: "Blocked a demo command from an admin who isn't paired with this wearer.", wearer: false, responders: false)
            persistIfDirty()
            throw EngineError.forbidden("This admin isn't paired with that wearer.")
        }
        return user
    }

    public func adminView(adminId: String, userId: String) throws -> AdminView {
        let user = try requireAssignment(adminId, userId)
        return buildAdminView(user)
    }

    public func triggerCheckIn(adminId: String, userId: String, _ request: TriggerCheckInRequest, key: String?) throws -> AdminView {
        let user = try requireAssignment(adminId, userId)
        return try once(key, scope: "\(adminId):checkin") {
            guard let session = activeSession(for: userId) else {
                throw EngineError.conflict("no_session", "Start a session on the wearer's iPhone first.")
            }
            if awaitingCheckIn(for: session.id) != nil {
                throw EngineError.conflict("checkin_pending", "A check-in is already waiting for a response.")
            }
            let window = min(max(request.responseWindowSeconds ?? user.timing.responseWindowSeconds, 5), 600)
            let checkIn = scheduleCheckIn(session: session, kind: .demo, promptAt: now(), window: window)
            log(userId, session: session.id, actor: .admin, type: "demo.checkin",
                text: "Demo: simulated concerning event. Check-in started by \(adminName(adminId)); respond by \(timeText(checkIn.respondBy)).",
                wearer: true, responders: false, simulated: true)
            bump(userId)
            return buildAdminView(db.users[userId] ?? user)
        }
    }

    public func triggerHelp(adminId: String, userId: String, key: String?) throws -> AdminView {
        let user = try requireAssignment(adminId, userId)
        return try once(key, scope: "\(adminId):help") {
            let session = activeSession(for: userId) ?? openAdHocSession(for: user)
            if let incident = openIncident(for: userId) {
                attachTrigger(.simulatedHelp, to: incident.id)
            } else {
                openNewIncident(userId: userId, sessionId: session.id, trigger: .simulatedHelp, concealed: false, simulated: true)
            }
            log(userId, session: session.id, incident: openIncident(for: userId)?.id, actor: .admin, type: "demo.help",
                text: "Demo: simulated help request from \(adminName(adminId)).", wearer: true, responders: true, simulated: true)
            bump(userId)
            return buildAdminView(db.users[userId] ?? user)
        }
    }

    public func stopIncident(adminId: String, userId: String, _ request: StopRequest, key: String?) throws -> AdminView {
        let user = try requireAssignment(adminId, userId)
        return try once(key, scope: "\(adminId):stop") {
            let reason = request.reason.trimmed
            guard !reason.isEmpty else { throw EngineError.invalid("Give a reason for stopping the alert.") }
            guard let incident = openIncident(for: userId) else {
                throw EngineError.conflict("no_incident", "There's no open alert to stop.")
            }
            resolveIncident(incident.id, reason: .operatorStop, note: String(reason.prefix(160)), by: adminName(adminId), actor: .admin)
            return buildAdminView(db.users[userId] ?? user)
        }
    }

    /// Starts a new demo run. Old timers, invitations, links and delayed
    /// responses can't affect the next run. Use Stop first if responders
    /// should get an update; reset itself sends nothing.
    public func resetRun(adminId: String, userId: String, key: String?) throws -> ResetResponse {
        _ = try requireAssignment(adminId, userId)
        return try once(key, scope: "\(adminId):reset") {
            let t = now()
            if let incident = openIncident(for: userId) {
                resolveIncident(incident.id, reason: .operatorStop, note: "Demo reset", by: adminName(adminId), actor: .admin,
                                sendUpdateMessages: false)
            }
            for session in db.sessions.values where session.userId == userId && session.monitoring == .active {
                endMonitoring(session.id, note: "Demo reset")
            }
            for coverage in db.coverages.values where coverage.userId == userId && [CoverageState.invited, .verified, .accepted].contains(coverage.state) {
                db.coverages[coverage.id]?.state = .revoked
                db.coverages[coverage.id]?.endedAt = t
            }
            for (hash, token) in db.tokens where token.userId == userId && token.revokedAt == nil {
                db.tokens[hash]?.revokedAt = t
            }
            for (id, delivery) in db.deliveries where delivery.userId == userId && delivery.state == .queued {
                db.deliveries[id]?.state = .cancelled
            }
            cancelJobs(note: "Demo reset") { $0.userId == userId }
            let newRun = newId()
            db.users[userId]?.demoRunId = newRun
            log(userId, actor: .admin, type: "demo.reset", text: "Demo reset by \(adminName(adminId)). New run started.",
                wearer: true, responders: false, simulated: true)
            bump(userId)
            return ResetResponse(demoRunId: newRun, message: "Demo reset. Start a new session on the wearer's iPhone.")
        }
    }
}
