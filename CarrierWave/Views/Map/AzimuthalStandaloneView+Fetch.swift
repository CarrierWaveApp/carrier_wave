//
//  AzimuthalStandaloneView+Fetch.swift
//  CarrierWave
//
//  Spot fetching from all sources (RBN, POTA, SOTA, WWFF)
//  and HamDB grid enrichment for the azimuthal map.
//

import CarrierWaveData
import Foundation

// MARK: - Source Fetching

extension AzimuthalStandaloneView {
    func fetchRBNSpots(since cutoff: Date) async -> [UnifiedSpot] {
        let client = RBNClient()
        guard let rbnSpots = try? await client.spots(since: cutoff, limit: 200) else {
            return []
        }
        return rbnSpots.map { spot in
            UnifiedSpot(
                id: "rbn-\(spot.id)",
                callsign: spot.callsign,
                frequencyKHz: spot.frequency,
                mode: spot.mode,
                timestamp: spot.timestamp,
                source: .rbn,
                snr: spot.snr,
                wpm: spot.wpm,
                spotter: spot.spotter,
                spotterGrid: spot.spotterGrid,
                parkRef: nil,
                parkName: nil,
                comments: nil,
                locationDesc: nil,
                stateAbbr: nil
            )
        }
    }

    func fetchPOTASpots(since cutoff: Date) async -> [UnifiedSpot] {
        let client = POTAClient(authService: POTAAuthService())
        guard let potaSpots = try? await client.fetchActiveSpots() else {
            return []
        }
        return potaSpots.compactMap { spot in
            guard let freqKHz = spot.frequencyKHz,
                  let timestamp = spot.timestamp,
                  timestamp >= cutoff
            else {
                return nil
            }
            return UnifiedSpot(
                id: "pota-\(spot.spotId)",
                callsign: spot.activator,
                frequencyKHz: freqKHz,
                mode: spot.mode,
                timestamp: timestamp,
                source: .pota,
                snr: nil,
                wpm: nil,
                spotter: spot.spotter,
                spotterGrid: nil,
                parkRef: spot.reference,
                parkName: spot.parkName,
                comments: spot.comments,
                locationDesc: spot.locationDesc,
                stateAbbr: UnifiedSpot.parseState(from: spot.locationDesc)
            )
        }
    }

    func fetchSOTASpots(since cutoff: Date) async -> [UnifiedSpot] {
        let client = SOTAClient()
        guard let sotaSpots = try? await client.fetchSpots(count: 50) else {
            return []
        }
        return sotaSpots.compactMap { spot in
            guard let freqKHz = spot.frequencyKHz,
                  let timestamp = spot.parsedTimestamp,
                  timestamp >= cutoff
            else {
                return nil
            }
            return UnifiedSpot(
                id: "sota-\(spot.id)",
                callsign: spot.activatorCallsign,
                frequencyKHz: freqKHz,
                mode: spot.mode.uppercased(),
                timestamp: timestamp,
                source: .sota,
                snr: nil,
                wpm: nil,
                spotter: spot.spotterCallsign,
                spotterGrid: nil,
                parkRef: nil,
                parkName: nil,
                comments: spot.comments,
                summitCode: spot.fullSummitReference,
                summitName: spot.summitName,
                summitPoints: spot.points,
                locationDesc: nil,
                stateAbbr: nil
            )
        }
    }

    func fetchWWFFSpots(since cutoff: Date) async -> [UnifiedSpot] {
        let client = WWFFClient()
        guard let wwffSpots = try? await client.fetchSpots() else {
            return []
        }
        return wwffSpots.compactMap { spot in
            guard let freqKHz = spot.frequencyKHz,
                  let timestamp = spot.parsedTimestamp,
                  timestamp >= cutoff
            else {
                return nil
            }
            var unified = UnifiedSpot(
                id: "wwff-\(spot.id)",
                callsign: spot.activator,
                frequencyKHz: freqKHz,
                mode: spot.mode.uppercased(),
                timestamp: timestamp,
                source: .wwff,
                snr: nil,
                wpm: nil,
                spotter: spot.spotter,
                spotterGrid: nil,
                parkRef: nil,
                parkName: nil,
                comments: spot.comments,
                locationDesc: nil,
                stateAbbr: nil
            )
            unified.wwffRef = spot.reference
            unified.wwffName = spot.locationName
            return unified
        }
    }
}

// MARK: - Grid Enrichment

extension AzimuthalStandaloneView {
    /// Look up callsign grids via HamDB for map projection
    func enrichCallsignGrids(_ spots: [UnifiedSpot]) async -> [UnifiedSpot] {
        let hamDB = HamDBClient()
        let maxLookups = 30

        // Find unique callsigns that need grid lookup
        var callsignsToLookup: [String] = []
        var seen = Set<String>()
        for spot in spots {
            let call = spot.callsign.uppercased()
            guard !seen.contains(call) else {
                continue
            }
            seen.insert(call)

            // Skip if we already have a cached grid
            if let cached = await GridCache.shared.get(call) {
                if cached != nil {
                    continue
                } // Already have a grid
                continue // Already looked up and found nothing
            }

            callsignsToLookup.append(call)
            if callsignsToLookup.count >= maxLookups {
                break
            }
        }

        // Look up grids in parallel
        if !callsignsToLookup.isEmpty {
            await withTaskGroup(of: (String, String?).self) { group in
                for callsign in callsignsToLookup {
                    group.addTask {
                        let grid = try? await hamDB.lookup(callsign: callsign)?.grid
                        return (callsign, grid)
                    }
                }
                for await (callsign, grid) in group {
                    await GridCache.shared.set(callsign, grid: grid)
                }
            }
        }

        // Apply cached grids to spots
        var enriched: [UnifiedSpot] = []
        for var spot in spots {
            let call = spot.callsign.uppercased()
            if let cachedGrid = await GridCache.shared.get(call) {
                spot.callsignGrid = cachedGrid
            }
            enriched.append(spot)
        }
        return enriched
    }
}
