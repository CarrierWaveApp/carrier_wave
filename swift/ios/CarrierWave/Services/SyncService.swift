import CarrierWaveData
import SwiftData
import UIKit

// MARK: - SyncService

@Observable
@MainActor
class SyncService {
    // MARK: Lifecycle

    init(
        modelContext: ModelContext, potaAuthService: POTAAuthService,
        lofiClient: LoFiClient? = nil,
        hamrsClient: HAMRSClient? = nil,
        lotwClient: LoTWClient? = nil,
        clublogClient: ClubLogClient? = nil,
        eqslClient: EQSLClient? = nil
    ) {
        self.modelContext = modelContext
        qrzClient = QRZClient()
        self.potaAuthService = potaAuthService
        potaClient = POTAClient(authService: potaAuthService)
        self.lofiClient = lofiClient ?? LoFiClient.appDefault()
        self.hamrsClient = hamrsClient ?? HAMRSClient()
        self.lotwClient = lotwClient ?? LoTWClient()
        self.clublogClient = clublogClient ?? ClubLogClient()
        self.eqslClient = eqslClient ?? EQSLClient()
        loadPersistedReports()
    }

    // MARK: Internal

    var isSyncing = false
    var lastSyncDate: Date?
    var syncPhase: SyncPhase?
    var syncProgress = SyncProgress()
    var lastSyncResults: [ServiceType: ServiceSyncReport] = [:]
    var serviceSyncStates: [ServiceType: ServiceSyncPhase] = [:]

    /// Set when a large download needs user confirmation before importing.
    /// The UI should observe this and show a confirmation dialog.
    var importConfirmation: SyncImportConfirmation?

    /// Set when a large number of QSOs are queued for upload.
    /// The UI should observe this and show a confirmation dialog.
    var exportConfirmation: SyncExportConfirmation?

    let modelContext: ModelContext
    let qrzClient: QRZClient
    let potaClient: POTAClient
    let potaAuthService: POTAAuthService
    let lofiClient: LoFiClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let clublogClient: ClubLogClient
    let eqslClient: EQSLClient

    /// Remote QSO map from the most recent POTA download, used for gap repair.
    var potaRemoteQSOMap: POTARemoteQSOMap?

    /// Activation snapshots from the most recent POTA download, used for session creation.
    var potaActivationSnapshots: [POTAActivationSnapshot] = []

    /// Confirmed QRZ log IDs from the latest sync. Set during download,
    /// applied during processing to mark QSOs as confirmed without full ADIF re-fetch.
    var qrzConfirmedLogIds: Set<String> = []

    /// QSL confirmations applied to existing QRZ-tracked QSOs in the latest sync.
    /// Reset at sync start, populated when applyQRZConfirmations runs.
    var lastQRZQslsApplied: Int = 0

    /// QSL confirmation records returned by LoTW in the latest sync.
    /// Reset at sync start, populated by the LoTW download path.
    var lastLoTWQslsReceived: Int = 0

    // Activity detection (internal for extension access)
    var activityDetector: ActivityDetector?
    var activityReporter: ActivityReporter?
    let activitySourceURL = ActivitiesClient.resolvedBaseURL

    /// Timeout for individual service sync operations (in seconds)
    let syncTimeoutSeconds: TimeInterval = 180

    /// Extended timeout for services with internal adaptive handling (POTA, LoTW)
    /// These services handle their own per-request timeouts and retries
    let extendedSyncTimeoutSeconds: TimeInterval = 600 // 10 minutes

    /// Check if uploads are enabled for a specific service (based on per-service sync mode).
    func isUploadEnabled(for service: ServiceType) -> Bool {
        CarrierWaveData.ServiceConfiguration.isUploadEnabled(for: service)
    }

    /// Check if downloads are enabled for a specific service (based on per-service sync mode).
    func isDownloadEnabled(for service: ServiceType) -> Bool {
        CarrierWaveData.ServiceConfiguration.isDownloadEnabled(for: service)
    }

    /// Initialize per-service sync states based on which services are configured.
    /// Also resets transient per-sync counters so each sync starts clean.
    func initializeServiceSyncStates() {
        lastQRZQslsApplied = 0
        lastLoTWQslsReceived = 0
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
        // Club Log: "Coming Soon" — not yet configurable as a sync source
        if eqslClient.isConfigured {
            states[.eqsl] = .waiting
        }
        serviceSyncStates = states
    }

    /// Full sync: download from all sources, deduplicate, upload to all destinations
    func syncAll() async throws -> SyncResult {
        // Re-entrancy guard: prevents concurrent syncAll() calls from corrupting
        // the isSyncing flag. Without this, a manual sync + AutoSyncService can
        // overlap, and the first defer resets isSyncing=false while the second is
        // still running — letting AutoSyncService start yet another sync in a loop.
        guard !isSyncing else {
            SyncDebugLog.shared.info("syncAll skipped: already syncing")
            return SyncResult(
                downloaded: [:], uploaded: [:], errors: [],
                newQSOs: 0, mergedQSOs: 0, potaMaintenanceSkipped: false
            )
        }

        beginSyncState()
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting full sync")

        // Backgrounding mid-sync must not suspend the process while a cw-store
        // commit holds the SQLite lock — that's a 0xdead10cc RunningBoard kill
        // (TestFlight crashes 3160, 3428). The assertion keeps the process alive
        // for the ~30 s background grant, and its expiration handler cancels the
        // sync so the batched commit loops bail at their next
        // Task.checkCancellation() — a safe point *between* SQLite commits —
        // instead of being suspended mid-fsync when the grant runs out (the
        // download phase can spend most of it before the writes even begin). Sync
        // state is durable, so the next foreground sync resumes cleanly.
        let suspensionGuard = BackgroundTaskAssertion(name: "SyncService.syncAll")

        defer {
            suspensionGuard.release()
            isSyncing = false
            syncPhase = nil
            syncProgress.reset()
            serviceSyncStates = [:]
            lastSyncDate = Date()
            debugLog.info("Sync complete")
        }

        let work = Task { try await self.performFullSync(debugLog: debugLog) }
        suspensionGuard.onExpiration = { work.cancel() }
        return try await withTaskCancellationHandler(operation: {
            try await work.value
        }, onCancel: {
            work.cancel()
        })
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

    /// The phased sync body (download → process → reconcile → upload). Runs inside
    /// a cancellable child task owned by `syncAll()` so the background-task
    /// expiration handler can stop it at a safe point before the process is
    /// suspended (see the `suspensionGuard` note in `syncAll()`).
    private func performFullSync(debugLog: SyncDebugLog) async throws -> SyncResult {
        let qrzWasIncremental = await prepareSyncEnvironment()

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

        // PHASE 2.5: Post-process, session creation, reconciliation
        try await performPostProcessing(processResult)
        let (qrzResetCount, potaReconcileResult) = try await performReconciliation(
            allFetched: allFetched, qrzWasIncremental: qrzWasIncremental
        )

        // PHASE 3: Upload to all destinations in parallel (unless read-only mode)
        await performUploadsIfEnabled(into: &result, debugLog: debugLog)
        if modelContext.hasChanges {
            try modelContext.save()
        }

        buildFullSyncReports(
            result: result,
            qrzResetCount: qrzResetCount,
            potaReconcileResult: potaReconcileResult
        )
        return result
    }

    /// Flip the observable sync state to "syncing" and reset per-run progress.
    private func beginSyncState() {
        isSyncing = true
        syncProgress.reset()
        initializeServiceSyncStates()
    }

    /// Post-processing: activities, QRZ confirmations, POTA session creation.
    private func performPostProcessing(_ processResult: ProcessResult) async throws {
        let createdQSOs = processResult.fetchCreatedQSOs(from: modelContext)
        if !createdQSOs.isEmpty {
            await processActivities(newQSOs: createdQSOs)
        }

        if !qrzConfirmedLogIds.isEmpty {
            try await applyQRZConfirmations(logIds: qrzConfirmedLogIds)
            qrzConfirmedLogIds = []
        }

        if !potaActivationSnapshots.isEmpty {
            await createPOTASessionsAsync(snapshots: potaActivationSnapshots)
            potaActivationSnapshots = []
        }
    }

    /// Check if user wants to cancel after a large download.
    /// Only prompts when net-new QSOs (not already in DB) exceed the threshold.
    private func shouldCancelAfterDownload(
        _ allFetched: [FetchedQSO], downloaded: [ServiceType: Int]
    ) async -> Bool {
        await shouldCancelLargeImport(allFetched, downloaded: downloaded)
    }

    // MARK: - Pre-Sync Setup

    /// Pre-sync setup: backup, QRZ reconciliation scheduling, callsign sync.
    /// Returns whether the upcoming QRZ download will be incremental.
    private func prepareSyncEnvironment() async -> Bool {
        await createPreSyncBackupIfEnabled()

        // Periodically force a full QRZ download for reconciliation.
        // Incremental syncs skip reconciliation (incomplete data), so stale
        // isPresent flags accumulate. Forcing a full download every N syncs
        // triggers reconciliation which corrects drift.
        forceFullQRZDownloadIfDue()

        if qrzClient.hasApiKey() {
            await syncCallsignFromQRZ()
        }

        return qrzClient.getLastDownloadDate() != nil
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
