import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - Single Service Sync (for UI buttons)

extension SyncService {
    /// Process activities for newly created QSOs if any were created
    private func processNewActivities(
        _ processResult: ProcessResult
    ) async {
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }
    }

    /// Sync only with QRZ (download then upload)
    /// - Parameter forceFullSync: If true, ignores last sync date and downloads all QSOs
    func syncQRZ(forceFullSync: Bool = false) async throws -> QRZSyncResult {
        isSyncing = true
        serviceSyncStates = [.qrz: .waiting]
        defer {
            isSyncing = false
            syncPhase = nil
            serviceSyncStates = [:]
            lastSyncDate = Date()
        }

        let lastDownload = forceFullSync ? nil : qrzClient.getLastDownloadDate()
        let syncStartTime = Date()

        // Download
        syncPhase = .downloading(service: .qrz)
        serviceSyncStates[.qrz] = .downloading
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
            try await self.qrzClient.fetchQSOs(since: lastDownload)
        }
        let fetched = qsos.map { FetchedQSO.fromQRZ($0) }
        serviceSyncStates[.qrz] = .downloaded(count: fetched.count)
        qrzClient.saveLastDownloadDate(syncStartTime)

        // Process
        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        await processNewActivities(processResult)

        // Reconcile on full sync only
        if forceFullSync || lastDownload == nil {
            let keys = Set(fetched.map(\.deduplicationKey))
            try await reconcileQRZPresenceAsync(downloadedKeys: keys)
        }
        await performDataRepairs()

        // Upload
        let (uploaded, skipped) = try await uploadQRZPhase(downloadedCount: fetched.count)

        storeReport(buildReport(
            service: .qrz,
            downloaded: fetched.count,
            created: processResult.created,
            merged: processResult.merged,
            uploaded: uploaded
        ))

        return QRZSyncResult(
            downloaded: processResult.created, uploaded: uploaded, skipped: skipped
        )
    }

    /// Sync only with POTA (download then upload)
    func syncPOTA() async throws -> (downloaded: Int, uploaded: Int) {
        isSyncing = true
        serviceSyncStates = [.pota: .waiting]
        defer {
            isSyncing = false
            syncPhase = nil
            serviceSyncStates = [:]
            lastSyncDate = Date()
        }

        if POTAClient.isInMaintenanceWindow() {
            throw POTAError.maintenanceWindow
        }

        // Download
        syncPhase = .downloading(service: .pota)
        serviceSyncStates[.pota] = .downloading
        let (qsos, remoteMap) = try await withTimeout(seconds: syncTimeoutSeconds, service: .pota) {
            try await self.potaClient.fetchAllQSOs { [weak self] processed, total, phase, qsoCount in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    var updated = syncProgress
                    updated.potaProcessedActivations = processed
                    updated.potaTotalActivations = total
                    updated.potaPhase = phase
                    updated.potaDownloadedQSOs = qsoCount
                    syncProgress = updated
                }
            }
        }
        potaRemoteQSOMap = remoteMap
        let fetched = qsos.map { FetchedQSO.fromPOTA($0) }
        serviceSyncStates[.pota] = .downloaded(count: fetched.count)

        // Process
        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        await processNewActivities(processResult)

        // Reconcile, repair, upload
        let reconcileResult = await reconcileAndRepairPOTA(remoteMap: remoteMap)
        let uploaded = try await uploadPOTAPhase(downloadedCount: fetched.count)

        storeReport(buildReport(
            service: .pota,
            downloaded: fetched.count,
            created: processResult.created,
            merged: processResult.merged,
            uploaded: uploaded,
            reconciliation: reconciliationReport(potaResult: reconcileResult)
        ))

        return (processResult.created, uploaded)
    }

    /// Sync only with LoFi (download only)
    func syncLoFi() async throws -> Int {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting LoFi-only sync", service: .lofi)
        isSyncing = true
        syncProgress.reset()
        serviceSyncStates = [.lofi: .waiting]
        defer {
            isSyncing = false
            syncPhase = nil
            serviceSyncStates = [:]
            lastSyncDate = Date()
        }

        // Download
        syncPhase = .downloading(service: .lofi)
        serviceSyncStates[.lofi] = .downloading
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
        debugLog.info("Fetched \(downloadResult.rawFetchCount) raw (\(qsos.count) dedup)", service: .lofi)
        let fetched = qsos.compactMap { FetchedQSO.fromLoFi($0.0, operation: $0.1) }
        debugLog.info("After filtering: \(fetched.count) valid QSOs", service: .lofi)
        serviceSyncStates[.lofi] = .downloaded(count: fetched.count)

        // Process
        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        await processNewActivities(processResult)

        storeReport(buildReport(
            service: .lofi,
            downloaded: qsos.count,
            skipped: qsos.count - fetched.count,
            created: processResult.created,
            merged: processResult.merged
        ))
        return processResult.created
    }

    /// Sync only with HAMRS (download only)
    func syncHAMRS() async throws -> Int {
        isSyncing = true
        serviceSyncStates = [.hamrs: .waiting]
        defer {
            isSyncing = false
            syncPhase = nil
            serviceSyncStates = [:]
            lastSyncDate = Date()
        }

        // Download with timeout
        syncPhase = .downloading(service: .hamrs)
        serviceSyncStates[.hamrs] = .downloading
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .hamrs) {
            try await self.hamrsClient.fetchAllQSOs()
        }
        let fetched = qsos.compactMap { FetchedQSO.fromHAMRS($0.0, logbook: $0.1) }
        serviceSyncStates[.hamrs] = .downloaded(count: fetched.count)

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)

        await processNewActivities(processResult)

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
        serviceSyncStates = [.lotw: .waiting]
        defer {
            isSyncing = false
            syncPhase = nil
            serviceSyncStates = [:]
            lastSyncDate = Date()
        }

        syncPhase = .downloading(service: .lotw)
        serviceSyncStates[.lotw] = .downloading
        let rxSince = lotwClient.getLastQSORxDate()
        let response = try await withTimeout(seconds: syncTimeoutSeconds, service: .lotw) {
            try await self.lotwClient.fetchQSOs(qsoRxSince: rxSince)
        }
        let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }
        serviceSyncStates[.lotw] = .downloaded(count: fetched.count)

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)

        await processNewActivities(processResult)

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
        serviceSyncStates = [.clublog: .waiting]
        defer {
            isSyncing = false
            syncPhase = nil
            serviceSyncStates = [:]
            lastSyncDate = Date()
        }

        var downloaded = 0
        var uploaded = 0

        // Use incremental sync unless forced full
        let lastDownload = forceFullSync ? nil : clublogClient.getLastDownloadDate()
        let syncStartTime = Date()

        // Download with timeout
        syncPhase = .downloading(service: .clublog)
        serviceSyncStates[.clublog] = .downloading
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .clublog) {
            try await self.clublogClient.fetchQSOs(since: lastDownload)
        }
        let fetched = qsos.map { FetchedQSO.fromClubLog($0) }
        serviceSyncStates[.clublog] = .downloaded(count: fetched.count)

        // Save sync timestamp on success
        clublogClient.saveLastDownloadDate(syncStartTime)

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        downloaded = processResult.created

        await processNewActivities(processResult)

        await performDataRepairs()

        uploaded = try await uploadClubLogPhase(downloadedCount: fetched.count)

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

// MARK: - Single Sync Helpers

extension SyncService {
    /// QRZ upload phase — returns (uploaded, skipped)
    private func uploadQRZPhase(downloadedCount: Int) async throws -> (Int, Int) {
        guard !isReadOnlyMode else {
            return (0, 0)
        }
        syncPhase = .uploading(service: .qrz)
        serviceSyncStates[.qrz] = .uploading
        let qsosToUpload = try fetchQSOsNeedingUpload().filter { $0.needsUpload(to: .qrz) }
        if qsosToUpload.count >= SyncExportConfirmation.threshold {
            let shouldProceed = await requestExportConfirmation(
                uploadByService: [.qrz: qsosToUpload.count]
            )
            guard shouldProceed else {
                return (0, 0)
            }
        }
        let result = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
            try await self.uploadToQRZ(qsos: qsosToUpload)
        }
        serviceSyncStates[.qrz] = .complete(
            downloaded: downloadedCount, uploaded: result.uploaded
        )
        if modelContext.hasChanges {
            try modelContext.save()
        }
        return (result.uploaded, result.skipped)
    }

    /// POTA reconcile, gap repair, and context refresh
    private func reconcileAndRepairPOTA(
        remoteMap: POTARemoteQSOMap
    ) async -> QSOProcessingActor.POTAReconcileResult? {
        let result = await reconcilePOTAPresenceAsync()
        if !remoteMap.isEmpty {
            await repairPOTAGapsAsync(remoteQSOMap: remoteMap)
        }
        modelContext.rollback()
        return result
    }

    /// POTA upload phase — returns uploaded count
    private func uploadPOTAPhase(downloadedCount: Int) async throws -> Int {
        guard !isReadOnlyMode else {
            return 0
        }
        syncPhase = .uploading(service: .pota)
        serviceSyncStates[.pota] = .uploading
        let qsosToUpload = try fetchQSOsNeedingUpload().filter {
            $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
        }
        if qsosToUpload.count >= SyncExportConfirmation.threshold {
            let shouldProceed = await requestExportConfirmation(
                uploadByService: [.pota: qsosToUpload.count]
            )
            guard shouldProceed else {
                return 0
            }
        }
        let uploaded = try await withTimeout(seconds: syncTimeoutSeconds, service: .pota) {
            try await self.uploadToPOTA(qsos: qsosToUpload)
        }
        serviceSyncStates[.pota] = .complete(
            downloaded: downloadedCount, uploaded: uploaded
        )
        if modelContext.hasChanges {
            try modelContext.save()
        }
        return uploaded
    }

    /// Club Log upload phase — returns uploaded count
    private func uploadClubLogPhase(downloadedCount: Int) async throws -> Int {
        guard !isReadOnlyMode else {
            return 0
        }
        syncPhase = .uploading(service: .clublog)
        serviceSyncStates[.clublog] = .uploading
        let qsosToUpload = try fetchQSOsNeedingUpload()
            .filter { $0.needsUpload(to: .clublog) }
        if !qsosToUpload.isEmpty {
            if qsosToUpload.count >= SyncExportConfirmation.threshold {
                let shouldProceed = await requestExportConfirmation(
                    uploadByService: [.clublog: qsosToUpload.count]
                )
                guard shouldProceed else {
                    serviceSyncStates[.clublog] = .complete(
                        downloaded: downloadedCount, uploaded: 0
                    )
                    return 0
                }
            }
            let result = try await withTimeout(
                seconds: syncTimeoutSeconds, service: .clublog
            ) {
                try await self.uploadToClubLog(qsos: qsosToUpload)
            }
            if modelContext.hasChanges {
                try modelContext.save()
            }
            serviceSyncStates[.clublog] = .complete(
                downloaded: downloadedCount, uploaded: result.uploaded
            )
            return result.uploaded
        }
        serviceSyncStates[.clublog] = .complete(
            downloaded: downloadedCount, uploaded: 0
        )
        return 0
    }
}
