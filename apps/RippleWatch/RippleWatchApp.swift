import SwiftUI

@main
struct RippleWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            CircleScreen()
                .environment(store)
                // New York, Apple's serif, to match the iPhone.
                .fontDesign(.serif)
        }
    }
}
