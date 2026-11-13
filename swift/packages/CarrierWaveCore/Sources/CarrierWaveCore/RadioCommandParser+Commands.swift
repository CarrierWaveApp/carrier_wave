// MARK: - Phase 3 Command Parsing

extension RadioCommandParser {
    static func parseCQCommand(raw: String) -> (RadioCommand, [RadioParsedToken]) {
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Send CQ (F1)", state: .valid)
        return (RadioCommand(namedCommand: .sendCQ), [token])
    }

    static func parseSendCWCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        let text = args.joined(separator: " ")
        guard !text.isEmpty else {
            return nil
        }
        let clamped = String(text.prefix(100))
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Send CW: \(clamped)", state: .valid)
        return (RadioCommand(namedCommand: .sendCW(text: clamped)), [token])
    }

    static func parseSpeedCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        guard let arg = args.first, let wpm = Int(arg), wpm >= 5, wpm <= 60 else {
            return nil
        }
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Set CW speed \(wpm) WPM", state: .valid)
        return (RadioCommand(namedCommand: .setSpeed(wpm: wpm)), [token])
    }

    static func parseContestModeCommand(
        _ mode: ContestModeValue, raw: String
    ) -> (RadioCommand, [RadioParsedToken]) {
        let label = mode == .run ? "RUN" : "S&P"
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Set contest mode: \(label)", state: .valid)
        return (RadioCommand(namedCommand: .setContestMode(mode: mode)), [token])
    }

    static func parseFindCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        guard let call = args.first else {
            return nil
        }
        let callsign = call.uppercased()
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Search log for \(callsign)", state: .valid)
        return (RadioCommand(namedCommand: .findCall(callsign: callsign)), [token])
    }

    static func parseLastCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken]) {
        let count = max(1, min(args.first.flatMap(Int.init) ?? 10, 100))
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Show last \(count) QSOs", state: .valid)
        return (RadioCommand(namedCommand: .lastQSOs(count: count)), [token])
    }

    static func parseCountCommand(raw: String) -> (RadioCommand, [RadioParsedToken]) {
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Session QSO count", state: .valid)
        return (RadioCommand(namedCommand: .sessionCount), [token])
    }
}
