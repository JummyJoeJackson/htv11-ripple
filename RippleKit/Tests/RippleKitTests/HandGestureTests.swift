import Foundation
import XCTest
@testable import RippleKit

final class HandGestureTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testPresetMenuHasExactlyTheRequestedOrderAndSequences() {
        XCTAssertEqual(HandGesturePreset.allCases.map(\.label), [
            "pinch", "clench", "double pinch", "double clench", "pinch + clench",
            "double pinch + clench", "clench + pinch", "clench + double pinch",
            "double clench + pinch", "double clench + double pinch",
        ])
        XCTAssertEqual(HandGesturePreset.allCases.map(\.steps), [
            [.pinch], [.clench], [.doublePinch], [.doubleClench], [.pinch, .clench],
            [.doublePinch, .clench], [.clench, .pinch], [.clench, .doublePinch],
            [.doubleClench, .pinch], [.doubleClench, .doublePinch],
        ])
        XCTAssertEqual(Set(HandGestureStep.allCases.map(\.shortcutName)).count, 4)
    }

    func testEveryPresetMatchesOnlyAfterItsFinalStep() {
        for preset in HandGesturePreset.allCases {
            var recognizer = HandGestureRecognizer(preset: preset)
            for (index, step) in preset.steps.enumerated() {
                let expected: HandGestureProgress = index == preset.steps.count - 1 ? .matched : .partial
                XCTAssertEqual(recognizer.record(step, at: at(Double(index))), expected, preset.label)
            }
        }
    }

    func testDoubleInputsAreAtomicAndCannotBeReplacedBySingles() {
        var pinch = HandGestureRecognizer(preset: .doublePinch)
        XCTAssertEqual(pinch.record(.pinch, at: at(0)), .idle)
        XCTAssertEqual(pinch.record(.pinch, at: at(1)), .idle)
        XCTAssertEqual(pinch.record(.doublePinch, at: at(2)), .matched)
        var clench = HandGestureRecognizer(preset: .doubleClench)
        XCTAssertEqual(clench.record(.clench, at: at(0)), .idle)
        XCTAssertEqual(clench.record(.clench, at: at(1)), .idle)
        XCTAssertEqual(clench.record(.doubleClench, at: at(2)), .matched)
    }

    func testUnselectedPresetCannotMatch() {
        for preset in HandGesturePreset.allCases {
            for unrelated in HandGestureStep.allCases where unrelated != preset.steps.first {
                var recognizer = HandGestureRecognizer(preset: preset)
                XCTAssertEqual(recognizer.record(unrelated, at: at(0)), .idle, preset.label)
            }
        }
    }

    func testCompoundPrefixDoesNotDismiss() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        XCTAssertEqual(recognizer.record(.pinch, at: at(0)), .partial)
        XCTAssertEqual(recognizer.record(.pinch, at: at(1)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(2)), .matched)
    }

    func testSlowInputAtWindowBoundaryMatches() {
        var recognizer = HandGestureRecognizer(preset: .doubleClenchDoublePinch)
        recognizer.record(.doubleClench, at: at(0))
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(5)), .matched)
    }

    func testExpiredPrefixCannotCompleteAndNextSequenceWorks() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        XCTAssertEqual(recognizer.record(.clench, at: at(5.01)), .idle)
        XCTAssertEqual(recognizer.record(.pinch, at: at(6)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(7)), .matched)
    }

    func testDuplicatePrefixDoesNotExtendWindow() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        XCTAssertEqual(recognizer.record(.pinch, at: at(0.3)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(5.1)), .idle)
    }

    func testPartialDeadlineDoesNotMoveForDuplicatesAndClearsOnMatch() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        XCTAssertNil(recognizer.expiresAt)
        recognizer.record(.pinch, at: at(0))
        XCTAssertEqual(recognizer.expiresAt, at(5))
        recognizer.record(.pinch, at: at(0.3))
        XCTAssertEqual(recognizer.expiresAt, at(5))
        recognizer.record(.clench, at: at(1))
        XCTAssertNil(recognizer.expiresAt)
        recognizer.record(.pinch, at: at(2))
        recognizer.reset()
        XCTAssertNil(recognizer.expiresAt)
    }

    func testRepeatedShortcutDeliveryDoesNotReplayAMatch() {
        for preset in HandGesturePreset.allCases {
            var recognizer = HandGestureRecognizer(preset: preset)
            for (index, step) in preset.steps.enumerated() {
                recognizer.record(step, at: at(Double(index)))
            }
            let completedAt = Double(preset.steps.count - 1)
            let duplicate = preset.steps.last!
            XCTAssertEqual(recognizer.record(duplicate, at: at(completedAt + 0.1)), .idle, preset.label)
            XCTAssertEqual(recognizer.record(duplicate, at: at(completedAt + 0.3)), .idle, preset.label)
        }
    }

    func testWrongStepClearsPrefix() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        XCTAssertEqual(recognizer.record(.doubleClench, at: at(1)), .idle)
        XCTAssertEqual(recognizer.record(.clench, at: at(2)), .idle)
    }

    func testWrongStepCanRestartAtFirstStep() {
        var recognizer = HandGestureRecognizer(preset: .clenchDoublePinch)
        recognizer.record(.clench, at: at(0))
        XCTAssertEqual(recognizer.record(.clench, at: at(1)), .partial)
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(2)), .matched)
    }

    func testResetDiscardsPartialInputAndDuplicateHistory() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        recognizer.reset()
        XCTAssertEqual(recognizer.record(.clench, at: at(1)), .idle)
        recognizer.select(.pinch)
        XCTAssertEqual(recognizer.record(.pinch, at: at(2)), .matched)
        recognizer.reset()
        XCTAssertEqual(recognizer.record(.pinch, at: at(2.1)), .matched)
    }

    func testSelectionChangeCannotFinishOldSequence() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        recognizer.select(.doublePinchClench)
        XCTAssertEqual(recognizer.preset, .doublePinchClench)
        XCTAssertEqual(recognizer.record(.clench, at: at(1)), .idle)
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(2)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(3)), .matched)
    }

    func testOutOfOrderInputCannotCompleteAndClearsOldPrefix() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(1))
        XCTAssertEqual(recognizer.record(.clench, at: at(0)), .idle)
        XCTAssertEqual(recognizer.record(.clench, at: at(2)), .idle)
        XCTAssertEqual(recognizer.record(.pinch, at: at(3)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(4)), .matched)
    }

    func testNonFiniteInputCannotCompleteAndClearsPrefix() {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            var recognizer = HandGestureRecognizer(preset: .pinchClench)
            recognizer.record(.pinch, at: at(0))
            XCTAssertEqual(recognizer.record(.clench, at: Date(timeIntervalSince1970: invalid)), .idle)
            XCTAssertEqual(recognizer.record(.clench, at: at(1)), .idle)
        }
    }

    func testInvalidTimingOptionsUseSafeDefaults() {
        for invalid in [Double.nan, Double.infinity, -1] {
            let recognizer = HandGestureRecognizer(preset: .pinchClench, maxGap: invalid, bounce: invalid)
            XCTAssertEqual(recognizer.maxGap, 5)
            XCTAssertEqual(recognizer.bounce, 0.4)
        }
    }
}

final class HandGestureConfigTests: XCTestCase {
    private func wearerConfig() -> RippleConfig {
        var config = RippleConfig.makeDefault(wearerName: "Existing wearer")
        config.version = 22
        config.contacts = [PermanentContact(id: "existing", name: "Saved contact", phone: "4165550100", tier: .two, shareLocation: true)]
        config.helpCardEnabled = true
        config.helpCard = "Existing help card"
        config.voiceEnabled = true
        config.voicePhrase = "saved phrase"
        config.combosEnabled = false
        config.shortcutName = "Existing sender"
        return config
    }

    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: RippleJSON.encoder.encode(value)) as? [String: Any])
    }

    func testEveryPresetRoundTripsAndReachesWatchWithoutChangingOtherSettings() throws {
        for preset in HandGesturePreset.allCases {
            var config = wearerConfig()
            config.handGesturesEnabled = true
            config.handGesturePreset = preset
            let restored = try RippleJSON.decoder.decode(RippleConfig.self, from: RippleJSON.encoder.encode(config))
            XCTAssertEqual(restored, config)
            XCTAssertEqual(restored.watchConfig.handGesturePreset, preset)
            XCTAssertTrue(restored.watchConfig.handGesturesEnabled)
            let watch = try RippleJSON.decoder.decode(WatchConfig.self, from: RippleJSON.encoder.encode(restored.watchConfig))
            XCTAssertEqual(watch, restored.watchConfig)
        }
    }

    func testLegacyPhoneSettingsRetainContactsAndAllPreferences() throws {
        let original = wearerConfig()
        var legacy = try encodedObject(original)
        legacy.removeValue(forKey: "handGesturesEnabled")
        legacy.removeValue(forKey: "handGesturePreset")
        let restored = try RippleJSON.decoder.decode(RippleConfig.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.contacts, original.contacts)
        XCTAssertFalse(restored.handGesturesEnabled)
        XCTAssertEqual(restored.handGesturePreset, .pinchClench)
    }

    func testLegacyWatchSettingsStillLoad() throws {
        let original = wearerConfig().watchConfig
        var legacy = try encodedObject(original)
        legacy.removeValue(forKey: "handGesturesEnabled")
        legacy.removeValue(forKey: "handGesturePreset")
        let restored = try RippleJSON.decoder.decode(WatchConfig.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored, original)
    }

    func testUnknownFuturePhonePresetKeepsDataAndDisablesUnintendedDismissal() throws {
        let original = wearerConfig()
        var future = try encodedObject(original)
        future["handGesturePreset"] = "futureGesture"
        future["handGesturesEnabled"] = true
        let restored = try RippleJSON.decoder.decode(RippleConfig.self, from: JSONSerialization.data(withJSONObject: future))
        XCTAssertEqual(restored, original)
        XCTAssertFalse(restored.handGesturesEnabled)
    }

    func testUnknownFutureWatchPresetKeepsSettingsAndDisablesUnintendedDismissal() throws {
        let original = wearerConfig().watchConfig
        var future = try encodedObject(original)
        future["handGesturePreset"] = "futureGesture"
        future["handGesturesEnabled"] = true
        let restored = try RippleJSON.decoder.decode(WatchConfig.self, from: JSONSerialization.data(withJSONObject: future))
        XCTAssertEqual(restored, original)
        XCTAssertFalse(restored.handGesturesEnabled)
    }

    func testMissingPresetCannotEnableAnUnselectedSequence() throws {
        var payload = try encodedObject(wearerConfig())
        payload.removeValue(forKey: "handGesturePreset")
        payload["handGesturesEnabled"] = true
        let restored = try RippleJSON.decoder.decode(RippleConfig.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertFalse(restored.handGesturesEnabled)
        XCTAssertEqual(restored.contacts, wearerConfig().contacts)
    }

    func testFreshDefaultsKeepHandGesturesOffUntilSetUp() {
        XCTAssertFalse(RippleConfig.makeDefault(wearerName: "New wearer").handGesturesEnabled)
        XCTAssertFalse(WatchConfig.fallback.handGesturesEnabled)
    }
}
