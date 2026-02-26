import CarrierWaveCore
import CloudKit
import Foundation
import os
import SwiftData

/// Background actor implementing CKSyncEngineDelegate.
/// Handles the heavy lifting: record mapping, conflict resolution, and deduplication.
/// Uses a background ModelContext per performance rules.
actor CloudSyncEngine: CKSyncEngineDelegate {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
        modelContext = ModelContext(container)
        modelContext.autosaveEnabled = false
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

    /// Start the CKSyncEngine with persisted state
    func start() async throws {
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
    func stop() async {
        // State is persisted via stateUpdate events during operation
        syncEngine = nil
    }

    /// Schedule pending changes for records that have dirty flags set
    func schedulePendingChanges() async {
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
    func handleRemoteNotification(
        _ userInfo: sending [AnyHashable: Any]
    ) async {
        // CKSyncEngine processes the notification internally
        // Just trigger a fetch
        try? await syncEngine?.fetchChanges()
    }

    /// Fetch latest changes from CloudKit (used for foreground re-sync)
    func fetchChanges() async {
        try? await syncEngine?.fetchChanges()
    }

    // MARK: - CKSyncEngineDelegate

    nonisolated func handleEvent(
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
            break // We don't create/delete zones dynamically

        case let .sentRecordZoneChanges(sentChanges):
            await handleSentRecordZoneChanges(sentChanges)

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
            break

        @unknown default:
            logger.warning("Unknown CKSyncEngine event: \(String(describing: event))")
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await buildNextChangeBatch(context, engine: syncEngine)
    }
}
