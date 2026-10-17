import Foundation

// Read models ("projections") returned by the server. The server builds each
// one with the caller's permissions applied; clients never see raw records.

public struct ContactView: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var phone: String
    public var share: SharePermissions
    public init(id: String, name: String, phone: String, share: SharePermissions) {
        self.id = id
        self.name = name
        self.phone = phone
        self.share = share
    }
}

public struct WearerProfile: Codable, Hashable, Sendable {
    public var userId: String
    public var displayName: String
    public var phone: String
    public var helpCard: String
    public var timing: TimingSettings
    public var contacts: [ContactView]
    public var hasPins: Bool
    /// Shown on the wearer's phone so a demo admin can pair with this wearer.
    public var pairingCode: String
    public init(userId: String, displayName: String, phone: String, helpCard: String, timing: TimingSettings, contacts: [ContactView], hasPins: Bool, pairingCode: String) {
        self.userId = userId
        self.displayName = displayName
        self.phone = phone
        self.helpCard = helpCard
        self.timing = timing
        self.contacts = contacts
        self.hasPins = hasPins
        self.pairingCode = pairingCode
    }
}

public struct SessionView: Codable, Hashable, Sendable {
    public var id: String
    public var monitoring: MonitoringState
    public var venue: String
    public var startedAt: Date
    /// Nil for a session opened by Get help without a planned end.
    public var expectedEndAt: Date?
    public var endedAt: Date?
    public var lastHeartbeatAt: Date
    public var watchReachable: Bool
    public var lastWatchContactAt: Date?
    public var lastSafetyConfirmationAt: Date?
    public var connectionLost: Bool
    public init(id: String, monitoring: MonitoringState, venue: String, startedAt: Date, expectedEndAt: Date?, endedAt: Date?, lastHeartbeatAt: Date, watchReachable: Bool, lastWatchContactAt: Date?, lastSafetyConfirmationAt: Date?, connectionLost: Bool) {
        self.id = id
        self.monitoring = monitoring
        self.venue = venue
        self.startedAt = startedAt
        self.expectedEndAt = expectedEndAt
        self.endedAt = endedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.watchReachable = watchReachable
        self.lastWatchContactAt = lastWatchContactAt
        self.lastSafetyConfirmationAt = lastSafetyConfirmationAt
        self.connectionLost = connectionLost
    }
}

public struct CheckInView: Codable, Hashable, Sendable {
    public var id: String
    public var kind: CheckInKind
    public var state: CheckInState
    public var promptAt: Date
    public var respondBy: Date
    public var respondedAt: Date?
    public init(id: String, kind: CheckInKind, state: CheckInState, promptAt: Date, respondBy: Date, respondedAt: Date?) {
        self.id = id
        self.kind = kind
        self.state = state
        self.promptAt = promptAt
        self.respondBy = respondBy
        self.respondedAt = respondedAt
    }
}

public struct DeliveryView: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var purpose: DeliveryPurpose
    public var to: String
    public var body: String
    public var state: DeliveryState
    public var attemptNo: Int
    public var providerStatus: String?
    public var error: String?
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: String, purpose: DeliveryPurpose, to: String, body: String, state: DeliveryState, attemptNo: Int, providerStatus: String?, error: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.purpose = purpose
        self.to = to
        self.body = body
        self.state = state
        self.attemptNo = attemptNo
        self.providerStatus = providerStatus
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StepView: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var position: Int
    public var recipientKind: RecipientKind
    public var name: String
    public var state: RoutingStepState
    public var notifiedAt: Date?
    public var ackDeadline: Date?
    public var actedAt: Date?
    /// When the responder's page first loaded the alert. This is observed
    /// receipt, unlike message submission.
    public var firstOpenedAt: Date?
    /// Only filled in for the admin view.
    public var deliveries: [DeliveryView]
    public init(id: String, position: Int, recipientKind: RecipientKind, name: String, state: RoutingStepState, notifiedAt: Date?, ackDeadline: Date?, actedAt: Date?, firstOpenedAt: Date?, deliveries: [DeliveryView]) {
        self.id = id
        self.position = position
        self.recipientKind = recipientKind
        self.name = name
        self.state = state
        self.notifiedAt = notifiedAt
        self.ackDeadline = ackDeadline
        self.actedAt = actedAt
        self.firstOpenedAt = firstOpenedAt
        self.deliveries = deliveries
    }
}

public struct IncidentView: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var status: IncidentStatus
    public var triggers: [IncidentTrigger]
    /// True for a duress alert. Always false in the wearer's own view.
    public var concealed: Bool
    public var simulated: Bool
    public var openedAt: Date
    public var progress: ResponderProgress
    public var responderName: String?
    public var acknowledgedAt: Date?
    public var wearerSafetyReportAt: Date?
    public var escalationPaused: Bool
    public var noResponderConfirmed: Bool
    public var resolvedAt: Date?
    public var resolution: ResolutionReason?
    public var resolutionNote: String?
    public var steps: [StepView]
    public init(id: String, status: IncidentStatus, triggers: [IncidentTrigger], concealed: Bool, simulated: Bool, openedAt: Date, progress: ResponderProgress, responderName: String?, acknowledgedAt: Date?, wearerSafetyReportAt: Date?, escalationPaused: Bool, noResponderConfirmed: Bool, resolvedAt: Date?, resolution: ResolutionReason?, resolutionNote: String?, steps: [StepView]) {
        self.id = id
        self.status = status
        self.triggers = triggers
        self.concealed = concealed
        self.simulated = simulated
        self.openedAt = openedAt
        self.progress = progress
        self.responderName = responderName
        self.acknowledgedAt = acknowledgedAt
        self.wearerSafetyReportAt = wearerSafetyReportAt
        self.escalationPaused = escalationPaused
        self.noResponderConfirmed = noResponderConfirmed
        self.resolvedAt = resolvedAt
        self.resolution = resolution
        self.resolutionNote = resolutionNote
        self.steps = steps
    }
}

public struct CoverageView: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var venue: String
    public var helperName: String
    public var helperPhoneHint: String
    public var startsAt: Date
    public var endsAt: Date
    public var state: CoverageState
    /// Accepted and inside its coverage period. Only active coverage is routed to.
    public var isActive: Bool
    public var share: SharePermissions
    public init(id: String, venue: String, helperName: String, helperPhoneHint: String, startsAt: Date, endsAt: Date, state: CoverageState, isActive: Bool, share: SharePermissions) {
        self.id = id
        self.venue = venue
        self.helperName = helperName
        self.helperPhoneHint = helperPhoneHint
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.state = state
        self.isActive = isActive
        self.share = share
    }
}

public struct EventView: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var at: Date
    public var actor: ActorType
    public var text: String
    public var simulated: Bool
    public init(id: String, at: Date, actor: ActorType, text: String, simulated: Bool) {
        self.id = id
        self.at = at
        self.actor = actor
        self.text = text
        self.simulated = simulated
    }
}

/// Everything the wearer's iPhone (and, through it, the watch) shows.
/// Duress alerts never appear here.
public struct WearerState: Codable, Sendable {
    public var serverTime: Date
    public var revision: Int
    public var demoRunId: String
    public var profile: WearerProfile
    public var session: SessionView?
    /// The check-in that is awaiting a response, or the next scheduled one.
    public var checkIn: CheckInView?
    public var incident: IncidentView?
    public var coverages: [CoverageView]
    /// Who gets alerted, in order, if an alert opened right now.
    public var routingOrder: [String]
    public var coverageSummary: String
    public var tone: StatusTone
    public var headline: String
    public var detail: String
    public var events: [EventView]
    public init(serverTime: Date, revision: Int, demoRunId: String, profile: WearerProfile, session: SessionView?, checkIn: CheckInView?, incident: IncidentView?, coverages: [CoverageView], routingOrder: [String], coverageSummary: String, tone: StatusTone, headline: String, detail: String, events: [EventView]) {
        self.serverTime = serverTime
        self.revision = revision
        self.demoRunId = demoRunId
        self.profile = profile
        self.session = session
        self.checkIn = checkIn
        self.incident = incident
        self.coverages = coverages
        self.routingOrder = routingOrder
        self.coverageSummary = coverageSummary
        self.tone = tone
        self.headline = headline
        self.detail = detail
        self.events = events
    }
}

// MARK: - Admin

public struct AdminWearerSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String { userId }
    public var userId: String
    public var displayName: String
    public var sessionActive: Bool
    public var openIncident: Bool
    public init(userId: String, displayName: String, sessionActive: Bool, openIncident: Bool) {
        self.userId = userId
        self.displayName = displayName
        self.sessionActive = sessionActive
        self.openIncident = openIncident
    }
}

public struct PairResponse: Codable, Sendable {
    public var wearer: AdminWearerSummary
    public init(wearer: AdminWearerSummary) { self.wearer = wearer }
}

public struct JobView: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: JobKind
    public var runAt: Date
    public var state: JobState
    public var note: String?
    public init(id: String, kind: JobKind, runAt: Date, state: JobState, note: String?) {
        self.id = id
        self.kind = kind
        self.runAt = runAt
        self.state = state
        self.note = note
    }
}

public struct AdminView: Codable, Sendable {
    public var serverTime: Date
    public var revision: Int
    public var demoRunId: String
    public var wearer: AdminWearerSummary
    public var timing: TimingSettings
    public var session: SessionView?
    public var checkIn: CheckInView?
    public var lastResponseAt: Date?
    /// The open incident, or the most recent one in this demo run.
    public var incident: IncidentView?
    public var coverages: [CoverageView]
    public var jobs: [JobView]
    public var events: [EventView]
    public init(serverTime: Date, revision: Int, demoRunId: String, wearer: AdminWearerSummary, timing: TimingSettings, session: SessionView?, checkIn: CheckInView?, lastResponseAt: Date?, incident: IncidentView?, coverages: [CoverageView], jobs: [JobView], events: [EventView]) {
        self.serverTime = serverTime
        self.revision = revision
        self.demoRunId = demoRunId
        self.wearer = wearer
        self.timing = timing
        self.session = session
        self.checkIn = checkIn
        self.lastResponseAt = lastResponseAt
        self.incident = incident
        self.coverages = coverages
        self.jobs = jobs
        self.events = events
    }
}

public struct ResetResponse: Codable, Sendable {
    public var demoRunId: String
    public var message: String
    public init(demoRunId: String, message: String) {
        self.demoRunId = demoRunId
        self.message = message
    }
}

// MARK: - Web pages

public struct EnrollView: Codable, Sendable {
    public var serverTime: Date
    public var venue: String
    public var helperName: String
    public var phoneHint: String
    public var startsAt: Date
    public var endsAt: Date
    public var state: CoverageState
    /// What the helper would see during an alert. No wearer details are shown here.
    public var shared: [String]
    public var codeSent: Bool
    public init(serverTime: Date, venue: String, helperName: String, phoneHint: String, startsAt: Date, endsAt: Date, state: CoverageState, shared: [String], codeSent: Bool) {
        self.serverTime = serverTime
        self.venue = venue
        self.helperName = helperName
        self.phoneHint = phoneHint
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.state = state
        self.shared = shared
        self.codeSent = codeSent
    }
}

public struct LocationView: Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracyMeters: Double
    public var capturedAt: Date
    public var mapURL: String
    public init(latitude: Double, longitude: Double, accuracyMeters: Double, capturedAt: Date, mapURL: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.capturedAt = capturedAt
        self.mapURL = mapURL
    }
}

/// What one responder may see. Fields the wearer didn't permit are nil.
public struct ResponderView: Codable, Sendable {
    public var serverTime: Date
    public var incidentId: String
    public var status: IncidentStatus
    public var reason: String
    public var silent: Bool
    public var simulated: Bool
    public var openedAt: Date
    public var recipientName: String
    public var recipientKind: RecipientKind
    public var stepState: RoutingStepState
    public var canAct: Bool
    public var progress: ResponderProgress
    public var responderName: String?
    public var wearerName: String?
    public var venue: String?
    public var location: LocationView?
    public var locationNote: String?
    public var wearerPhone: String?
    public var helpCard: String?
    public var wearerSafetyReportAt: Date?
    public var resolution: ResolutionReason?
    public var resolutionNote: String?
    public var timeline: [EventView]
    public init(serverTime: Date, incidentId: String, status: IncidentStatus, reason: String, silent: Bool, simulated: Bool, openedAt: Date, recipientName: String, recipientKind: RecipientKind, stepState: RoutingStepState, canAct: Bool, progress: ResponderProgress, responderName: String?, wearerName: String?, venue: String?, location: LocationView?, locationNote: String?, wearerPhone: String?, helpCard: String?, wearerSafetyReportAt: Date?, resolution: ResolutionReason?, resolutionNote: String?, timeline: [EventView]) {
        self.serverTime = serverTime
        self.incidentId = incidentId
        self.status = status
        self.reason = reason
        self.silent = silent
        self.simulated = simulated
        self.openedAt = openedAt
        self.recipientName = recipientName
        self.recipientKind = recipientKind
        self.stepState = stepState
        self.canAct = canAct
        self.progress = progress
        self.responderName = responderName
        self.wearerName = wearerName
        self.venue = venue
        self.location = location
        self.locationNote = locationNote
        self.wearerPhone = wearerPhone
        self.helpCard = helpCard
        self.wearerSafetyReportAt = wearerSafetyReportAt
        self.resolution = resolution
        self.resolutionNote = resolutionNote
        self.timeline = timeline
    }
}
