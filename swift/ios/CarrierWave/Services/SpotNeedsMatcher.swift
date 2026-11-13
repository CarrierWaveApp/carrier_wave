// Spot Needs Summary
//
// The per-spot needs MATCHING moved to the Rust spot engine (cw-domain
// needs matcher; spots arrive with `matchedNeeds` already populated via
// `FfiEnrichedSpot.matched_needs`). What remains host-side is the
// aggregation of matched spots into the one-line "needs on the air"
// summary shown in the hunter UI.

import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - SpotNeedsMatcher

enum SpotNeedsMatcher {
    /// Quick summary of matched needs across all spots.
    static func summarize(
        _ spots: [EnrichedSpot]
    ) -> NeedsOnAirSummary {
        var dxccCount = 0
        var wasStates = Set<String>()
        var potaParkCount = 0
        var wwffRefCount = 0
        var customCount = 0

        let matchedSpots = spots.filter(\.hasNeeds)

        for spot in matchedSpots {
            for need in spot.matchedNeeds {
                switch need.category {
                case .dxccEntity:
                    dxccCount += 1
                case .dxccBandSlot:
                    break // Don't double-count
                case let .wasState(state),
                     let .wasStateMode(state, _):
                    wasStates.insert(state)
                case .potaNewPark:
                    potaParkCount += 1
                case .wwffNewReference:
                    wwffRefCount += 1
                case .custom:
                    customCount += 1
                case .potaActivatorState,
                     .potaActivatorEntity:
                    break
                }
            }
        }

        return NeedsOnAirSummary(
            totalMatchedSpots: matchedSpots.count,
            newDXCCEntities: dxccCount,
            wasStates: wasStates,
            newPOTAParks: potaParkCount,
            newWWFFReferences: wwffRefCount,
            customMatches: customCount
        )
    }
}

// MARK: - NeedsOnAirSummary

/// Aggregated summary of needs currently on the air.
struct NeedsOnAirSummary {
    static let empty = NeedsOnAirSummary(
        totalMatchedSpots: 0,
        newDXCCEntities: 0,
        wasStates: [],
        newPOTAParks: 0,
        newWWFFReferences: 0,
        customMatches: 0
    )

    let totalMatchedSpots: Int
    let newDXCCEntities: Int
    let wasStates: Set<String>
    let newPOTAParks: Int
    let newWWFFReferences: Int
    let customMatches: Int

    var hasMatches: Bool {
        totalMatchedSpots > 0
    }

    /// Human-readable one-line summary.
    var summaryText: String {
        var parts: [String] = []
        if newDXCCEntities > 0 {
            parts.append(
                "\(newDXCCEntities) new DXCC"
            )
        }
        if !wasStates.isEmpty {
            let stateList = wasStates.sorted().prefix(3)
                .joined(separator: ", ")
            let suffix = wasStates.count > 3
                ? " +\(wasStates.count - 3)"
                : ""
            parts.append("WAS: \(stateList)\(suffix)")
        }
        if newPOTAParks > 0 {
            parts.append(
                "\(newPOTAParks) new park\(newPOTAParks == 1 ? "" : "s")"
            )
        }
        if newWWFFReferences > 0 {
            parts.append(
                "\(newWWFFReferences) new WWFF"
            )
        }
        if customMatches > 0 {
            parts.append(
                "\(customMatches) custom"
            )
        }
        return parts.isEmpty ? "No needs on the air" : parts.joined(separator: " · ")
    }
}
