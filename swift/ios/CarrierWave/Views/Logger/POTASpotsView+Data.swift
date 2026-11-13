import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - POTASpotsView Data Loading & Grouping

extension POTASpotsView {
    static func groupSpotsByBand(
        _ spots: [POTASpot]
    ) -> [(band: String, spots: [POTASpot])] {
        let grouped = Dictionary(grouping: spots) { spot -> String in
            BandUtilities.deriveBand(from: spot.frequencyKHz) ?? "Other"
        }
        return grouped.sorted { lhs, rhs in
            let lhsIdx = BandUtilities.bandOrder.firstIndex(of: lhs.key) ?? 999
            let rhsIdx = BandUtilities.bandOrder.firstIndex(of: rhs.key) ?? 999
            return lhsIdx < rhsIdx
        }.map {
            (
                band: $0.key,
                // Human spots first, then RBN; secondary sort by frequency
                spots: $0.value.sorted { lhs, rhs in
                    if lhs.isHumanSpot != rhs.isHumanSpot {
                        return lhs.isHumanSpot
                    }
                    return (lhs.frequencyKHz ?? 0) < (rhs.frequencyKHz ?? 0)
                }
            )
        }
    }

    static func groupSOTASpotsByBand(
        _ spots: [SOTASpot]
    ) -> [(band: String, spots: [SOTASpot])] {
        let grouped = Dictionary(grouping: spots) { spot -> String in
            BandUtilities.deriveBand(from: spot.frequencyKHz) ?? "Other"
        }
        return grouped.sorted { lhs, rhs in
            let lhsIdx = BandUtilities.bandOrder.firstIndex(of: lhs.key) ?? 999
            let rhsIdx = BandUtilities.bandOrder.firstIndex(of: rhs.key) ?? 999
            return lhsIdx < rhsIdx
        }.map {
            (band: $0.key, spots: $0.value.sorted { ($0.frequencyKHz ?? 0) < ($1.frequencyKHz ?? 0) })
        }
    }

    func loadSpots() async {
        isLoading = true
        errorMessage = nil

        let provider = SpotEngineProvider.shared
        guard let engine = provider.engine() else {
            errorMessage = provider.lastEngineError
            allSpots = []
            allSOTASpots = []
            isLoading = false
            return
        }

        // One engine poll covers POTA and SOTA; the Logger's S2S
        // enrichment reads the same pool via `SOTASpotsCache`.
        await engine.refresh()
        let spots = engine.snapshot(filter: nil, worked: nil).spots
        allSpots = spots.compactMap(\.appPotaSpot)
        allSOTASpots = spots.compactMap(\.appSotaSpot)
        isLoading = false
        await loadWorkedBefore()
    }

    func loadWorkedBefore() async {
        let container = modelContext.container
        await workedBeforeCache.loadToday(container: container)

        let potaCallsigns = allSpots.map(\.activator)
        let sotaCallsigns = allSOTASpots.map(\.activatorCallsign)
        let allCallsigns = potaCallsigns + sotaCallsigns
        await workedBeforeCache.checkCallsigns(allCallsigns, container: container)

        var results: [String: WorkedBeforeResult] = [:]
        for spot in allSpots {
            let upper = spot.activator.uppercased()
            let band = BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
            results[upper] = await workedBeforeCache.result(
                for: upper,
                band: band
            )
        }
        for spot in allSOTASpots {
            let upper = spot.activatorCallsign.uppercased()
            let band = BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
            results[upper] = await workedBeforeCache.result(
                for: upper,
                band: band
            )
        }
        workedResults = results
    }

    func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else {
                return
            }
            await loadSpots()
        }
    }
}
