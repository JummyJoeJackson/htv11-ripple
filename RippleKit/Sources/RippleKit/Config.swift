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
        case .invited: return "Waiting for reply"
        case .active: return "Active"
        case .expired: return "Expired"
        case .removed: return "Removed"
        }
    }
}

/// Someone who agreed to be a contact for a one-hour session. Stored on the
/// backend, which starts the session when their text reply is accepted.
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
/// One usual dose time, like 1:00 PM, in the wearer's own time zone.
public struct MedicationTime: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var hour: Int
    public var minute: Int

    public init(id: String = RippleID.make(bytes: 6), hour: Int, minute: Int) {
        self.id = id
        self.hour = hour
        self.minute = minute
    }
}

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
    /// Accept the selected AssistiveTouch shortcut sequence to dismiss an alarm.
    public var handGesturesEnabled: Bool
    public var handGesturePreset: HandGesturePreset
    /// Accept a second sequence that asks for help in any state, like swiping
    /// up twice. Never duress, and never overlapping the dismiss sequence.
    public var handGestureHelpEnabled: Bool
    public var handGestureHelpPreset: HandGesturePreset
    /// Name of the user-installed shortcut that sends the texts.
    public var shortcutName: String
    /// Usual dose times. At each one the Watch asks for "Took my meds".
    public var medicationTimes: [MedicationTime]
    /// Minutes to wait for "Took my meds" before a gentle check-in starts.
    public var medicationGraceMinutes: Int
    /// Check in when Apple Watch records a fall in Apple Health.
    public var healthFallsEnabled: Bool
    /// Check in when Apple Watch records a high, low or irregular heart rhythm alert.
    public var healthHeartEnabled: Bool

    /// Without a help preset, the default one that doesn't overlap the dismiss preset.
    public init(version: Int, wearerName: String, contacts: [PermanentContact], helpCardEnabled: Bool, helpCard: String, checkInIntervalMinutes: Int, countdownSeconds: Int, ackWindowSeconds: Int, doubleTapEnabled: Bool, voiceEnabled: Bool, voicePhrase: String, shortcutName: String, combosEnabled: Bool = true, handGesturesEnabled: Bool = false, handGesturePreset: HandGesturePreset = .pinchClench, handGestureHelpEnabled: Bool = false, handGestureHelpPreset: HandGesturePreset? = nil, medicationTimes: [MedicationTime] = [], medicationGraceMinutes: Int = 30, healthFallsEnabled: Bool = false, healthHeartEnabled: Bool = false) {
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
        self.handGesturesEnabled = handGesturesEnabled
        self.handGesturePreset = handGesturePreset
        self.handGestureHelpEnabled = handGestureHelpEnabled
        self.handGestureHelpPreset = handGestureHelpPreset ?? .defaultHelp(besides: handGesturePreset)
        self.shortcutName = shortcutName
        self.medicationTimes = medicationTimes
        self.medicationGraceMinutes = medicationGraceMinutes
        self.healthFallsEnabled = healthFallsEnabled
        self.healthHeartEnabled = healthHeartEnabled
    }

    /// The Apple Health alerts the wearer chose to turn into check-ins.
    public var healthAlerts: Set<HealthAlertKind> {
        var kinds: Set<HealthAlertKind> = []
        if healthFallsEnabled { kinds.insert(.fall) }
        if healthHeartEnabled { kinds.insert(.heart) }
        return kinds
    }

    private enum CodingKeys: String, CodingKey {
        case version, wearerName, contacts, helpCardEnabled, helpCard, checkInIntervalMinutes, countdownSeconds,
             ackWindowSeconds, doubleTapEnabled, voiceEnabled, voicePhrase, combosEnabled, shortcutName,
             handGesturesEnabled, handGesturePreset, handGestureHelpEnabled, handGestureHelpPreset,
             medicationTimes, medicationGraceMinutes,
             healthFallsEnabled, healthHeartEnabled
    }

    /// Older settings still load without losing contacts. Hand gestures need
    /// explicit opt-in, and unknown future presets stay disabled. So does a
    /// help preset that overlaps the dismiss preset.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try? container.decode(HandGesturePreset.self, forKey: .handGesturePreset)
        let helpPreset = (try? container.decode(HandGesturePreset.self, forKey: .handGestureHelpPreset))
            .flatMap { HandGesturePreset.helpChoices(besides: preset ?? .pinchClench).contains($0) ? $0 : nil }
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
            combosEnabled: try container.decodeIfPresent(Bool.self, forKey: .combosEnabled) ?? true,
            handGesturesEnabled: (try container.decodeIfPresent(Bool.self, forKey: .handGesturesEnabled) ?? false) && preset != nil,
            handGesturePreset: preset ?? .pinchClench,
            handGestureHelpEnabled: (try container.decodeIfPresent(Bool.self, forKey: .handGestureHelpEnabled) ?? false) && helpPreset != nil,
            handGestureHelpPreset: helpPreset,
            medicationTimes: try container.decodeIfPresent([MedicationTime].self, forKey: .medicationTimes) ?? [],
            medicationGraceMinutes: try container.decodeIfPresent(Int.self, forKey: .medicationGraceMinutes) ?? 30,
            // Health alerts need Apple Health permission, so they're opt-in.
            healthFallsEnabled: try container.decodeIfPresent(Bool.self, forKey: .healthFallsEnabled) ?? false,
            healthHeartEnabled: try container.decodeIfPresent(Bool.self, forKey: .healthHeartEnabled) ?? false
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
            voicePhrase: "I am currently fine",
            shortcutName: "Ripple Alert"
        )
    }

    /// The part of the configuration the Watch needs.
    public var watchConfig: WatchConfig {
        WatchConfig(version: version, doubleTapEnabled: doubleTapEnabled, voiceEnabled: voiceEnabled, voicePhrase: voicePhrase, combosEnabled: combosEnabled, handGesturesEnabled: handGesturesEnabled, handGesturePreset: handGesturePreset, handGestureHelpEnabled: handGestureHelpEnabled, handGestureHelpPreset: handGestureHelpPreset)
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
