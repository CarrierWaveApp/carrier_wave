import CarrierWaveData
import Foundation
import Testing

// MARK: - ContestDefinition Tests

@Test func contestDefinitionJSONRoundTrip() throws {
    let definition = ContestDefinition(
        id: "test-contest",
        name: "Test Contest",
        cabrilloCategoryContest: "TEST",
        bands: ["20m", "40m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: [
            ExchangeField(id: "rst", label: "RST", type: .rst, defaultValue: "599"),
            ExchangeField(id: "zone", label: "Zone", type: .cqZone),
        ]),
        multipliers: ContestMultipliers(types: [.dxcc, .cqZone], perBand: true),
        scoring: ContestScoring(rules: [
            ScoringRule(condition: .sameContinent, points: 1),
            ScoringRule(condition: .differentContinent, points: 3),
        ]),
        dupeRules: ContestDupeRules(perBand: true, perMode: false),
        cabrillo: CabrilloTemplate(
            qsoTemplate: "freq mode date time mycall rst exch call rst exch",
            fieldWidths: ["freq": 5, "mode": 2]
        )
    )

    let data = try JSONEncoder().encode(definition)
    let decoded = try JSONDecoder().decode(ContestDefinition.self, from: data)

    #expect(decoded.id == "test-contest")
    #expect(decoded.name == "Test Contest")
    #expect(decoded.bands == ["20m", "40m"])
    #expect(decoded.modes == ["CW"])
    #expect(decoded.exchange.fields.count == 2)
    #expect(decoded.multipliers.types == [.dxcc, .cqZone])
    #expect(decoded.multipliers.perBand == true)
    #expect(decoded.scoring.rules.count == 2)
    #expect(decoded.dupeRules.perBand == true)
    #expect(decoded.dupeRules.perMode == false)
    #expect(decoded.cabrillo.qsoTemplate.contains("freq"))
}

@Test func exchangeFieldTypeCases() {
    // Verify all expected exchange field types exist
    let cases: [ExchangeFieldType] = [
        .rst, .cqZone, .ituZone, .state, .arrlSection,
        .serialNumber, .county, .power, .opaque, .name,
        .precedence, .check, .classField,
    ]
    #expect(cases.count == 13)
}

@Test func multiplierTypeCases() {
    let cases: [MultiplierType] = [
        .dxcc, .cqZone, .ituZone, .state, .arrlSection, .county, .wpxPrefix,
    ]
    #expect(cases.count == 7)
}

@Test func scoringConditionCases() {
    let cases: [ScoringCondition] = [
        .sameCountry, .sameContinent, .differentContinent, .sameDXCC, .any,
    ]
    #expect(cases.count == 5)
}

@Test func contestDefinitionFromBundledJSON() throws {
    // Load CQ WW CW from test resources
    let json = """
    {
      "id": "cq-ww-cw",
      "name": "CQ World Wide DX Contest CW",
      "cabrilloCategoryContest": "CQ-WW-CW",
      "bands": ["160m", "80m", "40m", "20m", "15m", "10m"],
      "modes": ["CW"],
      "exchange": {
        "fields": [
          { "id": "rst", "label": "RST", "type": "rst", "defaultValue": "599", "width": 3 },
          { "id": "cqZone", "label": "CQ Zone", "type": "cqZone", "width": 2 }
        ]
      },
      "multipliers": { "types": ["dxcc", "cqZone"], "perBand": true },
      "scoring": {
        "rules": [
          { "condition": "sameCountry", "points": 0 },
          { "condition": "sameContinent", "points": 1 },
          { "condition": "differentContinent", "points": 3 }
        ]
      },
      "dupeRules": { "perBand": true, "perMode": false },
      "cabrillo": {
        "qsoTemplate": "freq mode date time mycall rst myexch call rst exch",
        "fieldWidths": { "freq": 5, "mode": 2 }
      }
    }
    """
    let data = try #require(json.data(using: .utf8))
    let def = try JSONDecoder().decode(ContestDefinition.self, from: data)
    #expect(def.id == "cq-ww-cw")
    #expect(def.exchange.fields.count == 2)
    #expect(def.exchange.fields[1].type == .cqZone)
}
