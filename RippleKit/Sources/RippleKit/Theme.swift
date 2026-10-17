#if canImport(SwiftUI)
import SwiftUI

/// Shared design system for the wearer iPhone app and the Watch app, tuned
/// for older adults with Parkinson's: large type, large targets, high
/// contrast, and status colors that always come with an icon and a label.
/// Every text color here is at least 4.5:1 against the background it's used on.
public enum Theme {
    // MARK: Brand

    public static let primary = Color(rgb: 0x0F766E)
    public static let primaryPressed = Color(rgb: 0x0B5F58)
    public static let primaryTint = Color(rgb: 0xCCFBF1)

    // MARK: iPhone brand: baby blue. The Watch keeps the teal above.

    /// Baby blue fill for primary buttons and the tab bar, always with `onBrand` text.
    public static let brand = Color(rgb: 0x89CFF0)
    public static let brandPressed = Color(rgb: 0x6FC0EA)
    /// Navy text and icons on baby blue (about 8:1).
    public static let onBrand = Color(rgb: 0x0B2E4A)
    /// Deeper blue for links, icons and outline buttons on white, where
    /// baby blue itself would be too faint to read (about 5.3:1 on white).
    public static let accent = Color(rgb: 0x1F6FB2)
    /// Background for icon tiles on the iPhone.
    public static let iconTint = Color(rgb: 0xD3ECFA)

    // MARK: Surfaces and text

    /// Pale baby blue, the iPhone app's screen background.
    public static let background = Color(rgb: 0xEAF5FC)
    public static let card = Color(rgb: 0xFFFFFF)
    /// Navy for titles and main text.
    public static let text = Color(rgb: 0x0B2E4A)
    /// Used instead of light gray, which is too faint to read comfortably.
    public static let secondaryText = Color(rgb: 0x3D5468)
    public static let divider = Color(rgb: 0xD2E3EE)

    // MARK: Status. Red is only ever used for alerts.

    public static let safe = Color(rgb: 0x15803D)
    public static let checkIn = Color(rgb: 0xB45309)
    public static let alert = Color(rgb: 0xB91C1C)
    public static let responding = Color(rgb: 0x1D4ED8)
    public static let off = Color(rgb: 0x4B5563)

    // MARK: Shape and size

    public static let cornerRadius: CGFloat = 24
    public static let primaryButtonHeight: CGFloat = 72
    public static let secondaryButtonHeight: CGFloat = 64
    public static let rowHeight: CGFloat = 72
    /// Rows in a grouped list card, like a settings list.
    public static let listRowHeight: CGFloat = 88

    // Card shadow: black 6%, radius 12, 4 pt down.
    public static let shadowColor = Color.black.opacity(0.06)
    public static let shadowRadius: CGFloat = 12
    public static let shadowY: CGFloat = 4
    public static let minTarget: CGFloat = 60
    public static let spacing: CGFloat = 16

    // MARK: Type. All Dynamic Type styles, so larger accessibility sizes scale.

    /// 28 pt bold at the default size.
    public static let screenTitle = Font.title.weight(.bold)
    /// 15 pt, shown uppercase with letter spacing, like "WHO WAS TEXTED".
    public static let sectionLabel = Font.subheadline.weight(.semibold)
    public static let sectionLabelTracking: CGFloat = 1.5
    /// 20 pt semibold, for card and row titles.
    public static let cardTitle = Font.title3.weight(.semibold)

    /// 17 pt at the default size.
    public static let body = Font.body
    /// 22 pt at the default size.
    public static let headline = Font.title2.weight(.bold)
    /// 16 pt at the default size. The smallest text anywhere except section labels.
    public static let label = Font.callout
    public static let labelBold = Font.callout.weight(.semibold)
    /// 17 pt bold, for button titles.
    public static let button = Font.headline.weight(.bold)
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Status

/// What the status color, icon and words mean. The color is never shown alone.
public enum StatusKind: Sendable {
    case safe, checkIn, alert, responding, off

    public var color: Color {
        switch self {
        case .safe: return Theme.safe
        case .checkIn: return Theme.checkIn
        case .alert: return Theme.alert
        case .responding: return Theme.responding
        case .off: return Theme.off
        }
    }
}

/// A rounded label with an icon and text in white on a solid status color.
public struct StatusPill: View {
    let text: String
    let systemImage: String
    let kind: StatusKind

    public init(_ text: String, systemImage: String, kind: StatusKind) {
        self.text = text
        self.systemImage = systemImage
        self.kind = kind
    }

    public var body: some View {
        // Looks the text up in the app's translations; untranslated text shows as is.
        Label(LocalizedStringKey(text), systemImage: systemImage)
            .font(Theme.labelBold)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(kind.color, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LocalizedStringKey(text)))
    }
}

// MARK: - Buttons

/// Full-width filled baby blue button with navy text, 72 pt tall, with an
/// uppercase, letter-spaced label. At most one per screen.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button)
            .textCase(.uppercase)
            .tracking(1.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? Theme.onBrand : .white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: Theme.primaryButtonHeight)
            .background(
                isEnabled ? (configuration.isPressed ? Theme.brandPressed : Theme.brand) : Theme.off,
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// Full-width teal outline button, 64 pt tall. At most one per screen.
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let tint = isEnabled ? Theme.accent : Theme.off
        configuration.label
            .font(Theme.button)
            .multilineTextAlignment(.center)
            .foregroundStyle(configuration.isPressed ? Theme.onBrand : tint)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: Theme.secondaryButtonHeight)
            .background(
                configuration.isPressed ? Theme.iconTint : Theme.card,
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(tint, lineWidth: 3))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

public extension View {
    /// A white card with 24 pt corners and a very soft shadow.
    func rippleCard(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        // The shadow is on the card shape only, so text and pills inside stay crisp.
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: Theme.shadowY)
        }
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var ripplePrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var rippleSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
#endif
