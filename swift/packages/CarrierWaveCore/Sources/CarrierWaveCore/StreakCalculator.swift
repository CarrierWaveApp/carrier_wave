import Foundation

// MARK: - StreakResult

public struct StreakResult: Sendable {
    // MARK: Lifecycle

    public init(
        current: Int,
        longest: Int,
        currentStart: Date?,
        longestStart: Date?,
        longestEnd: Date?,
        lastActive: Date?
    ) {
        self.current = current
        self.longest = longest
        self.currentStart = currentStart
        self.longestStart = longestStart
        self.longestEnd = longestEnd
        self.lastActive = lastActive
    }

    // MARK: Public

    public static let empty = StreakResult(
        current: 0, longest: 0, currentStart: nil,
        longestStart: nil, longestEnd: nil, lastActive: nil
    )

    public let current: Int
    public let longest: Int
    public let currentStart: Date?
    public let longestStart: Date?
    public let longestEnd: Date?
    public let lastActive: Date?
}

// MARK: - StreakSegment

private struct StreakSegment {
    let start: Date
    let end: Date
    let length: Int
}

// MARK: - StreakCalculator

public enum StreakCalculator {
    // MARK: Public

    /// Calculate streak from a set of active dates
    public static func calculateStreak(
        from activeDates: Set<Date>,
        calendar: Calendar = .current,
        useUTC: Bool = false
    ) -> StreakResult {
        guard !activeDates.isEmpty else {
            return .empty
        }

        let cal = useUTC ? makeUTCCalendar() : calendar
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let sortedDates = activeDates.sorted()
        let streaks = findAllStreaks(from: sortedDates, calendar: cal)

        let longestStreak = streaks.max { $0.length < $1.length }
        let currentStreak = streaks.first { streak in
            cal.isDate(streak.end, inSameDayAs: today)
                || cal.isDate(streak.end, inSameDayAs: yesterday)
        }

        return StreakResult(
            current: currentStreak?.length ?? 0,
            longest: longestStreak?.length ?? 0,
            currentStart: currentStreak?.start,
            longestStart: longestStreak?.start,
            longestEnd: longestStreak?.end,
            lastActive: sortedDates.last
        )
    }

    // MARK: Private

    private static func findAllStreaks(from sortedDates: [Date], calendar cal: Calendar)
        -> [StreakSegment]
    {
        var streaks: [StreakSegment] = []
        var currentStart = sortedDates[0]
        var previousDate = sortedDates[0]
        var length = 1

        for date in sortedDates.dropFirst() {
            let dayDiff = cal.dateComponents([.day], from: previousDate, to: date).day ?? 0
            if dayDiff == 1 {
                length += 1
            } else if dayDiff > 1 {
                streaks.append(
                    StreakSegment(start: currentStart, end: previousDate, length: length)
                )
                currentStart = date
                length = 1
            }
            previousDate = date
        }
        streaks.append(StreakSegment(start: currentStart, end: previousDate, length: length))
        return streaks
    }

    private static func makeUTCCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}
