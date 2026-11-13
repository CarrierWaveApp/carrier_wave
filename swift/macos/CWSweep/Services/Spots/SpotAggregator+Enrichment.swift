import CarrierWaveCore
import CoreLocation
import Foundation

// MARK: - SpotAggregator + Enrichment

extension SpotAggregator {
    /// Enrich unified spots with distance, region, DXCC, and publish
    func enrichAndPublish() {
        let userCoord = userCoordinate()
        let lookup = dxccLookup
        let checker = neededChecker
        let enrichCache = callsignEnrichmentCache

        spots = unifiedSpots.values.map { spot in
            // Apply cached grid if spot has no DX grid
            var enrichedSpot = spot
            let cached = enrichCache[spot.callsign.uppercased()]
            if enrichedSpot.dxGrid == nil, let grid = cached?.grid, !grid.isEmpty {
                enrichedSpot.dxGrid = grid
            }

            let gridForRegion = enrichedSpot.dxGrid ?? enrichedSpot.spotterGrid
            let region = SpotRegion.from(grid: gridForRegion)
            let spotGrid = enrichedSpot.dxGrid ?? enrichedSpot.spotterGrid
            let distance = distanceBetween(userCoord: userCoord, spotGrid: spotGrid)
            let bearing = bearingTo(spotGrid: spotGrid)

            // DXCC entity resolution via CTY.dat
            let entity = lookup?.lookup(spot.callsign)
            let needed: NeededStatus = {
                guard let entityName = entity?.name, let checker
                else {
                    return .unknown
                }
                return checker.check(
                    entityName: entityName, band: spot.band
                )
            }()

            return EnrichedSpot(
                spot: enrichedSpot,
                distanceMeters: distance,
                bearingDegrees: bearing,
                region: region,
                state: spot.stateAbbr ?? cached?.state,
                country: entity?.name ?? cached?.country,
                dxccEntity: entity?.name,
                dxccCode: nil,
                neededStatus: needed,
                operatorName: cached?.operatorName,
                skccMember: SKCCMembershipStore.shared.member(for: spot.callsign)
            )
        }
        .sorted { $0.spot.timestamp > $1.spot.timestamp }

        // Kick off callsign lookups (runs batches back-to-back)
        cancelEnrichment()
        enrichWithCallsignLookup()
    }

    // MARK: - Callsign Enrichment (QRZ + HamDB)

    /// Kick off callsign lookups. Runs batches back-to-back until all
    /// visible spots have been looked up, independent of the spot poll timer.
    func enrichWithCallsignLookup() {
        // Don't start a second enrichment loop if one is already running
        guard enrichmentTask == nil else {
            return
        }

        enrichmentTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let batch = nextEnrichmentBatch()
                guard !batch.isEmpty else {
                    break
                }

                let results = await lookupBatch(batch)
                guard !Task.isCancelled else {
                    break
                }
                applyCallsignResults(results)
            }
            self?.enrichmentTask = nil
        }
    }

    /// Cancel any in-flight enrichment loop (called before a fresh one starts)
    func cancelEnrichment() {
        enrichmentTask?.cancel()
        enrichmentTask = nil
    }

    /// Next batch of callsigns that haven't been looked up yet.
    private func nextEnrichmentBatch() -> [String] {
        let alreadyLookedUp = callsignEnrichmentCache
        let needed = spots
            .map(\.spot.callsign)
            .filter { alreadyLookedUp[$0.uppercased()] == nil }
        let unique = Array(Set(needed))
        return Array(unique.prefix(20))
    }

    /// Look up a batch of callsigns via QRZ + HamDB in parallel.
    private func lookupBatch(
        _ batch: [String]
    ) async -> [String: CallsignEnrichment] {
        await withTaskGroup(
            of: (String, CallsignEnrichment).self
        ) { group in
            for callsign in batch {
                group.addTask {
                    if let cached = await CallsignStateCache.shared
                        .get(callsign)
                    {
                        return (callsign, CallsignEnrichment(
                            state: cached?.state,
                            country: cached?.country,
                            operatorName: cached?.operatorName,
                            grid: cached?.grid
                        ))
                    }

                    let info = await CallsignInfoCache.shared.lookup(
                        callsign: callsign, qsoSummaries: []
                    )
                    let enrichment = CallsignEnrichment(info: info)

                    await CallsignStateCache.shared.set(
                        callsign,
                        info: .init(
                            state: enrichment.state,
                            country: enrichment.country,
                            operatorName: enrichment.operatorName,
                            grid: enrichment.grid
                        )
                    )
                    return (callsign, enrichment)
                }
            }

            var results: [String: CallsignEnrichment] = [:]
            for await (call, enrichment) in group {
                results[call] = enrichment
            }
            return results
        }
    }

    struct CallsignEnrichment {
        // MARK: Lifecycle

        init(state: String?, country: String?, operatorName: String?, grid: String?) {
            self.state = state
            self.country = country
            self.operatorName = operatorName
            self.grid = grid
        }

        init(info: CallsignInfo) {
            state = info.qrzResult?.state ?? info.license?.state
            country = info.qrzResult?.country ?? info.license?.country
            operatorName = info.operatorName
            grid = info.qrzResult?.grid ?? info.license?.grid
        }

        // MARK: Internal

        let state: String?
        let country: String?
        let operatorName: String?
        let grid: String?
    }

    func applyCallsignResults(
        _ results: [String: CallsignEnrichment]
    ) {
        // Persist to local cache so enrichAndPublish() preserves data
        for (callsign, enrichment) in results {
            callsignEnrichmentCache[callsign.uppercased()] = enrichment
        }

        // Apply to current spots
        for idx in spots.indices {
            let callsign = spots[idx].spot.callsign
            if let result = results[callsign] {
                if spots[idx].state == nil,
                   let st = result.state, !st.isEmpty
                {
                    spots[idx].state = st
                }
                if spots[idx].country == nil,
                   let ctry = result.country, !ctry.isEmpty
                {
                    spots[idx].country = ctry
                }
                if spots[idx].operatorName == nil,
                   let opName = result.operatorName, !opName.isEmpty
                {
                    spots[idx].operatorName = opName
                }
                if spots[idx].spot.dxGrid == nil,
                   let grid = result.grid, !grid.isEmpty
                {
                    spots[idx].spot.dxGrid = grid
                }
            }
        }
        spotsVersion += 1
    }

    // MARK: - Geo Helpers

    func userCoordinate() -> CLLocationCoordinate2D? {
        guard !userGrid.isEmpty,
              let coord = MaidenheadConverter.coordinate(from: userGrid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    func bearingTo(spotGrid: String?) -> Double? {
        guard !userGrid.isEmpty, let spotGrid else {
            return nil
        }
        return MaidenheadConverter.bearing(from: userGrid, to: spotGrid)
    }

    func distanceBetween(
        userCoord: CLLocationCoordinate2D?,
        spotGrid: String?
    ) -> Double? {
        guard let userCoord,
              let grid = spotGrid,
              let spotCoord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        let userLocation = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let spotLocation = CLLocation(latitude: spotCoord.latitude, longitude: spotCoord.longitude)
        return userLocation.distance(from: spotLocation)
    }
}
