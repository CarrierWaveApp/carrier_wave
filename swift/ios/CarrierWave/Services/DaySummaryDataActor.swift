import CarrierWaveData
import Foundation
import SwiftData

// MARK: - DaySummaryDataActor

/// Background loader for `DaySummaryView`. Pages QSOs and overlapping
/// `LoggingSession`s for a UTC day off the main thread, then builds a
/// snapshot for the view to render.
actor DaySummaryDataActor {
    // MARK: Lifecycle

    init(container: ModelContainer, activityLogId: UUID?) {
        self.container = container
        self.activityLogId = activityLogId
    }

    // MARK: Internal

    static func utcDayWindow(for date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Top-level load. Scans are serialised (QSO scan completes before
    /// session scan starts) to honour the no-parallel-full-table-scans rule.
    func load(for date: Date) throws -> DaySummarySnapshot {
        let (startOfDay, endOfDay) = Self.utcDayWindow(for: date)
        let dayQSOs = try loadDayQSOs(startOfDay: startOfDay, endOfDay: endOfDay)
        let sessions = try loadOverlappingSessions(startOfDay: startOfDay, endOfDay: endOfDay)

        return Self.buildSnapshot(.init(
            date: startOfDay,
            endOfDay: endOfDay,
            dayQSOs: dayQSOs,
            sessions: sessions,
            activityLogId: activityLogId,
            now: Date()
        ))
    }

    // MARK: Private

    private let container: ModelContainer
    private let activityLogId: UUID?

    private func loadDayQSOs(startOfDay: Date, endOfDay: Date) throws -> [DaySummaryQSO] {
        let batchSize = BoundedDescriptor<QSO>.maxLimit
        var offset = 0
        var snapshots: [DaySummaryQSO] = []

        while true {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let predicate = #Predicate<QSO> { qso in
                !qso.isHidden
                    && qso.timestamp >= startOfDay
                    && qso.timestamp < endOfDay
            }
            let descriptor = BoundedDescriptor<QSO>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.timestamp, order: .forward)],
                limit: batchSize,
                offset: offset
            )
            let batch = try context.boundedFetch(descriptor)
            for qso in batch where !QSOMode.isMetadata(qso.mode) {
                snapshots.append(DaySummaryQSO(qso: qso))
            }

            if batch.count < batchSize {
                break
            }
            offset += batchSize
        }

        return snapshots
    }

    private func loadOverlappingSessions(
        startOfDay: Date,
        endOfDay: Date
    ) throws -> [SessionFacts] {
        let batchSize = BoundedDescriptor<LoggingSession>.maxLimit
        var offset = 0
        var sessions: [SessionFacts] = []
        let excludedId = activityLogId

        // Sessions that could overlap [startOfDay, endOfDay) must start
        // within a reasonable lookback. 30 days covers everything except
        // pathologically-long sessions (the always-on hunter log is
        // excluded by id, so it doesn't matter that it spans much longer).
        let lookbackStart = startOfDay.addingTimeInterval(-30 * 24 * 3_600)

        while true {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            // Coarse predicate. Force-unwrap inside `#Predicate` is
            // unreliable, so the precise overlap + exclusion check happens
            // in-memory after the fetch.
            let predicate = #Predicate<LoggingSession> { session in
                session.startedAt < endOfDay && session.startedAt >= lookbackStart
            }
            let descriptor = BoundedDescriptor<LoggingSession>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.startedAt, order: .forward)],
                limit: batchSize,
                offset: offset
            )
            let batch = try context.boundedFetch(descriptor)

            for session in batch {
                if let excludedId, session.id == excludedId {
                    continue
                }
                if let endedAt = session.endedAt, endedAt < startOfDay {
                    continue
                }
                sessions.append(SessionFacts(session: session))
            }

            if batch.count < batchSize {
                break
            }
            offset += batch.count
        }

        return sessions
    }
}

// MARK: - Snapshot assembly (pure)

extension DaySummaryDataActor {
    /// Inputs to `buildSnapshot`. Grouped so the call site stays under
    /// the function-parameter-count limit and the body stays focused.
    struct BuildInput {
        let date: Date
        let endOfDay: Date
        let dayQSOs: [DaySummaryQSO]
        let sessions: [SessionFacts]
        let activityLogId: UUID?
        let now: Date
    }

    /// Pure transformation of paged data into a snapshot. Static so tests
    /// can exercise it without a model container.
    static func buildSnapshot(_ input: BuildInput) -> DaySummarySnapshot {
        let grouped = groupByLoggingSession(input.dayQSOs)
        let sessionCards = makeSessionCards(grouped: grouped, input: input)
        let hunterCard = makeHunterCardIfAny(grouped: grouped, input: input)
        let looseCard = makeLooseCardIfAny(grouped: grouped, input: input)

        return DaySummarySnapshot(
            date: input.date,
            dayQSOs: input.dayQSOs,
            sessions: sessionCards,
            hunterCard: hunterCard,
            looseCard: looseCard,
            bandCounts: aggregateBands(input.dayQSOs.map(\.band)),
            modeCounts: aggregateModes(input.dayQSOs.map(\.mode)),
            dxccCount: Set(input.dayQSOs.compactMap(\.dxcc)).count,
            stateAbbreviations: dayStates(input.dayQSOs)
        )
    }

    private static func groupByLoggingSession(
        _ qsos: [DaySummaryQSO]
    ) -> [UUID?: [DaySummaryQSO]] {
        var grouped: [UUID?: [DaySummaryQSO]] = [:]
        for qso in qsos {
            grouped[qso.loggingSessionId, default: []].append(qso)
        }
        return grouped
    }

    private static func makeSessionCards(
        grouped: [UUID?: [DaySummaryQSO]],
        input: BuildInput
    ) -> [SessionCardData] {
        var cards: [SessionCardData] = []
        for session in input.sessions {
            let sliced = grouped[session.id] ?? []
            guard !sliced.isEmpty else {
                continue
            }
            cards.append(makeSessionCard(
                session: session,
                sliced: sliced,
                dayStart: input.date,
                dayEnd: input.endOfDay,
                now: input.now
            ))
        }
        cards.sort { ($0.slicedQSOs.first?.timestamp ?? .distantPast)
            < ($1.slicedQSOs.first?.timestamp ?? .distantPast)
        }
        return cards
    }

    private static func makeHunterCardIfAny(
        grouped: [UUID?: [DaySummaryQSO]],
        input: BuildInput
    ) -> SessionCardData? {
        guard let logId = input.activityLogId,
              let hunterQSOs = grouped[logId],
              !hunterQSOs.isEmpty
        else {
            return nil
        }
        return makeHunterCard(qsos: hunterQSOs, dayStart: input.date)
    }

    private static func makeLooseCardIfAny(
        grouped: [UUID?: [DaySummaryQSO]],
        input: BuildInput
    ) -> SessionCardData? {
        let loadedSessionIds = Set(input.sessions.map(\.id))
        var looseQSOs: [DaySummaryQSO] = grouped[nil] ?? []
        for (key, value) in grouped {
            guard let key else {
                continue
            }
            if key == input.activityLogId {
                continue
            }
            if loadedSessionIds.contains(key) {
                continue
            }
            looseQSOs.append(contentsOf: value)
        }
        guard !looseQSOs.isEmpty else {
            return nil
        }
        looseQSOs.sort { $0.timestamp < $1.timestamp }
        return makeLooseCard(qsos: looseQSOs, dayStart: input.date)
    }

    private static func dayStates(_ qsos: [DaySummaryQSO]) -> Set<String> {
        Set(qsos.compactMap { qso -> String? in
            guard let raw = qso.state else {
                return nil
            }
            let abbr = USStates.normalizeAbbreviation(raw)
            return USStates.abbreviations.contains(abbr) ? abbr : nil
        })
    }

    private static func makeSessionCard(
        session: SessionFacts,
        sliced: [DaySummaryQSO],
        dayStart: Date,
        dayEnd: Date,
        now: Date
    ) -> SessionCardData {
        let icon = typeIcon(for: session)
        let title = sessionTitle(for: session)
        let endTime = session.endedAt ?? dayEnd
        let timeRange = session.startedAt ... max(session.startedAt, endTime)
        let isLive = session.endedAt == nil && session.startedAt <= now

        let startedBefore = session.startedAt < dayStart
        let endsAfter = (session.endedAt ?? .distantFuture) > dayEnd
        let badge: ContinuationBadge? = switch (startedBefore, endsAfter) {
        case (true, true): .both
        case (true, false): .continued
        case (false, true): .continues
        case (false, false): nil
        }

        let sorted = sliced.sorted { $0.timestamp < $1.timestamp }
        return SessionCardData(
            id: "session-\(session.id.uuidString)",
            kind: .session(session.id),
            title: title,
            typeIcon: icon,
            timeRange: timeRange,
            isLive: isLive,
            continuationBadge: badge,
            slicedQSOs: sorted,
            bandPills: aggregateBands(sorted.map(\.band)),
            modePills: aggregateModes(sorted.map(\.mode))
        )
    }

    private static func makeHunterCard(
        qsos: [DaySummaryQSO],
        dayStart: Date
    ) -> SessionCardData {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        return SessionCardData(
            id: "hunter-\(Int(dayStart.timeIntervalSince1970))",
            kind: .hunter,
            title: "Hunter Log",
            typeIcon: .hunter,
            timeRange: nil,
            isLive: false,
            continuationBadge: nil,
            slicedQSOs: sorted,
            bandPills: aggregateBands(sorted.map(\.band)),
            modePills: aggregateModes(sorted.map(\.mode))
        )
    }

    private static func makeLooseCard(
        qsos: [DaySummaryQSO],
        dayStart: Date
    ) -> SessionCardData {
        SessionCardData(
            id: "loose-\(Int(dayStart.timeIntervalSince1970))",
            kind: .loose,
            title: "Loose QSOs",
            typeIcon: .loose,
            timeRange: nil,
            isLive: false,
            continuationBadge: nil,
            slicedQSOs: qsos,
            bandPills: aggregateBands(qsos.map(\.band)),
            modePills: aggregateModes(qsos.map(\.mode))
        )
    }

    private static func typeIcon(for session: SessionFacts) -> SessionTypeIcon {
        if session.programs.contains("pota") {
            return .pota
        }
        if session.programs.contains("sota") {
            return .sota
        }
        if session.programs.contains("wwff") {
            return .wwff
        }
        if session.programs.contains("aoa") {
            return .aoa
        }
        if session.programs.contains("tota") {
            return .tota
        }
        if session.mode.uppercased() == "FT8" {
            return .ft8
        }
        if !(session.customTitle ?? "").isEmpty {
            return .contest
        }
        return .casual
    }

    private static func sessionTitle(for session: SessionFacts) -> String {
        if let title = session.customTitle, !title.isEmpty {
            return title
        }
        if let park = session.parkReference, !park.isEmpty {
            return park
        }
        if let summit = session.sotaReference, !summit.isEmpty {
            return summit
        }
        if let wwff = session.wwffReference, !wwff.isEmpty {
            return wwff
        }
        return session.activationTypeDisplay
    }

    private static func aggregateBands(_ values: [String]) -> [DayBandCount] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }
            .map { DayBandCount(band: $0.key, count: $0.value) }
    }

    private static func aggregateModes(_ values: [String]) -> [DayModeCount] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }
            .map { DayModeCount(mode: $0.key, count: $0.value) }
    }
}
