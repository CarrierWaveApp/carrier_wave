import CoreLocation
import Observation

// MARK: - GridLocationService

/// Lightweight one-shot GPS → grid square service.
/// Requests a single location fix and converts it to a 6-char Maidenhead locator.
@MainActor
@Observable
final class GridLocationService: NSObject {
    // MARK: Lifecycle

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: Internal

    /// The GPS-derived 6-character grid square, or nil if not yet determined
    private(set) var currentGrid: String?

    /// Whether a location request is in flight
    private(set) var isLocating = false

    /// Request a one-shot location fix and convert to grid
    func requestGrid() {
        guard !isLocating else {
            return
        }
        isLocating = true
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    // MARK: Private

    private let locationManager = CLLocationManager()
}

// MARK: CLLocationManagerDelegate

extension GridLocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            return
        }
        let grid = MaidenheadConverter.grid(from: location.coordinate)
        Task { @MainActor in
            self.currentGrid = grid
            self.isLocating = false
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError _: Error
    ) {
        Task { @MainActor in
            self.isLocating = false
        }
    }
}
