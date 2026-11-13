import CarrierWaveCore
import CoreLocation
import UIKit

// MARK: - DeviceLocationHint

/// Persistent, best-effort "where is the user?" hint used to avoid hardcoded
/// US-centric map defaults. Writes are performed by `LocationSessionService`
/// whenever a GPS fix lands on a new grid; reads do not require location
/// permission and are safe to call from any thread.
///
/// Lookup priority used by map and onboarding flows:
///   1. `loggerDefaultGrid` (user-set)
///   2. `DeviceLocationHint.shared.lastKnownGrid`
///   3. nil — caller should use `.automatic` camera or a world view
enum DeviceLocationHint {
    // MARK: Internal

    /// Persisted last-known Maidenhead grid from GPS. `nil` until the
    /// location service has produced at least one fix.
    static var lastKnownGrid: String? {
        get {
            let value = UserDefaults.standard.string(forKey: gridKey)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: gridKey)
            } else {
                UserDefaults.standard.removeObject(forKey: gridKey)
            }
        }
    }

    /// Coordinate center of `lastKnownGrid`, or nil if no grid has been
    /// recorded.
    static var lastKnownCoordinate: CLLocationCoordinate2D? {
        guard let grid = lastKnownGrid,
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        return coord
    }

    /// Best-effort home coordinate for map views — checks user-set grid
    /// first, then the persisted device-location hint. Returns nil when
    /// nothing is known; callers should use `.automatic` camera in that
    /// case instead of a hardcoded fallback.
    static var bestKnownHomeCoordinate: CLLocationCoordinate2D? {
        let defaultGrid = UserDefaults.standard.string(forKey: "loggerDefaultGrid") ?? ""
        if !defaultGrid.isEmpty,
           let coord = MaidenheadConverter.coordinate(from: defaultGrid)
        {
            return coord
        }
        return lastKnownCoordinate
    }

    /// Record a new GPS-derived grid. Also seeds `loggerDefaultGrid` on
    /// first fix so downstream features (session start, azimuthal map,
    /// WebSDR picker) stop falling back to US-centric behavior.
    static func record(grid: String) {
        guard !grid.isEmpty else {
            return
        }
        lastKnownGrid = grid

        let defaults = UserDefaults.standard
        let existing = defaults.string(forKey: "loggerDefaultGrid") ?? ""
        if existing.isEmpty {
            defaults.set(grid, forKey: "loggerDefaultGrid")
        }
    }

    // MARK: Private

    private static let gridKey = "deviceLocationHintGrid"
}
