import Foundation

/// The five states of the Watch circle (PRD: green Monitoring, yellow Check
/// in, red Alert sent, blue Contact responding, gray Off).
public enum CircleMode: String, Codable, Sendable {
    case off, monitoring, checkIn, alertSent, responding

    /// True while an alarm the wearer can see is open.
    public var isAlarm: Bool { self == .checkIn || self == .alertSent || self == .responding }
}

/// What the Watch shows. Built by the iPhone. A duress alarm never appears here.
public struct WatchDisplay: Codable, Equatable, Sendable {
    public var mode: CircleMode
    /// Text inside the circle: Start, Stop, I'm okay, I'm okay now.
    public var circleLabel: String
    /// Short status line, for example "Monitoring" or "Sam is responding".
    public var status: String
    public var alarmId: String?
    /// End of the response countdown while checking in.
    public var deadline: Date?
    /// Whether the iPhone can currently act (false during a simulated phone failure).
    public var phoneAvailable: Bool
    public var updatedAt: Date
    /// Set while a dose is due and "Took my meds" hasn't been tapped. Only
    /// while monitoring with no alarm open. Older saved displays load as nil.
    public var medsDueAt: Date?

    public init(mode: CircleMode, circleLabel: String, status: String, alarmId: String?, deadline: Date?, phoneAvailable: Bool, updatedAt: Date, medsDueAt: Date? = nil) {
        self.mode = mode
        self.circleLabel = circleLabel
        self.status = status
        self.alarmId = alarmId
        self.deadline = deadline
        self.phoneAvailable = phoneAvailable
        self.updatedAt = updatedAt
        self.medsDueAt = medsDueAt
    }

    public static let off = WatchDisplay(mode: .off, circleLabel: "Start", status: "Off", alarmId: nil, deadline: nil, phoneAvailable: true, updatedAt: Date())

    /// True when two displays would look the same.
    public func sameContent(as other: WatchDisplay?) -> Bool {
        guard let other else { return false }
        var a = self
        var b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }
}

/// The part of the configuration the Watch keeps. It retains the last one it
/// received, even when the iPhone isn't reachable.
public struct WatchConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var doubleTapEnabled: Bool
    public var voiceEnabled: Bool
    public var voicePhrase: String
    /// Swipe up twice for help, down twice for I'm okay.
    public var combosEnabled: Bool
    public var handGesturesEnabled: Bool
    public var handGesturePreset: HandGesturePreset
    /// The sequence that starts an alarm only when no alarm is open.
    public var handGestureHelpEnabled: Bool
    public var handGestureHelpPreset: HandGesturePreset

    public init(version: Int, doubleTapEnabled: Bool, voiceEnabled: Bool, voicePhrase: String, combosEnabled: Bool = true, handGesturesEnabled: Bool = false, handGesturePreset: HandGesturePreset = .pinchClench, handGestureHelpEnabled: Bool = false, handGestureHelpPreset: HandGesturePreset? = nil) {
        self.version = version
        self.doubleTapEnabled = doubleTapEnabled
        self.voiceEnabled = voiceEnabled
        self.voicePhrase = voicePhrase
        self.combosEnabled = combosEnabled
        self.handGesturesEnabled = handGesturesEnabled
        self.handGesturePreset = handGesturePreset
        self.handGestureHelpEnabled = handGestureHelpEnabled
        self.handGestureHelpPreset = handGestureHelpPreset ?? .defaultHelp(besides: handGesturePreset)
    }

    /// Dismissal and alarm triggering never listen at the same time, even
    /// when dismissal is disabled or an alarm display has no identifier yet.
    public func handGestureBindings(for display: WatchDisplay) -> [HandGestureBinding] {
        if display.mode.isAlarm {
            guard handGesturesEnabled, display.alarmId != nil else { return [] }
            return [HandGestureBinding(preset: handGesturePreset, action: .okay)]
        }
        guard handGestureHelpEnabled, handGestureHelpPreset != handGesturePreset else { return [] }
        return [HandGestureBinding(preset: handGestureHelpPreset, action: .help)]
    }

    private enum CodingKeys: String, CodingKey {
        case version, doubleTapEnabled, voiceEnabled, voicePhrase, combosEnabled, handGesturesEnabled, handGesturePreset,
             handGestureHelpEnabled, handGestureHelpPreset
    }

    /// Older settings still load; new hand gestures need explicit opt-in.
    /// Unknown future presets, and a help preset identical to the dismiss
    /// preset, are disabled rather than mapped to another action.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try? container.decode(HandGesturePreset.self, forKey: .handGesturePreset)
        let helpPreset = (try? container.decode(HandGesturePreset.self, forKey: .handGestureHelpPreset))
            .flatMap { HandGesturePreset.helpChoices(besides: preset ?? .pinchClench).contains($0) ? $0 : nil }
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            doubleTapEnabled: try container.decode(Bool.self, forKey: .doubleTapEnabled),
            voiceEnabled: try container.decode(Bool.self, forKey: .voiceEnabled),
            voicePhrase: try container.decode(String.self, forKey: .voicePhrase),
            combosEnabled: try container.decodeIfPresent(Bool.self, forKey: .combosEnabled) ?? true,
            handGesturesEnabled: (try container.decodeIfPresent(Bool.self, forKey: .handGesturesEnabled) ?? false) && preset != nil,
            handGesturePreset: preset ?? .pinchClench,
            handGestureHelpEnabled: (try container.decodeIfPresent(Bool.self, forKey: .handGestureHelpEnabled) ?? false) && helpPreset != nil,
            handGestureHelpPreset: helpPreset
        )
    }

    public static let fallback = WatchConfig(version: 0, doubleTapEnabled: true, voiceEnabled: false, voicePhrase: "I am currently fine")
}

public enum WatchActionKind: String, Codable, Sendable {
    /// Monitoring off: tap or hold the circle.
    case start
    /// Monitoring on: hold, then confirm "Stop monitoring?".
    case stop
    /// Alarm: tap the circle. Also used by double tap and the voice phrase.
    case dismiss
    /// Alarm: hold the circle for 2 seconds. Duress. Touch only.
    case hold
    /// Swipe up twice in any state, or complete the alarm hand gesture when
    /// no alarm is open. Texts contacts now, without a countdown. Never duress.
    case help
    /// A dose is due: tap the circle. Records "Took my meds"; never starts or ends an alarm.
    case tookMeds
}

public enum DismissMethod: String, Codable, Sendable {
    /// `combo` covers swipe combinations and the selected AssistiveTouch
    /// shortcut sequences. Like swipes, they confirm "I'm okay" or ask for
    /// help; duress stays the touch-only hold.
    case touch, doubleTap, voice, combo
}

public struct WatchAction: Codable, Sendable {
    /// Also the de-duplication key, so a repeated tap never repeats an action.
    public var id: String
    public var kind: WatchActionKind
    public var method: DismissMethod
    /// The alarm the wearer saw when they acted.
    public var alarmId: String?
    public var sentAt: Date

    public init(id: String = RippleID.make(bytes: 8), kind: WatchActionKind, method: DismissMethod = .touch, alarmId: String?, sentAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.method = method
        self.alarmId = alarmId
        self.sentAt = sentAt
    }
}

public struct ActionResult: Codable, Equatable, Sendable {
    public var ok: Bool
    /// Shown briefly on the Watch, for example "Dismissed".
    public var feedback: String

    public init(ok: Bool, feedback: String) {
        self.ok = ok
        self.feedback = feedback
    }
}

public struct WatchActionReply: Codable, Sendable {
    public var actionId: String
    public var result: ActionResult
    public var display: WatchDisplay

    public init(actionId: String, result: ActionResult, display: WatchDisplay) {
        self.actionId = actionId
        self.result = result
        self.display = display
    }
}

public struct WatchConfigAck: Codable, Sendable {
    public var version: Int
    public init(version: Int) { self.version = version }
}

/// Listening for the voice phrase. watchOS has no speech recognition, so
/// during an alarm the Watch streams its microphone to the iPhone, which
/// recognizes it and sends back what it heard.
public enum VoiceAudio {
    /// Mono 16-bit little-endian PCM at this rate.
    public static let sampleRate: Double = 16_000
}

/// From the iPhone: what one listening session has heard so far, or why the
/// iPhone can't listen.
public struct VoiceHeard: Codable, Sendable {
    public var sessionId: String
    /// The best guess.
    public var text: String
    /// Other guesses, also checked for the phrase.
    public var alternatives: [String]
    /// Set when the iPhone can't recognize speech, for example without permission.
    public var problem: String?

    public init(sessionId: String, text: String, alternatives: [String] = [], problem: String? = nil) {
        self.sessionId = sessionId
        self.text = text
        self.alternatives = alternatives
        self.problem = problem
    }
}

/// WatchConnectivity carries property-list dictionaries, so each message is a
/// type name plus a JSON payload.
public enum WatchEnvelope {
    public static let typeKey = "type"
    public static let payloadKey = "payload"

    public static let display = "display"
    public static let config = "config"
    public static let action = "action"
    public static let reply = "reply"
    public static let configAck = "configAck"
    public static let ping = "ping"
    public static let hello = "hello"
    public static let voiceAudio = "voiceAudio"
    public static let voiceStop = "voiceStop"
    public static let voiceHeard = "voiceHeard"
    public static let sessionKey = "session"

    public static func make<T: Encodable>(_ type: String, _ value: T) -> [String: Any] {
        guard let data = try? RippleJSON.encoder.encode(value) else {
            return [typeKey: type]
        }
        return [typeKey: type, payloadKey: data]
    }

    /// The application context carries both the display and the configuration.
    public static func context(display: WatchDisplay, config: WatchConfig) -> [String: Any] {
        var result: [String: Any] = [typeKey: "context"]
        if let data = try? RippleJSON.encoder.encode(display) { result[WatchEnvelope.display] = data }
        if let data = try? RippleJSON.encoder.encode(config) { result[WatchEnvelope.config] = data }
        return result
    }

    public static func type(of message: [String: Any]) -> String? {
        message[typeKey] as? String
    }

    /// Microphone audio goes as raw bytes, not JSON, to keep messages small.
    public static func makeVoiceAudio(session: String, audio: Data) -> [String: Any] {
        [typeKey: voiceAudio, sessionKey: session, payloadKey: audio]
    }

    public static func decodeVoiceAudio(from message: [String: Any]) -> (session: String, audio: Data)? {
        guard let session = message[sessionKey] as? String, let audio = message[payloadKey] as? Data else { return nil }
        return (session, audio)
    }

    public static func makeVoiceStop(session: String) -> [String: Any] {
        [typeKey: voiceStop, sessionKey: session]
    }

    public static func decode<T: Decodable>(_ type: T.Type, from message: [String: Any], key: String = payloadKey) -> T? {
        guard let data = message[key] as? Data else { return nil }
        return try? RippleJSON.decoder.decode(T.self, from: data)
    }
}
