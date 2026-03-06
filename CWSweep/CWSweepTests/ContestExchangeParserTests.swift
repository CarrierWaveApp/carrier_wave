import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - Test Helpers

private func makeCQWWExchange() -> ContestDefinition {
    ContestDefinition(
        id: "cq-ww-cw",
        name: "CQ WW CW",
        cabrilloCategoryContest: "CQ-WW-CW",
        bands: ["20m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: [
            ExchangeField(id: "rst", label: "RST", type: .rst, defaultValue: "599"),
            ExchangeField(id: "cqZone", label: "CQ Zone", type: .cqZone),
        ]),
        multipliers: ContestMultipliers(types: [.dxcc, .cqZone], perBand: true),
        scoring: ContestScoring(rules: [ScoringRule(condition: .any, points: 1)]),
        dupeRules: ContestDupeRules(perBand: true, perMode: false),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )
}

private func makeSSExchange() -> ContestDefinition {
    ContestDefinition(
        id: "arrl-ss-cw",
        name: "SS CW",
        cabrilloCategoryContest: "ARRL-SS-CW",
        bands: ["20m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: [
            ExchangeField(id: "serial", label: "Serial", type: .serialNumber),
            ExchangeField(id: "precedence", label: "Prec", type: .precedence),
            ExchangeField(id: "check", label: "Check", type: .check),
            ExchangeField(id: "section", label: "Section", type: .arrlSection),
        ]),
        multipliers: ContestMultipliers(types: [.arrlSection], perBand: false),
        scoring: ContestScoring(rules: [ScoringRule(condition: .any, points: 2)]),
        dupeRules: ContestDupeRules(perBand: false, perMode: false),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )
}

private func makeFDExchange() -> ContestDefinition {
    ContestDefinition(
        id: "arrl-field-day",
        name: "Field Day",
        cabrilloCategoryContest: "ARRL-FD",
        bands: ["20m"],
        modes: ["CW"],
        exchange: ContestExchange(fields: [
            ExchangeField(id: "class", label: "Class", type: .classField),
            ExchangeField(id: "section", label: "Section", type: .arrlSection),
        ]),
        multipliers: ContestMultipliers(types: [], perBand: false),
        scoring: ContestScoring(rules: [ScoringRule(condition: .any, points: 1)]),
        dupeRules: ContestDupeRules(perBand: true, perMode: true),
        cabrillo: CabrilloTemplate(qsoTemplate: "", fieldWidths: [:])
    )
}

// MARK: - CQ WW Exchange Parsing

@Test func cqWWParsesZone() {
    let result = ContestExchangeParser.parse(tokens: ["599", "3"], definition: makeCQWWExchange())
    #expect(result.fields["cqZone"] == "3")
}

@Test func cqWWParsesRSTAndZone() {
    let result = ContestExchangeParser.parse(tokens: ["59", "14"], definition: makeCQWWExchange())
    #expect(result.fields["rst"] == "59")
    #expect(result.fields["cqZone"] == "14")
}

// MARK: - Sweepstakes Exchange Parsing

@Test func ssParsesFullExchange() {
    let result = ContestExchangeParser.parse(
        tokens: ["1234", "A", "72", "ENY"],
        definition: makeSSExchange()
    )
    #expect(result.fields["serial"] == "1234")
    #expect(result.serialReceived == 1_234)
    #expect(result.fields["precedence"] == "A")
    #expect(result.fields["check"] == "72")
    #expect(result.fields["section"] == "ENY")
}

@Test func ssHandlesPartialExchange() {
    let result = ContestExchangeParser.parse(
        tokens: ["42", "B"],
        definition: makeSSExchange()
    )
    #expect(result.fields["serial"] == "42")
    #expect(result.fields["precedence"] == "B")
    // check and section not provided
    #expect(result.fields["check"] == nil)
    #expect(result.fields["section"] == nil)
}

// MARK: - Field Day Exchange Parsing

@Test func fieldDayParsesClassAndSection() {
    let result = ContestExchangeParser.parse(
        tokens: ["2A", "ENY"],
        definition: makeFDExchange()
    )
    #expect(result.fields["class"] == "2A")
    #expect(result.fields["section"] == "ENY")
}

@Test func fieldDayHandleLargeClass() {
    let result = ContestExchangeParser.parse(
        tokens: ["15A", "SFL"],
        definition: makeFDExchange()
    )
    #expect(result.fields["class"] == "15A")
    #expect(result.fields["section"] == "SFL")
}

// MARK: - Unmatched Tokens

@Test func unmatchedTokensReturned() {
    let result = ContestExchangeParser.parse(
        tokens: ["599", "3", "EXTRA", "JUNK"],
        definition: makeCQWWExchange()
    )
    #expect(result.unmatchedTokens.contains("EXTRA"))
    #expect(result.unmatchedTokens.contains("JUNK"))
}

// MARK: - ARRL Section Data

@Test func arrlSectionsContainsKnownSections() {
    #expect(ContestExchangeParser.arrlSections.contains("ENY"))
    #expect(ContestExchangeParser.arrlSections.contains("NLI"))
    #expect(ContestExchangeParser.arrlSections.contains("NNJ"))
    #expect(ContestExchangeParser.arrlSections.contains("WMA"))
    #expect(ContestExchangeParser.arrlSections.contains("SFL"))
    #expect(ContestExchangeParser.arrlSections.contains("LAX"))
}
