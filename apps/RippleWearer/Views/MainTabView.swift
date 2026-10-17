import RippleKit
import SwiftUI

/// Home, Contacts, Session and Settings behind a large bottom bar. During a
/// check-in or an alert the bar hides and Home comes to the front, so the
/// "I'm okay" button is the one obvious thing to tap.
struct MainTabView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: AppTab = .home
    /// Room left under each screen's content for the floating bar, plus a gap.
    /// Grows with the text size, like the bar does.
    @ScaledMetric(relativeTo: .footnote) private var barClearance: CGFloat = 96

    var body: some View {
        // Read the revision so the bar hides and shows as the alarm changes.
        let _ = store.revision
        let inAlarm = store.coordinator.display(phoneAvailable: !store.inOutage).mode.isAlarm
        // The glass bar floats over the screens, so backgrounds run to the bottom
        // edge. Every scrolling screen gets a bottom margin the height of the bar,
        // so its last item always scrolls fully above it.
        Group {
            switch selection {
            case .home:
                HomeView()
            case .contacts:
                NavigationStack { ContactsView() }
            case .session:
                NavigationStack { SessionView() }
            case .settings:
                NavigationStack { SettingsView() }
            }
        }
        .contentMargins(.bottom, inAlarm ? 16 : barClearance, for: .scrollContent)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                FeedbackBar()
                if !inAlarm {
                    TabBar(selection: $selection)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: inAlarm)
        .onChange(of: inAlarm) { _, alarm in
            if alarm { selection = .home }
        }
        .onAppear {
            if inAlarm { selection = .home }
        }
    }
}

enum AppTab: CaseIterable {
    case home, contacts, session, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .contacts: return "Contacts"
        case .session: return "Sessions"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .contacts: return "person.2"
        case .session: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .contacts: return "person.2.fill"
        case .session: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// A floating glass capsule. Each tab is at least 60 pt tall; the selected
/// one sits on a brighter inner pill with a filled blue icon.
private struct TabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selected ? Theme.accent : Theme.text)
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                    // The selected tab sits on a brighter inner pill, like a glass lens.
                    .background {
                        if selected {
                            Capsule()
                                .fill(.white.opacity(0.75))
                                .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(6)
        .background { glass }
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// A floating frosted-glass capsule. Real Liquid Glass on iOS 26, frosted
    /// material before that, and solid white when Reduce Transparency is on.
    @ViewBuilder
    private var glass: some View {
        if reduceTransparency {
            Capsule().fill(Theme.card).shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        } else {
            // glassEffect only exists in the iOS 26 SDK (Xcode 26, Swift 6.2), so
            // older Xcode, including CI, builds the frosted version instead.
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
            } else {
                frosted
            }
            #else
            frosted
            #endif
        }
    }

    private var frosted: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(.white.opacity(0.25)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

#Preview("Tabs") {
    MainTabView().environment(WearerStore())
}

#Preview("Tabs, largest text") {
    MainTabView().environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
