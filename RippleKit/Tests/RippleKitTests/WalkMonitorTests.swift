import Foundation
import XCTest
@testable import RippleKit

final class WalkMonitorTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// Steady walking: about two steps a second, reported every 3 seconds.
    func walk(_ monitor: inout WalkMonitor, from: TimeInterval, to: TimeInterval) {
        var t = from
        while t <= to {
            monitor.update(totalSteps: monitor.steps + 6, at: at(t))
            XCTAssertFalse(monitor.checkStopped(at: at(t)), "Walking never counts as a stop")
            t += 3
        }
    }

    func testStandingStillFromTheStartDoesNothing() {
        var monitor = WalkMonitor(stopAfter: 20)
        XCTAssertFalse(monitor.checkStopped(at: at(600)))
        monitor.update(totalSteps: 4, at: at(5))
        XCTAssertFalse(monitor.checkStopped(at: at(600)), "A few shuffled steps aren't a walk")
    }

    func testStoppingAfterWalkingChecksInOnce() {
        var monitor = WalkMonitor(stopAfter: 20)
        walk(&monitor, from: 0, to: 30)
        let lastStep = monitor.lastStepAt!
        XCTAssertFalse(monitor.checkStopped(at: lastStep.addingTimeInterval(19)))
        XCTAssertTrue(monitor.checkStopped(at: lastStep.addingTimeInterval(20)))
        XCTAssertFalse(monitor.checkStopped(at: lastStep.addingTimeInterval(120)), "Still stopped: no second check-in")
    }

    func testWalkingAgainAllowsAnotherCheckIn() {
        var monitor = WalkMonitor(stopAfter: 20)
        walk(&monitor, from: 0, to: 30)
        XCTAssertTrue(monitor.checkStopped(at: at(60)))
        monitor.update(totalSteps: monitor.steps + 5, at: at(70))
        XCTAssertFalse(monitor.checkStopped(at: at(200)), "A few steps after a check-in don't re-arm it")
        walk(&monitor, from: 210, to: 240)
        XCTAssertTrue(monitor.checkStopped(at: at(270)))
    }

    func testAnsweringAnotherCheckInNeedsMoreWalking() {
        var monitor = WalkMonitor(stopAfter: 20)
        walk(&monitor, from: 0, to: 30)
        monitor.waitForWalking()
        XCTAssertFalse(monitor.checkStopped(at: at(120)), "Standing still to answer an alarm isn't a new stop")
        walk(&monitor, from: 130, to: 150)
        XCTAssertTrue(monitor.checkStopped(at: at(180)))
    }

    func testCountsOnlyNewSteps() {
        var monitor = WalkMonitor(stopAfter: 20)
        walk(&monitor, from: 0, to: 30)
        let steps = monitor.steps
        monitor.update(totalSteps: steps, at: at(50))
        XCTAssertEqual(monitor.lastStepAt, at(30), "The same total again isn't a new step")
        XCTAssertTrue(monitor.checkStopped(at: at(50)))
    }
}
