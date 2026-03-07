//
//  RadioCommandParserTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("RadioCommandParser Tests")
struct RadioCommandParserTests {
    // MARK: - Frequency Parsing

    @Test("Parse bare kHz frequency")
    func parseKHzFrequency() {
        let (cmd, tokens) = RadioCommandParser.parse("14074")
        #expect(cmd.frequencyMHz == 14.074)
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .frequency)
    }

    @Test("Parse kHz frequency with decimal")
    func parseKHzWithDecimal() {
        let (cmd, _) = RadioCommandParser.parse("14074.5")
        #expect(cmd.frequencyMHz == 14.0745)
    }

    @Test("Parse MHz frequency")
    func parseMHzFrequency() {
        let (cmd, _) = RadioCommandParser.parse("14.074")
        #expect(cmd.frequencyMHz == 14.074)
    }

    @Test("Parse VHF frequency")
    func parseVHFFrequency() {
        let (cmd, _) = RadioCommandParser.parse("144300")
        #expect(cmd.frequencyMHz == 144.3)
    }

    // MARK: - Mode Parsing

    @Test("Parse mode keyword")
    func parseModeKeyword() {
        let (cmd, tokens) = RadioCommandParser.parse("CW")
        #expect(cmd.mode == "CW")
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .mode)
    }

    @Test("Parse mode case insensitive")
    func parseModeCaseInsensitive() {
        let (cmd, _) = RadioCommandParser.parse("ft8")
        #expect(cmd.mode == "FT8")
    }

    @Test("PSK31 normalizes to PSK")
    func parsePSK31() {
        let (cmd, _) = RadioCommandParser.parse("PSK31")
        #expect(cmd.mode == "PSK")
    }

    @Test("DIGI normalizes to DATA")
    func parseDIGI() {
        let (cmd, _) = RadioCommandParser.parse("DIGI")
        #expect(cmd.mode == "DATA")
    }

    // MARK: - Band Shortcuts

    @Test("Parse band shortcut with default CW frequency")
    func parseBandShortcutCW() {
        let (cmd, tokens) = RadioCommandParser.parse("20m")
        #expect(cmd.frequencyMHz == 14.030)
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .band)
    }

    @Test("Band shortcut with FT8 mode uses FT8 frequency")
    func parseBandShortcutFT8() {
        let (cmd, _) = RadioCommandParser.parse("20m FT8")
        #expect(cmd.frequencyMHz == 14.074)
        #expect(cmd.mode == "FT8")
    }

    @Test("Band shortcut with SSB mode uses phone frequency")
    func parseBandShortcutSSB() {
        let (cmd, _) = RadioCommandParser.parse("20m SSB")
        #expect(cmd.frequencyMHz == 14.250)
        #expect(cmd.mode == "SSB")
    }

    @Test("Band shortcut case insensitive")
    func parseBandShortcutCaseInsensitive() {
        let (cmd, _) = RadioCommandParser.parse("40M")
        #expect(cmd.frequencyMHz == 7.030)
    }

    // MARK: - Split Directives

    @Test("Parse UP with offset")
    func parseUpWithOffset() {
        let (cmd, _) = RadioCommandParser.parse("UP 5")
        #expect(cmd.splitDirective == .up(kHz: 5))
    }

    @Test("Parse UP without offset defaults to 1 kHz")
    func parseUpDefaultOffset() {
        let (cmd, _) = RadioCommandParser.parse("UP")
        #expect(cmd.splitDirective == .up(kHz: 1))
    }

    @Test("Parse DN with offset")
    func parseDnWithOffset() {
        let (cmd, _) = RadioCommandParser.parse("DN 10")
        #expect(cmd.splitDirective == .down(kHz: 10))
    }

    @Test("Parse DOWN with offset")
    func parseDownWithOffset() {
        let (cmd, _) = RadioCommandParser.parse("DOWN 3")
        #expect(cmd.splitDirective == .down(kHz: 3))
    }

    @Test("Parse SPLIT with explicit frequency")
    func parseSplitExplicit() {
        let (cmd, _) = RadioCommandParser.parse("SPLIT 14210")
        #expect(cmd.splitDirective == .explicitFrequency(kHz: 14_210))
    }

    @Test("Parse NOSPLIT")
    func parseNosplit() {
        let (cmd, _) = RadioCommandParser.parse("NOSPLIT")
        #expect(cmd.splitDirective == .off)
    }

    // MARK: - Combined Commands

    @Test("Frequency + mode")
    func parseFrequencyAndMode() {
        let (cmd, tokens) = RadioCommandParser.parse("14074 FT8")
        #expect(cmd.frequencyMHz == 14.074)
        #expect(cmd.mode == "FT8")
        #expect(tokens.count == 2)
    }

    @Test("Mode + frequency (reversed order)")
    func parseModeAndFrequency() {
        let (cmd, _) = RadioCommandParser.parse("CW 7035")
        #expect(cmd.frequencyMHz == 7.035)
        #expect(cmd.mode == "CW")
    }

    @Test("Frequency + mode + split")
    func parseFullCommand() {
        let (cmd, tokens) = RadioCommandParser.parse("21074 FT8 UP 1")
        #expect(cmd.frequencyMHz == 21.074)
        #expect(cmd.mode == "FT8")
        #expect(cmd.splitDirective == .up(kHz: 1))
        #expect(tokens.count == 3)
    }

    @Test("Band + mode")
    func parseBandAndMode() {
        let (cmd, _) = RadioCommandParser.parse("20m SSB")
        #expect(cmd.frequencyMHz == 14.250)
        #expect(cmd.mode == "SSB")
    }

    // MARK: - Token Order Flexibility

    @Test("Tokens parse identically regardless of order")
    func parseOrderFlexibility() {
        let (cmd1, _) = RadioCommandParser.parse("CW 14074 UP 1")
        let (cmd2, _) = RadioCommandParser.parse("14074 UP 1 CW")
        let (cmd3, _) = RadioCommandParser.parse("UP 1 CW 14074")

        #expect(cmd1.frequencyMHz == cmd2.frequencyMHz)
        #expect(cmd2.frequencyMHz == cmd3.frequencyMHz)
        #expect(cmd1.mode == cmd2.mode)
        #expect(cmd2.mode == cmd3.mode)
        #expect(cmd1.splitDirective == cmd2.splitDirective)
        #expect(cmd2.splitDirective == cmd3.splitDirective)
    }

    // MARK: - SSB Resolution

    @Test("SSB resolves to USB above 10 MHz")
    func resolveSsbAbove10() {
        let mode = RadioCommandParser.resolveMode("SSB", frequencyMHz: 14.250)
        #expect(mode == "USB")
    }

    @Test("SSB resolves to LSB below 10 MHz")
    func resolveSsbBelow10() {
        let mode = RadioCommandParser.resolveMode("SSB", frequencyMHz: 7.200)
        #expect(mode == "LSB")
    }

    @Test("CW stays CW regardless of frequency")
    func resolveCwUnchanged() {
        let mode = RadioCommandParser.resolveMode("CW", frequencyMHz: 14.030)
        #expect(mode == "CW")
    }

    // MARK: - Edge Cases

    @Test("Empty input returns empty command")
    func parseEmpty() {
        let (cmd, tokens) = RadioCommandParser.parse("")
        #expect(cmd.isEmpty)
        #expect(tokens.isEmpty)
    }

    @Test("Whitespace only returns empty command")
    func parseWhitespace() {
        let (cmd, tokens) = RadioCommandParser.parse("   ")
        #expect(cmd.isEmpty)
        #expect(tokens.isEmpty)
    }

    @Test("Unknown token produces error state")
    func parseUnknownToken() {
        let (_, tokens) = RadioCommandParser.parse("FOOBAR")
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .unknown)
        if case .error = tokens[0].state {} else {
            Issue.record("Expected error state for unknown token")
        }
    }

    @Test("Split only command")
    func parseSplitOnly() {
        let (cmd, _) = RadioCommandParser.parse("UP 5")
        #expect(cmd.frequencyMHz == nil)
        #expect(cmd.mode == nil)
        #expect(cmd.splitDirective == .up(kHz: 5))
    }

    @Test("Mode only command")
    func parseModeOnly() {
        let (cmd, _) = RadioCommandParser.parse("CW")
        #expect(cmd.frequencyMHz == nil)
        #expect(cmd.mode == "CW")
        #expect(cmd.splitDirective == nil)
    }

    // MARK: - Named Commands (Phase 2)

    @Test("QRZ lookup with callsign")
    func parseQRZLookup() {
        let (cmd, tokens) = RadioCommandParser.parse("QRZ K4ABC")
        #expect(cmd.namedCommand == .lookup(callsign: "K4ABC"))
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .command)
    }

    @Test("? shorthand for lookup")
    func parseQuestionMarkLookup() {
        let (cmd, _) = RadioCommandParser.parse("? W1AW")
        #expect(cmd.namedCommand == .lookup(callsign: "W1AW"))
    }

    @Test("SPOT callsign without frequency")
    func parseSpotNoFreq() {
        let (cmd, _) = RadioCommandParser.parse("SPOT K4ABC")
        #expect(cmd.namedCommand == .spot(callsign: "K4ABC", frequencyKHz: nil))
    }

    @Test("SPOT callsign with frequency")
    func parseSpotWithFreq() {
        let (cmd, _) = RadioCommandParser.parse("SPOT K4ABC 14074")
        #expect(cmd.namedCommand == .spot(callsign: "K4ABC", frequencyKHz: 14_074))
    }

    @Test("PARK sets park reference")
    func parsePark() {
        let (cmd, tokens) = RadioCommandParser.parse("PARK K-0001")
        #expect(cmd.namedCommand == .setPark(reference: "K-0001"))
        #expect(tokens[0].kind == .command)
    }

    @Test("SUMMIT sets summit reference")
    func parseSummit() {
        let (cmd, _) = RadioCommandParser.parse("SUMMIT W7W/KG-001")
        #expect(cmd.namedCommand == .setSummit(reference: "W7W/KG-001"))
    }

    @Test("PWR sets power in watts")
    func parsePower() {
        let (cmd, _) = RadioCommandParser.parse("PWR 100")
        #expect(cmd.namedCommand == .setPower(watts: 100))
    }

    @Test("PWR QRP sets 5 watts")
    func parsePowerQRP() {
        let (cmd, _) = RadioCommandParser.parse("PWR QRP")
        #expect(cmd.namedCommand == .setPower(watts: 5))
    }

    @Test("Named command takes priority over radio tuning tokens")
    func namedCommandPriority() {
        let (cmd, _) = RadioCommandParser.parse("QRZ K4ABC")
        // Should be a lookup, not try to parse K4ABC as a token
        #expect(cmd.namedCommand != nil)
        #expect(cmd.frequencyMHz == nil)
    }

    @Test("QRZ without callsign falls through to radio parse")
    func qrzNoCallFallsThrough() {
        let (cmd, _) = RadioCommandParser.parse("QRZ")
        // No argument means it can't be a lookup
        #expect(cmd.namedCommand == nil)
    }
}
