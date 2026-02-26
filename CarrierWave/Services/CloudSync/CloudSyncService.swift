import CloudKit
import Combine
import Foundation
import Network
import os
import SwiftData

// MARK: - CloudSyncService

/// @MainActor service that owns the CKSyncEngine and publishes sync status for UI.
/// Observes local data changes and feeds pending record IDs to the engine.
@MainActor
class CloudSyncService: ObservableObject {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CloudSyncService()

    /// Whether iCloud QSO sync is enabled by the user
    @Published var isEnabled: Bool = false

    /// Current sync status for UI display
    @Published var syncStatus: SyncStatus = .disabled

    /// Number of pending records waiting to sync
    @Published var pendingCount: Int = 0

    /// Last successful sync timestamp
    @Published var lastSyncDate: Date?

    /// Persistent error message for settings display
    @Published var errorMessage: String?

    /// iCloud account status
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine

    // MARK: - Public API

    /// Configure and start the sync service.
    /// Call this from the app entry point after ModelContainer is ready.
    func configure(container: ModelContainer) {
        self.container = container
        engine = CloudSyncEngine(container: container)

        // Load persisted enabled state
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)

        // Observe local data changes
        setupChangeObserver()

        // Observe active logging session to enable/disable polling
        setupActiveSessionObserver()

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

    /// Force a full sync (mark everything dirty and push)
    func forceFullSync() async {
        guard isEnabled, let engine else {
            return
        }
        syncStatus = .syncing(detail: "Full sync...")
        await engine.schedulePendingChanges()
    }

    /// Fetch latest changes from CloudKit.
    /// Called on foreground re-entry and network recovery for seamless cross-device sync.
    func fetchChangesFromCloud() async {
        guard isEnabled, let engine else {
            return
        }
        await engine.fetchChanges()
    }

    /// Start periodic sync polling for active logging sessions.
    /// Polls every 30s so QSOs logged on another device appear quickly.
    func startActiveSessionPolling() {
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

    /// Stop periodic sync polling when logging session ends.
    func stopActiveSessionPolling() {
        activeSessionPollTimer?.invalidate()
        activeSessionPollTimer = nil
        logger.info("Stopped active session sync polling")
    }

    // MARK: Private

    private let logger = Logger(
        subsystem: "com.jsvana.FullDuplex", category: "CloudSyncService"
    )
    private let enabledKey = "cloudSyncEnabled"

    private var container: ModelContainer?
    private var engine: CloudSyncEngine?
    private var changeObserver: AnyCancellable?
    private var networkMonitor: NWPathMonitor?
    private var networkMonitorQueue = DispatchQueue(label: "cloudSync.networkMonitor")
    private var wasDisconnected = false
    private var activeSessionPollTimer: Timer?
    private var activeSessionObserver: AnyCancellable?

    private func startSync() async {
        guard let engine else {
            return
        }

        do {
            syncStatus = .syncing(detail: "Starting...")
            try await engine.start()
            await engine.schedulePendingChanges()
            startNetworkMonitor()
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
        pendingCount = 0
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

    // MARK: - Active Session Polling

    private func setupActiveSessionObserver() {
        let key = "activeLoggingSessionId"
        // Check current state on setup
        if UserDefaults.standard.string(forKey: key) != nil, isEnabled {
            startActiveSessionPolling()
        }
        // Observe future changes via UserDefaults KVO
        activeSessionObserver = UserDefaults.standard.publisher(for: \.activeLoggingSessionId)
            .sink { [weak self] value in
                guard let self, isEnabled else {
                    return
                }
                if value != nil {
                    startActiveSessionPolling()
                } else {
                    stopActiveSessionPolling()
                }
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
        // Observe ModelContext saves to detect local changes
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

    var isSyncing: Bool {
        syncStatus.isSyncing
    }
}

// MARK: - UserDefaults KVO for Active Session

extension UserDefaults {
    /// KVO-observable property for the active logging session ID.
    /// Used by CloudSyncService to start/stop polling during active sessions.
    @objc dynamic var activeLoggingSessionId: String? {
        string(forKey: "activeLoggingSessionId")
    }
}
