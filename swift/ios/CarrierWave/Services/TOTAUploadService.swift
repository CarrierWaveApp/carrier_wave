// Session-bound TOTA upload helper.
//
// Bridges between a `LoggingSession` and `TOTAClient.uploadADIF` so the
// returned official points value can be persisted back to the session and
// the corresponding `ActivityItem` can be re-published with the official
// score (per docs/features/tota-scoring.md, Brag Sheet section).
//
// The current Settings → manual ADIF upload path doesn't carry a session
// reference, so this helper exists for the next iteration that adds an
// in-app session-bound TOTA upload step (parallel to the POTA one).

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

@MainActor
enum TOTAUploadService {
    // MARK: Internal

    /// Upload the given ADIF for `session` and, on success, persist the
    /// server-returned points + re-publish the brag-sheet activity item.
    /// Returns the persisted points value, or nil on upload failure.
    @discardableResult
    static func uploadAndPersist(
        adif: String,
        session: LoggingSession,
        qsos: [QSO],
        modelContext: ModelContext,
        client: TOTAClient = .shared
    ) async -> Double? {
        do {
            let response = try await client.uploadADIF(
                adif,
                filename: TOTAClient.defaultFilename()
            )
            guard response.success, let points = response.activation?.points else {
                return nil
            }
            session.totaOfficialPoints = points
            try? modelContext.save()
            updateBragSheetActivity(session: session, qsos: qsos, modelContext: modelContext)
            return points
        } catch {
            return nil
        }
    }

    // MARK: Private

    /// Find the session-completed activity item for `session` and overwrite
    /// `totaScore` + `totaScoreConfidence` so clubmates' brag-sheet card
    /// reflects the official score.
    private static func updateBragSheetActivity(
        session: LoggingSession,
        qsos: [QSO],
        modelContext: ModelContext
    ) {
        let callsign = session.stationCallsign ?? session.myCallsign
        let typeRaw = ActivityType.sessionCompleted.rawValue
        let sessionStart = session.startedAt
        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate {
                $0.isOwn
                    && $0.callsign == callsign
                    && $0.activityTypeRawValue == typeRaw
                    && $0.timestamp >= sessionStart
            }
        )
        descriptor.fetchLimit = 5
        guard let items = try? modelContext.fetch(descriptor) else {
            return
        }
        // Find the closest item by start-time match (within a 2 min window).
        let candidate = items.first { item in
            abs(item.timestamp.timeIntervalSince(sessionStart)) < 120
        }
        guard let item = candidate, var details = item.details else {
            return
        }
        let inputs = TOTAEnrichmentService.makeScoringInputs(for: session, qsos: qsos)
        details.totaScore = session.totaOfficialPoints ?? TOTAScoringEngine.score(inputs).total
        details.totaScoreConfidence = session.totaOfficialPoints != nil ? "official" : "estimated"
        item.details = details
        try? modelContext.save()
    }
}
