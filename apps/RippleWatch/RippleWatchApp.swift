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
                // SF Pro semibold throughout, easy to read at a glance.
                .fontWeight(.semibold)
        }
    }
}
