import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - Single Service Sync (for UI buttons)

extension SyncService {
    /// Sync only with QRZ (download then upload)
    /// - Parameter forceFullSync: If true, ignores last sync date and downloads all QSOs
    func syncQRZ(forceFullSync: Bool = false) async throws -> QRZSyncResult {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
        }

        var downloaded = 0
        var uploaded = 0
        var skipped = 0
        // Use incremental sync unless forced full
        let lastDownload = forceFullSync ? nil : qrzClient.getLastDownloadDate()
        let syncStartTime = Date()

        // Download with timeout
        syncPhase = .downloading(service: .qrz)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
            try await self.qrzClient.fetchQSOs(since: lastDownload)
        }
        let fetched = qsos.map { FetchedQSO.fromQRZ($0) }

        // Save sync timestamp on success
        qrzClient.saveLastDownloadDate(syncStartTime)

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        downloaded = processResult.created

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        // Only reconcile on full sync - incremental sync doesn't have complete picture
        if forceFullSync || lastDownload == nil {
            let qrzDownloadedKeys = Set(fetched.map(\.deduplicationKey))
            try await reconcileQRZPresenceAsync(downloadedKeys: qrzDownloadedKeys)
        }

        await performDataRepairs()

        // Upload with timeout (unless read-only mode)
        if !isReadOnlyMode {
            syncPhase = .uploading(service: .qrz)
            let qsosToUpload = try fetchQSOsNeedingUpload().filter { $0.needsUpload(to: .qrz) }
            let uploadResult = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
                try await self.uploadToQRZ(qsos: qsosToUpload)
            }
            uploaded = uploadResult.uploaded
            skipped = uploadResult.skipped
            if modelContext.hasChanges {
                try modelContext.save()
            }
        }

        let qrzResult = QRZSyncResult(downloaded: downloaded, uploaded: uploaded, skipped: skipped)

        storeReport(buildReport(
            service: .qrz,
            downloaded: fetched.count,
            created: downloaded,
            merged: processResult.merged,
            uploaded: uploaded
        ))

        return qrzResult
    }

    /// Sync only with POTA (download then upload)
    func syncPOTA() async throws -> (downloaded: Int, uploaded: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
        }

        // Check maintenance window
        if POTAClient.isInMaintenanceWindow() {
            throw POTAError.maintenanceWindow
        }

        var downloaded = 0
        var uploaded = 0

        // Download with timeout
        syncPhase = .downloading(service: .pota)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .pota) {
            try await self.potaClient.fetchAllQSOs()
        }
        let fetched = qsos.map { FetchedQSO.fromPOTA($0) }

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        downloaded = processResult.created

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        // Reconcile POTA presence against job log
        let potaReconcileResult = await reconcilePOTAPresenceAsync()

        // Refresh main context to pick up changes from background actor
        modelContext.rollback()

        // Upload with timeout (unless read-only mode)
        if !isReadOnlyMode {
            syncPhase = .uploading(service: .pota)
            let qsosToUpload = try fetchQSOsNeedingUpload().filter {
                $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
            }
            uploaded = try await withTimeout(seconds: syncTimeoutSeconds, service: .pota) {
                try await self.uploadToPOTA(qsos: qsosToUpload)
            }
            if modelContext.hasChanges {
                try modelContext.save()
            }
        }

        storeReport(buildReport(
            service: .pota,
            downloaded: fetched.count,
            created: downloaded,
            merged: processResult.merged,
            uploaded: uploaded,
            reconciliation: reconciliationReport(potaResult: potaReconcileResult)
        ))

        return (downloaded, uploaded)
    }

    /// Sync only with LoFi (download only)
    func syncLoFi() async throws -> Int {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting LoFi-only sync", service: .lofi)
        isSyncing = true
        syncProgress.reset()
        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
        }

        // Download with timeout and progress tracking
        syncPhase = .downloading(service: .lofi)
        let downloadResult = try await withTimeout(seconds: syncTimeoutSeconds, service: .lofi) {
            try await self.lofiClient.fetchAllQsosSinceLastSync { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    var updated = syncProgress
                    updated.lofiTotalQSOs = progress.totalQSOs
                    updated.lofiTotalOperations = progress.totalOperations
                    updated.lofiDownloadedQSOs = progress.downloadedQSOs
                    syncProgress = updated
                }
            }
        }
        let qsos = downloadResult.qsos
        debugLog.info(
            "Fetched \(downloadResult.rawFetchCount) raw QSOs (\(qsos.count) after dedup)",
            service: .lofi
        )
        let fetched = qsos.compactMap { FetchedQSO.fromLoFi($0.0, operation: $0.1) }
        debugLog.info("After filtering: \(fetched.count) valid QSOs", service: .lofi)

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        let skippedCount = qsos.count - fetched.count
        storeReport(buildReport(
            service: .lofi,
            downloaded: qsos.count,
            skipped: skippedCount,
            created: processResult.created,
            merged: processResult.merged
        ))

        return processResult.created
    }

    /// Sync only with HAMRS (download only)
    func syncHAMRS() async throws -> Int {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
        }

        // Download with timeout
        syncPhase = .downloading(service: .hamrs)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .hamrs) {
            try await self.hamrsClient.fetchAllQSOs()
        }
        let fetched = qsos.compactMap { FetchedQSO.fromHAMRS($0.0, logbook: $0.1) }

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        let skippedCount = qsos.count - fetched.count
        storeReport(buildReport(
            service: .hamrs,
            downloaded: qsos.count,
            skipped: skippedCount,
            created: processResult.created,
            merged: processResult.merged
        ))

        return processResult.created
    }

    /// Sync only with LoTW (download only)
    func syncLoTW() async throws -> Int {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
        }

        syncPhase = .downloading(service: .lotw)
        let rxSince = lotwClient.getLastQSORxDate()
        let response = try await withTimeout(seconds: syncTimeoutSeconds, service: .lotw) {
            try await self.lotwClient.fetchQSOs(qsoRxSince: rxSince)
        }
        let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        // Save timestamp for incremental sync
        if let lastQSORx = response.lastQSORx {
            try lotwClient.saveLastQSORxDate(lastQSORx)
        }

        storeReport(buildReport(
            service: .lotw,
            downloaded: fetched.count,
            created: processResult.created,
            merged: processResult.merged
        ))

        return processResult.created
    }

    /// Sync only with Club Log (download then upload)
    func syncClubLog(forceFullSync: Bool = false) async throws -> (downloaded: Int, uploaded: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
        }

        var downloaded = 0
        var uploaded = 0

        // Use incremental sync unless forced full
        let lastDownload = forceFullSync ? nil : clublogClient.getLastDownloadDate()
        let syncStartTime = Date()

        // Download with timeout
        syncPhase = .downloading(service: .clublog)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .clublog) {
            try await self.clublogClient.fetchQSOs(since: lastDownload)
        }
        let fetched = qsos.map { FetchedQSO.fromClubLog($0) }

        // Save sync timestamp on success
        clublogClient.saveLastDownloadDate(syncStartTime)

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        downloaded = processResult.created

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        await performDataRepairs()

        // Upload with timeout (unless read-only mode)
        if !isReadOnlyMode {
            syncPhase = .uploading(service: .clublog)
            let qsosToUpload = try fetchQSOsNeedingUpload()
                .filter { $0.needsUpload(to: .clublog) }
            if !qsosToUpload.isEmpty {
                let uploadResult = try await withTimeout(
                    seconds: syncTimeoutSeconds, service: .clublog
                ) {
                    try await self.uploadToClubLog(qsos: qsosToUpload)
                }
                uploaded = uploadResult.uploaded
                if modelContext.hasChanges {
                    try modelContext.save()
                }
            }
        }

        storeReport(buildReport(
            service: .clublog,
            downloaded: fetched.count,
            created: downloaded,
            merged: processResult.merged,
            uploaded: uploaded
        ))

        return (downloaded, uploaded)
    }
}
