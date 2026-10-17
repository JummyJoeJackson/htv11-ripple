import Crypto
import Foundation

enum Secrets {
    /// URL-safe random token. 32 bytes by default.
    static func randomToken(bytes: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let data = Data((0..<bytes).map { _ in UInt8.random(in: 0...255, using: &generator) })
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomDigits(_ count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in String(Int.random(in: 0...9, using: &generator)) }.joined()
    }

    static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hashPin(_ pin: String, salt: String) -> String {
        hash(salt + ":" + pin)
    }
}

enum Phone {
    /// Normalizes to E.164. Ten-digit numbers are treated as North American.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber }
        if trimmed.hasPrefix("+") {
            return (8...15).contains(digits.count) ? "+" + digits : nil
        }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11 && digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    static func hint(_ phone: String) -> String {
        "•••• " + String(phone.suffix(4))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
