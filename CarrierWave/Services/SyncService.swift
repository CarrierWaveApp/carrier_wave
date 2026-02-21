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

    /// Full sync: download from all sources, deduplicate, upload to all destinations
    func syncAll() async throws -> SyncResult {
        isSyncing = true
        syncProgress.reset()
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting full sync")

        // Pre-sync backup
        if UserDefaults.standard.object(
            forKey: "autoBackupEnabled"
        ) as? Bool ?? true,
            let storeURL = modelContext.container
            .configurations.first?.url
        {
            await BackupService.shared.snapshot(
                trigger: .preSync, storeURL: storeURL
            )
        }

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
}

// MARK: - SyncService single-service sync methods are in SyncService+SingleSync.swift

// MARK: - SyncService Helpers are in SyncService+Helpers.swift
