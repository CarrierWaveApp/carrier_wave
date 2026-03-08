import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Session Grouping

extension QSOProcessingActor {
    /// Result of grouping orphan POTA QSOs into sessions
    struct SessionGroupingResult: Sendable {
        let sessionsCreated: Int
        let qsosAssigned: Int
    }

    /// Find POTA QSOs without a logging session and group them into new sessions.
    /// Groups by (parkReference, UTC date, myCallsign) — same logic as POTAActivation.groupQSOs.
    /// Creates a completed LoggingSession for each group and assigns loggingSessionId.
    func groupOrphanPOTAQSOsIntoSessions(
        container: ModelContainer
    ) async throws -> SessionGroupingResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch QSOs with park references but no session
        let orphanQSOs = try fetchOrphanPOTAQSOs(context: context)
        guard !orphanQSOs.isEmpty else {
            return SessionGroupingResult(sessionsCreated: 0, qsosAssigned: 0)
        }

        // Group by (park, UTC date, callsign)
        let groups = groupByActivation(orphanQSOs)

        // Fetch existing session keys to avoid duplicates
        let existingSessionKeys = try fetchExistingSessionKeys(context: context)

        var sessionsCreated = 0
        var qsosAssigned = 0
        var unsavedCount = 0

        for (key, qsoSnapshots) in groups {
            try Task.checkCancellation()

            // Skip if a session already exists for this activation
            guard !existingSessionKeys.contains(key) else {
                continue
            }

            let session = createSession(from: qsoSnapshots, context: context)
            context.insert(session)

            // Assign session ID to all QSOs in the group
            for snapshot in qsoSnapshots {
                assignSessionId(session.id, toQSOWithId: snapshot.id, context: context)
                qsosAssigned += 1
            }

            sessionsCreated += 1
            unsavedCount += qsoSnapshots.count + 1

            if unsavedCount >= 200 {
                try context.save()
                unsavedCount = 0
                await Task.yield()
            }
        }

        if unsavedCount > 0 {
            try context.save()
        }

        return SessionGroupingResult(
            sessionsCreated: sessionsCreated, qsosAssigned: qsosAssigned
        )
    }

    // MARK: - Private Helpers

    /// Lightweight snapshot for grouping without holding managed objects
    private struct QSOSnapshot {
        let id: UUID
        let myCallsign: String
        let mode: String
        let frequency: Double?
        let parkReference: String
        let timestamp: Date
    }

    private func fetchOrphanPOTAQSOs(context: ModelContext) throws -> [QSOSnapshot] {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate {
                $0.parkReference != nil && $0.loggingSessionId == nil
                    && !$0.isHidden && !$0.isActivityLogQSO
            }
        )
        descriptor.fetchLimit = 5_000
        let qsos = try context.fetch(descriptor)

        return qsos.compactMap { qso -> QSOSnapshot? in
            guard let parkRef = qso.parkReference, !parkRef.isEmpty else {
                return nil
            }
            let mode = qso.mode.uppercased()
            guard !Self.sessionGroupingMetadataModes.contains(mode) else {
                return nil
            }
            return QSOSnapshot(
                id: qso.id,
                myCallsign: qso.myCallsign,
                mode: qso.mode,
                frequency: qso.frequency,
                parkReference: parkRef,
                timestamp: qso.timestamp
            )
        }
    }

    private static let sessionGroupingMetadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Group QSO snapshots by (parkReference, UTC date, myCallsign)
    private func groupByActivation(_ snapshots: [QSOSnapshot]) -> [String: [QSOSnapshot]] {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var groups: [String: [QSOSnapshot]] = [:]
        for snapshot in snapshots {
            let parkRef = snapshot.parkReference.uppercased()
            let utcDate = utcCal.startOfDay(for: snapshot.timestamp)
            let callsign = snapshot.myCallsign.uppercased()
            let key = "\(parkRef)|\(callsign)|\(formatter.string(from: utcDate))"
            groups[key, default: []].append(snapshot)
        }
        return groups
    }

    /// Fetch keys for existing completed POTA sessions to avoid duplicates.
    /// Key format: "PARKREF|CALLSIGN|YYYY-MM-DD"
    private func fetchExistingSessionKeys(context: ModelContext) throws -> Set<String> {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.statusRawValue == "completed" && $0.activationTypeRawValue == "pota"
            }
        )
        descriptor.fetchLimit = 1_000
        let sessions = try context.fetch(descriptor)

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var keys = Set<String>()
        for session in sessions {
            guard let parkRef = session.parkReference else {
                continue
            }
            let utcDate = utcCal.startOfDay(for: session.startedAt)
            let callsign = session.myCallsign.uppercased()
            let key = "\(parkRef.uppercased())|\(callsign)|\(formatter.string(from: utcDate))"
            keys.insert(key)
        }
        return keys
    }

    /// Create a completed LoggingSession from a group of QSO snapshots
    private func createSession(
        from snapshots: [QSOSnapshot], context: ModelContext
    ) -> LoggingSession {
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        let first = sorted[0]

        // Derive most common mode and latest frequency
        let modeCounts = Dictionary(grouping: sorted, by: { $0.mode }).mapValues(\.count)
        let primaryMode = modeCounts.max(by: { $0.value < $1.value })?.key ?? first.mode
        let lastFrequency = sorted.last(where: { $0.frequency != nil })?.frequency

        let session = LoggingSession(
            myCallsign: first.myCallsign,
            startedAt: first.timestamp,
            frequency: lastFrequency,
            mode: primaryMode,
            activationType: .pota,
            parkReference: first.parkReference
        )
        session.status = .completed
        session.endedAt = sorted.last?.timestamp ?? first.timestamp
        session.qsoCount = sorted.count
        session.cloudDirtyFlag = true
        return session
    }

    private func assignSessionId(
        _ sessionId: UUID, toQSOWithId qsoId: UUID, context: ModelContext
    ) {
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == qsoId })
        descriptor.fetchLimit = 1
        if let qso = try? context.fetch(descriptor).first {
            qso.loggingSessionId = sessionId
        }
    }
}
