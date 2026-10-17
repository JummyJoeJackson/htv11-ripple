import Foundation
import KazeKit

// The responder page behind each alert link. Access is checked on every
// request, so revocation also stops a page that is already open.

extension Engine {
    func responderAccess(_ raw: String) throws -> (StepRecord, IncidentRecord, UserRecord) {
        guard let token = db.tokens[Secrets.hash(raw)], token.purpose == .respond,
              let stepId = token.stepId, let step = db.steps[stepId],
              let incident = db.incidents[step.incidentId], let user = db.users[token.userId]
        else { throw EngineError.notFound("This alert link isn't valid.") }
        let ended = EngineError.gone("Your access to this alert has ended. Information you already saw can't be recalled, but nothing more will be shown.")
        guard token.revokedAt == nil, token.expiresAt > now(), token.demoRunId == user.demoRunId else { throw ended }
        if step.recipientKind == .helper {
            guard let coverageId = step.coverageId, let coverage = db.coverages[coverageId], isActive(coverage) else { throw ended }
        }
        return (step, incident, user)
    }

    public func responderView(token raw: String) throws -> ResponderView {
        let (step, incident, user) = try responderAccess(raw)
        if step.firstOpenedAt == nil {
            // Observed receipt: the page's script called the API, so a person
            // (not just a link preview) has the alert open.
            db.steps[step.id]?.firstOpenedAt = now()
            log(user.id, incident: incident.id, actor: .responder, type: "step.opened",
                text: "\(step.name) opened the alert.", wearer: !incident.concealed, responders: true)
            bump(user.id)
            persistIfDirty()
        }
        return buildResponderView(step: db.steps[step.id] ?? step, incident: incident, user: user)
    }

    public func responderAction(token raw: String, _ request: ResponderActionRequest, key: String?) throws -> ResponderView {
        try once(key, scope: "respond:\(Secrets.hash(raw))") {
            let (step, incident, user) = try responderAccess(raw)
            guard incident.status == .open else {
                throw EngineError.conflict("resolved", "This alert is already resolved.")
            }
            let t = now()
            switch request.action {
            case .acknowledge:
                acknowledge(stepId: step.id, at: t)

            case .decline:
                db.steps[step.id]?.state = .declined
                db.steps[step.id]?.actedAt = t
                cancelJobs(note: "Responder declined") { $0.kind == .ackTimeout && $0.targetId == step.id }
                log(user.id, incident: incident.id, actor: .responder, type: "step.declined",
                    text: "\(step.name) declined.", wearer: !incident.concealed, responders: true)
                if incident.currentStepId == step.id {
                    db.incidents[incident.id]?.currentStepId = nil
                    db.incidents[incident.id]?.progress = .unassigned
                    db.incidents[incident.id]?.progressVersion += 1
                    cancelJobs(note: "Responder declined") { $0.kind == .followUp && $0.targetId == incident.id }
                }
                advance(incident.id)

            case .arranging:
                if db.steps[step.id]?.state != .acknowledged {
                    acknowledge(stepId: step.id, at: t)
                }
                guard var current = db.incidents[incident.id] else { break }
                current.currentStepId = step.id
                current.progress = .assistanceArranged
                current.progressVersion += 1
                db.incidents[incident.id] = current
                scheduleFollowUp(current)
                log(user.id, incident: incident.id, actor: .responder, type: "incident.arranging",
                    text: "\(step.name) is arranging help.", wearer: !incident.concealed, responders: true)

            case .resolved:
                let outcome = (request.outcome ?? "").trimmed
                guard !outcome.isEmpty else { throw EngineError.invalid("Add a short outcome, such as \"Help arrived\".") }
                if db.steps[step.id]?.state != .acknowledged {
                    acknowledge(stepId: step.id, at: t)
                }
                resolveIncident(incident.id, reason: .responderResolved, note: String(outcome.prefix(200)), by: step.name,
                                actor: .responder, exceptStepId: step.id)
            }
            bump(user.id)
            let freshStep = db.steps[step.id] ?? step
            let freshIncident = db.incidents[incident.id] ?? incident
            return buildResponderView(step: freshStep, incident: freshIncident, user: user)
        }
    }

    /// Acknowledgment records who accepted and when. It does not mean help has arrived.
    func acknowledge(stepId: String, at t: Date) {
        guard var step = db.steps[stepId], var incident = db.incidents[step.incidentId] else { return }
        if step.state == .acknowledged { return }
        step.state = .acknowledged
        step.actedAt = t
        if step.firstOpenedAt == nil { step.firstOpenedAt = t }
        db.steps[stepId] = step
        cancelJobs(note: "Acknowledged") { $0.kind == .ackTimeout && $0.targetId == stepId }
        if incident.currentStepId == nil {
            incident.currentStepId = stepId
            incident.progress = .acknowledged
            incident.acknowledgedAt = t
        }
        incident.noResponderConfirmed = false
        incident.progressVersion += 1
        db.incidents[incident.id] = incident
        scheduleFollowUp(incident)
        log(incident.userId, incident: incident.id, actor: .responder, type: "step.acknowledged",
            text: "\(step.name) acknowledged the alert. That doesn't mean help has arrived yet.",
            wearer: !incident.concealed, responders: true)
    }

    /// If progress stops, the follow-up deadline alerts the next contact.
    func scheduleFollowUp(_ incident: IncidentRecord) {
        guard let user = db.users[incident.userId] else { return }
        cancelJobs(note: "Progress updated") { $0.kind == .followUp && $0.targetId == incident.id }
        schedule(.followUp, target: incident.id, userId: user.id,
                 at: now().addingTimeInterval(TimeInterval(user.timing.followUpWindowSeconds)),
                 key: "followup:\(incident.id):\(incident.progressVersion)", version: incident.progressVersion)
    }

    func buildResponderView(step: StepRecord, incident: IncidentRecord, user: UserRecord) -> ResponderView {
        let session = incident.sessionId.flatMap { db.sessions[$0] }
        let open = incident.status == .open
        let share = step.share

        var venue: String?
        if share.venue {
            if let coverageId = step.coverageId, let coverage = db.coverages[coverageId] {
                venue = coverage.venue
            } else if let sessionVenue = session?.venue, !sessionVenue.isEmpty {
                venue = sessionVenue
            }
        }

        // Location only during an open alert, labelled as last known.
        var location: LocationView?
        var locationNote: String?
        if share.location && open {
            if let fix = session?.lastLocation {
                location = LocationView(
                    latitude: fix.latitude, longitude: fix.longitude, accuracyMeters: fix.accuracyMeters, capturedAt: fix.capturedAt,
                    mapURL: "https://maps.apple.com/?ll=\(fix.latitude),\(fix.longitude)&q=Last%20known%20location"
                )
            } else {
                locationNote = venue == nil ? "Location isn't available." : "Location isn't available. Use the venue above."
            }
        }

        let responderName = incident.currentStepId.flatMap { db.steps[$0]?.name }
        let timeline = db.events
            .filter { $0.incidentId == incident.id && $0.visibleToResponders }
            .suffix(40)
            .map { EventView(id: $0.id, at: $0.at, actor: $0.actor, text: $0.text, simulated: $0.simulated) }

        let reason = incident.triggers.contains(.duress)
            ? "Silent alert. They may not be able to talk freely."
            : (incident.triggers.first?.label ?? "Alert")

        return ResponderView(
            serverTime: now(),
            incidentId: incident.id,
            status: incident.status,
            reason: reason,
            silent: incident.triggers.contains(.duress),
            simulated: incident.simulated,
            openedAt: incident.openedAt,
            recipientName: step.name,
            recipientKind: step.recipientKind,
            stepState: step.state,
            canAct: open,
            progress: incident.progress,
            responderName: responderName,
            wearerName: share.name ? user.displayName : nil,
            venue: venue,
            location: location,
            locationNote: locationNote,
            wearerPhone: share.contactInfo && !user.phone.isEmpty ? user.phone : nil,
            helpCard: share.helpCard && !user.helpCard.isEmpty ? user.helpCard : nil,
            wearerSafetyReportAt: incident.wearerSafetyReportAt,
            resolution: incident.resolution,
            resolutionNote: incident.resolutionNote,
            timeline: Array(timeline.reversed())
        )
    }
}
