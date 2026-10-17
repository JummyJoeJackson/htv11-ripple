import CoreMotion
import Foundation

/// Counts steps during a walk session with CMPedometer. While monitoring,
/// the extended runtime session keeps the app running with the screen off.
/// Live updates may still slow down or pause then, so `refresh()` also asks
/// for the total directly: the Watch's motion chip counts steps either way.
/// Use on the main thread.
final class WatchPedometer {
    /// Called on the main thread with the steps since `start` and when they were counted.
    var onSteps: ((Int, Date) -> Void)?
    /// Called on the main thread when step counting can't run.
    var onProblem: ((String) -> Void)?

    private let pedometer = CMPedometer()
    private var startedAt: Date?

    /// Nil when steps can be counted, otherwise why not.
    static var problem: String? {
        guard CMPedometer.isStepCountingAvailable() else { return "This Watch can't count steps." }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted: return "Allow Motion & Fitness for Ripple in the Watch's Settings."
        default: return nil
        }
    }

    /// Asks for Motion & Fitness permission the first time.
    func start(from date: Date) {
        startedAt = date
        pedometer.startUpdates(from: date) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.startedAt == date else { return }
                if let data {
                    self.onSteps?(data.numberOfSteps.intValue, data.endDate)
                } else if error != nil {
                    self.onProblem?(WatchPedometer.problem ?? "Step counting stopped.")
                }
            }
        }
    }

    /// Fetches the steps since the walk started, in case live updates paused.
    func refresh() {
        guard let start = startedAt else { return }
        pedometer.queryPedometerData(from: start, to: Date()) { [weak self] data, _ in
            guard let data else { return }
            DispatchQueue.main.async {
                // Ignore an answer for a walk that has since ended or restarted.
                guard let self, self.startedAt == start else { return }
                self.onSteps?(data.numberOfSteps.intValue, data.endDate)
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        startedAt = nil
    }
}
