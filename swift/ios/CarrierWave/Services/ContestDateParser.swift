import CarrierWaveData
import Foundation

/// Parses WA7BNM Contest Calendar date strings like
/// `"2200Z, Feb 27 to 2200Z, Mar 1"` into a start/end date pair.
nonisolated enum ContestDateParser {
    // MARK: Internal

    /// Parse a description string into start and end dates.
    /// Returns nil if the format is unrecognizable.
    static func parse(
        _ description: String,
        referenceYear: Int = Calendar.current.component(.year, from: Date())
    ) -> (start: Date, end: Date)? {
        // Split on " to " to get start/end halves
        let halves = description.components(separatedBy: " to ")
        guard halves.count == 2 else {
            return nil
        }

        guard let start = parseHalf(halves[0].trimmingCharacters(in: .whitespaces),
                                    referenceYear: referenceYear),
            let end = parseHalf(halves[1].trimmingCharacters(in: .whitespaces),
                                referenceYear: referenceYear)
        else {
            return nil
        }

        // Handle Dec→Jan rollover: if end is before start, bump end year
        var adjustedEnd = end
        if adjustedEnd < start {
            guard let rolled = Calendar.current.date(
                byAdding: .year, value: 1, to: adjustedEnd
            ) else {
                return nil
            }
            adjustedEnd = rolled
        }

        return (start: start, end: adjustedEnd)
    }

    // MARK: Private

    /// Month abbreviation lookup
    private static let monthMap: [String: Int] = [
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4,
        "May": 5, "Jun": 6, "Jul": 7, "Aug": 8,
        "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
    ]

    /// Parse one half like `"2200Z, Feb 27"` into a Date.
    private static func parseHalf(_ half: String, referenceYear: Int) -> Date? {
        // Expected format: "HHmmZ, Mon DD" or "HHmmZ, Mon D"
        let parts = half.components(separatedBy: ", ")
        guard parts.count == 2 else {
            return nil
        }

        let timePart = parts[0].trimmingCharacters(in: .whitespaces)
        let datePart = parts[1].trimmingCharacters(in: .whitespaces)

        // Parse time: "2200Z" or "2400Z"
        let timeStr = timePart.replacingOccurrences(of: "Z", with: "")
        guard let timeInt = Int(timeStr), timeStr.count == 4 else {
            return nil
        }

        let hour = timeInt / 100
        let minute = timeInt % 100

        // Handle "2400Z" → midnight next day
        let is2400 = hour == 24

        // Parse date: "Feb 27" or "Mar 1"
        let dateTokens = datePart.components(separatedBy: " ")
        guard dateTokens.count == 2,
              let month = monthMap[dateTokens[0]],
              let day = Int(dateTokens[1])
        else {
            return nil
        }

        var components = DateComponents()
        components.year = referenceYear
        components.month = month
        components.day = day
        components.hour = is2400 ? 0 : hour
        components.minute = is2400 ? 0 : minute
        components.timeZone = TimeZone(identifier: "UTC")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        guard var date = cal.date(from: components) else {
            return nil
        }

        // "2400Z" means start of the next day
        if is2400 {
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: date) else {
                return nil
            }
            date = nextDay
        }

        return date
    }
}
