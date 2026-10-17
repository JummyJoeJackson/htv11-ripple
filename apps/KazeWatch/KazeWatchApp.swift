import SwiftUI

@main
struct KazeWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(store)
        }
    }
}
