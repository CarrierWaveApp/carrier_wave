import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + brag streaks

/// Streak-shaped brag-sheet stats (on-air / activation / per-mode day streaks), served from
/// cw-store's `brag_streaks`. `query` is the optional `.cwquery` DSL filter; `today` is the
/// reference UTC calendar day (`YYYY-MM-DD`) the caller derives from the current date.
public extension RustAnalyticsReadSource {
    func bragStreaks(
        query: String,
        today: String,
        start: Int? = nil,
        end: Int? = nil
    ) async throws -> BragStreaksResult {
        let streaks = try store.bragStreaks(
            query: query,
            today: today,
            start: start.map(Int64.init),
            end: end.map(Int64.init)
        )
        return BragStreaksResult(
            onAir: Self.streak(streaks.onAir),
            activation: streaks.activation.map(Self.streak),
            modes: streaks.modes
                .map { ModeStreakRow(mode: $0.mode, current: Int($0.current), longest: Int($0.longest)) }
        )
    }

    private static func streak(_ ffi: FfiStreakValue) -> StreakValueRow {
        StreakValueRow(current: Int(ffi.current), longest: Int(ffi.longest))
    }
}
