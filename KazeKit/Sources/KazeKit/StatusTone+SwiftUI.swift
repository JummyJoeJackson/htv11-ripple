#if canImport(SwiftUI)
import SwiftUI

public extension StatusTone {
    /// Green safe, yellow awaiting response, red alert, blue acknowledged, gray resolved (PRD §7).
    var color: Color {
        switch self {
        case .safe: return .green
        case .awaiting: return .yellow
        case .alert: return .red
        case .acknowledged: return .blue
        case .resolved: return .gray
        case .neutral: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .awaiting: return "clock.badge.exclamationmark"
        case .alert: return "exclamationmark.triangle.fill"
        case .acknowledged: return "person.fill.checkmark"
        case .resolved: return "checkmark.circle"
        case .neutral: return "circle.dashed"
        }
    }
}
#endif
