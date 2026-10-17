import Foundation
import KazeKit

// The persistent job worker (PRD §5). Deadlines live in the database, so
// they survive phone/watch disconnection and server restarts.

extension Engine {
    /// Called by the worker every 250 ms. Runs due jobs and returns the
    /// messages that should now be handed to the messaging adapter.
    public func tick() -> [OutboundMessage] {
        let t = now()
        var outbound: [OutboundMessage] = []
        sweepConnections(at: t)
        // A job can schedule follow-on work that is due immediately, so make a few passes.
        for _ in 0..<3 {
            let due = db.jobs.values
                .filter { $0.state == .pending && $0.runAt <= t }
                .sorted { $0.runAt < $1.runAt }
            if due.isEmpty { break }
            for job in due where db.jobs[job.id]?.state == .pending {
                run(job, outbound: &outbound)
            }
        }
        if t.timeIntervalSince(lastPrune) > 60 {
            prune(at: t)
            lastPrune = t
        }
        persistIfDirty()
        return outbound
    }

    func run(_ job: JobRecord, outbound: inout [OutboundMessage]) {
        // Jobs from a demo run that was reset never act.
        guard let user = db.users[job.userId], user.demoRunId == job.demoRunId else {
            finish(job.id, .skipped, note: "Belongs to an old demo run")
            return
        }
        switch job.kind {
        case .checkInPrompt:
            guard var checkIn = db.checkIns[job.targetId], checkIn.state == .scheduled else {
                finish(job.id, .skipped, note: "Check-in no longer scheduled")
                return
            }
            checkIn.state = .awaitingResponse
            db.checkIns[checkIn.id] = checkIn
            log(user.id, session: checkIn.sessionId, actor: .system, type: "checkin.prompted",
                text: "Check-in started. Waiting for I'm okay until \(timeText(checkIn.respondBy)).", wearer: true, responders: false,
                simulated: checkIn.kind == .demo)
            bump(user.id)
            finish(job.id, .done)

        case .checkInExpire:
            guard let checkIn = db.checkIns[job.targetId],
                  checkIn.state == .awaitingResponse || checkIn.state == .scheduled
            else {
                finish(job.id, .skipped, note: "Check-in already answered or cancelled")
                return
            }
            finish(job.id, .done)
            expireCheckIn(checkIn.id)

        case .deliverySend:
            guard var delivery = db.deliveries[job.targetId], delivery.state == .queued else {
                finish(job.id, .skipped, note: "Message no longer queued")
                return
            }
            // Recheck incident state and permissions immediately before dispatch.
            if delivery.purpose == .alert {
                guard let stepId = delivery.stepId, let step = db.steps[stepId], step.state == .notifying,
                      let incident = db.incidents[step.incidentId], incident.status == .open, !incident.escalationPaused,
                      isEligible(step)
                else {
                    delivery.state = .cancelled
                    delivery.updatedAt = now()
                    db.deliveries[delivery.id] = delivery
                    finish(job.id, .skipped, note: "Alert no longer needed")
                    if let stepId = delivery.stepId, db.steps[stepId]?.state == .notifying {
                        db.steps[stepId]?.state = .skipped
                        if let incidentId = db.steps[stepId]?.incidentId { advance(incidentId) }
                    }
                    return
                }
            }
            if let allowed = config.demoRecipients, !allowed.contains(delivery.to) {
                db.deliveries[delivery.id]?.state = .submitting
                finish(job.id, .done)
                recordSendResult(deliveryId: delivery.id, result: SendResult(state: .failed, error: "Not a designated demo recipient"))
                return
            }
            delivery.state = .submitting
            delivery.updatedAt = now()
            db.deliveries[delivery.id] = delivery
            outbound.append(OutboundMessage(deliveryId: delivery.id, to: delivery.to, body: delivery.body))
            finish(job.id, .done)

        case .ackTimeout:
            guard let step = db.steps[job.targetId], step.state == .notified,
                  let incident = db.incidents[step.incidentId], incident.status == .open, !incident.escalationPaused
            else {
                finish(job.id, .skipped, note: "Responder already answered")
                return
            }
            db.steps[step.id]?.state = .timedOut
            log(user.id, incident: incident.id, actor: .system, type: "step.timed_out",
                text: "No acknowledgment from \(step.name) within \(user.timing.ackWindowSeconds) s.",
                wearer: !incident.concealed, responders: true)
            finish(job.id, .done)
            advance(incident.id)
            bump(user.id)

        case .followUp:
            guard let incident = db.incidents[job.targetId], incident.status == .open, !incident.escalationPaused,
                  incident.progressVersion == job.version
            else {
                finish(job.id, .skipped, note: "Progress was updated")
                return
            }
            let name = incident.currentStepId.flatMap { db.steps[$0]?.name } ?? "the responder"
            log(user.id, incident: incident.id, actor: .system, type: "incident.follow_up",
                text: "No progress update from \(name) in \(user.timing.followUpWindowSeconds) s. Alerting the next contact too.",
                wearer: !incident.concealed, responders: true)
            finish(job.id, .done)
            advance(incident.id, force: true)
            bump(user.id)

        case .coverageExpire:
            guard let coverage = db.coverages[job.targetId],
                  [CoverageState.invited, .verified, .accepted].contains(coverage.state)
            else {
                finish(job.id, .skipped, note: "Coverage already ended")
                return
            }
            finish(job.id, .done)
            endCoverage(coverage.id, newState: .expired, actor: .system)
        }
    }

    /// Records what the messaging adapter reported. A timeout is "unknown",
    /// never "delivered".
    public func recordSendResult(deliveryId: String, result: SendResult) {
        guard var delivery = db.deliveries[deliveryId], delivery.state == .submitting else { return }
        let t = now()
        delivery.state = result.state
        delivery.providerMessageId = result.providerMessageId
        delivery.error = result.error
        delivery.updatedAt = t
        db.deliveries[deliveryId] = delivery
        dirty = true

        guard delivery.purpose == .alert, let stepId = delivery.stepId, var step = db.steps[stepId],
              let incident = db.incidents[step.incidentId], let user = db.users[incident.userId]
        else {
            if result.state == .failed {
                log(delivery.userId, incident: delivery.incidentId, actor: .system, type: "delivery.failed",
                    text: "A \(delivery.purpose.rawValue) message couldn't be submitted: \(result.error ?? "unknown error").",
                    wearer: false, responders: false)
            }
            persistIfDirty()
            return
        }
        guard step.state == .notifying else {
            persistIfDirty()
            return
        }

        switch result.state {
        case .submitted, .unknown:
            step.state = .notified
            step.notifiedAt = t
            step.ackDeadline = t.addingTimeInterval(TimeInterval(user.timing.ackWindowSeconds))
            db.steps[stepId] = step
            schedule(.ackTimeout, target: stepId, userId: user.id, at: step.ackDeadline!, key: "ack:\(stepId)")
            let status = result.state == .submitted
                ? "submitted to the messaging service (not yet confirmed received)"
                : "sent, but the messaging service didn't confirm it"
            log(user.id, incident: incident.id, actor: .system, type: "step.notified",
                text: "Alert to \(step.name) \(status).", wearer: !incident.concealed, responders: false)

        case .failed:
            if step.attempts <= user.timing.maxRetries {
                log(user.id, incident: incident.id, actor: .system, type: "delivery.retry",
                    text: "Couldn't send to \(step.name) (\(result.error ?? "error")). Retrying.", wearer: false, responders: false)
                db.steps[stepId] = step
                retryAlert(stepId: stepId, after: 3)
            } else {
                step.state = .failed
                db.steps[stepId] = step
                log(user.id, incident: incident.id, actor: .system, type: "step.failed",
                    text: "Couldn't send the alert to \(step.name): \(result.error ?? "error"). Moving to the next contact.",
                    wearer: !incident.concealed, responders: false)
                advance(incident.id)
            }

        case .queued, .submitting, .cancelled:
            break
        }
        bump(user.id)
        persistIfDirty()
    }

    func retryAlert(stepId: String, after seconds: TimeInterval) {
        guard var step = db.steps[stepId], let incident = db.incidents[step.incidentId] else { return }
        step.attempts += 1
        db.steps[stepId] = step
        let delivery = DeliveryRecord(
            id: newId(), userId: incident.userId, incidentId: incident.id, stepId: stepId, coverageId: step.coverageId,
            purpose: .alert, to: step.phone, body: step.alertBody ?? "", state: .queued, attemptNo: step.attempts,
            providerMessageId: nil, providerStatus: nil, error: nil, createdAt: now(), updatedAt: now()
        )
        db.deliveries[delivery.id] = delivery
        schedule(.deliverySend, target: delivery.id, userId: incident.userId, at: now().addingTimeInterval(seconds), key: "send:\(delivery.id)")
        dirty = true
    }

    /// Delivery evidence from the provider's status callback. "delivered" is a
    /// carrier report, not proof a person read the message.
    public func recordProviderStatus(providerMessageId: String, status: String, errorCode: String?) {
        guard let match = db.deliveries.first(where: { $0.value.providerMessageId == providerMessageId }) else { return }
        let id = match.key
        let delivery = match.value
        db.deliveries[id]?.providerStatus = status
        db.deliveries[id]?.updatedAt = now()
        dirty = true
        guard delivery.purpose == .alert, let stepId = delivery.stepId, let step = db.steps[stepId],
              let incident = db.incidents[step.incidentId]
        else {
            persistIfDirty()
            return
        }
        switch status {
        case "delivered":
            log(incident.userId, incident: incident.id, actor: .system, type: "delivery.carrier_delivered",
                text: "Carrier reported the alert to \(step.name) as delivered (not proof it was read).",
                wearer: false, responders: false)
        case "undelivered", "failed":
            db.deliveries[id]?.state = .failed
            db.deliveries[id]?.error = "Carrier reported \(status)\(errorCode.map { " (\($0))" } ?? "")"
            if step.state == .notified, incident.status == .open {
                db.steps[stepId]?.state = .failed
                cancelJobs(note: "Message undelivered") { $0.kind == .ackTimeout && $0.targetId == stepId }
                log(incident.userId, incident: incident.id, actor: .system, type: "step.failed",
                    text: "The alert to \(step.name) wasn't delivered. Moving to the next contact.",
                    wearer: !incident.concealed, responders: false)
                advance(incident.id)
            }
            bump(incident.userId)
        default:
            break
        }
        persistIfDirty()
    }

    /// Silence is the signal: missing heartbeats or watch contact beyond the
    /// grace period opens an alert.
    func sweepConnections(at t: Date) {
        for session in db.sessions.values where session.monitoring == .active && !session.connectionLost {
            guard let user = db.users[session.userId], session.demoRunId == user.demoRunId else { continue }
            guard isConnectionStale(session, user: user, at: t) else { continue }
            db.sessions[session.id]?.connectionLost = true
            let phoneStale = t.timeIntervalSince(session.lastHeartbeatAt) > TimeInterval(user.timing.connectionGraceSeconds)
            let device = phoneStale ? "iPhone" : "Apple Watch"
            log(user.id, session: session.id, actor: .system, type: "connection.lost",
                text: "No contact from the wearer's \(device) for over \(user.timing.connectionGraceSeconds) s.",
                wearer: true, responders: true)
            if let incident = openIncident(for: user.id) {
                attachTrigger(.connectionLost, to: incident.id)
            } else {
                openNewIncident(userId: user.id, sessionId: session.id, trigger: .connectionLost, concealed: false, simulated: false)
            }
            bump(user.id)
        }
    }

    /// Call once at startup.
    public func recoverAfterRestart() {
        let t = now()
        // A send that was in progress when the server stopped may or may not have gone out.
        for (id, delivery) in db.deliveries where delivery.state == .submitting {
            recordSendResult(deliveryId: id, result: SendResult(state: .unknown, error: "Server restarted while sending"))
        }
        // Give devices a fresh grace period after server downtime.
        for (id, session) in db.sessions where session.monitoring == .active {
            if t.timeIntervalSince(session.lastHeartbeatAt) > 5 {
                db.sessions[id]?.lastHeartbeatAt = t
            }
            if session.lastWatchContactAt != nil {
                db.sessions[id]?.lastWatchContactAt = t
            }
        }
        dirty = true
        persistIfDirty()
    }

    func prune(at t: Date) {
        let cutoff = t.addingTimeInterval(-6 * 3600)
        db.jobs = db.jobs.filter { $0.value.state == .pending || ($0.value.finishedAt ?? t) > cutoff }
        db.idempotency = db.idempotency.filter { $0.value.createdAt > t.addingTimeInterval(-3600) }
        if db.events.count > 5000 {
            db.events.removeFirst(db.events.count - 5000)
        }
        db.otps = db.otps.filter { $0.value.expiresAt > t.addingTimeInterval(-3600) }
        dirty = true
    }
}
