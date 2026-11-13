import Foundation

// MARK: - BragSessionStatsResult

/// The session-/sequence-based brag-sheet stats (mirrors cw-store `BragSessionStats` /
/// `BragSheetComputationActor`'s speed-and-rate, operating-hours, longest-session, and
/// largest-Nfer stats). Durations are seconds; `peak15MinCount` / `largestNfer` are 0 over no
/// data (and `largestNfer` ≤ 1 → `.noData` view-side).
public struct BragSessionStatsResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        operatingSeconds: Double?,
        fastestTenSeconds: Double?,
        bestSessionRate: Double?,
        fastestActivationSeconds: Double?,
        longestSessionSeconds: Double?,
        peak15MinCount: Int,
        largestNfer: Int
    ) {
        self.operatingSeconds = operatingSeconds
        self.fastestTenSeconds = fastestTenSeconds
        self.bestSessionRate = bestSessionRate
        self.fastestActivationSeconds = fastestActivationSeconds
        self.longestSessionSeconds = longestSessionSeconds
        self.peak15MinCount = peak15MinCount
        self.largestNfer = largestNfer
    }

    // MARK: Public

    public let operatingSeconds: Double?
    public let fastestTenSeconds: Double?
    public let bestSessionRate: Double?
    public let fastestActivationSeconds: Double?
    public let longestSessionSeconds: Double?
    public let peak15MinCount: Int
    public let largestNfer: Int
}
