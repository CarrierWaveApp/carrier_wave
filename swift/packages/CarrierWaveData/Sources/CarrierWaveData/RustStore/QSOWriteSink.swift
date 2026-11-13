import CarrierWaveCore
import SwiftData

// MARK: - QSOWriteSinkRegistry

/// Main-actor handle to the live write seam so `LoggingSessionManager` can route
/// QSO mutations through cw-store in `on`/`shadow` mode. Set by
/// `CarrierWaveApp.applyQSOMirrorMode`; `nil` in `off` mode. Value type, so the
/// registry holds it by value (no weak/strong cycle).
@MainActor
public enum QSOWriteSinkRegistry {
    public static var current: QSOWriteSink?
}

// MARK: - QSOWriteSink

/// Funnels QSO hide/unhide writes, routed by `cwStoreQSOMode`:
/// - `on`: write cw-store FIRST (canonical — abort if it throws), then mutate the
///   SwiftData replica and save with `CwStoreMirror` suppressed so CloudKit still
///   picks up the change but the save does not echo back into cw-store.
/// - `shadow`/anything else: mutate SwiftData and save (the unsuppressed mirror
///   dual-writes in `shadow`). `off` mode never constructs a seam (registry is nil).
@MainActor
public struct QSOWriteSink {
    // MARK: Lifecycle

    public init(store: FieldStore, mirror: CwStoreMirror?) {
        self.store = store
        self.mirror = mirror
    }

    /// Test seam: pin the routing mode instead of reading `CwStoreQSOMode.current`.
    public init(store: FieldStore, mirror: CwStoreMirror?, modeProvider: @escaping () -> CwStoreQSOMode) {
        self.store = store
        self.mirror = mirror
        self.modeProvider = modeProvider
    }

    // MARK: Public

    public let store: FieldStore
    public let mirror: CwStoreMirror?
    public var modeProvider: () -> CwStoreQSOMode = { CwStoreQSOMode.current }

    /// Apply a hidden-flag change, then commit via `upsert`.
    public func setHidden(_ qso: QSO, hidden: Bool, in context: ModelContext) throws {
        applyHiddenInMemory(qso, hidden: hidden)
        try upsert(qso, in: context)
    }

    /// Commit a QSO insert/update. The caller has already inserted (new) or mutated
    /// (edit) the QSO in `context`. In `on` mode this writes cw-store FIRST (the QSO and
    /// its ServicePresence rows), then saves SwiftData with the mirror suppressed. Other
    /// modes just save (the unsuppressed mirror dual-writes in `shadow`). Throws if the
    /// canonical cw-store write fails — the caller must `rollback()`.
    public func upsert(_ qso: QSO, in context: ModelContext) throws {
        if modeProvider() == .on {
            try writeUpsertToStore(qso)
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            try context.save()
        } else {
            try context.save()
        }
    }

    /// Commit a batch of QSO inserts/updates. `on`: upsert every QSO + its
    /// ServicePresence to cw-store FIRST, then one mirror-suppressed save. Other modes:
    /// one plain save. Throws on a canonical-write failure — the caller must rollback.
    public func upsertBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if modeProvider() == .on {
            for qso in qsos {
                try writeUpsertToStore(qso)
            }
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            try context.save()
        } else {
            try context.save()
        }
    }

    /// Commit a batch of QSO hard-deletes. `on`: delete every QSO (and its
    /// ServicePresence rows) from cw-store FIRST, then `context.delete` each + one
    /// mirror-suppressed save. Other modes: `context.delete` each + one plain save.
    public func deleteBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if modeProvider() == .on {
            for qso in qsos {
                for presence in qso.servicePresence {
                    try store.deleteServicePresence(id: SwiftDataStoreImporter.uuid(presence.id))
                }
                try store.deleteQso(id: SwiftDataStoreImporter.uuid(qso.id))
            }
            for qso in qsos {
                context.delete(qso)
            }
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            try context.save()
        } else {
            for qso in qsos {
                context.delete(qso)
            }
            try context.save()
        }
    }

    // MARK: Private

    private func writeUpsertToStore(_ qso: QSO) throws {
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        for presence in qso.servicePresence {
            try store.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))
        }
    }

    private func applyHiddenInMemory(_ qso: QSO, hidden: Bool) {
        qso.isHidden = hidden
        guard hidden else {
            return
        }
        for presence in qso.servicePresence where presence.needsUpload {
            presence.needsUpload = false
        }
    }
}

// MARK: - QSOWriteSink + Routing

public extension QSOWriteSink {
    /// Route a QSO upsert through the active seam, or fall back to a plain SwiftData
    /// save when no seam is active (`off` mode / experiment disabled). The caller has
    /// already inserted/mutated the QSO in `context`.
    @MainActor
    static func commitUpsert(_ qso: QSO, in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.upsert(qso, in: context)
        } else {
            try context.save()
        }
    }

    /// Batch upsert through the active seam, or a plain save when no seam is active.
    @MainActor
    static func commitUpsertBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.upsertBatch(qsos, in: context)
        } else {
            try context.save()
        }
    }

    /// Batch hard-delete through the active seam, or a plain SwiftData delete+save.
    @MainActor
    static func commitDeleteBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.deleteBatch(qsos, in: context)
        } else {
            for qso in qsos {
                context.delete(qso)
            }
            try context.save()
        }
    }
}
