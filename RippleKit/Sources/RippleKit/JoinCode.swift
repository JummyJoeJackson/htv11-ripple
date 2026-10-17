import Foundation

/// Invitation replies use six digits and a separate command from alarm replies.
public enum JoinCode {
    public static func code(in text: String) -> String? {
        let pattern = "ripple[^a-z0-9]*join[^0-9]*([0-9]{6})(?![0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let codeRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[codeRange])
    }
}
