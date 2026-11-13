import CarrierWaveData
import CloudKit
import Combine
import Foundation
import Network
import OSLog
import SwiftData

// MARK: - CloudSyncService

/// @MainActor service that owns the journal-based CKSyncEngine and publishes
/// sync status for UI. Observes local data changes and feeds them to the
/// journal engine, which batches them into `ChangeJournal` CKRecords and
/// uploads SQLite snapshots periodically for fast device bootstrap.
@Observable
@MainActor
final class CloudSyncService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CloudSyncService()

    /// Whether iCloud QSO sync is enabled by the user.
    var isEnabled: Bool = false

    /// Current sync status for UI display.
    var syncStatus: SyncStatus = .disabled

    /// Last successful sync timestamp.
    var lastSyncDate: Date?

    /// Persistent error message for settings display.
    var errorMessage: String?

    /// iCloud account status.
    var accountStatus: CKAccountStatus = .couldNotDetermine

    /// Snapshot of dirty record counts for the Settings panel.
    var counts: CloudSyncRecordCounts = .empty

    /// Total records at start of current upload (for progress bar). Nil when idle.
    var uploadGoal: Int?

    /// Running count of records successfully uploaded in current batch operation.
    var uploadedCount: Int = 0

    /// Computed summary of recent sync activity (for Settings).
    var syncSummary: CloudSyncSummary = .empty

    /// Recent sync events for the activity log.
    var syncEvents: [CloudSyncEvent] = []

    var journalEngine: CloudSyncJournalEngine?

    // MARK: - Public API

    /// Configure the sync service without starting the engine. Call from the
    /// app entry point after the ModelContainer is ready; call
    /// `startIfEnabled()` separately after the startup stats pipeline finishes
    /// so we don't run two concurrent full-table scans (scene-update watchdog).
    func configure(container: ModelContainer) {
        self.container = container
        let engine = CloudSyncJournalEngine(container: container)
        journalEngine = engine
        Task {
            await engine.setDelegate(self)
            // Phase 7.2 seam: when CwStoreSyncMode == .serverSync the engine
            // routes its entry points here instead of CKSyncEngine.
            await engine.setServerSyncRunner {
                await SyncKeyService.runBackgroundPass(trigger: "journal-engine")
            }
        }

        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)

        setupChangeObserver()
    }

    /// Check iCloud account and start the sync engine if enabled.
    func startIfEnabled() async {
        await checkAccountStatus()
        if isEnabled {
            await startSync()
        }
        await refreshSyncEvents()
    }

    /// Enable or disable iCloud sync.
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)

        if enabled {
            await startSync()
        } else {
            await stopSync()
        }
    }

    /// Handle a remote push notification by fetching latest journal entries.
    func handleRemoteNotification(_ userInfo: sending [AnyHashable: Any]) async {
        guard isEnabled, let journalEngine else {
            return
        }
        await journalEngine.fetchChanges()
    }

    /// Upload pending (already-dirty) records to iCloud.
    func syncPending() async {
        guard isEnabled, let journalEngine else {
            return
        }
        uploadedCount = 0
        uploadGoal = counts.totalDirty
        syncStatus = .syncing(detail: "Uploading... \(counts.totalDirty) remaining")
        await journalEngine.schedulePendingChanges()
    }

    /// Force a full sync (mark everything dirty and push).
    func forceFullSync() async {
        guard isEnabled, let journalEngine else {
            return
        }
        syncStatus = .syncing(detail: "Marking all records dirty...")
        await journalEngine.markAllRecordsDirty()
        counts = await journalEngine.recordCounts()
        uploadedCount = 0
        uploadGoal = counts.totalDirty
        syncStatus = .syncing(detail: "Uploading... \(counts.totalDirty) remaining")
        await journalEngine.schedulePendingChanges()
    }

    /// Upload a SQLite snapshot to CloudKit for fast bootstrap on other devices.
    /// Called periodically (every 6 hours) after sync completes.
    func uploadSnapshotIfNeeded() async {
        guard isEnabled, let container, let journalEngine else {
            return
        }
        guard let storeURL = container.configurations.first?.url else {
            return
        }
        let qsoCount = await Task.detached {
            BackupService.visibleQSOCount(in: container)
        }.value
        await journalEngine.uploadSnapshotIfNeeded(
            storeURL: storeURL, qsoCount: qsoCount
        )
    }

    /// Refresh dirty record counts for Settings display.
    func refreshCounts() async {
        guard let journalEngine else {
            return
        }
        counts = await journalEngine.recordCounts()
    }

    /// Fetch latest changes from CloudKit. Called on foreground re-entry,
    /// network recovery, and the active-session poll for cross-device sync.
    func fetchChangesFromCloud() async {
        guard isEnabled, let journalEngine else {
            return
        }
        await journalEngine.fetchChanges()
    }

    /// Refresh the in-memory event log for Settings display.
    func refreshSyncEvents() async {
        guard let journalEngine else {
            return
        }
        let events = await journalEngine.eventLog.allEvents()
        logger.info("refreshSyncEvents: \(events.count) events loaded")
        syncEvents = events
        syncSummary = CloudSyncSummary.from(events: events)
    }

    /// Reset sync state after the user wipes the local logbook so the
    /// next engine start re-bootstraps from the cloud snapshot + replays
    /// every journal in the zone. Without this, the persisted change
    /// token would skip already-applied journals and the cloud copy
    /// would never repopulate the freshly-emptied store (CAR-264).
    func resetForLocalWipe() async {
        // Server-sync (Phase 7) per-base cursors + seeded flags must reset
        // regardless of whether the CK journal engine is running — a stale
        // cursor would skip the repopulating pull and a stale seeded flag
        // would let a background pass push the emptied store.
        SyncKeyService.resetForLocalWipe()
        guard let journalEngine else {
            return
        }
        syncStatus = .syncing(detail: "Restoring from iCloud...")
        uploadGoal = nil
        uploadedCount = 0
        await journalEngine.resetForLocalWipe()
        counts = await journalEngine.recordCounts()
        syncStatus = isEnabled ? .upToDate : .disabled
        lastSyncDate = Date()
    }

    // MARK: Private

    private let logger = Logger(
        subsystem: "com.jsvana.FullDuplex", category: "CloudSyncService"
    )
    private let enabledKey = "cloudSyncEnabled"

    private var container: ModelContainer?
    private var changeObserver: AnyCancellable?
    private var networkMonitor: NWPathMonitor?
    private var networkMonitorQueue = DispatchQueue(label: "cloudSync.networkMonitor")
    private var wasDisconnected = false

    private func startSync() async {
        guard let journalEngine else {
            return
        }
        do {
            syncStatus = .syncing(detail: "Starting...")
            try await journalEngine.start()
            await journalEngine.schedulePendingChanges()
            startNetworkMonitor()
            counts = await journalEngine.recordCounts()
            syncStatus = .upToDate
            lastSyncDate = Date()
            errorMessage = nil
        } catch {
            logger.error("Failed to start cloud sync: \(error)")
            syncStatus = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func stopSync() async {
        if let journalEngine {
            await journalEngine.stop()
        }
        stopNetworkMonitor()
        syncStatus = .disabled
    }

    // MARK: - Account Status

    private func checkAccountStatus() async {
        do {
            let ckContainer = CKContainer(
                identifier: "iCloud.com.jsvana.FullDuplex"
            )
            accountStatus = try await ckContainer.accountStatus()

            switch accountStatus {
            case .available:
                errorMessage = nil
            case .noAccount:
                errorMessage = "No iCloud account. Sign in to Settings to enable sync."
                if isEnabled {
                    syncStatus = .error("No iCloud account")
                }
            case .restricted:
                errorMessage = "iCloud access is restricted on this device."
            case .couldNotDetermine:
                errorMessage = "Unable to determine iCloud account status."
            case .temporarilyUnavailable:
                errorMessage = "iCloud is temporarily unavailable."
            @unknown default:
                break
            }
        } catch {
            logger.error("Failed to check iCloud account: \(error)")
            errorMessage = "Unable to check iCloud account status."
        }
    }

    // MARK: - Network Recovery

    private func startNetworkMonitor() {
        networkMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else {
                return
            }
            Task { @MainActor in
                if path.status == .satisfied, self.wasDisconnected {
                    self.logger.info("Network recovered — fetching cloud changes")
                    self.wasDisconnected = false
                    await self.fetchChangesFromCloud()
                } else if path.status != .satisfied {
                    self.wasDisconnected = true
                }
            }
        }
        monitor.start(queue: networkMonitorQueue)
        networkMonitor = monitor
    }

    private func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
        wasDisconnected = false
    }

    // MARK: - Change Observation

    private func setupChangeObserver() {
        changeObserver = NotificationCenter.default.publisher(
            for: ModelContext.didSave
        )
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            guard let self, isEnabled else {
                return
            }
            Task { @MainActor in
                await self.journalEngine?.schedulePendingChanges()
            }
        }
    }
}

// MARK: CloudSyncJournalDelegate

extension CloudSyncService: CloudSyncJournalDelegate {
    nonisolated func journalEngine(
        _ engine: CloudSyncJournalEngine,
        didUpdateStatus status: String
    ) {
        Task { @MainActor in
            self.syncStatus = .syncing(detail: status)
        }
    }

    nonisolated func journalEngineDidFinishSync(
        _ engine: CloudSyncJournalEngine
    ) {
        Task { @MainActor in
            if self.syncStatus.isSyncing {
                self.syncStatus = .upToDate
                self.lastSyncDate = Date()
                self.uploadGoal = nil
                self.uploadedCount = 0
            }
            await self.refreshCounts()
            await self.uploadSnapshotIfNeeded()
        }
    }

    nonisolated func journalEngine(
        _ engine: CloudSyncJournalEngine,
        didLogEvent event: CloudSyncEvent
    ) {
        Task { @MainActor in
            self.syncEvents.append(event)
            self.syncSummary = CloudSyncSummary.from(events: self.syncEvents)
        }
    }

    nonisolated func journalEngine(
        _ engine: CloudSyncJournalEngine,
        didConfirmOperations count: Int
    ) {
        Task { @MainActor in
            self.uploadedCount += count
            if let goal = self.uploadGoal, goal > 0 {
                let remaining = max(0, goal - self.uploadedCount)
                self.syncStatus = .syncing(
                    detail: "Uploading... \(remaining) remaining"
                )
            }
        }
    }
}

// MARK: CloudSyncService.SyncStatus

extension CloudSyncService {
    enum SyncStatus: Equatable {
        case disabled
        case upToDate
        case syncing(detail: String)
        case error(String)

        // MARK: Internal

        var displayText: String {
            switch self {
            case .disabled: "Disabled"
            case .upToDate: "Up to date"
            case let .syncing(detail): detail
            case let .error(message): message
            }
        }

        var iconName: String {
            switch self {
            case .disabled: "icloud.slash"
            case .upToDate: "checkmark.icloud"
            case .syncing: "icloud.and.arrow.up"
            case .error: "exclamationmark.icloud"
            }
        }

        var isError: Bool {
            if case .error = self {
                return true
            }
            return false
        }

        var isSyncing: Bool {
            if case .syncing = self {
                return true
            }
            return false
        }
    }

    var isSyncing: Bool {
        syncStatus.isSyncing
    }
}
