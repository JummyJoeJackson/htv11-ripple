import RippleKit
import SwiftUI

/// Home, Contacts, Session and Settings behind a large bottom bar. During a
/// check-in or an alert the bar hides and Home comes to the front, so the
/// "I'm okay" button is the one obvious thing to tap.
struct MainTabView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: AppTab = .home

    var body: some View {
        // Read the revision so the bar hides and shows as the alarm changes.
        let _ = store.revision
        let inAlarm = store.coordinator.display(phoneAvailable: !store.inOutage).mode.isAlarm
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
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
        case .session: return "Session"
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

/// A solid baby blue bar with large navy icons and labels. Each tab is at
/// least 64 pt tall; the selected one sits on a lighter pill with a filled icon.
private struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                            .font(.system(size: 24, weight: .semibold))
                            .frame(height: 28)
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.onBrand)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    // A lighter pill and a filled icon mark the selected tab; navy text stays above 4.5:1.
                    .background(selected ? Color.white.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.brand.ignoresSafeArea(edges: .bottom))
    }
}

#Preview("Tabs") {
    MainTabView().environment(WearerStore())
}

#Preview("Tabs, largest text") {
    MainTabView().environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
