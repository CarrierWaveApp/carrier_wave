import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CompactQSOTable + Hide

extension CompactQSOTable {
    func hideQSOs(ids: [UUID]) {
        var sessionDecrements: [UUID: Int] = [:]
        var hidden: [QSO] = []
        var touchedSessions: [LoggingSession] = []

        for targetId in ids {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { $0.id == targetId },
                limit: 1
            )
            guard let qso = try? modelContext.boundedFetch(descriptor).first else {
                continue
            }

            hideDuplicates(of: qso, hidden: &hidden, sessionDecrements: &sessionDecrements)
        }

        for (sessionId, count) in sessionDecrements {
            let sessionDesc = FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.id == sessionId }
            )
            if let session = try? modelContext.fetch(sessionDesc).first {
                for _ in 0 ..< count {
                    session.decrementQSOCount()
                }
                touchedSessions.append(session)
            }
        }

        try? CwStoreSeams.save(modelContext, qsos: hidden, sessions: touchedSessions)
        selection.subtract(ids)
        loadQSOs()
    }

    /// Hide every visible twin of `qso` in the same 2-minute window (CloudKit
    /// mirrors duplicated rows), collecting the rows touched and the session
    /// counters to decrement.
    func hideDuplicates(of qso: QSO, hidden: inout [QSO], sessionDecrements: inout [UUID: Int]) {
        let call = qso.callsign
        let qsoBand = qso.band
        let qsoMode = qso.mode
        let windowStart = Date(
            timeIntervalSince1970: Double(Int(qso.timestamp.timeIntervalSince1970 / 120) * 120)
        )
        let windowEnd = windowStart.addingTimeInterval(120)

        let dupeDescriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate {
                $0.callsign == call
                    && $0.band == qsoBand
                    && $0.mode == qsoMode
                    && $0.timestamp >= windowStart
                    && $0.timestamp < windowEnd
            },
            limit: 20
        )
        let dupes = (try? modelContext.boundedFetch(dupeDescriptor)) ?? []
        for dupe in dupes where !dupe.isHidden {
            dupe.isHidden = true
            dupe.cloudDirtyFlag = true
            dupe.modifiedAt = Date()
            hidden.append(dupe)
            for presence in dupe.servicePresence where presence.needsUpload {
                presence.needsUpload = false
            }
            if let sessionId = dupe.loggingSessionId {
                sessionDecrements[sessionId, default: 0] += 1
            }
        }
    }
}
