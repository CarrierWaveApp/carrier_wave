import Foundation

/// Parses DX cluster spot lines into structured data.
///
/// Standard format:
/// `DX de SPOTTER:    FREQ  CALLSIGN  comment            TIMEZ`
/// Example:
/// `DX de W3LPL:      14076.0  JA1ABC     FT8               1423Z`
enum DXSpotParser {
    // MARK: Internal

    /// Parse a single line from a DX cluster
    static func parse(line: String) -> DXClusterSpot? {
        guard let match = line.firstMatch(of: spotPattern) else {
            return nil
        }

        let spotter = String(match.1).trimmingCharacters(in: .whitespaces)
        guard let freq = Double(match.2) else {
            return nil
        }
        let callsign = String(match.3).trimmingCharacters(in: .whitespaces)
        let comment = String(match.4).trimmingCharacters(in: .whitespaces)
        let timeStr = String(match.5)

        let timestamp = parseUTCTime(timeStr) ?? Date()

        return DXClusterSpot(
            spotter: spotter,
            frequencyKHz: freq,
            callsign: callsign,
            comment: comment,
            timestamp: timestamp
        )
    }

    /// Parse mode from a DX cluster comment (e.g. "FT8 +3dB" → "FT8")
    static func parseMode(from comment: String) -> String? {
        for (token, pattern) in modePatterns {
            if comment.firstMatch(of: pattern) != nil {
                return token
            }
        }
        return nil
    }

    /// Parse CW speed from a DX cluster comment (e.g. "CW 28 WPM" → 28)
    static func parseCWSpeed(from comment: String) -> Int? {
        guard let match = comment.firstMatch(of: wpmPattern) else {
            return nil
        }
        return Int(match.1)
    }

    // MARK: Private

    /// DX de <spotter>: <freq> <callsign> <comment> <time>Z
    nonisolated(unsafe) private static let spotPattern =
        /DX\s+de\s+(\S+?):\s+(\d+\.?\d*)\s+(\S+)\s+(.*?)\s+(\d{4})Z\s*$/

    // MARK: - Comment Parsing

    /// Known mode tokens in priority order
    private static let modeTokens = [
        "FT8", "FT4", "CW", "SSB", "LSB", "USB", "AM", "FM",
        "RTTY", "PSK31", "PSK63", "JT65", "JT9", "JS8",
        "OLIVIA", "SSTV", "DIGI", "DATA",
    ]

    nonisolated(unsafe) private static let modePatterns: [(String, Regex<Substring>)] = modeTokens.compactMap { token in
        guard let regex = try? Regex<Substring>("(?i)\\b\(token)\\b") else {
            return nil
        }
        return (token, regex)
    }

    nonisolated(unsafe) private static let wpmPattern =
        /(\d{1,3})\s*WPM/

    /// Parse HHMM UTC time string into today's date with that time
    private static func parseUTCTime(_ timeStr: String) -> Date? {
        guard timeStr.count == 4,
              let hour = Int(timeStr.prefix(2)),
              let minute = Int(timeStr.suffix(2))
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let date = calendar.date(from: components) else {
            return nil
        }

        // If the parsed time is in the future, it was probably yesterday
        if date > now {
            return calendar.date(byAdding: .day, value: -1, to: date)
        }
        return date
    }
}
