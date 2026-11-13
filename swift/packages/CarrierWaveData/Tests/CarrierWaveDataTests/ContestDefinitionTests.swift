import CarrierWaveData
import Foundation
import Testing

// The contest engine lives in the Rust core; these tests exercise the Swift
// facades end-to-end (definition parse → engine scoring → schedule → WPX).
// They mirror the original Swift-engine suite — the Rust module carries the
// same cases in `cw-domain/src/contest/`.

// MARK: - Decoding

@Test func contestDefinitionDecodesFromServerJSON() throws {
    let json = """
    {
      "id": "sst",
      "name": "Slow Speed Test",
      "short_name": "SST",
      "modes": ["CW"],
      "bands": ["80m", "40m", "20m"],
      "schedule": {
        "type": "recurring_weekly",
        "sessions": [
          { "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }
        ],
        "session_scoring": "independent"
      },
      "exchange": {
        "sent": [
          { "name": "name", "type": "name", "label": "Name", "autofill": "station_name" },
          { "name": "state", "type": "state_province", "label": "State", "autofill": "station_state" }
        ],
        "received": [
          { "name": "name", "type": "name", "label": "Name" },
          { "name": "state", "type": "state_province", "label": "State" }
        ]
      },
      "dupe_rules": {
        "scope": "session",
        "key": ["callsign"]
      },
      "scoring": {
        "phases": [
          { "id": "qso_points", "type": "per_qso", "rules": [ { "conditions": [], "value": 1 } ] },
          { "id": "total", "type": "aggregate", "operation": { "op": "ref", "phase": "qso_points" } }
        ]
      },
      "categories": [
        { "id": "SO", "label": "Single Op", "power_classes": ["HIGH", "LOW", "QRP"] }
      ]
    }
    """

    let definition = try contestDefinition(fromJson: json)

    #expect(definition.id == "sst")
    #expect(definition.displayName == "SST")
    #expect(definition.exchange.received.count == 2)
    #expect(definition.dupeRules.scope == .session)
    #expect(definition.scoring.phases.count == 2)
    #expect(definition.categories.first?.powerClasses == ["HIGH", "LOW", "QRP"])
}

// MARK: - Engine scoring

@Test func perQSOPhaseAwardsFirstMatchingRule() async throws {
    let definition = try makeSimpleContest(
        phasesJSON: """
        [{ "id": "qso_points", "type": "per_qso", "rules": [
            { "conditions": [ { "field": "their_country", "op": "eq", "ref": "my_country" } ], "value": 0 },
            { "conditions": [], "value": 3 }
        ] }]
        """
    )
    let engine = ContestEngine(
        definition: definition,
        myStation: MyStationContext(callsign: "K4XL", country: "United States")
    )

    // Same country → 0 points
    let sameCountry = makeRecord(callsign: "W1ABC", country: "United States")
    _ = await engine.registerQSO(sameCountry)

    // Different country → 3 points
    let dx = makeRecord(callsign: "DL1ABC", country: "Germany", timestamp: Date().addingTimeInterval(60))
    _ = await engine.registerQSO(dx)

    let score = await engine.scoreSnapshot()
    #expect(score.totalPoints == 3)
    #expect(score.totalQSOs == 2)
}

@Test func dupeDetectionHonorsCompositeKey() async throws {
    let definition = try makeSimpleContest(dupeKey: ["callsign", "band"])
    let engine = ContestEngine(definition: definition)

    let firstQSO = makeRecord(callsign: "K4XL", band: "20m")
    let dupeSameBand = makeRecord(callsign: "K4XL", band: "20m", timestamp: Date().addingTimeInterval(60))
    let newBand = makeRecord(callsign: "K4XL", band: "40m", timestamp: Date().addingTimeInterval(120))

    let first = await engine.registerQSO(firstQSO)
    let dupe = await engine.registerQSO(dupeSameBand)
    let cross = await engine.registerQSO(newBand)

    #expect(first == .newStation)
    #expect(dupe == .dupe)
    #expect(cross != .dupe)
}

@Test func multiplierPhaseAccumulatesUniqueValues() async throws {
    let definition = try makeSimpleContest(
        phasesJSON: """
        [
          { "id": "qso_points", "type": "per_qso", "rules": [ { "conditions": [], "value": 1 } ] },
          { "id": "mult_countries", "type": "multiplier_count", "source": "their_country", "scope": "per_contest" }
        ]
        """
    )
    let engine = ContestEngine(definition: definition)

    _ = await engine.registerQSO(makeRecord(callsign: "W1ABC", country: "United States"))
    _ = await engine.registerQSO(makeRecord(
        callsign: "DL1ABC",
        country: "Germany",
        timestamp: Date().addingTimeInterval(60)
    ))
    _ = await engine.registerQSO(makeRecord(
        callsign: "DL2ABC",
        country: "Germany",
        timestamp: Date().addingTimeInterval(120)
    ))

    let score = await engine.scoreSnapshot()
    #expect(score.multiplierCount == 2)
}

// MARK: - Schedule evaluator

@Test func scheduleEvaluatorFindsWeeklySession() throws {
    let definition = try makeSimpleContest(
        scheduleJSON: """
        {
          "type": "recurring_weekly",
          "sessions": [ { "day": "monday", "start_utc": "00:00", "duration_minutes": 60 } ],
          "session_scoring": "independent"
        }
        """
    )
    let occurrence = ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule)
    #expect(occurrence != nil)
}

@Test func scheduleEvaluatorResolvesWpxWeekends() throws {
    for rule in ["last_full_weekend_may", "last_full_weekend_march"] {
        let definition = try makeSimpleContest(
            scheduleJSON: """
            { "type": "annual", "rule": "\(rule)", "start_utc": "00:00",
              "start_day": "saturday", "duration_hours": 48 }
            """
        )
        #expect(ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule) != nil)
    }
}

// MARK: - WPX prefix

@Test func wpxPrefixExtraction() {
    // Simple calls: up to and including the last digit.
    #expect(ContestCallsign.wpxPrefix("K4XL") == "K4")
    #expect(ContestCallsign.wpxPrefix("ve3xyz") == "VE3")
    #expect(ContestCallsign.wpxPrefix("4U1UN") == "4U1")
    #expect(ContestCallsign.wpxPrefix("OE25XYZ") == "OE25")
    // No digit anywhere: zero after the first two letters.
    #expect(ContestCallsign.wpxPrefix("RAEM") == "RA0")
    // Strippable suffixes don't change the prefix.
    #expect(ContestCallsign.wpxPrefix("K4XL/QRP") == "K4")
    #expect(ContestCallsign.wpxPrefix("G3XYZ/P") == "G3")
    // Portable host designator (letters) forms the prefix.
    #expect(ContestCallsign.wpxPrefix("KH6/N8BJQ") == "KH6")
    #expect(ContestCallsign.wpxPrefix("PA/N8BJQ") == "PA0")
    #expect(ContestCallsign.wpxPrefix("VP2E/K4XL") == "VP2")
    #expect(ContestCallsign.wpxPrefix("W1/K4XL") == "W1")
    // Single-number portable: home-call letters + the digit.
    #expect(ContestCallsign.wpxPrefix("N8BJQ/9") == "N9")
    #expect(ContestCallsign.wpxPrefix("WB8XYZ/4") == "WB4")
}

@Test func wpxPrefixMultiplierCountsUniquePrefixes() async throws {
    let definition = try makeSimpleContest(
        phasesJSON: """
        [
          { "id": "qso_points", "type": "per_qso", "rules": [ { "conditions": [], "value": 1 } ] },
          { "id": "mult_prefixes", "type": "multiplier_count", "source": "their_callsign_wpx", "scope": "per_contest" }
        ]
        """
    )
    let engine = ContestEngine(definition: definition)

    _ = await engine.registerQSO(makeRecord(callsign: "K1XX"))
    // Same prefix (K1), different callsign → not a dupe, no new multiplier.
    _ = await engine.registerQSO(makeRecord(
        callsign: "K1ZZ",
        timestamp: Date().addingTimeInterval(60)
    ))
    _ = await engine.registerQSO(makeRecord(
        callsign: "VE3ABC",
        timestamp: Date().addingTimeInterval(120)
    ))

    let score = await engine.scoreSnapshot()
    #expect(score.multiplierCount == 2)
}

// MARK: - Fixtures

private func makeSimpleContest(
    phasesJSON: String = """
    [{ "id": "qso_points", "type": "per_qso", "rules": [ { "conditions": [], "value": 1 } ] }]
    """,
    dupeKey: [String] = ["callsign"],
    scheduleJSON: String = """
    { "type": "annual", "rule": "last_full_weekend_november", "start_utc": "00:00",
      "start_day": "saturday", "duration_hours": 48 }
    """
) throws -> ContestDefinition {
    let keyJSON = dupeKey.map { "\"\($0)\"" }.joined(separator: ", ")
    let json = """
    {
      "id": "test",
      "name": "Test Contest",
      "modes": ["CW"],
      "bands": ["20m", "40m"],
      "schedule": \(scheduleJSON),
      "exchange": { "sent": [], "received": [] },
      "dupe_rules": { "scope": "contest", "key": [\(keyJSON)] },
      "scoring": { "phases": \(phasesJSON) },
      "categories": [ { "id": "SO", "label": "Single Op" } ]
    }
    """
    return try contestDefinition(fromJson: json)
}

private func makeRecord(
    callsign: String,
    band: String = "20m",
    country: String? = nil,
    timestamp: Date = Date()
) -> ContestQSORecord {
    ContestQSORecord(
        callsign: callsign,
        band: band,
        mode: "CW",
        timestamp: timestamp,
        theirCountry: country
    )
}
