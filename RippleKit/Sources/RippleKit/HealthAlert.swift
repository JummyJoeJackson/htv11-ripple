import Foundation

/// An alert Apple Watch records in Apple Health, which Ripple turns into a
/// check-in. Apple decides there was a fall or a heart rhythm worth noting;
/// Ripple never measures or judges anything itself. It only asks the wearer,
/// and brings their people in if they don't answer.
public enum HealthAlertKind: String, Codable, CaseIterable, Sendable {
    /// Fall detection recorded a fall (Health's "Number of Times Fallen").
    /// Health only keeps falls the wearer confirmed or that Apple escalated.
    case fall
    /// A high, low or irregular heart rhythm notification.
    case heart

    /// The alarm source for a check-in started by this alert.
    public var source: AlarmSource {
        switch self {
        case .fall: return .fall
        case .heart: return .heartAlert
        }
    }

    public var label: String {
        switch self {
        case .fall: return "Fall"
        case .heart: return "Heart alert"
        }
    }
}
