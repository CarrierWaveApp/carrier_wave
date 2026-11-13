// FFI Spot Adapters
//
// Conversions between the Rust spot engine's FFI records and the iOS spot
// models. The engine owns fetching/merging/enrichment/needs-matching;
// these adapters re-shape its output into the `UnifiedSpot`/`EnrichedSpot`
// types every existing view and persistence path consumes. SKCC membership
// is deliberately layered on host-side (bundled roster).

import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import UIKit

extension FfiSpotSource {
    var appSource: SpotSource {
        switch self {
        case .rbn: .rbn
        case .pota: .pota
        case .sota: .sota
        case .wwff: .wwff
        case .pskr: .pskr
        case .dxSummit: .dxSummit
        case .dxHeat: .dxHeat
        case .dxWatch: .dxWatch
        case .cluster: .cluster
        }
    }
}

extension SpotSource {
    var ffiSource: FfiSpotSource {
        switch self {
        case .rbn: .rbn
        case .pota: .pota
        case .sota: .sota
        case .wwff: .wwff
        case .pskr: .pskr
        case .dxSummit: .dxSummit
        case .dxHeat: .dxHeat
        case .dxWatch: .dxWatch
        case .cluster: .cluster
        }
    }
}

extension FfiNeedPriority {
    var appPriority: NeedPriority {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}

extension FfiMatchedNeed {
    var appNeed: MatchedNeed {
        let category: NeedCategory = switch kind {
        case .dxccEntity: .dxccEntity(entity: value ?? "")
        case .dxccBandSlot: .dxccBandSlot(entity: value ?? "", band: band ?? "")
        case .wasState: .wasState(state: value ?? "")
        case .wasStateMode: .wasStateMode(state: value ?? "", mode: band ?? "")
        case .potaNewPark: .potaNewPark
        case .potaActivatorState: .potaActivatorState(state: value ?? "")
        case .potaActivatorEntity: .potaActivatorEntity(entity: value ?? "")
        case .wwffNewReference: .wwffNewReference
        case .custom: .custom(pattern: value ?? "", label: label)
        }
        return MatchedNeed(category: category, label: label, priority: priority.appPriority)
    }
}

extension FfiEnrichedSpot {
    /// Rebuild the app's `UnifiedSpot` from the flattened FFI record.
    var appUnifiedSpot: UnifiedSpot {
        var unified = UnifiedSpot(
            id: id,
            callsign: callsign,
            frequencyKHz: frequencyKhz,
            mode: mode,
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            source: source.appSource,
            snr: snr.map(Int.init),
            wpm: wpm.map(Int.init),
            spotter: spotter,
            spotterGrid: spotterGrid,
            parkRef: parkRef,
            parkName: parkName,
            comments: comments,
            summitCode: summitCode,
            summitName: summitName,
            summitPoints: summitPoints.map(Int.init),
            locationDesc: locationDesc,
            stateAbbr: stateAbbr
        )
        unified.callsignGrid = dxGrid
        unified.wwffRef = wwffRef
        unified.wwffName = wwffName
        return unified
    }

    /// Full enriched conversion, layering SKCC membership on host-side.
    var appEnrichedSpot: EnrichedSpot {
        var enriched = EnrichedSpot(
            spot: appUnifiedSpot,
            distanceMeters: distanceMeters,
            bearingDegrees: bearingDegrees,
            region: SpotRegion(rawValue: region) ?? .other
        )
        enriched.matchedNeeds = matchedNeeds.map(\.appNeed)
        enriched.skccMember = SKCCMembershipStore.shared.member(for: callsign)
        return enriched
    }
}

extension NeedsSnapshot {
    /// Project the host-computed needs snapshot into the engine's flat FFI
    /// record (preferences resolved at call time).
    var ffiSnapshot: FfiNeedsSnapshot {
        FfiNeedsSnapshot(
            dxccAllTimeWorked: Array(dxcc.allTimeWorked),
            dxccBandSlotsWorked: dxcc.bandSlotsWorked.map {
                FfiBandSlot(entity: $0.entity, band: $0.band)
            },
            wasStatesWorked: Array(was.statesWorked),
            wasStatesMissing: Array(was.statesMissing),
            potaParksWorked: Array(potaHunter.parksWorked),
            potaActivatorStatesMissing: Array(potaActivator.statesMissing),
            wwffReferencesWorked: Array(wwffHunter.referencesWorked),
            customPatterns: customPatterns.map { pattern in
                let patternType: FfiCustomPatternType = switch pattern.patternType {
                case .callsign: .callsign
                case .entity: .entity
                case .state: .state
                case .parkRef: .parkRef
                }
                return FfiCustomPattern(
                    pattern: pattern.pattern,
                    patternType: patternType,
                    label: pattern.label
                )
            },
            modeFamiliesWorked: Array(modeFamiliesWorked),
            trackDxcc: NeedsPreferences.trackDXCC,
            trackWas: NeedsPreferences.trackWAS,
            trackPotaHunter: NeedsPreferences.trackPOTAHunter,
            trackWwffHunter: NeedsPreferences.trackWWFFHunter
        )
    }
}
