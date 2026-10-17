import Foundation
import RippleKit
import XCTest
@testable import RippleEngine

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

/// Collects what the simulated phone hands to its Shortcut.
final class PhoneOutbox: AlarmCoordinatorDelegate {
    var sent: [OutMessage] = []
    func coordinator(_ coordinator: AlarmCoordinator, send messages: [OutMessage]) { sent += messages }
    func coordinatorDidChange(_ coordinator: AlarmCoordinator) {}
}

final class BackupTests: XCTestCase {
    var clock: TestClock!
    var engine: Engine!
    var phone: AlarmCoordinator!
    var outbox: PhoneOutbox!
    var userId = ""
    var adminId = ""
    var backups: [OutboundMessage] = []

    override func setUp() async throws {
        clock = TestClock()
        let clock = self.clock!
        engine = Engine(
            storageURL: nil,
            config: EngineConfig(publicBaseURL: "http://ripple.test", adminSecret: "secret"),
            clock: { clock.now }
        )
        let setup = try await engine.setup(SetupRequest(displayName: "Alex"))
        userId = setup.userId
        let login = try await engine.adminLogin(AdminLoginRequest(secret: "secret", name: "Presenter"))
        adminId = login.adminId
        _ = try await engine.pair(adminId: adminId, PairRequest(pairingCode: setup.pairingCode))

        var config = RippleConfig.makeDefault(wearerName: "Alex")
        config.contacts = [
            PermanentContact(id: "sam", name: "Sam", phone: "416 555 0101", tier: .one, shareLocation: true),
            PermanentContact(id: "jo", name: "Jo", phone: "416 555 0102", tier: .one, shareLocation: false),
            PermanentContact(id: "pat", name: "Pat", phone: "416 555 0103", tier: .two, shareLocation: false),
        ]
        outbox = PhoneOutbox()
        phone = AlarmCoordinator(config: config, serverBaseURL: "http://ripple.test", clock: { clock.now })
        phone.delegate = outbox
        phone.setRunId(setup.runId)
        phone.startMonitoring()
        backups = []
    }

    // MARK: Helpers

    @discardableResult
    func sync(results: [CommandResult] = []) async throws -> SyncResponse {
        let status = DeviceStatus(
            displayName: "Alex", monitoring: phone.monitoring, watchPaired: true, watchReachable: true,
            configVersion: phone.config.version, watchConfigVersion: phone.config.version,
            nextCheckInAt: nil, appActive: true
        )
        let response = try await engine.sync(userId: userId, SyncRequest(runId: phone.runId, status: status, alarm: phone.alarm, commandResults: results))
        phone.temporaryContacts = response.temporaryContacts
        if let feedback = response.feedback {
            phone.applyFeedback(feedback)
        }
        return response
    }

    /// Moves time; the backend worker runs and every backup text is accepted by the provider.
    @discardableResult
    func advance(_ seconds: TimeInterval) async -> [OutboundMessage] {
        clock.now = clock.now.addingTimeInterval(seconds)
        let out = await engine.tick()
        for message in out {
            await engine.recordSendResult(messageId: message.messageId, result: SendResult(status: .submitted, providerMessageId: "SM1"))
        }
        backups += out
        return out
    }

    /// The phone's Shortcut reports success for everything it was handed.
    func phoneSubmits() {
        phone.recordResults(ids: outbox.sent.map(\.id), status: .submitted, detail: nil)
    }

    func recipients(_ messages: [OutboundMessage]) -> Set<String> {
        Set(messages.map(\.to))
    }

    func adminView() async throws -> AdminWearerView {
        try await engine.adminView(adminId: adminId, userId: userId)
    }

    // MARK: Phone first

    func testPhoneSendsFirstSoTheBackupStaysQuiet() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        for _ in 0..<15 {
            await advance(1)
            phone.tick()
            phoneSubmits()
            try await sync()
        }
        XCTAssertEqual(Set(outbox.sent.filter { $0.kind == .alert }.map(\.recipientId)), ["sam", "jo"])
        for _ in 0..<40 {
            await advance(1)
            try await sync()
        }
        XCTAssertTrue(backups.filter { $0.body.contains("did not respond to their Watch check-in") }.isEmpty,
                      "No backup alert when the phone sent and reported it")
    }

    func testDismissedAlarmNeverTriggersBackup() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        phone.dismiss(alarmId: phone.alarm?.id)
        try await sync()
        await advance(120)
        XCTAssertTrue(backups.isEmpty)
    }

    // MARK: Connectivity failure

    func testBackupTextsTheAlertWhenThePhoneGoesQuiet() async throws {
        phone.startAlarm(source: .admin)
        try await sync() // registered; then the phone goes silent
        let early = await advance(20)
        XCTAssertTrue(early.isEmpty, "Still inside the grace period")
        let out = await advance(11) // 31 s since the last heartbeat, past the deadline
        XCTAssertEqual(recipients(out), ["+14165550101", "+14165550102"])
        XCTAssertTrue(out.allSatisfy { $0.body.hasSuffix(MessageTemplates.backupNote) }, "Marked as sent by backup")
        XCTAssertTrue(out.first { $0.to == "+14165550101" }!.body.contains("Tap if you're checking: http://ripple.test/a/"))

        let view = try await adminView()
        XCTAssertEqual(view.messages.filter { $0.path == .backup && $0.kind == .alert }.count, 2)
    }

    func testBackupAlsoCoversAPhoneThatIsOnlineButLate() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        // The phone keeps syncing but never sends (for example the Shortcut didn't run).
        for _ in 0..<44 {
            await advance(1)
            try await sync()
        }
        XCTAssertTrue(backups.isEmpty)
        let out = await advance(1) // deadline (15 s) + 30 s grace
        XCTAssertEqual(recipients(out), ["+14165550101", "+14165550102"])
    }

    func testBackupEscalatesToTierTwoWhenNobodyAcknowledges() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        await advance(31) // backup alert
        XCTAssertEqual(backups.count, 2)
        let notYet = await advance(14)
        XCTAssertTrue(notYet.isEmpty)
        let escalation = await advance(1) // 15 s acknowledge window
        XCTAssertEqual(recipients(escalation), ["+14165550103"])
        XCTAssertTrue(escalation[0].body.contains("no one has confirmed yet"))
    }

    func testPhoneDoesNotRepeatWhatTheBackupSent() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        await advance(31) // backup alert while the phone is quiet
        try await sync()   // the phone comes back
        phone.tick()
        XCTAssertTrue(outbox.sent.filter { $0.kind == .alert }.isEmpty)
        XCTAssertEqual(phone.alarm?.phase, .alerted)
    }

    // MARK: Acknowledgment

    func testAcknowledgeLinkReachesThePhoneAndStopsEscalation() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        await advance(15)
        phone.tick()
        phoneSubmits()
        try await sync()

        let samToken = phone.alarm!.recipients.first { $0.id == "sam" }!.ackToken
        let page = try await engine.ackPage(token: samToken)
        XCTAssertEqual(page.wearerName, "Alex")
        XCTAssertTrue(page.open)
        let acked = try await engine.acknowledge(token: samToken)
        XCTAssertTrue(acked.youAcknowledged)

        try await sync()
        XCTAssertEqual(phone.display().status, "Sam is responding")
        XCTAssertEqual(outbox.sent.filter { $0.kind == .responding }.map(\.recipientId), ["jo"])
        phoneSubmits()
        try await sync()

        for _ in 0..<60 {
            await advance(1)
            phone.tick()
            try await sync()
        }
        XCTAssertTrue(outbox.sent.filter { $0.kind == .escalation }.isEmpty)
        XCTAssertTrue(backups.isEmpty)
    }

    func testTextReplyAcceptReachesTheBackendAndStopsTierTwo() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        await advance(15)
        phone.tick()
        phoneSubmits()
        try await sync()

        // Sam texts back the code; the Ripple Accept shortcut hands it to the app.
        let sam = phone.alarm!.recipients.first { $0.id == "sam" }!
        XCTAssertTrue(sam.alertText.contains("or reply RIPPLE ACCEPT \(sam.acceptCode!)"))
        let result = phone.acceptReply(text: "Ripple accept \(sam.acceptCode!)", from: "+14165550101")
        XCTAssertTrue(result.ok)
        phoneSubmits()
        try await sync() // the backend learns about it, then the phone goes quiet

        let joToken = phone.alarm!.recipients.first { $0.id == "jo" }!.ackToken
        let page = try await engine.ackPage(token: joToken)
        XCTAssertEqual(page.responderName, "Sam", "The link page shows Sam is already checking")

        let out = await advance(60)
        XCTAssertTrue(out.isEmpty, "No Tier 2 backup once someone accepted by text")
        let view = try await adminView()
        XCTAssertEqual(view.acknowledgment?.name, "Sam")
    }

    func testRespondingTextComesFromBackupWhenThePhoneIsQuiet() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        await advance(15)
        phone.tick()
        phoneSubmits()
        try await sync() // the phone reported the alert, then goes quiet
        let samToken = phone.alarm!.recipients.first { $0.id == "sam" }!.ackToken
        _ = try await engine.acknowledge(token: samToken)
        await advance(1)
        XCTAssertTrue(backups.isEmpty, "The phone isn't quiet long enough yet")
        let out = await advance(30)
        XCTAssertEqual(recipients(out), ["+14165550102"])
        XCTAssertTrue(out[0].body.hasPrefix("Ripple: Sam is checking on Alex."))
    }

    func testAcknowledgePageClosesWithTheAlarm() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        let token = phone.alarm!.recipients[0].ackToken
        phone.dismiss(alarmId: phone.alarm?.id)
        try await sync()
        do {
            _ = try await engine.ackPage(token: token)
            XCTFail("Expected the page to stop working")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 410)
        }
    }

    // MARK: Duress

    func testDuressAlertIsBackedUpAndNeverRevealed() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        phone.hold(alarmId: phone.alarm?.id) // texts are handed to the Shortcut right away
        try await sync()                     // then the phone goes quiet before they launch
        let out = await advance(31)
        XCTAssertEqual(recipients(out), ["+14165550101", "+14165550102"])
        XCTAssertFalse(out.contains { $0.body.lowercased().contains("duress") })
        let view = try await adminView()
        XCTAssertEqual(view.alarm?.duress, true, "The demo admin can see it was a duress hold")
    }

    // MARK: Privacy and temporary contacts

    func testExpiredTemporaryContactGetsNothing() async throws {
        let invite = try await engine.inviteTemporary(userId: userId, InviteTemporaryRequest(name: "Riley", phone: "416 555 0199", shareLocation: false), key: nil)
        let token = invite.inviteURL.components(separatedBy: "/t/").last!
        let consent = try await engine.acceptInvite(token: token)
        XCTAssertEqual(consent.state, .active)
        try await sync()
        XCTAssertEqual(phone.temporaryContacts.first?.state, .active)

        phone.startAlarm(source: .admin)
        try await sync()
        XCTAssertTrue(phone.alarm!.recipients.contains { $0.temporary })
        _ = try await engine.expireTemporary(adminId: adminId, userId: userId, ExpireTemporaryRequest(contactId: nil))
        let out = await advance(31)
        XCTAssertFalse(recipients(out).contains("+14165550199"), "An expired contact must not receive new alerts")
        XCTAssertEqual(recipients(out), ["+14165550101", "+14165550102"])
    }

    func testRemovedInvitationLinkStopsWorking() async throws {
        let invite = try await engine.inviteTemporary(userId: userId, InviteTemporaryRequest(name: "Riley", phone: "416 555 0199", shareLocation: true), key: nil)
        let token = invite.inviteURL.components(separatedBy: "/t/").last!
        _ = try await engine.removeTemporary(userId: userId, contactId: invite.contact.id)
        do {
            _ = try await engine.acceptInvite(token: token)
            XCTFail("Expected the invitation to be gone")
        } catch let error as EngineError {
            XCTAssertTrue([404, 410].contains(error.status))
        }
    }

    // MARK: Demo admin

    func testCommandsReachThePhoneAndReportBack() async throws {
        _ = try await engine.sendCommand(adminId: adminId, userId: userId, AdminCommandRequest(kind: .triggerAlarm, countdownSeconds: 15), key: nil)
        var view = try await adminView()
        XCTAssertEqual(view.commands.first?.state, .queued)

        let response = try await sync()
        XCTAssertEqual(response.commands.map(\.kind), [.triggerAlarm])
        view = try await adminView()
        XCTAssertEqual(view.commands.first?.state, .delivered, "The admin sees the command reached the iPhone")

        let command = response.commands[0]
        let result = phone.once(command.id) { phone.startAlarm(source: .admin, countdownSeconds: command.countdownSeconds) }
        try await sync(results: [CommandResult(commandId: command.id, ok: result.ok, message: result.feedback)])
        view = try await adminView()
        XCTAssertEqual(view.commands.first?.state, .done)
        XCTAssertNotNil(view.alarm)
    }

    func testDisableAlarmStopsTheBackupEvenWithoutThePhone() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        _ = try await engine.sendCommand(adminId: adminId, userId: userId, AdminCommandRequest(kind: .disableAlarm), key: nil)
        let out = await advance(120)
        XCTAssertTrue(out.isEmpty)
        try await sync()
        XCTAssertEqual(phone.alarm?.closeReason, .disabled)
    }

    func testResetMakesTheOldRunInert() async throws {
        phone.startAlarm(source: .admin)
        try await sync()
        _ = try await engine.resetDemo(adminId: adminId, userId: userId, key: nil)
        let out = await advance(120)
        XCTAssertTrue(out.isEmpty, "Old deadlines must not fire after a reset")
        let response = try await sync()
        XCTAssertTrue(response.resetRequired)
        phone.reset(runId: response.runId)
        XCTAssertNil(phone.alarm)
        let view = try await adminView()
        XCTAssertNil(view.alarm)
    }

    func testUnpairedAdminIsRefused() async throws {
        let other = try await engine.adminLogin(AdminLoginRequest(secret: "secret", name: "Someone else"))
        do {
            _ = try await engine.sendCommand(adminId: other.adminId, userId: userId, AdminCommandRequest(kind: .triggerAlarm), key: nil)
            XCTFail("Expected a refusal")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 403)
        }
    }

    func testWrongAdminSecretIsRefused() async throws {
        do {
            _ = try await engine.adminLogin(AdminLoginRequest(secret: "nope", name: "x"))
            XCTFail("Expected a refusal")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 403)
        }
    }
}
