import Foundation
import XCTest
@testable import RippleKit

final class GestureComboTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: Swipes

    func testSwipesNeedNetVerticalTravel() {
        XCTAssertEqual(GestureStep.swipe(dx: 5, dy: -60), .swipeUp)
        XCTAssertEqual(GestureStep.swipe(dx: -10, dy: 45), .swipeDown)
        XCTAssertNil(GestureStep.swipe(dx: 3, dy: -12), "Tremor jitter that ends near where it started is not a swipe")
        XCTAssertNil(GestureStep.swipe(dx: 70, dy: -50), "Mostly sideways is not a swipe")
    }

    // MARK: Combos

    func testTwoSwipesUpAskForHelp() {
        var recognizer = ComboRecognizer()
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(0)), .partial(.help))
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(1.5)), .matched(.help))
    }

    func testTwoSwipesDownConfirmOkay() {
        var recognizer = ComboRecognizer()
        XCTAssertEqual(recognizer.record(.swipeDown, at: at(0)), .partial(.okay))
        XCTAssertEqual(recognizer.record(.swipeDown, at: at(1)), .matched(.okay))
    }

    func testOneSwipeIsNeverEnough() {
        var recognizer = ComboRecognizer()
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(0)), .partial(.help))
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(5)), .partial(.help), "Too long a pause starts over")
    }

    func testSlowMovementStillCounts() {
        var recognizer = ComboRecognizer()
        recognizer.record(.swipeDown, at: at(0))
        XCTAssertEqual(recognizer.record(.swipeDown, at: at(2.9)), .matched(.okay))
    }

    func testABounceCountsOnce() {
        var recognizer = ComboRecognizer()
        recognizer.record(.swipeUp, at: at(0))
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(0.2)), .partial(.help), "A finger bouncing off the glass mid-swipe is one swipe")
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(1)), .matched(.help))
    }

    func testABounceRightAfterAMatchDoesNotStartAnother() {
        var recognizer = ComboRecognizer()
        recognizer.record(.swipeUp, at: at(0))
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(1)), .matched(.help))
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(1.2)), .idle)
    }

    func testAStraySwipeRestartsInsteadOfBlocking() {
        var recognizer = ComboRecognizer()
        recognizer.record(.swipeUp, at: at(0))
        XCTAssertEqual(recognizer.record(.swipeDown, at: at(1)), .partial(.okay))
        XCTAssertEqual(recognizer.record(.swipeDown, at: at(2)), .matched(.okay))
    }

    func testResetForgetsProgress() {
        var recognizer = ComboRecognizer()
        recognizer.record(.swipeUp, at: at(0))
        recognizer.reset()
        XCTAssertEqual(recognizer.record(.swipeUp, at: at(1)), .partial(.help))
    }
}
