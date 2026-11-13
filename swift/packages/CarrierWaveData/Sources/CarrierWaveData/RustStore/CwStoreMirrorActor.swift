import CarrierWaveCore
import Foundation

/// Serializes QSO dual-writes into the Rust store off the main thread. Accepts
/// only value types so no @Model crosses the boundary. `drain()` is a barrier the
/// read path can await so reads never precede pending writes.
actor CwStoreMirrorActor {
    // MARK: Lifecycle

    init(store: FieldStore) {
        self.store = store
    }

    // MARK: Internal

    func applyUpserts(_ qsos: [FfiQso]) {
        for qso in qsos {
            try? store.upsertQso(qso: qso)
        }
    }

    func applyDeletes(_ ids: [String]) {
        for id in ids {
            try? store.deleteQso(id: id)
        }
    }

    func applyServicePresenceUpserts(_ items: [FfiServicePresence]) {
        for item in items {
            try? store.upsertServicePresence(item: item)
        }
    }

    func applyServicePresenceDeletes(_ ids: [String]) {
        for id in ids {
            try? store.deleteServicePresence(id: id)
        }
    }

    /// Replay non-QSO/ServicePresence entity writes. Each op was captured on the
    /// saving context's thread (projecting the live `@Model` to a value DTO, or its
    /// natural key for a delete) and just calls the matching `FieldStore` method,
    /// which fires its own `notify(...)`.
    func applyEntityWrites(_ ops: [@Sendable (FieldStore) -> Void]) {
        for op in ops {
            op(store)
        }
    }

    /// Barrier: returns once previously-enqueued work has run (actor serialization).
    func drain() {}

    // MARK: Private

    private let store: FieldStore
}
