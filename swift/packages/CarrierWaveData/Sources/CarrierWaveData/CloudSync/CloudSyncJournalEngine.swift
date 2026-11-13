import CarrierWaveCore
import CloudKit
import Foundation
import OSLog
import SwiftData

// MARK: - CloudSyncJournalDelegate

/// Delegate protocol for the journal-based sync engine.
public protocol CloudSyncJournalDelegate: AnyObject, Sendable {
    @MainActor func journalEngine(
        _ engine: CloudSyncJournalEngine,
        didUpdateStatus status: String
    )
    @MainActor func journalEngineDidFinishSync(
        _ engine: CloudSyncJournalEngine
    )
    @MainActor func journalEngine(
        _ engine: CloudSyncJournalEngine,
        didLogEvent event: CloudSyncEvent
    )
    /// Number of entity-level operations confirmed-saved in a single
    /// outbound CK round trip. Lets the service advance an aggregate
    /// progress counter for the Settings UI without exposing CKRecord
    /// internals to the main actor.
    @MainActor func journalEngine(
        _ engine: CloudSyncJournalEngine,
        didConfirmOperations count: Int
    )
}

public extension CloudSyncJournalDelegate {
    @MainActor func journalEngine(
        _: CloudSyncJournalEngine,
        didConfirmOperations _: Int
    ) {}
}

// MARK: - CloudSyncJournalEngine

/// Journal-based sync engine that replaces per-record CKSyncEngine sync.
/// Instead of one CKRecord per QSO, batches changes into journal entries
/// and uses SQLite snapshots for initial device bootstrap.
///
/// Architecture:
/// - Outbound: dirty records → extract fields → JSON journal CKRecord
/// - Inbound: journal CKRecords → decode JSON → apply to SwiftData
/// - Bootstrap: download SQLite snapshot → apply journal tail
public actor CloudSyncJournalEngine: CKSyncEngineDelegate {
    // MARK: Lifecycle

    /// Defers `ModelContext(container)` to `start()` so that synchronous
    /// construction from `MainActor.configure(container:)` doesn't block the
    /// main thread during app launch / background-entry (CAR-244 watchdog).
    public init(container: ModelContainer) {
        self.container = container
        snapshotService = CloudSyncSnapshotService(container: container)
    }

    // MARK: Public

    public weak var delegate: CloudSyncJournalDelegate?

    public let eventLog = CloudSyncEventLog()
    public let snapshotService: CloudSyncSnapshotService

    public func setDelegate(_ delegate: CloudSyncJournalDelegate?) {
        self.delegate = delegate
    }

    /// Start the journal sync engine.
    ///
    /// When `CwStoreSyncMode == .serverSync`, the CloudKit `CKSyncEngine` is
    /// not constructed at all; a single server-sync pass runs instead. The
    /// persisted CK engine state is left untouched so flipping back to `.off`
    /// resumes CloudKit exactly where it left off.
    public func start() async throws {
        if await routeToServerSyncIfEnabled() {
            return
        }
        ensureModelContext()
        await resolveQSOJournalStore()
        await eventLog.load()
        let state = try loadSyncState()
        let isFirstSync = state == nil

        let config = CKSyncEngine.Configuration(
            database: ckDatabase(),
            stateSerialization: state,
            delegate: self
        )
        syncEngine = CKSyncEngine(config)
        try await ensureZoneExists()

        if isFirstSync, !localDatabaseHasData() {
            await attemptSnapshotBootstrap()
        }

        try await syncEngine?.fetchChanges()
    }

    /// Stop the sync engine.
    public func stop() async {
        syncEngine = nil
    }

    /// Reset the engine so the next `start()` behaves like a fresh install:
    /// downloads the latest cloud snapshot and re-fetches every journal
    /// record in the zone. Called by the user-initiated "Clear All QSOs"
    /// flow on both iOS and macOS — without this reset, the persisted
    /// `CKSyncEngine.State` change token would cause `fetchChanges()` to
    /// skip already-applied journals after the local store is emptied, so
    /// the cloud-backed logbook would never reappear (CAR-264).
    ///
    /// Clears, in order: the in-flight engine, the persisted engine state,
    /// this device's `cloudSyncDeviceId` (so journals authored by the
    /// pre-wipe identity get re-applied alongside the snapshot), the
    /// outbound sequence counter, the snapshot-upload throttle, the
    /// in-memory pending records, and the cached model context (the
    /// caller usually mutated the underlying store, so the context's
    /// row cache is now stale).
    public func resetForLocalWipe() async {
        await stop()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: "cloudSyncDeviceId")
        defaults.removeObject(forKey: "journalSequenceNumber")
        defaults.removeObject(forKey: "cloudSyncLastSnapshotUpload")
        pendingJournalRecords.removeAll()
        modelContext = nil
        qsoJournalStore = nil // re-resolved by start()
        try? await start()
    }

    /// Collect dirty records and schedule journal entries for upload.
    /// In server-sync mode the Rust store's own dirty flags drive the push —
    /// no CK journal records are built.
    public func schedulePendingChanges() async {
        if await routeToServerSyncIfEnabled() {
            return
        }
        // CAR-244: skip outbound scheduling while inbound apply is in flight
        // to break the inbound→didSave→outbound→echo loop.
        guard !isApplyingInbound else {
            return
        }
        // Skip re-collection while previously-built journal records are still
        // in flight. Without this guard, every successful batch save triggers
        // `ModelContext.didSave` → observer reschedule → full re-scan of all
        // dirty records (45k+ for force-full-sync), creating a CPU storm that
        // burns the device battery without making progress. The next save
        // after `pendingJournalRecords` drains will pick up whatever's still
        // dirty.
        guard pendingJournalRecords.isEmpty else {
            return
        }
        ensureModelContext()
        let operations = collectDirtyOperations()
        guard !operations.isEmpty else {
            return
        }

        let batches = stride(
            from: 0, to: operations.count,
            by: JournalPayload.maxOperationsPerEntry
        ).map { idx in
            Array(operations[idx ..< min(
                idx + JournalPayload.maxOperationsPerEntry,
                operations.count
            )])
        }

        for batch in batches {
            let seq = nextSequenceNumber()
            let payload = JournalPayload(
                deviceId: deviceId,
                sequenceNumber: seq,
                operations: batch
            )
            let record = payload.toCKRecord()
            pendingJournalRecords.append(record)
        }

        if let engine = syncEngine {
            let pendingChanges = pendingJournalRecords.map { record in
                CKSyncEngine.PendingRecordZoneChange.saveRecord(
                    record.recordID
                )
            }
            engine.state.add(pendingRecordZoneChanges: pendingChanges)
            logger.info(
                "Scheduled \(operations.count) ops in \(batches.count) journal entries"
            )
        }
    }

    /// Fetch latest changes from CloudKit (or, in server-sync mode, run one
    /// pull+push pass against the E2E server).
    public func fetchChanges() async {
        if await routeToServerSyncIfEnabled() {
            return
        }
        try? await syncEngine?.fetchChanges()
    }

    /// Mark every syncable record dirty so the next outbound batch re-uploads
    /// the entire log. Used by "Force Full Sync" in Settings and on iCloud
    /// account sign-in to push the local log to the new account.
    public func markAllRecordsDirty() {
        ensureModelContext()
        markAllRecordsDirtyImpl()
    }

    /// Upload a snapshot if enough time has passed.
    public func uploadSnapshotIfNeeded(
        storeURL: URL, qsoCount: Int
    ) async {
        guard await snapshotService.shouldUploadSnapshot() else {
            return
        }
        do {
            let result = try await snapshotService.uploadSnapshot(
                storeURL: storeURL, qsoCount: qsoCount
            )
            let event = CloudSyncEvent(
                category: .upload,
                detail: "Snapshot uploaded (\(qsoCount) QSOs)",
                recordCount: qsoCount,
                duration: result.duration,
                byteCount: result.fileSize
            )
            await eventLog.append(event)
        } catch {
            logger.error(
                "Snapshot upload failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - CKSyncEngineDelegate

    nonisolated public func handleEvent(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        switch event {
        case let .stateUpdate(update):
            await saveSyncState(update.stateSerialization)
        case let .accountChange(change):
            await handleAccountChange(change)
        case let .fetchedRecordZoneChanges(changes):
            await handleInboundChanges(changes)
        case .didFetchChanges:
            await delegate?.journalEngineDidFinishSync(self)
        case let .sentRecordZoneChanges(sent):
            await handleSentChanges(sent)
        case .fetchedDatabaseChanges,
             .sentDatabaseChanges,
             .willFetchChanges,
             .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges,
             .willSendChanges,
             .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    nonisolated public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await buildNextBatch(engine: syncEngine)
    }

    /// Compute dirty/synced record counts using a fresh context to avoid stale caches.
    public func recordCounts() -> CloudSyncRecordCounts {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // QSO dirty count comes from the store once authority is flipped — the
        // journal clears the store's flag, not SwiftData's, so a SwiftData count
        // would grow stale.
        let dirtyQSOs: Int = if let qsoJournalStore {
            (try? qsoJournalStore.dirtyCount()) ?? 0
        } else {
            (try? ctx.boundedCount(
                QSO.self,
                predicate: #Predicate { $0.cloudDirtyFlag == true }
            )) ?? 0
        }
        let dirtyPresence = (try? ctx.boundedCount(
            ServicePresence.self,
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )) ?? 0
        let dirtySessions = (try? ctx.fetchCount(
            FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.cloudDirtyFlag == true }
            )
        )) ?? 0
        let dirtyMetadata = (try? ctx.fetchCount(
            FetchDescriptor<ActivationMetadata>(
                predicate: #Predicate { $0.cloudDirtyFlag == true }
            )
        )) ?? 0
        let dirtySpots = (try? ctx.fetchCount(
            FetchDescriptor<SessionSpot>(
                predicate: #Predicate { $0.cloudDirtyFlag == true }
            )
        )) ?? 0
        let dirtyLogs = (try? ctx.fetchCount(
            FetchDescriptor<ActivityLog>(
                predicate: #Predicate { $0.cloudDirtyFlag == true }
            )
        )) ?? 0

        return CloudSyncRecordCounts(
            dirtyQSOs: dirtyQSOs,
            dirtyServicePresence: dirtyPresence,
            dirtySessions: dirtySessions,
            dirtyMetadata: dirtyMetadata,
            dirtySpots: dirtySpots,
            dirtyLogs: dirtyLogs
        )
    }

    // MARK: Internal

    let container: ModelContainer
    var modelContext: ModelContext!
    var syncEngine: CKSyncEngine?

    /// When QSO authority has been flipped to the Rust store (`CwStoreQSOMode ==
    /// .on`), the QSO half of every store-access touchpoint (outbound dirty
    /// collection + clear, inbound apply/delete, mark-all-dirty, dirty count,
    /// bootstrap gate) routes through this seam instead of `modelContext`. `nil`
    /// when the flag is `.off`/`.shadow` — then the SwiftData path runs unchanged.
    /// Resolved once in `start()` so the sync hot-paths stay synchronous; the
    /// other synced entities (ServicePresence/Session/etc.) stay on SwiftData
    /// until their own Phase-2 flips.
    var qsoJournalStore: QSOJournalStore?

    /// CAR-244: set true while `handleInboundChanges` is mutating + saving the
    /// model context, so the `ModelContext.didSave` observer in
    /// `CloudSyncService` doesn't reschedule outbound right after we just
    /// applied a remote batch (inbound→outbound echo loop).
    var isApplyingInbound = false

    /// LoggingSession UUIDs upserted during the current inbound batch.
    /// Drained at the end of `handleInboundChanges` to fan out a
    /// `cwLoggingSessionRemotelyChanged` notification.
    var touchedSessionIDsThisBatch: Set<UUID> = []

    let logger = Logger(
        subsystem: "com.jsvana.FullDuplex", category: "JournalSync"
    )

    /// Pending journal CKRecords waiting to be sent.
    var pendingJournalRecords: [CKRecord] = []

    let stateKey = "journalSyncEngineState"

    /// Phase 7.2 seam — see `setServerSyncRunner(_:)` in
    /// `CloudSyncJournalEngine+ServerSync.swift`.
    var serverSyncRunner: ServerSyncRunner?

    /// Lazy-init to keep actor `init` cheap on the calling thread.
    func ensureModelContext() {
        if modelContext == nil {
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            modelContext = ctx
        }
    }

    // MARK: Private

    private var deviceId: String {
        if let existing = UserDefaults.standard.string(
            forKey: "cloudSyncDeviceId"
        ) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "cloudSyncDeviceId")
        return newId
    }

    private func nextSequenceNumber() -> Int64 {
        let key = "journalSequenceNumber"
        let current = UserDefaults.standard.integer(forKey: key)
        let next = Int64(current) + 1
        UserDefaults.standard.set(Int(next), forKey: key)
        return next
    }

    private func ckDatabase() -> CKDatabase {
        CKContainer(
            identifier: "iCloud.com.jsvana.FullDuplex"
        ).privateCloudDatabase
    }

    private func ensureZoneExists() async throws {
        guard let engine = syncEngine else {
            return
        }
        let zone = CKRecordZone(zoneID: CloudSyncZone.zoneID)
        engine.state.add(pendingDatabaseChanges: [
            .saveZone(zone),
        ])
    }

    private func loadSyncState() throws
        -> CKSyncEngine.State.Serialization?
    {
        guard let data = UserDefaults.standard.data(
            forKey: stateKey
        ) else {
            return nil
        }
        return try JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self, from: data
        )
    }

    private func saveSyncState(
        _ state: CKSyncEngine.State.Serialization
    ) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: stateKey)
        } catch {
            logger.error("Failed to save journal sync state: \(error)")
        }
    }

    private func handleAccountChange(
        _ change: CKSyncEngine.Event.AccountChange
    ) {
        switch change.changeType {
        case .signIn,
             .switchAccounts:
            Task { await schedulePendingChanges() }
        case .signOut:
            break
        @unknown default:
            break
        }
    }

    /// Check if the local database already has QSOs (e.g., from legacy sync).
    /// If so, skip snapshot bootstrap — the data is already here.
    private func localDatabaseHasData() -> Bool {
        if let qsoJournalStore {
            return (try? qsoJournalStore.hasVisibleQSO()) ?? false
        }
        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate { !$0.isHidden }, limit: 1
        )
        return ((try? modelContext.boundedFetch(desc))?.isEmpty == false)
    }
}

// MARK: - QSO seam binding (Phase 1c)

extension CloudSyncJournalEngine {
    /// Bind (or clear) the QSO seam from the current rollout flag. Called from
    /// `start()`.
    ///
    /// Gated on BOTH `CwStoreQSOMode == .on` AND a completed SwiftData→store
    /// import: app launch fires `applyQSOMirrorMode` (which runs the import) and
    /// the sync service's `start()` concurrently, with no ordering guarantee. If
    /// the import hasn't finished, the store is empty/partial — pointing sync at
    /// it would mis-bootstrap and drop the outbound backlog. Until then the
    /// SwiftData path runs (seam stays `nil`); the next `start()` after the import
    /// completes binds the seam.
    func resolveQSOJournalStore() async {
        guard CwStoreQSOMode.current == .on,
              CwStoreImportCoordinator.hasEverCompletedImport()
        else {
            qsoJournalStore = nil
            return
        }
        if let store = try? await CwStoreProvider.shared.store() {
            qsoJournalStore = QSOJournalStore(store: store)
        } else {
            qsoJournalStore = nil
        }
    }
}
