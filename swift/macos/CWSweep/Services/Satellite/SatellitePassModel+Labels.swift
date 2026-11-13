import Foundation

// MARK: - SatellitePassModel labels and tables

extension SatellitePassModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Keys {
        static let minPeak = "satellite.minPeakElevationDeg"
    }

    /// Uplink CTCSS for the common FM birds (Hz), keyed by NORAD ID.
    static let tonesHz: [Int: Double] = [
        27_607: 67.0, // SO-50
        25_544: 67.0, // ISS cross-band repeater
        43_017: 67.0, // AO-91
        43_137: 67.0, // AO-92
        44_909: 141.3, // PO-101
    ]

    /// "12 min" / "3.2 h" since the TLE set was fetched.
    var tleAgeLabel: String {
        guard let tlesFetchedAt else {
            return "TLE —"
        }
        let age = Date().timeIntervalSince(tlesFetchedAt)
        let text = if age < 3_600 {
            "\(Int(age / 60)) min"
        } else if age < 48 * 3_600 {
            String(format: "%.1f h", age / 3_600)
        } else {
            "\(Int(age / 86_400)) d"
        }
        return tlesStale ? "TLE \(text) (stale)" : "TLE \(text)"
    }
}
