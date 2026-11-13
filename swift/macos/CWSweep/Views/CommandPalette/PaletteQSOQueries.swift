import CarrierWaveData
import Foundation
import SwiftData

// MARK: - PaletteQSOQueries

/// Bounded QSO / session lookups shared by the radio palette's informational
/// commands (`FIND`, `LAST`, `COUNT`) and their vim-mode counterparts
/// (`:find`, `:last`, `:count`) so both surfaces answer identically.
///
/// Every fetch goes through `BoundedDescriptor` (hard `fetchLimit`) and QSO
/// results are deduped by UUID before being returned — CloudKit mirrors can
/// hold several copies of the same QSO, so raw row counts overstate reality.
@MainActor
enum PaletteQSOQueries {
    // MARK: Internal

    /// Maximum rows examined by `matchingQSOs`. A result set of exactly this
    /// size means the match count is a lower bound.
    static let findLimit = 20

    /// Most recent active `LoggingSession`, if any.
    static func activeSession(in context: ModelContext) -> LoggingSession? {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// QSO count on the active session, or nil when no session is active.
    static func sessionQSOCount(in context: ModelContext) -> Int? {
        activeSession(in: context)?.qsoCount
    }

    /// QSOs whose callsign contains `callsign`, newest first, capped at `findLimit`.
    static func matchingQSOs(callsign: String, in context: ModelContext) -> [QSOSearchResult] {
        let upper = callsign.uppercased()
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign.localizedStandardContains(upper)
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)],
            limit: findLimit
        )
        guard let qsos = try? context.boundedFetch(descriptor) else {
            return []
        }
        return dedupedResults(qsos)
    }

    /// The most recent `count` real QSOs (metadata pseudo-modes excluded).
    static func recentQSOs(count: Int, in context: ModelContext) -> [QSOSearchResult] {
        let fetchLimit = min(max(count, 1) + 10, BoundedDescriptor<QSO>.maxLimit)
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                !qso.isHidden && !qso.callsign.isEmpty
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)],
            limit: fetchLimit
        )
        guard let qsos = try? context.boundedFetch(descriptor) else {
            return []
        }
        return Array(
            dedupedResults(qsos.filter { !QSOMode.isMetadata($0.mode) })
                .prefix(count)
        )
    }

    // MARK: Private

    /// Snapshot rows, dropping CloudKit duplicates by QSO UUID (first wins).
    private static func dedupedResults(_ qsos: [QSO]) -> [QSOSearchResult] {
        var seen = Set<UUID>()
        return qsos.compactMap { qso in
            seen.insert(qso.id).inserted ? QSOSearchResult(from: qso) : nil
        }
    }
}

// MARK: - QSOSearchResult

/// Lightweight snapshot for displaying QSO search results in the palette
/// summary and the vim status line.
struct QSOSearchResult: Identifiable {
    // MARK: Lifecycle

    init(from qso: QSO) {
        id = qso.id
        callsign = qso.callsign
        timestamp = qso.timestamp
        band = qso.band
        mode = qso.mode
    }

    // MARK: Internal

    let id: UUID
    let callsign: String
    let timestamp: Date
    let band: String
    let mode: String
}
