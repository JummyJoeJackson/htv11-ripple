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
                let expected: HandGestureProgress = index == preset.steps.count - 1 ? .matched(.okay) : .partial
                XCTAssertEqual(recognizer.record(step, at: at(Double(index))), expected, preset.label)
            }
        }
    }

    func testDoubleInputsAreAtomicAndCannotBeReplacedBySingles() {
        var pinch = HandGestureRecognizer(preset: .doublePinch)
        XCTAssertEqual(pinch.record(.pinch, at: at(0)), .idle)
        XCTAssertEqual(pinch.record(.pinch, at: at(1)), .idle)
        XCTAssertEqual(pinch.record(.doublePinch, at: at(2)), .matched(.okay))
        var clench = HandGestureRecognizer(preset: .doubleClench)
        XCTAssertEqual(clench.record(.clench, at: at(0)), .idle)
        XCTAssertEqual(clench.record(.clench, at: at(1)), .idle)
        XCTAssertEqual(clench.record(.doubleClench, at: at(2)), .matched(.okay))
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
        XCTAssertEqual(recognizer.record(.clench, at: at(2)), .matched(.okay))
    }

    func testSlowInputAtWindowBoundaryMatches() {
        var recognizer = HandGestureRecognizer(preset: .doubleClenchDoublePinch)
        recognizer.record(.doubleClench, at: at(0))
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(5)), .matched(.okay))
    }

    func testExpiredPrefixCannotCompleteAndNextSequenceWorks() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        XCTAssertEqual(recognizer.record(.clench, at: at(5.01)), .idle)
        XCTAssertEqual(recognizer.record(.pinch, at: at(6)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(7)), .matched(.okay))
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
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(2)), .matched(.okay))
    }

    func testResetDiscardsPartialInputAndDuplicateHistory() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        recognizer.reset()
        XCTAssertEqual(recognizer.record(.clench, at: at(1)), .idle)
        recognizer.select(.pinch)
        XCTAssertEqual(recognizer.record(.pinch, at: at(2)), .matched(.okay))
        recognizer.reset()
        XCTAssertEqual(recognizer.record(.pinch, at: at(2.1)), .matched(.okay))
    }

    func testSelectionChangeCannotFinishOldSequence() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(0))
        recognizer.select(.doublePinchClench)
        XCTAssertEqual(recognizer.bindings, [HandGestureBinding(preset: .doublePinchClench, action: .okay)])
        XCTAssertEqual(recognizer.record(.clench, at: at(1)), .idle)
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(2)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(3)), .matched(.okay))
    }

    func testOutOfOrderInputCannotCompleteAndClearsOldPrefix() {
        var recognizer = HandGestureRecognizer(preset: .pinchClench)
        recognizer.record(.pinch, at: at(1))
        XCTAssertEqual(recognizer.record(.clench, at: at(0)), .idle)
        XCTAssertEqual(recognizer.record(.clench, at: at(2)), .idle)
        XCTAssertEqual(recognizer.record(.pinch, at: at(3)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(4)), .matched(.okay))
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

    // MARK: Dismiss and help together

    private func both(dismiss: HandGesturePreset, help: HandGesturePreset) -> HandGestureRecognizer {
        HandGestureRecognizer(bindings: [
            HandGestureBinding(preset: dismiss, action: .okay),
            HandGestureBinding(preset: help, action: .help),
        ])
    }

    func testEachSequenceReportsItsOwnAction() {
        var recognizer = both(dismiss: .pinchClench, help: .doubleClenchDoublePinch)
        XCTAssertEqual(recognizer.record(.pinch, at: at(0)), .partial)
        XCTAssertEqual(recognizer.record(.clench, at: at(1)), .matched(.okay))
        XCTAssertEqual(recognizer.record(.doubleClench, at: at(2)), .partial)
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(3)), .matched(.help))
    }

    func testSharedFirstStepWaitsForTheSecond() {
        var recognizer = both(dismiss: .clenchPinch, help: .clenchDoublePinch)
        XCTAssertEqual(recognizer.nextSteps, [.clench])
        XCTAssertEqual(recognizer.record(.clench, at: at(0)), .partial)
        XCTAssertEqual(recognizer.nextSteps, [.pinch, .doublePinch])
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(1)), .matched(.help))
        XCTAssertEqual(recognizer.nextSteps, [.clench])
    }

    func testFinishingOneSequenceCannotStartTheOther() {
        // The pinch that finishes clench + pinch is not the start of pinch + clench.
        var recognizer = both(dismiss: .clenchPinch, help: .pinchClench)
        recognizer.record(.clench, at: at(0))
        XCTAssertEqual(recognizer.record(.pinch, at: at(1)), .matched(.okay))
        XCTAssertEqual(recognizer.record(.clench, at: at(2)), .partial)
        XCTAssertEqual(recognizer.nextSteps, [.pinch])
    }

    func testNextStepsListEachSequenceStartOnce() {
        let recognizer = both(dismiss: .doublePinch, help: .clenchPinch)
        XCTAssertEqual(recognizer.nextSteps, [.doublePinch, .clench])
        XCTAssertEqual(HandGestureRecognizer(bindings: []).nextSteps, [])
    }

    func testSelectingNewBindingsDiscardsPartialInput() {
        var recognizer = HandGestureRecognizer(bindings: [HandGestureBinding(preset: .doubleClenchDoublePinch, action: .help)])
        recognizer.record(.doubleClench, at: at(0))
        recognizer.select([
            HandGestureBinding(preset: .pinch, action: .okay),
            HandGestureBinding(preset: .doubleClenchDoublePinch, action: .help),
        ])
        XCTAssertEqual(recognizer.record(.doublePinch, at: at(1)), .idle)
    }
}

final class HandGesturePairTests: XCTestCase {
    func testOverlapMeansSameOrContained() {
        XCTAssertTrue(HandGesturePreset.pinchClench.overlaps(.pinchClench))
        XCTAssertTrue(HandGesturePreset.pinch.overlaps(.pinchClench))
        XCTAssertTrue(HandGesturePreset.pinchClench.overlaps(.pinch))
        XCTAssertTrue(HandGesturePreset.clench.overlaps(.pinchClench))
        XCTAssertFalse(HandGesturePreset.doublePinch.overlaps(.pinchClench))
        XCTAssertFalse(HandGesturePreset.clenchPinch.overlaps(.pinchClench))
        XCTAssertFalse(HandGesturePreset.pinch.overlaps(.clench))
    }

    func testAChoiceDisappearsFromTheOtherPicker() {
        for dismiss in HandGesturePreset.allCases {
            XCTAssertFalse(HandGesturePreset.helpChoices(besides: dismiss).contains(dismiss), dismiss.label)
        }
        for help in HandGesturePreset.helpChoices(besides: .pinchClench) {
            XCTAssertFalse(HandGesturePreset.dismissChoices(besides: help).contains(help), help.label)
        }
    }

    func testEveryAllowedPairKeepsBothSelectionsAvailable() {
        for dismiss in HandGesturePreset.allCases {
            let helps = HandGesturePreset.helpChoices(besides: dismiss)
            XCTAssertFalse(helps.isEmpty, dismiss.label)
            for help in helps {
                XCTAssertEqual(help.steps.count, 2, help.label)
                XCTAssertFalse(help.overlaps(dismiss), "\(dismiss.label) / \(help.label)")
                XCTAssertTrue(HandGesturePreset.dismissChoices(besides: help).contains(dismiss), "\(dismiss.label) / \(help.label)")
            }
        }
    }

    func testHelpChoicesLeaveOutSequencesContainingASingleDismissInput() {
        XCTAssertEqual(HandGesturePreset.helpChoices(besides: .pinch), [.doublePinchClench, .clenchDoublePinch, .doubleClenchDoublePinch])
        XCTAssertEqual(HandGesturePreset.dismissChoices(besides: .doubleClenchDoublePinch).count, 7)
    }

    func testDefaultHelpIsAlwaysAllowed() {
        XCTAssertEqual(HandGesturePreset.defaultHelp(besides: .pinchClench), .doubleClenchDoublePinch)
        for dismiss in HandGesturePreset.allCases {
            XCTAssertTrue(HandGesturePreset.helpChoices(besides: dismiss).contains(.defaultHelp(besides: dismiss)), dismiss.label)
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
            config.handGestureHelpPreset = .defaultHelp(besides: preset)
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
        XCTAssertFalse(RippleConfig.makeDefault(wearerName: "New wearer").handGestureHelpEnabled)
        XCTAssertFalse(WatchConfig.fallback.handGestureHelpEnabled)
        XCTAssertEqual(RippleConfig.makeDefault(wearerName: "New wearer").handGestureHelpPreset, .doubleClenchDoublePinch)
    }

    // MARK: Help sequence

    func testEveryAllowedPairRoundTripsAndReachesWatch() throws {
        for dismiss in HandGesturePreset.allCases {
            for help in HandGesturePreset.helpChoices(besides: dismiss) {
                var config = wearerConfig()
                config.handGesturesEnabled = true
                config.handGesturePreset = dismiss
                config.handGestureHelpEnabled = true
                config.handGestureHelpPreset = help
                let restored = try RippleJSON.decoder.decode(RippleConfig.self, from: RippleJSON.encoder.encode(config))
                XCTAssertEqual(restored, config)
                let watch = try RippleJSON.decoder.decode(WatchConfig.self, from: RippleJSON.encoder.encode(restored.watchConfig))
                XCTAssertEqual(watch, restored.watchConfig)
                XCTAssertTrue(watch.handGestureHelpEnabled)
                XCTAssertEqual(watch.handGestureHelpPreset, help)
            }
        }
    }

    func testSettingsWithoutHelpKeysKeepHelpOffAndClearOfDismiss() throws {
        var original = wearerConfig()
        original.handGesturesEnabled = true
        original.handGesturePreset = .doubleClench
        var legacy = try encodedObject(original)
        legacy.removeValue(forKey: "handGestureHelpEnabled")
        legacy.removeValue(forKey: "handGestureHelpPreset")
        let restored = try RippleJSON.decoder.decode(RippleConfig.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.contacts, original.contacts)
        XCTAssertTrue(restored.handGesturesEnabled)
        XCTAssertEqual(restored.handGesturePreset, .doubleClench)
        XCTAssertFalse(restored.handGestureHelpEnabled)
        XCTAssertFalse(restored.handGestureHelpPreset.overlaps(.doubleClench))

        var legacyWatch = try encodedObject(original.watchConfig)
        legacyWatch.removeValue(forKey: "handGestureHelpEnabled")
        legacyWatch.removeValue(forKey: "handGestureHelpPreset")
        let watch = try RippleJSON.decoder.decode(WatchConfig.self, from: JSONSerialization.data(withJSONObject: legacyWatch))
        XCTAssertTrue(watch.handGesturesEnabled)
        XCTAssertFalse(watch.handGestureHelpEnabled)
        XCTAssertFalse(watch.handGestureHelpPreset.overlaps(.doubleClench))
    }

    func testOverlappingSingleOrUnknownHelpPresetLoadsDisabled() throws {
        for invalid in ["pinchClench", "clench", "futureGesture"] {
            var payload = try encodedObject(wearerConfig())
            payload["handGesturePreset"] = "pinch"
            payload["handGesturesEnabled"] = true
            payload["handGestureHelpPreset"] = invalid
            payload["handGestureHelpEnabled"] = true
            let restored = try RippleJSON.decoder.decode(RippleConfig.self, from: JSONSerialization.data(withJSONObject: payload))
            XCTAssertTrue(restored.handGesturesEnabled, invalid)
            XCTAssertEqual(restored.handGesturePreset, .pinch, invalid)
            XCTAssertFalse(restored.handGestureHelpEnabled, invalid)
            XCTAssertEqual(restored.handGestureHelpPreset, .defaultHelp(besides: .pinch), invalid)
            XCTAssertEqual(restored.contacts, wearerConfig().contacts, invalid)

            var watchPayload = try encodedObject(wearerConfig().watchConfig)
            watchPayload["handGesturePreset"] = "pinch"
            watchPayload["handGesturesEnabled"] = true
            watchPayload["handGestureHelpPreset"] = invalid
            watchPayload["handGestureHelpEnabled"] = true
            let watch = try RippleJSON.decoder.decode(WatchConfig.self, from: JSONSerialization.data(withJSONObject: watchPayload))
            XCTAssertTrue(watch.handGesturesEnabled, invalid)
            XCTAssertFalse(watch.handGestureHelpEnabled, invalid)
            XCTAssertEqual(watch.handGestureHelpPreset, .defaultHelp(besides: .pinch), invalid)
        }
    }
}
