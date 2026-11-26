import CoreLocation
import Foundation
import Observation

// MARK: - LocationSessionService

/// Continuous GPS → Maidenhead grid tracking for logging sessions.
/// Shared between LoggingSessionManager and ActivityLogManager.
/// Uses reference-counted start/stop so multiple callers can
/// independently request monitoring.
@MainActor
@Observable
final class LocationSessionService: NSObject {
    // MARK: Lifecycle

    init(locationProvider: any LocationProviding = CLLocationManager()) {
        self.locationProvider = locationProvider
        super.init()
        locationProvider.delegate = self
        locationProvider.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: Internal

    /// The current GPS-derived 6-character grid square, or nil if unknown.
    /// Only updates when the grid actually changes (with debounce).
    private(set) var currentGrid: String?

    /// The latest GPS fix, published only after the station moves about
    /// 25 m, so observers (BKG Turf Wars corner detection) aren't woken on
    /// every update.
    private(set) var currentFix: GPSFix?

    /// Current authorization status for UI fallback display
    private(set) var locationAuthorized: Bool = false

    /// Whether a location error occurred (for UI fallback message)
    private(set) var locationError: String?

    /// Whether the service is actively monitoring
    var isMonitoring: Bool {
        startCount > 0
    }

    /// Request monitoring start. Reference-counted — call `stop()` once
    /// for each `start()` call.
    func start() {
        startCount += 1
        guard startCount == 1 else {
            return
        }
        locationError = nil
        let status = locationProvider.authorizationStatus
        locationAuthorized = status == .authorizedWhenInUse
            || status == .authorizedAlways
        if status == .notDetermined {
            locationProvider.requestWhenInUseAuthorization()
        } else if locationAuthorized {
            locationProvider.startUpdatingLocation()
        } else {
            locationError = "Location permission denied"
        }
    }

    /// Decrement the reference count. Stops monitoring when it reaches zero.
    func stop() {
        guard startCount > 0 else {
            return
        }
        startCount -= 1
        guard startCount == 0 else {
            return
        }
        locationProvider.stopUpdatingLocation()
        pendingGrid = nil
        pendingGridCount = 0
    }

    /// Force-stop regardless of reference count (for cleanup)
    func forceStop() {
        startCount = 0
        locationProvider.stopUpdatingLocation()
        pendingGrid = nil
        pendingGridCount = 0
    }

    // MARK: Private

    private let locationProvider: any LocationProviding
    private var startCount = 0

    /// Debounce: require 2 consecutive fixes with the same new grid
    private var pendingGrid: String?
    private var pendingGridCount = 0
}

// MARK: CLLocationManagerDelegate

extension LocationSessionService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            return
        }
        let grid = MaidenheadConverter.grid(
            from: location.coordinate,
            precision: GridPrecisionPreference.current
        )
        let fix = GPSFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy
        )
        Task { @MainActor in
            self.processFix(fix)
            self.processGridUpdate(grid)
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.locationError = message
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _: CLLocationManager
    ) {
        // Read status from our own provider, not the passed manager parameter,
        // so tests can control authorization via the mock.
        Task { @MainActor in
            let status = self.locationProvider.authorizationStatus
            let authorized = status == .authorizedWhenInUse
                || status == .authorizedAlways
            self.locationAuthorized = authorized
            if authorized, self.isMonitoring {
                self.locationError = nil
                self.locationProvider.startUpdatingLocation()
            } else if !authorized, self.isMonitoring {
                self.locationError = "Location permission denied"
                self.locationProvider.stopUpdatingLocation()
            }
        }
    }
}

// MARK: - Grid Processing

@MainActor
private extension LocationSessionService {
    func processFix(_ fix: GPSFix) {
        guard fix.horizontalAccuracy >= 0 else {
            return
        }
        if let last = currentFix, last.distanceMeters(to: fix) < 25 {
            return
        }
        currentFix = fix
    }

    func processGridUpdate(_ grid: String) {
        // Same as current — no update needed
        guard grid != currentGrid else {
            pendingGrid = nil
            pendingGridCount = 0
            return
        }

        // Debounce: require 2 consecutive fixes at the new grid
        if grid == pendingGrid {
            pendingGridCount += 1
        } else {
            pendingGrid = grid
            pendingGridCount = 1
        }

        if pendingGridCount >= 2 {
            currentGrid = grid
            DeviceLocationHint.record(grid: grid)
            pendingGrid = nil
            pendingGridCount = 0
        }
    }
}

// MARK: - GPSFix

/// A GPS position, `Equatable` so SwiftUI can observe it.
struct GPSFix: Equatable {
    let latitude: Double
    let longitude: Double
    /// Metres; negative means invalid (CoreLocation's convention).
    let horizontalAccuracy: Double

    func distanceMeters(to other: GPSFix) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
