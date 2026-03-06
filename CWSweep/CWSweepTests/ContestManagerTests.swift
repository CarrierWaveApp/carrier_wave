import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - Test Helpers

private func makeTestDefinition() -> ContestDefinition {
    ContestDefinition(
        id: "test-contest",
        name: "Test Contest",
        cabrilloCategoryContest: "TEST",
        bands: ["20m", "40m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: [
            ExchangeField(id: "rst", label: "RST", type: .rst, defaultValue: "599"),
        ]),
        multipliers: ContestMultipliers(types: [.dxcc], perBand: true),
        scoring: ContestScoring(rules: [ScoringRule(condition: .any, points: 1)]),
        dupeRules: ContestDupeRules(perBand: true, perMode: false),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )
}

private func makeTestSession() -> LoggingSession {
    LoggingSession(
        myCallsign: "W6JSV",
        contestId: "test-contest",
        contestCategory: "SINGLE-OP",
        contestPower: "HIGH",
        contestBands: "ALL"
    )
}

// MARK: - ContestManager Tests

@Test @MainActor func contestManagerStartSetsActive() async {
    let manager = ContestManager()
    #expect(!manager.isActive)

    await manager.startContest(definition: makeTestDefinition(), session: makeTestSession())
    #expect(manager.isActive)
    #expect(manager.definition?.id == "test-contest")
}

@Test @MainActor func contestManagerEndClearsState() async {
    let manager = ContestManager()
    await manager.startContest(definition: makeTestDefinition(), session: makeTestSession())
    #expect(manager.isActive)

    manager.endContest()
    #expect(!manager.isActive)
    #expect(manager.definition == nil)
    #expect(manager.activeSession == nil)
}

@Test @MainActor func contestManagerToggleOperatingMode() {
    let manager = ContestManager()
    #expect(manager.operatingMode == .cq)

    manager.toggleOperatingMode()
    #expect(manager.operatingMode == .sp)

    manager.toggleOperatingMode()
    #expect(manager.operatingMode == .cq)
}

@Test @MainActor func contestManagerCheckDupeDelegates() async {
    let manager = ContestManager()
    await manager.startContest(definition: makeTestDefinition(), session: makeTestSession())

    // First check should be new station
    let status = await manager.checkDupe(callsign: "K3LR", band: "20m")
    #expect(status == .newStation)
}

@Test @MainActor func contestManagerBandStack() {
    let manager = ContestManager()
    manager.rememberBand("20m", frequency: 14.030)
    manager.rememberBand("40m", frequency: 7.025)

    #expect(manager.recallBand("20m") == 14.030)
    #expect(manager.recallBand("40m") == 7.025)
    #expect(manager.recallBand("80m") == nil)
}

@Test @MainActor func contestManagerScoreUpdatesAfterQSO() async {
    let manager = ContestManager()
    await manager.startContest(definition: makeTestDefinition(), session: makeTestSession())

    let snapshot = QSOContestSnapshot(
        callsign: "K3LR",
        band: "20m",
        mode: "CW",
        timestamp: Date(),
        rstSent: "599",
        rstReceived: "599",
        exchangeSent: "599",
        exchangeReceived: "599",
        country: "United States",
        dxcc: 291
    )

    await manager.logContestQSO(snapshot)
    #expect(manager.score.totalQSOs == 1)
    #expect(manager.score.totalPoints > 0)
}
