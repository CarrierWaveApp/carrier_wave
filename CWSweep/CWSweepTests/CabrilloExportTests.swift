import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - Cabrillo Export Tests

@Test func cabrilloHeaderFormat() {
    let exporter = CabrilloExportService()
    let session = LoggingSession(
        myCallsign: "W6JSV",
        contestId: "cq-ww-cw",
        contestCategory: "SINGLE-OP",
        contestPower: "HIGH",
        contestBands: "ALL",
        contestOperator: "W6JSV"
    )
    let definition = ContestDefinition(
        id: "cq-ww-cw",
        name: "CQ WW CW",
        cabrilloCategoryContest: "CQ-WW-CW",
        bands: ["20m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: []),
        multipliers: ContestMultipliers(types: [], perBand: true),
        scoring: ContestScoring(rules: []),
        dupeRules: ContestDupeRules(perBand: true, perMode: false),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )
    let score = ContestScoreSnapshot(
        totalQSOs: 100,
        totalPoints: 250,
        multiplierCount: 50,
        finalScore: 12_500
    )

    let result = exporter.generate(session: session, qsos: [], definition: definition, score: score)

    #expect(result.contains("START-OF-LOG: 3.0"))
    #expect(result.contains("CONTEST: CQ-WW-CW"))
    #expect(result.contains("CALLSIGN: W6JSV"))
    #expect(result.contains("CATEGORY-OPERATOR: SINGLE-OP"))
    #expect(result.contains("CATEGORY-BAND: ALL"))
    #expect(result.contains("CATEGORY-POWER: HIGH"))
    #expect(result.contains("CLAIMED-SCORE: 12500"))
    #expect(result.contains("CREATED-BY: CW Sweep"))
    #expect(result.contains("END-OF-LOG:"))
}

@Test func cabrilloQSOLineFormat() {
    let exporter = CabrilloExportService()
    let session = LoggingSession(
        myCallsign: "W6JSV",
        contestId: "cq-ww-cw",
        contestOperator: "W6JSV"
    )
    let definition = ContestDefinition(
        id: "cq-ww-cw",
        name: "CQ WW CW",
        cabrilloCategoryContest: "CQ-WW-CW",
        bands: ["20m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: []),
        multipliers: ContestMultipliers(types: [], perBand: true),
        scoring: ContestScoring(rules: []),
        dupeRules: ContestDupeRules(perBand: true, perMode: false),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )

    let qso = QSO(
        callsign: "K3LR",
        band: "20m",
        mode: "CW",
        frequency: 14.030,
        timestamp: Date(),
        rstSent: "599",
        rstReceived: "599",
        myCallsign: "W6JSV",
        importSource: .logger,
        contestName: "cq-ww-cw",
        contestExchangeSent: "5",
        contestExchangeReceived: "3"
    )

    let result = exporter.generate(
        session: session,
        qsos: [qso],
        definition: definition,
        score: ContestScoreSnapshot()
    )

    let lines = result.split(separator: "\n").map(String.init)
    let qsoLines = lines.filter { $0.hasPrefix("QSO:") }
    #expect(qsoLines.count == 1)

    let qsoLine = qsoLines[0]
    #expect(qsoLine.contains("14030")) // freq in kHz
    #expect(qsoLine.contains("CW"))
    #expect(qsoLine.contains("W6JSV"))
    #expect(qsoLine.contains("K3LR"))
    #expect(qsoLine.contains("599"))
}

@Test func cabrilloScoreInHeader() {
    let exporter = CabrilloExportService()
    let session = LoggingSession(myCallsign: "W6JSV", contestId: "test")
    let definition = ContestDefinition(
        id: "test", name: "Test", cabrilloCategoryContest: "TEST",
        bands: [], modes: [],
        exchange: ContestExchange(fields: []),
        multipliers: ContestMultipliers(types: [], perBand: false),
        scoring: ContestScoring(rules: []),
        dupeRules: ContestDupeRules(perBand: false, perMode: false),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )
    let score = ContestScoreSnapshot(finalScore: 99_999)

    let result = exporter.generate(session: session, qsos: [], definition: definition, score: score)
    #expect(result.contains("CLAIMED-SCORE: 99999"))
}

@Test func cabrilloModeMapping() {
    let exporter = CabrilloExportService()
    let session = LoggingSession(myCallsign: "W6JSV", contestId: "test")
    let definition = ContestDefinition(
        id: "test", name: "Test", cabrilloCategoryContest: "TEST",
        bands: [], modes: ["SSB"],
        exchange: ContestExchange(fields: []),
        multipliers: ContestMultipliers(types: [], perBand: false),
        scoring: ContestScoring(rules: []),
        dupeRules: ContestDupeRules(perBand: false, perMode: false),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )

    let qso = QSO(
        callsign: "K3LR", band: "20m", mode: "SSB", frequency: 14.200,
        timestamp: Date(), myCallsign: "W6JSV", importSource: .logger,
        contestName: "test"
    )

    let result = exporter.generate(
        session: session, qsos: [qso], definition: definition, score: ContestScoreSnapshot()
    )
    #expect(result.contains("PH")) // SSB → PH in Cabrillo
}
