import Foundation
import XCTest
@testable import RippleKit

final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

final class Recorder: AlarmCoordinatorDelegate {
    var sent: [OutMessage] = []
    func coordinator(_ coordinator: AlarmCoordinator, send messages: [OutMessage]) { sent += messages }
    func coordinatorDidChange(_ coordinator: AlarmCoordinator) {}
}

final class AlarmCoordinatorTests: XCTestCase {
    var clock: TestClock!
    var recorder: Recorder!
    var coordinator: AlarmCoordinator!

    let sam = PermanentContact(id: "sam", name: "Sam", phone: "416 555 0101", tier: .one, shareLocation: true)
    let jo = PermanentContact(id: "jo", name: "Jo", phone: "416 555 0102", tier: .one, shareLocation: false)
    let pat = PermanentContact(id: "pat", name: "Pat", phone: "416 555 0103", tier: .two, shareLocation: false)

    override func setUp() {
        clock = TestClock()
        recorder = Recorder()
        var config = RippleConfig.makeDefault(wearerName: "Alex")
        config.contacts = [sam, jo, pat]
        let clock = self.clock!
        coordinator = AlarmCoordinator(config: config, clock: { clock.now })
        coordinator.timeZone = TimeZone(identifier: "America/Toronto")!
        coordinator.delegate = recorder
        coordinator.setRunId("run-1")
        coordinator.startMonitoring()
    }

    // MARK: Helpers

    func advance(_ seconds: TimeInterval) {
        clock.now = clock.now.addingTimeInterval(seconds)
        coordinator.tick()
    }

    /// Pretends the Shortcuts app sent everything handed to it so far.
    func submitAll() {
        coordinator.recordResults(ids: recorder.sent.map(\.id), status: .submitted, detail: nil)
    }

    func sent(_ kind: MessageKind) -> [String] {
        recorder.sent.filter { $0.kind == kind }.map(\.recipientId)
    }

    // MARK: Safe

    func testDismissDuringCountdownSendsNothing() {
        coordinator.startAlarm(source: .admin)
        XCTAssertEqual(coordinator.display().mode, .checkIn)
        let result = coordinator.dismiss(alarmId: coordinator.alarm?.id)
        XCTAssertEqual(result.feedback, "Dismissed")
        advance(60)
        XCTAssertTrue(recorder.sent.isEmpty)
        XCTAssertEqual(coordinator.display().mode, .monitoring, "Monitoring stays on after a dismissal")
        XCTAssertEqual(coordinator.alarm?.closeReason, .dismissed)
    }

    // MARK: No response and privacy

    func testTimeoutTextsTierOneWithLocationOnlyWhereAllowed() {
        var config = coordinator.config
        config.helpCardEnabled = true
        config.helpCard = "My medication is in my left pocket."
        coordinator.config = config
        coordinator.startAlarm(source: .admin)
        let fix = LocationFix(latitude: 43.78, longitude: -79.19, accuracyMeters: 20, capturedAt: clock.now)
        coordinator.updateLocation(fix, alarmId: coordinator.alarm!.id)

        advance(15)
        XCTAssertEqual(Set(sent(.alert)), ["sam", "jo"], "Only Tier 1 gets the first alert")
        let samText = recorder.sent.first { $0.recipientId == "sam" }!.text
        let joText = recorder.sent.first { $0.recipientId == "jo" }!.text
        XCTAssertTrue(samText.hasSuffix("\n\nLocation: \(fix.mapURL)"), "The location URL is last for Messages previews")
        XCTAssertFalse(joText.contains("maps.apple.com"), "Location only for contacts with sharing on")
        XCTAssertTrue(samText.contains("\n\nNote from Alex: My medication is in my left pocket.\n\nReply"))
        XCTAssertFalse(samText.contains("http://ripple.test/a/"))
        XCTAssertTrue(samText.hasPrefix("RIPPLE ALERT: Alex did not respond"))
        XCTAssertEqual(coordinator.display().mode, .alertSent)
    }

    func testHelpCardIsOffByDefault() {
        var config = coordinator.config
        config.helpCard = "Should not appear"
        coordinator.config = config
        coordinator.startAlarm(source: .admin)
        advance(15)
        XCTAssertFalse(recorder.sent.contains { $0.text.contains("Should not appear") })
    }

    func testExpiredTemporaryContactGetsNothing() {
        coordinator.temporaryContacts = [TemporaryContactView(
            id: "temp", name: "Riley", phone: "+14165550199", shareLocation: false, state: .active,
            invitedAt: clock.now, consentAt: clock.now, expiresAt: clock.now.addingTimeInterval(10)
        )]
        coordinator.startAlarm(source: .admin)
        XCTAssertTrue(coordinator.alarm!.recipients.contains { $0.id == "temp" }, "Active temporary contacts join Tier 1")
        advance(15) // the temporary session expired 5 s before the deadline
        XCTAssertFalse(sent(.alert).contains("temp"))
        XCTAssertEqual(Set(sent(.alert)), ["sam", "jo"])
    }

    func testActiveTemporaryContactIsInTierOne() {
        coordinator.temporaryContacts = [TemporaryContactView(
            id: "temp", name: "Riley", phone: "+14165550199", shareLocation: false, state: .active,
            invitedAt: clock.now, consentAt: clock.now, expiresAt: clock.now.addingTimeInterval(3600)
        )]
        coordinator.startAlarm(source: .admin)
        advance(15)
        XCTAssertTrue(sent(.alert).contains("temp"))
    }

    // MARK: Unacknowledged alert

    func testAckWindowEscalatesToTierTwo() {
        coordinator.startAlarm(source: .admin)
        advance(15)
        submitAll()
        advance(14)
        XCTAssertTrue(sent(.escalation).isEmpty)
        advance(1)
        XCTAssertEqual(sent(.escalation), ["pat"])
        XCTAssertTrue(recorder.sent.first { $0.kind == .escalation }!.text.contains("no one has confirmed yet"))
    }

    func testAcknowledgmentTellsOthersAndStopsEscalation() {
        coordinator.startAlarm(source: .admin)
        advance(15)
        submitAll()
        coordinator.applyAcknowledgment(Acknowledgment(recipientId: "sam", name: "Sam", at: clock.now))
        XCTAssertEqual(sent(.responding), ["jo"], "Everyone else already texted hears who is checking")
        XCTAssertEqual(recorder.sent.first { $0.kind == .responding }!.text, "Ripple: Sam is checking on Alex.")
        XCTAssertEqual(coordinator.display().mode, .responding)
        XCTAssertEqual(coordinator.display().status, "Sam is responding")
        advance(60)
        XCTAssertTrue(sent(.escalation).isEmpty)
    }

    func testTierTwoGetsTheAlertWhenTierOneIsEmpty() {
        var config = coordinator.config
        config.contacts = [pat]
        coordinator.config = config
        coordinator.startAlarm(source: .admin)
        advance(15)
        XCTAssertEqual(sent(.alert), ["pat"])
        submitAll()
        advance(60)
        XCTAssertTrue(sent(.escalation).isEmpty)
    }

    // MARK: False alarm

    func testOkayNowTextsEveryoneAlreadyTexted() {
        coordinator.startAlarm(source: .admin)
        advance(15)
        submitAll()
        advance(15)
        submitAll()
        let result = coordinator.dismiss(alarmId: coordinator.alarm?.id)
        XCTAssertEqual(result.feedback, "Dismissed")
        XCTAssertEqual(Set(sent(.okayNow)), ["sam", "jo", "pat"])
        XCTAssertTrue(recorder.sent.first { $0.kind == .okayNow }!.text.hasPrefix("Ripple: Alex says they're okay now"))
        XCTAssertEqual(coordinator.alarm?.closeReason, .okayNow)
        XCTAssertEqual(coordinator.display().mode, .monitoring)
    }

    func testOkayNowCancelsMessagesNotYetSent() {
        coordinator.startAlarm(source: .admin)
        advance(15)
        // Sam's alert went out; Jo's is still waiting for the Shortcuts app.
        let samId = recorder.sent.first { $0.recipientId == "sam" }!.id
        let joId = recorder.sent.first { $0.recipientId == "jo" }!.id
        coordinator.recordResults(ids: [samId], status: .submitted, detail: nil)
        coordinator.dismiss(alarmId: coordinator.alarm?.id)
        XCTAssertEqual(coordinator.message(joId)?.status, .cancelled)
        XCTAssertEqual(sent(.okayNow), ["sam"])
    }

    // MARK: Duress

    func testDuressDuringCountdownLooksDismissedButAlerts() {
        coordinator.startAlarm(source: .admin)
        let alarmId = coordinator.alarm!.id
        let result = coordinator.hold(alarmId: alarmId)
        XCTAssertEqual(result, ActionResult(ok: true, feedback: "Dismissed"), "Identical to a real dismissal")
        XCTAssertEqual(coordinator.display().mode, .monitoring)
        XCTAssertNil(coordinator.visibleAlarm)
        XCTAssertEqual(Set(sent(.alert)), ["sam", "jo"], "The alert still sends, right away")
        XCTAssertFalse(recorder.sent.contains { $0.text.lowercased().contains("duress") }, "Texts never reveal duress")
    }

    func testDuressAfterAlertKeepsEscalatingOutOfSight() {
        coordinator.startAlarm(source: .admin)
        advance(15)
        submitAll()
        coordinator.hold(alarmId: coordinator.alarm?.id)
        XCTAssertEqual(coordinator.display().mode, .monitoring)
        advance(15)
        XCTAssertEqual(sent(.escalation), ["pat"])
        XCTAssertTrue(sent(.okayNow).isEmpty)
        coordinator.applyAcknowledgment(Acknowledgment(recipientId: "pat", name: "Pat", at: clock.now))
        XCTAssertEqual(coordinator.display().mode, .monitoring, "The Watch never shows a responder for a duress alarm")
    }

    // MARK: Help combo

    func testHelpTextsTierOneRightAway() {
        let result = coordinator.handle(WatchAction(kind: .help, method: .combo, alarmId: nil))
        XCTAssertEqual(result.feedback, "Help requested")
        XCTAssertEqual(Set(sent(.alert)), ["sam", "jo"], "No countdown: the wearer asked")
        XCTAssertTrue(recorder.sent.first { $0.kind == .alert }!.text.hasPrefix("RIPPLE ALERT: Alex asked for help from their Watch at"))
        XCTAssertEqual(coordinator.alarm?.source, .help)
        XCTAssertEqual(coordinator.display().mode, .alertSent)
        XCTAssertEqual(coordinator.display().status, "Help requested")
    }

    func testHelpWorksWithMonitoringOff() {
        coordinator.stopMonitoring()
        coordinator.requestHelp()
        XCTAssertEqual(Set(sent(.alert)), ["sam", "jo"])
        submitAll()
        coordinator.dismiss(alarmId: coordinator.alarm?.id)
        XCTAssertEqual(Set(sent(.okayNow)), ["sam", "jo"], "I'm okay now still follows up")
        XCTAssertEqual(coordinator.display().mode, .off, "Asking for help doesn't turn monitoring on")
    }

    func testHelpDuringCountdownSendsNow() {
        coordinator.startAlarm(source: .admin)
        advance(3)
        coordinator.requestHelp()
        XCTAssertEqual(Set(sent(.alert)), ["sam", "jo"])
        XCTAssertTrue(recorder.sent.first { $0.kind == .alert }!.text.contains("asked for help"))
    }

    func testHelpAfterTheAlertEscalatesWithoutWaiting() {
        coordinator.startAlarm(source: .admin)
        advance(15)
        submitAll()
        coordinator.requestHelp()
        XCTAssertEqual(sent(.escalation), ["pat"], "Nobody has confirmed, so Tier 2 is texted now")
        XCTAssertTrue(recorder.sent.first { $0.kind == .escalation }!.text.contains("asked for help"))
        advance(60)
        XCTAssertEqual(sent(.escalation), ["pat"], "Tier 2 is texted once")
    }

    func testHelpAfterSomeoneRespondsSendsNothingNew() {
        coordinator.startAlarm(source: .admin)
        advance(15)
        submitAll()
        coordinator.applyAcknowledgment(Acknowledgment(recipientId: "sam", name: "Sam", at: clock.now))
        let before = recorder.sent.count
        XCTAssertEqual(coordinator.requestHelp().feedback, "Sam is responding")
        XCTAssertEqual(recorder.sent.count, before)
    }

    func testSettingsSavedBeforeCombosStillLoad() throws {
        var json = try JSONSerialization.jsonObject(with: RippleJSON.encoder.encode(coordinator.config)) as! [String: Any]
        json["combosEnabled"] = nil
        let old = try JSONSerialization.data(withJSONObject: json)
        let loaded = try RippleJSON.decoder.decode(RippleConfig.self, from: old)
        XCTAssertEqual(loaded.contacts.count, 3, "Updating the app keeps the wearer's contacts")
        XCTAssertTrue(loaded.combosEnabled)
    }

    // MARK: Connectivity failure

    func testBackupSendsAreNotRepeatedByThePhone() {
        coordinator.startAlarm(source: .admin)
        let alarm = coordinator.alarm!
        clock.now = clock.now.addingTimeInterval(50)
        let backups = alarm.recipients.filter { $0.tier == .one }.map { recipient -> OutMessage in
            var message = OutMessage(alarmId: alarm.id, recipientId: recipient.id, recipientName: recipient.name, phone: recipient.phone,
                                     kind: .alert, text: recipient.alertText + MessageTemplates.backupNote, status: .submitted,
                                     path: .backup, createdAt: clock.now)
            message.updatedAt = clock.now
            return message
        }
        coordinator.applyFeedback(AlarmFeedback(alarmId: alarm.id, acknowledgment: nil, backupMessages: backups, closedByAdmin: false))
        coordinator.tick()
        XCTAssertTrue(sent(.alert).isEmpty, "The phone doesn't resend what the backup already sent")
        XCTAssertEqual(coordinator.alarm?.phase, .alerted)
        XCTAssertEqual(coordinator.alarm?.messages.filter { $0.path == .backup }.count, 2)
    }

    func testAdminCloseFromBackendClosesAlarm() {
        coordinator.startAlarm(source: .admin)
        let id = coordinator.alarm!.id
        coordinator.applyFeedback(AlarmFeedback(alarmId: id, acknowledgment: nil, backupMessages: [], closedByAdmin: true))
        XCTAssertEqual(coordinator.alarm?.closeReason, .disabled)
        advance(30)
        XCTAssertTrue(recorder.sent.isEmpty)
    }

    // MARK: Guards

    func testOnlyOneAlarmAtATimeAndRepeatedTapsAreIgnored() {
        XCTAssertTrue(coordinator.startAlarm(source: .admin).ok)
        XCTAssertFalse(coordinator.startAlarm(source: .admin).ok)
        let action = WatchAction(kind: .dismiss, alarmId: coordinator.alarm?.id)
        coordinator.handle(action)
        coordinator.startAlarm(source: .admin)
        let second = coordinator.alarm!.id
        coordinator.handle(action) // the same tap delivered again
        XCTAssertEqual(coordinator.alarm?.id, second)
        XCTAssertTrue(coordinator.alarm!.isOpen, "A repeated tap must not dismiss the next alarm")
    }

    func testStopIsRefusedDuringAVisibleAlarm() {
        coordinator.startAlarm(source: .admin)
        XCTAssertFalse(coordinator.stopMonitoring().ok)
        coordinator.dismiss(alarmId: coordinator.alarm?.id)
        XCTAssertTrue(coordinator.stopMonitoring().ok)
        XCTAssertEqual(coordinator.display().mode, .off)
        XCTAssertFalse(coordinator.startAlarm(source: .admin).ok, "No alarms while monitoring is off")
    }

    func testResetClearsEverything() {
        coordinator.startAlarm(source: .admin)
        coordinator.reset(runId: "run-2")
        XCTAssertNil(coordinator.alarm)
        advance(60)
        XCTAssertTrue(recorder.sent.isEmpty, "Nothing from the old run fires")
        XCTAssertEqual(coordinator.runId, "run-2")
    }

    func testCheckInTimerStartsAlarms() {
        var config = coordinator.config
        config.checkInIntervalMinutes = 1
        coordinator.config = config
        coordinator.stopMonitoring()
        coordinator.startMonitoring()
        advance(59)
        XCTAssertNil(coordinator.alarm)
        advance(1)
        XCTAssertEqual(coordinator.alarm?.source, .timer)
    }
}
