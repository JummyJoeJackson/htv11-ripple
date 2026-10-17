import Foundation
import KazeKit

// Stored records (PRD §6). Every record that belongs to a demo run carries
// `demoRunId`, so a reset makes old timers, links and responses inert.

struct UserRecord: Codable {
    var id: String
    var displayName: String
    var phone: String
    var pairingCode: String
    var helpCard: String
    var timing: TimingSettings
    /// Escalation order.
    var contactIds: [String]
    var pinSalt: String
    var safetyPinHash: String?
    var duressPinHash: String?
    var demoRunId: String
    var revision: Int
    var createdAt: Date
}

struct AdminRecord: Codable {
    var id: String
    var name: String
    var createdAt: Date
}

struct ContactRecord: Codable {
    var id: String
    var userId: String
    var name: String
    var phone: String
    var share: SharePermissions
}

struct SessionRecord: Codable {
    var id: String
    var userId: String
    var demoRunId: String
    var monitoring: MonitoringState
    var venue: String
    var startedAt: Date
    var expectedEndAt: Date?
    var endedAt: Date?
    var lastHeartbeatAt: Date
    var watchReachable: Bool
    var lastWatchContactAt: Date?
    var lastLocation: LocationFix?
    var lastSafetyConfirmationAt: Date?
    /// Set once a connection-loss alert was raised, until contact returns.
    var connectionLost: Bool
}

struct CheckInRecord: Codable {
    var id: String
    var sessionId: String
    var userId: String
    var demoRunId: String
    var kind: CheckInKind
    var state: CheckInState
    var promptAt: Date
    var respondBy: Date
    var respondedAt: Date?
    var source: ResponseSource?
}

struct IncidentRecord: Codable {
    var id: String
    var userId: String
    /// The session whose venue and last location responders may see.
    var sessionId: String?
    var demoRunId: String
    var status: IncidentStatus
    var triggers: [IncidentTrigger]
    /// Duress: hidden from the wearer's own screens, routed normally.
    var concealed: Bool
    var simulated: Bool
    var openedAt: Date
    var stepIds: [String]
    var progress: ResponderProgress
    var currentStepId: String?
    var acknowledgedAt: Date?
    /// Bumped on every progress change; follow-up jobs check it.
    var progressVersion: Int
    var wearerSafetyReportAt: Date?
    /// Set by a late "I'm okay": unsent escalation is suppressed.
    var escalationPaused: Bool
    var noResponderConfirmed: Bool
    var resolvedAt: Date?
    var resolution: ResolutionReason?
    var resolutionNote: String?
    var resolvedBy: String?
}

struct StepRecord: Codable {
    var id: String
    var incidentId: String
    var position: Int
    var recipientKind: RecipientKind
    var contactId: String?
    var coverageId: String?
    var name: String
    var phone: String
    var share: SharePermissions
    var state: RoutingStepState
    /// Number of alert deliveries created for this step.
    var attempts: Int
    var notifiedAt: Date?
    var ackDeadline: Date?
    var actedAt: Date?
    var firstOpenedAt: Date?
    var tokenHash: String?
    /// The alert text, reused for retries.
    var alertBody: String?
}

struct DeliveryRecord: Codable {
    var id: String
    var userId: String
    var incidentId: String?
    var stepId: String?
    var coverageId: String?
    var purpose: DeliveryPurpose
    var to: String
    var body: String
    var state: DeliveryState
    var attemptNo: Int
    var providerMessageId: String?
    var providerStatus: String?
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct CoverageRecord: Codable {
    var id: String
    var userId: String
    var demoRunId: String
    var venue: String
    var helperName: String
    var helperPhone: String
    var share: SharePermissions
    var startsAt: Date
    var endsAt: Date
    var state: CoverageState
    var verifiedAt: Date?
    var acceptedAt: Date?
    var endedAt: Date?
    var enrollTokenHash: String
}

enum TokenPurpose: String, Codable {
    case enroll, respond
}

/// Scoped, expiring, revocable access for the web pages. Only the hash of the
/// token is stored as the key.
struct TokenRecord: Codable {
    var purpose: TokenPurpose
    var userId: String
    var demoRunId: String
    var coverageId: String?
    var incidentId: String?
    var stepId: String?
    var expiresAt: Date
    var revokedAt: Date?
}

struct OTPRecord: Codable {
    var codeHash: String
    var expiresAt: Date
    var attempts: Int
    var sentAt: Date
}

struct JobRecord: Codable {
    var id: String
    var kind: JobKind
    var targetId: String
    var userId: String
    var demoRunId: String
    var runAt: Date
    var state: JobState
    var dedupeKey: String
    /// For follow-up jobs: the incident progress version they were scheduled for.
    var version: Int?
    var createdAt: Date
    var finishedAt: Date?
    var note: String?
}

struct EventRecord: Codable {
    var id: String
    var at: Date
    var userId: String
    var demoRunId: String
    var sessionId: String?
    var incidentId: String?
    var actor: ActorType
    var type: String
    var text: String
    var visibleToWearer: Bool
    var visibleToResponders: Bool
    var simulated: Bool
}

struct IdempotencyRecord: Codable {
    var response: Data
    var createdAt: Date
}

struct Database: Codable {
    var users: [String: UserRecord] = [:]
    /// Device token hash -> user id.
    var deviceTokens: [String: String] = [:]
    /// Admin token hash -> admin.
    var admins: [String: AdminRecord] = [:]
    /// Admin id -> wearer user ids the admin may control.
    var assignments: [String: Set<String>] = [:]
    var contacts: [String: ContactRecord] = [:]
    var sessions: [String: SessionRecord] = [:]
    var checkIns: [String: CheckInRecord] = [:]
    var incidents: [String: IncidentRecord] = [:]
    var steps: [String: StepRecord] = [:]
    var deliveries: [String: DeliveryRecord] = [:]
    var coverages: [String: CoverageRecord] = [:]
    /// Token hash -> token.
    var tokens: [String: TokenRecord] = [:]
    /// Coverage id -> verification code.
    var otps: [String: OTPRecord] = [:]
    var jobs: [String: JobRecord] = [:]
    var events: [EventRecord] = []
    var idempotency: [String: IdempotencyRecord] = [:]
}
