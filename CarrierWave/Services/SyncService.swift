import CarrierWaveCore
import Combine
import Foundation
import SwiftData

// MARK: - SyncService

@MainActor
class SyncService: ObservableObject {
    // MARK: Lifecycle

    init(
        modelContext: ModelContext, potaAuthService: POTAAuthService,
        lofiClient: LoFiClient? = nil,
        hamrsClient: HAMRSClient? = nil,
        lotwClient: LoTWClient? = nil
    ) {
        self.modelContext = modelContext
        qrzClient = QRZClient()
        self.potaAuthService = potaAuthService
        potaClient = POTAClient(authService: potaAuthService)
        self.lofiClient = lofiClient ?? LoFiClient()
        self.hamrsClient = hamrsClient ?? HAMRSClient()
        self.lotwClient = lotwClient ?? LoTWClient()
    }

    // MARK: Internal

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be synced to any service
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncPhase: SyncPhase?
    @Published var syncProgress = SyncProgress()

    let modelContext: ModelContext
    let qrzClient: QRZClient
    let potaClient: POTAClient
    let potaAuthService: POTAAuthService
    let lofiClient: LoFiClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient

    // Activity detection (internal for extension access)
    var activityDetector: ActivityDetector?
    var activityReporter: ActivityReporter?
    let activitySourceURL = "https://activities.carrierwave.app"

    /// Timeout for individual service sync operations (in seconds)
    let syncTimeoutSeconds: TimeInterval = 180

    /// Extended timeout for services with internal adaptive handling (POTA, LoTW)
    /// These services handle their own per-request timeouts and retries
    let extendedSyncTimeoutSeconds: TimeInterval = 600 // 10 minutes

    /// Check if read-only mode is enabled (disables uploads)
    var isReadOnlyMode: Bool {
        UserDefaults.standard.bool(forKey: "readOnlyMode")
    }

    /// Full sync: download from all sources, deduplicate, upload to all destinations
    func syncAll() async throws -> SyncResult {
        isSyncing = true
        syncProgress.reset()
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting full sync")

        // Capture whether this will be an incremental QRZ sync (before downloads modify it)
        let qrzWasIncremental = qrzClient.getLastDownloadDate() != nil

        defer {
            isSyncing = false
            syncPhase = nil
            syncProgress.reset()
            lastSyncDate = Date()
            debugLog.info("Sync complete")
        }

        var result = SyncResult(
            downloaded: [:], uploaded: [:], errors: [], newQSOs: 0, mergedQSOs: 0,
            potaMaintenanceSkipped: false
        )

        // PHASE 1: Download from all sources in parallel
        let downloadResults = await downloadFromAllSources()
        let allFetched = collectDownloadResults(downloadResults, into: &result)

        // PHASE 2: Process and deduplicate (on background thread)
        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(allFetched)
        result.newQSOs = processResult.created
        result.mergedQSOs = processResult.merged
        notifyNewQSOsIfNeeded(count: processResult.created)

        // PHASE 2.5a: Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        // PHASE 2.5b: Reconcile QRZ presence - only on full sync (not incremental)
        // Incremental sync doesn't have the complete picture, so reconciliation would be inaccurate
        if !qrzWasIncremental {
            let qrzDownloadedKeys = Set(
                allFetched.filter { $0.source == .qrz }.map(\.deduplicationKey)
            )
            if !qrzDownloadedKeys.isEmpty {
                try await reconcileQRZPresenceAsync(downloadedKeys: qrzDownloadedKeys)
            }
        }

        // PHASE 2.5c: Repair orphaned QSOs (logged when services weren't configured)
        if qrzClient.hasApiKey() {
            await repairOrphanedQSOsAsync(for: .qrz)
        }

        // PHASE 2.5d: Clear upload flags on metadata pseudo-modes (WEATHER, SOLAR, NOTE)
        await clearMetadataUploadFlagsAsync()

        // PHASE 2.5e: Clear upload flags on QSOs from non-primary callsigns
        // These will never upload because services are configured with current callsign
        await clearNonPrimaryCallsignUploadFlagsAsync()

        // PHASE 2.5f: Repair missing DXCC from rawADIF
        // Backfills DXCC for QSOs imported before the fix was applied
        await repairMissingDXCCAsync()

        // Refresh main context to pick up changes from background actor
        modelContext.rollback()

        // PHASE 3: Upload to all destinations in parallel (unless read-only mode)
        await performUploadsIfEnabled(into: &result, debugLog: debugLog)

        // Only save if uploads made changes (presence records modified)
        // Background processing actor already saved QSO/presence changes
        if modelContext.hasChanges {
            try modelContext.save()
        }

        return result
    }

    // MARK: - Single Service Sync (for UI buttons)

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

        // Repair orphaned QSOs (logged when QRZ wasn't configured)
        await repairOrphanedQSOsAsync(for: .qrz)

        // Clear upload flags on metadata pseudo-modes (WEATHER, SOLAR, NOTE)
        await clearMetadataUploadFlagsAsync()

        // Clear upload flags on QSOs from non-primary callsigns
        await clearNonPrimaryCallsignUploadFlagsAsync()

        // Repair missing DXCC from rawADIF
        await repairMissingDXCCAsync()

        // Refresh main context to pick up changes from background actor
        modelContext.rollback()

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

        return QRZSyncResult(downloaded: downloaded, uploaded: uploaded, skipped: skipped)
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
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .lofi) {
            try await self.lofiClient.fetchAllQsosSinceLastSync { [weak self] progress in
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
        debugLog.info("Fetched \(qsos.count) raw QSOs", service: .lofi)
        let fetched = qsos.compactMap { FetchedQSO.fromLoFi($0.0, operation: $0.1) }
        debugLog.info("After filtering: \(fetched.count) valid QSOs", service: .lofi)

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

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

        return processResult.created
    }
}

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

// Download methods are in SyncService+Download.swift
// Upload methods are in SyncService+Upload.swift
// Process methods are in SyncService+Process.swift
