import CarrierWaveData
import Foundation

// MARK: - UnitFormatter

/// Centralized unit formatting that respects the user's imperial/metric preference.
/// All inputs use the canonical unit (km for distance, °F for temperature, mph for wind).
nonisolated enum UnitFormatter {
    // MARK: Internal

    /// Whether the user prefers metric units
    static var useMetric: Bool {
        UserDefaults.standard.bool(forKey: "useMetricUnits")
    }

    // MARK: - Distance

    /// Format a distance in km with unit label.
    /// Sub-kilometer values show meters; large values use "k" suffix.
    static func distance(_ km: Double) -> String {
        if useMetric {
            return metricDistance(km)
        }
        let mi = km * kmToMiles
        return imperialDistance(mi)
    }

    /// Compact distance (no unit label, for tight spaces like map overlays).
    /// Returns e.g. "5.2k" or "340" (implied km or mi).
    static func distanceCompact(_ km: Double) -> String {
        if useMetric {
            if km >= 1_000 {
                return String(format: "%.0fk", km / 1_000)
            }
            return String(format: "%.0f", km)
        }
        let mi = km * kmToMiles
        if mi >= 1_000 {
            return String(format: "%.0fk", mi / 1_000)
        }
        return String(format: "%.0f", mi)
    }

    /// Distance with a label suffix (e.g. "340 mi avg", "1.2k km max").
    static func distanceCompact(_ km: Double, label: String) -> String {
        let unit = useMetric ? "km" : "mi"
        let value = useMetric ? km : km * kmToMiles
        if value >= 1_000 {
            let precision = value >= 10_000 ? "0" : "1"
            return String(format: "%.\(precision)fk \(unit) \(label)", value / 1_000)
        }
        return String(format: "%.0f \(unit) \(label)", value)
    }

    /// Format a distance range from meters (e.g. "120-450 km" or "75-280 mi").
    static func distanceRange(minMeters: Double, maxMeters: Double) -> String {
        if useMetric {
            let minKm = minMeters / 1_000.0
            let maxKm = maxMeters / 1_000.0
            return String(format: "%.0f-%.0f km", minKm, maxKm)
        }
        let minMi = minMeters / 1_609.344
        let maxMi = maxMeters / 1_609.344
        return String(format: "%.0f-%.0f mi", minMi, maxMi)
    }

    // MARK: - Temperature

    /// Format a temperature given in Fahrenheit.
    static func temperature(_ fahrenheit: Double) -> String {
        if useMetric {
            let celsius = (fahrenheit - 32) * 5.0 / 9.0
            return "\(Int(celsius.rounded()))\u{00B0}C"
        }
        return "\(Int(fahrenheit))\u{00B0}F"
    }

    /// Compact temperature for tight badges — just "16°" with no unit suffix.
    static func temperatureCompact(_ fahrenheit: Double) -> String {
        if useMetric {
            let celsius = (fahrenheit - 32) * 5.0 / 9.0
            return "\(Int(celsius.rounded()))\u{00B0}"
        }
        return "\(Int(fahrenheit))\u{00B0}"
    }

    /// The secondary unit display (opposite of preference).
    static func temperatureSecondary(_ fahrenheit: Double) -> String {
        if useMetric {
            return "\(Int(fahrenheit))\u{00B0}F"
        }
        let celsius = (fahrenheit - 32) * 5.0 / 9.0
        return "\(Int(celsius.rounded()))\u{00B0}C"
    }

    // MARK: - Wind Speed

    /// Format wind speed given in mph, optionally with direction.
    static func windSpeed(_ mph: Double, direction: String? = nil) -> String {
        let suffix = direction.map { " \($0)" } ?? ""
        if useMetric {
            let kmh = mph * mphToKmh
            return "\(Int(kmh.rounded())) km/h\(suffix)"
        }
        return "\(Int(mph)) mph\(suffix)"
    }

    // MARK: - Watts Per Distance

    /// Format watts per mile with the appropriate unit label.
    /// Input is always in watts per mile (internal computation unit).
    static func wattsPerDistance(_ wpm: Double) -> String {
        if useMetric {
            // W/mi to W/km: 1 km = 0.621371 mi, so W/km = W/mi * 0.621371
            return String(format: "%.2f W/km", wpm * kmToMiles)
        }
        return String(format: "%.2f W/mi", wpm)
    }

    /// Label-only for watts-per-distance (e.g. for stat labels).
    static func wattsPerDistanceLabel() -> String {
        useMetric ? "W/km" : "W/mi"
    }

    // MARK: - Bearing

    /// Format bearing degrees to cardinal direction (N, NE, E, SE, S, SW, W, NW).
    static func cardinal(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[index]
    }

    /// Format distance (meters) and bearing (degrees) into a compact string.
    /// e.g. "1,240 mi NE" or "2,000 km S"
    static func distanceAndBearing(
        meters: Double, bearingDeg: Double
    ) -> String {
        let km = meters / 1_000.0
        return "\(distance(km)) \(cardinal(bearingDeg))"
    }

    // MARK: Private

    // MARK: - Conversion Constants

    private static let kmToMiles = 0.621371
    private static let milesToKm = 1.60934
    private static let mphToKmh = 1.60934

    // MARK: - Private Helpers

    private static func metricDistance(_ km: Double) -> String {
        if km < 1 {
            return String(format: "%.0f m", km * 1_000)
        }
        if km < 10 {
            return String(format: "%.1f km", km)
        }
        if km >= 1_000 {
            return String(format: "%.0fk km", km / 1_000)
        }
        return String(format: "%.0f km", km)
    }

    private static func imperialDistance(_ mi: Double) -> String {
        if mi < 0.1 {
            let feet = mi * 5_280
            return String(format: "%.0f ft", feet)
        }
        if mi < 10 {
            return String(format: "%.1f mi", mi)
        }
        if mi >= 1_000 {
            return String(format: "%.0fk mi", mi / 1_000)
        }
        return String(format: "%.0f mi", mi)
    }
}
