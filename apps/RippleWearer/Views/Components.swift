import CoreImage
import RippleKit
import SwiftUI
import UIKit

// MARK: - Screen

extension View {
    /// The light screen: pale baby blue background, blue links and controls.
    func rippleScreen() -> some View {
        self
            .background(Theme.background.ignoresSafeArea())
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

// MARK: - Cards

/// An uppercase, letter-spaced section label, like "JOURNAL".
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.sectionLabel)
            .tracking(Theme.sectionLabelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityLabel(text)
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
                Text(title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.text)
                if let detail {
                    Text(detail)
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
            Text(label)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? Theme.safe : Theme.checkIn)
                    .accessibilityHidden(true)
            }
            Text(value)
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
        Text(text)
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
    func rippleForm() -> some View {
        self
            .font(Theme.body)
            .foregroundStyle(Theme.text)
            .controlSize(.large)
            .environment(\.defaultMinListRowHeight, Theme.minTarget)
            .scrollContentBackground(.hidden)
            .rippleScreen()
    }
}

extension Date {
    /// "12:46 AM". Times are always shown without seconds.
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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
