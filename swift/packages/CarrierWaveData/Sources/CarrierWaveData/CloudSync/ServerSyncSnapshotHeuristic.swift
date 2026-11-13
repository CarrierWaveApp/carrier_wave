import Foundation

// MARK: - ServerSyncSnapshotHeuristic

/// Phase 7.4 snapshot cadence for the E2E sync server: on session end and app
/// background, a device should build + POST an encrypted snapshot once enough
/// journal entries have accumulated since the last one. The threshold is
/// proportional to log size with a floor, so small logs snapshot after a fixed
/// number of entries and large logs don't thrash.
///
/// The constant lives here — in one place — per the sync-server plan.
public enum ServerSyncSnapshotHeuristic {
    /// Absolute floor: never snapshot for fewer than this many entries.
    public static let minimumEntries = 30

    /// Proportional component: snapshot after this fraction of the total log
    /// has accumulated as journal entries.
    public static let logFraction = 0.2

    /// `entries_since_snapshot >= max(30, total_log * 0.2)`.
    public static func isDue(entriesSinceSnapshot: Int, totalLogSize: Int) -> Bool {
        guard entriesSinceSnapshot > 0 else {
            return false
        }
        let threshold = max(
            Double(minimumEntries),
            Double(totalLogSize) * logFraction
        )
        return Double(entriesSinceSnapshot) >= threshold
    }
}
