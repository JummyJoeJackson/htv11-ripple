import Foundation

// Request and response bodies for the backend. The backend connects the admin
// phone to the wearer phone, records temporary-contact replies, and holds
// the backup deadline. The wearer's iPhone always sends first.

public struct APIErrorBody: Codable, Sendable {
    public var code: String
    public var message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct SetupRequest: Codable, Sendable {
    public var displayName: String
    public init(displayName: String) { self.displayName = displayName }
}

public struct SetupResponse: Codable, Sendable {
    public var userId: String
    public var deviceToken: String
    public var pairingCode: String
    public var runId: String
    public init(userId: String, deviceToken: String, pairingCode: String, runId: String) {
        self.userId = userId
        self.deviceToken = deviceToken
        self.pairingCode = pairingCode
        self.runId = runId
    }
}

/// What the wearer's iPhone reports on every sync (its heartbeat).
public struct DeviceStatus: Codable, Equatable, Sendable {
    public var displayName: String
    public var monitoring: Bool
    public var watchPaired: Bool
    public var watchReachable: Bool
    public var configVersion: Int
    /// The configuration version the Watch confirmed it stored.
    public var watchConfigVersion: Int?
    public var nextCheckInAt: Date?
    public var appActive: Bool

    public init(displayName: String, monitoring: Bool, watchPaired: Bool, watchReachable: Bool, configVersion: Int, watchConfigVersion: Int?, nextCheckInAt: Date?, appActive: Bool) {
        self.displayName = displayName
        self.monitoring = monitoring
        self.watchPaired = watchPaired
        self.watchReachable = watchReachable
        self.configVersion = configVersion
        self.watchConfigVersion = watchConfigVersion
        self.nextCheckInAt = nextCheckInAt
        self.appActive = appActive
    }
}

public enum DeviceCommandKind: String, Codable, Sendable {
    /// Start an alarm and its response countdown on the Watch.
    case triggerAlarm
    /// Simulated phone failure: the iPhone stops sending heartbeats and messages.
    case cutConnection
    case disableAlarm
    /// Adjust the short demo countdowns.
    case setTimers

    public var label: String {
        switch self {
        case .triggerAlarm: return "Trigger alarm"
        case .cutConnection: return "Cut phone connection"
        case .disableAlarm: return "Disable alarm"
        case .setTimers: return "Set demo timers"
        }
    }
}

public struct DeviceCommand: Codable, Identifiable, Sendable {
    public var id: String
    public var kind: DeviceCommandKind
    public var countdownSeconds: Int?
    public var ackWindowSeconds: Int?
    public var durationSeconds: Int?
    public var createdAt: Date

    public init(id: String, kind: DeviceCommandKind, countdownSeconds: Int?, ackWindowSeconds: Int?, durationSeconds: Int?, createdAt: Date) {
        self.id = id
        self.kind = kind
        self.countdownSeconds = countdownSeconds
        self.ackWindowSeconds = ackWindowSeconds
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
    }
}

public struct CommandResult: Codable, Sendable {
    public var commandId: String
    public var ok: Bool
    public var message: String
    public init(commandId: String, ok: Bool, message: String) {
        self.commandId = commandId
        self.ok = ok
        self.message = message
    }
}

public struct SyncRequest: Codable, Sendable {
    public var runId: String
    public var status: DeviceStatus
    /// The current alarm, or the most recently closed one so the backend learns it closed.
    public var alarm: Alarm?
    public var commandResults: [CommandResult]
    public init(runId: String, status: DeviceStatus, alarm: Alarm?, commandResults: [CommandResult]) {
        self.runId = runId
        self.status = status
        self.alarm = alarm
        self.commandResults = commandResults
    }
}

/// What the backend knows about an alarm that the phone may not.
public struct AlarmFeedback: Codable, Sendable {
    public var alarmId: String
    public var acknowledgment: Acknowledgment?
    /// Messages the backend sent as backup. The phone never resends these.
    public var backupMessages: [OutMessage]
    public var closedByAdmin: Bool
    public init(alarmId: String, acknowledgment: Acknowledgment?, backupMessages: [OutMessage], closedByAdmin: Bool) {
        self.alarmId = alarmId
        self.acknowledgment = acknowledgment
        self.backupMessages = backupMessages
        self.closedByAdmin = closedByAdmin
    }
}

public struct SyncResponse: Codable, Sendable {
    public var serverTime: Date
    public var runId: String
    /// The demo was reset: clear the local alarm and adopt `runId`.
    public var resetRequired: Bool
    public var commands: [DeviceCommand]
    public var temporaryContacts: [TemporaryContactView]
    public var feedback: AlarmFeedback?
    /// Public server address, also used for provider callbacks.
    public var publicBaseURL: String
    public var pairingCode: String
    public init(serverTime: Date, runId: String, resetRequired: Bool, commands: [DeviceCommand], temporaryContacts: [TemporaryContactView], feedback: AlarmFeedback?, publicBaseURL: String, pairingCode: String) {
        self.serverTime = serverTime
        self.runId = runId
        self.resetRequired = resetRequired
        self.commands = commands
        self.temporaryContacts = temporaryContacts
        self.feedback = feedback
        self.publicBaseURL = publicBaseURL
        self.pairingCode = pairingCode
    }
}

public struct InviteTemporaryRequest: Codable, Sendable {
    public var name: String
    public var phone: String
    public var shareLocation: Bool
    public init(name: String, phone: String, shareLocation: Bool) {
        self.name = name
        self.phone = phone
        self.shareLocation = shareLocation
    }
}

public struct InviteTemporaryResponse: Codable, Sendable {
    public var contact: TemporaryContactView
    public var joinCode: String
    /// Sent through the same Ripple Alert shortcut as alarm messages.
    public var invitationText: String
    public init(contact: TemporaryContactView, joinCode: String, invitationText: String) {
        self.contact = contact
        self.joinCode = joinCode
        self.invitationText = invitationText
    }
}

public struct JoinTemporaryRequest: Codable, Hashable, Sendable {
    public var runId: String
    public var code: String
    public var from: String?
    public init(runId: String, code: String, from: String? = nil) {
        self.runId = runId
        self.code = code
        self.from = from
    }
}

public struct JoinTemporaryResponse: Codable, Sendable {
    public var contact: TemporaryContactView
    public var contacts: [TemporaryContactView]
    public init(contact: TemporaryContactView, contacts: [TemporaryContactView]) {
        self.contact = contact
        self.contacts = contacts
    }
}

public struct TemporaryContactsResponse: Codable, Sendable {
    public var contacts: [TemporaryContactView]
    public init(contacts: [TemporaryContactView]) { self.contacts = contacts }
}

// MARK: - Demo admin

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

public struct AdminWearerSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { userId }
    public var userId: String
    public var displayName: String
    public var online: Bool
    public var monitoring: Bool
    public var alarmOpen: Bool
    public init(userId: String, displayName: String, online: Bool, monitoring: Bool, alarmOpen: Bool) {
        self.userId = userId
        self.displayName = displayName
        self.online = online
        self.monitoring = monitoring
        self.alarmOpen = alarmOpen
    }
}

public struct PairResponse: Codable, Sendable {
    public var wearer: AdminWearerSummary
    public init(wearer: AdminWearerSummary) { self.wearer = wearer }
}

public struct AdminCommandRequest: Codable, Sendable {
    public var kind: DeviceCommandKind
    public var countdownSeconds: Int?
    public var ackWindowSeconds: Int?
    public var durationSeconds: Int?
    public init(kind: DeviceCommandKind, countdownSeconds: Int? = nil, ackWindowSeconds: Int? = nil, durationSeconds: Int? = nil) {
        self.kind = kind
        self.countdownSeconds = countdownSeconds
        self.ackWindowSeconds = ackWindowSeconds
        self.durationSeconds = durationSeconds
    }
}

public struct ExpireTemporaryRequest: Codable, Sendable {
    /// Nil expires every active temporary contact.
    public var contactId: String?
    public init(contactId: String?) { self.contactId = contactId }
}

public enum CommandState: String, Codable, Sendable {
    /// Waiting for the wearer's iPhone to pick it up.
    case queued
    /// The iPhone fetched it.
    case delivered
    /// The iPhone carried it out.
    case done
    /// The iPhone refused it, for example because monitoring was off.
    case rejected

    public var label: String {
        switch self {
        case .queued: return "Waiting for the wearer's iPhone"
        case .delivered: return "Reached the iPhone"
        case .done: return "Done"
        case .rejected: return "Refused"
        }
    }
}

public struct CommandView: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: DeviceCommandKind
    public var state: CommandState
    public var createdAt: Date
    public var deliveredAt: Date?
    public var result: String?
    public init(id: String, kind: DeviceCommandKind, state: CommandState, createdAt: Date, deliveredAt: Date?, result: String?) {
        self.id = id
        self.kind = kind
        self.state = state
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
        self.result = result
    }
}

public struct EventView: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var at: Date
    public var text: String
    public init(id: String, at: Date, text: String) {
        self.id = id
        self.at = at
        self.text = text
    }
}

public struct AdminWearerView: Codable, Sendable {
    public var serverTime: Date
    public var runId: String
    public var wearer: AdminWearerSummary
    public var status: DeviceStatus?
    public var lastSyncAt: Date?
    /// The current alarm, or the most recent one in this demo run.
    public var alarm: Alarm?
    /// The alarm's messages from the phone and the backend, merged.
    public var messages: [OutMessage]
    public var acknowledgment: Acknowledgment?
    public var closedByAdmin: Bool
    /// When the backend would send the next backup message if the phone stays quiet.
    public var nextBackupAt: Date?
    public var temporaryContacts: [TemporaryContactView]
    public var commands: [CommandView]
    public var events: [EventView]
    public init(serverTime: Date, runId: String, wearer: AdminWearerSummary, status: DeviceStatus?, lastSyncAt: Date?, alarm: Alarm?, messages: [OutMessage], acknowledgment: Acknowledgment?, closedByAdmin: Bool, nextBackupAt: Date?, temporaryContacts: [TemporaryContactView], commands: [CommandView], events: [EventView]) {
        self.serverTime = serverTime
        self.runId = runId
        self.wearer = wearer
        self.status = status
        self.lastSyncAt = lastSyncAt
        self.alarm = alarm
        self.messages = messages
        self.acknowledgment = acknowledgment
        self.closedByAdmin = closedByAdmin
        self.nextBackupAt = nextBackupAt
        self.temporaryContacts = temporaryContacts
        self.commands = commands
        self.events = events
    }
}
