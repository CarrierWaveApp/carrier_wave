import Foundation

// MARK: - BandPropagation

/// Estimated propagation quality for a specific amateur band.
public struct BandPropagation: Sendable, Identifiable {
    // MARK: Lifecycle

    public init(band: String, quality: PropagationQuality, mufEstimateMHz: Double?) {
        self.band = band
        self.quality = quality
        self.mufEstimateMHz = mufEstimateMHz
    }

    // MARK: Public

    /// Band name (e.g., "20m", "40m")
    public let band: String

    /// Overall propagation quality
    public let quality: PropagationQuality

    /// Estimated MUF in MHz (nil if unknown)
    public let mufEstimateMHz: Double?

    public var id: String {
        band
    }
}

// MARK: - PropagationQuality

/// Quality level for band propagation.
public enum PropagationQuality: Int, Sendable, Comparable {
    case closed = 0
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4

    // MARK: Public

    public var label: String {
        switch self {
        case .closed: "Closed"
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    public static func < (lhs: PropagationQuality, rhs: PropagationQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - PropagationEstimator

/// Estimates HF band propagation quality from solar indices.
///
/// Uses a simplified model based on:
/// - Solar Flux Index (SFI) → estimated MUF via empirical curves
/// - K-index → ionospheric absorption penalty
/// - Time of day (UTC hour) → D-layer and F-layer behavior
///
/// This is a rough estimate, not a replacement for real-time ionosonde data.
public enum PropagationEstimator {
    // MARK: Public

    /// Estimate propagation for all HF amateur bands.
    /// - Parameters:
    ///   - sfi: Solar Flux Index (typically 60-300)
    ///   - kIndex: Planetary K-index (0-9)
    ///   - utcHour: Current UTC hour (0-23)
    /// - Returns: Per-band propagation estimates, ordered low-freq to high-freq.
    public static func estimate(
        sfi: Double,
        kIndex: Double,
        utcHour: Int
    ) -> [BandPropagation] {
        let estimatedMUF = estimateMUF(sfi: sfi, kIndex: kIndex, utcHour: utcHour)

        return bands.map { band in
            let quality = bandQuality(
                bandFreqMHz: band.centerMHz,
                muf: estimatedMUF,
                kIndex: kIndex,
                utcHour: utcHour,
                isLowBand: band.isLow
            )
            return BandPropagation(
                band: band.name,
                quality: quality,
                mufEstimateMHz: estimatedMUF
            )
        }
    }

    /// Suggest the best band for current conditions.
    /// - Parameters:
    ///   - sfi: Solar Flux Index
    ///   - kIndex: K-index
    ///   - utcHour: Current UTC hour
    /// - Returns: The band with the best propagation, or nil if all closed.
    public static func bestBand(
        sfi: Double,
        kIndex: Double,
        utcHour: Int
    ) -> BandPropagation? {
        let estimates = estimate(sfi: sfi, kIndex: kIndex, utcHour: utcHour)
        return estimates.max { $0.quality < $1.quality }
    }

    /// Human-readable summary explaining current propagation conditions.
    public static func conditionSummary(
        sfi: Double,
        kIndex: Double,
        utcHour: Int
    ) -> String {
        let muf = estimateMUF(sfi: sfi, kIndex: kIndex, utcHour: utcHour)
        let isNight = utcHour < 6 || utcHour > 20

        var parts: [String] = []

        // MUF / band opening story
        if kIndex >= 5 {
            parts.append(
                "Geomagnetic storm (K=\(Int(kIndex))) is suppressing propagation on most bands."
            )
        } else if muf >= 25 {
            parts.append(
                "Higher bands wide open \u{2014} SFI \(Int(sfi)) is pushing MUF to ~\(Int(muf)) MHz."
            )
        } else if muf >= 18 {
            parts.append(
                "Mid and upper HF bands open \u{2014} estimated MUF near \(Int(muf)) MHz."
            )
        } else if muf >= 10 {
            parts.append(
                "Lower HF bands usable \u{2014} MUF around \(Int(muf)) MHz limits higher bands."
            )
        } else {
            parts.append(
                "Propagation limited \u{2014} low SFI (\(Int(sfi))) keeping MUF near \(Int(muf)) MHz."
            )
        }

        // K-index context
        if kIndex < 2 {
            parts.append("Quiet geomagnetic conditions (K=\(Int(kIndex))).")
        } else if kIndex < 4 {
            parts.append("Moderate geomagnetic activity (K=\(Int(kIndex))).")
        }

        // Time-of-day context
        if isNight {
            parts.append("Nighttime: low bands favored as D-layer absorption fades.")
        }

        return parts.joined(separator: " ")
    }

    /// Contextual label for a Solar Flux Index value.
    public static func sfiDescription(_ sfi: Double) -> String {
        switch sfi {
        case ..<80: "Low"
        case ..<120: "Moderate"
        case ..<180: "High"
        default: "Very High"
        }
    }

    /// Contextual label for a K-index value.
    public static func kIndexDescription(_ kIndex: Double) -> String {
        switch kIndex {
        case ..<2: "Quiet"
        case ..<4: "Unsettled"
        case ..<5: "Active"
        case ..<6: "Storm"
        default: "Severe Storm"
        }
    }

    /// Brief explanation of why a specific band has its current quality.
    public static func bandExplanation(
        band: BandPropagation,
        kIndex: Double,
        utcHour: Int
    ) -> String {
        let isNight = utcHour < 6 || utcHour > 20
        let isLowBand = ["160m", "80m", "60m"].contains(band.band)

        if isLowBand {
            if isNight {
                if kIndex >= 5 {
                    return "Night helps, but geomagnetic storm is degrading signals."
                }
                return "Nighttime \u{2014} D-layer gone, good for low-band propagation."
            } else {
                return "Daytime D-layer absorption limits low-band propagation."
            }
        }

        guard let muf = band.mufEstimateMHz else {
            return ""
        }

        let bandFreqs: [String: Double] = [
            "40m": 7.1, "30m": 10.1, "20m": 14.1,
            "17m": 18.1, "15m": 21.1, "12m": 24.9, "10m": 28.3,
        ]
        guard let freq = bandFreqs[band.band] else {
            return ""
        }

        let headroom = muf - freq
        if headroom < -5 {
            return "Above estimated MUF (\(Int(muf)) MHz) \u{2014} signals unlikely."
        } else if headroom < 0 {
            return "Near MUF ceiling \u{2014} marginal, occasional openings possible."
        } else if headroom < 5 {
            return "Close to MUF \u{2014} usable but may fade."
        } else {
            return "Well below MUF (\(Int(muf)) MHz) \u{2014} solid propagation expected."
        }
    }

    // MARK: Private

    private struct BandDef {
        let name: String
        let centerMHz: Double
        let isLow: Bool
    }

    private static let bands: [BandDef] = [
        BandDef(name: "160m", centerMHz: 1.9, isLow: true),
        BandDef(name: "80m", centerMHz: 3.6, isLow: true),
        BandDef(name: "60m", centerMHz: 5.3, isLow: true),
        BandDef(name: "40m", centerMHz: 7.1, isLow: false),
        BandDef(name: "30m", centerMHz: 10.1, isLow: false),
        BandDef(name: "20m", centerMHz: 14.1, isLow: false),
        BandDef(name: "17m", centerMHz: 18.1, isLow: false),
        BandDef(name: "15m", centerMHz: 21.1, isLow: false),
        BandDef(name: "12m", centerMHz: 24.9, isLow: false),
        BandDef(name: "10m", centerMHz: 28.3, isLow: false),
    ]

    /// Rough MUF estimate from SFI and K-index.
    ///
    /// Based on simplified empirical relationship:
    /// - Base MUF scales roughly with sqrt(SFI)
    /// - K-index depresses MUF through increased absorption
    /// - Daytime MUF is higher than nighttime
    private static func estimateMUF(sfi: Double, kIndex: Double, utcHour: Int) -> Double {
        // Base MUF from SFI: empirical sqrt relationship
        // SFI 70 → ~14 MHz, SFI 150 → ~21 MHz, SFI 250 → ~28 MHz
        let baseMUF = 1.7 * sqrt(sfi)

        // K-index penalty: each K unit above 2 reduces MUF by ~8%
        let kPenalty = max(0, kIndex - 2.0) * 0.08
        let kFactor = max(0.5, 1.0 - kPenalty)

        // Diurnal factor: MUF peaks at ~14 UTC, minimum at ~04 UTC
        let diurnalFactor = diurnalMultiplier(utcHour: utcHour)

        return baseMUF * kFactor * diurnalFactor
    }

    /// Diurnal MUF multiplier (simplified, assumes mid-latitude location).
    /// Peak at ~14 UTC, trough at ~04 UTC.
    private static func diurnalMultiplier(utcHour: Int) -> Double {
        // Sinusoidal model: peak at 14 UTC
        let hour = Double(utcHour)
        let phase = (hour - 14.0) * .pi / 12.0
        return 0.7 + 0.3 * cos(phase) // Range: 0.4 to 1.0
    }

    /// Determine propagation quality for a band.
    private static func bandQuality(
        bandFreqMHz: Double,
        muf: Double,
        kIndex: Double,
        utcHour: Int,
        isLowBand: Bool
    ) -> PropagationQuality {
        // Low bands (160m, 80m, 60m) are better at night, worse with high K
        if isLowBand {
            return lowBandQuality(
                bandFreqMHz: bandFreqMHz,
                kIndex: kIndex,
                utcHour: utcHour
            )
        }

        // High bands: quality depends on MUF vs band frequency
        let headroom = muf - bandFreqMHz

        if headroom < -5 {
            return .closed
        } else if headroom < 0 {
            return .poor
        } else if headroom < 5 {
            // Near the MUF — some propagation but unreliable
            return kIndex < 3 ? .fair : .poor
        } else if headroom < 15 {
            return kIndex < 2 ? .excellent : kIndex < 4 ? .good : .fair
        } else {
            // Well below MUF — solid propagation
            return kIndex < 3 ? .good : .fair
        }
    }

    /// Low band propagation depends primarily on darkness and geomagnetic activity.
    private static func lowBandQuality(
        bandFreqMHz: Double,
        kIndex: Double,
        utcHour: Int
    ) -> PropagationQuality {
        let isNight = utcHour < 6 || utcHour > 20

        if kIndex >= 5 {
            return .poor
        }

        if isNight {
            if bandFreqMHz < 2.0 {
                // 160m: excellent at night with low K
                return kIndex < 2 ? .good : kIndex < 4 ? .fair : .poor
            } else {
                // 80m/60m: good at night
                return kIndex < 3 ? .good : .fair
            }
        } else {
            // Daytime: D-layer absorption kills low bands
            return bandFreqMHz < 4 ? .poor : .fair
        }
    }
}
