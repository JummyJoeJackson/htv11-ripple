import Foundation
import KazeKit

// Wearer operations: setup, configuration, sessions, check-ins, Help and PINs.

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
        guard !name.isEmpty else { throw EngineError.invalid("Enter the name you'd like responders to see.") }
        let token = Secrets.randomToken()
        let user = UserRecord(
            id: newId(),
            displayName: String(name.prefix(60)),
            phone: "",
            pairingCode: uniquePairingCode(),
            helpCard: "",
            timing: .demo,
            contactIds: [],
            pinSalt: Secrets.randomToken(bytes: 16),
            safetyPinHash: nil,
            duressPinHash: nil,
            demoRunId: newId(),
            revision: 1,
            createdAt: now()
        )
        db.users[user.id] = user
        db.deviceTokens[Secrets.hash(token)] = user.id
        log(user.id, actor: .wearer, type: "wearer.setup", text: "KAZE was set up on this iPhone.", wearer: true, responders: false)
        persistIfDirty()
        return SetupResponse(userId: user.id, deviceToken: token, pairingCode: user.pairingCode)
    }

    func uniquePairingCode() -> String {
        while true {
            let code = Secrets.randomDigits(6)
            if !db.users.values.contains(where: { $0.pairingCode == code }) { return code }
        }
    }

    public func updateConfig(userId: String, _ request: ConfigRequest) throws -> WearerState {
        var user = try requireUser(userId)
        let name = request.displayName.trimmed
        guard !name.isEmpty else { throw EngineError.invalid("Enter the name you'd like responders to see.") }
        var phone = ""
        if !request.phone.trimmed.isEmpty {
            guard let normalized = Phone.normalize(request.phone) else {
                throw EngineError.invalid("Enter your phone number with its area code, for example 416 555 0123.")
            }
            phone = normalized
        }
        let t = request.timing
        guard (0...3600).contains(t.graceSeconds),
              (5...3600).contains(t.responseWindowSeconds),
              (5...3600).contains(t.ackWindowSeconds),
              (5...7200).contains(t.followUpWindowSeconds),
              t.connectionGraceSeconds == 0 || (10...7200).contains(t.connectionGraceSeconds),
              (0...3).contains(t.maxRetries)
        else { throw EngineError.invalid("One of the timings is out of range.") }

        user.displayName = String(name.prefix(60))
        user.phone = phone
        user.helpCard = String(request.helpCard.trimmed.prefix(500))
        user.timing = t
        db.users[userId] = user
        bump(userId)
        log(userId, actor: .wearer, type: "wearer.config", text: "Settings saved.", wearer: true, responders: false)
        persistIfDirty()
        return try wearerState(userId: userId)
    }

    public func replaceContacts(userId: String, _ request: ContactsRequest) throws -> WearerState {
        var user = try requireUser(userId)
        guard request.contacts.count <= 6 else { throw EngineError.invalid("Add up to six trusted contacts.") }
        var newIds: [String] = []
        for input in request.contacts {
            let name = input.name.trimmed
            guard !name.isEmpty else { throw EngineError.invalid("Every trusted contact needs a name.") }
            guard let phone = Phone.normalize(input.phone) else {
                throw EngineError.invalid("\(name)'s phone number doesn't look right. Include the area code.")
            }
            let id: String
            if let existing = input.id, db.contacts[existing]?.userId == userId {
                id = existing
            } else {
                id = newId()
            }
            db.contacts[id] = ContactRecord(id: id, userId: userId, name: String(name.prefix(60)), phone: phone, share: input.share)
            newIds.append(id)
        }
        for oldId in user.contactIds where !newIds.contains(oldId) {
            db.contacts[oldId] = nil
        }
        user.contactIds = newIds
        db.users[userId] = user
        bump(userId)
        log(userId, actor: .wearer, type: "wearer.contacts", text: "Trusted contacts updated (\(newIds.count)).", wearer: true, responders: false)
        persistIfDirty()
        return try wearerState(userId: userId)
    }

    public func setPins(userId: String, _ request: PinsRequest) throws -> WearerState {
        var user = try requireUser(userId)
        let safety = request.safetyPin.trimmed
        let duress = request.duressPin.trimmed
        guard isValidPin(safety), isValidPin(duress) else {
            throw EngineError.invalid("PINs must be 4 to 8 digits.")
        }
        guard safety != duress else {
            throw EngineError.invalid("The duress PIN must be different from the safety PIN.")
        }
        user.safetyPinHash = Secrets.hashPin(safety, salt: user.pinSalt)
        user.duressPinHash = Secrets.hashPin(duress, salt: user.pinSalt)
        db.users[userId] = user
        bump(userId)
        log(userId, actor: .wearer, type: "wearer.pins", text: "Safety and duress PINs set.", wearer: true, responders: false)
        persistIfDirty()
        return try wearerState(userId: userId)
    }

    func isValidPin(_ pin: String) -> Bool {
        (4...8).contains(pin.count) && pin.allSatisfy { $0.isNumber }
    }

    // MARK: Sessions

    public func startSession(userId: String, _ request: StartSessionRequest, key: String?) throws -> WearerState {
        try once(key, scope: "\(userId):start") {
            let user = try requireUser(userId)
            if activeSession(for: userId) != nil {
                throw EngineError.conflict("session_active", "A session is already running.")
            }
            guard !user.contactIds.isEmpty else {
                throw EngineError.invalid("Add at least one trusted contact before starting a session.")
            }
            guard (30...86_400).contains(request.durationSeconds) else {
                throw EngineError.invalid("Choose a duration between 30 seconds and 24 hours.")
            }
            let t = now()
            let session = SessionRecord(
                id: newId(),
                userId: userId,
                demoRunId: user.demoRunId,
                monitoring: .active,
                venue: String(request.venue.trimmed.prefix(120)),
                startedAt: t,
                expectedEndAt: t.addingTimeInterval(TimeInterval(request.durationSeconds)),
                endedAt: nil,
                lastHeartbeatAt: t,
                watchReachable: false,
                lastWatchContactAt: nil,
                lastLocation: nil,
                lastSafetyConfirmationAt: nil,
                connectionLost: false
            )
            db.sessions[session.id] = session
            let checkIn = scheduleCheckIn(
                session: session,
                kind: .planned,
                promptAt: session.expectedEndAt!.addingTimeInterval(TimeInterval(user.timing.graceSeconds)),
                window: user.timing.responseWindowSeconds
            )
            let place = session.venue.isEmpty ? "" : " at \(session.venue)"
            log(userId, session: session.id, actor: .wearer, type: "session.started",
                text: "Session started\(place). Check-in at \(timeText(checkIn.promptAt)).", wearer: true, responders: false)
            bump(userId)
            return try wearerState(userId: userId)
        }
    }

    @discardableResult
    func scheduleCheckIn(session: SessionRecord, kind: CheckInKind, promptAt: Date, window: Int) -> CheckInRecord {
        let t = now()
        let respondBy = max(promptAt, t).addingTimeInterval(TimeInterval(window))
        let checkIn = CheckInRecord(
            id: newId(),
            sessionId: session.id,
            userId: session.userId,
            demoRunId: session.demoRunId,
            kind: kind,
            state: promptAt <= t ? .awaitingResponse : .scheduled,
            promptAt: max(promptAt, t),
            respondBy: respondBy,
            respondedAt: nil,
            source: nil
        )
        db.checkIns[checkIn.id] = checkIn
        if checkIn.state == .scheduled {
            schedule(.checkInPrompt, target: checkIn.id, userId: session.userId, at: checkIn.promptAt, key: "prompt:\(checkIn.id)")
        }
        schedule(.checkInExpire, target: checkIn.id, userId: session.userId, at: checkIn.respondBy, key: "expire:\(checkIn.id)")
        dirty = true
        return checkIn
    }

    func cancelCheckIn(_ id: String, note: String) {
        guard let checkIn = db.checkIns[id], checkIn.state == .scheduled || checkIn.state == .awaitingResponse else { return }
        db.checkIns[id]?.state = .cancelled
        cancelJobs(note: note) { $0.targetId == id }
        dirty = true
    }

    public func extendSession(userId: String, _ request: ExtendSessionRequest, key: String?) throws -> WearerState {
        try once(key, scope: "\(userId):extend") {
            let user = try requireUser(userId)
            guard var session = activeSession(for: userId) else {
                throw EngineError.conflict("no_session", "There's no active session to extend.")
            }
            if awaitingCheckIn(for: session.id) != nil {
                throw EngineError.conflict("checkin_pending", "Answer the check-in first, then extend.")
            }
            guard (30...86_400).contains(request.additionalSeconds) else {
                throw EngineError.invalid("Choose an extension between 30 seconds and 24 hours.")
            }
            for checkIn in checkIns(for: session.id) where checkIn.kind == .planned && checkIn.state == .scheduled {
                cancelCheckIn(checkIn.id, note: "Replaced by an extension")
            }
            let base = max(now(), session.expectedEndAt ?? now())
            session.expectedEndAt = base.addingTimeInterval(TimeInterval(request.additionalSeconds))
            db.sessions[session.id] = session
            let checkIn = scheduleCheckIn(
                session: session,
                kind: .planned,
                promptAt: session.expectedEndAt!.addingTimeInterval(TimeInterval(user.timing.graceSeconds)),
                window: user.timing.responseWindowSeconds
            )
            log(userId, session: session.id, actor: .wearer, type: "session.extended",
                text: "Session extended. Next check-in at \(timeText(checkIn.promptAt)).", wearer: true, responders: false)
            bump(userId)
            return try wearerState(userId: userId)
        }
    }

    public func endSession(userId: String, key: String?) throws -> WearerState {
        try once(key, scope: "\(userId):end") {
            _ = try requireUser(userId)
            guard let session = activeSession(for: userId) else {
                return try wearerState(userId: userId)
            }
            endMonitoring(session.id, note: "Session ended by the wearer")
            let text = openIncident(for: userId) == nil
                ? "Session ended."
                : "Session ended. The open alert stays open until it's resolved."
            log(userId, session: session.id, actor: .wearer, type: "session.ended", text: text, wearer: true, responders: false)
            bump(userId)
            return try wearerState(userId: userId)
        }
    }

    /// Stops future check-ins. Never closes an open incident.
    func endMonitoring(_ sessionId: String, note: String) {
        guard db.sessions[sessionId]?.monitoring == .active else { return }
        db.sessions[sessionId]?.monitoring = .ended
        db.sessions[sessionId]?.endedAt = now()
        for checkIn in checkIns(for: sessionId) {
            cancelCheckIn(checkIn.id, note: note)
        }
        dirty = true
    }

    public func heartbeat(userId: String, _ request: HeartbeatRequest) throws -> HeartbeatResponse {
        let user = try requireUser(userId)
        let t = now()
        if var session = activeSession(for: userId) {
            session.lastHeartbeatAt = t
            session.watchReachable = request.watchReachable
            if let contact = request.lastWatchContactAt {
                let clamped = min(contact, t)
                if session.lastWatchContactAt == nil || clamped > session.lastWatchContactAt! {
                    session.lastWatchContactAt = clamped
                }
            }
            if let fix = request.location {
                session.lastLocation = fix
            }
            if session.connectionLost && !isConnectionStale(session, user: user, at: t) {
                session.connectionLost = false
                log(userId, session: session.id, incident: openIncident(for: userId)?.id, actor: .system, type: "connection.restored",
                    text: "Connection with the wearer's devices is back.", wearer: true, responders: true)
                bump(userId)
            }
            db.sessions[session.id] = session
            dirty = true
        }
        persistIfDirty()
        return HeartbeatResponse(serverTime: t, revision: db.users[userId]?.revision ?? 0)
    }

    func isConnectionStale(_ session: SessionRecord, user: UserRecord, at t: Date) -> Bool {
        let grace = TimeInterval(user.timing.connectionGraceSeconds)
        guard grace > 0 else { return false }
        if t.timeIntervalSince(session.lastHeartbeatAt) > grace { return true }
        // Watch loss only counts once the watch has been seen in this session.
        if let watch = session.lastWatchContactAt, t.timeIntervalSince(watch) > grace { return true }
        return false
    }

    // MARK: Check-in responses

    public func confirm(userId: String, _ request: ConfirmRequest, key: String?) throws -> ConfirmResponse {
        try once(key, scope: "\(userId):confirm") {
            let user = try requireUser(userId)
            let t = now()
            var target: CheckInRecord?
            if let id = request.checkInId {
                guard let checkIn = db.checkIns[id], checkIn.userId == userId else {
                    throw EngineError.notFound("That check-in doesn't exist.")
                }
                guard checkIn.demoRunId == user.demoRunId else { throw EngineError.staleRun }
                target = checkIn
            } else if let session = activeSession(for: userId) {
                target = awaitingCheckIn(for: session.id)
            }

            if let checkIn = target {
                switch checkIn.state {
                case .confirmed:
                    return ConfirmResponse(outcome: .alreadyConfirmed, message: "You're already checked in.")
                case .awaitingResponse:
                    // The backend's receive time decides the race against the deadline.
                    if t <= checkIn.respondBy {
                        confirmCheckIn(checkIn.id, source: request.source)
                        bump(userId)
                        return ConfirmResponse(outcome: .confirmed, message: "Thanks, you're checked in.")
                    }
                    expireCheckIn(checkIn.id)
                    return safetyTap(userId: userId, source: request.source)
                case .expired:
                    return safetyTap(userId: userId, source: request.source)
                case .scheduled, .cancelled:
                    return safetyTap(userId: userId, source: request.source)
                }
            }
            return safetyTap(userId: userId, source: request.source)
        }
    }

    func confirmCheckIn(_ id: String, source: ResponseSource) {
        guard var checkIn = db.checkIns[id] else { return }
        let t = now()
        checkIn.state = .confirmed
        checkIn.respondedAt = t
        checkIn.source = source
        db.checkIns[id] = checkIn
        cancelJobs(note: "Check-in answered") { $0.targetId == id }
        db.sessions[checkIn.sessionId]?.lastSafetyConfirmationAt = t
        let via = source == .watch ? "watch" : "iPhone"
        log(checkIn.userId, session: checkIn.sessionId, actor: .wearer, type: "checkin.confirmed",
            text: "Check-in answered on the \(via): I'm okay.", wearer: true, responders: false)
        if checkIn.kind == .planned {
            // A successful final check-in ends the activity session (PRD §4.3).
            endMonitoring(checkIn.sessionId, note: "Final check-in confirmed")
            log(checkIn.userId, session: checkIn.sessionId, actor: .system, type: "session.completed",
                text: "Final check-in confirmed. Session complete.", wearer: true, responders: false)
        }
        dirty = true
    }

    /// "I'm okay" outside an answerable check-in. Updates the last confirmation
    /// time but never moves a registered deadline. During an open alert it is a
    /// late safety report.
    func safetyTap(userId: String, source: ResponseSource) -> ConfirmResponse {
        let t = now()
        if let session = activeSession(for: userId) ?? latestSession(for: userId) {
            db.sessions[session.id]?.lastSafetyConfirmationAt = t
        }
        if let incident = openIncident(for: userId), !incident.concealed {
            applySafetyReport(incident.id)
            bump(userId)
            return ConfirmResponse(outcome: .lateReport, message: "Your responders were told you're okay.")
        }
        if let incident = openIncident(for: userId), incident.concealed {
            log(userId, incident: incident.id, actor: .wearer, type: "incident.tap_after_duress",
                text: "The wearer tapped I'm okay after a silent alert. Treat this with caution.", wearer: false, responders: true)
        }
        log(userId, actor: .wearer, type: "safety.tap", text: "Safety tap recorded.", wearer: true, responders: false)
        bump(userId)
        return ConfirmResponse(outcome: .recorded, message: "Safety tap recorded.")
    }

    // MARK: Help and PINs

    public func help(userId: String, _ request: HelpRequest, key: String?) throws -> MessageResponse {
        try once(key, scope: "\(userId):help") {
            let user = try requireUser(userId)
            let session = activeSession(for: userId) ?? openAdHocSession(for: user)
            if var incident = openIncident(for: userId) {
                if incident.concealed {
                    // The wearer is asking for help openly now.
                    incident.concealed = false
                    db.incidents[incident.id] = incident
                }
                attachTrigger(.help, to: incident.id)
            } else {
                openNewIncident(userId: userId, sessionId: session.id, trigger: .help, concealed: false, simulated: false)
            }
            let via = request.source == .watch ? "watch" : "iPhone"
            log(userId, session: session.id, incident: openIncident(for: userId)?.id, actor: .wearer, type: "help.requested",
                text: "Get help pressed on the \(via).", wearer: true, responders: true)
            bump(userId)
            return MessageResponse(message: "Help requested. Contacting your responders.")
        }
    }

    /// Help can always be requested. Without a running session, one is opened
    /// with no deadline to hold the alert.
    func openAdHocSession(for user: UserRecord) -> SessionRecord {
        let t = now()
        let session = SessionRecord(
            id: newId(),
            userId: user.id,
            demoRunId: user.demoRunId,
            monitoring: .active,
            venue: "",
            startedAt: t,
            expectedEndAt: nil,
            endedAt: nil,
            lastHeartbeatAt: t,
            watchReachable: false,
            lastWatchContactAt: nil,
            lastLocation: latestSession(for: user.id)?.lastLocation,
            lastSafetyConfirmationAt: nil,
            connectionLost: false
        )
        db.sessions[session.id] = session
        dirty = true
        return session
    }

    /// The safety PIN and the duress PIN produce exactly the same response and
    /// the same wearer-visible result. Only the backend knows the difference.
    public func cancel(userId: String, _ request: CancelRequest, key: String?) throws -> MessageResponse {
        try once(key, scope: "\(userId):cancel") {
            let user = try requireUser(userId)
            guard let safetyHash = user.safetyPinHash, let duressHash = user.duressPinHash else {
                throw EngineError.invalid("Set your safety and duress PINs in Settings first.")
            }
            let entered = Secrets.hashPin(request.pin.trimmed, salt: user.pinSalt)
            guard entered == safetyHash || entered == duressHash else {
                throw EngineError.forbidden("That PIN wasn't recognized. Nothing was cancelled.")
            }
            let isDuress = entered == duressHash
            let session = activeSession(for: userId)
            let awaiting = session.flatMap { awaitingCheckIn(for: $0.id) }

            if let checkIn = awaiting {
                confirmCheckIn(checkIn.id, source: .phone)
            }
            if isDuress {
                if var incident = openIncident(for: userId) {
                    incident.concealed = true
                    db.incidents[incident.id] = incident
                    attachTrigger(.duress, to: incident.id)
                } else {
                    let sessionId = session?.id ?? latestSession(for: userId)?.id
                    openNewIncident(userId: userId, sessionId: sessionId, trigger: .duress, concealed: true, simulated: false)
                }
            } else if let incident = openIncident(for: userId) {
                resolveIncident(incident.id, reason: .safetyPinCancel, note: nil, by: user.displayName, actor: .wearer)
            }
            log(userId, actor: .wearer, type: "pin.accepted", text: "PIN accepted. Alert cancelled.", wearer: true, responders: false)
            bump(userId)
            return MessageResponse(message: "Cancelled.")
        }
    }
}
