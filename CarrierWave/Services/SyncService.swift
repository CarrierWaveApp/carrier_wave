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
        lotwClient: LoTWClient? = nil,
        clublogClient: ClubLogClient? = nil
    ) {
        self.modelContext = modelContext
        qrzClient = QRZClient()
        self.potaAuthService = potaAuthService
        potaClient = POTAClient(authService: potaAuthService)
        self.lofiClient = lofiClient ?? LoFiClient.appDefault()
        self.hamrsClient = hamrsClient ?? HAMRSClient()
        self.lotwClient = lotwClient ?? LoTWClient()
        self.clublogClient = clublogClient ?? ClubLogClient()
        loadPersistedReports()
    }

    // MARK: Internal

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be synced to any service
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncPhase: SyncPhase?
    @Published var syncProgress = SyncProgress()
    @Published var lastSyncResults: [ServiceType: ServiceSyncReport] = [:]
    @Published var serviceSyncStates: [ServiceType: ServiceSyncPhase] = [:]

    /// Set when a large download needs user confirmation before importing.
    /// The UI should observe this and show a confirmation dialog.
    @Published var importConfirmation: SyncImportConfirmation?

    /// Set when a large number of QSOs are queued for upload.
    /// The UI should observe this and show a confirmation dialog.
    @Published var exportConfirmation: SyncExportConfirmation?

    let modelContext: ModelContext
    let qrzClient: QRZClient
    let potaClient: POTAClient
    let potaAuthService: POTAAuthService
    let lofiClient: LoFiClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let clublogClient: ClubLogClient

    /// Remote QSO map from the most recent POTA download, used for gap repair.
    var potaRemoteQSOMap: POTARemoteQSOMap?

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

    /// Initialize per-service sync states based on which services are configured
    func initializeServiceSyncStates() {
        var states: [ServiceType: ServiceSyncPhase] = [:]
        if qrzClient.hasApiKey() {
            states[.qrz] = .waiting
        }
        if potaAuthService.isConfigured, !POTAClient.isInMaintenanceWindow() {
            states[.pota] = .waiting
        }
        if lofiClient.isConfigured, lofiClient.isLinked {
            states[.lofi] = .waiting
        }
        if hamrsClient.isConfigured {
            states[.hamrs] = .waiting
        }
        if lotwClient.hasCredentials() {
            states[.lotw] = .waiting
        }
        if clublogClient.isConfigured {
            states[.clublog] = .waiting
        }
        serviceSyncStates = states
    }

    /// Full sync: download from all sources, deduplicate, upload to all destinations
    func syncAll() async throws -> SyncResult {
        isSyncing = true
        syncProgress.reset()
        initializeServiceSyncStates()
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting full sync")

        await createPreSyncBackupIfEnabled()

        // Capture whether this will be an incremental QRZ sync (before downloads modify it)
        let qrzWasIncremental = qrzClient.getLastDownloadDate() != nil

        defer {
            isSyncing = false
            syncPhase = nil
            syncProgress.reset()
            serviceSyncStates = [:]
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

        // PHASE 1.5: Confirm with user if large download detected
        if await shouldCancelAfterDownload(allFetched, downloaded: result.downloaded) {
            return result
        }

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

        // PHASE 2.5: Reconcile and repair data
        let (qrzResetCount, potaReconcileResult) = try await performReconciliation(
            allFetched: allFetched, qrzWasIncremental: qrzWasIncremental
        )

        // PHASE 3: Upload to all destinations in parallel (unless read-only mode)
        await performUploadsIfEnabled(into: &result, debugLog: debugLog)

        // Only save if uploads made changes (background actor already saved QSO changes)
        if modelContext.hasChanges {
            try modelContext.save()
        }

        // Build per-service sync reports
        buildFullSyncReports(
            result: result,
            qrzResetCount: qrzResetCount,
            potaReconcileResult: potaReconcileResult
        )

        return result
    }

    /// Count net-new QSOs that don't already exist in the database.
    func countNetNewQSOs(_ fetched: [FetchedQSO]) async -> Int {
        do {
            return try await SyncService.processingActor.countNetNewQSOs(
                fetched, container: modelContext.container
            )
        } catch {
            // On error, fall back to total count (will show the confirmation)
            return fetched.count
        }
    }

    // MARK: Private

    /// Check if user wants to cancel after a large download.
    /// Only prompts when net-new QSOs (not already in DB) exceed the threshold.
    private func shouldCancelAfterDownload(
        _ allFetched: [FetchedQSO], downloaded: [ServiceType: Int]
    ) async -> Bool {
        await shouldCancelLargeImport(allFetched, downloaded: downloaded)
    }

    // MARK: - Pre-Sync Backup

    private func createPreSyncBackupIfEnabled() async {
        guard UserDefaults.standard.object(
            forKey: "autoBackupEnabled"
        ) as? Bool ?? true,
            let storeURL = modelContext.container
            .configurations.first?.url
        else {
            return
        }

        let count = BackupService.visibleQSOCount(
            in: modelContext.container
        )
        await BackupService.shared.snapshot(
            trigger: .preSync, storeURL: storeURL,
            qsoCount: count
        )
    }
}

// MARK: - SyncService single-service sync methods are in SyncService+SingleSync.swift

// MARK: - SyncService Helpers are in SyncService+Helpers.swift
