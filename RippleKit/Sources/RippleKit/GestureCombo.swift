import Foundation

/// A coarse movement on the Watch circle. Combos use swipes rather than taps
/// or wrist motion: a tremor moves the finger back and forth, so its net
/// travel stays small, while a deliberate swipe travels one way.
public enum GestureStep: String, Codable, Sendable {
    case swipeUp, swipeDown

    /// Net vertical travel needed for a swipe, in points (about 6 mm on the Watch).
    public static let swipeDistance: Double = 40

    /// Classifies a drag by where it ended relative to where it started.
    /// Jitter that wanders and comes back, and mostly sideways drags, are not swipes.
    public static func swipe(dx: Double, dy: Double) -> GestureStep? {
        guard abs(dy) >= swipeDistance, abs(dy) >= abs(dx) else { return nil }
        return dy < 0 ? .swipeUp : .swipeDown
    }
}

/// What a combo does. Combos only ask for help or confirm the wearer is okay;
/// duress stays the touch-only 2-second hold.
public enum ComboAction: String, Codable, Sendable {
    case help, okay
}

public struct GestureCombo: Equatable, Sendable {
    public var steps: [GestureStep]
    public var action: ComboAction

    public init(steps: [GestureStep], action: ComboAction) {
        self.steps = steps
        self.action = action
    }

    /// Swipe up twice: ask for help.
    public static let help = GestureCombo(steps: [.swipeUp, .swipeUp], action: .help)
    /// Swipe down twice: I'm okay.
    public static let okay = GestureCombo(steps: [.swipeDown, .swipeDown], action: .okay)
    public static let all: [GestureCombo] = [help, okay]
}

public enum ComboProgress: Equatable, Sendable {
    /// Nothing entered yet, or the last step didn't start a combo.
    case idle
    /// The start of a combo; more steps are needed.
    case partial(ComboAction)
    case matched(ComboAction)
}

/// Matches swipes against combos, with timing that tolerates slow and shaky
/// movement. Pure logic with explicit times, so it is unit tested.
public struct ComboRecognizer: Sendable {
    public var combos: [GestureCombo]
    /// Longest pause allowed between steps. Generous, for slow movement.
    public var maxGap: TimeInterval
    /// The same swipe again within this time is one stuttered movement (a
    /// finger bouncing off the glass), so it counts once.
    public var bounce: TimeInterval

    private var steps: [GestureStep] = []
    private var lastStep: GestureStep?
    private var lastAt: Date?

    public init(combos: [GestureCombo] = GestureCombo.all, maxGap: TimeInterval = 3, bounce: TimeInterval = 0.4) {
        self.combos = combos
        self.maxGap = maxGap
        self.bounce = bounce
    }

    @discardableResult
    public mutating func record(_ step: GestureStep, at time: Date = Date()) -> ComboProgress {
        if let lastStep, let lastAt {
            let gap = time.timeIntervalSince(lastAt)
            if step == lastStep && gap < bounce { return progress }
            if gap > maxGap { steps = [] }
        }
        lastStep = step
        lastAt = time
        steps.append(step)
        // A stray swipe restarts the sequence instead of blocking it.
        while !steps.isEmpty && !combos.contains(where: { $0.steps.starts(with: steps) }) {
            steps.removeFirst()
        }
        if let match = combos.first(where: { $0.steps == steps }) {
            // Keep the last step and time, so a bounce right after a match can't start another.
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

    private var progress: ComboProgress {
        guard !steps.isEmpty, let combo = combos.first(where: { $0.steps.starts(with: steps) }) else { return .idle }
        return .partial(combo.action)
    }
}
