import SwiftUI
import UIKit

@main
struct RippleWearerApp: App {
    @State private var store = WearerStore()
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    init() {
        // Navigation bar title colors, set before any screen appears.
        _ = NavigationBarStyle.applied
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .appLanguage(language)
                // New York, Apple's serif, everywhere. It scales with Dynamic Type.
                .fontDesign(.serif)
                // The light palette is contrast-checked for light mode.
                .preferredColorScheme(.light)
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
                MainTabView()
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
