import CarrierWaveData
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

    /// Raw GPS coordinate from the latest fix, retained for callers that need
    /// finer-than-grid precision (e.g. TOTA activation site capture).
    private(set) var currentCoordinate: CLLocationCoordinate2D?

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
        let grid = MaidenheadConverter.grid(
            from: location.coordinate,
            precision: GridPrecisionPreference.current
        )
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        Task { @MainActor [weak self] in
            self?.currentGrid = grid
            self?.currentCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            self?.isLocating = false
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError _: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isLocating = false
        }
    }

    /// A request made while authorization was still undetermined fails
    /// immediately; re-request once the user grants permission so the
    /// one-shot fix still arrives.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            switch status {
            case .authorizedWhenInUse,
                 .authorizedAlways:
                if currentCoordinate == nil {
                    isLocating = true
                    locationManager.requestLocation()
                }
            case .denied,
                 .restricted:
                isLocating = false
            default:
                break
            }
        }
    }
}
