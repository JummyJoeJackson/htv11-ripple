import Foundation

// Request bodies. Every mutating request may also carry an `Idempotency-Key`
// header so retries and repeated taps never create a second logical action.

public struct SetupRequest: Codable, Sendable {
    public var displayName: String
    public init(displayName: String) { self.displayName = displayName }
}

public struct SetupResponse: Codable, Sendable {
    public var userId: String
    public var deviceToken: String
    public var pairingCode: String
    public init(userId: String, deviceToken: String, pairingCode: String) {
        self.userId = userId
        self.deviceToken = deviceToken
        self.pairingCode = pairingCode
    }
}

public struct ConfigRequest: Codable, Sendable {
    public var displayName: String
    public var phone: String
    public var helpCard: String
    public var timing: TimingSettings
    public init(displayName: String, phone: String, helpCard: String, timing: TimingSettings) {
        self.displayName = displayName
        self.phone = phone
        self.helpCard = helpCard
        self.timing = timing
    }
}

public struct ContactInput: Codable, Hashable, Sendable, Identifiable {
    /// Nil for a new contact.
    public var id: String?
    public var name: String
    public var phone: String
    public var share: SharePermissions
    public init(id: String? = nil, name: String, phone: String, share: SharePermissions = .contactDefault) {
        self.id = id
        self.name = name
        self.phone = phone
        self.share = share
    }
}

public struct ContactsRequest: Codable, Sendable {
    /// In escalation order: the first contact is alerted first.
    public var contacts: [ContactInput]
    public init(contacts: [ContactInput]) { self.contacts = contacts }
}

public struct PinsRequest: Codable, Sendable {
    public var safetyPin: String
    public var duressPin: String
    public init(safetyPin: String, duressPin: String) {
        self.safetyPin = safetyPin
        self.duressPin = duressPin
    }
}

public struct StartSessionRequest: Codable, Sendable {
    public var venue: String
    /// The backend computes the expected end from its own clock.
    public var durationSeconds: Int
    public init(venue: String, durationSeconds: Int) {
        self.venue = venue
        self.durationSeconds = durationSeconds
    }
}

public struct ExtendSessionRequest: Codable, Sendable {
    public var additionalSeconds: Int
    public init(additionalSeconds: Int) { self.additionalSeconds = additionalSeconds }
}

public struct HeartbeatRequest: Codable, Sendable {
    public var watchReachable: Bool
    public var lastWatchContactAt: Date?
    public var location: LocationFix?
    public init(watchReachable: Bool, lastWatchContactAt: Date?, location: LocationFix?) {
        self.watchReachable = watchReachable
        self.lastWatchContactAt = lastWatchContactAt
        self.location = location
    }
}

public struct HeartbeatResponse: Codable, Sendable {
    public var serverTime: Date
    public var revision: Int
    public init(serverTime: Date, revision: Int) {
        self.serverTime = serverTime
        self.revision = revision
    }
}

public struct ConfirmRequest: Codable, Sendable {
    /// The check-in being answered. Nil for a voluntary safety tap.
    public var checkInId: String?
    public var source: ResponseSource
    public init(checkInId: String?, source: ResponseSource) {
        self.checkInId = checkInId
        self.source = source
    }
}

public struct ConfirmResponse: Codable, Sendable {
    public var outcome: ConfirmOutcome
    public var message: String
    public init(outcome: ConfirmOutcome, message: String) {
        self.outcome = outcome
        self.message = message
    }
}

public struct HelpRequest: Codable, Sendable {
    public var source: ResponseSource
    public init(source: ResponseSource) { self.source = source }
}

public struct CancelRequest: Codable, Sendable {
    public var pin: String
    public init(pin: String) { self.pin = pin }
}

public struct MessageResponse: Codable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

public struct InviteHelperRequest: Codable, Sendable {
    public var helperName: String
    public var helperPhone: String
    public var venue: String
    public var durationMinutes: Int
    public var share: SharePermissions
    public init(helperName: String, helperPhone: String, venue: String, durationMinutes: Int, share: SharePermissions = .helperDefault) {
        self.helperName = helperName
        self.helperPhone = helperPhone
        self.venue = venue
        self.durationMinutes = durationMinutes
        self.share = share
    }
}

public struct InviteHelperResponse: Codable, Sendable {
    public var coverage: CoverageView
    /// Show this as a QR code. On its own it reveals only the coverage terms.
    public var enrollURL: String
    public init(coverage: CoverageView, enrollURL: String) {
        self.coverage = coverage
        self.enrollURL = enrollURL
    }
}

// MARK: - Admin

public struct AdminLoginRequest: Codable, Sendable {
    public var secret: String
    public var name: String
    public init(secret: String, name: String) {
        self.secret = secret
        self.name = name
    }
}

public struct AdminLoginResponse: Codable, Sendable {
    public var adminId: String
    public var adminToken: String
    public init(adminId: String, adminToken: String) {
        self.adminId = adminId
        self.adminToken = adminToken
    }
}

public struct PairRequest: Codable, Sendable {
    public var pairingCode: String
    public init(pairingCode: String) { self.pairingCode = pairingCode }
}

public struct TriggerCheckInRequest: Codable, Sendable {
    public var responseWindowSeconds: Int?
    public init(responseWindowSeconds: Int?) { self.responseWindowSeconds = responseWindowSeconds }
}

public struct StopRequest: Codable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

// MARK: - Helper enrollment and responder pages

public struct VerifyCodeRequest: Codable, Sendable {
    public var code: String
    public init(code: String) { self.code = code }
}

public struct AcceptCoverageRequest: Codable, Sendable {
    public var agree: Bool
    public init(agree: Bool) { self.agree = agree }
}

public struct ResponderActionRequest: Codable, Sendable {
    public var action: ResponderAction
    /// Required for `resolved`: a short outcome such as "Help arrived".
    public var outcome: String?
    public init(action: ResponderAction, outcome: String? = nil) {
        self.action = action
        self.outcome = outcome
    }
}

/// Error body returned by the server for every non-2xx response.
public struct APIErrorBody: Codable, Sendable {
    public var code: String
    public var message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
