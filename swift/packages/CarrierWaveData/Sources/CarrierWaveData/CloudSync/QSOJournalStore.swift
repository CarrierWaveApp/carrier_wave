import CarrierWaveCore
import Foundation

// MARK: - QSOJournalStore

//
// The `FieldStore`-backed store-access seam for the CloudKit journal's QSO path
// (Phase 1b). It performs exactly the QSO store operations the journal engine
// does against `ModelContext` today — fetch dirty, clear dirty (with the CAR-245
// guard), mark-all-dirty, inbound upsert-with-merge, soft-delete, and the
// bootstrap "has visible QSO" gate — but against the shared Rust store.
//
// The journal wire format (`QSOFields`) and the conflict resolver
// (`CloudSyncConflictResolver.mergeQSO`) are unchanged; this only swaps where the
// rows live. Every conversion goes through `QSOFields ↔ FfiQso`
// (`QSOFields+FieldStore.swift`), which matches `SwiftDataStoreImporter.project`
// so the seam and the mirror address the same row ids.
//
// NOTE: not yet wired into `CloudSyncJournalEngine` — graduating the engine onto
// this seam (and flipping QSO write authority to the store) is gated on the
// two-device round-trip verification in the migration plan (Phase 1c). This type
// is the verified building block for that step.

/// QSO store-access operations for the journal engine, backed by `FieldStore`.
public struct QSOJournalStore: Sendable {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    /// One bounded page of dirty QSOs, split into rows that should emit an
    /// outbound journal op (real QSOs → wire fields) and the metadata-mode ids
    /// that must be cleared WITHOUT emitting an op (mirrors the Swift outbound's
    /// `QSOMode.isMetadata` skip — WEATHER/SOLAR/NOTE never sync).
    public struct DirtyQSOPage: Sendable {
        public let emittable: [QSOFields]
        public let metadataModeIds: [String]
    }

    public let store: FieldStore

    /// Fetch a bounded page of dirty QSOs (≤ 1000, the store's cap), partitioned
    /// for the outbound collector.
    public func dirtyQSOPage(limit: Int64 = 1_000, offset: Int64 = 0) throws -> DirtyQSOPage {
        let filter = FfiQsoFilter(
            callsignPrefix: nil, band: nil, mode: nil, since: nil, dirtyOnly: true
        )
        let rows = try store.fetchQsos(filter: filter, limit: limit, offset: offset)
        var emittable: [QSOFields] = []
        var metadataModeIds: [String] = []
        for row in rows {
            if QSOMode.isMetadata(row.mode ?? "") {
                metadataModeIds.append(row.id)
            } else if let fields = row.toQSOFields() {
                emittable.append(fields)
            }
        }
        return DirtyQSOPage(emittable: emittable, metadataModeIds: metadataModeIds)
    }

    /// Clear the dirty flag on confirmed-saved QSOs. Rows the user edited after
    /// the journal snapshot (`notIfModifiedAfter`) keep their flag set so the
    /// newer write flushes on the next outbound pass (CAR-245).
    @discardableResult
    public func clearDirty(ids: [UUID], notIfModifiedAfter: Date?) throws -> Int64 {
        guard !ids.isEmpty else {
            return 0
        }
        let idStrings = ids.map { SwiftDataStoreImporter.uuid($0) }
        let cutoff = notIfModifiedAfter.map { Int64($0.timeIntervalSince1970) }
        return try store.clearDirty(entityType: "qso", ids: idStrings, notIfModifiedAfter: cutoff)
    }

    /// Clear dirty by raw store id with no CAR-245 guard — the metadata-mode
    /// skip path (those rows are never emitted, just cleared).
    @discardableResult
    public func clearDirty(storeIds: [String]) throws -> Int64 {
        guard !storeIds.isEmpty else {
            return 0
        }
        return try store.clearDirty(entityType: "qso", ids: storeIds, notIfModifiedAfter: nil)
    }

    /// Mark every non-metadata QSO dirty (Force Full Sync / account sign-in).
    @discardableResult
    public func markAllDirty() throws -> Int64 {
        try store.markAllDirty(entityType: "qso")
    }

    /// Count of dirty (un-synced) QSOs — backs the sync panel's outbound backlog.
    public func dirtyCount() throws -> Int {
        try Int(store.dirtyQsoCount())
    }

    /// Apply an inbound QSO upsert. If the row exists, merge the incoming fields
    /// against the local row via the conflict resolver and preserve the
    /// FfiQso-only columns + the existing dirty flag (no sync ping-pong); else
    /// insert a fresh, clean row. Mirrors `applyQSOUpsert`.
    public func applyInbound(_ remote: QSOFields, remoteTimestamp: Date) throws {
        let storeId = SwiftDataStoreImporter.uuid(remote.id)
        if let existing = try store.fetchQso(id: storeId), let localFields = existing.toQSOFields() {
            let localMod = localFields.modifiedAt ?? localFields.importedAt
            let merged = CloudSyncConflictResolver.mergeQSO(
                local: localFields,
                remote: remote,
                localModDate: localMod,
                remoteModDate: remoteTimestamp
            )
            try store.upsertQso(qso: merged.toFfiQso(dirty: existing.dirty, preserving: existing))
        } else {
            try store.upsertQso(qso: remote.toFfiQso(dirty: false))
        }
    }

    /// Soft-delete a QSO (set `isHidden`, never a hard delete) — mirrors the
    /// journal's QSO deletion path. Missing id is a no-op.
    public func softDelete(id: UUID) throws {
        guard var existing = try store.fetchQso(id: SwiftDataStoreImporter.uuid(id)) else {
            return
        }
        existing.isHidden = true
        try store.upsertQso(qso: existing)
    }

    /// Bootstrap gate: does the store hold any visible (non-hidden) QSO? Uses the
    /// query path because it applies the `is_hidden = 0` predicate (the bounded
    /// `fetchQsos` does not). Mirrors `localDatabaseHasData`.
    public func hasVisibleQSO() throws -> Bool {
        try !store.fetchQsosQuery(query: "", limit: 1, offset: 0).isEmpty
    }
}
