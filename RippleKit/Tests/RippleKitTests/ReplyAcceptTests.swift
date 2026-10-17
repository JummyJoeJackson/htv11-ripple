import Foundation
import XCTest
@testable import RippleKit

/// Text replies acknowledge alerts through the wearer's Messages automation.
final class ReplyAcceptTests: XCTestCase {
    var clock: TestClock!
    var recorder: Recorder!
    var coordinator: AlarmCoordinator!

    let sam = PermanentContact(id: "sam", name: "Sam", phone: "416 555 0101", tier: .one, shareLocation: false)
    let jo = PermanentContact(id: "jo", name: "Jo", phone: "416 555 0102", tier: .one, shareLocation: false)
    let pat = PermanentContact(id: "pat", name: "Pat", phone: "416 555 0103", tier: .two, shareLocation: false)

    override func setUp() {
        clock = TestClock()
        recorder = Recorder()
        var config = RippleConfig.makeDefault(wearerName: "Alex")
        config.contacts = [sam, jo, pat]
        let clock = self.clock!
        coordinator = AlarmCoordinator(config: config, clock: { clock.now })
        coordinator.delegate = recorder
        coordinator.setRunId("run-1")
        coordinator.startMonitoring()
    }

    /// Starts an alarm, lets it run out, and marks the Tier 1 alerts as sent.
    func alertTierOne() {
        coordinator.startAlarm(source: .admin)
        clock.now = clock.now.addingTimeInterval(15)
        coordinator.tick()
        coordinator.recordResults(ids: recorder.sent.map(\.id), status: .submitted, detail: nil)
    }

    func code(for id: String) -> String {
        coordinator.alarm!.recipients.first { $0.id == id }!.acceptCode!
    }

    // MARK: Parsing

    func testParsesTheCodeLoosely() {
        XCTAssertEqual(ReplyCode.acceptCode(in: "RIPPLE ACCEPT 4821"), "4821")
        XCTAssertEqual(ReplyCode.acceptCode(in: "ripple accept 4821"), "4821")
        XCTAssertEqual(ReplyCode.acceptCode(in: "Ripple  Accept: 4821!"), "4821")
        XCTAssertEqual(ReplyCode.acceptCode(in: "On my way. RIPPLE-ACCEPT 4821"), "4821")
        XCTAssertEqual(ReplyCode.acceptCode(in: "rippleaccept4821"), "4821")
    }

    func testRejectsRepliesWithoutAValidCode() {
        XCTAssertNil(ReplyCode.acceptCode(in: "On my way"))
        XCTAssertNil(ReplyCode.acceptCode(in: "ripple accept"))
        XCTAssertNil(ReplyCode.acceptCode(in: "ripple accept 482"))
        XCTAssertNil(ReplyCode.acceptCode(in: "ripple accept 48210"))
        XCTAssertNil(ReplyCode.acceptCode(in: "accept 4821"))
    }

    // MARK: Codes in texts

    func testEveryRecipientGetsTheirOwnCodeInTheirTexts() {
        coordinator.startAlarm(source: .admin)
        let recipients = coordinator.alarm!.recipients
        let codes = recipients.compactMap(\.acceptCode)
        XCTAssertEqual(codes.count, 3)
        XCTAssertEqual(Set(codes).count, 3, "Codes are unique within an alarm")
        for recipient in recipients {
            let instruction = "Reply \"Ripple accept \(recipient.acceptCode!)\" if you are able to check in on Alex."
            XCTAssertTrue(recipient.alertText.hasSuffix("\n\n" + instruction))
            XCTAssertTrue(recipient.escalationText.hasSuffix("\n\n" + instruction))
            XCTAssertFalse(recipient.alertText.contains("http://ripple.test/a/"))
            XCTAssertFalse(recipient.escalationText.contains("http://ripple.test/a/"))
        }
    }

    func testHelpRequestTextsCarryTheCodeToo() {
        coordinator.requestHelp()
        let sam = coordinator.alarm!.recipients.first { $0.id == "sam" }!
        XCTAssertTrue(sam.alertText.contains("asked for help"))
        let instruction = "Reply \"Ripple accept \(sam.acceptCode!)\" if you are able to check in on Alex."
        XCTAssertTrue(sam.alertText.hasSuffix("\n\n" + instruction))
        XCTAssertTrue(sam.escalationText.hasSuffix("\n\n" + instruction))
    }

    // MARK: Accepting

    func testReplyRecordsResponderAndStopsEscalation() {
        alertTierOne()
        let result = coordinator.acceptReply(text: "Ripple accept \(code(for: "sam"))", from: "+14165550101")
        XCTAssertEqual(result, ActionResult(ok: true, feedback: "Sam is responding."))
        XCTAssertEqual(coordinator.alarm?.acknowledgment?.recipientId, "sam")
        XCTAssertEqual(coordinator.display().mode, .responding)
        XCTAssertEqual(coordinator.display().status, "Sam is responding")
        XCTAssertEqual(recorder.sent.filter { $0.kind == .responding }.map(\.recipientId), ["jo"],
                       "Everyone else already texted hears who is checking")

        clock.now = clock.now.addingTimeInterval(60)
        coordinator.tick()
        XCTAssertTrue(recorder.sent.filter { $0.kind == .escalation }.isEmpty, "No Tier 2 once someone accepted")
    }

    func testSenderNameInsteadOfNumberIsFine() {
        alertTierOne()
        let result = coordinator.acceptReply(text: "RIPPLE ACCEPT \(code(for: "jo"))", from: "Jo")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(coordinator.alarm?.acknowledgment?.name, "Jo")
    }

    func testForwardedCodeFromAnotherNumberIsRefused() {
        alertTierOne()
        let result = coordinator.acceptReply(text: "RIPPLE ACCEPT \(code(for: "sam"))", from: "+14165550199")
        XCTAssertFalse(result.ok)
        XCTAssertNil(coordinator.alarm?.acknowledgment)
    }

    func testCodeOfSomeoneNotYetTextedIsRefused() {
        alertTierOne()
        let result = coordinator.acceptReply(text: "RIPPLE ACCEPT \(code(for: "pat"))")
        XCTAssertFalse(result.ok, "Pat is Tier 2 and hasn't been texted yet")
        XCTAssertNil(coordinator.alarm?.acknowledgment)
    }

    func testWrongCodeAndClosedAlarmAreIgnored() {
        alertTierOne()
        let samCode = code(for: "sam")
        let wrong = samCode == "1234" ? "4321" : "1234"
        XCTAssertFalse(coordinator.acceptReply(text: "RIPPLE ACCEPT \(wrong)").ok)
        coordinator.dismiss(alarmId: coordinator.alarm?.id)
        XCTAssertFalse(coordinator.acceptReply(text: "RIPPLE ACCEPT \(samCode)").ok, "A late reply can't reopen a closed alert")
    }

    func testSecondAcceptKeepsTheFirstResponder() {
        alertTierOne()
        coordinator.acceptReply(text: "RIPPLE ACCEPT \(code(for: "sam"))")
        let second = coordinator.acceptReply(text: "RIPPLE ACCEPT \(code(for: "jo"))")
        XCTAssertEqual(second.feedback, "Sam is already responding.")
        XCTAssertEqual(coordinator.alarm?.acknowledgment?.name, "Sam")
    }

    func testDuressAcceptStaysOutOfSight() {
        coordinator.startAlarm(source: .admin)
        coordinator.hold(alarmId: coordinator.alarm?.id)
        coordinator.recordResults(ids: recorder.sent.map(\.id), status: .submitted, detail: nil)
        let result = coordinator.acceptReply(text: "RIPPLE ACCEPT \(code(for: "sam"))")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.feedback, "", "Nothing for the iPhone to show")
        XCTAssertEqual(coordinator.alarm?.acknowledgment?.name, "Sam", "Recorded, so escalation stops")
        XCTAssertEqual(coordinator.display().mode, .monitoring, "The Watch still looks like a normal dismissal")
    }

    func testAlarmsSavedBeforeReplyCodesStillLoad() throws {
        coordinator.startAlarm(source: .admin)
        var json = try JSONSerialization.jsonObject(with: RippleJSON.encoder.encode(coordinator.alarm!)) as! [String: Any]
        json["recipients"] = (json["recipients"] as! [[String: Any]]).map { recipient in
            var old = recipient
            old.removeValue(forKey: "acceptCode")
            old["ackToken"] = "retired-link-token"
            return old
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        let alarm = try RippleJSON.decoder.decode(Alarm.self, from: data)
        XCTAssertNil(alarm.recipients.first?.acceptCode)
        let saved = try JSONSerialization.jsonObject(with: RippleJSON.encoder.encode(alarm)) as! [String: Any]
        XCTAssertTrue((saved["recipients"] as! [[String: Any]]).allSatisfy { $0["ackToken"] == nil })
    }
}
