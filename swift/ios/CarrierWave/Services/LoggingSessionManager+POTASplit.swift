import CarrierWaveData
import Foundation
import SwiftData

// MARK: - UTC Midnight POTA Split

/// Splits POTA sessions at UTC midnight so each session covers one activation date.
/// POTA groups QSOs by (park, callsign, UTC date), so a session spanning UTC midnight
/// produces duplicate park entries. Splitting at midnight aligns sessions with POTA's
/// grouping and avoids inflated park counts on brag sheets.
extension LoggingSessionManager {
    /// Split a completed POTA session at UTC day boundaries.
    /// Creates new sessions for each additional UTC date, reassigning QSOs and rove stops.
    /// Call after `session.end()` and before the final `modelContext.save()`.
    /// One-time repair: fix broken v1 splits and split remaining multi-day POTA sessions.
    /// Returns the number of sessions repaired or split.
    func repairExistingPOTASessions() -> Int {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.statusRawValue == "completed" && $0.activationTypeRawValue == "pota"
            }
        )
        descriptor.fetchLimit = 200
        let potaSessions = (try? modelContext.fetch(descriptor)) ?? []
        print("POTA split repair: found \(potaSessions.count) completed POTA sessions")

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        // Phase 1: fix broken v1 splits (endedAt <= startedAt)
        let fixedCount = fixBrokenV1Splits(potaSessions, calendar: utcCal)

        // Phase 2: split any remaining multi-day sessions
        var splitCount = 0
        for session in potaSessions {
            let qsos = fetchSessionQSOs(session.id)
            let dates = Set(qsos.map { utcCal.startOfDay(for: $0.timestamp) })
            if dates.count > 1 {
                print("POTA split repair: splitting session \(session.parkReference ?? "?") "
                    + "with \(qsos.count) QSOs across \(dates.count) dates")
                splitPOTAAtUTCMidnight(session)
                splitCount += 1
            }
        }

        if fixedCount > 0 || splitCount > 0 {
            try? modelContext.save()
        }
        print("POTA split repair: fixed=\(fixedCount), split=\(splitCount)")
        return fixedCount + splitCount
    }

    /// Split a multi-day POTA session at UTC midnight. Mutates the original session
    /// in place and inserts a new session per extra UTC date, reassigning QSOs and
    /// recordings. Returns every entity it touched (besides the original session,
    /// which the caller already owns) so the caller can route one coordinated
    /// `SeamWriteBatch` — the save flushes all of them at once.
    @discardableResult
    func splitPOTAAtUTCMidnight(_ session: LoggingSession) -> SessionSplitChanges {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let allQSOs = fetchSessionQSOs(session.id)
        guard !allQSOs.isEmpty else {
            return SessionSplitChanges()
        }

        let qsosByDate = Dictionary(grouping: allQSOs) { qso in
            utcCalendar.startOfDay(for: qso.timestamp)
        }
        let sortedDates = qsosByDate.keys.sorted()
        guard sortedDates.count > 1 else {
            return SessionSplitChanges()
        }

        let originalEndedAt = session.endedAt
        let ctx = POTASplitContext(
            stops: session.roveStops, allQSOs: allQSOs, calendar: utcCalendar
        )

        // Keep original session for the first UTC date
        let firstDayQSOs = qsosByDate[sortedDates[0]] ?? []
        let secondDayMidnight = sortedDates[1]
        session.endedAt = secondDayMidnight
        session.qsoCount = firstDayQSOs.count
        session.roveStops = splitStops(ctx, dayStart: sortedDates[0], midnight: secondDayMidnight)

        // Create new sessions for each subsequent UTC date
        var changes = SessionSplitChanges()
        var sessionByDate: [Date: LoggingSession] = [sortedDates[0]: session]
        for (index, date) in sortedDates.dropFirst().enumerated() {
            let dayQSOs = qsosByDate[date] ?? []
            let nextMidnight: Date = if index + 2 < sortedDates.count {
                sortedDates[index + 2]
            } else {
                originalEndedAt ?? utcCalendar.date(byAdding: .day, value: 1, to: date)!
            }
            let newSession = createSplitSession(from: session, ctx: ctx, date: date, endDate: nextMidnight)
            newSession.qsoCount = dayQSOs.count
            modelContext.insert(newSession)
            sessionByDate[date] = newSession
            changes.sessions.append(newSession)
            for qso in dayQSOs {
                qso.loggingSessionId = newSession.id
            }
            changes.qsos.append(contentsOf: dayQSOs)
        }

        changes.recordings = reassignRecordings(
            originalSessionId: session.id, sessionByDate: sessionByDate, calendar: utcCalendar
        )
        return changes
    }

    /// Route a coordinated seam write for a session split: the primary (original)
    /// session plus every entity the split touched (new sessions, reassigned QSOs,
    /// reassigned recordings) reach cw-store under one mirror-suppression window in
    /// `on` mode. Falls back to a plain save in `off` mode / when disabled.
    func commitSessionSplit(primarySession: LoggingSession, changes: SessionSplitChanges) {
        guard var batch = SeamWriteBatch.make() else {
            try? modelContext.save()
            return
        }
        batch.upsert(primarySession)
        for session in changes.sessions {
            batch.upsert(session)
        }
        for qso in changes.qsos {
            batch.upsertQSO(qso)
        }
        for recording in changes.recordings {
            batch.upsert(recording)
        }
        for metadata in changes.metadata {
            batch.upsert(metadata)
        }
        try? batch.commit(in: modelContext)
    }
}

// MARK: - SessionSplitChanges

/// The entities a POTA midnight split mutated, surfaced so a save site can route
/// them through one coordinated `SeamWriteBatch` instead of a suppressed save that
/// would drop the co-mutated rows from cw-store.
struct SessionSplitChanges {
    /// Newly inserted split sessions (the original is owned by the caller).
    var sessions: [LoggingSession] = []
    /// QSOs reassigned to a split session (`loggingSessionId` changed).
    var qsos: [QSO] = []
    /// WebSDR recordings reassigned to a split session.
    var recordings: [WebSDRRecording] = []
    /// ActivationMetadata mutated during session end (e.g. average-WPM backfill)
    /// that must ride the same coordinated seam write.
    var metadata: [ActivationMetadata] = []
}

// MARK: - POTASplitContext

/// Shared context for POTA split operations, bundling parameters that are reused across helpers.
private struct POTASplitContext {
    let stops: [RoveStop]
    let allQSOs: [QSO]
    let calendar: Calendar
}

// MARK: - Private Helpers

private extension LoggingSessionManager {
    func fetchSessionQSOs(_ sessionId: UUID) -> [QSO] {
        let predicate = #Predicate<QSO> { $0.loggingSessionId == sessionId }
        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)],
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        return (try? modelContext.boundedFetch(descriptor)) ?? []
    }

    func createSplitSession(
        from session: LoggingSession, ctx: POTASplitContext,
        date: Date, endDate: Date
    ) -> LoggingSession {
        let parkAtMidnight = parkActiveAt(date: date, stops: ctx.stops)
            ?? session.parkReference

        let newSession = LoggingSession(
            myCallsign: session.myCallsign, startedAt: date,
            frequency: session.frequency, mode: session.mode,
            activationType: session.activationType,
            parkReference: parkAtMidnight, myGrid: session.myGrid,
            power: session.power, myRig: session.myRig,
            myAntenna: session.myAntenna, myKey: session.myKey,
            myMic: session.myMic, extraEquipment: session.extraEquipment,
            attendees: session.attendees
        )
        newSession.isRove = session.isRove
        newSession.status = .completed
        newSession.endedAt = endDate
        newSession.roveStops = splitStops(ctx, dayStart: date, midnight: endDate)
        return newSession
    }

    /// Return rove stops that overlap a given UTC day, splitting any that span midnight.
    func splitStops(_ ctx: POTASplitContext, dayStart: Date, midnight: Date) -> [RoveStop] {
        ctx.stops.compactMap { stop in
            splitSingleStop(stop, dayStart: dayStart, midnight: midnight, ctx: ctx)
        }
    }

    func splitSingleStop(
        _ stop: RoveStop, dayStart: Date, midnight: Date, ctx: POTASplitContext
    ) -> RoveStop? {
        let stopEnd = stop.endedAt ?? midnight

        // Stop entirely outside this day
        guard stopEnd > dayStart, stop.startedAt < midnight else {
            return nil
        }

        let clampedStart = max(stop.startedAt, dayStart)
        let clampedEnd = min(stopEnd, midnight)
        let stopDayStart = ctx.calendar.startOfDay(for: stop.startedAt)

        guard clampedStart < clampedEnd || stopDayStart == dayStart else {
            return nil
        }

        let sliceCount = ctx.allQSOs.filter { qso in
            let qsoDay = ctx.calendar.startOfDay(for: qso.timestamp)
            return qsoDay == dayStart
                && qso.timestamp >= clampedStart
                && qso.timestamp < clampedEnd
        }.count

        var splitStop = RoveStop(
            parkReference: stop.parkReference,
            startedAt: clampedStart, myGrid: stop.myGrid
        )
        splitStop.endedAt = clampedEnd
        splitStop.qsoCount = sliceCount
        splitStop.notes = stop.notes
        return splitStop
    }

    /// Reassign WebSDR recordings to the correct split session based on startedAt
    /// timestamp. Returns the recordings that were actually reassigned so they can
    /// ride the coordinated seam write.
    @discardableResult
    func reassignRecordings(
        originalSessionId: UUID, sessionByDate: [Date: LoggingSession], calendar: Calendar
    ) -> [WebSDRRecording] {
        let predicate = #Predicate<WebSDRRecording> { $0.loggingSessionId == originalSessionId }
        let recordings = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        var reassigned: [WebSDRRecording] = []
        for recording in recordings {
            let recDate = calendar.startOfDay(for: recording.startedAt)
            if let target = sessionByDate[recDate] {
                recording.loggingSessionId = target.id
                reassigned.append(recording)
            }
        }
        return reassigned
    }

    // MARK: - V1 Split Repair

    /// Fix broken sessions created by v1 split (endedAt == startedAt, 0 rove stops).
    func fixBrokenV1Splits(_ sessions: [LoggingSession], calendar: Calendar) -> Int {
        let broken = sessions.filter { session in
            guard let ended = session.endedAt else {
                return false
            }
            return ended <= session.startedAt
        }
        guard !broken.isEmpty else {
            return 0
        }

        for session in broken {
            let qsos = fetchSessionQSOs(session.id)
            guard !qsos.isEmpty else {
                continue
            }

            // Fix endedAt from QSO timestamps
            let lastQSO = qsos.map(\.timestamp).max() ?? session.startedAt
            session.endedAt = lastQSO

            // Reconstruct rove stops from QSOs
            if session.isRove {
                session.roveStops = reconstructStopsFromQSOs(qsos)
            }

            // Reassign recordings from sibling (original pre-split session)
            reassignRecordingsFromSibling(to: session, allSessions: sessions, calendar: calendar)
        }
        return broken.count
    }

    /// Reconstruct approximate rove stops by walking QSOs in time order and tracking park changes.
    func reconstructStopsFromQSOs(_ qsos: [QSO]) -> [RoveStop] {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        var stops: [RoveStop] = []
        var curPark: String?
        var curStart: Date?
        var curGrid: String?
        var curCount = 0

        for qso in sorted {
            let park = qso.parkReference ?? ""
            if park != curPark {
                if let cp = curPark, !cp.isEmpty, let cs = curStart {
                    var stop = RoveStop(parkReference: cp, startedAt: cs, myGrid: curGrid)
                    stop.endedAt = qso.timestamp
                    stop.qsoCount = curCount
                    stops.append(stop)
                }
                curPark = park; curStart = qso.timestamp; curGrid = qso.myGrid; curCount = 1
            } else {
                curCount += 1
            }
        }
        if let cp = curPark, !cp.isEmpty, let cs = curStart {
            var stop = RoveStop(parkReference: cp, startedAt: cs, myGrid: curGrid)
            stop.endedAt = sorted.last?.timestamp ?? cs
            stop.qsoCount = curCount
            stops.append(stop)
        }
        return stops
    }

    /// Find the sibling session (original pre-split) and move its recordings to target if timestamps match.
    func reassignRecordingsFromSibling(
        to target: LoggingSession, allSessions: [LoggingSession], calendar: Calendar
    ) {
        let sibling = allSessions.first { candidate in
            candidate.id != target.id
                && candidate.endedAt == target.startedAt
                && candidate.myCallsign == target.myCallsign
        }
        guard let sibling else {
            return
        }
        let sibId = sibling.id
        let predicate = #Predicate<WebSDRRecording> { $0.loggingSessionId == sibId }
        let recordings = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        let targetDay = calendar.startOfDay(for: target.startedAt)
        for recording in recordings where calendar.startOfDay(for: recording.startedAt) == targetDay {
            recording.loggingSessionId = target.id
        }
    }

    /// Find the park reference that was active at a given date (midnight boundary).
    func parkActiveAt(date: Date, stops: [RoveStop]) -> String? {
        for stop in stops {
            let stopEnd = stop.endedAt ?? .distantFuture
            if stop.startedAt <= date, stopEnd > date {
                return stop.parkReference
            }
        }
        return stops.last { $0.startedAt <= date }?.parkReference
    }
}
