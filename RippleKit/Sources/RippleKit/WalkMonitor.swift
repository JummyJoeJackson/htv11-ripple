import Foundation

/// Decides when steps have stopped during a walk session. It never claims a
/// fall or a freeze: a stop only starts a check-in the wearer can answer.
/// Pure logic with explicit times, so it is unit tested.
///
/// A stop only counts after the wearer has actually walked (`stepsToArm`
/// steps), so standing still when the session starts does nothing. After a
/// stop it waits for more walking before another stop can count.
public struct WalkMonitor: Sendable {
    /// No new steps for this long, after walking, starts a check-in.
    public var stopAfter: TimeInterval
    /// Steps needed before a stop counts.
    public var stepsToArm: Int

    /// Steps since the session started.
    public private(set) var steps = 0
    /// When the step count last went up.
    public private(set) var lastStepAt: Date?
    private var stepsSinceStop = 0

    public init(stopAfter: TimeInterval, stepsToArm: Int = 10) {
        self.stopAfter = stopAfter
        self.stepsToArm = stepsToArm
    }

    /// True once enough walking has happened that a stop would count.
    public var armed: Bool { stepsSinceStop >= stepsToArm }

    /// The total steps since the session started, as the pedometer reports
    /// them, and when they were counted.
    public mutating func update(totalSteps: Int, at time: Date) {
        guard totalSteps > steps else { return }
        stepsSinceStop += totalSteps - steps
        steps = totalSteps
        lastStepAt = time
    }

    /// The wearer just answered a check-in, so a stop counts again only after
    /// more walking.
    public mutating func waitForWalking() {
        stepsSinceStop = 0
    }

    /// Call regularly. True, once, when steps have stopped for `stopAfter`
    /// after walking.
    public mutating func checkStopped(at time: Date) -> Bool {
        guard armed, let lastStepAt, time.timeIntervalSince(lastStepAt) >= stopAfter else { return false }
        stepsSinceStop = 0
        return true
    }
}
