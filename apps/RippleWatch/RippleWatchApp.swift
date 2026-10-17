import SwiftUI

@main
struct RippleWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            CircleScreen()
                .environment(store)
        }
    }
}
