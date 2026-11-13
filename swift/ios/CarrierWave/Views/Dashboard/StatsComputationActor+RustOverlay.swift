import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - StatsComputationActor + cw-store overlay

/// `.on`-mode overlays: replace specific computed-stats fields with cw-store values
/// (SQL aggregates) while the snapshot scan still produces everything not yet in the
/// analytics catalog. Split from `StatsComputationActor.swift` for file length. Parity
/// with the SwiftData math is gated by the `Analytics*ParityTests`.
extension StatsComputationActor {
    /// Overwrite the headline distinct counts with cw-store values.
    static func overlayRustHeadlineCounts(
        into stats: inout ComputedStats,
        store: FieldStore
    ) async {
        guard let counts = try? await RustAnalyticsReadSource(store: store)
            .distinctCounts(query: "")
        else {
            return
        }
        stats.totalQSOs = counts.qsos
        stats.uniqueBands = counts.bands
        stats.uniqueGrids = counts.grids
        stats.uniqueEntities = counts.entities
        stats.confirmedQSLs = counts.confirmed
        stats.qrzConfirmedCount = counts.qrzConfirmed
        stats.lotwConfirmedCount = counts.lotwConfirmed
        stats.qsosWithGrid = counts.withGrid
        stats.qsosWithParkRef = counts.withPark
        stats.qsosWithDXCC = counts.withDXCC
        stats.uniqueCallsignCount = counts.uniqueCallsigns
    }

    /// Replace the WAS drilldown with cw-store values. Reassembles the flat
    /// `was_drilldown` rows into the `[WASFilterKey: WASStateData]` the UI keys on;
    /// callsigns arrive distinct-sorted (the drilldown view dedupes anyway).
    static func overlayRustWASData(
        into stats: inout ComputedStats,
        store: FieldStore
    ) async {
        guard let rows = try? await RustAnalyticsReadSource(store: store).wasDrilldown(query: "") else {
            return
        }
        var wasData: [WASFilterKey: WASStateData] = [:]
        for row in rows {
            let source: WASSource = row.source == "qth" ? .qthOnly : .all
            let key = WASFilterKey(source: source, mode: row.mode)
            var data = wasData[key] ?? WASStateData()
            data.stateCounts[row.state] = row.count
            data.stateCallsigns[row.state] = row.callsigns
            wasData[key] = data
        }
        stats.wasData = wasData
    }
}
