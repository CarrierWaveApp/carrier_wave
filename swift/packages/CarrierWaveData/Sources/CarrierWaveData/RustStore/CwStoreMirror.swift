import CarrierWaveCore
import Foundation
import SwiftData

// Observes `ModelContext` save notifications and dual-writes QSO changes into
// the Rust cw-store. Inserts/updates become upserts; deletes are captured during
// `willSave` (while the models are still alive) and applied during `didSave`.
//
// THREADING (important): we observe with `object: nil`, so the notifications fire
// on the executor of WHICHEVER `ModelContext` is saving — the main context, but
// also background `ModelContext`s used by sync, repairs, and imports. The handler
// therefore must NOT assume the main actor (`MainActor.assumeIsolated` off-main is
// a hard crash — that was an earlier bug). Instead the class is thread-agnostic:
// it runs on the arriving thread, projects the changed QSOs there (the models
// belong to that context's executor, so reading them synchronously is correct),
// and buffers value-typed results under an `NSLock` keyed by the context. The
// actual store writes are handed to the serial off-main `CwStoreMirrorActor`.
//
// `willSave` and `didSave` for one save fire synchronously on the same thread, so
// per-context the buffer is filled then flushed in order; the lock guards against
// different contexts saving concurrently on different threads.
//
// Reads only from SwiftData — the app's state is never mutated.

// MARK: - CwStoreMirrorRegistry

/// Main-actor handle to the live mirror so read paths (e.g. the Logbook list in
/// `.on` mode) can `await CwStoreMirrorRegistry.current?.drain()` as a
/// read-after-write barrier. Set by each app's mirror-mode setup
/// (`CarrierWaveApp.applyQSOMirrorMode` on iOS, `CWSweepApp` on macOS) when the
/// mirror starts/stops. `weak` — the app holds the strong reference.
@MainActor
public enum CwStoreMirrorRegistry {
    public static weak var current: CwStoreMirror?
}

// MARK: - CwStoreMirror

/// `nonisolated` (the iOS target defaults to `@MainActor`) because the save
/// observers fire on background `ModelContext` executors, not the main actor.
/// `@unchecked Sendable`: mutable state (`pending`, `lastWrite`) is guarded by
/// `lock`; observer tokens are only touched from `start()`/`stop()`.
nonisolated public final class CwStoreMirror: @unchecked Sendable {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        mirrorActor = CwStoreMirrorActor(store: store)
    }

    // MARK: Public

    public func start() {
        guard willSaveObserver == nil else {
            return
        }
        let center = NotificationCenter.default
        // queue: nil → the handler runs synchronously on the saving context's
        // thread. We do NOT hop to the main actor.
        willSaveObserver = center.addObserver(
            forName: ModelContext.willSave,
            object: nil,
            queue: nil
        ) { [weak self] note in
            self?.handleWillSave(note)
        }
        didSaveObserver = center.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: nil
        ) { [weak self] note in
            self?.handleDidSave(note)
        }
    }

    public func stop() {
        let center = NotificationCenter.default
        if let obs = willSaveObserver {
            center.removeObserver(obs)
            willSaveObserver = nil
        }
        if let obs = didSaveObserver {
            center.removeObserver(obs)
            didSaveObserver = nil
        }
        lock.withLock { pending.removeAll() }
    }

    /// Barrier: awaits the most recent dispatched write, then the actor's queue,
    /// so callers (e.g. the `.on` read path, or tests) never observe a stale
    /// store while a mirror write is in flight.
    public func drain() async {
        let task = lock.withLock { lastWrite }
        await task?.value
        await mirrorActor.drain()
    }

    /// Raise the seam-origin guard before a seam-driven `ModelContext.save()`.
    /// Keyed by the saving context: suppressing one context's seam save must NOT
    /// suppress a *concurrent* save on a different context (a background-context
    /// seam write must not silently drop a main-context save's changes from
    /// cw-store). `ObjectIdentifier(ModelContext)` is stable — `ModelContext` is a
    /// class, and `willSave`/`didSave` fire with the same instance as `note.object`.
    public func beginSeamWrite(for context: ModelContext) {
        let key = ObjectIdentifier(context)
        lock.withLock { seamWriteDepth[key, default: 0] += 1 }
    }

    /// Lower the seam-origin guard after a seam-driven save completes.
    public func endSeamWrite(for context: ModelContext) {
        let key = ObjectIdentifier(context)
        lock.withLock {
            let next = (seamWriteDepth[key] ?? 0) - 1
            if next <= 0 {
                seamWriteDepth.removeValue(forKey: key)
            } else {
                seamWriteDepth[key] = next
            }
        }
    }

    // MARK: Private

    private struct Pending {
        var upserts: [FfiQso] = []
        var deletes: [String] = []
        var spUpserts: [FfiServicePresence] = []
        var spDeletes: [String] = []
        /// Non-QSO/ServicePresence entity writes, captured as value-typed closures
        /// (projected on the saving context's thread) and replayed on the actor.
        var entityWrites: [@Sendable (FieldStore) -> Void] = []

        var isEmpty: Bool {
            upserts.isEmpty && deletes.isEmpty && spUpserts.isEmpty && spDeletes.isEmpty
                && entityWrites.isEmpty
        }
    }

    private let mirrorActor: CwStoreMirrorActor
    private let lock = NSLock()

    /// Per-context buffer, keyed by the saving `ModelContext`'s identity. Filled
    /// in `willSave`, flushed in `didSave`. Guarded by `lock`.
    private var pending: [ObjectIdentifier: Pending] = [:]

    /// Most recent dispatched write task; awaited by `drain()`. Guarded by `lock`.
    private var lastWrite: Task<Void, Never>?

    /// Per-context depth: nonzero for a context while one of its seam writes is
    /// committing. When set, `capture` skips that context's changes so the seam's
    /// SwiftData save does not echo back into cw-store (the seam already wrote
    /// cw-store canonically). Guarded by `lock`. Keyed by context so a background
    /// seam write can't suppress a concurrent main-context save. A depth counter
    /// (not a Bool) is robust to nested writes on the same context.
    private var seamWriteDepth: [ObjectIdentifier: Int] = [:]

    private var willSaveObserver: NSObjectProtocol?
    private var didSaveObserver: NSObjectProtocol?

    /// Snapshot pending QSO and ServicePresence changes from the context BEFORE
    /// the commit, on the context's own thread. `insertedModelsArray` /
    /// `changedModelsArray` / `deletedModelsArray` are populated regardless of
    /// storage backend (unlike the notification's `userInfo`, which is empty for
    /// in-memory stores).
    private func handleWillSave(_ note: Notification) {
        guard let context = note.object as? ModelContext else {
            return
        }
        let batch = capture(from: context)
        guard !batch.isEmpty else {
            return
        }
        let key = ObjectIdentifier(context)
        lock.withLock {
            pending[key, default: Pending()].upserts.append(contentsOf: batch.upserts)
            pending[key, default: Pending()].deletes.append(contentsOf: batch.deletes)
            pending[key, default: Pending()].spUpserts.append(contentsOf: batch.spUpserts)
            pending[key, default: Pending()].spDeletes.append(contentsOf: batch.spDeletes)
            pending[key, default: Pending()].entityWrites.append(contentsOf: batch.entityWrites)
        }
    }

    /// Project all changed QSOs and ServicePresence records from `context` into
    /// value-typed `Pending`. Called synchronously on the saving context's thread;
    /// no main-actor assumption is made.
    private func capture(from context: ModelContext) -> Pending {
        let key = ObjectIdentifier(context)
        if lock.withLock({ (seamWriteDepth[key] ?? 0) > 0 }) {
            return Pending()
        }
        var batch = Pending()
        for case let qso as QSO in context.insertedModelsArray {
            batch.upserts.append(SwiftDataStoreImporter.project(qso))
        }
        for case let qso as QSO in context.changedModelsArray {
            batch.upserts.append(SwiftDataStoreImporter.project(qso))
        }
        for case let qso as QSO in context.deletedModelsArray {
            batch.deletes.append(SwiftDataStoreImporter.uuid(qso.id))
        }
        for case let sp as ServicePresence in context.insertedModelsArray {
            batch.spUpserts.append(SwiftDataStoreImporter.project(sp))
        }
        for case let sp as ServicePresence in context.changedModelsArray {
            batch.spUpserts.append(SwiftDataStoreImporter.project(sp))
        }
        for case let sp as ServicePresence in context.deletedModelsArray {
            batch.spDeletes.append(SwiftDataStoreImporter.uuid(sp.id))
        }
        captureSessionEntities(context, into: &batch)
        captureCatalogEntities(context, into: &batch)
        captureMediaEntities(context, into: &batch)
        captureSyncEntities(context, into: &batch)
        return batch
    }

    /// LoggingSession / SessionSpot / ActivityLog — all id-keyed. Insert+update →
    /// upsert; delete → delete-by-id. Projected on the context's thread; the closures
    /// replay against the store on the mirror actor.
    private func captureSessionEntities(_ context: ModelContext, into batch: inout Pending) {
        for case let model as LoggingSession in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertLoggingSession(item: dto) }
            // Keep the structured rove_stop table (which the Rust split reads) in
            // lockstep with the transitional blob the iOS UI still mutates.
            if model.isRove {
                let sessionId = SwiftDataStoreImporter.uuid(model.id)
                let stops = SwiftDataStoreImporter.projectRoveStops(model)
                batch.entityWrites.append {
                    try? $0.replaceRoveStops(loggingSessionId: sessionId, stops: stops)
                }
            }
        }
        for case let model as LoggingSession in context.deletedModelsArray {
            let id = SwiftDataStoreImporter.uuid(model.id)
            batch.entityWrites.append { try? $0.deleteLoggingSession(id: id) }
        }
        for case let model as SessionSpot in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertSessionSpot(item: dto) }
        }
        for case let model as SessionSpot in context.deletedModelsArray {
            let id = SwiftDataStoreImporter.uuid(model.id)
            batch.entityWrites.append { try? $0.deleteSessionSpot(id: id) }
        }
        for case let model as ActivityLog in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertActivityLog(item: dto) }
        }
        for case let model as ActivityLog in context.deletedModelsArray {
            let id = SwiftDataStoreImporter.uuid(model.id)
            batch.entityWrites.append { try? $0.deleteActivityLog(id: id) }
        }
    }

    /// EquipmentItem / RadioMacro / UploadDestination — all id-keyed.
    private func captureCatalogEntities(_ context: ModelContext, into batch: inout Pending) {
        for case let model as EquipmentItem in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertEquipmentItem(item: dto) }
        }
        for case let model as EquipmentItem in context.deletedModelsArray {
            let id = SwiftDataStoreImporter.uuid(model.id)
            batch.entityWrites.append { try? $0.deleteEquipmentItem(id: id) }
        }
        for case let model as RadioMacro in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertRadioMacro(item: dto) }
        }
        for case let model as RadioMacro in context.deletedModelsArray {
            let id = SwiftDataStoreImporter.uuid(model.id)
            batch.entityWrites.append { try? $0.deleteRadioMacro(id: id) }
        }
        for case let model as UploadDestination in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertUploadDestination(item: dto) }
        }
        for case let model as UploadDestination in context.deletedModelsArray {
            let id = SwiftDataStoreImporter.uuid(model.id)
            batch.entityWrites.append { try? $0.deleteUploadDestination(id: id) }
        }
    }

    /// WebSDRRecording (id-keyed) + WebSDRFavorite (keyed by `host_port`).
    private func captureMediaEntities(_ context: ModelContext, into batch: inout Pending) {
        for case let model as WebSDRRecording in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertWebsdrRecording(item: dto) }
        }
        for case let model as WebSDRRecording in context.deletedModelsArray {
            let id = SwiftDataStoreImporter.uuid(model.id)
            batch.entityWrites.append { try? $0.deleteWebsdrRecording(id: id) }
        }
        for case let model as CarrierWaveData.WebSDRFavorite in context.insertedModelsArray + context
            .changedModelsArray
        {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertWebsdrFavorite(item: dto) }
        }
        for case let model as CarrierWaveData.WebSDRFavorite in context.deletedModelsArray {
            let hostPort = model.hostPort
            batch.entityWrites.append { try? $0.deleteWebsdrFavorite(hostPort: hostPort) }
        }
    }

    /// ActivationMetadata (keyed by `(park_reference, date)`) + CloudSyncMetadata
    /// (keyed by `(entity_type, local_id)`). Natural-key deletes read the key off the
    /// projected DTO so the representation matches the stored row exactly.
    private func captureSyncEntities(_ context: ModelContext, into batch: inout Pending) {
        for case let model as ActivationMetadata in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertActivationMetadata(item: dto) }
        }
        for case let model as ActivationMetadata in context.deletedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append {
                try? $0.deleteActivationMetadata(parkReference: dto.parkReference, date: dto.date)
            }
        }
        for case let model as CloudSyncMetadata in context.insertedModelsArray + context.changedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append { try? $0.upsertCloudSyncMetadata(item: dto) }
        }
        for case let model as CloudSyncMetadata in context.deletedModelsArray {
            let dto = SwiftDataStoreImporter.project(model)
            batch.entityWrites.append {
                try? $0.deleteCloudSyncMetadata(entityType: dto.entityType, localId: dto.localId)
            }
        }
    }

    /// After commit, flush this context's buffered changes to the serial actor.
    private func handleDidSave(_ note: Notification) {
        guard let context = note.object as? ModelContext else {
            return
        }
        let key = ObjectIdentifier(context)
        let batch = lock.withLock { pending.removeValue(forKey: key) }
        guard let batch, !batch.isEmpty else {
            return
        }
        let task = Task { [mirrorActor] in
            if !batch.upserts.isEmpty {
                await mirrorActor.applyUpserts(batch.upserts)
            }
            if !batch.spUpserts.isEmpty {
                await mirrorActor.applyServicePresenceUpserts(batch.spUpserts)
            }
            if !batch.deletes.isEmpty {
                await mirrorActor.applyDeletes(batch.deletes)
            }
            if !batch.spDeletes.isEmpty {
                await mirrorActor.applyServicePresenceDeletes(batch.spDeletes)
            }
            if !batch.entityWrites.isEmpty {
                await mirrorActor.applyEntityWrites(batch.entityWrites)
            }
        }
        lock.withLock { lastWrite = task }
    }
}
