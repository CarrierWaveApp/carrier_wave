import CarrierWaveCore
import SwiftData

// MARK: - EntityWriteSink

/// Generic write seam for the uniform peripheral entities (everything except QSO
/// and ServicePresence, which keep dedicated sinks for their presence-row / hidden
/// logic). Mirrors the `QSOWriteSink` contract, routed by `cwStoreQSOMode`:
/// - `on`: write cw-store FIRST (canonical — abort if it throws), then mutate the
///   SwiftData replica and save with `CwStoreMirror` suppressed so CloudKit still
///   picks up the change but the save does not echo back into cw-store.
/// - `shadow`/anything else: mutate SwiftData and save (the unsuppressed mirror
///   dual-writes in `shadow`). `off` never registers a sink.
///
/// The per-entity store calls are supplied as closures by `EntityWriteSinkFactory`
/// (the `RustCountReadSource` factory idiom), so the right `upsert_*` / `delete_*`
/// FFI is wired once per entity and call sites stay discoverable.
@MainActor
public struct EntityWriteSink<Model: PersistentModel> {
    // MARK: Lifecycle

    public init(
        store: FieldStore,
        mirror: CwStoreMirror?,
        upsertToStore: @escaping (Model, FieldStore) throws -> Void,
        deleteFromStore: @escaping (Model, FieldStore) throws -> Void
    ) {
        self.store = store
        self.mirror = mirror
        self.upsertToStore = upsertToStore
        self.deleteFromStore = deleteFromStore
    }

    // MARK: Public

    public let store: FieldStore
    public let mirror: CwStoreMirror?
    public let upsertToStore: (Model, FieldStore) throws -> Void
    public let deleteFromStore: (Model, FieldStore) throws -> Void
    public var modeProvider: () -> CwStoreQSOMode = { CwStoreQSOMode.current }

    /// Commit a batch of inserts/updates. The caller has already inserted (new) or
    /// mutated (edit) the models in `context`. In `on` mode this writes cw-store
    /// FIRST, then one mirror-suppressed save. Other modes just save (the
    /// unsuppressed mirror dual-writes in `shadow`). Throws if the canonical
    /// cw-store write fails — the caller must `rollback()`.
    public func upsert(_ models: [Model], in context: ModelContext) throws {
        if modeProvider() == .on {
            for model in models {
                try upsertToStore(model, store)
            }
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            try context.save()
        } else {
            try context.save()
        }
    }

    /// Commit a batch of hard-deletes. `on`: delete every row from cw-store FIRST,
    /// then `context.delete` each + one mirror-suppressed save. Other modes:
    /// `context.delete` each + one plain save.
    public func delete(_ models: [Model], in context: ModelContext) throws {
        if modeProvider() == .on {
            for model in models {
                try deleteFromStore(model, store)
            }
            for model in models {
                context.delete(model)
            }
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            try context.save()
        } else {
            for model in models {
                context.delete(model)
            }
            try context.save()
        }
    }
}

// MARK: - EntityWriteSink + Routing

public extension EntityWriteSink {
    /// Route an upsert through the active per-type seam, or fall back to a plain
    /// SwiftData save when no seam is active (`off` mode / experiment disabled).
    @MainActor
    static func commitUpsert(_ model: Model, in context: ModelContext) throws {
        try commitUpsert([model], in: context)
    }

    /// Batch upsert through the active seam, or a plain save when none is active.
    @MainActor
    static func commitUpsert(_ models: [Model], in context: ModelContext) throws {
        if let sink = EntityWriteSinkRegistry.sink(for: Model.self) {
            try sink.upsert(models, in: context)
        } else {
            try context.save()
        }
    }

    /// Route a hard-delete through the active seam, or a plain SwiftData delete+save.
    @MainActor
    static func commitDelete(_ model: Model, in context: ModelContext) throws {
        try commitDelete([model], in: context)
    }

    /// Batch hard-delete through the active seam, or a plain SwiftData delete+save.
    @MainActor
    static func commitDelete(_ models: [Model], in context: ModelContext) throws {
        if let sink = EntityWriteSinkRegistry.sink(for: Model.self) {
            try sink.delete(models, in: context)
        } else {
            for model in models {
                context.delete(model)
            }
            try context.save()
        }
    }
}

// MARK: - EntityWriteSinkRegistry

/// Main-actor, type-keyed handle to the live per-entity write seams so write sites
/// can route mutations through cw-store in `on`/`shadow` mode. Populated by
/// `CarrierWaveApp.applyQSOMirrorMode` via `EntityWriteSinkFactory`; cleared in
/// `off` mode. Holds value-type sinks by value (no weak/strong cycle).
@MainActor
public enum EntityWriteSinkRegistry {
    // MARK: Public

    public static func register<Model>(_ sink: EntityWriteSink<Model>) {
        sinks[ObjectIdentifier(Model.self)] = sink
    }

    public static func sink<Model>(for _: Model.Type) -> EntityWriteSink<Model>? {
        sinks[ObjectIdentifier(Model.self)] as? EntityWriteSink<Model>
    }

    public static func clear() {
        sinks.removeAll()
    }

    // MARK: Private

    private static var sinks: [ObjectIdentifier: Any] = [:]
}
