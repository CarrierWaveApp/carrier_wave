import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Session Grouping

extension QSOProcessingActor {
    /// Result of grouping orphan POTA QSOs into sessions
    struct SessionGroupingResult {
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

    /// Create LoggingSessions directly from POTA activation metadata snapshots.
    /// More reliable than re-deriving groups from QSO data since it uses the
    /// activation context that POTA's API provides (park, date, callsign, timestamps).
    func createSessionsFromPOTAActivations(
        _ snapshots: [POTAActivationSnapshot],
        container: ModelContainer
    ) async throws -> SessionGroupingResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let existingKeys = try fetchExistingSessionKeys(context: context)
        let dateFormatter = Self.potaDateFormatter

        var sessionsCreated = 0
        var qsosAssigned = 0
        var unsavedCount = 0

        for snapshot in snapshots {
            try Task.checkCancellation()

            let callsign = snapshot.callsign.uppercased()
            let ref = snapshot.reference.uppercased()
            let key = "\(ref)|\(callsign)|\(snapshot.date)"

            guard !existingKeys.contains(key) else {
                continue
            }

            let timestamps = parseActivationTimestamps(
                snapshot, dateFormatter: dateFormatter
            )

            let session = buildSessionFromSnapshot(
                snapshot, startedAt: timestamps.start, endedAt: timestamps.end
            )

            // Find and assign matching orphan QSOs
            let assigned = try assignOrphanQSOs(
                to: session, snapshot: snapshot, context: context
            )
            qsosAssigned += assigned

            context.insert(session)
            sessionsCreated += 1
            unsavedCount += assigned + 1

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

    // MARK: - Activation Session Helpers

    private static let potaDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private struct ActivationTimestamps {
        let start: Date
        let end: Date
    }

    private func parseActivationTimestamps(
        _ snapshot: POTAActivationSnapshot,
        dateFormatter: DateFormatter
    ) -> ActivationTimestamps {
        let fallbackDate = dateFormatter.date(
            from: "\(snapshot.date)T00:00:00"
        ) ?? Date()
        let start = snapshot.firstQso.flatMap {
            dateFormatter.date(from: $0)
        } ?? fallbackDate
        let end = snapshot.lastQso.flatMap {
            dateFormatter.date(from: $0)
        } ?? start
        return ActivationTimestamps(start: start, end: end)
    }

    private func buildSessionFromSnapshot(
        _ snapshot: POTAActivationSnapshot,
        startedAt: Date,
        endedAt: Date
    ) -> LoggingSession {
        let session = LoggingSession(
            myCallsign: snapshot.callsign,
            startedAt: startedAt,
            frequency: nil,
            activationType: .pota,
            parkReference: snapshot.reference
        )
        session.status = .completed
        session.endedAt = endedAt
        session.qsoCount = snapshot.totalQSOs
        session.cloudDirtyFlag = true
        return session
    }

    /// Find orphan QSOs matching this activation and assign the session ID.
    /// Returns the number of QSOs assigned.
    private func assignOrphanQSOs(
        to session: LoggingSession,
        snapshot: POTAActivationSnapshot,
        context: ModelContext
    ) throws -> Int {
        let ref = snapshot.reference.uppercased()
        let callsign = snapshot.callsign.uppercased()
        let sessionId = session.id

        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate {
                $0.parkReference == ref
                    && $0.loggingSessionId == nil
                    && !$0.isHidden && !$0.isActivityLogQSO
            },
            limit: 500
        )
        let candidates = try context.boundedFetch(descriptor)

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        let sessionDay = utcCal.startOfDay(for: session.startedAt)
        var assigned = 0
        var modeSet = false

        for qso in candidates {
            let qsoDay = utcCal.startOfDay(for: qso.timestamp)
            let qsoCall = qso.myCallsign.uppercased()
            guard qsoDay == sessionDay, qsoCall == callsign else {
                continue
            }
            let mode = qso.mode.uppercased()
            guard !QSOMode.isMetadata(mode) else {
                continue
            }
            qso.loggingSessionId = sessionId
            assigned += 1

            // Derive mode/frequency from first matched QSO
            if !modeSet {
                session.mode = qso.mode
                modeSet = true
            }
            if session.frequency == nil {
                session.frequency = qso.frequency
            }
        }

        session.qsoCount = max(session.qsoCount, assigned)
        return assigned
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
        let predicate = #Predicate<QSO> {
            $0.parkReference != nil && $0.loggingSessionId == nil
                && !$0.isHidden && !$0.isActivityLogQSO
        }
        let batchSize = BoundedDescriptor<QSO>.maxLimit
        var offset = 0
        var snapshots: [QSOSnapshot] = []

        while true {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: predicate,
                limit: batchSize,
                offset: offset
            )
            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            for qso in batch {
                guard let parkRef = qso.parkReference, !parkRef.isEmpty else {
                    continue
                }
                let mode = qso.mode.uppercased()
                guard !QSOMode.isMetadata(mode) else {
                    continue
                }
                snapshots.append(QSOSnapshot(
                    id: qso.id,
                    myCallsign: qso.myCallsign,
                    mode: qso.mode,
                    frequency: qso.frequency,
                    parkReference: parkRef,
                    timestamp: qso.timestamp
                ))
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }

        return snapshots
    }

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
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == qsoId },
            limit: 1
        )
        if let qso = try? context.boundedFetch(descriptor).first {
            qso.loggingSessionId = sessionId
        }
    }
}
