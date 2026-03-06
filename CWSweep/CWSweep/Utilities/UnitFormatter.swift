import Foundation

/// Formats distances using the synced `useMetricUnits` iCloud KVS preference from Carrier Wave
enum UnitFormatter {
    /// Whether to use metric units (km) vs imperial (mi).
    /// Reads the same key Carrier Wave writes via iCloud KVS.
    static var useMetric: Bool {
        UserDefaults.standard.bool(forKey: "useMetricUnits")
    }

    /// Format a distance given in kilometers
    static func distance(_ km: Double) -> String {
        if useMetric {
            if km < 1 {
                return String(format: "%.0f m", km * 1_000)
            }
            return String(format: "%.0f km", km)
        } else {
            let miles = km * 0.621371
            return String(format: "%.0f mi", miles)
        }
    }

    /// Format a distance given in meters
    static func distanceFromMeters(_ meters: Double) -> String {
        distance(meters / 1_000.0)
    }
}
