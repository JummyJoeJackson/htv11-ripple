import CoreLocation
import Foundation
import RippleKit

/// Takes one location fix when an alarm starts, only if a contact has
/// location sharing on. Location is never tracked in the background.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [(LocationFix?) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var statusText: String {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Allowed while using the app"
        case .denied: return "Denied in Settings"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// The completion runs on the main thread, with nil if location isn't available.
    func requestOneFix(_ completion: @escaping (LocationFix?) -> Void) {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            completion(nil)
            return
        }
        waiting.append(completion)
        manager.requestLocation()
    }

    private func deliver(_ fix: LocationFix?) {
        let callbacks = waiting
        waiting.removeAll()
        DispatchQueue.main.async {
            callbacks.forEach { $0(fix) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        deliver(LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy,
            capturedAt: location.timestamp
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        deliver(nil)
    }
}
