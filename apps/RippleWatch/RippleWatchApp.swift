import AppIntents
import SwiftUI

@main
struct RippleWatchApp: App {
    @State private var store = WatchStore.shared

    init() {
        RippleGestureShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            CircleScreen()
                .environment(store)
                // New York, Apple's serif, to match the iPhone.
                .fontDesign(.serif)
        }
    }
}
