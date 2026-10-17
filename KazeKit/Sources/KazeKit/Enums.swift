import Foundation

// State models from the PRD (§6). Each one moves independently; there is no
// single "alarm" boolean anywhere in the system.

public enum MonitoringState: String, Codable, Sendable {
    case inactive, active, ended

    public var label: String {
        switch self {
        case .inactive: return "Not monitoring"
        case .active: return "Monitoring active"
        case .ended: return "Monitoring ended"
        }
    }
}

public enum CheckInKind: String, Codable, Sendable {
    /// The check-in at the planned end of an outing (expected end + grace).
    case planned
    /// A check-in started from the demo admin app.
    case demo
}

public enum CheckInState: String, Codable, Sendable {
    case scheduled, awaitingResponse, confirmed, expired, cancelled

    public var label: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .awaitingResponse: return "Awaiting response"
        case .confirmed: return "Confirmed"
        case .expired: return "Missed"
        case .cancelled: return "Cancelled"
        }
    }
}

public enum IncidentStatus: String, Codable, Sendable {
    case open, resolved
}

public enum IncidentTrigger: String, Codable, Sendable {
    case missedCheckIn, help, duress, connectionLost, simulatedHelp

    public var label: String {
        switch self {
        case .missedCheckIn: return "Missed check-in"
        case .help: return "Help requested"
        case .duress: return "Silent alert (duress PIN)"
        case .connectionLost: return "Lost connection"
        case .simulatedHelp: return "Simulated help request (demo)"
        }
    }
}

public enum ResponderProgress: String, Codable, Sendable {
    case unassigned, acknowledged, assistanceArranged, resolved

    public var label: String {
        switch self {
        case .unassigned: return "No responder yet"
        case .acknowledged: return "Acknowledged"
        case .assistanceArranged: return "Arranging help"
        case .resolved: return "Resolved"
        }
    }
}

public enum ResolutionReason: String, Codable, Sendable {
    case responderResolved, safetyPinCancel, operatorStop

    public var label: String {
        switch self {
        case .responderResolved: return "Resolved by responder"
        case .safetyPinCancel: return "Cancelled with safety PIN"
        case .operatorStop: return "Stopped by demo operator"
        }
    }
}

public enum RoutingStepState: String, Codable, Sendable {
    case pending, notifying, notified, acknowledged, declined, timedOut, failed, skipped

    public var label: String {
        switch self {
        case .pending: return "Waiting"
        case .notifying: return "Sending"
        case .notified: return "Alert sent"
        case .acknowledged: return "Acknowledged"
        case .declined: return "Declined"
        case .timedOut: return "No answer"
        case .failed: return "Couldn't send"
        case .skipped: return "Skipped"
        }
    }
}

/// What we know about one outbound message. Submission to a provider is not
/// proof that a person received it (PRD §5).
public enum DeliveryState: String, Codable, Sendable {
    case queued, submitting, submitted, failed, unknown, cancelled

    public var label: String {
        switch self {
        case .queued: return "Queued"
        case .submitting: return "Submitting"
        case .submitted: return "Submitted"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        case .cancelled: return "Not sent"
        }
    }
}

public enum DeliveryPurpose: String, Codable, Sendable {
    case alert, update, code
}

public enum CoverageState: String, Codable, Sendable {
    case invited, verified, accepted, expired, revoked

    public var label: String {
        switch self {
        case .invited: return "Invited"
        case .verified: return "Phone verified"
        case .accepted: return "Accepted"
        case .expired: return "Expired"
        case .revoked: return "Revoked"
        }
    }
}

public enum RecipientKind: String, Codable, Sendable {
    case helper, contact

    public var label: String {
        switch self {
        case .helper: return "Temporary helper"
        case .contact: return "Trusted contact"
        }
    }
}

public enum ResponseSource: String, Codable, Sendable {
    case watch, phone
}

public enum ResponderAction: String, Codable, Sendable {
    case acknowledge, decline, arranging, resolved
}

public enum ActorType: String, Codable, Sendable {
    case wearer, admin, responder, helper, system
}

public enum JobKind: String, Codable, Sendable {
    case checkInPrompt, checkInExpire, deliverySend, ackTimeout, followUp, coverageExpire

    public var label: String {
        switch self {
        case .checkInPrompt: return "Start check-in"
        case .checkInExpire: return "Check-in deadline"
        case .deliverySend: return "Send message"
        case .ackTimeout: return "Acknowledgment deadline"
        case .followUp: return "Follow-up deadline"
        case .coverageExpire: return "Helper coverage ends"
        }
    }
}

public enum JobState: String, Codable, Sendable {
    case pending, done, cancelled, skipped
}

/// Status colours from PRD §7. Every tone also has a text label so colour is
/// never the only signal.
public enum StatusTone: String, Codable, Sendable {
    case safe, awaiting, alert, acknowledged, resolved, neutral

    public var label: String {
        switch self {
        case .safe: return "Safe"
        case .awaiting: return "Awaiting response"
        case .alert: return "Alert"
        case .acknowledged: return "Responder acknowledged"
        case .resolved: return "Resolved"
        case .neutral: return "Idle"
        }
    }
}

public enum ConfirmOutcome: String, Codable, Sendable {
    /// A pending check-in was answered in time.
    case confirmed
    /// The answer arrived after the deadline; responders were told.
    case lateReport
    /// A voluntary safety tap outside a check-in. The deadline did not move.
    case recorded
    case alreadyConfirmed
}
