import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SyncService Helpers

extension SyncService {
    /// Download from all sources without uploading (debug mode)
    func downloadOnly() async throws -> SyncResult {
        isSyncing = true
        syncProgress.reset()
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting download-only sync")

        defer {
            isSyncing = false
            syncPhase = nil
            syncProgress.reset()
            lastSyncDate = Date()
            debugLog.info("Download-only sync complete")
        }

        var result = SyncResult(
            downloaded: [:], uploaded: [:], errors: [], newQSOs: 0, mergedQSOs: 0,
            potaMaintenanceSkipped: false
        )

        // PHASE 1: Download from all sources in parallel
        let downloadResults = await downloadFromAllSources()

        var allFetched: [FetchedQSO] = []
        for (service, fetchResult) in downloadResults {
            switch fetchResult {
            case let .success(qsos):
                result.downloaded[service] = qsos.count
                // Note: syncProgress is updated in downloadFrom* methods for real-time updates
                allFetched.append(contentsOf: qsos)
            case let .failure(error):
                result.errors.append(
                    "\(service.displayName) download: \(error.localizedDescription)"
                )
            }
        }

        // PHASE 2: Process and deduplicate (on background thread)
        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(allFetched)
        result.newQSOs = processResult.created
        result.mergedQSOs = processResult.merged

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        // Skip upload phase
        return result
    }

    func collectDownloadResults(
        _ downloadResults: [ServiceType: Result<[FetchedQSO], Error>],
        into result: inout SyncResult
    ) -> [FetchedQSO] {
        var allFetched: [FetchedQSO] = []
        for (service, fetchResult) in downloadResults {
            switch fetchResult {
            case let .success(qsos):
                result.downloaded[service] = qsos.count
                // Note: syncProgress is updated in downloadFrom* methods for real-time updates
                allFetched.append(contentsOf: qsos)
            case let .failure(error):
                result.errors.append(
                    "\(service.displayName) download: \(error.localizedDescription)"
                )
            }
        }
        return allFetched
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

        // Clear upload flags on hidden (soft-deleted) QSOs
        await clearHiddenQSOUploadFlagsAsync()

        // Clear upload flags on metadata pseudo-modes (WEATHER, SOLAR, NOTE)
        await clearMetadataUploadFlagsAsync()

        // Clear upload flags on QSOs from non-primary callsigns
        await clearNonPrimaryCallsignUploadFlagsAsync()

        // Repair missing DXCC from rawADIF
        await repairMissingDXCCAsync()

        // Refresh main context to pick up changes from background actor
        modelContext.rollback()
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

        // Common repair and refresh
        await performDataRepairs()

        return (qrzResetCount, potaReconcileResult)
    }

    func performUploadsIfEnabled(
        into result: inout SyncResult,
        debugLog: SyncDebugLog
    ) async {
        if isReadOnlyMode {
            debugLog.info("Read-only mode enabled, skipping uploads")
            return
        }

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
}
