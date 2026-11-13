import CarrierWaveData
import UIKit

// MARK: - ContestManager

/// Bridge between `ContestEngine` (actor) and SwiftUI for iOS contest
/// logging. Holds selected category/overlay, tracks off-time compliance,
/// and exposes the current score snapshot to views.
@MainActor
@Observable
final class ContestManager {
    // MARK: Internal

    private(set) var definition: ContestDefinition?
    private(set) var score = ContestScoreSnapshot()
    private(set) var currentSerial: Int = 1
    var lastDupeStatus: ContestDupeStatus?

    /// Selected primary category (e.g. `SOAB-HP`, `MULTI-ONE`).
    var categoryID: String?
    /// Optional overlay (e.g. `YL`, `ROOKIE`, `TB-WIRES`).
    var overlayCategoryID: String?

    private(set) var offTimeSummary = OffTimeSummary()
    private(set) var bandChangeSummary = BandChangeSummary()

    /// Active schedule occurrence (start/end) for a contest that is currently
    /// running, or the next upcoming one.
    private(set) var activeOccurrence: ContestOccurrence?

    var isActive: Bool {
        definition != nil
    }

    // MARK: - Public API

    func startContest(
        definition: ContestDefinition,
        session: LoggingSession,
        myStation: MyStationContext? = nil,
        existingQSOs: [ContestQSORecord] = []
    ) async {
        self.definition = definition
        categoryID = session.contestCategory
        overlayCategoryID = session.contestOverlayCategory
        activeOccurrence = ContestScheduleEvaluator.activeOccurrence(schedule: definition.schedule)
            ?? ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule)

        let newEngine = ContestEngine(definition: definition, myStation: myStation)
        engine = newEngine

        if !existingQSOs.isEmpty {
            await newEngine.loadExistingQSOs(existingQSOs)
        }

        await refreshScore()
        currentSerial = await newEngine.currentSerial()
        recomputeConstraints(session: session, records: existingQSOs)
    }

    func endContest() {
        definition = nil
        engine = nil
        score = ContestScoreSnapshot()
        currentSerial = 1
        lastDupeStatus = nil
        categoryID = nil
        overlayCategoryID = nil
        offTimeSummary = OffTimeSummary()
        bandChangeSummary = BandChangeSummary()
        activeOccurrence = nil
    }

    func checkDupe(callsign: String, band: String, mode: String) async -> ContestDupeStatus {
        guard let engine else {
            return .newStation
        }
        let status = await engine.dupeStatus(callsign: callsign, band: band, mode: mode)
        lastDupeStatus = status
        return status
    }

    func logContestQSO(_ record: ContestQSORecord, session: LoggingSession) async {
        guard let engine else {
            return
        }
        let status = await engine.registerQSO(record)
        lastDupeStatus = status
        await refreshScore()
        currentSerial = await engine.currentSerial()
        recomputeConstraints(session: session, append: record)
    }

    func nextSerial() async -> Int {
        guard let engine else {
            return 1
        }
        let serial = await engine.nextSerial()
        currentSerial = await engine.currentSerial()
        return serial
    }

    func suggestedExchange(for callsign: String) async -> [String: String]? {
        guard let engine else {
            return nil
        }
        return await engine.suggestedExchange(for: callsign)
    }

    func refreshScore() async {
        guard let engine else {
            return
        }
        score = await engine.scoreSnapshot()
    }

    /// Rescore from an up-to-date QSO list (call after edits or deletions).
    func rescore(
        _ records: [ContestQSORecord],
        session: LoggingSession
    ) async {
        guard let engine else {
            return
        }
        await engine.rescore(records)
        await refreshScore()
        currentSerial = await engine.currentSerial()
        recomputeConstraints(session: session, records: records)
    }

    // MARK: Private

    private var engine: ContestEngine?
    private var cachedTimestamps: [Date] = []
    private var cachedBandTimeline: [(band: String, timestamp: Date)] = []

    private func recomputeConstraints(
        session: LoggingSession,
        records: [ContestQSORecord]
    ) {
        cachedTimestamps = records.map(\.timestamp)
        cachedBandTimeline = records.map { ($0.band, $0.timestamp) }
        evaluateConstraints(session: session)
    }

    private func recomputeConstraints(session: LoggingSession, append: ContestQSORecord) {
        cachedTimestamps.append(append.timestamp)
        cachedBandTimeline.append((append.band, append.timestamp))
        evaluateConstraints(session: session)
    }

    private func evaluateConstraints(session: LoggingSession) {
        guard let definition else {
            return
        }
        offTimeSummary = OffTimeTracker.summarize(
            qsoTimestamps: cachedTimestamps,
            sessionStart: session.startedAt,
            sessionEnd: session.endedAt,
            categoryID: categoryID,
            rules: definition.operatingConstraints?.offTime
        )
        bandChangeSummary = BandChangeTracker.summarize(
            qsos: cachedBandTimeline,
            categoryID: categoryID,
            rules: definition.operatingConstraints?.bandChanges
        )
    }
}
