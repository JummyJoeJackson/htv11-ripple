import SwiftUI
import UIKit

@main
struct RippleWearerApp: App {
    @State private var store = WearerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { url in store.handle(url: url) }
        }
    }
}

struct RootView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isSetUp {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .task { store.start() }
        .onChange(of: scenePhase) { _, phase in
            store.setActive(phase == .active)
            // Keep the screen on for the demo: sending opens Shortcuts, which needs the app in front.
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
    }
}
