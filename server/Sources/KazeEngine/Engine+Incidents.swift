import Foundation
import KazeKit

// Incident lifecycle and escalation (PRD §4, steps 4–9).

extension Engine {
    /// Opens a new incident, builds its routing order, and alerts the first responder.
    @discardableResult
    func openNewIncident(userId: String, sessionId: String?, trigger: IncidentTrigger, concealed: Bool, simulated: Bool) -> String {
        guard let user = db.users[userId] else { return "" }
        let t = now()
        let incidentId = newId()
        var stepIds: [String] = []
        var position = 0

        // Route: an accepted temporary helper first while coverage is valid,
        // then trusted contacts in their configured order.
        if let coverage = activeCoverage(for: userId) {
            let step = StepRecord(
                id: newId(), incidentId: incidentId, position: position, recipientKind: .helper,
                contactId: nil, coverageId: coverage.id, name: coverage.helperName, phone: coverage.helperPhone,
                share: coverage.share, state: .pending, attempts: 0, notifiedAt: nil, ackDeadline: nil,
                actedAt: nil, firstOpenedAt: nil, tokenHash: nil, alertBody: nil
            )
            db.steps[step.id] = step
            stepIds.append(step.id)
            position += 1
        }
        for contactId in user.contactIds {
            guard let contact = db.contacts[contactId] else { continue }
            let step = StepRecord(
                id: newId(), incidentId: incidentId, position: position, recipientKind: .contact,
                contactId: contact.id, coverageId: nil, name: contact.name, phone: contact.phone,
                share: contact.share, state: .pending, attempts: 0, notifiedAt: nil, ackDeadline: nil,
                actedAt: nil, firstOpenedAt: nil, tokenHash: nil, alertBody: nil
            )
            db.steps[step.id] = step
            stepIds.append(step.id)
            position += 1
        }

        let incident = IncidentRecord(
            id: incidentId, userId: userId, sessionId: sessionId, demoRunId: user.demoRunId,
            status: .open, triggers: [trigger], concealed: concealed, simulated: simulated, openedAt: t,
            stepIds: stepIds, progress: .unassigned, currentStepId: nil, acknowledgedAt: nil,
            progressVersion: 0, wearerSafetyReportAt: nil, escalationPaused: false,
            noResponderConfirmed: false, resolvedAt: nil, resolution: nil, resolutionNote: nil, resolvedBy: nil
        )
        db.incidents[incidentId] = incident
        let order = stepIds.compactMap { db.steps[$0]?.name }.joined(separator: " → ")
        log(userId, session: sessionId, incident: incidentId, actor: .system, type: "incident.opened",
            text: "Alert opened: \(trigger.label). Routing: \(order.isEmpty ? "nobody to contact" : order).",
            wearer: !concealed, responders: true, simulated: simulated)
        advance(incidentId)
        bump(userId)
        return incidentId
    }

    /// A new trigger while an incident is open joins that incident instead of
    /// creating a duplicate.
    func attachTrigger(_ trigger: IncidentTrigger, to incidentId: String) {
        guard var incident = db.incidents[incidentId], incident.status == .open else { return }
        if !incident.triggers.contains(trigger) {
            incident.triggers.append(trigger)
        }
        db.incidents[incidentId] = incident
        log(incident.userId, session: incident.sessionId, incident: incidentId, actor: .system, type: "incident.trigger",
            text: "Also: \(trigger.label).", wearer: !incident.concealed && trigger != .duress, responders: true,
            simulated: trigger == .simulatedHelp)
        if incident.escalationPaused {
            resumeEscalation(incidentId)
        } else {
            advance(incidentId)
        }
        bump(incident.userId)
    }

    /// Alerts the next eligible responder, if escalation should continue.
    /// `force` is used by the follow-up deadline to add a responder even though
    /// someone already acknowledged.
    func advance(_ incidentId: String, force: Bool = false) {
        guard var incident = db.incidents[incidentId], incident.status == .open, !incident.escalationPaused else { return }
        if incident.currentStepId != nil && !force { return }
        // Only one alert in flight at a time.
        let inFlight = incident.stepIds.contains { id in
            guard let step = db.steps[id] else { return false }
            return step.state == .notifying || (step.state == .notified && (step.ackDeadline ?? .distantPast) > now())
        }
        if inFlight && !force { return }

        for stepId in incident.stepIds {
            guard var step = db.steps[stepId], step.state == .pending else { continue }
            if !isEligible(step) {
                step.state = .skipped
                db.steps[stepId] = step
                log(incident.userId, incident: incidentId, actor: .system, type: "step.skipped",
                    text: "Skipped \(step.name): helper coverage is no longer active.", wearer: !incident.concealed, responders: true)
                continue
            }
            step.state = .notifying
            db.steps[stepId] = step
            queueAlert(stepId: stepId)
            if incident.noResponderConfirmed {
                incident.noResponderConfirmed = false
                db.incidents[incidentId] = incident
            }
            dirty = true
            return
        }

        let someoneAcknowledged = incident.stepIds.contains { db.steps[$0]?.state == .acknowledged }
        if !inFlight && !someoneAcknowledged && !incident.noResponderConfirmed {
            incident.noResponderConfirmed = true
            db.incidents[incidentId] = incident
            log(incident.userId, incident: incidentId, actor: .system, type: "incident.no_responder",
                text: "No responder confirmed. The alert stays open.", wearer: !incident.concealed, responders: true)
            bump(incident.userId)
        }
    }

    func isEligible(_ step: StepRecord) -> Bool {
        if step.recipientKind == .helper {
            guard let coverageId = step.coverageId, let coverage = db.coverages[coverageId] else { return false }
            return isActive(coverage)
        }
        return true
    }

    func queueAlert(stepId: String) {
        guard var step = db.steps[stepId], let incident = db.incidents[step.incidentId], let user = db.users[incident.userId] else { return }
        if step.tokenHash == nil {
            let raw = Secrets.randomToken()
            let hash = Secrets.hash(raw)
            db.tokens[hash] = TokenRecord(
                purpose: .respond, userId: user.id, demoRunId: user.demoRunId, coverageId: step.coverageId,
                incidentId: incident.id, stepId: step.id, expiresAt: now().addingTimeInterval(24 * 3600), revokedAt: nil
            )
            step.tokenHash = hash
            step.alertBody = alertText(incident: incident, step: step, user: user, link: link("/r/\(raw)"))
        }
        step.attempts += 1
        db.steps[stepId] = step
        let delivery = DeliveryRecord(
            id: newId(), userId: user.id, incidentId: incident.id, stepId: step.id, coverageId: step.coverageId,
            purpose: .alert, to: step.phone, body: step.alertBody ?? "", state: .queued, attemptNo: step.attempts,
            providerMessageId: nil, providerStatus: nil, error: nil, createdAt: now(), updatedAt: now()
        )
        db.deliveries[delivery.id] = delivery
        schedule(.deliverySend, target: delivery.id, userId: user.id, at: now(), key: "send:\(delivery.id)")
        dirty = true
    }

    func alertText(incident: IncidentRecord, step: StepRecord, user: UserRecord, link: String) -> String {
        let who: String
        if step.share.name {
            who = user.displayName
        } else if step.recipientKind == .helper {
            who = "Someone you're covering"
        } else {
            who = "Someone who listed you as a trusted contact"
        }
        let demo = incident.simulated ? "[DEMO] " : ""
        if incident.triggers.contains(.duress) {
            return "\(demo)KAZE silent alert: \(who) may need help but can't say so. Don't call or text them about this alert. Open: \(link)"
        }
        let reason: String
        switch incident.triggers.first ?? .help {
        case .missedCheckIn: reason = "missed a safety check-in"
        case .help: reason = "pressed Get help"
        case .duress: reason = "may need help"
        case .connectionLost: reason = "lost contact with KAZE"
        case .simulatedHelp: reason = "sent a simulated help request"
        }
        return "\(demo)KAZE alert: \(who) \(reason). Please respond: \(link)"
    }

    // MARK: Check-in deadline

    /// The registered deadline passed without an accepted response.
    func expireCheckIn(_ id: String) {
        guard var checkIn = db.checkIns[id], checkIn.state == .awaitingResponse || checkIn.state == .scheduled else { return }
        checkIn.state = .expired
        db.checkIns[id] = checkIn
        cancelJobs(note: "Check-in expired") { $0.targetId == id }
        log(checkIn.userId, session: checkIn.sessionId, actor: .system, type: "checkin.expired",
            text: "Check-in missed: no response by \(timeText(checkIn.respondBy)).", wearer: true, responders: true,
            simulated: checkIn.kind == .demo)
        if let incident = openIncident(for: checkIn.userId) {
            attachTrigger(.missedCheckIn, to: incident.id)
        } else {
            openNewIncident(userId: checkIn.userId, sessionId: checkIn.sessionId, trigger: .missedCheckIn,
                            concealed: false, simulated: checkIn.kind == .demo)
        }
        bump(checkIn.userId)
    }

    // MARK: Late safety report

    /// A late "I'm okay": record it, suppress unsent escalation, tell everyone
    /// already contacted. The incident stays open (PRD §4.8).
    func applySafetyReport(_ incidentId: String) {
        guard var incident = db.incidents[incidentId], incident.status == .open, !incident.concealed else { return }
        let t = now()
        incident.wearerSafetyReportAt = t
        incident.escalationPaused = true
        db.incidents[incidentId] = incident
        stopPendingEscalation(incidentId, note: "Suppressed after the wearer reported they're okay")
        log(incident.userId, incident: incidentId, actor: .wearer, type: "incident.safety_report",
            text: "The wearer reported they're okay at \(timeText(t)). The alert stays open until a responder resolves it or the wearer cancels with their safety PIN.",
            wearer: true, responders: true)
        sendUpdates(incidentId) { step, user in
            let who = step.share.name ? user.displayName : "The person you were alerted about"
            return "KAZE update: \(who) reported they're okay (\(self.timeText(t))). The alert is still open on your link."
        }
        bump(incident.userId)
    }

    /// Cancels queued alert messages and pending deadlines for an incident.
    /// Steps whose message hadn't gone out yet go back to pending.
    func stopPendingEscalation(_ incidentId: String, note: String) {
        guard let incident = db.incidents[incidentId] else { return }
        let stepIds = Set(incident.stepIds)
        for (id, delivery) in db.deliveries where delivery.purpose == .alert && delivery.state == .queued {
            guard let stepId = delivery.stepId, stepIds.contains(stepId) else { continue }
            db.deliveries[id]?.state = .cancelled
            db.deliveries[id]?.updatedAt = now()
            cancelJobs(note: note) { $0.targetId == id }
            if db.steps[stepId]?.state == .notifying {
                db.steps[stepId]?.state = .pending
            }
        }
        cancelJobs(note: note) { job in
            (job.kind == .ackTimeout && stepIds.contains(job.targetId)) || (job.kind == .followUp && job.targetId == incidentId)
        }
        dirty = true
    }

    func resumeEscalation(_ incidentId: String) {
        guard var incident = db.incidents[incidentId], incident.status == .open else { return }
        incident.escalationPaused = false
        db.incidents[incidentId] = incident
        let t = now()
        for stepId in incident.stepIds {
            guard let step = db.steps[stepId] else { continue }
            if step.state == .notified, let deadline = step.ackDeadline {
                if deadline <= t {
                    db.steps[stepId]?.state = .timedOut
                } else {
                    schedule(.ackTimeout, target: stepId, userId: incident.userId, at: deadline, key: "ack:\(stepId):resume:\(Int(t.timeIntervalSince1970))")
                }
            }
        }
        log(incident.userId, incident: incidentId, actor: .system, type: "incident.resumed",
            text: "Escalation resumed.", wearer: !incident.concealed, responders: true)
        advance(incidentId)
        dirty = true
    }

    // MARK: Resolution

    func resolveIncident(_ incidentId: String, reason: ResolutionReason, note: String?, by name: String, actor: ActorType,
                         exceptStepId: String? = nil, sendUpdateMessages: Bool = true) {
        guard var incident = db.incidents[incidentId], incident.status == .open else { return }
        let t = now()
        incident.status = .resolved
        incident.resolvedAt = t
        incident.resolution = reason
        incident.resolutionNote = note
        incident.resolvedBy = name
        if reason == .responderResolved {
            incident.progress = .resolved
        }
        db.incidents[incidentId] = incident

        stopPendingEscalation(incidentId, note: "Incident resolved")
        for stepId in incident.stepIds {
            guard let step = db.steps[stepId] else { continue }
            if step.state == .pending || step.state == .notifying {
                db.steps[stepId]?.state = .skipped
            }
            // Responders keep a short read-only view of the outcome.
            if let hash = step.tokenHash, let token = db.tokens[hash] {
                db.tokens[hash]?.expiresAt = min(token.expiresAt, t.addingTimeInterval(30 * 60))
            }
        }

        let text: String
        switch reason {
        case .responderResolved:
            text = "\(name) marked the alert resolved: \(note ?? "")"
        case .safetyPinCancel:
            text = "The wearer cancelled the alert with their safety PIN."
        case .operatorStop:
            text = "The demo operator stopped this alert (\(note ?? "no reason given")). This does not confirm the person is safe."
        }
        log(incident.userId, incident: incidentId, actor: actor, type: "incident.resolved", text: text,
            wearer: !incident.concealed, responders: true, simulated: incident.simulated)

        if sendUpdateMessages {
            sendUpdates(incidentId, except: exceptStepId) { step, user in
                let who = step.share.name ? user.displayName : "the person you were alerted about"
                switch reason {
                case .responderResolved:
                    return "KAZE update: \(name) resolved the alert for \(who): \(note ?? "")."
                case .safetyPinCancel:
                    return "KAZE update: \(who) cancelled the alert with their safety PIN."
                case .operatorStop:
                    return "KAZE update: the demo operator stopped this alert. This does not confirm \(who) is safe."
                }
            }
        }
        bump(incident.userId)
    }

    /// Texts everyone already contacted for this incident. Messages already
    /// sent can't be recalled, so updates are the only correction.
    func sendUpdates(_ incidentId: String, except exceptStepId: String? = nil, _ text: (StepRecord, UserRecord) -> String) {
        guard let incident = db.incidents[incidentId], let user = db.users[incident.userId] else { return }
        for stepId in incident.stepIds where stepId != exceptStepId {
            guard let step = db.steps[stepId], step.notifiedAt != nil else { continue }
            if step.recipientKind == .helper {
                guard let coverageId = step.coverageId, let coverage = db.coverages[coverageId], isActive(coverage) else { continue }
            }
            queueMessage(userId: user.id, purpose: .update, to: step.phone, body: text(step, user), incidentId: incidentId, stepId: stepId)
        }
    }

    func queueMessage(userId: String, purpose: DeliveryPurpose, to: String, body: String,
                      incidentId: String? = nil, stepId: String? = nil, coverageId: String? = nil) {
        let delivery = DeliveryRecord(
            id: newId(), userId: userId, incidentId: incidentId, stepId: stepId, coverageId: coverageId,
            purpose: purpose, to: to, body: body, state: .queued, attemptNo: 1, providerMessageId: nil,
            providerStatus: nil, error: nil, createdAt: now(), updatedAt: now()
        )
        db.deliveries[delivery.id] = delivery
        schedule(.deliverySend, target: delivery.id, userId: userId, at: now(), key: "send:\(delivery.id)")
        dirty = true
    }
}
