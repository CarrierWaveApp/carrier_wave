//
//  FT8DecodeEnricher.swift
//  CarrierWave
//

import CarrierWaveData
import Foundation

// MARK: - FT8DecodeEnricher

/// Enriches raw FT8 decode results with worked-before status, DXCC entity,
/// distance/bearing, and other metadata for display in the FT8 interface.
///
/// All lookups are O(1) in-memory — no async calls during enrichment.
/// Preload worked history via `loadWorkedHistory` at session start, then
/// call `enrich` synchronously each decode cycle (~15 seconds).
@MainActor
final class FT8DecodeEnricher {
    // MARK: Lifecycle

    init(myCallsign: String, myGrid: String, currentBand: String) {
        self.myCallsign = myCallsign
        self.myGrid = myGrid
        self.currentBand = currentBand
    }

    // MARK: Internal

    private(set) var currentCycleIndex = 0

    /// Advance the cycle counter. Called at each slot boundary.
    func advanceCycle() {
        currentCycleIndex += 1
    }

    /// Enrich an array of raw decodes into enriched decodes with metadata.
    func enrich(_ decodes: [FT8DecodeResult]) -> [FT8EnrichedDecode] {
        decodes.map { decode in
            var enriched = enrichSingle(decode)
            enriched.cycleAge = 0
            return enriched
        }
    }

    /// Mark a callsign as worked during this session (for dupe detection).
    func markWorkedThisSession(_ callsign: String) {
        sessionWorkedCallsigns.insert(callsign.uppercased())
    }

    /// Load precomputed worked history sets for new-entity/grid/band detection.
    ///
    /// - Parameters:
    ///   - dxccEntities: Country names already worked (e.g. "United States", "Japan")
    ///   - grids: Grid squares already worked (e.g. "FN31", "PM95")
    ///   - callBandCombos: Callsign-band pairs already worked (e.g. "W1AW-20m")
    func loadWorkedHistory(
        dxccEntities: Set<String>,
        grids: Set<String>,
        callBandCombos: Set<String>
    ) {
        workedDXCCEntities = dxccEntities
        workedGrids = grids
        workedCallBandCombos = callBandCombos
    }

    // MARK: Private

    private let myCallsign: String
    private let myGrid: String
    private let currentBand: String

    private var workedDXCCEntities: Set<String> = []
    private var workedGrids: Set<String> = []
    private var workedCallBandCombos: Set<String> = []
    private var sessionWorkedCallsigns: Set<String> = []

    private func enrichSingle(_ decode: FT8DecodeResult) -> FT8EnrichedDecode {
        let callsign = decode.message.callerCallsign
        let grid = decode.message.grid

        // DXCC entity lookup
        let dxccEntity: String? = callsign.flatMap { call in
            let entity = DescriptionLookup.entityDescription(for: call)
            return entity == "Unknown" ? nil : entity
        }

        // Distance and bearing from grid (use fully-qualified name to avoid local wrapper)
        let distanceMiles: Int? = grid.flatMap { theirGrid in
            CarrierWaveCore.MaidenheadConverter.distanceMiles(from: myGrid, to: theirGrid).map { Int($0) }
        }

        let bearing: Int? = grid.flatMap { theirGrid in
            CarrierWaveCore.MaidenheadConverter.bearing(from: myGrid, to: theirGrid).map { Int($0) }
        }

        // Directed-at-me check
        let isDirectedAtMe = decode.message.isDirectedTo(myCallsign)

        // New DXCC: entity is known and not in the worked set
        let isNewDXCC = dxccEntity.map { !workedDXCCEntities.contains($0) } ?? false

        // New grid: grid is present and not in the worked set
        let isNewGrid = grid.map { !workedGrids.contains($0) } ?? false

        // New band: callsign has been worked on another band but NOT on the current band
        let isNewBand: Bool = {
            guard let call = callsign else {
                return false
            }
            let upperCall = call.uppercased()
            let currentCombo = "\(upperCall)-\(currentBand)"
            // Not new band if already worked on this band
            if workedCallBandCombos.contains(currentCombo) {
                return false
            }
            // New band only if worked on at least one other band
            return workedCallBandCombos.contains { combo in
                combo.hasPrefix("\(upperCall)-") && combo != currentCombo
            }
        }()

        // Dupe: callsign was worked during this session
        let isDupe: Bool = callsign.map { call in
            sessionWorkedCallsigns.contains(call.uppercased())
        } ?? false

        return FT8EnrichedDecode(
            decode: decode,
            dxccEntity: dxccEntity,
            stateProvince: nil,
            distanceMiles: distanceMiles,
            bearing: bearing,
            isNewDXCC: isNewDXCC,
            isNewState: false,
            isNewGrid: isNewGrid,
            isNewBand: isNewBand,
            isDupe: isDupe,
            isDirectedAtMe: isDirectedAtMe
        )
    }
}
