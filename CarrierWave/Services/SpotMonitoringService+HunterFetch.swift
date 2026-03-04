// Spot Monitoring Service — Hunter Fetch
//
// Extension with hunter-mode spot fetching methods (RBN, POTA, SOTA, WWFF).

import CarrierWaveData
import Foundation

// MARK: - SpotMonitoringService + Hunter Fetch

extension SpotMonitoringService {
    /// Fetch all RBN spots (not per-callsign) for hunter mode
    func fetchHunterRBNSpots(since cutoff: Date) async -> [UnifiedSpot] {
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
                summitCode: nil,
                summitName: nil,
                summitPoints: nil,
                locationDesc: nil,
                stateAbbr: nil
            )
        }
    }

    /// Fetch all POTA spots for hunter mode
    func fetchHunterPOTASpots(since cutoff: Date) async -> [UnifiedSpot] {
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
                summitCode: nil,
                summitName: nil,
                summitPoints: nil,
                locationDesc: spot.locationDesc,
                stateAbbr: UnifiedSpot.parseState(from: spot.locationDesc)
            )
        }
    }

    /// Fetch all SOTA spots for hunter mode
    func fetchHunterSOTASpots(since cutoff: Date) async -> [UnifiedSpot] {
        if sotaClient == nil {
            sotaClient = SOTAClient()
        }
        guard let sotaSpots = try? await sotaClient!.fetchSpots(count: 50) else {
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

    /// Fetch all WWFF spots for hunter mode
    func fetchHunterWWFFSpots(since cutoff: Date) async -> [UnifiedSpot] {
        if wwffClient == nil {
            wwffClient = WWFFClient()
        }
        guard let wwffSpots = try? await wwffClient!.fetchSpots() else {
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
                summitCode: nil,
                summitName: nil,
                summitPoints: nil,
                locationDesc: nil,
                stateAbbr: nil
            )
            unified.wwffRef = spot.reference
            unified.wwffName = spot.locationName
            return unified
        }
    }
}
