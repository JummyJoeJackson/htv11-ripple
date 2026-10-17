import CoreLocation
import Foundation
import KazeKit

/// Last-known location, collected only while a session is active and only if
/// the wearer allowed it. Denied or missing location never blocks an alert.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var active = false
    /// Updated on the main thread.
    private(set) var lastFix: LocationFix?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy,
            capturedAt: location.timestamp
        )
        DispatchQueue.main.async { self.lastFix = fix }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if active && (status == .authorizedWhenInUse || status == .authorizedAlways) {
            manager.startUpdatingLocation()
        }
    }
}
