import CarrierWaveCore
import Foundation
import SwiftData

// One-time SwiftData → cw-store (SQLCipher) seed importer.
//
// Each batch runs on a fresh off-main `ModelContext` per the PERFORMANCE.md
// batching pattern: fetch a bounded page, project to `Sendable` `Ffi*` values,
// commit them as ONE SQLite transaction via the store's batch upsert FFI, then
// drop the context so SwiftData releases its row cache. Two prior designs are
// deliberately dead:
// - Main-context reads: an early on-device fetch crash looked entity-specific
//   but was really a duplicated model in the schema (fixed by `AppSchema.models`
//   dedup — see docs/plans/2026-06-14-swiftdata-import-design.md). Background
//   contexts are safe on this store (the mirror + reconciler already use them),
//   and the main context's row cache never shrinks — paging 100k QSOs through
//   it risks jetsam.
// - Per-row upserts on the main thread: `synchronous=FULL` + `fullfsync` ⇒ two
//   disk barriers per row, which blocked the run loop for minutes on large logs
//   and got the app watchdog-killed at launch (0x8BADF00D, 2026-07-02).
// Reads only — the app's SwiftData state is never mutated.
//
// Upserts a faithful `Ffi*` projection into the Rust store. Idempotent: every
// upsert is keyed on the entity's primary key; a failed batch rolls back whole.
//
// The per-entity `project(_:)` overloads live in
// SwiftDataStoreImporter+Projections.swift; verify/count logic in
// SwiftDataStoreImporter+Verify.swift.
//
// Design: docs/plans/2026-06-14-swiftdata-import-design.md
// Field fidelity: docs/plans/2026-06-14-cw-store-fidelity-audit.md

// MARK: - ImportReport

/// Per-table row counts produced by an import run. Keys are the cw-store table
/// names. Used by verify mode to assert the store matches the SwiftData source.
public struct ImportReport: Sendable, Equatable {
    // MARK: Lifecycle

    public init(counts: [String: Int] = [:]) {
        self.counts = counts
    }

    // MARK: Public

    public var counts: [String: Int]

    /// Total rows imported across all tables.
    public var total: Int {
        counts.values.reduce(0, +)
    }
}

// MARK: - SwiftDataStoreImporter

@MainActor
public struct SwiftDataStoreImporter {
    // MARK: Lifecycle

    nonisolated public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Public

    /// Default batch size — the bounded fetch window per query.
    public static let defaultBatchSize = 500

    /// Lowercase hyphenated UUID string — the store's id convention.
    /// `nonisolated` so the mirror can project on a background context's thread.
    nonisolated public static func uuid(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    /// Import every supported entity into `store`. Each batch fetches on a
    /// fresh off-main context, projects, and commits as a single transaction —
    /// bounded memory, and the run loop never blocks on disk barriers.
    public func importAll(into store: FieldStore, batchSize: Int = defaultBatchSize) async throws -> ImportReport {
        var counts = try await importLogEntities(into: store, batchSize: batchSize)
        try await counts.merge(importAncillaryEntities(into: store, batchSize: batchSize)) { _, new in new }
        return ImportReport(counts: counts)
    }

    // MARK: Internal

    let container: ModelContainer

    /// Unix seconds (UTC) from a `Date`, the store's timestamp representation.
    nonisolated static func unix(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970)
    }

    /// JSON-encode a `[String]` into the store's text representation (matches the
    /// `@Model`'s JSON-backed array columns). Falls back to `"[]"`.
    nonisolated static func jsonStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    /// The log-shaped tables — QSOs and their satellites. These are the ones
    /// that scale with logbook size (100k+ rows).
    func importLogEntities(into store: FieldStore, batchSize: Int) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["qso"] = try await batchedImport(
            batchSize,
            project: { (model: QSO) in Self.project(model) },
            write: { try store.upsertQsos(qsos: $0) }
        )
        counts["logging_session"] = try await batchedImport(
            batchSize,
            project: { (model: LoggingSession) in
                (Self.project(model), model.isRove ? Self.projectRoveStops(model) : nil)
            },
            write: { items in
                try store.upsertLoggingSessions(items: items.map(\.0))
                // Backfill the structured rove_stop table from the transitional
                // blob (re-runs per app-version bump; replace is idempotent).
                for (session, stops) in items {
                    if let stops {
                        try store.replaceRoveStops(loggingSessionId: session.id, stops: stops)
                    }
                }
            }
        )
        counts["service_presence"] = try await batchedImport(
            batchSize,
            project: { (model: ServicePresence) in Self.project(model) },
            write: { try store.upsertServicePresences(items: $0) }
        )
        counts["session_spot"] = try await batchedImport(
            batchSize,
            project: { (model: SessionSpot) in Self.project(model) },
            write: { try store.upsertSessionSpots(items: $0) }
        )
        counts["activation_metadata"] = try await batchedImport(
            batchSize,
            project: { (model: ActivationMetadata) in Self.project(model) },
            write: { try store.upsertActivationMetadataBatch(items: $0) }
        )
        counts["activity_log"] = try await batchedImport(
            batchSize,
            project: { (model: ActivityLog) in Self.project(model) },
            write: { try store.upsertActivityLogs(items: $0) }
        )
        return counts
    }

    /// Small settings-scale tables — equipment, macros, SDR data, sync state.
    func importAncillaryEntities(into store: FieldStore, batchSize: Int) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["equipment_item"] = try await batchedImport(
            batchSize,
            project: { (model: EquipmentItem) in Self.project(model) },
            write: { try store.upsertEquipmentItems(items: $0) }
        )
        counts["radio_macro"] = try await batchedImport(
            batchSize,
            project: { (model: RadioMacro) in Self.project(model) },
            write: { try store.upsertRadioMacros(items: $0) }
        )
        counts["websdr_recording"] = try await batchedImport(
            batchSize,
            project: { (model: WebSDRRecording) in Self.project(model) },
            write: { try store.upsertWebsdrRecordings(items: $0) }
        )
        counts["websdr_favorite"] = try await batchedImport(
            batchSize,
            project: { (model: WebSDRFavorite) in Self.project(model) },
            write: { try store.upsertWebsdrFavorites(items: $0) }
        )
        counts["upload_destination"] = try await batchedImport(
            batchSize,
            project: { (model: UploadDestination) in Self.project(model) },
            write: { try store.upsertUploadDestinations(items: $0) }
        )
        counts["cloud_sync_metadata"] = try await batchedImport(
            batchSize,
            project: { (model: CloudSyncMetadata) in Self.project(model) },
            write: { try store.upsertCloudSyncMetadataBatch(items: $0) }
        )
        return counts
    }

    /// Page through `Model` rows in `batchSize` chunks, each batch on a fresh
    /// off-main `ModelContext` (PERFORMANCE.md batching pattern: the fresh
    /// context releases SwiftData's row cache between batches, keeping peak
    /// memory ~one batch instead of the whole table — 100k-QSO logs OOM'd
    /// otherwise). Rows are projected to `Sendable` FFI values on the batch's
    /// own thread, then the whole batch commits as one SQLite transaction
    /// (per-row main-thread commits are what watchdog-killed 1.94.0's launch).
    /// Main-actor work per batch is O(1) bookkeeping. `fetchLimit` is always
    /// set, satisfying the project's bounded-fetch rule.
    func batchedImport<Model: PersistentModel, Item: Sendable>(
        _ batchSize: Int,
        project: @escaping @Sendable (Model) throws -> Item,
        write: @escaping @Sendable ([Item]) throws -> Void
    ) async throws -> Int {
        let container = container
        var total = 0
        var offset = 0
        while true {
            let fetchOffset = offset
            let processed = try await Task.detached(priority: .utility) {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                var descriptor = FetchDescriptor<Model>()
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = fetchOffset
                let batch = try context.fetch(descriptor)
                if batch.isEmpty {
                    return 0
                }
                try write(batch.map(project))
                return batch.count
            }.value
            if processed == 0 {
                break
            }
            total += processed
            if processed < batchSize {
                break
            }
            offset += processed
        }
        return total
    }
}
