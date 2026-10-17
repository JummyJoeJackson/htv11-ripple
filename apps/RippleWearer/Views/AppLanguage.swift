import RippleKit
import SwiftUI

/// The language the iPhone app shows. "Match iPhone" follows the phone's own
/// language. Translations live in Localizable.xcstrings; anything not yet
/// translated shows in English.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"

    static let storageKey = "ripple.language"

    var id: String { rawValue }

    /// Each language's name written in that language, so anyone can find theirs.
    var nativeName: String {
        switch self {
        case .system: return "Match iPhone"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        }
    }

    /// The locale screens use. Nil means follow the phone.
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }
}

extension View {
    /// Shows this view in the language picked in Settings.
    func appLanguage(_ code: String) -> some View {
        environment(\.locale, AppLanguage(rawValue: code)?.locale ?? .autoupdatingCurrent)
    }
}

/// A language picker row, used in Settings and on the first screen.
struct LanguagePicker: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue

    var body: some View {
        Picker(selection: $language) {
            ForEach(AppLanguage.allCases) { option in
                // "Match iPhone" is translated; the language names stay in their own language.
                if option == .system {
                    Text("Match iPhone").tag(option.rawValue)
                } else {
                    Text(verbatim: option.nativeName).tag(option.rawValue)
                }
            }
        } label: {
            Label("Language", systemImage: "globe")
        }
        .pickerStyle(.menu)
        .accessibilityHint("Changes the language of the app.")
    }
}
