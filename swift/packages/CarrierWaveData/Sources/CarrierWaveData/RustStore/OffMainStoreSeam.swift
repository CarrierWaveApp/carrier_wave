import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - OffMainStoreSeam

/// Off-main analogue of `SeamWriteBatch` for background `ModelContext` savers
/// (`QSOProcessingActor`, `BatchedRewrite`-based repairs, `WPMBackfillService`)
/// that run off the main actor and so can't reach the `@MainActor` sinks.
///
/// Same contract, routed by `cwStoreQSOMode`:
/// - `on`: write cw-store FIRST for every staged op (canonical — abort if any
///   throws), then one `CwStoreMirror`-suppressed `context.save()`. Suppression is
///   **per-context** (`beginSeamWrite(for:)`), so suppressing this background save
///   never drops a *concurrent* main-context save's changes from cw-store.
/// - other modes: one plain save (the unsuppressed mirror dual-writes in `shadow`).
///
/// `nonisolated` + `@unchecked Sendable`: callable from any actor/thread. The live
/// `(store, mirror)` handle is set once on mirror setup and read under a lock; both
/// values are `Sendable`. `FieldStore`'s Rust-side mutex serializes the actual DB
/// writes, so concurrent off-main + main-actor store writes are safe.
///
/// The `storeOps` project the models lazily inside the op, so projection runs on the
/// caller's thread (the saving context's executor) — the only thread that may touch
/// those `@Model`s — exactly as `SeamWriteBatch` does on the main actor.
nonisolated public enum OffMainStoreSeam {
    // MARK: Public

    /// Publish the live store + mirror. Called from `applyQSOMirrorMode` on setup.
    public static func activate(store: FieldStore, mirror: CwStoreMirror) {
        holder.set((store, mirror))
    }

    /// Drop the handle. Called from `applyQSOMirrorMode` when the mirror stops.
    public static func deactivate() {
        holder.set(nil)
    }

    /// Commit a background save. `storeOps` are the canonical cw-store writes for
    /// **every** entity this `save()` flushes; the caller has already applied the
    /// SwiftData mutations in `context`. Throws if a canonical write fails — the
    /// caller keeps whatever `try?` / rollback handling it used for the plain save.
    public static func commit(in context: ModelContext, storeOps: [(FieldStore) throws -> Void]) throws {
        guard CwStoreQSOMode.current == .on, let (store, mirror) = holder.get() else {
            try context.save()
            return
        }
        for op in storeOps {
            try op(store)
        }
        mirror.beginSeamWrite(for: context)
        defer { mirror.endSeamWrite(for: context) }
        try context.save()
    }

    /// Presence-only background save (sync-upload marking / `POTAPresenceRepairService`).
    ///
    /// All three typed commits below use the batch FFI methods — one Rust-side
    /// transaction (one fsync) per table, not one autocommit per row. Per-row
    /// commits under `synchronous=FULL` hold the SQLite lock for the whole
    /// batch; getting suspended inside that window is a `0xdead10cc` kill
    /// (TestFlight crash 3160).
    public static func commitPresence(_ presences: [ServicePresence], in context: ModelContext) throws {
        try commit(in: context, storeOps: [{ store in
            try store.upsertServicePresences(items: presences.map { SwiftDataStoreImporter.project($0) })
        }])
    }

    /// ActivationMetadata-only background save (`WPMBackfillService`).
    public static func commitActivationMetadata(_ items: [ActivationMetadata], in context: ModelContext) throws {
        try commit(in: context, storeOps: [{ store in
            try store.upsertActivationMetadataBatch(items: items.map { SwiftDataStoreImporter.project($0) })
        }])
    }

    /// QSO + co-mutated ServicePresence background save (`QSOProcessingActor`,
    /// `HuntingParkRefRepairService`). Mirrors `QSOWriteSink.writeUpsertToStore`.
    /// QSOs commit before their presences so the presence rows' `qso_id`
    /// references already exist.
    public static func commitQSOsWithPresence(_ qsos: [QSO], in context: ModelContext) throws {
        try commit(in: context, storeOps: [{ store in
            try store.upsertQsos(qsos: qsos.map { SwiftDataStoreImporter.project($0) })
            let presences = qsos.flatMap(\.servicePresence)
            try store.upsertServicePresences(items: presences.map { SwiftDataStoreImporter.project($0) })
        }])
    }

    /// LoggingSession-only background save (CW Sweep remote-op session apply).
    public static func commitLoggingSessions(_ sessions: [LoggingSession], in context: ModelContext) throws {
        try commit(in: context, storeOps: [{ store in
            for session in sessions {
                try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))
            }
        }])
    }

    /// QSOs (+ their ServicePresence rows) and the sessions they were logged
    /// into, in one background save (CW Sweep satlog ingest). QSOs first, then
    /// presences, then sessions.
    public static func commitQSOsWithPresence(
        _ qsos: [QSO], sessions: [LoggingSession], in context: ModelContext
    ) throws {
        try commit(in: context, storeOps: [{ store in
            try store.upsertQsos(qsos: qsos.map { SwiftDataStoreImporter.project($0) })
            let presences = qsos.flatMap(\.servicePresence)
            try store.upsertServicePresences(items: presences.map { SwiftDataStoreImporter.project($0) })
            for session in sessions {
                try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))
            }
        }])
    }

    // MARK: Private

    /// NSLock-guarded set-once handle (no `nonisolated(unsafe)` on mutable state).
    private final class Holder: @unchecked Sendable {
        // MARK: Internal

        func set(_ value: (FieldStore, CwStoreMirror)?) {
            lock.withLock { self.value = value }
        }

        func get() -> (FieldStore, CwStoreMirror)? {
            lock.withLock { value }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value: (FieldStore, CwStoreMirror)?
    }

    private static let holder = Holder()
}
