import Foundation

// MARK: - TimestampExtraction

/// Result of extracting date/time tokens from a row of text.
struct TimestampExtraction {
    /// The remaining text after date/time tokens are removed
    let remainingText: String
    /// Extracted date components (may be partial)
    let date: DateComponents?
    /// Extracted time components (may be partial)
    let time: DateComponents?
}

// MARK: - TimestampExtractor

/// Extracts date and time tokens from scanned log row text before quick entry parsing.
///
/// Handwritten logs often have dates and times that the `QuickEntryParser` doesn't handle.
/// This pre-processes each row to pull out date/time tokens, returning the remaining text
/// for the quick entry parser.
enum TimestampExtractor {
    // MARK: Internal

    /// Extract date and time from a row of text.
    /// - Parameter text: The full row text from OCR
    /// - Returns: Extraction result with remaining text and any found date/time
    static func extract(from text: String) -> TimestampExtraction {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var dateComponents: DateComponents?
        var timeComponents: DateComponents?
        var indicesToRemove: [Int] = []

        for (index, token) in tokens.enumerated() {
            if dateComponents == nil, let dc = parseDate(token) {
                dateComponents = dc
                indicesToRemove.append(index)
            } else if timeComponents == nil, let tc = parseTime(token) {
                timeComponents = tc
                indicesToRemove.append(index)
            }
        }

        // Remove extracted tokens in reverse order to preserve indices
        for index in indicesToRemove.sorted().reversed() {
            tokens.remove(at: index)
        }

        return TimestampExtraction(
            remainingText: tokens.joined(separator: " "),
            date: dateComponents,
            time: timeComponents
        )
    }

    /// Build a full Date from extracted components, using fallbacks for missing parts.
    /// - Parameters:
    ///   - date: Date components from this row
    ///   - time: Time components from this row
    ///   - fallbackDate: Date components inherited from a previous row
    ///   - defaultDate: User-provided default date
    /// - Returns: A Date if enough components are available, nil otherwise
    static func buildDate(
        date: DateComponents?,
        time: DateComponents?,
        fallbackDate: DateComponents?,
        defaultDate: Date?
    ) -> Date? {
        let effectiveDate = date ?? fallbackDate ?? defaultDate.map(calendarComponents)

        guard let dc = effectiveDate else {
            // Even without a date, if we have time and a default, use that
            return nil
        }

        var merged = DateComponents()
        merged.year = dc.year
        merged.month = dc.month
        merged.day = dc.day
        merged.hour = time?.hour ?? 0
        merged.minute = time?.minute ?? 0
        merged.timeZone = TimeZone(identifier: "UTC")

        return Calendar.current.date(from: merged)
    }

    // MARK: Private

    private static let monthAbbreviations: [String: Int] = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
        "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
    ]

    /// Parse a token as a date. Supports:
    /// - MM/DD/YY, MM/DD/YYYY
    /// - YYYY-MM-DD
    /// - DD-MMM-YY, DD-MMM-YYYY (e.g., 30-MAR-26)
    private static func parseDate(_ token: String) -> DateComponents? {
        let upper = token.uppercased()

        // YYYY-MM-DD
        if let match = upper.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
            return DateComponents(
                year: Int(match.1),
                month: Int(match.2),
                day: Int(match.3)
            )
        }

        // MM/DD/YYYY or MM/DD/YY
        if let match = upper.wholeMatch(of: /(\d{1,2})\/(\d{1,2})\/(\d{2,4})/) {
            let yearRaw = Int(match.3) ?? 0
            let year = yearRaw < 100 ? 2_000 + yearRaw : yearRaw
            return DateComponents(
                year: year,
                month: Int(match.1),
                day: Int(match.2)
            )
        }

        // DD-MMM-YY or DD-MMM-YYYY (e.g., 30-MAR-26)
        if let match = upper.wholeMatch(of: /(\d{1,2})-([A-Z]{3})-(\d{2,4})/) {
            guard let month = monthAbbreviations[String(match.2)] else {
                return nil
            }
            let yearRaw = Int(match.3) ?? 0
            let year = yearRaw < 100 ? 2_000 + yearRaw : yearRaw
            return DateComponents(
                year: year,
                month: month,
                day: Int(match.1)
            )
        }

        return nil
    }

    /// Parse a token as a time. Supports:
    /// - HHMM (4 digits, 0000-2359)
    /// - HH:MM
    /// - HMMZ or HHMMZ (3-4 digits + Z suffix, e.g. 930Z, 1804Z)
    private static func parseTime(_ token: String) -> DateComponents? {
        let upper = token.uppercased()

        // HH:MM or HH:MMZ
        let colonStr = upper.hasSuffix("Z") ? String(upper.dropLast()) : upper
        if let match = colonStr.wholeMatch(of: /(\d{1,2}):(\d{2})/) {
            let hour = Int(match.1) ?? 0
            let minute = Int(match.2) ?? 0
            guard hour <= 23, minute <= 59 else {
                return nil
            }
            return DateComponents(hour: hour, minute: minute)
        }

        // Strip Z suffix for digit-only patterns
        let stripped = upper.hasSuffix("Z") ? String(upper.dropLast()) : upper
        let isZulu = upper.hasSuffix("Z")

        // HHMM (exactly 4 digits) or HHMMZ
        if stripped.count == 4, let match = stripped.wholeMatch(of: /(\d{2})(\d{2})/) {
            let hour = Int(match.1) ?? 0
            let minute = Int(match.2) ?? 0
            guard hour <= 23, minute <= 59 else {
                return nil
            }
            return DateComponents(hour: hour, minute: minute)
        }

        // HMM + Z (3 digits + Z, e.g. 930Z = 09:30) — only with Z suffix
        // to avoid false positives on bare 3-digit numbers like RSTs
        if isZulu, stripped.count == 3, let match = stripped.wholeMatch(of: /(\d)(\d{2})/) {
            let hour = Int(match.1) ?? 0
            let minute = Int(match.2) ?? 0
            guard hour <= 9, minute <= 59 else {
                return nil
            }
            return DateComponents(hour: hour, minute: minute)
        }

        return nil
    }

    private static func calendarComponents(from date: Date) -> DateComponents {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateComponents([.year, .month, .day], from: date)
    }
}
