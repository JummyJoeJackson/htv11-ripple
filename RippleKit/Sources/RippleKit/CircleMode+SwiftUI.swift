#if canImport(SwiftUI)
import SwiftUI

public extension CircleMode {
    /// Green Monitoring, amber Check in, red Alert sent, blue Contact
    /// responding, gray Off. Always shown together with an icon and text.
    var statusKind: StatusKind {
        switch self {
        case .off: return .off
        case .monitoring: return .safe
        case .checkIn: return .checkIn
        case .alertSent: return .alert
        case .responding: return .responding
        }
    }

    var color: Color { statusKind.color }

    /// The Watch circle: teal while monitoring, amber during a check-in,
    /// red after the alert, blue once a contact is checking, gray when off.
    var circleColor: Color {
        switch self {
        case .monitoring: return Theme.primary
        default: return statusKind.color
        }
    }

    /// Short words for the status pill.
    var pillLabel: String {
        switch self {
        case .off: return "Off"
        case .monitoring: return "Monitoring"
        case .checkIn: return "Check in"
        case .alertSent: return "Alert sent"
        case .responding: return "Someone is coming"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "power"
        case .monitoring: return "checkmark.shield.fill"
        case .checkIn: return "bell.fill"
        case .alertSent: return "exclamationmark.triangle.fill"
        case .responding: return "figure.walk"
        }
    }
}
#endif
