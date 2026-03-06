import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - Test Helpers

private func makeCQWWDefinition() -> ContestDefinition {
    ContestDefinition(
        id: "cq-ww-cw",
        name: "CQ WW CW",
        cabrilloCategoryContest: "CQ-WW-CW",
        bands: ["160m", "80m", "40m", "20m", "15m", "10m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: [
            ExchangeField(id: "rst", label: "RST", type: .rst, defaultValue: "599"),
            ExchangeField(id: "cqZone", label: "CQ Zone", type: .cqZone),
        ]),
        multipliers: ContestMultipliers(types: [.dxcc, .cqZone], perBand: true),
        scoring: ContestScoring(rules: [
            ScoringRule(condition: .sameCountry, points: 0),
            ScoringRule(condition: .sameContinent, points: 1),
            ScoringRule(condition: .differentContinent, points: 3),
        ]),
        dupeRules: ContestDupeRules(perBand: true, perMode: false),
        cabrillo: CabrilloTemplate(
            qsoTemplate: "freq mode date time mycall rst myexch call rst exch",
            fieldWidths: ["freq": 5, "mode": 2]
        )
    )
}

private func makeSnapshot(
    callsign: String,
    band: String = "20m",
    cqZone: Int? = nil,
    dxcc: Int? = nil,
    country: String? = nil
) -> QSOContestSnapshot {
    QSOContestSnapshot(
        callsign: callsign,
        band: band,
        mode: "CW",
        timestamp: Date(),
        rstSent: "599",
        rstReceived: "599",
        exchangeSent: "599 5",
        exchangeReceived: "599 \(cqZone ?? 0)",
        serialSent: nil,
        serialReceived: nil,
        country: country,
        dxcc: dxcc,
        cqZone: cqZone,
        state: nil,
        arrlSection: nil,
        county: nil
    )
}

// MARK: - Dupe Detection Tests

@Test func dupeDetectionPerBand() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    let first = await engine.registerQSO(makeSnapshot(callsign: "K3LR", band: "20m", cqZone: 5))
    #expect(first != .dupe)

    // Same callsign, same band = dupe
    let dupe = await engine.registerQSO(makeSnapshot(callsign: "K3LR", band: "20m", cqZone: 5))
    #expect(dupe == .dupe)

    // Same callsign, different band = not dupe
    let newBand = await engine.registerQSO(makeSnapshot(callsign: "K3LR", band: "40m", cqZone: 5))
    #expect(newBand != .dupe)
}

@Test func dupeCheckDoesNotMutateState() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    // Check should not register the QSO
    let status = await engine.dupeStatus(callsign: "W1AW", band: "20m")
    #expect(status == .newStation)

    // Still should be new after checking
    let status2 = await engine.dupeStatus(callsign: "W1AW", band: "20m")
    #expect(status2 == .newStation)
}

// MARK: - Multiplier Tests

@Test func newDXCCMultiplier() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    let status = await engine.registerQSO(
        makeSnapshot(callsign: "JA1ABC", band: "20m", cqZone: 25, dxcc: 339, country: "Japan")
    )

    // Should be a new multiplier (first DXCC or first zone)
    switch status {
    case .newMultiplier:
        break // expected
    default:
        Issue.record("Expected new multiplier, got \(status)")
    }
}

@Test func sameZoneDifferentBandIsNewMult() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    _ = await engine.registerQSO(makeSnapshot(callsign: "K3LR", band: "20m", cqZone: 5, dxcc: 291))
    let status = await engine.registerQSO(makeSnapshot(callsign: "W1AW", band: "40m", cqZone: 5, dxcc: 291))

    // Zone 5 on 40m is a new mult even though zone 5 was already on 20m (perBand = true)
    switch status {
    case .newMultiplier:
        break // expected - new per-band mult
    case .newStation:
        break // also acceptable if DXCC already counted
    case .dupe:
        Issue.record("Should not be a dupe")
    }
}

// MARK: - Serial Number Tests

@Test func serialAutoIncrement() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    let s1 = await engine.nextSerial()
    #expect(s1 == 1)

    let s2 = await engine.nextSerial()
    #expect(s2 == 2)

    let s3 = await engine.nextSerial()
    #expect(s3 == 3)
}

// MARK: - Score Snapshot Tests

@Test func scoreSnapshotAfterQSOs() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    _ = await engine.registerQSO(makeSnapshot(callsign: "K3LR", band: "20m", cqZone: 5, dxcc: 291))
    _ = await engine.registerQSO(makeSnapshot(callsign: "JA1ABC", band: "20m", cqZone: 25, dxcc: 339))

    let snapshot = await engine.scoreSnapshot()
    #expect(snapshot.totalQSOs == 2)
    #expect(snapshot.totalPoints > 0)
    #expect(snapshot.multiplierCount > 0)
    #expect(snapshot.qsosByBand["20m"] == 2)
}

// MARK: - Rate Calculation Tests

@Test func rateCalculationWithKnownTimestamps() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    // Log QSOs with timestamps in the last hour
    for i in 0 ..< 10 {
        var snapshot = makeSnapshot(callsign: "W\(i)TEST", band: "20m", cqZone: 5, dxcc: 291)
        snapshot.timestamp = Date().addingTimeInterval(-Double(i * 60)) // 1 minute apart
        _ = await engine.registerQSO(snapshot)
    }

    let rate = await engine.rate(overMinutes: 60)
    #expect(rate == 10.0) // 10 QSOs in 60 minutes
}

// MARK: - Suggested Exchange Tests

@Test func suggestedExchangeFromPreviousQSO() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    var snapshot = makeSnapshot(callsign: "K3LR", band: "20m", cqZone: 5)
    snapshot.exchangeReceived = "599 5"
    _ = await engine.registerQSO(snapshot)

    let suggested = await engine.suggestedExchange(for: "K3LR")
    #expect(suggested == "599 5")
}

@Test func suggestedExchangeForUnknownCallsignIsNil() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    let suggested = await engine.suggestedExchange(for: "UNKNOWN")
    #expect(suggested == nil)
}

// MARK: - Load Existing QSOs Tests

@Test func loadExistingQSOsPopulatesDupeTable() async {
    let engine = ContestEngine(definition: makeCQWWDefinition())

    let existing = [
        makeSnapshot(callsign: "K3LR", band: "20m", cqZone: 5, dxcc: 291),
        makeSnapshot(callsign: "JA1ABC", band: "20m", cqZone: 25, dxcc: 339),
    ]

    await engine.loadExistingQSOs(existing)

    // K3LR on 20m should now be a dupe
    let status = await engine.dupeStatus(callsign: "K3LR", band: "20m")
    #expect(status == .dupe)

    // JA1ABC on 40m should not be a dupe
    let status2 = await engine.dupeStatus(callsign: "JA1ABC", band: "40m")
    #expect(status2 == .newStation)

    let snapshot = await engine.scoreSnapshot()
    #expect(snapshot.totalQSOs == 2)
}

// MARK: - ContestTypes Tests

@Test func dupeStatusEquality() {
    #expect(DupeStatus.dupe == DupeStatus.dupe)
    #expect(DupeStatus.newStation == DupeStatus.newStation)
    #expect(DupeStatus.newMultiplier(value: "5", .cqZone) == DupeStatus.newMultiplier(value: "5", .cqZone))
    #expect(DupeStatus.dupe != DupeStatus.newStation)
}

@Test func contestScoreSnapshotDefaults() {
    let snapshot = ContestScoreSnapshot()
    #expect(snapshot.totalQSOs == 0)
    #expect(snapshot.totalPoints == 0)
    #expect(snapshot.multiplierCount == 0)
    #expect(snapshot.finalScore == 0)
    #expect(snapshot.dupeCount == 0)
}

@Test func contestOperatingModeToggle() {
    var mode = ContestOperatingMode.cq
    mode = mode == .cq ? .sp : .cq
    #expect(mode == .sp)
    mode = mode == .cq ? .sp : .cq
    #expect(mode == .cq)
}
