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
    var closedByAdmin: Bool
    var closedAt: Date?
}

extension AlarmRecord {
    private enum CodingKeys: String, CodingKey {
        case id, userId, runId, snapshot, firstSeenAt, updatedAt, closedByAdmin, closedAt
    }

    private enum LegacyKeys: String, CodingKey {
        case acknowledgment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        userId = try values.decode(String.self, forKey: .userId)
        runId = try values.decode(String.self, forKey: .runId)
        snapshot = try values.decode(Alarm.self, forKey: .snapshot)
        firstSeenAt = try values.decode(Date.self, forKey: .firstSeenAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        closedByAdmin = try values.decode(Bool.self, forKey: .closedByAdmin)
        closedAt = try values.decodeIfPresent(Date.self, forKey: .closedAt)
        // Preserve a response saved by an older server before replies were
        // recorded in the phone's alarm snapshot. Re-encoding uses only the snapshot.
        if snapshot.acknowledgment == nil {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            snapshot.acknowledgment = try legacy.decodeIfPresent(Acknowledgment.self, forKey: .acknowledgment)
        }
    }
}

/// A message the backend sent because the phone went quiet.
struct BackupRecord: Codable {
    var message: OutMessage
    var userId: String
    var providerMessageId: String?
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
    var commands: [String: CommandRecord] = [:]
    var temporaryContacts: [String: TemporaryContactRecord] = [:]
    /// Consent-link token hash -> temporary contact id.
    var inviteTokens: [String: String] = [:]
    var events: [EventRecord] = []
    var idempotency: [String: IdempotencyRecord] = [:]
}
