// Records a continuous GPS track during a session, primarily for TOTA where
// distance and elevation gain are scoring inputs.
//
// Buffers `TrackPoint` samples in memory and persists them to the active
// `LoggingSession.trackPointsData` blob. Caller controls lifecycle:
//
//     let tracker = LocationTrackingService()
//     await tracker.start()
//     // … later …
//     let points = await tracker.stop()
//     session.trackPoints = points
//
// Authorization is best-requested during session start (the user already
// granted "When In Use" for grid lookup); the service falls back gracefully
// when permission is denied.

import CarrierWaveData
import CoreLocation
import Observation

// MARK: - LocationTrackingService

@MainActor
@Observable
final class LocationTrackingService: NSObject {
    // MARK: Lifecycle

    override init() {
        super.init()
        locationManager.delegate = self
        // Best-effort accuracy; ~10 m horizontal is plenty for tile/distance scoring
        // and dramatically less battery-hungry than `kCLLocationAccuracyBest`.
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10 // metres between updates
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: Internal

    private(set) var isTracking = false
    private(set) var points: [TrackPoint] = []

    /// Latest sample, useful for status overlays.
    var latestPoint: TrackPoint? {
        points.last
    }

    /// Total distance walked so far, in miles. Sums spherical distances between
    /// successive samples. Cheap to recompute since we cap point count via thinning.
    var distanceMiles: Double {
        Self.totalDistanceMiles(in: points)
    }

    /// Net elevation gain in feet (sum of positive deltas). Returns 0 when the
    /// device hasn't reported elevation values (e.g. simulator).
    var elevationGainFeet: Double {
        Self.totalElevationGainFeet(in: points)
    }

    // MARK: - Pure helpers (exposed `internal` for tests)

    static func totalDistanceMiles(in points: [TrackPoint]) -> Double {
        guard points.count > 1 else {
            return 0
        }
        var meters: Double = 0
        for index in 1 ..< points.count {
            let previous = points[index - 1]
            let current = points[index]
            let firstLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let secondLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            meters += secondLocation.distance(from: firstLocation)
        }
        return Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: .miles)
            .value
    }

    static func totalElevationGainFeet(in points: [TrackPoint]) -> Double {
        guard points.count > 1 else {
            return 0
        }
        var gainMeters: Double = 0
        for index in 1 ..< points.count {
            guard let previous = points[index - 1].elevationMeters,
                  let current = points[index].elevationMeters
            else {
                continue
            }
            let delta = current - previous
            if delta > 0 {
                gainMeters += delta
            }
        }
        return Measurement(value: gainMeters, unit: UnitLength.meters)
            .converted(to: .feet)
            .value
    }

    /// Begin tracking. Idempotent — second call is a no-op.
    func start() {
        guard !isTracking else {
            return
        }
        isTracking = true
        points.removeAll()
        // `requestWhenInUseAuthorization` is safe to call repeatedly; the system
        // only prompts the first time.
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    /// Stop tracking and return the collected points (already thinned).
    @discardableResult
    func stop() -> [TrackPoint] {
        guard isTracking else {
            return points
        }
        locationManager.stopUpdatingLocation()
        isTracking = false
        return points
    }

    /// Reset to an empty trail without changing tracking state. Useful for
    /// "clear and start over" UI affordances.
    func reset() {
        points.removeAll()
    }

    // MARK: Private

    /// Drop a sample if it's within 5 metres / 2 seconds of the previous one,
    /// and never let the buffer exceed `maxPoints`. Keeps the JSON blob bounded
    /// even on multi-hour activations.
    private static let maxPoints = 5_000
    private static let minPointSpacingMeters: CLLocationDistance = 5
    private static let minPointSpacingSeconds: TimeInterval = 2

    private let locationManager = CLLocationManager()

    private func appendIfFresh(_ location: CLLocation) {
        if let last = points.last {
            let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let distance = location.distance(from: lastLocation)
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            if distance < Self.minPointSpacingMeters,
               timeDelta < Self.minPointSpacingSeconds
            {
                return
            }
        }

        let elevation: Double? = location.verticalAccuracy >= 0 ? location.altitude : nil
        let point = TrackPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevationMeters: elevation
        )
        points.append(point)

        // Hard cap the buffer; if we're over, evict the oldest half by stride
        // so we don't lose endpoints. Cheaper than maintaining a ring buffer
        // and only kicks in for very long activations.
        if points.count > Self.maxPoints {
            let stride = 2
            points = points.enumerated()
                .compactMap { index, point in index.isMultiple(of: stride) ? point : nil }
        }
    }
}

// MARK: - LocationSample

/// Sendable snapshot of one CLLocation reading. Captured on the delegate
/// thread before hopping to MainActor; using a typed struct (vs. an N-tuple)
/// keeps SwiftLint happy with the 2-member tuple cap.
private struct LocationSample {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let verticalAccuracy: Double
}

// MARK: - LocationTrackingService + CLLocationManagerDelegate

extension LocationTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Capture sendable values before hopping to the main actor.
        let samples: [LocationSample] = locations.map { location in
            LocationSample(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                verticalAccuracy: location.verticalAccuracy
            )
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            for sample in samples {
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: sample.latitude,
                        longitude: sample.longitude
                    ),
                    altitude: sample.altitude,
                    horizontalAccuracy: 0,
                    verticalAccuracy: sample.verticalAccuracy,
                    timestamp: sample.timestamp
                )
                appendIfFresh(location)
            }
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError _: Error
    ) {
        // Soft-fail: leave the existing points alone; the user can retry.
    }
}
