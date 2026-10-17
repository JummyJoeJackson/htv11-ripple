import RippleKit
import SwiftUI
import UIKit

// MARK: - Screen

/// The three soft blue wave backgrounds every screen uses. They live in the
/// asset catalog as RippleBackground1, 2 and 3; new screens get one through
/// `rippleScreen(background:)`.
enum RippleBackground: String, CaseIterable {
    /// Ripples top right, waves along the bottom. Home.
    case one = "RippleBackground1"
    /// Waves top right, ripples bottom left. Lists and forms.
    case two = "RippleBackground2"
    /// Ripples top right and bottom right. Detail and setup screens.
    case three = "RippleBackground3"
}

/// A full-screen wave background over the pale blue base color. Decorative only.
struct RippleBackgroundView: View {
    let background: RippleBackground

    var body: some View {
        ZStack {
            Theme.background
            Image(background.rawValue)
                .resizable()
                .scaledToFill()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// The light screen: a soft blue wave background, blue links and controls.
    func rippleScreen(background: RippleBackground = .one) -> some View {
        self
            .background(RippleBackgroundView(background: background))
            .tint(Theme.accent)
            .environment(\.colorScheme, .light)
    }
}

/// Navy titles in navigation bars, to match the in-screen titles.
/// Only the title color changes; the bar keeps the system's own look.
enum NavigationBarStyle {
    static let applied: Void = {
        let navy = UIColor(red: 0x0B / 255, green: 0x2E / 255, blue: 0x4A / 255, alpha: 1)
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: navy]
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: navy]
    }()
}

// MARK: - Screen header

/// A big screen title with an optional one-line subtitle and a round button
/// on the right, like "Contacts  (+)".
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(Theme.label)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A round light-blue icon button for screen headers.
struct HeaderIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.minTarget, height: Theme.minTarget)
                .background(Theme.iconTint, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

/// An uppercase section label with a plain-words note after it, like
/// "TIER 1  Texted first".
struct SectionTitle: View {
    let title: String
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            SectionLabel(title)
            if let note {
                Text(LocalizedStringKey(note))
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

/// An uppercase, letter-spaced section label, like "JOURNAL".
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(Theme.sectionLabel)
            .tracking(Theme.sectionLabelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityLabel(Text(LocalizedStringKey(text)))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A white card with generous padding and a very soft shadow.
struct Card<Content: View>: View {
    let title: String?
    let elevated: Bool
    let content: Content

    init(_ title: String? = nil, elevated: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.elevated = elevated
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if let title {
                SectionLabel(title)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .rippleCard()
    }
}

/// Seconds remaining until a deadline. Display only.
struct CountdownText: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Text("\(remaining) s")
                .monospacedDigit()
                .accessibilityLabel("\(remaining) seconds left")
        }
    }
}

// MARK: - Grouped list rows

/// Rows stacked in one white card with thin dividers, like a settings list.
struct RowGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .rippleCard()
    }
}

/// A thin divider between rows in a `RowGroup`, inset past the icon.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.leading, 88)
            .accessibilityHidden(true)
    }
}

/// An 88 pt list row: large outline icon, dark title, optional detail, chevron.
struct NavRow: View {
    let title: String
    let systemImage: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.iconTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.text)
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(Theme.label)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: Theme.listRowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A label and value. When `ok` is set, an icon and the words carry the
/// meaning, not just the color.
struct StatusRow: View {
    let label: String
    let value: String
    var ok: Bool? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(LocalizedStringKey(label))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? Theme.safe : Theme.checkIn)
                    .accessibilityHidden(true)
            }
            Text(LocalizedStringKey(value))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.secondaryText)
        }
        .font(Theme.label)
        .accessibilityElement(children: .combine)
    }
}

/// Explanatory text under a section, at the 17 pt minimum. Italic marks it
/// as background information; anything to act on stays upright.
struct FormNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(Theme.label)
            .italic()
            .foregroundStyle(Theme.secondaryText)
    }
}

// MARK: - Link buttons

/// A text link in a form row: brand blue, gray when disabled, system red
/// for destructive actions (as before the restyle).
struct LinkButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(!isEnabled ? Theme.secondaryText : (destructive ? Color(uiColor: .systemRed) : Theme.accent))
            .frame(maxWidth: .infinity, minHeight: Theme.minTarget, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == LinkButtonStyle {
    static var rippleLink: LinkButtonStyle { LinkButtonStyle() }
    static var rippleDestructiveLink: LinkButtonStyle { LinkButtonStyle(destructive: true) }
}

// MARK: - Forms

/// A form on the pale background with white grouped rows. Same content and
/// order as a plain Form.
struct RippleForm<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.divider)
        }
        .rippleForm()
    }
}

/// A list on the pale background with white grouped rows. Same content and
/// order as a plain List.
struct RippleList<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        List {
            Group { content }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.divider)
        }
        .rippleForm()
    }
}

extension View {
    /// Large type and roomy rows for forms and lists.
    func rippleForm(background: RippleBackground = .two) -> some View {
        self
            .font(Theme.body)
            .foregroundStyle(Theme.text)
            .controlSize(.large)
            .environment(\.defaultMinListRowHeight, Theme.minTarget)
            .scrollContentBackground(.hidden)
            .rippleScreen(background: background)
    }
}

extension Date {
    /// "12:46 AM". Times are always shown without seconds.
    var shortTime: String { formatted(date: .omitted, time: .shortened) }

    /// "Today, 2:00 PM", "Yesterday, 3:21 PM" or "Mon, Oct 21, 4:00 PM".
    var dayAndTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today, \(shortTime)" }
        if calendar.isDateInYesterday(self) { return "Yesterday, \(shortTime)" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow, \(shortTime)" }
        return formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", " + shortTime
    }
}

private struct ComponentsPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                StatusPill("Monitoring", systemImage: "checkmark.shield.fill", kind: .safe)
                RowGroup {
                    NavRow(title: "Contacts", systemImage: "person.2", detail: "3 people")
                    RowDivider()
                    NavRow(title: "Settings", systemImage: "gearshape", detail: "Timing, help card, Watch")
                }
                Card("Example") {
                    StatusRow(label: "Apple Watch", value: "Connected", ok: true)
                    StatusRow(label: "Server", value: "Can't reach it", ok: false)
                }
                Button("I'm okay now") {}.buttonStyle(.ripplePrimary)
                Button("Stop monitoring") {}.buttonStyle(.rippleSecondary)
            }
            .padding(Theme.spacing)
        }
        .rippleScreen()
    }
}

#Preview("Components") { ComponentsPreview() }
#Preview("Components, largest text") { ComponentsPreview().dynamicTypeSize(.accessibility3) }
