import Foundation
import Testing
@testable import CarrierWaveData

// MARK: - Cabrillo cross-language golden

//
// This test pins the exact Cabrillo output of `CabrilloExportService` with
// inputs mirrored byte-for-byte by the Rust port's golden test
// (`rust/cw-core/cw-domain/src/contest/cabrillo.rs`,
// `generates_full_log`). Both suites assert the identical expected string,
// so the two implementations provably agree before the Swift one is
// replaced by the FFI facade. Do not change one side without the other.

private let goldenDefinitionJSON = """
{
  "id": "sst",
  "name": "Slow Speed Test",
  "short_name": "SST",
  "modes": ["CW"],
  "bands": ["40m"],
  "schedule": {
    "type": "recurring_weekly",
    "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
    "session_scoring": "independent"
  },
  "exchange": {
    "sent": [
      { "name": "name", "type": "name", "label": "Name" },
      { "name": "state", "type": "state_province", "label": "State" }
    ],
    "received": [
      { "name": "name", "type": "name", "label": "Name" },
      { "name": "state", "type": "state_province", "label": "State" }
    ]
  },
  "dupe_rules": { "scope": "session", "key": ["callsign"] },
  "scoring": { "phases": [] },
  "cabrillo": { "contest_name": "K1USN-SST", "version": "3.0" },
  "categories": []
}
"""

private let expectedGoldenLog = [
    "START-OF-LOG: 3.0",
    "CONTEST: K1USN-SST",
    "CALLSIGN: W6JY",
    "CATEGORY-OPERATOR: SINGLE-OP",
    "CATEGORY-BAND: ALL",
    "CATEGORY-POWER: LOW",
    "CATEGORY-MODE: CW",
    "CATEGORY-ASSISTED: NON-ASSISTED",
    "LOCATION: OR",
    "CLAIMED-SCORE: 42",
    "OPERATORS: W6JY",
    "CREATED-BY: Carrier Wave",
    "QSO:  7038 CW 2026-07-04 0002 W6JY          JAY    OR     N3ABC         TIM    MA\u{20}\u{20}\u{20}\u{20}",
    "QSO:  7038 CW 2026-07-04 0005 W6JY          JAY    OR     K1USN         TIM    MA\u{20}\u{20}\u{20}\u{20}",
    "END-OF-LOG:",
].joined(separator: "\n") + "\n"

@Test func cabrilloOutputMatchesRustGolden() throws {
    let definition = try contestDefinition(fromJson: goldenDefinitionJSON)

    let session = LoggingSession(myCallsign: "W6JY")
    session.contestPower = "LOW"

    let visible = [makeQSO(callsign: "K1USN", minute: 5), makeQSO(callsign: "N3ABC", minute: 2)]
    let hidden = makeQSO(callsign: "K9ZZZ", minute: 1)
    hidden.isHidden = true

    let score = ContestScoreSnapshot(finalScore: 42)
    let context = CabrilloExportService.Context(
        categoryID: "SINGLE-OP",
        location: "OR"
    )

    let output = CabrilloExportService().generate(
        session: session,
        qsos: visible + [hidden],
        definition: definition,
        score: score,
        context: context
    )

    #expect(output == expectedGoldenLog)
}

private func makeQSO(callsign: String, minute: Int) -> QSO {
    var components = DateComponents()
    components.year = 2_026
    components.month = 7
    components.day = 4
    components.hour = 0
    components.minute = minute
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let timestamp = calendar.date(from: components) ?? Date()

    let qso = QSO(
        callsign: callsign,
        band: "40m",
        mode: "CW",
        frequency: 7.038,
        timestamp: timestamp,
        myCallsign: "W6JY",
        importSource: .logger
    )
    qso.contestName = "sst"
    qso.contestExchangeSent = "JAY OR"
    qso.contestExchangeReceived = "TIM MA"
    return qso
}
