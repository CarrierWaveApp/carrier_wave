import CarrierWaveCore
import Foundation

/// Parses POTA job error/warning strings into structured components.
/// POTA messages follow: "ERROR [QSO N] <message>. <ADIF record>"
///                   or: "WARNING [QSO N] <message>. <ADIF record>"
enum POTAJobErrorParser {
    // MARK: Internal

    struct ParsedMessage {
        let qsoIndex: Int?
        let message: String
        let qsoSummary: QSOSummary?
    }

    /// Extracted QSO fields from the embedded ADIF record.
    struct QSOSummary: Hashable {
        let callsign: String
        let band: String
        let mode: String
    }

    /// Extract QSO index, human-readable message, and QSO fields from a POTA string.
    static func parse(_ raw: String) -> ParsedMessage {
        let qsoSummary = extractQSOSummary(from: raw)

        // Match: "ERROR [QSO 2] PHONE is not a valid mode. <CALL:6>..."
        //    or: "WARNING [QSO 1] Ignoring duplicate QSO. <CALL:4>..."
        let pattern = #"^(?:ERROR|WARNING)\s*\[QSO\s*(\d+)\]\s*(.+?)\.?\s*<"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
               in: raw, range: NSRange(raw.startIndex..., in: raw)
           )
        {
            let idxRange = Range(match.range(at: 1), in: raw)
            let msgRange = Range(match.range(at: 2), in: raw)
            let qsoIndex = idxRange.flatMap { Int(raw[$0]) }
            let msg = msgRange.map {
                String(raw[$0]).trimmingCharacters(in: .whitespaces)
            }
            return ParsedMessage(
                qsoIndex: qsoIndex, message: msg ?? raw,
                qsoSummary: qsoSummary
            )
        }
        // Fallback: strip ADIF if present but no [QSO N] prefix
        if let adifRange = raw.range(of: "<CALL:") ?? raw.range(of: "<call:") {
            let msg = raw[raw.startIndex ..< adifRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .trimmingCharacters(in: .whitespaces)
            if !msg.isEmpty {
                return ParsedMessage(
                    qsoIndex: nil, message: msg, qsoSummary: qsoSummary
                )
            }
        }
        return ParsedMessage(qsoIndex: nil, message: raw, qsoSummary: nil)
    }

    /// Summarize a list of POTA messages into a concise diagnostic string.
    static func summarize(_ messages: [String]) -> String {
        let parsed = messages.map { parse($0) }
        let uniqueMessages = Set(parsed.map(\.message))
        let summary = uniqueMessages.prefix(3).joined(separator: "; ")
        let more = uniqueMessages.count > 3
            ? " (+\(uniqueMessages.count - 3) more)" : ""
        return "\(messages.count) issue(s): \(summary)\(more)"
    }

    // MARK: Private

    /// Extract CALL, BAND, MODE from an embedded ADIF record using ADIFParser.
    private static func extractQSOSummary(from raw: String) -> QSOSummary? {
        // Find the start of ADIF fields — look for first "<" followed by a field name
        guard let adifStart = raw.range(of: "<CALL:", options: .caseInsensitive)
            ?? raw.range(of: "<call:", options: .caseInsensitive)
        else {
            return nil
        }
        let adifPortion = String(raw[adifStart.lowerBound...]) + "<EOR>"
        let call = ADIFParser.extractField("CALL", from: adifPortion)
        let band = ADIFParser.extractField("BAND", from: adifPortion)
        let mode = ADIFParser.extractField("MODE", from: adifPortion)
        guard let call, !call.isEmpty else {
            return nil
        }
        return QSOSummary(
            callsign: call, band: band ?? "?", mode: mode ?? "?"
        )
    }
}
