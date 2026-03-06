import CarrierWaveData
import Foundation

/// Template-driven Cabrillo 3.0 log generator.
struct CabrilloExportService {
    // MARK: Internal

    /// Generate Cabrillo 3.0 log text from a contest session.
    func generate(
        session: LoggingSession,
        qsos: [QSO],
        definition: ContestDefinition,
        score: ContestScoreSnapshot
    ) -> String {
        var lines: [String] = []

        // Header
        lines.append("START-OF-LOG: 3.0")
        lines.append("CONTEST: \(definition.cabrilloCategoryContest)")
        lines.append("CALLSIGN: \(session.contestOperator ?? session.myCallsign)")
        lines.append("CATEGORY-OPERATOR: \(session.contestCategory ?? "SINGLE-OP")")
        lines.append("CATEGORY-BAND: \(session.contestBands ?? "ALL")")
        lines.append("CATEGORY-POWER: \(session.contestPower ?? "HIGH")")
        lines.append("CATEGORY-MODE: \(definition.modes.first ?? "CW")")
        lines.append("CATEGORY-ASSISTED: NON-ASSISTED")
        lines.append("CLAIMED-SCORE: \(score.finalScore)")
        lines.append("OPERATORS: \(session.contestOperator ?? session.myCallsign)")
        lines.append("CREATED-BY: CW Sweep")

        // Sort QSOs by timestamp
        let sorted = qsos
            .filter { $0.isContestQSO && !$0.isHidden }
            .sorted { $0.timestamp < $1.timestamp }

        // QSO lines
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmm"
        timeFormatter.timeZone = TimeZone(identifier: "UTC")

        for qso in sorted {
            let freq = formatFrequency(qso.frequency)
            let mode = formatMode(qso.mode)
            let date = dateFormatter.string(from: qso.timestamp)
            let time = timeFormatter.string(from: qso.timestamp)
            let myCall = pad(session.contestOperator ?? session.myCallsign, width: 13)
            let rstS = pad(qso.rstSent ?? "599", width: 3)
            let exchS = pad(qso.contestExchangeSent ?? "", width: 6)
            let hisCall = pad(qso.callsign, width: 13)
            let rstR = pad(qso.rstReceived ?? "599", width: 3)
            let exchR = pad(qso.contestExchangeReceived ?? "", width: 6)

            let line = "QSO: \(freq) \(mode) \(date) \(time) \(myCall) \(rstS) \(exchS) \(hisCall) \(rstR) \(exchR)"
            lines.append(line)
        }

        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Private

    // MARK: - Formatting

    private func formatFrequency(_ freqMHz: Double?) -> String {
        guard let freq = freqMHz else {
            return "     "
        }
        // Cabrillo freq is in kHz, 5 chars wide
        let kHz = Int(freq * 1_000)
        return String(format: "%5d", kHz)
    }

    private func formatMode(_ mode: String) -> String {
        switch mode.uppercased() {
        case "CW": "CW"
        case "SSB",
             "USB",
             "LSB": "PH"
        case "FT8",
             "FT4",
             "RTTY",
             "PSK31",
             "PSK63": "RY"
        default: "CW"
        }
    }

    private func pad(_ string: String, width: Int) -> String {
        let s = string.prefix(width)
        return s.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
