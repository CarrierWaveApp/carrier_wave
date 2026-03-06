import CarrierWaveCore
import CoreLocation
import Foundation

/// Resolves the device's current location to a Maidenhead grid square.
/// Uses one-shot location request — no persistent monitoring.
@MainActor
final class LocationGridResolver: NSObject, CLLocationManagerDelegate {
    // MARK: Internal

    /// Request the device's current grid square. Returns nil if location unavailable or denied.
    func resolveGrid() async -> String? {
        // Check current authorization
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            return nil
        }

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer

        // If not determined, request permission first
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait briefly for authorization
            try? await Task.sleep(for: .seconds(1))
            let newStatus = manager.authorizationStatus
            if newStatus == .denied || newStatus == .restricted || newStatus == .notDetermined {
                return nil
            }
        }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            Task { @MainActor in
                continuation?.resume(returning: nil)
                continuation = nil
            }
            return
        }

        let grid = MaidenheadConverter.grid(from: Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))

        Task { @MainActor in
            continuation?.resume(returning: grid)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    // MARK: Private

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<String?, Never>?
}
