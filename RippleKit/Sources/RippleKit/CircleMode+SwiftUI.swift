#if canImport(SwiftUI)
import SwiftUI

public extension CircleMode {
    /// Green Monitoring, yellow Check in, red Alert sent, blue Contact
    /// responding, gray Off. Always shown together with text.
    var color: Color {
        switch self {
        case .off: return .gray
        case .monitoring: return .green
        case .checkIn: return .yellow
        case .alertSent: return .red
        case .responding: return .blue
        }
    }

    var symbol: String {
        switch self {
        case .off: return "power"
        case .monitoring: return "checkmark"
        case .checkIn: return "exclamationmark"
        case .alertSent: return "paperplane.fill"
        case .responding: return "person.fill.checkmark"
        }
    }
}
#endif
