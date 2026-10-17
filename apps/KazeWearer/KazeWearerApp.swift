import SwiftUI

@main
struct KazeWearerApp: App {
    @State private var store = WearerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

struct RootView: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        Group {
            if store.isSetUp {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .task { store.start() }
    }
}
