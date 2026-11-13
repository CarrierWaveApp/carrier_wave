// Operator Profile Service
//
// Local-first operator profile cache backed by the GRDB `operator_profiles`
// table. Populated from prior QSOs at first launch (offline source of truth)
// and refreshed by QRZ enrichment writebacks. Lookups consult this service
// first so the UI can render instantly from disk while the network calls
// fan out behind the scenes.
//
// HamDB results are intentionally NOT written back here — they exist only
// to fill nil fields when QRZ is unavailable, never to overwrite a richer
// QRZ/QSO-derived record.

import CarrierWaveData
import Foundation
import OSLog
import SwiftData

// MARK: - OperatorProfileService

@MainActor
final class OperatorProfileService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    /// Read-only snapshot of cache health for the Settings UI.
    struct Status: Equatable {
        let cachedCount: Int
        /// Newest `modifiedAt` (or `timestamp`) of the QSOs already
        /// consumed by the backfill. `nil` until the first run completes.
        let backfillWatermark: Date?
        let isStarted: Bool
        let isRebuilding: Bool
    }

    static let shared = OperatorProfileService()

    /// Age past which a QRZ-enriched row no longer short-circuits a live
    /// lookup (people change names, QTHs, and callsigns). The row itself
    /// is kept — it still renders as an offline fallback — but callers
    /// treat it as a hint, not an answer.
    nonisolated static let enrichmentStaleness: TimeInterval = 7 * 24 * 3_600

    /// Whether a manual rebuild is currently in flight. Used to disable
    /// the rebuild button and surface progress in the UI.
    private(set) var isRebuilding = false

    /// Idempotent. Brings up the GRDB store, primes the in-memory snapshot
    /// from `operator_profiles`, then kicks off the prior-QSO backfill.
    func start(container: ModelContainer) async {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        guard let store = QueryStoreBootstrap.ensureStore() else {
            logger.error("start: QueryStore unavailable, lookups will fall back to network")
            return
        }
        self.store = store
        self.container = container

        await primeSnapshot(from: store)

        // Backfill is idle work — defer to a detached task so it never
        // races startup-critical scans (stats, sync). Watermark gates it
        // so subsequent launches only pick up new/edited QSOs.
        Task.detached(priority: .utility) { [weak self] in
            await self?.runBackfillIfNeeded()
        }
    }

    /// Synchronous read from the in-memory snapshot. Returns `nil` if the
    /// service hasn't started, the callsign isn't cached, or the stored
    /// row contains no meaningful data.
    nonisolated func cachedInfoSync(for callsign: String) -> CallsignInfo? {
        let normalized = callsign.uppercased()
        guard let row = storage.value(for: normalized), row.hasMeaningfulData else {
            return nil
        }
        return Self.makeInfo(from: row)
    }

    /// Async read. Falls back to a direct DB hit if the in-memory snapshot
    /// hasn't been primed yet (e.g. lookup arrives during launch).
    func info(for callsign: String) async -> CallsignInfo? {
        if let cached = cachedInfoSync(for: callsign) {
            return cached
        }
        guard let store else {
            return nil
        }
        let normalized = callsign.uppercased()
        let row = try? await store.operatorProfile(callsign: normalized)
        guard let row, row.hasMeaningfulData else {
            return nil
        }
        storage.set(row, for: normalized)
        return Self.makeInfo(from: row)
    }

    /// Snapshot of cache health. Returns zeros if the GRDB store hasn't
    /// come up yet (e.g. during early launch or after a setup failure).
    func status() async -> Status {
        guard let store else {
            return Status(
                cachedCount: 0,
                backfillWatermark: nil,
                isStarted: hasStarted,
                isRebuilding: isRebuilding
            )
        }
        let count = await (try? store.operatorProfileCount()) ?? 0
        let watermark: Date?
        do {
            watermark = try await store.operatorBackfillWatermark()
        } catch {
            watermark = nil
        }
        return Status(
            cachedCount: count,
            backfillWatermark: watermark,
            isStarted: hasStarted,
            isRebuilding: isRebuilding
        )
    }

    /// Reset the watermark and re-run the QSO-history backfill from
    /// scratch. QRZ-enriched rows fresher than `enrichmentStaleness` are
    /// preserved; stale enrichment is overwritten so a rebuild can actually
    /// clear outdated profiles.
    func rebuild() async {
        guard let store, container != nil, !isRebuilding else {
            return
        }
        isRebuilding = true
        defer { isRebuilding = false }
        try? await store.setOperatorBackfillWatermark(.distantPast)
        await runBackfillIfNeeded()
    }

    /// Persist enrichment from a remote lookup. Only QRZ writebacks reach
    /// this method — HamDB is excluded by the caller. No-op if the new
    /// info doesn't add or change any meaningful field vs. the cached row.
    func record(_ info: CallsignInfo) async {
        guard info.source == .qrz else {
            return
        }
        guard let store else {
            return
        }
        let normalized = info.callsign.uppercased()
        let existing = storage.value(for: normalized)
        let merged = Self.mergedRow(existing: existing, info: info)
        if let existing, !Self.differs(existing, merged) {
            return
        }
        storage.set(merged, for: normalized)
        do {
            try await store.upsertOperatorProfile(merged)
        } catch {
            logger.error(
                "record failed for \(normalized, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Drop the cached row for a callsign. Called when a QRZ lookup
    /// forward-resolves `callsign` to a different current call — the fresh
    /// data lands under the new call via `record`, and keeping the old-call
    /// row would serve the stale identity forever (rows have no TTL).
    func forget(_ callsign: String) async {
        let normalized = callsign.uppercased()
        storage.remove(for: normalized)
        guard let store else {
            return
        }
        do {
            try await store.deleteOperatorProfile(callsign: normalized)
        } catch {
            logger.error(
                "forget failed for \(normalized, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: Private

    private struct BackfillResult {
        let aggregated: [String: OperatorProfileRow]
        let watermark: Date
    }

    nonisolated private static let logger = Logger(
        subsystem: "com.jsvana.CarrierWave",
        category: "OperatorProfileService"
    )

    /// Lock-protected snapshot for synchronous main-thread access (UI placeholders).
    nonisolated private let storage = ProfileSnapshotStorage()

    private var hasStarted = false
    private var store: QueryStore?
    private var container: ModelContainer?

    nonisolated private var logger: Logger {
        Self.logger
    }

    private func primeSnapshot(from store: QueryStore) async {
        // We don't expose a "fetchAll" API on the store on purpose — the
        // snapshot is filled lazily by `info(for:)`. Only seed with the
        // small set of recently-touched callsigns the watermark indicates
        // are worth keeping warm, to bound launch memory.
        // For now, leaving the in-memory cache empty at start is fine:
        // the first lookup of any callsign warms it. The DB hit is fast.
        _ = store
    }
}

// MARK: - Mapping helpers

extension OperatorProfileService {
    nonisolated private static func makeInfo(from row: OperatorProfileRow) -> CallsignInfo {
        let inferred: CallsignInfoSource = row.source == "qrz" ? .qrz : .hamdb
        return CallsignInfo(
            callsign: row.callsign,
            name: row.name,
            firstName: row.firstName,
            nickname: row.nickname,
            qth: row.qth,
            state: row.state,
            country: row.country,
            grid: row.grid,
            licenseClass: row.licenseClass,
            source: inferred,
            lookupDate: row.enrichedAt ?? row.updatedAt
        )
    }

    nonisolated private static func makeRow(from qso: QSO) -> OperatorProfileRow? {
        let callsign = qso.callsign.uppercased()
        guard !callsign.isEmpty else {
            return nil
        }
        let row = OperatorProfileRow(
            callsign: callsign,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            grid: qso.theirGrid,
            licenseClass: qso.theirLicenseClass,
            source: "qso",
            updatedAt: qso.modifiedAt ?? qso.timestamp,
            enrichedAt: nil
        )
        return row.hasMeaningfulData ? row : nil
    }

    nonisolated private static func mergeQSORow(
        existing: OperatorProfileRow?,
        new: OperatorProfileRow
    ) -> OperatorProfileRow {
        guard let existing else {
            return new
        }
        // Newer QSO wins on per-field basis, falling back to existing for nils.
        let useNew = new.updatedAt >= existing.updatedAt
        let primary = useNew ? new : existing
        let fallback = useNew ? existing : new
        return OperatorProfileRow(
            callsign: existing.callsign,
            name: primary.name ?? fallback.name,
            firstName: primary.firstName ?? fallback.firstName,
            nickname: primary.nickname ?? fallback.nickname,
            qth: primary.qth ?? fallback.qth,
            state: primary.state ?? fallback.state,
            country: primary.country ?? fallback.country,
            grid: primary.grid ?? fallback.grid,
            licenseClass: primary.licenseClass ?? fallback.licenseClass,
            source: existing.source == "qrz" ? "qrz" : primary.source,
            updatedAt: max(primary.updatedAt, fallback.updatedAt),
            enrichedAt: existing.enrichedAt
        )
    }

    nonisolated private static func mergedRow(
        existing: OperatorProfileRow?,
        info: CallsignInfo
    ) -> OperatorProfileRow {
        // QRZ wins on every field that QRZ provides; existing fills any
        // gaps QRZ didn't return.
        OperatorProfileRow(
            callsign: info.callsign,
            name: info.name ?? existing?.name,
            firstName: info.firstName ?? existing?.firstName,
            nickname: info.nickname ?? existing?.nickname,
            qth: info.qth ?? existing?.qth,
            state: info.state ?? existing?.state,
            country: info.country ?? existing?.country,
            grid: info.grid ?? existing?.grid,
            licenseClass: info.licenseClass ?? existing?.licenseClass,
            source: "qrz",
            updatedAt: Date(),
            enrichedAt: Date()
        )
    }

    nonisolated private static func differs(
        _ lhs: OperatorProfileRow,
        _ rhs: OperatorProfileRow
    ) -> Bool {
        lhs.name != rhs.name
            || lhs.firstName != rhs.firstName
            || lhs.nickname != rhs.nickname
            || lhs.qth != rhs.qth
            || lhs.state != rhs.state
            || lhs.country != rhs.country
            || lhs.grid != rhs.grid
            || lhs.licenseClass != rhs.licenseClass
    }
}

// MARK: - Backfill

extension OperatorProfileService {
    private func runBackfillIfNeeded() async {
        guard let store, let container else {
            return
        }
        let watermark = await (try? store.operatorBackfillWatermark()) ?? .distantPast
        let result = await aggregateBackfill(container: container, since: watermark)
        guard !result.aggregated.isEmpty else {
            return
        }
        await persistBackfill(
            store: store,
            aggregated: result.aggregated,
            newWatermark: result.watermark
        )
    }

    nonisolated private func aggregateBackfill(
        container: ModelContainer,
        since watermark: Date
    ) async -> BackfillResult {
        let predicate: Predicate<QSO>?
        if watermark == .distantPast {
            predicate = nil
        } else {
            predicate = #Predicate<QSO> { qso in
                (qso.modifiedAt ?? qso.timestamp) > watermark
            }
        }
        let fetch = BatchedFetch<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        var aggregated: [String: OperatorProfileRow] = [:]
        var newWatermark = watermark
        do {
            try await fetch.forEach(container: container) { qso in
                let mark = qso.modifiedAt ?? qso.timestamp
                if mark > newWatermark {
                    newWatermark = mark
                }
                guard let row = Self.makeRow(from: qso) else {
                    return
                }
                aggregated[row.callsign] = Self.mergeQSORow(
                    existing: aggregated[row.callsign],
                    new: row
                )
            }
        } catch {
            logger.error(
                "backfill aggregate failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        return BackfillResult(aggregated: aggregated, watermark: newWatermark)
    }

    private func persistBackfill(
        store: QueryStore,
        aggregated: [String: OperatorProfileRow],
        newWatermark: Date
    ) async {
        // Don't clobber FRESH QRZ-enriched rows. Stale enrichment (older
        // than `enrichmentStaleness`) is fair game — preserving it forever
        // meant a manual rebuild could never fix an outdated profile; the
        // next lookup re-enriches from QRZ anyway.
        var toWrite: [OperatorProfileRow] = []
        for (callsign, row) in aggregated {
            let existing = try? await store.operatorProfile(callsign: callsign)
            if let existing,
               existing.source == "qrz",
               let enrichedAt = existing.enrichedAt,
               Date().timeIntervalSince(enrichedAt) < Self.enrichmentStaleness
            {
                continue
            }
            if let existing, !Self.differs(existing, row) {
                continue
            }
            toWrite.append(row)
            storage.set(row, for: callsign)
        }
        do {
            try await store.upsertOperatorProfiles(toWrite)
            try await store.setOperatorBackfillWatermark(newWatermark)
            let count = toWrite.count
            let mark = newWatermark.timeIntervalSince1970
            logger.info(
                "backfill wrote \(count, privacy: .public) profiles, watermark=\(mark, privacy: .public)"
            )
        } catch {
            logger.error(
                "backfill persist failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

// MARK: - ProfileSnapshotStorage

/// Lock-protected callsign → row dictionary for synchronous main-thread reads.
///
/// Whole class is `nonisolated` — `default-isolation=MainActor` would
/// otherwise pin this to MainActor, but `cachedInfoSync` is nonisolated
/// and must call `value(for:)` synchronously. Thread safety comes from
/// `NSLock`, not actor isolation.
nonisolated private final class ProfileSnapshotStorage: @unchecked Sendable {
    // MARK: Internal

    func value(for callsign: String) -> OperatorProfileRow? {
        lock.withLock { rows[callsign] }
    }

    func set(_ row: OperatorProfileRow, for callsign: String) {
        lock.withLock { rows[callsign] = row }
    }

    func remove(for callsign: String) {
        lock.withLock { rows[callsign] = nil }
    }

    // MARK: Private

    private let lock = NSLock()
    private var rows: [String: OperatorProfileRow] = [:]
}
