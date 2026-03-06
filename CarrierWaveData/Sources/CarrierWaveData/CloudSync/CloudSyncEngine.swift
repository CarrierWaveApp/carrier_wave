import CloudKit
import Foundation
import os
import SwiftData

// MARK: - CloudSyncEngineDelegate

/// Delegate protocol to decouple the engine from app-specific CloudSyncService.
public protocol CloudSyncEngineDelegate: AnyObject, Sendable {
    @MainActor func cloudSyncEngine(
        _ engine: CloudSyncEngine,
        didUpdateCounts counts: CloudSyncRecordCounts,
        batchSaved: Int
    )
    @MainActor func cloudSyncEngineDidFinishFetch(_ engine: CloudSyncEngine)
}

// MARK: - CloudSyncEngine

/// Background actor implementing CKSyncEngineDelegate.
/// Handles the heavy lifting: record mapping, conflict resolution, and deduplication.
/// Uses a background ModelContext per performance rules.
public actor CloudSyncEngine: CKSyncEngineDelegate {
    // MARK: Lifecycle

    public init(container: ModelContainer) {
        self.container = container
        modelContext = ModelContext(container)
        modelContext.autosaveEnabled = false
    }

    // MARK: Public

    public weak var delegate: CloudSyncEngineDelegate?

    public func setDelegate(_ delegate: CloudSyncEngineDelegate?) {
        self.delegate = delegate
    }

    /// Start the CKSyncEngine with persisted state
    public func start() async throws {
        let state = try await loadSyncState()
        let config = CKSyncEngine.Configuration(
            database: CKContainer(
                identifier: "iCloud.com.jsvana.FullDuplex"
            ).privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        syncEngine = CKSyncEngine(config)

        // Ensure the zone exists
        try await ensureZoneExists()

        // Schedule initial fetch
        try await syncEngine?.fetchChanges()
    }

    /// Stop the sync engine
    public func stop() async {
        syncEngine = nil
    }

    /// Schedule pending changes for records that have dirty flags set
    public func schedulePendingChanges() async {
        guard let engine = syncEngine else {
            return
        }

        let pendingChanges = collectDirtyRecordIDs()
        if !pendingChanges.isEmpty {
            engine.state.add(pendingRecordZoneChanges: pendingChanges)
            logger.info("Scheduled \(pendingChanges.count) pending changes for sync")
        }
    }

    /// Forward a remote notification to the sync engine
    public func handleRemoteNotification(
        _ userInfo: sending [AnyHashable: Any]
    ) async {
        try? await syncEngine?.fetchChanges()
    }

    /// Fetch latest changes from CloudKit (used for foreground re-sync)
    public func fetchChanges() async {
        try? await syncEngine?.fetchChanges()
    }

    /// Mark all local records as dirty so they get pushed to CloudKit
    public func markAllRecordsDirty() {
        markAllRecordsDirtyImpl()
    }

    /// Count dirty (pending upload) and synced records per entity type.
    public func recordCounts() -> CloudSyncRecordCounts {
        recordCountsImpl()
    }

    // MARK: - CKSyncEngineDelegate

    nonisolated public func handleEvent(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        switch event {
        case let .stateUpdate(stateUpdate):
            await saveSyncState(stateUpdate.stateSerialization)

        case let .accountChange(change):
            await handleAccountChange(change)

        case let .fetchedDatabaseChanges(changes):
            await handleFetchedDatabaseChanges(changes)

        case let .fetchedRecordZoneChanges(changes):
            await handleFetchedRecordZoneChanges(changes)

        case .sentDatabaseChanges:
            break

        case let .sentRecordZoneChanges(sentChanges):
            await handleSentRecordZoneChanges(sentChanges)
            await postSendProgress(batchSaved: sentChanges.savedRecords.count)

        case .willFetchChanges:
            break

        case .willFetchRecordZoneChanges:
            break

        case let .didFetchRecordZoneChanges(fetchChanges):
            await handleDidFetchRecordZoneChanges(fetchChanges)

        case .didFetchChanges:
            await postSyncNotification()

        case .willSendChanges:
            break

        case .didSendChanges:
            await postSendProgress()

        @unknown default:
            await logUnknownEvent(event)
        }
    }

    nonisolated public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await buildNextChangeBatch(context, engine: syncEngine)
    }

    // MARK: Internal

    // MARK: Internal (accessed by extension files)

    let container: ModelContainer
    var modelContext: ModelContext
    var syncEngine: CKSyncEngine?
    let logger = Logger(subsystem: "com.jsvana.FullDuplex", category: "CloudSync")

    /// Limit batch sizes for CloudKit
    let sendBatchSize = 100
    /// State persistence key
    let stateKey = "cloudSyncEngineState"

    // MARK: Private

    private func logUnknownEvent(_ event: CKSyncEngine.Event) {
        logger.warning("Unknown CKSyncEngine event: \(String(describing: event))")
    }
}
