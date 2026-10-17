import Foundation
import XCTest
@testable import RippleKit

/// Dose reminders: ask once at each dose time, start a check-in if "Took my
/// meds" doesn't come within the grace period, and never ask late.
final class MedicationTests: XCTestCase {
    var clock: TestClock!
    var recorder: Recorder!
    var coordinator: AlarmCoordinator!
    let toronto = TimeZone(identifier: "America/Toronto")!

    override func setUp() {
        clock = TestClock()
        recorder = Recorder()
        var config = RippleConfig.makeDefault(wearerName: "Alex")
        config.contacts = [PermanentContact(id: "sam", name: "Sam", phone: "416 555 0101", tier: .one)]
        let clock = self.clock!
        coordinator = AlarmCoordinator(config: config, clock: { clock.now })
        coordinator.timeZone = toronto
        coordinator.delegate = recorder
        coordinator.setRunId("run-1")
        coordinator.startMonitoring()
    }

    /// A dose time `minutes` from now, in Toronto time.
    func dose(inMinutes minutes: Int) -> MedicationTime {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = toronto
        let at = clock.now.addingTimeInterval(TimeInterval(minutes * 60))
        let parts = calendar.dateComponents([.hour, .minute], from: at)
        return MedicationTime(hour: parts.hour!, minute: parts.minute!)
    }

    func setDoses(_ times: [MedicationTime], grace: Int = 30) {
        var config = coordinator.config
        config.medicationTimes = times
        config.medicationGraceMinutes = grace
        coordinator.config = config
    }

    func advance(_ seconds: TimeInterval) {
        clock.now = clock.now.addingTimeInterval(seconds)
        coordinator.tick()
    }

    func testAsksAtDoseTimeAndShowsOnWatch() {
        setDoses([dose(inMinutes: 10)])
        advance(9 * 60)
        XCTAssertNil(coordinator.pendingDoseAt)
        XCTAssertNil(coordinator.display().medsDueAt)
        advance(2 * 60)
        XCTAssertNotNil(coordinator.pendingDoseAt)
        let display = coordinator.display()
        XCTAssertEqual(display.mode, .monitoring)
        XCTAssertEqual(display.circleLabel, "Took my meds")
        XCTAssertNotNil(display.medsDueAt)
    }

    func testTookMedsClearsTheReminderAndNoCheckInStarts() {
        setDoses([dose(inMinutes: 1)])
        advance(2 * 60)
        XCTAssertNotNil(coordinator.pendingDoseAt)
        coordinator.handle(WatchAction(kind: .tookMeds, method: .touch, alarmId: nil))
        XCTAssertNil(coordinator.pendingDoseAt)
        XCTAssertNotNil(coordinator.lastMedsTakenAt)
        advance(60 * 60)
        XCTAssertNil(coordinator.visibleAlarm)
        XCTAssertTrue(recorder.sent.isEmpty)
    }

    func testMissedTapStartsACheckInAfterTheGracePeriod() {
        setDoses([dose(inMinutes: 1)], grace: 30)
        advance(2 * 60)
        advance(28 * 60)
        XCTAssertNil(coordinator.visibleAlarm, "still inside the grace period")
        advance(2 * 60)
        XCTAssertEqual(coordinator.display().mode, .checkIn)
        XCTAssertNil(coordinator.pendingDoseAt)
    }

    func testEachDoseIsAskedAboutOnlyOnce() {
        setDoses([dose(inMinutes: 1)])
        advance(2 * 60)
        coordinator.recordMedsTaken()
        advance(5 * 60)
        XCTAssertNil(coordinator.pendingDoseAt, "the same dose isn't asked about again")
    }

    func testADoseThatPassedLongAgoIsNotAskedAboutLate() {
        setDoses([dose(inMinutes: -90)], grace: 30)
        advance(60)
        XCTAssertNil(coordinator.pendingDoseAt)
        advance(60 * 60)
        XCTAssertNil(coordinator.visibleAlarm)
    }

    func testNoRemindersWhileMonitoringIsOff() {
        coordinator.stopMonitoring()
        setDoses([dose(inMinutes: 1)])
        advance(2 * 60)
        XCTAssertNil(coordinator.pendingDoseAt)
    }

    func testNextDoseIsTheSoonestUpcomingTime() {
        setDoses([dose(inMinutes: 120), dose(inMinutes: 30)])
        let next = coordinator.nextDoseAt!
        XCTAssertEqual(next.timeIntervalSince(clock.now), 30 * 60, accuracy: 60)
    }

    func testSettingsWithoutMedicationStillLoad() throws {
        let old = #"{"version":3,"wearerName":"Alex","contacts":[],"helpCardEnabled":false,"helpCard":"","checkInIntervalMinutes":0,"countdownSeconds":15,"ackWindowSeconds":15,"doubleTapEnabled":true,"voiceEnabled":false,"voicePhrase":"x","shortcutName":"Ripple Alert"}"#
        let config = try RippleJSON.decoder.decode(RippleConfig.self, from: Data(old.utf8))
        XCTAssertEqual(config.medicationTimes, [])
        XCTAssertEqual(config.medicationGraceMinutes, 30)
    }
}
