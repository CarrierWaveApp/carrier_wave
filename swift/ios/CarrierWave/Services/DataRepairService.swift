import CarrierWaveData
import Foundation
import OSLog
import SwiftData

/// One-time data repairs that run on app launch.
///
/// Each repair is gated by a UserDefaults key so it only executes once.
/// Add new static methods for future repairs and call them from the app entry point.
enum DataRepairService {
    // MARK: Internal

    /// Run all pending one-time repairs.
    static func runPendingRepairs() {
        StartupProfiler.shared.record("repair.potaSyncState.start")
        repairPOTASyncState()
        StartupProfiler.shared.record("repair.potaSyncState.done")
    }

    /// Run async repairs that need a ModelContainer (call from .task).
    static func runAsyncRepairs(container: ModelContainer) async {
        StartupProfiler.shared.record("repair.bandCase.start")
        await repairBandCase(container: container)
        StartupProfiler.shared.record("repair.bandCase.done")
        StartupProfiler.shared.record("repair.metadataUploadFlags.start")
        await repairMetadataUploadFlags(container: container)
        StartupProfiler.shared.record("repair.metadataUploadFlags.done")
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

    // MARK: - Mar 2026: Normalize band strings to lowercase

    /// QRZ import stored bands as uppercase (e.g. "20M") while ADIF import
    /// used lowercase ("20m"). Normalize all bands to lowercase so dedup keys,
    /// statistics, and display are consistent.
    private static func repairBandCase(container: ModelContainer) async {
        let key = "dataRepair.bandCaseNormalize.v1"
        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }

        logger.info("Normalizing band strings to lowercase")
        do {
            let result = try await BatchedRewrite<QSO>(
                label: "bandCase.normalize",
                container: container
            ) { qso, _ in
                let lowered = qso.band.lowercased()
                guard lowered != qso.band else {
                    return false
                }
                qso.band = lowered
                return true
            }.run()

            logger.info("Band case repair complete: \(result.mutated) QSOs normalized")
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            logger.error("Band case repair failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sep 2026: Clear upload flags on PoLo metadata rows (CAR-278)

    /// PoLo marker rows (`QSOMode.metadataModes`) imported via LoFi
    /// sync, orphan repair or QRZ dead-state repair were armed with
    /// `needsUpload=true` and sat in "pending upload" forever. The sync path now
    /// skips them; this clears the rows that already exist. Keyed `.v1` for the
    /// widened `QSOMode.metadataModes` (the to-do, timer and break markers were missed).
    private static func repairMetadataUploadFlags(container: ModelContainer) async {
        let key = "dataRepair.metadataUploadFlags.v1"
        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }

        logger.info("Clearing upload flags on PoLo metadata rows")
        do {
            let result = try await MetadataUploadFlagRepairService(container: container).repair()
            let breakdown = result.byService
                .sorted { $0.value > $1.value }
                .map { "\($0.key.rawValue)=\($0.value)" }
                .joined(separator: ", ")
            logger.info(
                "Metadata upload flag repair complete: \(result.clearedCount) cleared [\(breakdown)]"
            )
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            logger.error("Metadata upload flag repair failed: \(error.localizedDescription)")
        }
    }
}
