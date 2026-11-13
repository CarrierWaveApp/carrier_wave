import AppKit
import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog
import SwiftData

// MARK: - ServerSyncService

/// CW Sweep's Carrier Wave Sync front: owns the shared `SyncKeyService`
/// (passphrase + pass driver), publishes status for the status bar, the Sync
/// panel and Settings, and schedules passes — at launch, every few minutes
/// while online, shortly after local saves, and on wake. Replaces the
/// CloudKit `CloudSyncService`.
@MainActor
@Observable
final class ServerSyncService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    enum SyncStatus: Equatable {
        case disabled
        case upToDate
        case syncing(detail: String)
        case error(String)

        // MARK: Internal

        var displayText: String {
            switch self {
            case .disabled: "Not set up"
            case .upToDate: "Up to date"
            case let .syncing(detail): detail
            case let .error(message): message
            }
        }

        var iconName: String {
            switch self {
            case .disabled: "arrow.triangle.2.circlepath.circle"
            case .upToDate: "checkmark.circle"
            case .syncing: "arrow.triangle.2.circlepath"
            case .error: "exclamationmark.triangle"
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

    static let shared = ServerSyncService()

    /// Passphrase lifecycle + pass driver (shared with iOS).
    let keyService = SyncKeyService()

    /// Signed in with a verified account AND this Mac holds the data key.
    private(set) var isEnabled = false
    private(set) var syncStatus: SyncStatus = .disabled
    private(set) var lastSyncDate: Date?
    private(set) var errorMessage: String?
    private(set) var counts: CloudSyncRecordCounts = .empty
    /// Rows queued for upload at the start of the current pass; nil when idle.
    private(set) var uploadGoal: Int?
    private(set) var uploadedCount = 0

    /// Wire triggers and run the first pass. Call once after the model
    /// container is ready.
    func configure(container: ModelContainer) {
        guard !configured else {
            return
        }
        configured = true
        self.container = container
        observeLocalSaves()
        observeWake()
        observeServerChanges()
        startPeriodicPasses()
        Task {
            await refreshEnablement()
            await refreshCounts()
            if isEnabled, SyncKeyService.isSeeded(base: ActivitiesServer.resolvedBaseURL) {
                await runPass(trigger: "launch", manual: false)
            }
        }
    }

    /// Re-check account + key state; the Settings tab calls this after
    /// sign-in, passphrase setup and forget.
    func refreshEnablement() async {
        await AccountService.shared.refresh()
        let signedIn = AccountService.shared.isSignedIn
        if signedIn {
            await keyService.refreshStatus()
        }
        let enabled = signedIn && keyService.hasLocalKey
        isEnabled = enabled
        if !enabled {
            syncStatus = .disabled
        } else if case .disabled = syncStatus {
            syncStatus = .upToDate
        }
    }

    /// One pull → push pass now (Sync Now / palette / status bar).
    func syncPending() async {
        await runPass(trigger: "manual", manual: true)
    }

    /// Mark every QSO dirty and push the whole log (manual repair).
    func forceFullSync() async {
        await runPass(trigger: "full-upload", manual: true, fullUpload: true)
    }

    /// Dirty-row counts from the Rust store (the push source).
    func refreshCounts() async {
        let dirty: Int = await Task.detached(priority: .utility) {
            guard let store = try? await CwStoreProvider.shared.store() else {
                return 0
            }
            return (try? QSOJournalStore(store: store).dirtyCount()) ?? 0
        }.value
        counts = CloudSyncRecordCounts(
            dirtyQSOs: dirty, dirtyServicePresence: 0, dirtySessions: 0,
            dirtyMetadata: 0, dirtySpots: 0, dirtyLogs: 0
        )
    }

    /// After the user wipes the local logbook: drop the per-server cursors and
    /// seeded flags so the next pass replays the whole journal into the
    /// emptied store (CAR-264's server-sync analogue), then run it.
    func resetForLocalWipe() async {
        SyncKeyService.resetForLocalWipe()
        uploadGoal = nil
        uploadedCount = 0
        await refreshCounts()
        if isEnabled {
            await runPass(trigger: "local-wipe", manual: true)
        }
    }

    // MARK: Private

    private static let periodicInterval: Duration = .seconds(5 * 60)
    private static let saveDebounce: Duration = .seconds(30)

    private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "ServerSync")

    private var configured = false
    private var container: ModelContainer?
    private var periodicTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var lastServer = ActivitiesServer.resolvedBaseURL

    /// Run one pass through the shared key service and publish its outcome.
    /// Manual passes seed the log on first use and surface errors; automatic
    /// ones stay quiet unless enrolled and seeded.
    private func runPass(trigger: String, manual: Bool, fullUpload: Bool = false) async {
        guard isEnabled else {
            if manual {
                errorMessage = "Carrier Wave Sync isn't set up on this Mac. "
                    + "Sign in and enter your passphrase in Settings → Sync."
            }
            return
        }
        guard !syncStatus.isSyncing else {
            return
        }
        await refreshCounts()
        uploadGoal = counts.totalDirty
        uploadedCount = 0
        errorMessage = nil
        syncStatus = .syncing(detail: fullUpload ? "Uploading full log…" : "Syncing…")
        let phaseWatcher = Task { [weak self] in
            // Mirror the key service's phase into the status detail.
            guard let self else {
                return
            }
            while !Task.isCancelled {
                let label = keyService.phase.label
                if !label.isEmpty, syncStatus.isSyncing {
                    syncStatus = .syncing(detail: label)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        let success = fullUpload ? await keyService.uploadFullLog() : await keyService.runSyncOnce()
        phaseWatcher.cancel()
        if success {
            if let summary = keyService.lastSyncSummary {
                uploadedCount = summary.pushed
                uploadGoal = summary.pushed > 0 ? summary.pushed : nil
                logger.info("Sync (\(trigger)): pushed \(summary.pushed), pulled \(summary.pulled)")
            }
            lastSyncDate = Date()
            syncStatus = .upToDate
        } else {
            let message = keyService.lastError ?? "Sync failed."
            errorMessage = message
            syncStatus = .error(message)
            uploadGoal = nil
            logger.error("Sync (\(trigger)) failed: \(message)")
        }
        await refreshCounts()
    }

    private func startPeriodicPasses() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.periodicInterval)
                guard let self, !Task.isCancelled else {
                    return
                }
                await runPass(trigger: "periodic", manual: false)
            }
        }
    }

    /// Local saves (logging, edits, imports) schedule a pass after a quiet
    /// period so a burst of QSOs uploads once.
    private func observeLocalSaves() {
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleDebouncedPass() }
        }
    }

    private func scheduleDebouncedPass() {
        guard isEnabled else {
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard let self, !Task.isCancelled else {
                return
            }
            await runPass(trigger: "local-change", manual: false)
        }
    }

    /// The developer override (General → Server) moving the base URL changes
    /// which account session, data key, cursor and escrow apply; re-evaluate
    /// so the status reflects the new server instead of mixing two.
    private func observeServerChanges() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lastServer != ActivitiesServer.resolvedBaseURL else {
                    return
                }
                self.lastServer = ActivitiesServer.resolvedBaseURL
                self.errorMessage = nil
                await self.refreshEnablement()
                await self.refreshCounts()
            }
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.runPass(trigger: "wake", manual: false) }
        }
    }
}
