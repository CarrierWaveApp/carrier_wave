import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + brag session stats

/// The session-/sequence-based brag-sheet stats (operating hours, fastest-10, best session
/// rate, fastest activation, longest session, peak 15-min rate, largest Nfer), served from
/// cw-store's `brag_session_stats`. `query` is the optional `.cwquery` DSL filter (the period).
public extension RustAnalyticsReadSource {
    func bragSessionStats(query: String, start: Int? = nil, end: Int? = nil) async throws -> BragSessionStatsResult {
        let stats = try store.bragSessionStats(query: query, start: start.map(Int64.init), end: end.map(Int64.init))
        return BragSessionStatsResult(
            operatingSeconds: stats.operatingSeconds,
            fastestTenSeconds: stats.fastestTenSeconds,
            bestSessionRate: stats.bestSessionRate,
            fastestActivationSeconds: stats.fastestActivationSeconds,
            longestSessionSeconds: stats.longestSessionSeconds,
            peak15MinCount: Int(stats.peak15MinCount),
            largestNfer: Int(stats.largestNfer)
        )
    }
}
