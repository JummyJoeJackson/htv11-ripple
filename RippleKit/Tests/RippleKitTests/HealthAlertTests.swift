import Foundation
import XCTest
@testable import RippleKit

/// Apple Watch alerts from Apple Health: a fall or a heart alert starts an
/// ordinary check-in. Apple detects; Ripple only asks and brings people.
final class HealthAlertTests: XCTestCase {
    var clock: TestClock!
    var recorder: Recorder!
    var coordinator: AlarmCoordinator!

    let sam = PermanentContact(id: "sam", name: "Sam", phone: "416 555 0101", tier: .one, shareLocation: false)
    let pat = PermanentContact(id: "pat", name: "Pat", phone: "416 555 0103", tier: .two, shareLocation: false)

    override func setUp() {
        clock = TestClock()
        recorder = Recorder()
        var config = RippleConfig.makeDefault(wearerName: "Alex")
        config.contacts = [sam, pat]
        let clock = self.clock!
        coordinator = AlarmCoordinator(config: config, serverBaseURL: "http://ripple.test", clock: { clock.now })
        coordinator.timeZone = TimeZone(identifier: "America/Toronto")!
        coordinator.delegate = recorder
        coordinator.setRunId("run-1")
        coordinator.startMonitoring()
    }

    func advance(_ seconds: TimeInterval) {
        clock.now = clock.now.addingTimeInterval(seconds)
        coordinator.tick()
    }

    func text(_ kind: MessageKind) -> String? {
        recorder.sent.first { $0.kind == kind }?.text
    }

    func testFallStartsANormalCheckIn() {
        XCTAssertTrue(coordinator.healthAlert(.fall).ok)
        XCTAssertEqual(coordinator.alarm?.source, .fall)
        XCTAssertEqual(coordinator.display().mode, .checkIn)
        XCTAssertEqual(coordinator.display().status, "Fall reported")
        XCTAssertTrue(recorder.sent.isEmpty, "Nothing is texted while the wearer can still answer")
        coordinator.dismiss(alarmId: coordinator.alarm?.id)
        advance(60)
        XCTAssertTrue(recorder.sent.isEmpty)
    }

    func testTextsSayWhichAppleAlertItWas() {
        coordinator.healthAlert(.fall)
        advance(15)
        XCTAssertTrue(text(.alert)?.hasPrefix("RIPPLE ALERT: Alex's Apple Watch reported a fall, and they did not respond to a check-in at") == true)
        coordinator.recordResults(ids: recorder.sent.map(\.id), status: .submitted, detail: nil)
        advance(15)
        XCTAssertTrue(text(.escalation)?.contains("Apple Watch reported a fall at") == true)
        XCTAssertTrue(text(.escalation)?.contains("no one has confirmed yet") == true)
    }

    func testHeartAlertWording() {
        coordinator.healthAlert(.heart)
        XCTAssertEqual(coordinator.alarm?.source, .heartAlert)
        XCTAssertEqual(coordinator.display().status, "Heart alert")
        advance(15)
        XCTAssertTrue(text(.alert)?.contains("Apple Watch reported a heart alert") == true)
    }

    func testOrdinaryCheckInTextsAreUnchanged() {
        coordinator.startAlarm(source: .admin)
        XCTAssertEqual(coordinator.display().status, "Check in")
        advance(15)
        XCTAssertTrue(text(.alert)?.hasPrefix("RIPPLE ALERT: Alex did not respond to their Watch check-in at") == true)
        XCTAssertFalse(text(.alert)?.contains("Apple Watch reported") == true)
    }

    func testAlertDuringAnOpenAlarmChangesNothing() {
        coordinator.startAlarm(source: .admin)
        let alarmId = coordinator.alarm?.id
        XCTAssertTrue(coordinator.healthAlert(.fall).ok)
        XCTAssertEqual(coordinator.alarm?.id, alarmId)
        XCTAssertEqual(coordinator.alarm?.source, .admin)
    }

    func testDuressAlarmStaysHidden() {
        coordinator.startAlarm(source: .admin)
        coordinator.hold(alarmId: coordinator.alarm?.id)
        XCTAssertEqual(coordinator.healthAlert(.heart).feedback, "", "Nothing on screen hints that a duress alarm is open")
        XCTAssertEqual(coordinator.display().mode, .monitoring)
    }

    func testMonitoringOffDoesNothing() {
        coordinator.stopMonitoring()
        XCTAssertFalse(coordinator.healthAlert(.fall).ok)
        XCTAssertNil(coordinator.alarm)
    }

    func testHealthAlertsAreOptInAndOlderSettingsLoad() throws {
        var config = RippleConfig.makeDefault(wearerName: "Alex")
        XCTAssertTrue(config.healthAlerts.isEmpty, "They need Apple Health permission, so they start off")
        config.healthFallsEnabled = true
        XCTAssertEqual(config.healthAlerts, [.fall])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: RippleJSON.encoder.encode(config)) as? [String: Any])
        json.removeValue(forKey: "healthFallsEnabled")
        json.removeValue(forKey: "healthHeartEnabled")
        let loaded = try RippleJSON.decoder.decode(RippleConfig.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(loaded.healthAlerts.isEmpty, "Settings saved before health alerts existed load with them off")
    }

    func testSimulatedCommandCarriesItsAlert() throws {
        let command = DeviceCommand(id: "c1", kind: .simulateHealthAlert, countdownSeconds: nil, ackWindowSeconds: nil,
                                    durationSeconds: nil, createdAt: clock.now, healthAlert: .heart)
        let decoded = try RippleJSON.decoder.decode(DeviceCommand.self, from: RippleJSON.encoder.encode(command))
        XCTAssertEqual(decoded.kind, .simulateHealthAlert)
        XCTAssertEqual(decoded.healthAlert, .heart)
    }
}
