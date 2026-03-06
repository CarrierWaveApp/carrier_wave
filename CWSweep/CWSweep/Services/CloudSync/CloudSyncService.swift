import AppKit
import CarrierWaveData
import CloudKit
import Combine
import Foundation
import Network
import os
import SwiftData

// MARK: - CloudSyncService

/// @MainActor service that owns the CKSyncEngine and publishes sync status for UI.
/// macOS version using @Observable (matches CW Sweep conventions).
@MainActor @Observable
final class CloudSyncService: CloudSyncEngineDelegate {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CloudSyncService()

    /// Whether iCloud QSO sync is enabled by the user
    var isEnabled: Bool = false

    /// Current sync status for UI display
    var syncStatus: SyncStatus = .disabled

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Persistent error message for settings display
    var errorMessage: String?

    /// iCloud account status
    var accountStatus: CKAccountStatus = .couldNotDetermine

    /// Snapshot of dirty and synced record counts
    var counts: CloudSyncRecordCounts = .empty

    /// Total records at start of current upload (for progress bar). Nil when idle.
    var uploadGoal: Int?

    /// Running count of records successfully uploaded in current batch operation.
    var uploadedCount: Int = 0

    // MARK: - Public API

    /// Configure and start the sync service.
    func configure(container: ModelContainer) {
        self.container = container
        let syncEngine = CloudSyncEngine(container: container)
        engine = syncEngine
        Task { await syncEngine.setDelegate(self) }

        // Load persisted enabled state
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)

        // Observe local data changes
        setupChangeObserver()

        // Register for remote notifications
        NSApplication.shared.registerForRemoteNotifications()

        // Check account and start if enabled
        Task {
            await checkAccountStatus()
            if isEnabled {
                await startSync()
            }
        }
    }

    /// Enable or disable iCloud sync
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)

        if enabled {
            await startSync()
        } else {
            await stopSync()
        }
    }

    /// Handle a remote push notification
    func handleRemoteNotification(_ userInfo: sending [AnyHashable: Any]) async {
        guard isEnabled, let engine else {
            return
        }
        await engine.handleRemoteNotification(userInfo)
    }

    /// Upload pending (already-dirty) records to iCloud.
    func syncPending() async {
        guard isEnabled, let engine else {
            return
        }
        uploadedCount = 0
        uploadGoal = counts.totalDirty
        syncStatus = .syncing(detail: "Uploading... \(counts.totalDirty) remaining")
        await engine.schedulePendingChanges()
    }

    /// Force a full sync (mark everything dirty and push)
    func forceFullSync() async {
        guard isEnabled, let engine else {
            return
        }
        syncStatus = .syncing(detail: "Marking all records dirty...")
        await engine.markAllRecordsDirty()
        counts = await engine.recordCounts()
        uploadedCount = 0
        uploadGoal = counts.totalDirty
        syncStatus = .syncing(detail: "Uploading... \(counts.totalDirty) remaining")
        await engine.schedulePendingChanges()
    }

    /// Refresh the dirty/synced record counts for display.
    func refreshCounts() async {
        guard let engine else {
            return
        }
        counts = await engine.recordCounts()
    }

    /// Fetch latest changes from CloudKit.
    func fetchChangesFromCloud() async {
        guard isEnabled, let engine else {
            return
        }
        await engine.fetchChanges()
    }

    // MARK: - CloudSyncEngineDelegate

    nonisolated func cloudSyncEngine(
        _ engine: CloudSyncEngine,
        didUpdateCounts counts: CloudSyncRecordCounts,
        batchSaved: Int
    ) {
        Task { @MainActor in
            self.counts = counts
            self.uploadedCount += batchSaved
            if counts.totalDirty == 0, self.syncStatus.isSyncing {
                self.syncStatus = .upToDate
                self.lastSyncDate = Date()
                self.uploadGoal = nil
                self.uploadedCount = 0
            } else if self.syncStatus.isSyncing {
                self.syncStatus = .syncing(
                    detail: "Uploading... \(counts.totalDirty) remaining"
                )
            }
        }
    }

    nonisolated func cloudSyncEngineDidFinishFetch(_ engine: CloudSyncEngine) {
        // No additional action needed — notification already posted by engine
    }

    // MARK: Private

    private static let migrationKey = "didMigrateToCKSyncEngine"

    private let logger = Logger(
        subsystem: "com.jsvana.CWSweep", category: "CloudSyncService"
    )
    private let enabledKey = "cloudSyncEnabled"

    private var container: ModelContainer?
    private var engine: CloudSyncEngine?
    private var changeObserver: AnyCancellable?
    private var networkMonitor: NWPathMonitor?
    private var networkMonitorQueue = DispatchQueue(label: "cloudSync.networkMonitor")
    private var wasDisconnected = false
    private var activeSessionPollTimer: Timer?

    private func startSync() async {
        guard let engine else {
            return
        }

        do {
            syncStatus = .syncing(detail: "Starting...")
            try await engine.start()

            // First-launch migration: mark all local records dirty so they push
            // to the CarrierWaveData zone (previously they were in CoreData zone)
            if !UserDefaults.standard.bool(forKey: Self.migrationKey) {
                logger.info("First launch with CKSyncEngine — marking all records dirty")
                await engine.markAllRecordsDirty()
                UserDefaults.standard.set(true, forKey: Self.migrationKey)
            }

            await engine.schedulePendingChanges()
            startNetworkMonitor()
            startActiveSessionPolling()
            counts = await engine.recordCounts()
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
        guard let engine else {
            return
        }
        await engine.stop()
        stopNetworkMonitor()
        stopActiveSessionPolling()
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
                errorMessage = "No iCloud account. Sign in to System Settings to enable sync."
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

    // MARK: - Active Session Polling

    private func startActiveSessionPolling() {
        guard activeSessionPollTimer == nil else {
            return
        }
        activeSessionPollTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            guard let self else {
                return
            }
            Task { @MainActor in
                await self.fetchChangesFromCloud()
            }
        }
        logger.info("Started active session sync polling (30s)")
    }

    private func stopActiveSessionPolling() {
        activeSessionPollTimer?.invalidate()
        activeSessionPollTimer = nil
        logger.info("Stopped active session sync polling")
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
                await self.engine?.schedulePendingChanges()
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
}
