import Foundation

enum RippleShortcut: String, CaseIterable, Identifiable {
    case alert = "Ripple Alert"
    case accept = "Ripple Accept"
    case pinch = "Ripple Pinch"
    case clench = "Ripple Clench"
    case doublePinch = "Ripple Double Pinch"
    case doubleClench = "Ripple Double Clench"

    var id: String { rawValue }
    static let phone: [Self] = [.alert, .accept]
    static let watch: [Self] = [.pinch, .clench, .doublePinch, .doubleClench]

    var detail: String {
        switch self {
        case .alert: return "Send alert texts from your iPhone"
        case .accept: return "Receive alert and invitation replies"
        case .pinch: return "Assign to pinch in the Watch app"
        case .clench: return "Assign to clench in the Watch app"
        case .doublePinch: return "Assign to double pinch in the Watch app"
        case .doubleClench: return "Assign to double clench in the Watch app"
        }
    }
}

/// Public iCloud sharing links, bundled with the app. Empty entries stay unavailable.
struct ShortcutLinks {
    private let values: [String: String]

    static let bundled: Self = {
        guard let url = Bundle.main.url(forResource: "ShortcutLinks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return Self(values: [:])
        }
        return Self(values: values)
    }()

    func url(for shortcut: RippleShortcut) -> URL? {
        guard let value = values[shortcut.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              url.scheme == "https",
              ["www.icloud.com", "icloud.com"].contains(url.host?.lowercased() ?? ""),
              url.pathComponents.count == 3,
              url.pathComponents[1] == "shortcuts",
              !url.lastPathComponent.isEmpty else { return nil }
        return url
    }
}
