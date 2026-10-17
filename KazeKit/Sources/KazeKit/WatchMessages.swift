import Foundation

// Messages between the wearer's iPhone and the Apple Watch over
// WatchConnectivity. The watch captures input and shows state; it never owns
// a timer that can cause or prevent an alert.

/// What the watch displays. Built by the iPhone from the backend's state.
public struct WatchState: Codable, Equatable, Sendable {
    public var tone: StatusTone
    public var headline: String
    public var detail: String
    public var sessionActive: Bool
    /// Set while a check-in is awaiting a response.
    public var checkInId: String?
    public var respondBy: Date?
    /// Server clock minus iPhone clock, for an accurate countdown.
    public var serverOffset: TimeInterval
    /// For example "Sam acknowledged your alert".
    public var responderLine: String?
    /// Whether the iPhone can currently reach the backend.
    public var phoneOnline: Bool
    public var updatedAt: Date

    public init(tone: StatusTone, headline: String, detail: String, sessionActive: Bool, checkInId: String?, respondBy: Date?, serverOffset: TimeInterval, responderLine: String?, phoneOnline: Bool, updatedAt: Date) {
        self.tone = tone
        self.headline = headline
        self.detail = detail
        self.sessionActive = sessionActive
        self.checkInId = checkInId
        self.respondBy = respondBy
        self.serverOffset = serverOffset
        self.responderLine = responderLine
        self.phoneOnline = phoneOnline
        self.updatedAt = updatedAt
    }

    /// True when two states would look the same on screen.
    public func sameContent(as other: WatchState?) -> Bool {
        guard let other else { return false }
        var a = self
        var b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        a.serverOffset = a.serverOffset.rounded()
        b.serverOffset = b.serverOffset.rounded()
        return a == b
    }

    public static let notSetUp = WatchState(
        tone: .neutral,
        headline: "Open KAZE on iPhone",
        detail: "Finish setup on your iPhone to start a session.",
        sessionActive: false,
        checkInId: nil,
        respondBy: nil,
        serverOffset: 0,
        responderLine: nil,
        phoneOnline: false,
        updatedAt: Date()
    )
}

public enum WatchCommandKind: String, Codable, Sendable {
    case confirm, help
}

public struct WatchCommand: Codable, Sendable {
    /// Also used as the backend idempotency key.
    public var id: String
    public var kind: WatchCommandKind
    public var checkInId: String?
    public var sentAt: Date

    public init(id: String = UUID().uuidString, kind: WatchCommandKind, checkInId: String?, sentAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.checkInId = checkInId
        self.sentAt = sentAt
    }
}

public struct WatchCommandReply: Codable, Sendable {
    public var id: String
    /// True only once the backend accepted the command.
    public var ok: Bool
    public var message: String

    public init(id: String, ok: Bool, message: String) {
        self.id = id
        self.ok = ok
        self.message = message
    }
}

/// WatchConnectivity carries property-list dictionaries, so each message is a
/// type name plus a JSON payload.
public enum WatchEnvelope {
    public static let typeKey = "type"
    public static let payloadKey = "payload"

    public static let state = "state"
    public static let command = "command"
    public static let reply = "reply"
    public static let ping = "ping"
    public static let hello = "hello"

    public static func make<T: Encodable>(_ type: String, _ value: T) -> [String: Any] {
        guard let data = try? KazeJSON.encoder.encode(value) else {
            return [typeKey: type]
        }
        return [typeKey: type, payloadKey: data]
    }

    public static func type(of message: [String: Any]) -> String? {
        message[typeKey] as? String
    }

    public static func decode<T: Decodable>(_ type: T.Type, from message: [String: Any]) -> T? {
        guard let data = message[payloadKey] as? Data else { return nil }
        return try? KazeJSON.decoder.decode(T.self, from: data)
    }
}
