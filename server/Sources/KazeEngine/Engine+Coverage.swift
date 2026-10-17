import Foundation
import KazeKit

// Temporary helper coverage: invitation, phone verification, explicit
// acceptance, expiry and revocation (PRD §3 and §4.9).

extension Engine {
    public func inviteHelper(userId: String, _ request: InviteHelperRequest, key: String?) throws -> InviteHelperResponse {
        try once(key, scope: "\(userId):invite") {
            let user = try requireUser(userId)
            let name = request.helperName.trimmed
            let venue = request.venue.trimmed
            guard !name.isEmpty else { throw EngineError.invalid("Enter the helper's name.") }
            guard !venue.isEmpty else { throw EngineError.invalid("Enter the venue the helper works at.") }
            guard let phone = Phone.normalize(request.helperPhone) else {
                throw EngineError.invalid("The helper's phone number doesn't look right. Include the area code.")
            }
            guard (5...720).contains(request.durationMinutes) else {
                throw EngineError.invalid("Coverage can last between 5 minutes and 12 hours.")
            }
            if db.coverages.values.contains(where: { $0.userId == userId && [CoverageState.invited, .verified, .accepted].contains($0.state) && $0.endsAt > now() }) {
                throw EngineError.conflict("coverage_exists", "Revoke the current helper before inviting another.")
            }
            let t = now()
            let raw = Secrets.randomToken()
            let coverage = CoverageRecord(
                id: newId(), userId: userId, demoRunId: user.demoRunId, venue: String(venue.prefix(120)),
                helperName: String(name.prefix(60)), helperPhone: phone, share: request.share,
                startsAt: t, endsAt: t.addingTimeInterval(TimeInterval(request.durationMinutes * 60)),
                state: .invited, verifiedAt: nil, acceptedAt: nil, endedAt: nil, enrollTokenHash: Secrets.hash(raw)
            )
            db.coverages[coverage.id] = coverage
            db.tokens[coverage.enrollTokenHash] = TokenRecord(
                purpose: .enroll, userId: userId, demoRunId: user.demoRunId, coverageId: coverage.id,
                incidentId: nil, stepId: nil, expiresAt: coverage.endsAt, revokedAt: nil
            )
            schedule(.coverageExpire, target: coverage.id, userId: userId, at: coverage.endsAt, key: "coverage-expire:\(coverage.id)")
            log(userId, actor: .wearer, type: "coverage.invited",
                text: "Invited \(coverage.helperName) at \(coverage.venue) as a temporary helper until \(timeText(coverage.endsAt)). Not active until they verify and accept.",
                wearer: true, responders: false)
            bump(userId)
            return InviteHelperResponse(coverage: coverageView(coverage), enrollURL: link("/e/\(raw)"))
        }
    }

    public func revokeCoverage(userId: String, coverageId: String, key: String?) throws -> WearerState {
        try once(key, scope: "\(userId):revoke") {
            guard let coverage = db.coverages[coverageId], coverage.userId == userId else {
                throw EngineError.notFound("That helper invitation doesn't exist.")
            }
            if [CoverageState.invited, .verified, .accepted].contains(coverage.state) {
                endCoverage(coverageId, newState: .revoked, actor: .wearer)
            }
            return try wearerState(userId: userId)
        }
    }

    /// Expiry or revocation removes helper access immediately and passes any
    /// unresolved incident to trusted contacts. It never resolves an incident.
    func endCoverage(_ coverageId: String, newState: CoverageState, actor: ActorType) {
        guard var coverage = db.coverages[coverageId] else { return }
        let t = now()
        coverage.state = newState
        coverage.endedAt = t
        db.coverages[coverageId] = coverage
        db.tokens[coverage.enrollTokenHash]?.revokedAt = t
        cancelJobs(note: "Coverage ended") { $0.kind == .coverageExpire && $0.targetId == coverageId }

        let verb = newState == .expired ? "expired" : "was revoked"
        log(coverage.userId, actor: actor, type: "coverage.ended",
            text: "\(coverage.helperName)'s helper coverage \(verb). Alerts now go to trusted contacts.", wearer: true, responders: false)

        if let incident = openIncident(for: coverage.userId) {
            var rerouted = false
            for stepId in incident.stepIds {
                guard var step = db.steps[stepId], step.coverageId == coverageId else { continue }
                if let hash = step.tokenHash {
                    db.tokens[hash]?.revokedAt = t
                }
                switch step.state {
                case .pending, .notifying, .notified:
                    step.state = .skipped
                    cancelJobs(note: "Coverage ended") { $0.kind == .ackTimeout && $0.targetId == stepId }
                    for (deliveryId, delivery) in db.deliveries where delivery.stepId == stepId && delivery.state == .queued {
                        db.deliveries[deliveryId]?.state = .cancelled
                        cancelJobs(note: "Coverage ended") { $0.targetId == deliveryId }
                    }
                    rerouted = true
                default:
                    break
                }
                db.steps[stepId] = step
                if incident.currentStepId == stepId {
                    db.incidents[incident.id]?.currentStepId = nil
                    db.incidents[incident.id]?.progress = .unassigned
                    db.incidents[incident.id]?.progressVersion += 1
                    rerouted = true
                }
            }
            if rerouted {
                log(coverage.userId, incident: incident.id, actor: .system, type: "incident.handoff",
                    text: "Helper coverage ended. Passing the alert to trusted contacts.", wearer: !incident.concealed, responders: true)
                cancelJobs(note: "Coverage ended") { $0.kind == .followUp && $0.targetId == incident.id }
                advance(incident.id)
            }
        }
        bump(coverage.userId)
    }

    // MARK: Enrollment pages

    func enrollToken(_ raw: String) throws -> (TokenRecord, CoverageRecord) {
        guard let token = db.tokens[Secrets.hash(raw)], token.purpose == .enroll, let coverageId = token.coverageId,
              let coverage = db.coverages[coverageId]
        else { throw EngineError.notFound("This invitation link isn't valid.") }
        guard token.revokedAt == nil, token.expiresAt > now(),
              coverage.state != .expired, coverage.state != .revoked,
              db.users[token.userId]?.demoRunId == token.demoRunId
        else { throw EngineError.gone("This invitation has ended. Ask for a new one if you're still helping.") }
        return (token, coverage)
    }

    public func enrollView(token raw: String) throws -> EnrollView {
        let (_, coverage) = try enrollToken(raw)
        return enrollView(coverage)
    }

    func enrollView(_ coverage: CoverageRecord) -> EnrollView {
        EnrollView(
            serverTime: now(), venue: coverage.venue, helperName: coverage.helperName,
            phoneHint: Phone.hint(coverage.helperPhone), startsAt: coverage.startsAt, endsAt: coverage.endsAt,
            state: coverage.state, shared: coverage.share.labels, codeSent: db.otps[coverage.id] != nil
        )
    }

    public func sendEnrollCode(token raw: String) throws -> EnrollView {
        let (_, coverage) = try enrollToken(raw)
        guard coverage.state == .invited else { return enrollView(coverage) }
        let t = now()
        if let existing = db.otps[coverage.id], t.timeIntervalSince(existing.sentAt) < 20 {
            throw EngineError.tooMany("A code was just sent. Wait a few seconds before asking for another.")
        }
        let code = Secrets.randomDigits(6)
        db.otps[coverage.id] = OTPRecord(codeHash: Secrets.hash(coverage.id + ":" + code), expiresAt: t.addingTimeInterval(300), attempts: 0, sentAt: t)
        queueMessage(userId: coverage.userId, purpose: .code, to: coverage.helperPhone,
                     body: "Your KAZE helper verification code is \(code). It expires in 5 minutes.", coverageId: coverage.id)
        log(coverage.userId, actor: .helper, type: "coverage.code_sent",
            text: "Verification code sent to \(coverage.helperName).", wearer: true, responders: false)
        persistIfDirty()
        return enrollView(coverage)
    }

    public func verifyEnrollCode(token raw: String, _ request: VerifyCodeRequest) throws -> EnrollView {
        let (_, coverage) = try enrollToken(raw)
        guard coverage.state == .invited else { return enrollView(coverage) }
        guard var otp = db.otps[coverage.id] else { throw EngineError.invalid("Ask for a code first.") }
        guard otp.expiresAt > now() else { throw EngineError.invalid("That code expired. Ask for a new one.") }
        guard otp.attempts < 5 else { throw EngineError.tooMany("Too many tries. Ask for a new code.") }
        let code = request.code.filter { $0.isNumber }
        guard Secrets.hash(coverage.id + ":" + code) == otp.codeHash else {
            otp.attempts += 1
            db.otps[coverage.id] = otp
            dirty = true
            persistIfDirty()
            throw EngineError.invalid("That code didn't match.")
        }
        db.coverages[coverage.id]?.state = .verified
        db.coverages[coverage.id]?.verifiedAt = now()
        db.otps[coverage.id] = nil
        log(coverage.userId, actor: .helper, type: "coverage.verified",
            text: "\(coverage.helperName) verified their phone number.", wearer: true, responders: false)
        bump(coverage.userId)
        persistIfDirty()
        return enrollView(db.coverages[coverage.id]!)
    }

    public func acceptCoverage(token raw: String, _ request: AcceptCoverageRequest) throws -> EnrollView {
        let (_, coverage) = try enrollToken(raw)
        if coverage.state == .accepted { return enrollView(coverage) }
        guard coverage.state == .verified else { throw EngineError.invalid("Verify your phone number first.") }
        guard request.agree else { throw EngineError.invalid("Tick the box to accept coverage.") }
        db.coverages[coverage.id]?.state = .accepted
        db.coverages[coverage.id]?.acceptedAt = now()
        log(coverage.userId, actor: .helper, type: "coverage.accepted",
            text: "\(coverage.helperName) accepted helper coverage at \(coverage.venue) until \(timeText(coverage.endsAt)).",
            wearer: true, responders: false)
        bump(coverage.userId)
        persistIfDirty()
        return enrollView(db.coverages[coverage.id]!)
    }
}
