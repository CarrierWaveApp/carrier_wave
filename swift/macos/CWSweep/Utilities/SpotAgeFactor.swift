import Foundation

// MARK: - SpotAgeFactor

/// Shared source-aware aging calculations for spots.
/// RBN spots age faster (transient), POTA/SOTA/WWFF age slower (activators hold freq).
enum SpotAgeFactor {
    /// Aging multiplier by spot source. Higher = ages faster.
    static func factor(for source: SpotSource) -> Double {
        switch source {
        case .rbn: 2.0
        case .cluster: 1.0
        case .pota,
             .sota,
             .wwff: 0.5
        case .dxSummit,
             .dxHeat,
             .dxWatch: 1.0
        }
    }

    /// Effective age in seconds, adjusted by source aging factor
    static func effectiveAge(for spot: EnrichedSpot) -> Double {
        let actual = Date().timeIntervalSince(spot.spot.timestamp)
        return actual * factor(for: spot.spot.source)
    }

    /// Opacity based on effective age relative to max age
    static func opacity(for spot: EnrichedSpot, maxAgeMinutes: Int) -> Double {
        let maxSeconds = Double(maxAgeMinutes) * 60
        return max(0.3, 1.0 - (effectiveAge(for: spot) / maxSeconds) * 0.7)
    }
}
