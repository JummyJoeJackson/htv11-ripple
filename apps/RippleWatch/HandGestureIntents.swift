import AppIntents
import RippleKit

/// Four parameterless actions keep AssistiveTouch assignments stable when the
/// wearer changes the accepted sequence. No action opens an app or returns UI.
struct RipplePinchIntent: AppIntent {
    static let title: LocalizedStringResource = "Ripple Pinch"
    static let description = IntentDescription("Record a pinch in Ripple on Apple Watch. Only a complete configured sequence dismisses an active alarm.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WatchStore.shared.receiveHandGesture(.pinch)
        return .result()
    }
}

struct RippleClenchIntent: AppIntent {
    static let title: LocalizedStringResource = "Ripple Clench"
    static let description = IntentDescription("Record a clench in Ripple on Apple Watch. Only a complete configured sequence dismisses an active alarm.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WatchStore.shared.receiveHandGesture(.clench)
        return .result()
    }
}

struct RippleDoublePinchIntent: AppIntent {
    static let title: LocalizedStringResource = "Ripple Double Pinch"
    static let description = IntentDescription("Record a double pinch as one input in Ripple on Apple Watch. Only a complete configured sequence dismisses an active alarm.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WatchStore.shared.receiveHandGesture(.doublePinch)
        return .result()
    }
}

struct RippleDoubleClenchIntent: AppIntent {
    static let title: LocalizedStringResource = "Ripple Double Clench"
    static let description = IntentDescription("Record a double clench as one input in Ripple on Apple Watch. Only a complete configured sequence dismisses an active alarm.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WatchStore.shared.receiveHandGesture(.doubleClench)
        return .result()
    }
}

struct RippleGestureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RipplePinchIntent(),
                    phrases: ["Record a pinch in \(.applicationName)"],
                    shortTitle: "Ripple Pinch", systemImageName: "hand.pinch")
        AppShortcut(intent: RippleClenchIntent(),
                    phrases: ["Record a clench in \(.applicationName)"],
                    shortTitle: "Ripple Clench", systemImageName: "hand.raised.fingers.spread")
        AppShortcut(intent: RippleDoublePinchIntent(),
                    phrases: ["Record a double pinch in \(.applicationName)"],
                    shortTitle: "Ripple Double Pinch", systemImageName: "hand.pinch")
        AppShortcut(intent: RippleDoubleClenchIntent(),
                    phrases: ["Record a double clench in \(.applicationName)"],
                    shortTitle: "Ripple Double Clench", systemImageName: "hand.raised.fingers.spread")
    }
}
