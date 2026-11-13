import CarrierWaveCore
import SwiftData

// MARK: - SeamWriteBatchRegistry

/// Main-actor handle to the live store + mirror so a multi-entity save site can
/// build a `SeamWriteBatch`. Set by `CarrierWaveApp.applyQSOMirrorMode` when the
/// mirror starts; `nil` in `off` mode (callers then fall back to a plain save).
@MainActor
public enum SeamWriteBatchRegistry {
    public static var current: (store: FieldStore, mirror: CwStoreMirror?)?
}

// MARK: - SeamWriteBatch

/// Coordinated, multi-entity write seam for **shared saves** — a single
/// `modelContext.save()` that flushes more than one entity (e.g. a session delete
/// that also hides its QSOs and removes its SessionSpots).
///
/// Why the per-entity `EntityWriteSink` is not enough: `CwStoreMirror` suppresses
/// mirroring with one global counter per save, so routing a shared save through a
/// single-entity sink suppresses the mirror for the **whole** save and silently
/// drops the co-mutated entities from cw-store in `on` mode. The batch collects a
/// store op for **every** co-mutated entity, runs them all under one suppression
/// window, then issues one save.
///
/// Routed by `cwStoreQSOMode` exactly like the per-entity sinks:
/// - `on`: write cw-store FIRST for all collected ops (canonical — abort if any
///   throws), then one `CwStoreMirror`-suppressed save.
/// - `shadow`/anything else: one plain save (the unsuppressed mirror dual-writes in
///   `shadow`). `off` never builds a batch (`make()` returns nil).
///
/// Uniform-entity ops resolve through `EntityWriteSinkRegistry` so the per-entity
/// `upsert_*` / `delete_*` FFI stays the single source of truth. QSO carries its
/// ServicePresence rows, mirroring `QSOWriteSink`'s projection.
@MainActor
public struct SeamWriteBatch {
    // MARK: Lifecycle

    public init(store: FieldStore, mirror: CwStoreMirror?) {
        self.store = store
        self.mirror = mirror
    }

    // MARK: Public

    public let store: FieldStore
    public let mirror: CwStoreMirror?
    public var modeProvider: () -> CwStoreQSOMode = { CwStoreQSOMode.current }

    /// Build a batch from the live store/mirror, or `nil` when no seam is active
    /// (`off` mode / experiment disabled) — the caller then does a plain save.
    public static func make() -> SeamWriteBatch? {
        guard let ctx = SeamWriteBatchRegistry.current else {
            return nil
        }
        return SeamWriteBatch(store: ctx.store, mirror: ctx.mirror)
    }

    /// Stage an upsert for a uniform entity (LoggingSession, SessionSpot,
    /// ActivationMetadata, …). Resolved via `EntityWriteSinkRegistry`.
    public mutating func upsert<Model: PersistentModel>(_ model: Model) {
        guard let sink = EntityWriteSinkRegistry.sink(for: Model.self) else {
            recordUnregistered(Model.self)
            return
        }
        ops.append { try sink.upsertToStore(model, $0) }
    }

    /// Stage a hard-delete for a uniform entity. Resolved via the registry.
    public mutating func delete<Model: PersistentModel>(_ model: Model) {
        guard let sink = EntityWriteSinkRegistry.sink(for: Model.self) else {
            recordUnregistered(Model.self)
            return
        }
        ops.append { try sink.deleteFromStore(model, $0) }
    }

    /// Stage a QSO upsert plus its ServicePresence rows — mirrors
    /// `QSOWriteSink.writeUpsertToStore`. Use for co-mutated QSOs (e.g. hidden on
    /// session delete); the QSO hot path proper stays in `QSOWriteSink`.
    public mutating func upsertQSO(_ qso: QSO) {
        ops.append {
            try $0.upsertQso(qso: SwiftDataStoreImporter.project(qso))
            for presence in qso.servicePresence {
                try $0.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))
            }
        }
    }

    /// Commit the staged ops. `on`: every store op FIRST, then one suppressed save.
    /// Other modes: one plain save. Throws if a canonical cw-store write fails —
    /// the caller keeps the same `try?`/rollback handling it used for the save.
    public func commit(in context: ModelContext) throws {
        if modeProvider() == .on {
            for op in ops {
                try op(store)
            }
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            try context.save()
        } else {
            try context.save()
        }
    }

    // MARK: Private

    private var ops: [(FieldStore) throws -> Void] = []

    private func recordUnregistered(_ type: (some PersistentModel).Type) {
        CwStoreWriteLog.shared.record(
            "SeamWriteBatch: no EntityWriteSink registered for \(String(reflecting: type)) — op dropped"
        )
    }
}
