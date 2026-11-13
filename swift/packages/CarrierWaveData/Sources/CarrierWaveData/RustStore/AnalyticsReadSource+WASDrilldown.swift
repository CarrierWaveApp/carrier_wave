import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + WAS drilldown

/// WAS drilldown (per source × mode × state → count + distinct callsigns), served
/// from cw-store's `was_drilldown`. `query` is the optional `.cwquery` DSL filter.
public extension RustAnalyticsReadSource {
    func wasDrilldown(query: String) async throws -> [WASDrilldownRow] {
        try store.wasDrilldown(query: query).map {
            WASDrilldownRow(
                source: $0.source,
                mode: $0.mode,
                state: $0.state,
                count: Int($0.count),
                callsigns: $0.callsigns
            )
        }
    }
}
