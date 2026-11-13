import CarrierWaveData
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
        let base = defaultTitleBase
        guard isMultiOp else {
            return base
        }
        let ops = operatorCallsigns.joined(separator: ", ")
        return "\(base) w/ \(ops)"
    }

    /// Base title without multi-op suffix
    private var defaultTitleBase: String {
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
        case .tota:
            if let grid = myGrid, !grid.isEmpty {
                return "\(myCallsign) TOTA \(grid)"
            }
            return "\(myCallsign) TOTA"
        }
    }

    /// Reference for the activation (park or summit)
    nonisolated var activationReference: String? {
        switch activationType {
        case .pota: parkReference
        case .sota: sotaReference
        case .wwff: wwffReference
        case .aoa: missionReference
        case .tota: myGrid
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

    /// Get suggested frequencies for a mode (delegates to BandPlan).
    /// CW/SSB lookups dispatch by the operator's IARU region so we don't
    /// suggest 3.560 MHz to an SM0 operator whose band plan puts CW on
    /// 3.555 MHz. FT8/FT4/RTTY/digital frequencies are coordinated
    /// globally and don't have regional variants.
    @MainActor static func suggestedFrequencies(for mode: String) -> [String: Double] {
        let region = UserRegionProfile.primaryIARURegion ?? .region2
        return switch mode.uppercased() {
        case "CW":
            regionalFrequencies(region: region) { BandPlan.cwCallingFrequency(band: $0, region: $1) }
                ?? BandPlan.cwCallingFrequencies
        case "SSB",
             "USB",
             "LSB":
            regionalFrequencies(region: region) { BandPlan.ssbCallingFrequency(band: $0, region: $1) }
                ?? BandPlan.ssbCallingFrequencies
        case "FT8":
            BandPlan.ft8Frequencies
        case "FT4":
            BandPlan.ft4Frequencies
        case "RTTY": BandPlan.rttyFrequencies
        case "AM": BandPlan.amFrequencies
        case "FM": BandPlan.fmFrequencies
        default: BandPlan.cwCallingFrequencies
        }
    }

    /// Build a region-filtered band→frequency dictionary using the given
    /// per-band lookup, iterating over bands that have a Region-2
    /// entry (which today is a superset of the regional overrides).
    private static func regionalFrequencies(
        region: IARURegion,
        lookup: (String, IARURegion) -> Double?
    ) -> [String: Double]? {
        var result: [String: Double] = [:]
        for band in BandPlan.cwCallingFrequencies.keys {
            if let freq = lookup(band, region) {
                result[band] = freq
            }
        }
        return result.isEmpty ? nil : result
    }
}
