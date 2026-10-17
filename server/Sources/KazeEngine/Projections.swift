import Foundation
import KazeKit

// Read models. Each caller gets one projection with its permissions applied.

extension Engine {
    public func wearerState(userId: String) throws -> WearerState {
        let user = try requireUser(userId)
        let session = activeSession(for: userId)
        let checkIn: CheckInRecord? = session.flatMap { s in
            awaitingCheckIn(for: s.id) ?? checkIns(for: s.id).first { $0.state == .scheduled }
        }
        // Duress alerts are never shown to the wearer.
        let incident = openIncident(for: userId).flatMap { $0.concealed ? nil : $0 }
        let concealedIds = Set(db.incidents.values.filter { $0.userId == userId && $0.concealed }.map { $0.id })

        let coverages = db.coverages.values
            .filter { $0.userId == userId && $0.demoRunId == user.demoRunId && [CoverageState.invited, .verified, .accepted].contains($0.state) }
            .sorted { $0.startsAt > $1.startsAt }
        let active = coverages.first { isActive($0) }
        let contactNames = user.contactIds.compactMap { db.contacts[$0]?.name }
        let routing = (active.map { ["\($0.helperName) (helper)"] } ?? []) + contactNames

        let coverageSummary: String
        if contactNames.isEmpty {
            coverageSummary = "Add a trusted contact. Assistance coverage isn't active without one."
        } else if let active {
            coverageSummary = "\(active.helperName) at \(active.venue) is alerted first until \(timeText(active.endsAt)), then your trusted contacts."
        } else {
            coverageSummary = "Your trusted contacts are alerted in order."
        }

        var tone = StatusTone.neutral
        var headline = "Not monitoring"
        var detail = contactNames.isEmpty ? "Add a trusted contact in Settings to begin." : "Start a session when you head out."
        if let incident {
            let responder = incident.currentStepId.flatMap { db.steps[$0]?.name }
            switch incident.progress {
            case .acknowledged:
                tone = .acknowledged
                headline = "\(responder ?? "A responder") acknowledged your alert"
                detail = "They've taken responsibility for arranging help."
            case .assistanceArranged:
                tone = .acknowledged
                headline = "\(responder ?? "A responder") is arranging help"
                detail = "Help is being arranged."
            case .unassigned, .resolved:
                tone = .alert
                headline = incident.noResponderConfirmed ? "Alert open: no responder confirmed yet" : "Alert sent"
                detail = incident.noResponderConfirmed ? "Nobody has acknowledged yet." : "Contacting your responders in order."
            }
            if incident.wearerSafetyReportAt != nil {
                detail = "You reported you're okay. Your responders were told."
            }
        } else if let checkIn, checkIn.state == .awaitingResponse {
            tone = .awaiting
            headline = "Check-in: are you okay?"
            detail = "Respond by \(timeText(checkIn.respondBy))."
        } else if let session {
            tone = .safe
            headline = "Monitoring active"
            if let next = checkIn {
                detail = "Next check-in at \(timeText(next.promptAt))."
            } else if session.expectedEndAt == nil {
                detail = "No planned end. End the session when you're done."
            } else {
                detail = "Monitoring."
            }
        }

        let events = db.events
            .filter { $0.userId == userId && $0.visibleToWearer && !($0.incidentId.map { concealedIds.contains($0) } ?? false) }
            .suffix(30)
            .reversed()
            .map { EventView(id: $0.id, at: $0.at, actor: $0.actor, text: $0.text, simulated: $0.simulated) }

        return WearerState(
            serverTime: now(),
            revision: user.revision,
            demoRunId: user.demoRunId,
            profile: profile(user),
            session: session.map { sessionView($0) },
            checkIn: checkIn.map { checkInView($0) },
            incident: incident.map { incidentView($0, includeDeliveries: false) },
            coverages: coverages.map { coverageView($0) },
            routingOrder: routing,
            coverageSummary: coverageSummary,
            tone: tone,
            headline: headline,
            detail: detail,
            events: Array(events)
        )
    }

    func buildAdminView(_ user: UserRecord) -> AdminView {
        let session = activeSession(for: user.id) ?? latestSession(for: user.id).flatMap { $0.demoRunId == user.demoRunId ? $0 : nil }
        let checkIn: CheckInRecord? = session.flatMap { s in
            awaitingCheckIn(for: s.id) ?? checkIns(for: s.id).last
        }
        let lastResponse = db.checkIns.values
            .filter { $0.userId == user.id && $0.respondedAt != nil }
            .compactMap { $0.respondedAt }
            .max()
        let incident = openIncident(for: user.id) ?? db.incidents.values
            .filter { $0.userId == user.id && $0.demoRunId == user.demoRunId }
            .max(by: { $0.openedAt < $1.openedAt })
        let jobs = db.jobs.values
            .filter { $0.userId == user.id && $0.demoRunId == user.demoRunId }
            .sorted { lhs, rhs in
                if (lhs.state == .pending) != (rhs.state == .pending) { return lhs.state == .pending }
                return lhs.runAt > rhs.runAt
            }
            .prefix(25)
            .map { JobView(id: $0.id, kind: $0.kind, runAt: $0.runAt, state: $0.state, note: $0.note) }
        let events = db.events
            .filter { $0.userId == user.id }
            .suffix(60)
            .reversed()
            .map { EventView(id: $0.id, at: $0.at, actor: $0.actor, text: $0.text, simulated: $0.simulated) }
        let coverages = db.coverages.values
            .filter { $0.userId == user.id && $0.demoRunId == user.demoRunId }
            .sorted { $0.startsAt > $1.startsAt }
            .map { coverageView($0) }

        return AdminView(
            serverTime: now(),
            revision: user.revision,
            demoRunId: user.demoRunId,
            wearer: summary(user),
            timing: user.timing,
            session: session.map { sessionView($0) },
            checkIn: checkIn.map { checkInView($0) },
            lastResponseAt: lastResponse,
            incident: incident.map { incidentView($0, includeDeliveries: true) },
            coverages: coverages,
            jobs: Array(jobs),
            events: Array(events)
        )
    }

    func profile(_ user: UserRecord) -> WearerProfile {
        WearerProfile(
            userId: user.id,
            displayName: user.displayName,
            phone: user.phone,
            helpCard: user.helpCard,
            timing: user.timing,
            contacts: user.contactIds.compactMap { id in
                db.contacts[id].map { ContactView(id: $0.id, name: $0.name, phone: $0.phone, share: $0.share) }
            },
            hasPins: user.safetyPinHash != nil && user.duressPinHash != nil,
            pairingCode: user.pairingCode
        )
    }

    func sessionView(_ session: SessionRecord) -> SessionView {
        SessionView(
            id: session.id,
            monitoring: session.monitoring,
            venue: session.venue,
            startedAt: session.startedAt,
            expectedEndAt: session.expectedEndAt,
            endedAt: session.endedAt,
            lastHeartbeatAt: session.lastHeartbeatAt,
            watchReachable: session.watchReachable,
            lastWatchContactAt: session.lastWatchContactAt,
            lastSafetyConfirmationAt: session.lastSafetyConfirmationAt,
            connectionLost: session.connectionLost
        )
    }

    func checkInView(_ checkIn: CheckInRecord) -> CheckInView {
        CheckInView(
            id: checkIn.id,
            kind: checkIn.kind,
            state: checkIn.state,
            promptAt: checkIn.promptAt,
            respondBy: checkIn.respondBy,
            respondedAt: checkIn.respondedAt
        )
    }

    func coverageView(_ coverage: CoverageRecord) -> CoverageView {
        CoverageView(
            id: coverage.id,
            venue: coverage.venue,
            helperName: coverage.helperName,
            helperPhoneHint: Phone.hint(coverage.helperPhone),
            startsAt: coverage.startsAt,
            endsAt: coverage.endsAt,
            state: coverage.state,
            isActive: isActive(coverage),
            share: coverage.share
        )
    }

    func incidentView(_ incident: IncidentRecord, includeDeliveries: Bool) -> IncidentView {
        let steps = incident.stepIds.compactMap { db.steps[$0] }.map { step -> StepView in
            let deliveries: [DeliveryView] = includeDeliveries
                ? db.deliveries.values
                    .filter { $0.stepId == step.id }
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { deliveryView($0) }
                : []
            return StepView(
                id: step.id,
                position: step.position,
                recipientKind: step.recipientKind,
                name: step.name,
                state: step.state,
                notifiedAt: step.notifiedAt,
                ackDeadline: step.ackDeadline,
                actedAt: step.actedAt,
                firstOpenedAt: step.firstOpenedAt,
                deliveries: deliveries
            )
        }
        return IncidentView(
            id: incident.id,
            status: incident.status,
            triggers: incident.triggers,
            concealed: includeDeliveries ? incident.concealed : false,
            simulated: incident.simulated,
            openedAt: incident.openedAt,
            progress: incident.progress,
            responderName: incident.currentStepId.flatMap { db.steps[$0]?.name },
            acknowledgedAt: incident.acknowledgedAt,
            wearerSafetyReportAt: incident.wearerSafetyReportAt,
            escalationPaused: incident.escalationPaused,
            noResponderConfirmed: incident.noResponderConfirmed,
            resolvedAt: incident.resolvedAt,
            resolution: incident.resolution,
            resolutionNote: incident.resolutionNote,
            steps: steps
        )
    }

    /// Admin view of a message. The responder link is redacted so it can't be
    /// copied off the presenter's screen.
    func deliveryView(_ delivery: DeliveryRecord) -> DeliveryView {
        let body = delivery.body
            .replacingOccurrences(of: "/r/[A-Za-z0-9_-]+", with: "/r/…", options: .regularExpression)
            .replacingOccurrences(of: "code is [0-9]+", with: "code is ••••••", options: .regularExpression)
        return DeliveryView(
            id: delivery.id,
            purpose: delivery.purpose,
            to: Phone.hint(delivery.to),
            body: body,
            state: delivery.state,
            attemptNo: delivery.attemptNo,
            providerStatus: delivery.providerStatus,
            error: delivery.error,
            createdAt: delivery.createdAt,
            updatedAt: delivery.updatedAt
        )
    }
}
