import CarrierWaveCore
import Foundation

// MARK: - ServerSnapshotCoordinator

/// Phase 7.4 host side of the E2E server snapshot cadence: tracks how many
/// journal entries this device has pushed since the last snapshot (per base
/// URL, like the sync cursor) and, on session end + app background, decides
/// via `ServerSyncSnapshotHeuristic` whether a snapshot is due.
///
/// FFI GAP: cw-ffi exposes no call to build + POST an encrypted server
/// snapshot (only `sync_run_once` / push / pull and the key escrow). When one
/// lands, `snapshotIfDue` should drive it off-main and reset the counter on
/// success. Until then a due snapshot is recorded in the sync log so the
/// cadence logic is verifiable on-device.
@MainActor
public enum ServerSnapshotCoordinator {
    // MARK: Public

    /// Accumulate pushed-entry counts from completed sync passes.
    nonisolated public static func recordPushed(_ count: Int, base: String) {
        guard count > 0 else {
            return
        }
        let key = counterKey(base: base)
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: key) + count, forKey: key)
    }

    nonisolated public static func entriesSinceSnapshot(base: String) -> Int {
        UserDefaults.standard.integer(forKey: counterKey(base: base))
    }

    /// Check the cadence heuristic and (once the FFI exists) upload a
    /// snapshot. Called on session end and when the app backgrounds; gated on
    /// sync enrollment for the active server.
    public static func snapshotIfDue(trigger: String) async {
        guard SyncKeyService.isEnrolledForActiveServer else {
            return
        }
        let base = ActivitiesServer.resolvedBaseURL
        let entries = entriesSinceSnapshot(base: base)
        guard entries >= ServerSyncSnapshotHeuristic.minimumEntries else {
            return
        }
        do {
            let store = try await CwStoreProvider.shared.store()
            let total = try await qsoCountOffMain(store: store)
            guard ServerSyncSnapshotHeuristic.isDue(
                entriesSinceSnapshot: entries, totalLogSize: Int(total)
            ) else {
                return
            }
            // FFI gap (see type doc): nothing to upload with yet. Log so the
            // heuristic is observable; the counter is left intact so the
            // snapshot fires on the first pass after the FFI lands.
            ServerSyncLog.info(
                "Server snapshot due (\(trigger)): \(entries) entries since last snapshot, "
                    + "log size \(total) — deferred, cw-ffi has no snapshot export yet"
            )
        } catch {
            ServerSyncLog.error("Server snapshot check (\(trigger)) failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    nonisolated private static func counterKey(base: String) -> String {
        "syncEntriesSinceSnapshot.\(base)"
    }

    /// cw-store count off the main actor (FFI SQLite read).
    nonisolated private static func qsoCountOffMain(store: FieldStore) async throws -> Int64 {
        try await Task.detached(priority: .utility) {
            try store.qsoCount()
        }.value
    }
}
