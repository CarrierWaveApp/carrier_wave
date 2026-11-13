import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Callsign Sync

extension SyncService {
    /// Check QRZ STATUS for a callsign change on the primary mapping and propagate.
    /// Runs at the start of each QRZ sync so the user's callsign stays current.
    func syncCallsignFromQRZ() async {
        guard let primary = qrzClient.getPrimaryMapping() else {
            SyncDebugLog.shared.debug(
                "Callsign sync skipped: no primary QRZ mapping",
                service: .qrz
            )
            return
        }

        do {
            let status = try await qrzClient.validateApiKey(primary.apiKey)

            // Update stored QRZ callsign and primary mapping
            try qrzClient.saveCallsign(status.callsign)
            if let bookId = status.bookId {
                try qrzClient.saveBookId(bookId, for: status.callsign)
            }
            try qrzClient.updatePrimaryCallsign(status.callsign, bookId: status.bookId)

            // Propagate to alias service, profile, and UserDefaults. This is a
            // *detected* callsign: a key still bound to a callsign the user
            // retired must not flip the profile back on every sync (CAR-349).
            let profileService = UserProfileService.shared
            if let oldCallsign = try profileService.applyDetectedCallsignChangeIfNeeded(
                newCallsign: status.callsign
            ) {
                SyncDebugLog.shared.info(
                    "Callsign changed: \(oldCallsign) → \(status.callsign)",
                    service: .qrz
                )
            }
        } catch {
            // Non-fatal — sync can proceed with existing callsign
            SyncDebugLog.shared.warning(
                "Callsign sync check failed: \(error.localizedDescription)",
                service: .qrz
            )
        }
    }
}

// MARK: - SyncService Helpers

extension SyncService {
    func collectDownloadResults(
        _ downloadResults: [ServiceType: Result<[FetchedQSO], Error>],
        into result: inout SyncResult
    ) -> [FetchedQSO] {
        let store = UploadDiagnosticStore.shared
        var allFetched: [FetchedQSO] = []
        for (service, fetchResult) in downloadResults {
            switch fetchResult {
            case let .success(qsos):
                result.downloaded[service] = qsos.count
                // Note: syncProgress is updated in downloadFrom* methods for real-time updates
                allFetched.append(contentsOf: qsos)
                store.clearForService(service)
            case let .failure(error):
                result.errors.append(
                    "\(service.displayName) download: \(error.localizedDescription)"
                )
                let diagnostic = UploadErrorClassifier.classify(
                    error: error, service: service, affectedCount: 0
                )
                store.record(diagnostic)
            }
        }
        // Warn about non-ADIF-compliant values in downloaded QSOs
        warnAboutNonCompliantADIF(allFetched)

        return allFetched
    }

    /// Log warnings for downloaded QSOs with non-ADIF-compliant mode or band values.
    /// These may fail on strict services like POTA even though QRZ accepts them.
    private func warnAboutNonCompliantADIF(_ qsos: [FetchedQSO]) {
        var badModes: [(String, String)] = [] // (callsign, mode)
        var badBands: [(String, String)] = [] // (callsign, band)
        for qso in qsos {
            let normalized = ModeEquivalence.normalizeForStrictADIF(qso.mode)
            if ADIFFieldValidator.validateMode(normalized.mode) != nil {
                badModes.append((qso.callsign, qso.mode))
            }
            if ADIFFieldValidator.validateBand(qso.band) != nil {
                badBands.append((qso.callsign, qso.band))
            }
        }
        if !badModes.isEmpty {
            let samples = badModes.prefix(5)
                .map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
            let more = badModes.count > 5 ? " (+\(badModes.count - 5) more)" : ""
            SyncDebugLog.shared.warning(
                "Imported \(badModes.count) QSO(s) with non-ADIF mode — "
                    + "may fail on POTA: \(samples)\(more)",
                service: .pota
            )
        }
        if !badBands.isEmpty {
            let samples = badBands.prefix(5)
                .map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
            let more = badBands.count > 5 ? " (+\(badBands.count - 5) more)" : ""
            SyncDebugLog.shared.warning(
                "Imported \(badBands.count) QSO(s) with non-ADIF band — "
                    + "may fail on POTA: \(samples)\(more)",
                service: .pota
            )
        }
    }

    func notifyNewQSOsIfNeeded(count: Int) {
        guard count > 0 else {
            return
        }
        NotificationCenter.default.post(
            name: .didSyncQSOs,
            object: nil,
            userInfo: ["newQSOCount": count]
        )
    }

    /// Check if a large import should be cancelled. Returns true if user declines.
    func shouldCancelLargeImport(
        _ allFetched: [FetchedQSO], downloaded: [ServiceType: Int]
    ) async -> Bool {
        let debugLog = SyncDebugLog.shared
        guard allFetched.count >= SyncImportConfirmation.threshold else {
            return false
        }
        let netNew = await countNetNewQSOs(allFetched)
        guard netNew >= SyncImportConfirmation.threshold else {
            debugLog.info(
                "Skipping import confirmation: \(allFetched.count) downloaded, \(netNew) net-new"
            )
            return false
        }
        let shouldProceed = await requestImportConfirmation(
            downloadedByService: downloaded, netNewCount: netNew
        )
        if !shouldProceed {
            debugLog.info(
                "User cancelled sync (\(netNew) net-new of \(allFetched.count) QSOs)"
            )
        }
        return !shouldProceed
    }

    /// Pause sync and ask user to confirm importing a large batch of QSOs.
    /// Returns true if user confirms, false if cancelled.
    func requestImportConfirmation(
        downloadedByService: [ServiceType: Int],
        netNewCount: Int
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            importConfirmation = SyncImportConfirmation(
                downloadedByService: downloadedByService,
                netNewCount: netNewCount,
                continuation: continuation
            )
        }
    }

    /// Called by UI to resolve the pending import confirmation.
    func resolveImportConfirmation(proceed: Bool) {
        guard let confirmation = importConfirmation else {
            return
        }
        importConfirmation = nil
        confirmation.continuation.resume(returning: proceed)
    }

    /// Pause sync and ask user to confirm uploading a large batch of QSOs.
    /// Returns true if user confirms, false if cancelled.
    func requestExportConfirmation(
        uploadByService: [ServiceType: Int]
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            exportConfirmation = SyncExportConfirmation(
                uploadByService: uploadByService,
                continuation: continuation
            )
        }
    }

    /// Called by UI to resolve the pending export confirmation.
    func resolveExportConfirmation(proceed: Bool) {
        guard let confirmation = exportConfirmation else {
            return
        }
        exportConfirmation = nil
        confirmation.continuation.resume(returning: proceed)
    }

    /// Repair orphaned QSOs, clear invalid upload flags, and refresh context.
    /// Common post-processing step for both full and single-service syncs.
    func performDataRepairs() async {
        // Repair orphaned QSOs (logged when services weren't configured)
        if qrzClient.hasApiKey() {
            await repairOrphanedQSOsAsync(for: .qrz)
        }

        // Clear bogus HAMRS upload flags (HAMRS doesn't support uploads)
        await clearBogusHamrsUploadFlagsAsync()

        // Repair QRZ dead-state QSOs (isPresent=false, needsUpload=false)
        await repairQRZDeadStateAsync()

        // POTA dead-state recovery is handled by remote map gap repair (repairPOTAGapsAsync)

        // Clear upload flags on hidden (soft-deleted) QSOs
        await clearHiddenQSOUploadFlagsAsync()

        // Clear upload flags on PoLo metadata pseudo-modes (QSOMode.metadataModes, CAR-278)
        await clearMetadataUploadFlagsAsync()

        // Clear upload flags on QSOs from non-primary callsigns
        await clearNonPrimaryCallsignUploadFlagsAsync()

        // Clear upload flags for services that aren't configured
        await clearUnconfiguredServiceUploadFlagsAsync()

        // Repair missing DXCC from rawADIF
        await repairMissingDXCCAsync()

        // Repair callsigns with leading/trailing whitespace (and merge resulting dupes)
        await repairCallsignWhitespaceAsync()

        // Repair QRZ records stuck in isSubmitted state (should be isPresent)
        await repairQRZSubmittedStateAsync()

        // Group orphan POTA QSOs into sessions
        await groupOrphanPOTAQSOsAsync()

        // One-time: merge duplicate QSOs sharing the same qrzLogId (CAR-179)
        await repairDuplicateQRZLogIdsAsync()

        // One-time: force full QRZ download to reconcile QSOs stuck from batch upload bug
        await repairQRZPerQSOUpload()

        // One-time: force full POTA re-download to capture activation metadata for sessions
        await forcePOTAResyncForSessionMigration()

        // Refresh main context to pick up changes from background actor
        modelContext.rollback()
    }

    /// One-time migration: force full POTA re-download so activation metadata
    /// is captured and sessions are created for existing activations.
    private func forcePOTAResyncForSessionMigration() async {
        let key = "potaSessionMigrationResyncV1"
        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }

        guard potaAuthService.isConfigured else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        potaClient.clearSyncState()
        potaClient.clearDownloadCheckpoint()

        SyncDebugLog.shared.info(
            "POTA session migration: cleared sync state to force full "
                + "re-download (sessions will be created from activation metadata)",
            service: .pota
        )

        UserDefaults.standard.set(true, forKey: key)
    }

    /// One-time migration: clear QRZ lastDownloadDate to force full download.
    /// The old batch upload sent all QSOs in one request but QRZ only processed
    /// the last one, leaving QSOs stuck as isPresent=true but never actually uploaded.
    /// A full download triggers reconciliation which resets needsUpload for missing QSOs.
    private func repairQRZPerQSOUpload() async {
        let key = "qrzPerQSOUploadRepairV1"
        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }

        guard qrzClient.hasApiKey() else {
            // No QRZ configured, nothing to repair
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        qrzClient.clearLastDownloadDate()

        await MainActor.run {
            SyncDebugLog.shared.info(
                "QRZ per-QSO upload repair: cleared lastDownloadDate to force "
                    + "full download on next sync (reconciliation will flag "
                    + "missing QSOs for re-upload)",
                service: .qrz
            )
        }

        UserDefaults.standard.set(true, forKey: key)
    }

    /// Reconcile service presence and repair data after processing.
    /// Returns QRZ reset count and POTA reconcile result for report building.
    func performReconciliation(
        allFetched: [FetchedQSO],
        qrzWasIncremental: Bool
    ) async throws -> (Int, QSOProcessingActor.POTAReconcileResult?) {
        // Reconcile QRZ presence (full sync only — incremental is incomplete)
        var qrzResetCount = 0
        if !qrzWasIncremental {
            let qrzDownloadedKeys = Set(
                allFetched.filter { $0.source == .qrz }.map(\.deduplicationKey)
            )
            if !qrzDownloadedKeys.isEmpty {
                qrzResetCount = try await reconcileQRZPresenceAsync(
                    downloadedKeys: qrzDownloadedKeys
                )
            }
        }

        // Reconcile POTA presence against job log
        let potaReconcileResult = await reconcilePOTAPresenceAsync()

        // POTA QSO-level gap repair: compare local QSOs against remote per-activation data
        if let remoteMap = potaRemoteQSOMap, !remoteMap.isEmpty {
            await repairPOTAGapsAsync(remoteQSOMap: remoteMap)
        }

        // Common repair and refresh
        await performDataRepairs()

        return (qrzResetCount, potaReconcileResult)
    }

    func performUploadsIfEnabled(
        into result: inout SyncResult,
        debugLog: SyncDebugLog
    ) async {
        let (uploadResults, potaSkipped) = await uploadToAllDestinations()
        result.potaMaintenanceSkipped = potaSkipped

        if potaSkipped {
            debugLog.info("POTA skipped due to maintenance window (0000-0400 UTC)", service: .pota)
        }

        for (service, uploadResult) in uploadResults {
            switch uploadResult {
            case let .success(count):
                result.uploaded[service] = count
            case let .failure(error):
                result.errors.append(
                    "\(service.displayName) upload: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Apply QRZ confirmation status from log IDs to existing QSOs.
    /// First matches by qrzLogId (fast), then fetches ADIF for unmatched
    /// confirmed IDs and processes them through the normal merge pipeline
    /// (handles QSOs uploaded before the LOGID capture fix).
    func applyQRZConfirmations(logIds: Set<String>) async throws {
        let debugLog = SyncDebugLog.shared
        let result = try await SyncService.processingActor.applyQRZConfirmations(
            logIds: logIds, container: modelContext.container
        )
        if result.confirmed > 0 {
            debugLog.info(
                "Marked \(result.confirmed) QSOs as QRZ-confirmed from log IDs",
                service: .qrz
            )
        }
        lastQRZQslsApplied += result.confirmed

        // Backfill: fetch ADIF for confirmed IDs that couldn't be matched
        // by qrzLogId (QSOs uploaded before the LOGID capture fix)
        let unmatchedIds = logIds.subtracting(result.matchedLogIds)
        let alreadyConfirmedCount = try await countAlreadyConfirmedLogIds(
            unmatchedIds
        )
        let needsBackfill = unmatchedIds.count - alreadyConfirmedCount
        if needsBackfill > 0 {
            debugLog.info(
                "\(needsBackfill) confirmed IDs unmatched — fetching ADIF "
                    + "for backfill",
                service: .qrz
            )
            let fetched = try await qrzClient.fetchQSOsByLogIds(
                Array(unmatchedIds)
            )
            if !fetched.isEmpty {
                let fetchedQSOs = fetched.map { FetchedQSO.fromQRZ($0) }
                let processResult = try await processDownloadedQSOsAsync(
                    fetchedQSOs
                )
                lastQRZQslsApplied += processResult.merged
                debugLog.info(
                    "Backfill: \(processResult.merged) merged, "
                        + "\(processResult.created) created",
                    service: .qrz
                )
            }
        }
    }

    /// Count how many of the given log IDs are already confirmed locally
    private func countAlreadyConfirmedLogIds(
        _ logIds: Set<String>
    ) async throws -> Int {
        try await SyncService.processingActor.countConfirmedLogIds(
            logIds, container: modelContext.container
        )
    }

    // MARK: - Periodic QRZ Reconciliation

    /// Number of incremental syncs between forced full QRZ downloads.
    /// Full downloads trigger reconciliation which corrects stale isPresent flags.
    private static let qrzReconcileInterval = 20
    private static let qrzSyncCountKey = "qrzIncrementalSyncCount"

    /// Force a full QRZ download if enough incremental syncs have elapsed.
    /// Clears the last download date so the next download fetches everything,
    /// which triggers reconciliation in performReconciliation().
    func forceFullQRZDownloadIfDue() {
        guard qrzClient.hasApiKey(),
              qrzClient.getLastDownloadDate() != nil
        else {
            return
        }

        let count = UserDefaults.standard.integer(
            forKey: Self.qrzSyncCountKey
        )
        if count >= Self.qrzReconcileInterval {
            qrzClient.clearLastDownloadDate()
            UserDefaults.standard.set(0, forKey: Self.qrzSyncCountKey)
            SyncDebugLog.shared.info(
                "Periodic QRZ reconciliation: forcing full download "
                    + "(after \(count) incremental syncs)",
                service: .qrz
            )
        } else {
            UserDefaults.standard.set(
                count + 1, forKey: Self.qrzSyncCountKey
            )
        }
    }
}
