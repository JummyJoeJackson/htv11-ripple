import Foundation
import KazeKit
import XCTest
@testable import KazeEngine

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

final class EngineTests: XCTestCase {
    var clock: TestClock!
    var engine: Engine!
    var sent: [OutboundMessage] = []

    override func setUp() async throws {
        clock = TestClock()
        let clock = self.clock!
        engine = Engine(
            storageURL: nil,
            config: EngineConfig(publicBaseURL: "http://kaze.test", adminSecret: "secret"),
            clock: { clock.now }
        )
        sent = []
    }

    // MARK: Helpers

    /// A wearer with two trusted contacts (Sam, then Jo) and PINs 1234 / 9999.
    func makeWearer() async throws -> (userId: String, adminId: String) {
        let setup = try await engine.setup(SetupRequest(displayName: "Alex"))
        _ = try await engine.replaceContacts(userId: setup.userId, ContactsRequest(contacts: [
            ContactInput(name: "Sam", phone: "416 555 0101"),
            ContactInput(name: "Jo", phone: "416 555 0102"),
        ]))
        _ = try await engine.setPins(userId: setup.userId, PinsRequest(safetyPin: "1234", duressPin: "9999"))
        // Connection-loss alerts are off unless a test turns them on.
        try await setTiming(setup.userId, connectionGrace: 0)
        let login = try await engine.adminLogin(AdminLoginRequest(secret: "secret", name: "Presenter"))
        _ = try await engine.pair(adminId: login.adminId, PairRequest(pairingCode: setup.pairingCode))
        return (setup.userId, login.adminId)
    }

    func setTiming(_ userId: String, connectionGrace: Int) async throws {
        var timing = TimingSettings.demo
        timing.connectionGraceSeconds = connectionGrace
        _ = try await engine.updateConfig(userId: userId, ConfigRequest(
            displayName: "Alex", phone: "416 555 0100", helpCard: "Medication is in the front pocket of my bag.", timing: timing
        ))
    }

    /// Moves the clock, runs the worker once, and reports every message as submitted.
    @discardableResult
    func advance(_ seconds: TimeInterval, result: SendResult = SendResult(state: .submitted)) async -> [OutboundMessage] {
        clock.now = clock.now.addingTimeInterval(seconds)
        let outbound = await engine.tick()
        for message in outbound {
            await engine.recordSendResult(deliveryId: message.deliveryId, result: result)
        }
        // Results can queue follow-on work (retries, the next contact).
        let more = await engine.tick()
        for message in more {
            await engine.recordSendResult(deliveryId: message.deliveryId, result: result)
        }
        sent += outbound + more
        return outbound + more
    }

    func token(in message: OutboundMessage) -> String {
        message.body.components(separatedBy: "/r/").last ?? ""
    }

    func admin(_ ids: (userId: String, adminId: String)) async throws -> AdminView {
        try await engine.adminView(adminId: ids.adminId, userId: ids.userId)
    }

    func startSession(_ userId: String, seconds: Int = 60) async throws {
        _ = try await engine.startSession(userId: userId, StartSessionRequest(venue: "Community centre", durationSeconds: seconds), key: nil)
    }

    // MARK: Check-ins

    func testAnsweredCheckInSendsNoAlert() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId)
        await advance(66) // expected end 60 s + 5 s grace
        let state = try await engine.wearerState(userId: ids.userId)
        XCTAssertEqual(state.checkIn?.state, .awaitingResponse)
        XCTAssertEqual(state.tone, .awaiting)

        let response = try await engine.confirm(userId: ids.userId, ConfirmRequest(checkInId: state.checkIn?.id, source: .watch), key: "k1")
        XCTAssertEqual(response.outcome, .confirmed)

        let out = await advance(60)
        XCTAssertTrue(out.isEmpty)
        let view = try await admin(ids)
        XCTAssertNil(view.incident)
        // A successful final check-in ends the session.
        XCTAssertEqual(view.session?.monitoring, .ended)
    }

    func testMissedCheckInCreatesOneIncidentAndAlertsFirstContact() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId)
        await advance(66)
        let out = await advance(15)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.to, "+14165550101")
        XCTAssertTrue(out.first?.body.contains("missed a safety check-in") ?? false)

        await advance(1)
        await advance(1)
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.status, .open)
        XCTAssertEqual(view.incident?.triggers, [.missedCheckIn])
        XCTAssertEqual(view.incident?.steps.first?.state, .notified)
        XCTAssertEqual(sent.count, 1)
    }

    func testResponseRaceIsDecidedByServerReceiveTime() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId)
        await advance(66)
        let checkIn = try await engine.wearerState(userId: ids.userId).checkIn!

        // Exactly at the deadline, before the expire job has run: on time.
        clock.now = checkIn.respondBy
        let onTime = try await engine.confirm(userId: ids.userId, ConfirmRequest(checkInId: checkIn.id, source: .watch), key: nil)
        XCTAssertEqual(onTime.outcome, .confirmed)
        let out = await advance(1)
        XCTAssertTrue(out.isEmpty)
    }

    func testResponseJustAfterDeadlineIsLate() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId)
        await advance(66)
        let checkIn = try await engine.wearerState(userId: ids.userId).checkIn!

        clock.now = checkIn.respondBy.addingTimeInterval(0.001)
        let late = try await engine.confirm(userId: ids.userId, ConfirmRequest(checkInId: checkIn.id, source: .watch), key: nil)
        XCTAssertEqual(late.outcome, .lateReport)
        let view = try await admin(ids)
        XCTAssertNotNil(view.incident?.wearerSafetyReportAt)
        XCTAssertEqual(view.incident?.status, .open)
    }

    func testExtensionReplacesDeadline() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId)
        _ = try await engine.extendSession(userId: ids.userId, ExtendSessionRequest(additionalSeconds: 600), key: nil)
        let out = await advance(120)
        XCTAssertTrue(out.isEmpty, "The old deadline must not fire after an extension")
        let state = try await engine.wearerState(userId: ids.userId)
        XCTAssertEqual(state.checkIn?.state, .scheduled)
    }

    // MARK: Escalation

    func testAckTimeoutEscalatesToNextContact() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId)
        await advance(66)
        await advance(15)
        let next = await advance(16) // ack window 15 s
        XCTAssertEqual(next.first?.to, "+14165550102")
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.steps.map(\.state), [.timedOut, .notified])
    }

    func testDeclineEscalatesAndAcknowledgeStopsEscalation() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: "help-1")
        let first = await advance(0)
        XCTAssertEqual(first.count, 1)

        _ = try await engine.responderAction(token: token(in: first[0]), ResponderActionRequest(action: .decline), key: nil)
        let second = await advance(0)
        XCTAssertEqual(second.first?.to, "+14165550102")

        let view = try await engine.responderAction(token: token(in: second[0]), ResponderActionRequest(action: .acknowledge), key: nil)
        XCTAssertEqual(view.progress, .acknowledged)
        XCTAssertEqual(view.responderName, "Jo")

        let quiet = await advance(16)
        XCTAssertTrue(quiet.isEmpty, "No escalation after an acknowledgment, before the follow-up deadline")
    }

    func testResolveNotifiesOthersAndClosesIncident() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: nil)
        let first = await advance(0)
        await advance(16) // Sam times out, Jo is alerted
        let jo = sent.last!
        _ = try await engine.responderAction(token: token(in: jo), ResponderActionRequest(action: .arranging), key: nil)
        let resolved = try await engine.responderAction(token: token(in: jo), ResponderActionRequest(action: .resolved, outcome: "Help arrived"), key: nil)
        XCTAssertEqual(resolved.status, .resolved)
        let updates = await advance(0)
        XCTAssertEqual(updates.map(\.to), [first[0].to], "Sam was contacted, so Sam gets the update")
        XCTAssertTrue(updates.first?.body.contains("Help arrived") ?? false)
    }

    func testResolveNeedsOutcome() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: nil)
        let first = await advance(0)
        do {
            _ = try await engine.responderAction(token: token(in: first[0]), ResponderActionRequest(action: .resolved, outcome: " "), key: nil)
            XCTFail("Expected an error")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 422)
        }
    }

    func testFailedSubmissionRetriesThenMovesOn() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: nil)
        await advance(0, result: SendResult(state: .failed, error: "Invalid number"))
        // Retry after 3 s fails too; with one retry allowed, Jo is next.
        await advance(3, result: SendResult(state: .failed, error: "Invalid number"))
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.steps.first?.state, .failed)
        XCTAssertEqual(view.incident?.steps.first?.deliveries.count, 2)
        XCTAssertEqual(view.incident?.steps.last?.state, .notifying)
    }

    func testRepeatedHelpTapsDoNotDuplicateIncident() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: "same")
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: "same")
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: "different")
        let out = await advance(0)
        XCTAssertEqual(out.count, 1)
        let count = await engine.incidentCount(userId: ids.userId)
        XCTAssertEqual(count, 1)
    }

    // MARK: PINs

    func testDuressLooksLikeCancellationButAlerts() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId, seconds: 600)
        let safety = try await engine.cancel(userId: ids.userId, CancelRequest(pin: "1234"), key: nil)
        let duress = try await engine.cancel(userId: ids.userId, CancelRequest(pin: "9999"), key: nil)
        XCTAssertEqual(safety.message, duress.message)

        let state = try await engine.wearerState(userId: ids.userId)
        XCTAssertNil(state.incident, "The wearer never sees a duress alert")
        XCTAssertFalse(state.events.contains { $0.text.lowercased().contains("silent") })

        let out = await advance(0)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].body.contains("silent alert"))
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.concealed, true)
    }

    func testDuressDuringOpenAlertHidesItButKeepsEscalating() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: nil)
        await advance(0)
        _ = try await engine.cancel(userId: ids.userId, CancelRequest(pin: "9999"), key: nil)
        let state = try await engine.wearerState(userId: ids.userId)
        XCTAssertNil(state.incident)
        let next = await advance(16)
        XCTAssertEqual(next.first?.to, "+14165550102", "Escalation continues after a duress PIN")
    }

    func testSafetyPinCancelsAndUpdatesContactedResponders() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .phone), key: nil)
        await advance(0)
        _ = try await engine.cancel(userId: ids.userId, CancelRequest(pin: "1234"), key: nil)
        let updates = await advance(0)
        XCTAssertEqual(updates.count, 1)
        XCTAssertTrue(updates[0].body.contains("safety PIN"))
        let later = await advance(30)
        XCTAssertTrue(later.isEmpty, "Obsolete escalation jobs must not fire")
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.resolution, .safetyPinCancel)
    }

    func testWrongPinCancelsNothing() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .phone), key: nil)
        do {
            _ = try await engine.cancel(userId: ids.userId, CancelRequest(pin: "0000"), key: nil)
            XCTFail("Expected an error")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 403)
        }
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.status, .open)
    }

    func testLateOkaySuppressesUnsentEscalation() async throws {
        let ids = try await makeWearer()
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: nil)
        await advance(0)
        let response = try await engine.confirm(userId: ids.userId, ConfirmRequest(checkInId: nil, source: .watch), key: nil)
        XCTAssertEqual(response.outcome, .lateReport)
        let updates = await advance(0)
        XCTAssertEqual(updates.count, 1, "Sam, already contacted, gets an update")
        let later = await advance(30)
        XCTAssertTrue(later.isEmpty, "Jo is not alerted after the wearer reported they're okay")
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.status, .open, "Only a PIN or a responder closes the incident")
    }

    // MARK: Connectivity

    func testHeartbeatLossOpensIncident() async throws {
        let ids = try await makeWearer()
        try await setTiming(ids.userId, connectionGrace: 45)
        try await startSession(ids.userId, seconds: 3600)
        await advance(30)
        _ = try await engine.heartbeat(userId: ids.userId, HeartbeatRequest(watchReachable: true, lastWatchContactAt: clock.now, location: nil))
        let quiet = await advance(30)
        XCTAssertTrue(quiet.isEmpty)
        let out = await advance(20) // 50 s since the last heartbeat, grace is 45 s
        XCTAssertEqual(out.count, 1)
        let view = try await admin(ids)
        XCTAssertEqual(view.incident?.triggers, [.connectionLost])
    }

    // MARK: Helpers

    func testHelperCoverageRoutesFirstAndRevocationHandsOff() async throws {
        let ids = try await makeWearer()
        let invite = try await engine.inviteHelper(
            userId: ids.userId,
            InviteHelperRequest(helperName: "Riley", helperPhone: "416 555 0199", venue: "Community centre", durationMinutes: 60),
            key: nil
        )
        let enrollToken = invite.enrollURL.components(separatedBy: "/e/").last!
        let preview = try await engine.enrollView(token: enrollToken)
        XCTAssertEqual(preview.state, .invited)

        _ = try await engine.sendEnrollCode(token: enrollToken)
        let codeMessage = await advance(0).first!
        let code = codeMessage.body.filter { $0.isNumber }.prefix(6)
        _ = try await engine.verifyEnrollCode(token: enrollToken, VerifyCodeRequest(code: String(code)))
        let accepted = try await engine.acceptCoverage(token: enrollToken, AcceptCoverageRequest(agree: true))
        XCTAssertEqual(accepted.state, .accepted)

        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: nil)
        let helperAlert = await advance(0)
        XCTAssertEqual(helperAlert.first?.to, "+14165550199")
        let helperView = try await engine.responderView(token: token(in: helperAlert[0]))
        XCTAssertNil(helperView.wearerPhone, "Helpers don't see the wearer's phone number by default")

        _ = try await engine.revokeCoverage(userId: ids.userId, coverageId: invite.coverage.id, key: nil)
        do {
            _ = try await engine.responderView(token: token(in: helperAlert[0]))
            XCTFail("Revoked helper must lose access")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 410)
        }
        let handoff = await advance(0)
        XCTAssertEqual(handoff.first?.to, "+14165550101", "The incident passes to trusted contacts")
    }

    func testUnacceptedHelperIsNeverRouted() async throws {
        let ids = try await makeWearer()
        _ = try await engine.inviteHelper(
            userId: ids.userId,
            InviteHelperRequest(helperName: "Riley", helperPhone: "416 555 0199", venue: "Community centre", durationMinutes: 60),
            key: nil
        )
        _ = try await engine.help(userId: ids.userId, HelpRequest(source: .watch), key: nil)
        let out = await advance(0)
        XCTAssertEqual(out.first?.to, "+14165550101")
    }

    // MARK: Admin

    func testUnpairedAdminIsRefused() async throws {
        let ids = try await makeWearer()
        let other = try await engine.adminLogin(AdminLoginRequest(secret: "secret", name: "Someone else"))
        do {
            _ = try await engine.triggerHelp(adminId: other.adminId, userId: ids.userId, key: nil)
            XCTFail("Expected a refusal")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 403)
        }
        let out = await advance(0)
        XCTAssertTrue(out.isEmpty)
    }

    func testWrongAdminSecretIsRefused() async throws {
        do {
            _ = try await engine.adminLogin(AdminLoginRequest(secret: "nope", name: "x"))
            XCTFail("Expected a refusal")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 403)
        }
    }

    func testResetMakesOldRunInert() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId, seconds: 600)
        let view = try await engine.triggerCheckIn(adminId: ids.adminId, userId: ids.userId, TriggerCheckInRequest(responseWindowSeconds: 10), key: nil)
        let oldCheckIn = view.checkIn!
        _ = try await engine.resetRun(adminId: ids.adminId, userId: ids.userId, key: nil)

        let out = await advance(20)
        XCTAssertTrue(out.isEmpty, "Old timers must not fire after a reset")
        do {
            _ = try await engine.confirm(userId: ids.userId, ConfirmRequest(checkInId: oldCheckIn.id, source: .watch), key: nil)
            XCTFail("A delayed response from the old run must be rejected")
        } catch let error as EngineError {
            XCTAssertEqual(error.code, "stale_run")
        }
        let state = try await engine.wearerState(userId: ids.userId)
        XCTAssertNil(state.session)
    }

    func testOperatorStopUpdatesRespondersWithoutClaimingSafety() async throws {
        let ids = try await makeWearer()
        try await startSession(ids.userId, seconds: 600)
        _ = try await engine.triggerHelp(adminId: ids.adminId, userId: ids.userId, key: nil)
        let alert = await advance(0)
        XCTAssertTrue(alert.first?.body.hasPrefix("[DEMO]") ?? false)
        _ = try await engine.stopIncident(adminId: ids.adminId, userId: ids.userId, StopRequest(reason: "End of demo"), key: nil)
        let updates = await advance(0)
        XCTAssertTrue(updates.first?.body.contains("does not confirm") ?? false)
    }
}

extension Engine {
    func incidentCount(userId: String) -> Int {
        db.incidents.values.filter { $0.userId == userId }.count
    }
}
