import Foundation

public enum Tier: Int, Codable, Sendable, CaseIterable {
    /// Texted first.
    case one = 1
    /// Texted if nobody in Tier 1 acknowledges within the acknowledge window.
    case two = 2

    public var label: String { self == .one ? "Tier 1" : "Tier 2" }
}

/// A permanent contact, configured on the wearer's iPhone.
public struct PermanentContact: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var phone: String
    public var tier: Tier
    /// "Share my location in alerts." Off by default.
    public var shareLocation: Bool

    public init(id: String = RippleID.make(bytes: 8), name: String, phone: String, tier: Tier = .one, shareLocation: Bool = false) {
        self.id = id
        self.name = name
        self.phone = phone
        self.tier = tier
        self.shareLocation = shareLocation
    }
}

public enum TemporaryContactState: String, Codable, Sendable {
    /// Invitation created; they haven't agreed yet.
    case invited
    /// They agreed. Part of Tier 1 until the session expires.
    case active
    case expired
    case removed

    public var label: String {
        switch self {
        case .invited: return "Waiting for consent"
        case .active: return "Active"
        case .expired: return "Expired"
        case .removed: return "Removed"
        }
    }
}

/// Someone who agreed to be a contact for a one-hour session. Stored on the
/// backend because they consent on a web page.
public struct TemporaryContactView: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var phone: String
    public var shareLocation: Bool
    public var state: TemporaryContactState
    public var invitedAt: Date
    public var consentAt: Date?
    public var expiresAt: Date?

    public init(id: String, name: String, phone: String, shareLocation: Bool, state: TemporaryContactState, invitedAt: Date, consentAt: Date?, expiresAt: Date?) {
        self.id = id
        self.name = name
        self.phone = phone
        self.shareLocation = shareLocation
        self.state = state
        self.invitedAt = invitedAt
        self.consentAt = consentAt
        self.expiresAt = expiresAt
    }

    /// Expired or removed contacts never receive new alerts.
    public func isEligible(at date: Date) -> Bool {
        state == .active && (expiresAt ?? .distantPast) > date
    }
}

/// Everything the wearer configures on their iPhone.
public struct RippleConfig: Codable, Equatable, Sendable {
    /// Bumped on every save, so the Watch can confirm which version it has.
    public var version: Int
    public var wearerName: String
    public var contacts: [PermanentContact]
    public var helpCardEnabled: Bool
    public var helpCard: String
    /// Minutes between automatic check-ins while monitoring is on. 0 turns them off.
    public var checkInIntervalMinutes: Int
    /// Seconds the wearer has to answer an alarm.
    public var countdownSeconds: Int
    /// Seconds Tier 1 has to acknowledge before Tier 2 is texted.
    public var ackWindowSeconds: Int
    public var doubleTapEnabled: Bool
    public var voiceEnabled: Bool
    public var voicePhrase: String
    /// Swipe up twice for help, down twice for I'm okay.
    public var combosEnabled: Bool
    /// Name of the user-installed shortcut that sends the texts.
    public var shortcutName: String

    public init(version: Int, wearerName: String, contacts: [PermanentContact], helpCardEnabled: Bool, helpCard: String, checkInIntervalMinutes: Int, countdownSeconds: Int, ackWindowSeconds: Int, doubleTapEnabled: Bool, voiceEnabled: Bool, voicePhrase: String, shortcutName: String, combosEnabled: Bool = true) {
        self.version = version
        self.wearerName = wearerName
        self.contacts = contacts
        self.helpCardEnabled = helpCardEnabled
        self.helpCard = helpCard
        self.checkInIntervalMinutes = checkInIntervalMinutes
        self.countdownSeconds = countdownSeconds
        self.ackWindowSeconds = ackWindowSeconds
        self.doubleTapEnabled = doubleTapEnabled
        self.voiceEnabled = voiceEnabled
        self.voicePhrase = voicePhrase
        self.combosEnabled = combosEnabled
        self.shortcutName = shortcutName
    }

    private enum CodingKeys: String, CodingKey {
        case version, wearerName, contacts, helpCardEnabled, helpCard, checkInIntervalMinutes, countdownSeconds,
             ackWindowSeconds, doubleTapEnabled, voiceEnabled, voicePhrase, combosEnabled, shortcutName
    }

    /// Settings saved before swipe combos existed still load, with combos on,
    /// so updating the app never loses the wearer's contacts.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            wearerName: try container.decode(String.self, forKey: .wearerName),
            contacts: try container.decode([PermanentContact].self, forKey: .contacts),
            helpCardEnabled: try container.decode(Bool.self, forKey: .helpCardEnabled),
            helpCard: try container.decode(String.self, forKey: .helpCard),
            checkInIntervalMinutes: try container.decode(Int.self, forKey: .checkInIntervalMinutes),
            countdownSeconds: try container.decode(Int.self, forKey: .countdownSeconds),
            ackWindowSeconds: try container.decode(Int.self, forKey: .ackWindowSeconds),
            doubleTapEnabled: try container.decode(Bool.self, forKey: .doubleTapEnabled),
            voiceEnabled: try container.decode(Bool.self, forKey: .voiceEnabled),
            voicePhrase: try container.decode(String.self, forKey: .voicePhrase),
            shortcutName: try container.decode(String.self, forKey: .shortcutName),
            combosEnabled: try container.decodeIfPresent(Bool.self, forKey: .combosEnabled) ?? true
        )
    }

    /// Demo defaults: 15-second timers (PRD), automatic check-ins off.
    public static func makeDefault(wearerName: String) -> RippleConfig {
        RippleConfig(
            version: 1,
            wearerName: wearerName,
            contacts: [],
            helpCardEnabled: false,
            helpCard: "",
            checkInIntervalMinutes: 0,
            countdownSeconds: 15,
            ackWindowSeconds: 15,
            doubleTapEnabled: true,
            voiceEnabled: false,
            voicePhrase: "I'm okay",
            shortcutName: "Ripple Alert"
        )
    }

    /// The part of the configuration the Watch needs.
    public var watchConfig: WatchConfig {
        WatchConfig(version: version, doubleTapEnabled: doubleTapEnabled, voiceEnabled: voiceEnabled, voicePhrase: voicePhrase, combosEnabled: combosEnabled)
    }
}

public struct LocationFix: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracyMeters: Double
    public var capturedAt: Date

    public init(latitude: Double, longitude: Double, accuracyMeters: Double, capturedAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.capturedAt = capturedAt
    }

    public var mapURL: String {
        "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=Last%20known%20location"
    }
}

public enum Phone {
    /// Normalizes to E.164. Ten-digit numbers are treated as North American.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber }
        if trimmed.hasPrefix("+") {
            return (8...15).contains(digits.count) ? "+" + digits : nil
        }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11 && digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    public static func hint(_ phone: String) -> String {
        "•••• " + String(phone.suffix(4))
    }
}
