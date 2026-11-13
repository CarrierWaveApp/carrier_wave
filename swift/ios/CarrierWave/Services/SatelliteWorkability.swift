import UIKit

// MARK: - SatelliteWorkability

/// UI-side pass-quality thresholds. The actual workability gates (derelict
/// list, AMSAT 7-day silence, per-capability transmitter filtering) live in
/// the shared Rust engine (`cw-domain/src/satellite/workability.rs`), which
/// applies them before satellites ever reach the catalog — these constants
/// mirror the engine's values for pass-list labels and filters only.
nonisolated enum SatelliteWorkability {
    /// One persisted switch governs the workable-pass filter on every pass
    /// list (upcoming, per-satellite, mutual planner).
    static let workablePassFilterKey = "satelliteWorkablePassesOnly"

    /// A pass is "workable" when it peaks at or above this elevation.
    static let minWorkablePassElevationDeg = 10.0

    /// Recommended handheld-yagi threshold (community heuristic: ≥20–30°
    /// peak for handheld work). Passes between the 10° floor and this are
    /// labeled "marginal" and excluded from pass alerts by default.
    static let recommendedPassElevationDeg = 20.0

    /// True for a 10–20° pass: above the floor, below the recommendation.
    static func isMarginal(peakElevationDeg: Double) -> Bool {
        peakElevationDeg >= minWorkablePassElevationDeg
            && peakElevationDeg < recommendedPassElevationDeg
    }
}
