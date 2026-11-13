// S.A.T. record ingestor
//
// Writes S.A.T.-pushed ADIF records into the shared SwiftData store through
// the same construction path as file imports (`ADIFRecordQSOFactory`), tagged
// `.satTracker`, deduplicated by `QSO.deduplicationKey`, and attached to the
// active logging session when there is one.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SatLogIngestOutcome

enum SatLogIngestOutcome {
    case logged(QSO)
    /// A QSO with the same dedup key (callsign + band + mode + 2-minute
    /// bucket) already exists — typically a retransmit.
    case duplicate
    /// PoLo metadata pseudo-mode (WEATHER / SOLAR / NOTE); never a QSO.
    case skippedMetadata
}

// MARK: - SatLogIngestor

@MainActor
struct SatLogIngestor {
    // MARK: Internal

    /// Half-width of the timestamp window scanned for duplicates. The dedup key
    /// rounds to 2-minute buckets, so ±3 minutes covers every bucket a
    /// retransmitted record can land in.
    static let dedupWindow: TimeInterval = 180

    let context: ModelContext

    /// Insert `record` as a QSO unless it is metadata or a duplicate.
    ///
    /// - Parameters:
    ///   - record: Parsed ADIF record from the tracker.
    ///   - myCallsign: Station callsign fallback when the record carries none.
    ///   - session: Active logging session to attach the QSO to, if any.
    func ingest(
        _ record: ADIFRecord,
        myCallsign: String,
        session: LoggingSession?
    ) throws -> SatLogIngestOutcome {
        if QSOMode.isMetadata(record.mode) {
            return .skippedMetadata
        }

        let stationCallsign = session?.myCallsign ?? myCallsign
        let qso = try ADIFRecordQSOFactory.makeQSO(
            from: record,
            myCallsign: stationCallsign,
            importSource: .satTracker
        )
        if try isDuplicate(qso) {
            return .duplicate
        }

        if qso.myGrid == nil {
            qso.myGrid = session?.myGrid
        }
        if let session {
            qso.loggingSessionId = session.id
            qso.cloudDirtyFlag = true
            qso.modifiedAt = Date()
        }

        context.insert(qso)
        ADIFRecordQSOFactory.attachServicePresence(
            for: qso,
            context: context,
            myCallsign: stationCallsign
        )
        session?.incrementQSOCount()
        try OffMainStoreSeam.commitQSOsWithPresence([qso], sessions: session.map { [$0] } ?? [], in: context)
        return .logged(qso)
    }

    /// The single active `LoggingSession`, mirroring `MacSessionManager`.
    func activeSession() -> LoggingSession? {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Private

    /// Bounded lookup: only QSOs within ±`dedupWindow` of the candidate's
    /// timestamp are fetched, then compared by `deduplicationKey`.
    private func isDuplicate(_ candidate: QSO) throws -> Bool {
        let lower = candidate.timestamp.addingTimeInterval(-Self.dedupWindow)
        let upper = candidate.timestamp.addingTimeInterval(Self.dedupWindow)
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }
        )
        descriptor.fetchLimit = 200
        let key = candidate.deduplicationKey
        return try context.fetch(descriptor).contains { $0.deduplicationKey == key }
    }
}
