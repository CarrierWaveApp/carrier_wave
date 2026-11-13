import CarrierWaveData
import Foundation
import SwiftData

// MARK: - ContestManager

/// Bridge between `ContestEngine` (actor) and SwiftUI for CW Sweep contest
/// operating. Owns the active definition + a contest `LoggingSession`, assigns
/// serials, enriches each QSO with DXCC country/continent, persists it to
/// SwiftData, tracks dupes / multipliers / off-time / band-changes, and
/// publishes the running score. Resumes an in-progress session on launch and
/// can produce a Cabrillo 3.0 log for submission.
@MainActor
@Observable
final class ContestManager {
    // Note: many of these are written by the persistence/scoring extension in
    // `ContestManager+Persistence.swift`. Cross-file extensions can't reach
    // `private` setters, so the storage is plain `var` — still effectively
    // internal because `ContestManager` itself is internal.
    var definition: ContestDefinition?
    var score = ContestScoreSnapshot()
    var currentSerial = 1
    var lastDupeStatus: ContestDupeStatus?
    var recentQSOs: [ContestLoggedQSO] = []
    var offTimeSummary = OffTimeSummary()
    var bandChangeSummary = BandChangeSummary()

    /// Active schedule occurrence (running now, or the next upcoming one).
    var activeOccurrence: ContestOccurrence?

    /// Selected primary category (e.g. `SOAB`) — drives off-time caps and Cabrillo.
    var categoryID: String?
    /// Optional overlay (e.g. `ROOKIE`, `CLASSIC`).
    var overlayCategoryID: String?
    /// Selected power class (e.g. `HIGH`, `LOW`, `QRP`).
    var powerClass: String?

    // MARK: Internal storage (shared with `ContestManager+Persistence.swift`)

    var engine: ContestEngine?
    var dxcc: DXCCLookupService?
    var modelContext: ModelContext?
    var session: LoggingSession?
    var myCallsign = ""
    var sessionStart = Date()
    var qsoTimestamps: [Date] = []
    var bandTimeline: [(band: String, timestamp: Date)] = []

    var isActive: Bool {
        definition != nil
    }

    func start(
        definition: ContestDefinition,
        myStation: MyStationContext?,
        dxcc: DXCCLookupService?,
        modelContext: ModelContext?,
        sessionStart: Date = Date()
    ) async {
        self.definition = definition
        self.dxcc = dxcc
        self.modelContext = modelContext
        self.sessionStart = sessionStart
        myCallsign = myStation?.callsign ?? ""
        categoryID = nil
        overlayCategoryID = nil
        powerClass = nil
        activeOccurrence = ContestScheduleEvaluator.activeOccurrence(schedule: definition.schedule)
            ?? ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule)

        let existing = resumeOrCreateSession(definition: definition)
        categoryID = session?.contestCategory
        overlayCategoryID = session?.contestOverlayCategory
        powerClass = session?.contestPower

        let startingSerial = existing.compactMap(\.contestSerialSent).max() ?? 0
        let newEngine = ContestEngine(
            definition: definition,
            myStation: myStation,
            startingSerial: startingSerial
        )
        engine = newEngine

        let records = existing.map { recordFromQSO($0) }
        if !records.isEmpty {
            await newEngine.loadExistingQSOs(records)
        }
        applyExisting(existing)

        await refreshScore()
        currentSerial = await newEngine.currentSerial()
        recomputeConstraints()
    }

    func endContest() {
        definition = nil
        engine = nil
        dxcc = nil
        modelContext = nil
        session = nil
        score = ContestScoreSnapshot()
        currentSerial = 1
        lastDupeStatus = nil
        recentQSOs = []
        qsoTimestamps = []
        bandTimeline = []
        offTimeSummary = OffTimeSummary()
        bandChangeSummary = BandChangeSummary()
        activeOccurrence = nil
    }

    // MARK: - Category selection

    func setCategory(_ id: String?) {
        categoryID = id
        session?.contestCategory = id
        recomputeConstraints()
    }

    func setOverlay(_ id: String?) {
        overlayCategoryID = id
        session?.contestOverlayCategory = id
    }

    func setPowerClass(_ value: String?) {
        powerClass = value
        session?.contestPower = value
    }

    // MARK: - Operating

    /// Live dupe check for the entry field (does not mutate state).
    func checkDupe(callsign: String, band: String, mode: String) async -> ContestDupeStatus {
        guard let engine else {
            return .newStation
        }
        let status = await engine.dupeStatus(callsign: callsign, band: band, mode: mode)
        lastDupeStatus = status
        return status
    }

    /// Register a completed QSO. Scores it through the engine, persists it to
    /// SwiftData, and advances the sent serial for non-dupes.
    @discardableResult
    func logQSO(_ entry: ContestQSOEntry) async -> ContestDupeStatus {
        guard let engine else {
            return .newStation
        }
        let trimmed = entry.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            return .newStation
        }

        var resolved = entry
        resolved.callsign = trimmed
        let serialToSend = currentSerial
        let entity = dxcc?.lookup(trimmed)
        let record = makeRecord(entry: resolved, serialSent: serialToSend, entity: entity)

        let status = await engine.registerQSO(record)
        lastDupeStatus = status
        var qsoID: UUID?
        if status != .dupe {
            _ = await engine.nextSerial()
            qsoID = persist(entry: resolved, serialSent: serialToSend, country: entity?.name)
        }
        currentSerial = await engine.currentSerial()

        qsoTimestamps.append(record.timestamp)
        bandTimeline.append((band: record.band, timestamp: record.timestamp))
        recentQSOs.insert(
            ContestLoggedQSO(
                record: record,
                status: status,
                prefix: ContestCallsign.wpxPrefix(trimmed),
                qsoID: qsoID
            ),
            at: 0
        )
        if recentQSOs.count > 50 {
            recentQSOs.removeLast(recentQSOs.count - 50)
        }

        await refreshScore()
        recomputeConstraints()
        return status
    }

    func refreshScore() async {
        guard let engine else {
            return
        }
        score = await engine.scoreSnapshot()
    }
}
