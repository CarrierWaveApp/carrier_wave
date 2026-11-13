import SwiftUI

// MARK: - SatelliteFilterBucket

/// Work-type buckets for the map/pass-list filter. Unlike the engine's
/// `SatelliteModeCategory` (which serves the AMSAT capability gating and
/// mutual planner), this splits **telemetry** — downlink-only transmitters
/// you can receive but never work through — out of digital, so beacon-only
/// cubesats can be hidden without losing real digital birds.
nonisolated enum SatelliteFilterBucket: String, CaseIterable, Identifiable, Sendable {
    case fm = "FM"
    case linear = "LINEAR"
    case digital = "DIGI"
    case telemetry = "TLM"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .fm:
            "FM"
        case .linear:
            "Linear"
        case .digital:
            "Digital"
        case .telemetry:
            "Telemetry"
        }
    }

    /// No uplink = telemetry (nothing to transmit into); otherwise the
    /// mode decides, with CW folded into linear (it rides the transponder).
    static func bucket(for transmitter: SatNOGSTransmitter) -> SatelliteFilterBucket {
        guard transmitter.uplinkLow != nil else {
            return .telemetry
        }
        switch SatelliteModeCategory.category(for: transmitter) {
        case .voiceFM:
            return .fm
        case .linear,
             .morse:
            return .linear
        case .digital:
            return .digital
        }
    }
}

// MARK: - SatBand

/// Amateur-satellite band letters (the community's mode-designator
/// alphabet: V/U for 2 m / 70 cm, etc.) for the uplink/downlink filters.
nonisolated enum SatBand: String, CaseIterable, Identifiable, Sendable {
    case hf = "H"
    case vhf = "V"
    case uhf = "U"
    case lBand = "L"
    case sBand = "S"
    case cBand = "C"
    case xBand = "X"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .hf:
            "H (HF)"
        case .vhf:
            "V (2 m)"
        case .uhf:
            "U (70 cm)"
        case .lBand:
            "L (23 cm)"
        case .sBand:
            "S (13 cm)"
        case .cBand:
            "C (6 cm)"
        case .xBand:
            "X (3 cm)"
        }
    }

    static func band(forHz hz: Int64) -> SatBand {
        let mhz = Double(hz) / 1_000_000
        switch mhz {
        case ..<100:
            return .hf
        case ..<225:
            return .vhf
        case ..<1_000:
            return .uhf
        case ..<2_000:
            return .lBand
        case ..<3_500:
            return .sBand
        case ..<8_000:
            return .cBand
        default:
            return .xBand
        }
    }
}

// MARK: - SkySector

/// Eight compass sectors for the clear-sky (horizon mask) filter: disable
/// the directions your horizon is blocked and passes peaking there drop
/// out.
nonisolated enum SkySector: String, CaseIterable, Identifiable, Sendable {
    case north = "N"
    case northeast = "NE"
    case east = "E"
    case southeast = "SE"
    case south = "S"
    case southwest = "SW"
    case west = "W"
    case northwest = "NW"

    // MARK: Internal

    var id: String {
        rawValue
    }

    /// The 45° sector containing an azimuth (N spans 337.5°–22.5°).
    static func sector(forAzimuth degrees: Double) -> SkySector {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int(((normalized + 22.5) / 45).rounded(.down)) % 8
        return allCases[index]
    }
}

// MARK: - SatelliteFilterSelections

/// One snapshot of the transmitter-level filter dimensions (bird-level
/// dimensions — favorites, elevation, sky sectors — apply at the call
/// sites). Built from the callers' `@AppStorage` values so SwiftUI
/// observation stays intact.
nonisolated struct SatelliteFilterSelections {
    // MARK: Lifecycle

    init(modeRaw: String, uplinkRaw: String, downlinkRaw: String, heardRecentlyOnly: Bool) {
        buckets = SatelliteModeFilter.selection(from: modeRaw)
        uplink = SatelliteModeFilter.bandSelection(from: uplinkRaw)
        downlink = SatelliteModeFilter.bandSelection(from: downlinkRaw)
        self.heardRecentlyOnly = heardRecentlyOnly
    }

    // MARK: Internal

    let buckets: Set<SatelliteFilterBucket>
    let uplink: Set<SatBand>
    let downlink: Set<SatBand>
    let heardRecentlyOnly: Bool
}

// MARK: - SatelliteModeFilter

/// Shared persisted work-type + band filters for the satellite map and
/// pass lists — one set of keys, so hiding telemetry birds on the map
/// hides their passes too. Empty storage decodes as "all" (filter off).
nonisolated enum SatelliteModeFilter {
    static let storageKey = "satelliteModeFilter"
    static let uplinkBandKey = "satelliteUplinkBandFilter"
    static let downlinkBandKey = "satelliteDownlinkBandFilter"
    /// Minimum next-pass peak elevation (degrees; 0 = any). On the map
    /// this hides birds with no pass peaking at or above the threshold
    /// in the upcoming sweep window; pass lists filter per pass.
    static let minPeakElevationKey = "satelliteMinPeakElevation"
    /// Only birds the AMSAT community heard in the last 7 days (untracked
    /// birds keep the benefit of the doubt — most digital/beacon birds
    /// aren't on AMSAT's list at all).
    static let heardRecentlyKey = "satelliteHeardRecentlyOnly"
    /// Only favorited birds.
    static let favoritesOnlyKey = "satelliteFavoritesOnly"
    /// Horizon mask: per-sector minimum elevation ("N:30,W:90", degrees;
    /// absent sector = clear to the horizon). Beta-tester ask (N9HO):
    /// "depending on the direction I may be deaf until above 30°."
    static let horizonMaskKey = "satelliteHorizonMask"

    /// The heard-recently window (matches the FM workability rule).
    static let heardRecentlyWindow: TimeInterval = 7 * 24 * 3_600

    /// A sector marked fully blocked.
    static let blockedElevation = 90

    /// The per-sector minimums a horizon chip taps through.
    static let horizonSteps = [0, 10, 20, 30, 45, blockedElevation]

    /// Threshold choices in the steps operators actually use (N9HO: "15°
    /// is usually about the hard minimum, I set mine to 20/25").
    static let peakElevationOptions: [Int] = [0, 10, 15, 20, 25, 30, 45]

    static func peakElevationLabel(_ degrees: Int) -> String {
        degrees == 0 ? "Any" : "\(degrees)°"
    }

    /// The enabled buckets; empty/unrecognized raw = everything.
    static func selection(from raw: String) -> Set<SatelliteFilterBucket> {
        let decoded = Set(
            raw.split(separator: ",").compactMap { SatelliteFilterBucket(rawValue: String($0)) }
        )
        return decoded.isEmpty ? Set(SatelliteFilterBucket.allCases) : decoded
    }

    /// Toggle one bucket, never below one enabled (an empty map is a dead
    /// end, and empty storage would flip back to "all" anyway).
    static func toggled(_ bucket: SatelliteFilterBucket, raw: String) -> String {
        var buckets = selection(from: raw)
        if buckets.contains(bucket) {
            guard buckets.count > 1 else {
                return raw
            }
            buckets.remove(bucket)
        } else {
            buckets.insert(bucket)
        }
        return buckets.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// The enabled bands for one direction; empty/unrecognized raw = all.
    static func bandSelection(from raw: String) -> Set<SatBand> {
        let decoded = Set(raw.split(separator: ",").compactMap { SatBand(rawValue: String($0)) })
        return decoded.isEmpty ? Set(SatBand.allCases) : decoded
    }

    /// Toggle one band, never below one enabled.
    static func toggledBand(_ band: SatBand, raw: String) -> String {
        var bands = bandSelection(from: raw)
        if bands.contains(band) {
            guard bands.count > 1 else {
                return raw
            }
            bands.remove(band)
        } else {
            bands.insert(band)
        }
        return bands.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// The per-sector minimum elevations; sectors absent from the raw are
    /// clear to the horizon (0°).
    static func horizonMask(from raw: String) -> [SkySector: Int] {
        var mask = [SkySector: Int]()
        for entry in raw.split(separator: ",") {
            let parts = entry.split(separator: ":")
            guard parts.count == 2,
                  let sector = SkySector(rawValue: String(parts[0])),
                  let degrees = Int(parts[1])
            else {
                continue
            }
            mask[sector] = degrees
        }
        return mask
    }

    /// Tap-cycle one sector through the horizon steps (0 → 10 → … →
    /// blocked → 0).
    static func cycledHorizon(_ sector: SkySector, raw: String) -> String {
        var mask = horizonMask(from: raw)
        let current = mask[sector] ?? 0
        let index = horizonSteps.firstIndex(of: current) ?? 0
        let next = horizonSteps[(index + 1) % horizonSteps.count]
        mask[sector] = next
        return mask
            .filter { $0.value > 0 }
            .map { "\($0.key.rawValue):\($0.value)" }
            .sorted()
            .joined(separator: ",")
    }

    /// Any direction raised above the horizon?
    static func horizonActive(_ mask: [SkySector: Int]) -> Bool {
        mask.values.contains { $0 > 0 }
    }

    /// Does a pass peaking here clear the direction's minimum elevation?
    static func horizonAllows(
        peakAzimuthDeg: Double, peakElevationDeg: Double, mask: [SkySector: Int]
    ) -> Bool {
        peakElevationDeg >= Double(mask[.sector(forAzimuth: peakAzimuthDeg)] ?? 0)
    }

    /// Does the bird carry a transmitter satisfying ALL the
    /// transmitter-level filters at once (bucket + uplink band + downlink
    /// band + heard-recently)? An active uplink-band filter requires an
    /// uplink — it means "something I can transmit into on these bands" —
    /// likewise downlink; heard-recently only indicts AMSAT-tracked
    /// capabilities that have fallen silent (untracked birds keep the
    /// benefit of the doubt).
    static func matches(
        _ transmitters: [SatNOGSTransmitter],
        selections: SatelliteFilterSelections
    ) -> Bool {
        let allBuckets = selections.buckets.count == SatelliteFilterBucket.allCases.count
        let allUplink = selections.uplink.count == SatBand.allCases.count
        let allDownlink = selections.downlink.count == SatBand.allCases.count
        if allBuckets, allUplink, allDownlink, !selections.heardRecentlyOnly {
            return true
        }
        let heardCutoff = Date(timeIntervalSinceNow: -heardRecentlyWindow)
        return transmitters.contains { transmitter in
            guard allBuckets || selections.buckets.contains(.bucket(for: transmitter)) else {
                return false
            }
            if !allUplink {
                guard let uplink = transmitter.uplinkLow,
                      selections.uplink.contains(.band(forHz: uplink))
                else {
                    return false
                }
            }
            if !allDownlink {
                guard let downlink = transmitter.downlinkLow,
                      selections.downlink.contains(.band(forHz: downlink))
                else {
                    return false
                }
            }
            if selections.heardRecentlyOnly, transmitter.amsatTracked {
                guard let heard = transmitter.amsatLastHeardAt, heard > heardCutoff else {
                    return false
                }
            }
            return true
        }
    }
}
