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
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR"]

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
    let activitySourceURL = "https://challenges.example.com"

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

        // PHASE 2.5b: Reconcile QRZ presence against what QRZ actually returned (on background thread)
        let qrzDownloadedKeys = Set(allFetched.filter { $0.source == .qrz }.map(\.deduplicationKey))
        if !qrzDownloadedKeys.isEmpty {
            try await reconcileQRZPresenceAsync(downloadedKeys: qrzDownloadedKeys)
        }

        // PHASE 3: Upload to all destinations in parallel (unless read-only mode)
        await performUploadsIfEnabled(into: &result, debugLog: debugLog)

        try modelContext.save()
        return result
    }

    // MARK: - Single Service Sync (for UI buttons)

    /// Sync only with QRZ (download then upload)
    func syncQRZ() async throws -> QRZSyncResult {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
        }

        var downloaded = 0
        var uploaded = 0
        var skipped = 0

        // Download with timeout
        syncPhase = .downloading(service: .qrz)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
            try await self.qrzClient.fetchQSOs(since: nil)
        }
        let fetched = qsos.map { FetchedQSO.fromQRZ($0) }

        syncPhase = .processing
        let processResult = try await processDownloadedQSOsAsync(fetched)
        downloaded = processResult.created

        // Process activities for newly created QSOs
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        // Reconcile QRZ presence against what QRZ actually returned
        let qrzDownloadedKeys = Set(fetched.map(\.deduplicationKey))
        try await reconcileQRZPresenceAsync(downloadedKeys: qrzDownloadedKeys)

        // Upload with timeout (unless read-only mode)
        if !isReadOnlyMode {
            syncPhase = .uploading(service: .qrz)
            let qsosToUpload = try fetchQSOsNeedingUpload().filter { $0.needsUpload(to: .qrz) }
            let uploadResult = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
                try await self.uploadToQRZ(qsos: qsosToUpload)
            }
            uploaded = uploadResult.uploaded
            skipped = uploadResult.skipped
            try modelContext.save()
        }

        return QRZSyncResult(downloaded: downloaded, uploaded: uploaded, skipped: skipped)
    }

    /// Sync only with POTA (download then upload)
    func syncPOTA() async throws -> (downloaded: Int, uploaded: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
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

        // Upload with timeout (unless read-only mode)
        if !isReadOnlyMode {
            syncPhase = .uploading(service: .pota)
            let qsosToUpload = try fetchQSOsNeedingUpload().filter {
                $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
            }
            uploaded = try await withTimeout(seconds: syncTimeoutSeconds, service: .pota) {
                try await self.uploadToPOTA(qsos: qsosToUpload)
            }
            try modelContext.save()
        }

        return (downloaded, uploaded)
    }

    /// Sync only with LoFi (download only)
    func syncLoFi() async throws -> Int {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting LoFi-only sync", service: .lofi)
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
        }

        // Download with timeout
        syncPhase = .downloading(service: .lofi)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .lofi) {
            try await self.lofiClient.fetchAllQsosSinceLastSync()
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

    // MARK: Private

    private func collectDownloadResults(
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

    private func notifyNewQSOsIfNeeded(count: Int) {
        guard count > 0 else {
            return
        }
        NotificationCenter.default.post(
            name: .didSyncQSOs,
            object: nil,
            userInfo: ["newQSOCount": count]
        )
    }

    private func performUploadsIfEnabled(
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
