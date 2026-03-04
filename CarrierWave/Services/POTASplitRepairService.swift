import CarrierWaveData
import Foundation
import SwiftData

// MARK: - POTASplitRepairService

/// Standalone repair: splits completed POTA sessions that span UTC midnight.
/// Operates directly on ModelContext without LoggingSessionManager dependency.
enum POTASplitRepairService {
    // MARK: Internal

    @MainActor
    static func repair(context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.statusRawValue == "completed" && $0.activationTypeRawValue == "pota"
            }
        )
        descriptor.fetchLimit = 200
        let sessions = try context.fetch(descriptor)

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        var splitCount = 0
        for session in sessions {
            let qsos = try fetchQSOs(for: session.id, context: context)
            let dates = Set(qsos.map { utcCal.startOfDay(for: $0.timestamp) })
            guard dates.count > 1 else {
                continue
            }
            try splitSession(session, qsos: qsos, calendar: utcCal, context: context)
            splitCount += 1
        }

        if splitCount > 0 {
            try context.save()
        }
        return splitCount
    }

    // MARK: Private

    private static func fetchQSOs(for sessionId: UUID, context: ModelContext) throws -> [QSO] {
        let predicate = #Predicate<QSO> { $0.loggingSessionId == sessionId }
        var descriptor = FetchDescriptor<QSO>(
            predicate: predicate, sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 5_000
        return try context.fetch(descriptor)
    }

    private static func splitSession(
        _ session: LoggingSession, qsos: [QSO], calendar: Calendar, context: ModelContext
    ) throws {
        let qsosByDate = Dictionary(grouping: qsos) { calendar.startOfDay(for: $0.timestamp) }
        let sortedDates = qsosByDate.keys.sorted()
        guard sortedDates.count > 1 else {
            return
        }

        let originalEndedAt = session.endedAt
        let originalStops = session.roveStops

        // Trim original session to first UTC date
        session.endedAt = sortedDates[1]
        session.qsoCount = (qsosByDate[sortedDates[0]] ?? []).count

        // Create split sessions for subsequent dates
        var sessionByDate: [Date: LoggingSession] = [sortedDates[0]: session]
        for (index, date) in sortedDates.dropFirst().enumerated() {
            let dayQSOs = qsosByDate[date] ?? []
            let endDate: Date = if index + 2 < sortedDates.count {
                sortedDates[index + 2]
            } else {
                originalEndedAt ?? calendar.date(byAdding: .day, value: 1, to: date)!
            }

            let newSession = cloneSession(session, startDate: date, endDate: endDate, stops: originalStops)
            newSession.qsoCount = dayQSOs.count
            context.insert(newSession)
            sessionByDate[date] = newSession
            for qso in dayQSOs {
                qso.loggingSessionId = newSession.id
            }
        }

        // Reassign recordings
        let origId = session.id
        let pred = #Predicate<WebSDRRecording> { $0.loggingSessionId == origId }
        let recordings = (try? context.fetch(FetchDescriptor(predicate: pred))) ?? []
        for recording in recordings {
            let recDay = calendar.startOfDay(for: recording.startedAt)
            if let target = sessionByDate[recDay] {
                recording.loggingSessionId = target.id
            }
        }
    }

    private static func cloneSession(
        _ source: LoggingSession, startDate: Date, endDate: Date, stops: [RoveStop]
    ) -> LoggingSession {
        let parkRef = stops.last { $0.startedAt <= startDate }?.parkReference ?? source.parkReference
        let newSession = LoggingSession(
            myCallsign: source.myCallsign, startedAt: startDate,
            frequency: source.frequency, mode: source.mode,
            activationType: source.activationType,
            parkReference: parkRef, myGrid: source.myGrid,
            power: source.power, myRig: source.myRig,
            myAntenna: source.myAntenna, myKey: source.myKey,
            myMic: source.myMic, extraEquipment: source.extraEquipment,
            attendees: source.attendees
        )
        newSession.isRove = source.isRove
        newSession.status = .completed
        newSession.endedAt = endDate
        if source.isRove {
            newSession.roveStops = reconstructStops(from: stops, dayStart: startDate, dayEnd: endDate)
        }
        return newSession
    }

    private static func reconstructStops(
        from stops: [RoveStop], dayStart: Date, dayEnd: Date
    ) -> [RoveStop] {
        stops.compactMap { stop in
            let stopEnd = stop.endedAt ?? dayEnd
            guard stopEnd > dayStart, stop.startedAt < dayEnd else {
                return nil
            }
            var split = RoveStop(
                parkReference: stop.parkReference,
                startedAt: max(stop.startedAt, dayStart), myGrid: stop.myGrid
            )
            split.endedAt = min(stopEnd, dayEnd)
            split.qsoCount = stop.qsoCount
            split.notes = stop.notes
            return split
        }
    }
}
