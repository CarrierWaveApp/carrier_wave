// Park Location Manager
//
// Lightweight CLLocationManager wrapper for the park picker.

import CarrierWaveData
import CoreLocation

// MARK: - ParkLocationManager

/// Lightweight CLLocationManager wrapper for the park picker
@Observable
class ParkLocationManager: NSObject, CLLocationManagerDelegate {
    // MARK: Lifecycle

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: Internal

    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            self.location = locations.last
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError _: Error
    ) {
        // Silently handle - will fall back to grid square
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    // MARK: Private

    private let manager = CLLocationManager()
}
