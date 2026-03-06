//
//  CompassHeadingService.swift
//  CarrierWave
//
//  Provides device compass heading for antenna pattern orientation.
//

import CoreLocation
import Observation

// MARK: - CompassHeadingService

@MainActor
@Observable
final class CompassHeadingService: NSObject {
    // MARK: Lifecycle

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.headingFilter = 5 // Update every 5 degrees
    }

    // MARK: Internal

    /// Current magnetic heading in degrees (0–360), or nil if unavailable
    private(set) var heading: Double?

    /// Whether heading updates are active
    private(set) var isActive = false

    func startUpdating() {
        guard CLLocationManager.headingAvailable(), !isActive else {
            return
        }
        isActive = true
        locationManager.startUpdatingHeading()
    }

    func stopUpdating() {
        guard isActive else {
            return
        }
        isActive = false
        locationManager.stopUpdatingHeading()
    }

    // MARK: Private

    private let locationManager = CLLocationManager()
}

// MARK: CLLocationManagerDelegate

extension CompassHeadingService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        guard newHeading.headingAccuracy >= 0 else {
            return
        }
        let trueHeading = newHeading.trueHeading > 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = trueHeading
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        // Heading failures are non-fatal; just leave heading as nil
    }
}
