import CarrierWaveData
import Foundation
import os

/// One-time data repairs that run on app launch.
///
/// Each repair is gated by a UserDefaults key so it only executes once.
/// Add new static methods for future repairs and call them from the app entry point.
enum DataRepairService {
    // MARK: Internal

    /// Run all pending one-time repairs.
    static func runPendingRepairs() {
        repairPOTASyncState()
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "DataRepair"
    )

    // MARK: - Feb 2026: Clear POTA sync state after schema rename

    /// After commit 76d285f renamed SwiftData stored properties, POTA sync state
    /// became stale. Clear checkpoint and sync state so the next sync does a
    /// full re-download, recovering QSOs that exist in POTA but not locally.
    private static func repairPOTASyncState() {
        let key = "dataRepair.potaSyncStateReset.v1"
        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }

        logger.info("Clearing POTA sync state to force full re-download")
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.potaDownloadProgress)
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.potaLastSyncDate)

        UserDefaults.standard.set(true, forKey: key)
        logger.info("POTA sync state cleared — next sync will re-download all activations")
    }
}
