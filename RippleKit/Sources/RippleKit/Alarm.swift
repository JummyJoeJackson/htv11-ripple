import Foundation

public enum AlarmSource: String, Codable, Sendable {
    /// The check-in timer while monitoring is on.
    case timer
    /// A command from the demo admin app.
    case admin
    /// Started from the wearer's iPhone.
    case phone
    /// The wearer asked for help with a swipe combo on the Watch.
    case help
}

public enum AlarmPhase: String, Codable, Sendable {
    /// Waiting for the wearer to respond on the Watch.
    case countdown
    /// Tier 1 has been texted.
    case alerted
    /// Tier 2 has been texted (or there was no Tier 2 to text).
    case escalated
    case closed
}

public enum CloseReason: String, Codable, Sendable {
    case dismissed, okayNow, disabled, reset

    public var label: String {
        switch self {
        case .dismissed: return "Dismissed"
        case .okayNow: return "Okay now"
        case .disabled: return "Disabled by demo admin"
        case .reset: return "Demo reset"
        }
    }
}

public enum MessageKind: String, Codable, Sendable {
    case alert, escalation, responding, okayNow

    public var label: String {
        switch self {
        case .alert: return "Alert"
        case .escalation: return "Escalation"
        case .responding: return "Someone responding"
        case .okayNow: return "Okay now"
        }
    }
}

/// Opening the Shortcuts URL or handing a text to Twilio is not proof that a
/// person received it, so "delivered" is never claimed.
public enum MessageStatus: String, Codable, Sendable {
    case pending, submitted, failed, unknown, cancelled

    public var label: String {
        switch self {
        case .pending: return "Pending"
        case .submitted: return "Submitted"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        case .cancelled: return "Not sent"
        }
    }

    /// Sent, or possibly sent. Either way it can't be recalled.
    public var mayHaveBeenSent: Bool { self == .submitted || self == .unknown }
}

public enum SendPath: String, Codable, Sendable {
    /// Sent from the wearer's iPhone through the Ripple Alert shortcut.
    case phone
    /// Sent by the backend through Twilio because the phone went quiet.
    case backup

    public var label: String { self == .phone ? "Wearer's iPhone" : "Backend backup" }
}

/// One person who may be texted for an alarm, snapshotted when it starts.
public struct AlarmRecipient: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var phone: String
    public var tier: Tier
    public var shareLocation: Bool
    public var temporary: Bool
    /// Random token in this recipient's acknowledge link.
    public var ackToken: String
    /// Prebuilt texts, so the backend can send exactly the same words as backup.
    public var alertText: String
    public var escalationText: String
    /// 4-digit code this recipient can text back ("RIPPLE ACCEPT 4821") instead
    /// of tapping the link. Unique within the alarm, so it also says who replied.
    /// Nil for alarms saved before reply codes existed.
    public var acceptCode: String?

    public init(id: String, name: String, phone: String, tier: Tier, shareLocation: Bool, temporary: Bool, ackToken: String, alertText: String, escalationText: String, acceptCode: String? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.tier = tier
        self.shareLocation = shareLocation
        self.temporary = temporary
        self.ackToken = ackToken
        self.alertText = alertText
        self.escalationText = escalationText
        self.acceptCode = acceptCode
    }
}

public struct OutMessage: Codable, Hashable, Identifiable, Sendable {
    /// `alarmId:recipientId:kind`, shared by the phone and the backend so the
    /// same message is never sent twice for one alarm and recipient.
    public var id: String
    public var alarmId: String
    public var recipientId: String
    public var recipientName: String
    public var phone: String
    public var kind: MessageKind
    public var text: String
    public var status: MessageStatus
    public var path: SendPath
    public var createdAt: Date
    public var updatedAt: Date
    public var detail: String?
    /// Set when the phone handed the message to the Shortcuts app. It may have
    /// been sent from then on, so it can no longer be cancelled.
    public var launchedAt: Date?

    public init(alarmId: String, recipientId: String, recipientName: String, phone: String, kind: MessageKind, text: String, status: MessageStatus, path: SendPath, createdAt: Date, detail: String? = nil) {
        self.id = OutMessage.makeId(alarmId: alarmId, recipientId: recipientId, kind: kind)
        self.alarmId = alarmId
        self.recipientId = recipientId
        self.recipientName = recipientName
        self.phone = phone
        self.kind = kind
        self.text = text
        self.status = status
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.detail = detail
        self.launchedAt = nil
    }

    /// Sent, possibly sent, or already handed to the Shortcuts app.
    public var mayHaveBeenSent: Bool {
        status.mayHaveBeenSent || (status == .pending && launchedAt != nil)
    }

    /// Still waiting and not yet handed off, so it can be cancelled.
    public var isCancellable: Bool {
        status == .pending && launchedAt == nil
    }

    public static func makeId(alarmId: String, recipientId: String, kind: MessageKind) -> String {
        "\(alarmId):\(recipientId):\(kind.rawValue)"
    }
}

public struct Acknowledgment: Codable, Hashable, Sendable {
    public var recipientId: String
    public var name: String
    public var at: Date

    public init(recipientId: String, name: String, at: Date) {
        self.recipientId = recipientId
        self.name = name
        self.at = at
    }
}

/// One alarm, owned by the wearer's iPhone and mirrored to the backend.
public struct Alarm: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var runId: String
    public var source: AlarmSource
    public var startedAt: Date
    /// End of the response countdown.
    public var deadline: Date
    public var countdownSeconds: Int
    public var ackWindowSeconds: Int
    public var phase: AlarmPhase
    public var closeReason: CloseReason?
    public var closedAt: Date?
    /// Never displayed on the Watch or the wearer's iPhone.
    public var duress: Bool
    /// When Tier 1 was first texted.
    public var alertedAt: Date?
    public var escalatedAt: Date?
    public var acknowledgment: Acknowledgment?
    public var wearerName: String
    public var recipients: [AlarmRecipient]
    /// One fix taken when the alarm started. Never tracked in the background.
    public var location: LocationFix?
    public var messages: [OutMessage]
    /// When the wearer asked for help. Texts not yet sent say so instead of "did not respond".
    public var helpRequestedAt: Date? = nil

    public init(id: String, runId: String, source: AlarmSource, startedAt: Date, deadline: Date, countdownSeconds: Int, ackWindowSeconds: Int, phase: AlarmPhase, closeReason: CloseReason?, closedAt: Date?, duress: Bool, alertedAt: Date?, escalatedAt: Date?, acknowledgment: Acknowledgment?, wearerName: String, recipients: [AlarmRecipient], location: LocationFix?, messages: [OutMessage]) {
        self.id = id
        self.runId = runId
        self.source = source
        self.startedAt = startedAt
        self.deadline = deadline
        self.countdownSeconds = countdownSeconds
        self.ackWindowSeconds = ackWindowSeconds
        self.phase = phase
        self.closeReason = closeReason
        self.closedAt = closedAt
        self.duress = duress
        self.alertedAt = alertedAt
        self.escalatedAt = escalatedAt
        self.acknowledgment = acknowledgment
        self.wearerName = wearerName
        self.recipients = recipients
        self.location = location
        self.messages = messages
    }

    public var isOpen: Bool { phase != .closed }

    /// End of the acknowledge window, once Tier 1 has been texted.
    public var ackDeadline: Date? {
        alertedAt.map { $0.addingTimeInterval(TimeInterval(ackWindowSeconds)) }
    }

    public func message(_ id: String) -> OutMessage? {
        messages.first { $0.id == id }
    }

    /// Recipients who were sent an alert or escalation that can't be recalled.
    public var textedRecipientIds: [String] {
        var seen: [String] = []
        for message in messages where (message.kind == .alert || message.kind == .escalation) && message.mayHaveBeenSent {
            if !seen.contains(message.recipientId) { seen.append(message.recipientId) }
        }
        return seen
    }

    /// Adds or replaces a message, keeping one entry per id.
    public mutating func upsert(_ message: OutMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }
}

/// Who gets which text. Shared by the phone and the backend so both make the
/// same decision.
public enum RecipientRules {
    /// Tier 1 for the alert: permanent Tier 1 plus temporary contacts that are
    /// active right now. If nobody in Tier 1 is eligible, Tier 2 gets the alert.
    public static func alertRecipients(_ alarm: Alarm, isEligible: (AlarmRecipient) -> Bool) -> [AlarmRecipient] {
        let tierOne = alarm.recipients.filter { $0.tier == .one && isEligible($0) }
        if !tierOne.isEmpty { return tierOne }
        return alarm.recipients.filter { $0.tier == .two && isEligible($0) }
    }

    /// Tier 2, unless Tier 2 already got the alert because Tier 1 was empty.
    public static func escalationRecipients(_ alarm: Alarm, isEligible: (AlarmRecipient) -> Bool) -> [AlarmRecipient] {
        let alerted = Set(alertRecipients(alarm, isEligible: isEligible).map(\.id))
        return alarm.recipients.filter { $0.tier == .two && isEligible($0) && !alerted.contains($0.id) }
    }
}

/// Message wording from the PRD. No message claims a diagnosis or a confirmed
/// emergency, and a duress alert uses the normal alert text.
public enum MessageTemplates {
    public static let backupNote = " (Sent by Ripple backup.)"

    public static func clockTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    public static func alert(name: String, checkInTime: String, locationURL: String?, helpCard: String?, ackLink: String, acceptCode: String? = nil) -> String {
        var text = "Ripple alert: \(name) did not respond to their Watch check-in at \(checkInTime). Please call or check on them."
        if let locationURL { text += " Location: \(locationURL)" }
        if let helpCard, !helpCard.isEmpty { text += " Note from \(name): \(helpCard)" }
        text += " Tap if you're checking: \(ackLink)" + replyInstruction(acceptCode)
        return text
    }

    public static func escalation(name: String, checkInTime: String, locationURL: String?, ackLink: String, acceptCode: String? = nil) -> String {
        var text = "Ripple alert: \(name) did not respond at \(checkInTime) and no one has confirmed yet. Please call or check on them."
        if let locationURL { text += " Location: \(locationURL)" }
        text += " \(ackLink)" + replyInstruction(acceptCode)
        return text
    }

    public static func help(name: String, time: String, locationURL: String?, helpCard: String?, ackLink: String, acceptCode: String? = nil) -> String {
        var text = "Ripple alert: \(name) asked for help from their Watch at \(time). Please call or check on them."
        if let locationURL { text += " Location: \(locationURL)" }
        if let helpCard, !helpCard.isEmpty { text += " Note from \(name): \(helpCard)" }
        text += " Tap if you're checking: \(ackLink)" + replyInstruction(acceptCode)
        return text
    }

    public static func helpEscalation(name: String, time: String, locationURL: String?, ackLink: String, acceptCode: String? = nil) -> String {
        var text = "Ripple alert: \(name) asked for help at \(time) and no one has confirmed yet. Please call or check on them."
        if let locationURL { text += " Location: \(locationURL)" }
        text += " \(ackLink)" + replyInstruction(acceptCode)
        return text
    }

    /// " or reply RIPPLE ACCEPT 4821", or nothing without a code.
    static func replyInstruction(_ acceptCode: String?) -> String {
        guard let acceptCode, !acceptCode.isEmpty else { return "" }
        return " or reply \(ReplyCode.keyword) \(acceptCode)"
    }

    public static func responding(contact: String, name: String) -> String {
        "Ripple: \(contact) is checking on \(name)."
    }

    public static func okayNow(name: String, time: String) -> String {
        "Ripple: \(name) says they're okay now (\(time)). No action needed."
    }

    public static func ackLink(baseURL: String, token: String) -> String {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        return base + "/a/" + token
    }
}

/// Text replies that acknowledge an alert: "RIPPLE ACCEPT 4821". The wearer's
/// iPhone receives them through a Messages automation and the Ripple Accept
/// shortcut, which opens ripple://accept?text=<the reply>.
public enum ReplyCode {
    public static let keyword = "RIPPLE ACCEPT"

    /// The 4-digit code in a reply, ignoring case, spacing and punctuation,
    /// for example "ripple accept 4821", "Ripple  Accept: 4821!" or
    /// "RIPPLE-ACCEPT 4821 on my way". Nil if there is none.
    public static func acceptCode(in text: String) -> String? {
        let pattern = "ripple[^a-z0-9]*accept[^0-9]*([0-9]{4})(?![0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let codeRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[codeRange])
    }

    /// Distinct 4-digit codes, one per recipient of an alarm.
    public static func makeCodes(count: Int) -> [String] {
        var generator = SystemRandomNumberGenerator()
        var codes: [String] = []
        while codes.count < count {
            let code = String(Int.random(in: 1000...9999, using: &generator))
            if !codes.contains(code) { codes.append(code) }
        }
        return codes
    }
}
