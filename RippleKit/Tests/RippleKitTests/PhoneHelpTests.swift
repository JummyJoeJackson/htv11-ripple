import Foundation
import XCTest
@testable import RippleKit

final class PhoneHelpTests: XCTestCase {
    private var clock: TestClock!
    private var recorder: Recorder!
    private var coordinator: AlarmCoordinator!

    override func setUp() {
        clock = TestClock()
        recorder = Recorder()
        var config = RippleConfig.makeDefault(wearerName: "Alex")
        config.contacts = [
            PermanentContact(id: "sam", name: "Sam", phone: "416 555 0101", tier: .one, shareLocation: false),
            PermanentContact(id: "pat", name: "Pat", phone: "416 555 0103", tier: .two, shareLocation: false),
        ]
        let clock = self.clock!
        coordinator = AlarmCoordinator(config: config, clock: { clock.now })
        coordinator.delegate = recorder
    }

    func testPhoneHelpNotifiesBothTiersImmediatelyWithMonitoringOff() {
        XCTAssertFalse(coordinator.monitoring)
        XCTAssertTrue(coordinator.requestHelpForAllContacts().ok)
        XCTAssertEqual(Set(recorder.sent.map(\.recipientId)), ["sam", "pat"])
        XCTAssertEqual(recorder.sent.count, 2)
        XCTAssertEqual(coordinator.alarm?.alertedAt, clock.now)
        XCTAssertEqual(coordinator.alarm?.escalatedAt, clock.now)
    }

    func testOnlyActiveTemporaryContactsReceivePhoneHelp() {
        coordinator.temporaryContacts = [
            temporaryContact(id: "active", state: .active, expiresIn: 3600),
            temporaryContact(id: "expired", state: .active, expiresIn: -1),
            temporaryContact(id: "invited", state: .invited, expiresIn: 3600),
            temporaryContact(id: "removed", state: .removed, expiresIn: 3600),
        ]
        coordinator.requestHelpForAllContacts()
        XCTAssertEqual(Set(recorder.sent.map(\.recipientId)), ["sam", "pat", "active"])
    }

    func testPhoneHelpInterruptsCountdownAndNotifiesBothTiers() {
        coordinator.startMonitoring()
        coordinator.startAlarm(source: .admin)
        let alarmId = coordinator.alarm?.id
        XCTAssertTrue(recorder.sent.isEmpty)

        coordinator.requestHelpForAllContacts()
        XCTAssertEqual(coordinator.alarm?.id, alarmId)
        XCTAssertEqual(Set(recorder.sent.map(\.recipientId)), ["sam", "pat"])
        XCTAssertTrue(recorder.sent.allSatisfy { $0.text.contains("asked for help") })
        XCTAssertFalse(recorder.sent.contains { $0.text.contains("did not respond") })
    }

    func testRepeatedPhoneHelpDoesNotDuplicateAlerts() {
        coordinator.requestHelp()
        let alarmId = coordinator.alarm?.id
        coordinator.requestHelpForAllContacts()
        coordinator.requestHelpForAllContacts()
        clock.now = clock.now.addingTimeInterval(60)
        coordinator.tick()

        XCTAssertEqual(coordinator.alarm?.id, alarmId)
        XCTAssertEqual(recorder.sent.count, 2)
        XCTAssertEqual(Set(recorder.sent.map(\.recipientId)), ["sam", "pat"])
    }

    func testEachContactCanAcceptPhoneHelpUsingTheirOwnReplyCode() throws {
        coordinator.requestHelpForAllContacts()
        let recipients = try XCTUnwrap(coordinator.alarm?.recipients)
        XCTAssertEqual(Set(recipients.compactMap(\.acceptCode)).count, 2)
        for recipient in recipients {
            let code = try XCTUnwrap(recipient.acceptCode)
            let message = try XCTUnwrap(recorder.sent.first { $0.recipientId == recipient.id })
            XCTAssertEqual(message.phone, recipient.phone)
            XCTAssertTrue(message.text.contains("Reply \"Ripple accept \(code)\""))
        }
        coordinator.recordResults(ids: recorder.sent.map(\.id), status: .submitted, detail: nil)
        let pat = try XCTUnwrap(recipients.first { $0.id == "pat" })
        let code = try XCTUnwrap(pat.acceptCode)
        XCTAssertTrue(coordinator.acceptReply(text: "Ripple accept \(code)", from: pat.phone).ok)
        XCTAssertEqual(coordinator.alarm?.acknowledgment?.recipientId, "pat")
        XCTAssertEqual(coordinator.display().mode, .responding)
        XCTAssertEqual(recorder.sent.filter { $0.kind == .responding }.map(\.recipientId), ["sam"])

        let count = recorder.sent.count
        coordinator.requestHelpForAllContacts()
        clock.now = clock.now.addingTimeInterval(60)
        coordinator.tick()
        XCTAssertEqual(recorder.sent.count, count, "Accepting stops further alerts")
    }

    func testPhoneHelpWithOnlyTierTwoDoesNotSendTwice() {
        var config = coordinator.config
        config.contacts.removeAll { $0.tier == .one }
        coordinator.config = config
        coordinator.requestHelpForAllContacts()
        XCTAssertEqual(recorder.sent.map(\.recipientId), ["pat"])
        XCTAssertEqual(recorder.sent.first?.kind, .alert)
    }

    private func temporaryContact(id: String, state: TemporaryContactState, expiresIn: TimeInterval) -> TemporaryContactView {
        TemporaryContactView(
            id: id, name: id, phone: "+14165550199", shareLocation: false, state: state,
            invitedAt: clock.now, consentAt: clock.now, expiresAt: clock.now.addingTimeInterval(expiresIn)
        )
    }
}
