import Foundation

// MARK: - LoggingSession Frequency Maps & Computed Properties

extension LoggingSession {
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
            if isRove {
                let count = uniqueParkCount
                return count > 0
                    ? "\(myCallsign) Rove (\(count) \(count == 1 ? "park" : "parks"))"
                    : "\(myCallsign) POTA Rove"
            }
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
        case .wwff:
            if let ref = wwffReference {
                return "\(myCallsign) at \(ref)"
            }
            return "\(myCallsign) WWFF"
        case .aoa:
            if let mission = missionReference {
                return "\(myCallsign) AoA \(mission)"
            }
            return "\(myCallsign) AoA"
        }
    }

    /// Reference for the activation (park or summit)
    var activationReference: String? {
        switch activationType {
        case .pota: parkReference
        case .sota: sotaReference
        case .wwff: wwffReference
        case .aoa: missionReference
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

    /// Get suggested frequencies for a mode (delegates to BandPlan)
    @MainActor static func suggestedFrequencies(for mode: String) -> [String: Double] {
        switch mode.uppercased() {
        case "CW": BandPlan.cwCallingFrequencies
        case "SSB",
             "USB",
             "LSB":
            BandPlan.ssbCallingFrequencies
        case "FT8",
             "FT4":
            BandPlan.ft8Frequencies
        case "RTTY": BandPlan.rttyFrequencies
        case "AM": BandPlan.amFrequencies
        case "FM": BandPlan.fmFrequencies
        default: BandPlan.cwCallingFrequencies
        }
    }
}
