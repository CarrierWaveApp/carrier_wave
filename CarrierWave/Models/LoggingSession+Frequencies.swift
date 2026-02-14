import Foundation

// MARK: - LoggingSession Frequency Maps & Computed Properties

extension LoggingSession {
    /// Common CW frequencies by band
    static let cwFrequencies: [String: Double] = [
        "160m": 1.810,
        "80m": 3.530,
        "60m": 5.332,
        "40m": 7.030,
        "30m": 10.106,
        "20m": 14.060,
        "17m": 18.080,
        "15m": 21.060,
        "12m": 24.910,
        "10m": 28.060,
    ]

    /// Common SSB frequencies by band
    static let ssbFrequencies: [String: Double] = [
        "160m": 1.900,
        "80m": 3.850,
        "40m": 7.200,
        "20m": 14.250,
        "17m": 18.140,
        "15m": 21.300,
        "12m": 24.950,
        "10m": 28.400,
    ]

    /// Common FT8/FT4 frequencies by band
    static let ft8Frequencies: [String: Double] = [
        "160m": 1.840,
        "80m": 3.573,
        "40m": 7.074,
        "30m": 10.136,
        "20m": 14.074,
        "17m": 18.100,
        "15m": 21.074,
        "12m": 24.915,
        "10m": 28.074,
        "6m": 50.313,
    ]

    /// Common RTTY frequencies by band
    static let rttyFrequencies: [String: Double] = [
        "80m": 3.580,
        "40m": 7.080,
        "20m": 14.080,
        "15m": 21.080,
        "10m": 28.080,
    ]

    /// Common AM calling frequencies by band
    static let amFrequencies: [String: Double] = [
        "80m": 3.885,
        "40m": 7.290,
        "20m": 14.286,
    ]

    /// Common FM simplex frequencies by band
    static let fmFrequencies: [String: Double] = [
        "10m": 29.600,
        "6m": 52.525,
        "2m": 146.520,
        "70cm": 446.000,
    ]

    /// Band derived from frequency
    var band: String? {
        guard let freq = frequency else {
            return nil
        }
        return Self.bandForFrequency(freq)
    }

    /// Formatted duration string (e.g., "1h 23m")
    var formattedDuration: String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Display title for the session (uses customTitle if set)
    var displayTitle: String {
        if let custom = customTitle, !custom.isEmpty {
            return custom
        }
        return defaultTitle
    }

    /// Default generated title based on activation type
    var defaultTitle: String {
        switch activationType {
        case .pota:
            if let park = parkReference {
                return "\(myCallsign) at \(park)"
            }
            return "\(myCallsign) POTA"
        case .sota:
            if let summit = sotaReference {
                return "\(myCallsign) at \(summit)"
            }
            return "\(myCallsign) SOTA"
        case .casual:
            return "\(myCallsign) Casual"
        }
    }

    /// Reference for the activation (park or summit)
    var activationReference: String? {
        switch activationType {
        case .pota: parkReference
        case .sota: sotaReference
        case .casual: nil
        }
    }

    // MARK: - Static Helpers

    /// Get band name for a frequency in MHz
    static func bandForFrequency(_ freq: Double) -> String {
        switch freq {
        case 1.8 ..< 2.0: "160m"
        case 3.5 ..< 4.0: "80m"
        case 5.3 ..< 5.4: "60m"
        case 7.0 ..< 7.3: "40m"
        case 10.1 ..< 10.15: "30m"
        case 14.0 ..< 14.35: "20m"
        case 18.068 ..< 18.168: "17m"
        case 21.0 ..< 21.45: "15m"
        case 24.89 ..< 24.99: "12m"
        case 28.0 ..< 29.7: "10m"
        case 50.0 ..< 54.0: "6m"
        case 144.0 ..< 148.0: "2m"
        case 420.0 ..< 450.0: "70cm"
        default: "Unknown"
        }
    }

    /// Get suggested frequencies for a mode
    static func suggestedFrequencies(for mode: String) -> [String: Double] {
        switch mode.uppercased() {
        case "CW": cwFrequencies
        case "SSB",
             "USB",
             "LSB":
            ssbFrequencies
        case "FT8",
             "FT4":
            ft8Frequencies
        case "RTTY": rttyFrequencies
        case "AM": amFrequencies
        case "FM": fmFrequencies
        default: cwFrequencies
        }
    }
}
