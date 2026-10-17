import Foundation
import HealthKit
import Observation
import RippleKit

/// Watches Apple Health for alerts Apple Watch records itself: falls, and
/// high, low or irregular heart rhythm notifications. Ripple doesn't measure
/// or judge anything; each new alert just becomes an ordinary check-in.
///
/// HealthKit tells Ripple when a new entry is saved (an observer query, and
/// background delivery when the build allows it). Ripple then reads only the
/// entries it hasn't seen (an anchored query). While the app runs it also
/// re-reads every 30 seconds, in case a wake-up was missed.
///
/// Real alerts need the HealthKit capability on the RippleWearer target (see
/// docs/RUNNING.md). Without it nothing is read and `statusText` says so;
/// alerts simulated from the demo admin app still work.
@MainActor
@Observable
final class HealthAlerts {
    /// Called on the main thread for each new alert.
    @ObservationIgnored var onAlert: ((HealthAlertKind) -> Void)?
    /// Shown in Settings.
    private(set) var statusText = "Off"

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var watching: Set<HealthAlertKind> = []
    @ObservationIgnored private var queries: [HKQuery] = []
    /// Entries already turned into a check-in, so overlapping reads can't repeat one.
    @ObservationIgnored private var seen: Set<UUID> = []
    @ObservationIgnored private var lastCheck = Date.distantPast

    /// An alert older than this when Ripple first sees it doesn't start a
    /// check-in. Health can sync from the Watch late, so this isn't short.
    static let maxAge: TimeInterval = 2 * 60 * 60

    static func types(for kind: HealthAlertKind) -> [HKSampleType] {
        switch kind {
        case .fall:
            return [HKQuantityType(.numberOfTimesFallen)]
        case .heart:
            return [HKCategoryType(.highHeartRateEvent), HKCategoryType(.lowHeartRateEvent), HKCategoryType(.irregularHeartRhythmEvent)]
        }
    }

    /// Watches the chosen alerts, asking for read access first if `askPermission`.
    /// Call whenever the settings change; an empty set stops watching.
    func update(_ kinds: Set<HealthAlertKind>, askPermission: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = kinds.isEmpty ? "Off" : "Not available on this iPhone"
            return
        }
        guard !kinds.isEmpty else {
            stop()
            statusText = "Off"
            return
        }
        if askPermission {
            let read = Set(kinds.flatMap(Self.types).map { $0 as HKObjectType })
            do {
                try await store.requestAuthorization(toShare: [], read: read)
            } catch {
                stop()
                statusText = "Not in this build. Add the HealthKit capability."
                return
            }
        }
        guard kinds != watching else { return }
        stop()
        watching = kinds
        for kind in kinds {
            for type in Self.types(for: kind) {
                observe(type, kind: kind)
            }
        }
        // Apple never says whether read access was granted, so this can't be more certain.
        statusText = "On, if you allowed it in Health"
        checkNow(force: true)
    }

    /// Re-reads while the app runs, in case a wake-up was missed. At most every 30 seconds.
    func checkNow(force: Bool = false) {
        guard !watching.isEmpty, force || Date().timeIntervalSince(lastCheck) >= 30 else { return }
        lastCheck = Date()
        for kind in watching {
            for type in Self.types(for: kind) {
                readNew(type, kind: kind)
            }
        }
    }

    private func observe(_ type: HKSampleType, kind: HealthAlertKind) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            Task { @MainActor in
                guard let self, error == nil else {
                    if let error { self?.statusText = "Can't read Apple Health: \(error.localizedDescription)" }
                    completion()
                    return
                }
                self.readNew(type, kind: kind, then: completion)
            }
        }
        store.execute(query)
        queries.append(query)
        // Wakes Ripple in the background when Health saves a new entry. Needs
        // the Background Delivery option; without it this fails harmlessly.
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    /// Reads the entries saved since the last read, and reports new, recent ones.
    private func readNew(_ type: HKSampleType, kind: HealthAlertKind, then done: (() -> Void)? = nil) {
        let key = "ripple.health.anchor.\(type.identifier)"
        let anchor = UserDefaults.standard.data(forKey: key)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, error in
            Task { @MainActor in
                defer { done?() }
                guard let self, error == nil else { return }
                if let newAnchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                // The first read only marks where "new" starts, so turning this
                // on never raises a check-in for an old alert.
                guard anchor != nil else { return }
                self.report(samples ?? [], kind: kind)
            }
        }
        store.execute(query)
    }

    private func report(_ samples: [HKSample], kind: HealthAlertKind) {
        let fresh = samples.filter { sample in
            guard !seen.contains(sample.uuid), Date().timeIntervalSince(sample.endDate) < Self.maxAge else { return false }
            if let fall = sample as? HKQuantitySample {
                return fall.quantity.doubleValue(for: .count()) >= 1
            }
            return true
        }
        guard !fresh.isEmpty else { return }
        fresh.forEach { seen.insert($0.uuid) }
        onAlert?(kind)
    }

    private func stop() {
        queries.forEach(store.stop)
        queries.removeAll()
        for kind in watching {
            for type in Self.types(for: kind) {
                store.disableBackgroundDelivery(for: type) { _, _ in }
            }
        }
        watching = []
    }
}
