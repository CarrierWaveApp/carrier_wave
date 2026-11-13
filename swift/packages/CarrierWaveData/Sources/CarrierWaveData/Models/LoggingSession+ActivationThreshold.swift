import Foundation
import SwiftData

public extension LoggingSession {
    /// Minimum QSO count for this session to qualify as a valid activation,
    /// based on the active programs. POTA=10, SOTA=4, WWFF=44. For dual-program
    /// sessions returns the smallest threshold (you "qualify" as soon as the
    /// least-strict program is met). Returns nil for casual sessions or
    /// programs without an activation threshold.
    ///
    /// Mirrors the static defaults in `ActivityProgramStore.bundledPrograms`
    /// so models in CarrierWaveData stay self-contained — the store remains
    /// the dynamic / server-overridable source of truth on iOS.
    var activationThreshold: Int? {
        programs.compactMap { Self.activationThresholdsBySlug[$0] }.min()
    }

    private static let activationThresholdsBySlug: [String: Int] = [
        "pota": 10,
        "sota": 4,
        "wwff": 44,
    ]
}
