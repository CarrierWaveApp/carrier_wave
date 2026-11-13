import Foundation

/// Background service that periodically triggers `SyncService.syncAll()` while
/// the app is in the foreground. Off by default — users opt in via Settings.
///
/// Follows the `SolarPollingService` pattern: `@MainActor @Observable` singleton
/// with a Task-based poll loop.
@MainActor
@Observable
final class AutoSyncService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = AutoSyncService()

    static let enabledKey = "autoSyncEnabled"
    static let intervalKey = "autoSyncIntervalMinutes"

    /// Available interval choices (in minutes) for the settings picker.
    static let intervalOptions = [5, 15, 30, 60]

    /// Default interval when no preference is set.
    static let defaultIntervalMinutes = 15

    /// Whether the auto-sync loop is currently running.
    private(set) var isRunning = false

    /// Configure the service with the app's sync service. Call once at startup.
    func configure(syncService: SyncService) {
        self.syncService = syncService
    }

    /// Resume the poll loop (call when scene becomes `.active`).
    func resume() {
        guard syncService != nil, !isRunning else {
            return
        }
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        guard enabled else {
            return
        }
        startLoop()
    }

    /// Pause the poll loop (call when scene becomes `.inactive` or `.background`).
    func pause() {
        stopLoop()
    }

    /// Restart the loop if the user toggled the setting while the app is active.
    func settingsDidChange() {
        stopLoop()
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if enabled {
            startLoop()
        }
    }

    // MARK: Private

    /// Minimum time since last sync before auto-sync will fire (seconds).
    /// Prevents rapid re-sync if the user just triggered a manual sync.
    private static let cooldownSeconds: TimeInterval = 120

    private weak var syncService: SyncService?

    private var intervalTicks: Int {
        let minutes = UserDefaults.standard.integer(forKey: Self.intervalKey)
        return Self.intervalOptions.contains(minutes) ? minutes : Self.defaultIntervalMinutes
    }

    private func startLoop() {
        guard !isRunning else {
            return
        }
        isRunning = true

        let interval = intervalTicks
        PollingCoordinator.shared.register(
            id: "autoSync",
            every: interval,
            fireImmediately: false
        ) { [weak self] in
            // Re-check setting each invocation
            let enabled = UserDefaults.standard.bool(forKey: AutoSyncService.enabledKey)
            guard enabled else {
                await MainActor.run { self?.stopLoop() }
                return
            }
            await self?.syncIfReady()
        }
    }

    private func stopLoop() {
        isRunning = false
        PollingCoordinator.shared.unregister(id: "autoSync")
    }

    private func syncIfReady() async {
        guard let syncService else {
            return
        }

        // Skip if a sync is already in progress
        guard !syncService.isSyncing else {
            return
        }

        // Skip if a confirmation dialog is pending (would block)
        guard syncService.importConfirmation == nil,
              syncService.exportConfirmation == nil
        else {
            return
        }

        // Cooldown: skip if last sync was very recent
        if let lastSync = syncService.lastSyncDate,
           Date().timeIntervalSince(lastSync) < Self.cooldownSeconds
        {
            return
        }

        _ = try? await syncService.syncAll()
    }
}
