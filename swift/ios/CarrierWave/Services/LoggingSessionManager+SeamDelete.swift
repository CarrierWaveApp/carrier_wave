import CarrierWaveData
import SwiftData
import UIKit

// MARK: - Coordinated session-delete seam writes

extension LoggingSessionManager {
    /// Hide every QSO in the session and clear their upload flags so they never
    /// sync. Returns the hidden QSOs so the coordinated seam write can upsert their
    /// new state to cw-store. Best-effort: returns `[]` if the fetch fails.
    func hideQSOs(inSession sessionId: UUID) -> [QSO] {
        let predicate = #Predicate<QSO> { $0.loggingSessionId == sessionId }
        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate,
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        guard let qsos = try? modelContext.boundedFetch(descriptor) else {
            return []
        }
        for qso in qsos {
            qso.isHidden = true
            for presence in qso.servicePresence where presence.needsUpload {
                presence.needsUpload = false
            }
        }
        return qsos
    }

    /// Delete every SessionSpot for the session from SwiftData. Returns them so the
    /// coordinated seam write can remove their cw-store rows under the same window.
    func deleteSessionSpots(inSession sessionId: UUID) -> [SessionSpot] {
        let predicate = #Predicate<SessionSpot> { $0.loggingSessionId == sessionId }
        guard let spots = try? modelContext.fetch(FetchDescriptor(predicate: predicate)) else {
            return []
        }
        for spot in spots {
            modelContext.delete(spot)
        }
        return spots
    }

    /// Commit a session delete as one coordinated multi-entity seam write: the
    /// deleted session, its removed SessionSpots, and its hidden QSOs all reach
    /// cw-store under a single mirror-suppression window in `on` mode. The caller
    /// has already applied every SwiftData mutation (hide QSOs, `context.delete`
    /// spots + session); this only routes the save. Falls back to a plain save in
    /// `off` mode / when the experiment is disabled.
    func commitSessionDelete(
        session: LoggingSession,
        spots: [SessionSpot],
        hiddenQSOs: [QSO]
    ) {
        guard var batch = SeamWriteBatch.make() else {
            try? modelContext.save()
            return
        }
        for qso in hiddenQSOs {
            batch.upsertQSO(qso)
        }
        for spot in spots {
            batch.delete(spot)
        }
        batch.delete(session)
        try? batch.commit(in: modelContext)
    }
}
