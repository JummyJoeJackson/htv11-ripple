import Foundation
import RippleKit

// Stored records. The backend keeps only what it needs to be a declared
// backup: alarm ids, timestamps, phone numbers and message text. Everything
// for a wearer is deleted on demo reset.

struct WearerRecord: Codable {
    var id: String
    var displayName: String
    var pairingCode: String
    /// Changes on every demo reset; anything from an older run is ignored.
    var runId: String
    var createdAt: Date
    /// The phone's heartbeat.
    var lastSyncAt: Date?
    var status: DeviceStatus?
}

struct AdminRecord: Codable {
    var id: String
    var name: String
    var createdAt: Date
}

/// The backend's mirror of an alarm the phone registered.
struct AlarmRecord: Codable {
    var id: String
    var userId: String
    var runId: String
    /// The phone's latest report.
    var snapshot: Alarm
    var firstSeenAt: Date
    var updatedAt: Date
    /// Recorded when a contact taps their acknowledge link.
    var acknowledgment: Acknowledgment?
    var closedByAdmin: Bool
    var closedAt: Date?
}

/// A message the backend sent because the phone went quiet.
struct BackupRecord: Codable {
    var message: OutMessage
    var userId: String
    var providerMessageId: String?
}

struct AckTokenRecord: Codable {
    var alarmId: String
    var recipientId: String
    var userId: String
    var runId: String
}

struct CommandRecord: Codable {
    var id: String
    var userId: String
    var runId: String
    var adminId: String
    var command: DeviceCommand
    var state: CommandState
    var deliveredAt: Date?
    var finishedAt: Date?
    var result: String?
}

struct TemporaryContactRecord: Codable {
    var id: String
    var userId: String
    var runId: String
    var name: String
    var phone: String
    var shareLocation: Bool
    var state: TemporaryContactState
    var invitedAt: Date
    var consentAt: Date?
    var expiresAt: Date?
}

struct EventRecord: Codable {
    var id: String
    var at: Date
    var userId: String
    var runId: String
    var text: String
}

struct IdempotencyRecord: Codable {
    var response: Data
    var createdAt: Date
}

struct Database: Codable {
    var users: [String: WearerRecord] = [:]
    /// Device token hash -> user id.
    var deviceTokens: [String: String] = [:]
    /// Admin token hash -> admin.
    var admins: [String: AdminRecord] = [:]
    /// Admin id -> wearers that admin may control.
    var assignments: [String: Set<String>] = [:]
    var alarms: [String: AlarmRecord] = [:]
    /// Message id -> backup send.
    var backups: [String: BackupRecord] = [:]
    /// Acknowledge-link token hash -> alarm and recipient.
    var ackTokens: [String: AckTokenRecord] = [:]
    var commands: [String: CommandRecord] = [:]
    var temporaryContacts: [String: TemporaryContactRecord] = [:]
    /// Consent-link token hash -> temporary contact id.
    var inviteTokens: [String: String] = [:]
    var events: [EventRecord] = []
    var idempotency: [String: IdempotencyRecord] = [:]
}
