import CarrierWaveCore
import CarrierWaveData
import Foundation

/// Loads the grid tracker summary from cw-store (SQL GROUP BY) — the only
/// grid aggregation path since the SwiftData scan was removed (map port
/// phase A).
enum GridSummaryLoader {
    static func load() async throws -> GridTrackerSummary {
        let store = try await CwStoreProvider.shared.store()
        let tiles = try await RustAnalyticsReadSource(store: store)
            .gridTiles(query: "", precision: 4)

        var gridData: [String: GridSquareData] = [:]
        var fieldCounts: [String: Int] = [:]
        for tile in tiles {
            let status: GridSquareStatus = tile.confirmed > 0
                ? .confirmed(count: tile.confirmed)
                : .worked(count: tile.count)
            gridData[tile.tile] = GridSquareData(
                grid: tile.tile,
                status: status,
                qsoCount: tile.count,
                confirmedCount: tile.confirmed,
                callsigns: tile.callsigns,
                bands: Set(tile.bands),
                modes: Set(tile.modes),
                mostRecent: tile.lastQSO > 0
                    ? Date(timeIntervalSince1970: TimeInterval(tile.lastQSO))
                    : nil
            )
            fieldCounts[String(tile.tile.prefix(2)), default: 0] += 1
        }
        return GridTrackerSummary(
            totalGridsWorked: gridData.count,
            totalGridsConfirmed: gridData.values.filter { $0.confirmedCount > 0 }.count,
            totalFields: fieldCounts.count,
            gridData: gridData,
            fieldCounts: fieldCounts
        )
    }
}
