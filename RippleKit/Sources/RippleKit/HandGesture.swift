import Foundation

/// AssistiveTouch recognizes these four inputs and runs the matching Ripple
/// shortcut. A double input is one event, not two single inputs.
public enum HandGestureStep: String, Codable, CaseIterable, Sendable, Identifiable {
    case pinch, clench, doublePinch, doubleClench

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pinch: return "pinch"
        case .clench: return "clench"
        case .doublePinch: return "double pinch"
        case .doubleClench: return "double clench"
        }
    }

    public var shortcutName: String {
        switch self {
        case .pinch: return "Ripple Pinch"
        case .clench: return "Ripple Clench"
        case .doublePinch: return "Ripple Double Pinch"
        case .doubleClench: return "Ripple Double Clench"
        }
    }
}

/// One selected sequence confirms the wearer is okay during an alarm. The
/// other presets stay inactive, so a single input never consumes the prefix
/// of a selected two-input sequence.
public enum HandGesturePreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case pinch, clench, doublePinch, doubleClench
    case pinchClench, doublePinchClench, clenchPinch, clenchDoublePinch
    case doubleClenchPinch, doubleClenchDoublePinch

    public var id: String { rawValue }

    public var label: String { steps.map(\.label).joined(separator: " + ") }

    public var steps: [HandGestureStep] {
        switch self {
        case .pinch: return [.pinch]
        case .clench: return [.clench]
        case .doublePinch: return [.doublePinch]
        case .doubleClench: return [.doubleClench]
        case .pinchClench: return [.pinch, .clench]
        case .doublePinchClench: return [.doublePinch, .clench]
        case .clenchPinch: return [.clench, .pinch]
        case .clenchDoublePinch: return [.clench, .doublePinch]
        case .doubleClenchPinch: return [.doubleClench, .pinch]
        case .doubleClenchDoublePinch: return [.doubleClench, .doublePinch]
        }
    }
}

public enum HandGestureProgress: Equatable, Sendable {
    case idle
    case partial
    case matched
}

/// A Watch-local matcher for shortcut input. The caller scopes it to the
/// current alarm, resetting it whenever the alarm or enabled setting changes.
/// Explicit times make shortcut latency, duplicate input and expiry testable.
public struct HandGestureRecognizer: Sendable {
    public private(set) var preset: HandGesturePreset
    public let maxGap: TimeInterval
    public let bounce: TimeInterval

    private var steps: [HandGestureStep] = []
    private var lastStep: HandGestureStep?
    private var lastAt: Date?

    public init(preset: HandGesturePreset, maxGap: TimeInterval = 5, bounce: TimeInterval = 0.4) {
        self.preset = preset
        self.maxGap = maxGap.isFinite && maxGap >= 0 ? maxGap : 5
        self.bounce = bounce.isFinite && bounce >= 0 ? bounce : 0.4
    }

    /// A partial sequence expires relative to the last accepted input. Duplicate
    /// deliveries do not move this deadline; a complete sequence has none.
    public var expiresAt: Date? {
        guard !steps.isEmpty, let lastAt else { return nil }
        return lastAt.addingTimeInterval(maxGap)
    }

    /// A configuration change cannot finish a sequence started with old settings.
    public mutating func select(_ preset: HandGesturePreset) {
        self.preset = preset
        reset()
    }

    @discardableResult
    public mutating func record(_ step: HandGestureStep, at time: Date = Date()) -> HandGestureProgress {
        guard time.timeIntervalSinceReferenceDate.isFinite else {
            reset()
            return .idle
        }
        if let lastAt {
            let gap = time.timeIntervalSince(lastAt)
            // Discard out-of-order input instead of allowing it to finish a sequence.
            guard gap >= 0 else {
                reset()
                return .idle
            }
            if gap > maxGap { steps = [] }
            // A duplicate neither counts nor extends the time window. Returning
            // current progress also prevents replaying a completed single input.
            if step == lastStep && gap < bounce { return progress }
        }
        lastStep = step
        lastAt = time
        steps.append(step)
        while !steps.isEmpty && !preset.steps.starts(with: steps) {
            steps.removeFirst()
        }
        if steps == preset.steps {
            steps = []
            return .matched
        }
        return progress
    }

    public mutating func reset() {
        steps = []
        lastStep = nil
        lastAt = nil
    }

    private var progress: HandGestureProgress { steps.isEmpty ? .idle : .partial }
}
