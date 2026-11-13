import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + session item detail

/// Per-equipment-item QSO breakdown (totals, distance extremes, band/mode tallies), served
/// from cw-store's `session_item_detail`. `name` is the equipment item's display name,
/// matched against each session's rig / antenna / key / mic.
public extension RustAnalyticsReadSource {
    func sessionItemDetail(name: String) async throws -> SessionItemDetailResult {
        let detail = try store.sessionItemDetail(name: name)
        return SessionItemDetailResult(
            totalQSOs: Int(detail.totalQsos),
            uniqueEntities: Int(detail.uniqueEntities),
            farthestKm: detail.farthestKm,
            shortestKm: detail.shortestKm,
            averageKm: detail.averageKm,
            bandBreakdown: detail.bandBreakdown.map { ItemTallyRow(name: $0.name, count: Int($0.count)) },
            modeBreakdown: detail.modeBreakdown.map { ItemTallyRow(name: $0.name, count: Int($0.count)) }
        )
    }
}
