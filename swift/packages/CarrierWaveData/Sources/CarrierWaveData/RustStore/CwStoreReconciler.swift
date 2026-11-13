import CarrierWaveCore
import Foundation
import SwiftData

// Reconciles the cw-store follower against SwiftData (the canonical store in
// Phase 4) by **pruning orphans** — cw-store rows whose key SwiftData no longer
// has. This closes every delete blind spot the event-driven mirror can't see,
// by construction and regardless of how the row was deleted:
//
//   - bulk `modelContext.delete(model:)` (no per-object change notification),
//   - CloudKit remote deletions (merged via the store coordinator, not a save),
//   - the importer's upsert-only seed (never prunes),
//   - any future delete path.
//
// It is a SURGICAL prune, not a wipe: it only deletes rows keyed off a SwiftData
// @Model, so cw-store-only reference tables (e.g. `pota_park`) are untouched.
//
// Reads SwiftData through the supplied context and pages both sides in bounded
// batches (≤ pageSize rows in memory at once), so QSO count never affects the
// memory ceiling. Two-pass per entity: collect all cw-store keys first, then
// delete the orphans — deleting mid-enumeration would shift offsets and skip rows.

// MARK: - ReconcileReport

/// Per-table orphan counts removed from cw-store during a reconcile.
public struct ReconcileReport: Sendable, Equatable {
    // MARK: Lifecycle

    public init(deleted: [String: Int] = [:]) {
        self.deleted = deleted
    }

    // MARK: Public

    public var deleted: [String: Int]

    public var total: Int {
        deleted.values.reduce(0, +)
    }
}

// MARK: - CwStoreReconciler

public struct CwStoreReconciler {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public static let defaultPageSize = 1_000

    /// Prune cw-store QSO rows whose id is absent from SwiftData. Returns the count
    /// removed. Bounded: holds at most `pageSize` cw-store rows in memory per batch
    /// (only their ids are retained across batches).
    @discardableResult
    public func reconcileQSOs(in context: ModelContext, pageSize: Int = defaultPageSize) throws -> Int {
        // Order matters for concurrency safety: snapshot cw-store ids FIRST, then
        // SwiftData ids. A QSO created between the two reads is then absent from the
        // cw-store snapshot, so it can never be a delete candidate. (SwiftData-first
        // would flag that fresh row — present in cw-store, missing from the older
        // SwiftData snapshot — and wrongly prune a valid QSO.) Callers should drain
        // the mirror before this so in-flight follower writes are already applied.
        let rustIds = try cwStoreQSOIds(pageSize: pageSize)
        let swiftIds = try swiftDataQSOIds(in: context, pageSize: pageSize)
        var deleted = 0
        for id in rustIds where !swiftIds.contains(id) {
            try store.deleteQso(id: id)
            deleted += 1
        }
        return deleted
    }

    /// Reconcile every SwiftData-derived entity. Currently QSO (the high-churn,
    /// parity-checked table); structured so peripheral entities follow the same
    /// collect-keys-then-prune shape.
    @discardableResult
    public func reconcileAll(in context: ModelContext, pageSize: Int = defaultPageSize) throws -> ReconcileReport {
        // Under Rust authority (`.on`) cw-store is canonical and SwiftData is the
        // follower: rows that only exist in cw-store (server-sync pulls, CloudKit
        // inbound routed through `QSOJournalStore`) are real data, not orphans.
        // Pruning them would silently delete synced QSOs. Deletes under `.on` go
        // through the write seams, so there is nothing for this pass to heal.
        guard CwStoreQSOMode.current != .on else {
            return ReconcileReport()
        }
        var report: [String: Int] = [:]
        report["qso"] = try reconcileQSOs(in: context, pageSize: pageSize)
        return ReconcileReport(deleted: report)
    }

    // MARK: Private

    private let store: FieldStore

    /// All SwiftData QSO ids as the store's canonical key form (lowercased uuid),
    /// paged so the row cache never holds more than `pageSize` at once.
    private func swiftDataQSOIds(in context: ModelContext, pageSize: Int) throws -> Set<String> {
        var ids = Set<String>()
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<QSO>()
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            let batch = try context.fetch(descriptor)
            if batch.isEmpty {
                break
            }
            for qso in batch {
                ids.insert(SwiftDataStoreImporter.uuid(qso.id))
            }
            offset += batch.count
            if batch.count < pageSize {
                break
            }
        }
        return ids
    }

    /// All cw-store QSO ids (just the id strings retained across batches).
    private func cwStoreQSOIds(pageSize: Int) throws -> [String] {
        let allFilter = FfiQsoFilter(
            callsignPrefix: nil, band: nil, mode: nil, since: nil, dirtyOnly: false
        )
        var ids: [String] = []
        var offset = 0
        while true {
            let rows = try store.fetchQsos(filter: allFilter, limit: Int64(pageSize), offset: Int64(offset))
            if rows.isEmpty {
                break
            }
            ids.append(contentsOf: rows.map(\.id))
            offset += rows.count
            if rows.count < pageSize {
                break
            }
        }
        return ids
    }
}
