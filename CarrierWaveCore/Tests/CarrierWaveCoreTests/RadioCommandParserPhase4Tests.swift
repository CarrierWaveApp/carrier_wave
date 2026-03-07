//
//  RadioCommandParserPhase4Tests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("RadioCommandParser Phase 4 Tests")
struct RadioCommandParserPhase4Tests {
    // MARK: - Fuzzy Command Suggestions

    @Test("suggestCommands matches prefix")
    func suggestPrefix() {
        let results = RadioCommandParser.suggestCommands(for: "SP")
        #expect(results.contains("SPOT"))
        #expect(results.contains("SP"))
        #expect(results.contains("SPEED"))
    }

    @Test("suggestCommands is case-insensitive")
    func suggestCaseInsensitive() {
        let results = RadioCommandParser.suggestCommands(for: "sp")
        #expect(results.contains("SPOT"))
    }

    @Test("suggestCommands returns empty for no match")
    func suggestNoMatch() {
        let results = RadioCommandParser.suggestCommands(for: "XYZ")
        #expect(results.isEmpty)
    }

    @Test("suggestCommands matches single character")
    func suggestSingleChar() {
        let results = RadioCommandParser.suggestCommands(for: "C")
        #expect(results.contains("CQ"))
        #expect(results.contains("COUNT"))
    }

    // MARK: - Alias Expansion

    @Test("expandAliases replaces known alias")
    func expandAlias() {
        let aliases = ["FT": "14074 FT8", "CW40": "7030 CW"]
        let result = RadioCommandParser.expandAliases("FT", aliases: aliases)
        #expect(result == "14074 FT8")
    }

    @Test("expandAliases is case-insensitive")
    func expandAliasCaseInsensitive() {
        let aliases = ["FT": "14074 FT8"]
        let result = RadioCommandParser.expandAliases("ft", aliases: aliases)
        #expect(result == "14074 FT8")
    }

    @Test("expandAliases passes through unknown input")
    func expandAliasNoMatch() {
        let aliases = ["FT": "14074 FT8"]
        let result = RadioCommandParser.expandAliases("20m SSB", aliases: aliases)
        #expect(result == "20m SSB")
    }

    @Test("expandAliases trims whitespace")
    func expandAliasTrimmed() {
        let aliases = ["FT": "14074 FT8"]
        let result = RadioCommandParser.expandAliases("  FT  ", aliases: aliases)
        #expect(result == "14074 FT8")
    }

    @Test("expanded alias parses correctly")
    func expandedAliasParsesCorrectly() {
        let aliases = ["FT": "14074 FT8"]
        let expanded = RadioCommandParser.expandAliases("FT", aliases: aliases)
        let (cmd, _) = RadioCommandParser.parse(expanded)
        #expect(cmd.frequencyMHz == 14.074)
        #expect(cmd.mode == "FT8")
    }
}
