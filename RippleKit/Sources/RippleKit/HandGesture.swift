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

/// One selected sequence confirms the wearer is okay during an alarm, and an
/// optional second one asks for help. The other presets stay inactive, so a
/// single input never consumes the prefix of a selected two-input sequence.
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

    /// True when the two are the same sequence or one is a step of the other.
    /// A gesture meant for one could then finish or cut short the other: with
    /// dismiss on pinch and help on pinch + clench, the pinch would dismiss
    /// before help could finish.
    public func overlaps(_ other: HandGesturePreset) -> Bool {
        let (short, long) = steps.count <= other.steps.count ? (steps, other.steps) : (other.steps, steps)
        return (0...(long.count - short.count)).contains { start in
            Array(long[start..<(start + short.count)]) == short
        }
    }

    /// Dismiss sequences that can be saved alongside this help sequence.
    public static func dismissChoices(besides help: HandGesturePreset) -> [HandGesturePreset] {
        allCases.filter { !$0.overlaps(help) }
    }

    /// Help sequences that can be saved alongside this dismiss sequence. Help
    /// texts contacts straight away, so like swiping up twice it takes two
    /// inputs, and one stray pinch or clench can't send it.
    public static func helpChoices(besides dismiss: HandGesturePreset) -> [HandGesturePreset] {
        allCases.filter { $0.steps.count == 2 && !$0.overlaps(dismiss) }
    }

    /// Double clench + double pinch: two deliberate inputs. Clench + pinch
    /// shares no input with the dismiss sequences that rule that out.
    public static func defaultHelp(besides dismiss: HandGesturePreset) -> HandGesturePreset {
        let preferred = HandGesturePreset.doubleClenchDoublePinch
        return preferred.overlaps(dismiss) ? .clenchPinch : preferred
    }
}

/// A selected sequence and what completing it does.
public struct HandGestureBinding: Equatable, Sendable {
    public var preset: HandGesturePreset
    public var action: ComboAction

    public init(preset: HandGesturePreset, action: ComboAction) {
        self.preset = preset
        self.action = action
    }
}

public enum HandGestureProgress: Equatable, Sendable {
    case idle
    case partial
    case matched(ComboAction)
}

/// A Watch-local matcher for shortcut input. The caller decides which
/// sequences count right now, resetting it whenever the alarm or settings
/// change. Explicit times make shortcut latency, duplicate input and expiry
/// testable.
public struct HandGestureRecognizer: Sendable {
    /// Settings keep these from overlapping, so one input sequence can only
    /// ever complete one of them.
    public private(set) var bindings: [HandGestureBinding]
    public let maxGap: TimeInterval
    public let bounce: TimeInterval

    private var steps: [HandGestureStep] = []
    private var lastStep: HandGestureStep?
    private var lastAt: Date?

    public init(bindings: [HandGestureBinding], maxGap: TimeInterval = 5, bounce: TimeInterval = 0.4) {
        self.bindings = bindings
        self.maxGap = maxGap.isFinite && maxGap >= 0 ? maxGap : 5
        self.bounce = bounce.isFinite && bounce >= 0 ? bounce : 0.4
    }

    /// Only a dismiss sequence.
    public init(preset: HandGesturePreset, maxGap: TimeInterval = 5, bounce: TimeInterval = 0.4) {
        self.init(bindings: [HandGestureBinding(preset: preset, action: .okay)], maxGap: maxGap, bounce: bounce)
    }

    /// A partial sequence expires relative to the last accepted input. Duplicate
    /// deliveries do not move this deadline; a complete sequence has none.
    public var expiresAt: Date? {
        guard !steps.isEmpty, let lastAt else { return nil }
        return lastAt.addingTimeInterval(maxGap)
    }

    /// The inputs that can come next, for the Watch's status line: the first
    /// step of each sequence, or the step that finishes a partial one.
    public var nextSteps: [HandGestureStep] {
        var result: [HandGestureStep] = []
        for binding in bindings {
            let full = binding.preset.steps
            guard full.count > steps.count, full.starts(with: steps), !result.contains(full[steps.count]) else { continue }
            result.append(full[steps.count])
        }
        return result
    }

    /// A configuration change cannot finish a sequence started with old settings.
    public mutating func select(_ bindings: [HandGestureBinding]) {
        self.bindings = bindings
        reset()
    }

    public mutating func select(_ preset: HandGesturePreset) {
        select([HandGestureBinding(preset: preset, action: .okay)])
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
        while !steps.isEmpty && !bindings.contains(where: { $0.preset.steps.starts(with: steps) }) {
            steps.removeFirst()
        }
        if let match = bindings.first(where: { $0.preset.steps == steps }) {
            steps = []
            return .matched(match.action)
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
