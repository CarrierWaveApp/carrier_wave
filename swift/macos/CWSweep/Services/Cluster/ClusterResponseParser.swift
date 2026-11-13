import Foundation

// MARK: - SolarWeatherEntry

/// A parsed WWV/WCY solar weather report from the DX cluster
struct SolarWeatherEntry: Identifiable {
    let id = UUID()
    let date: String
    let hour: String
    let sfi: Int
    let aIndex: Int
    let kIndex: Int
    let forecast: String
    let reporter: String
}

// MARK: - ClusterFilterConfig

/// Parsed DX cluster filter configuration from SH/FILTER
struct ClusterFilterConfig {
    let count: Int?
    let filter: String
    let mode: String
    let output: String
    let commentOptions: String
    let rawLines: [String]
}

// MARK: - ClusterResponseParser

/// Parses structured responses from DX cluster commands (SH/WWV, SH/WCY, SH/FILTER)
enum ClusterResponseParser {
    // MARK: Internal

    // MARK: - WWV Parsing

    /// Parse SH/WWV or SH/WCY response lines into solar weather entries.
    /// Format: "25-Mar-2026 00    128   16   3    No Storms -> No Storms    <W0MU>"
    static func parseWWV(lines: [String]) -> [SolarWeatherEntry] {
        var entries: [SolarWeatherEntry] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let entry = parseWWVLine(trimmed) else {
                continue
            }
            entries.append(entry)
        }

        return entries
    }

    // MARK: - Filter Parsing

    /// Parse SH/FILTER response lines into filter configuration.
    /// Format:
    ///   DX configuration options:
    ///       Count: 20
    ///       Filter:
    ///       Mode: FILTER
    ///       Output: ON
    ///       Comment Options:
    static func parseFilter(lines: [String]) -> ClusterFilterConfig? {
        var count: Int?
        var filter = ""
        var mode = ""
        var output = ""
        var commentOptions = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let value = extractValue(from: trimmed, key: "Count") {
                count = Int(value)
            } else if let value = extractValue(from: trimmed, key: "Filter") {
                filter = value
            } else if let value = extractValue(from: trimmed, key: "Mode") {
                mode = value
            } else if let value = extractValue(from: trimmed, key: "Output") {
                output = value
            } else if let value = extractValue(from: trimmed, key: "Comment Options") {
                commentOptions = value
            }
        }

        // Only return if we found at least some config
        guard !mode.isEmpty || count != nil else {
            return nil
        }

        return ClusterFilterConfig(
            count: count,
            filter: filter,
            mode: mode,
            output: output,
            commentOptions: commentOptions,
            rawLines: lines
        )
    }

    // MARK: - Line Detection

    /// Check if a line looks like a WWV data row
    static func isWWVLine(_ line: String) -> Bool {
        parseWWVLine(line.trimmingCharacters(in: .whitespaces)) != nil
    }

    /// Check if a line is part of a filter response
    static func isFilterLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("DX configuration options")
            || trimmed.hasPrefix("Count:")
            || trimmed.hasPrefix("Filter:")
            || trimmed.hasPrefix("Mode:")
            || trimmed.hasPrefix("Output:")
            || trimmed.hasPrefix("Comment Options:")
    }

    /// Check if a line is a header row for WWV data
    static func isWWVHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("Date") && trimmed.contains("SFI")
    }

    // MARK: Private

    // swiftlint:disable:next large_tuple
    nonisolated(unsafe) private static let wwvPattern: Regex<(
        Substring,
        Substring,
        Substring,
        Substring,
        Substring,
        Substring,
        Substring,
        Substring
    )>? = // 25-Mar-2026 00    128   16   3    No Storms -> No Storms    <W0MU>
        try? Regex(#"(\d{1,2}-\w{3}-\d{4})\s+(\d{2})\s+(\d+)\s+(\d+)\s+(\d+)\s+(.+?)\s+<(\w+)>"#)

    private static func parseWWVLine(_ line: String) -> SolarWeatherEntry? {
        guard let pattern = wwvPattern,
              let match = line.firstMatch(of: pattern)
        else {
            return nil
        }

        guard let sfi = Int(match.3),
              let aIndex = Int(match.4),
              let kIndex = Int(match.5)
        else {
            return nil
        }

        return SolarWeatherEntry(
            date: String(match.1),
            hour: String(match.2),
            sfi: sfi,
            aIndex: aIndex,
            kIndex: kIndex,
            forecast: String(match.6).trimmingCharacters(in: .whitespaces),
            reporter: String(match.7)
        )
    }

    private static func extractValue(from line: String, key: String) -> String? {
        guard line.hasPrefix("\(key):") else {
            return nil
        }
        return line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
    }
}
