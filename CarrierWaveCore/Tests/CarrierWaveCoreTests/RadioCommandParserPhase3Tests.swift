//
//  RadioCommandParserPhase3Tests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("RadioCommandParser Phase 3 Tests")
struct RadioCommandParserPhase3Tests {
    // MARK: - CQ Command

    @Test("CQ sends CQ macro")
    func parseCQ() {
        let (cmd, tokens) = RadioCommandParser.parse("CQ")
        #expect(cmd.namedCommand == .sendCQ)
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .command)
    }

    // MARK: - WPM / Speed

    @Test("WPM sets CW speed")
    func parseWPM() {
        let (cmd, _) = RadioCommandParser.parse("WPM 25")
        #expect(cmd.namedCommand == .setSpeed(wpm: 25))
    }

    @Test("SPEED alias for WPM")
    func parseSpeed() {
        let (cmd, _) = RadioCommandParser.parse("SPEED 30")
        #expect(cmd.namedCommand == .setSpeed(wpm: 30))
    }

    @Test("WPM rejects out-of-range values")
    func parseWPMOutOfRange() {
        let (cmd1, _) = RadioCommandParser.parse("WPM 3")
        #expect(cmd1.namedCommand == nil)
        let (cmd2, _) = RadioCommandParser.parse("WPM 65")
        #expect(cmd2.namedCommand == nil)
    }

    @Test("WPM without argument falls through")
    func parseWPMNoArg() {
        let (cmd, _) = RadioCommandParser.parse("WPM")
        #expect(cmd.namedCommand == nil)
    }

    // MARK: - Contest Mode

    @Test("RUN sets contest mode")
    func parseRun() {
        let (cmd, _) = RadioCommandParser.parse("RUN")
        #expect(cmd.namedCommand == .setContestMode(mode: .run))
    }

    @Test("S&P sets contest mode")
    func parseSAndP() {
        let (cmd, _) = RadioCommandParser.parse("S&P")
        #expect(cmd.namedCommand == .setContestMode(mode: .searchAndPounce))
    }

    @Test("SP alias for S&P")
    func parseSP() {
        let (cmd, _) = RadioCommandParser.parse("SP")
        #expect(cmd.namedCommand == .setContestMode(mode: .searchAndPounce))
    }

    @Test("SAP alias for S&P")
    func parseSAP() {
        let (cmd, _) = RadioCommandParser.parse("SAP")
        #expect(cmd.namedCommand == .setContestMode(mode: .searchAndPounce))
    }

    // MARK: - Find Callsign

    @Test("FIND searches for callsign")
    func parseFind() {
        let (cmd, tokens) = RadioCommandParser.parse("FIND W1AW")
        #expect(cmd.namedCommand == .findCall(callsign: "W1AW"))
        #expect(tokens[0].kind == .command)
    }

    @Test("FIND without callsign falls through")
    func parseFindNoArg() {
        let (cmd, _) = RadioCommandParser.parse("FIND")
        #expect(cmd.namedCommand == nil)
    }

    @Test("FIND uppercases callsign")
    func parseFindUppercase() {
        let (cmd, _) = RadioCommandParser.parse("FIND w1aw")
        #expect(cmd.namedCommand == .findCall(callsign: "W1AW"))
    }

    // MARK: - Last QSOs

    @Test("LAST with count")
    func parseLast() {
        let (cmd, _) = RadioCommandParser.parse("LAST 5")
        #expect(cmd.namedCommand == .lastQSOs(count: 5))
    }

    @Test("LAST without count defaults to 10")
    func parseLastDefault() {
        let (cmd, _) = RadioCommandParser.parse("LAST")
        #expect(cmd.namedCommand == .lastQSOs(count: 10))
    }

    @Test("LAST clamps to 100 maximum")
    func parseLastClamped() {
        let (cmd, _) = RadioCommandParser.parse("LAST 500")
        #expect(cmd.namedCommand == .lastQSOs(count: 100))
    }

    @Test("LAST clamps to 1 minimum")
    func parseLastMinimum() {
        let (cmd, _) = RadioCommandParser.parse("LAST 0")
        #expect(cmd.namedCommand == .lastQSOs(count: 1))
    }

    // MARK: - Session Count

    @Test("COUNT returns session count command")
    func parseCount() {
        let (cmd, tokens) = RadioCommandParser.parse("COUNT")
        #expect(cmd.namedCommand == .sessionCount)
        #expect(tokens[0].kind == .command)
    }
}
