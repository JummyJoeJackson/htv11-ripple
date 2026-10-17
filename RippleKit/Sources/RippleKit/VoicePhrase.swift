import Foundation

/// Matches the spoken dismiss phrase. Speech recognition writes the same
/// words in different ways ("OK" or "okay", "I'm" or "I am"), so both sides
/// are normalized to words before comparing.
public enum VoicePhrase {
    /// True when the spoken text contains the phrase as whole words, in order.
    /// "I'm not okay" never matches "I'm okay".
    public static func matches(_ spoken: String, phrase: String) -> Bool {
        let wanted = words(phrase)
        let heard = words(spoken)
        guard !wanted.isEmpty, heard.count >= wanted.count else { return false }
        return (0...(heard.count - wanted.count)).contains { start in
            Array(heard[start..<start + wanted.count]) == wanted
        }
    }

    static func words(_ text: String) -> [String] {
        let cleaned = text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        return cleaned.split(whereSeparator: \.isWhitespace).flatMap { word -> [String] in
            switch word {
            case "ok": return ["okay"]
            case "im": return ["i", "am"]
            default: return [String(word)]
            }
        }
    }
}
