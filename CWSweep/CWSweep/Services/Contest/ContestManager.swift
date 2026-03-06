import CarrierWaveData
import Foundation

/// Bridge between ContestEngine (actor) and SwiftUI.
/// Follows the same @MainActor @Observable pattern as ClusterManager.
@MainActor
@Observable
final class ContestManager {
    // MARK: Internal

    // MARK: - Published State

    private(set) var activeSession: LoggingSession?
    private(set) var definition: ContestDefinition?
    private(set) var score = ContestScoreSnapshot()
    private(set) var currentSerial: Int = 1
    private(set) var lastDupeStatus: DupeStatus?
    private(set) var operatingMode: ContestOperatingMode = .cq
    private(set) var bandStack: [String: Double] = [:]

    // MARK: - Services

    let keyerService = CWKeyerService()

    var isActive: Bool {
        definition != nil
    }

    // MARK: - Public API

    func startContest(
        definition: ContestDefinition,
        session: LoggingSession,
        existingQSOs: [QSOContestSnapshot] = []
    ) async {
        self.definition = definition
        activeSession = session
        let newEngine = ContestEngine(definition: definition)
        engine = newEngine

        if !existingQSOs.isEmpty {
            await newEngine.loadExistingQSOs(existingQSOs)
        }

        await refreshScore()
        currentSerial = await newEngine.currentSerial()
    }

    func endContest() {
        definition = nil
        activeSession = nil
        engine = nil
        score = ContestScoreSnapshot()
        currentSerial = 1
        lastDupeStatus = nil
        bandStack = [:]
    }

    func checkDupe(callsign: String, band: String) async -> DupeStatus {
        guard let engine else {
            return .newStation
        }
        let status = await engine.dupeStatus(callsign: callsign, band: band)
        lastDupeStatus = status
        return status
    }

    func logContestQSO(_ snapshot: QSOContestSnapshot) async {
        guard let engine else {
            return
        }
        let status = await engine.registerQSO(snapshot)
        lastDupeStatus = status
        await refreshScore()
        currentSerial = await engine.currentSerial()
    }

    func nextSerial() async -> Int {
        guard let engine else {
            return 1
        }
        let serial = await engine.nextSerial()
        currentSerial = await engine.currentSerial()
        return serial
    }

    func suggestedExchange(for callsign: String) async -> String? {
        guard let engine else {
            return nil
        }
        return await engine.suggestedExchange(for: callsign)
    }

    func toggleOperatingMode() {
        operatingMode = operatingMode == .cq ? .sp : .cq
    }

    func rememberBand(_ band: String, frequency: Double) {
        bandStack[band] = frequency
    }

    func recallBand(_ band: String) -> Double? {
        bandStack[band]
    }

    func refreshScore() async {
        guard let engine else {
            return
        }
        score = await engine.scoreSnapshot()
    }

    func rate(overMinutes minutes: Int = 60) async -> Double {
        guard let engine else {
            return 0
        }
        return await engine.rate(overMinutes: minutes)
    }

    func rateTimeSeries(bucketMinutes: Int = 60) async -> [(date: Date, count: Int)] {
        guard let engine else {
            return []
        }
        return await engine.rateTimeSeries(bucketMinutes: bucketMinutes)
    }

    func multiplierValues(for type: MultiplierType, band: String?) async -> Set<String> {
        guard let engine else {
            return []
        }
        return await engine.multiplierValues(for: type, band: band)
    }

    // MARK: Private

    private var engine: ContestEngine?
    private let templateLoader = ContestTemplateLoader()
}
