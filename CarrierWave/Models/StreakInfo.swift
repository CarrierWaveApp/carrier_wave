import Foundation

// MARK: - StreakCategory

enum StreakCategory: String, Identifiable, CaseIterable {
    case daily = "Daily QSOs"
    case pota = "POTA Activations"
    case mode = "Mode"
    case band = "Band"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .daily: "flame.fill"
        case .pota: "leaf.fill"
        case .mode: "waveform.path"
        case .band: "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - StreakInfo

struct StreakInfo: Identifiable {
    /// Placeholder for loading states
    static let placeholder = StreakInfo(
        id: "placeholder",
        category: .daily,
        subcategory: nil,
        currentStreak: 0,
        longestStreak: 0,
        currentStartDate: nil,
        longestStartDate: nil,
        longestEndDate: nil,
        lastActiveDate: nil
    )

    let id: String
    let category: StreakCategory
    let subcategory: String? // Mode name or band name for specific streaks
    let currentStreak: Int
    let longestStreak: Int
    let currentStartDate: Date?
    let longestStartDate: Date?
    let longestEndDate: Date?
    let lastActiveDate: Date?

    /// True if active yesterday but not today (streak at risk of ending)
    var isAtRisk: Bool {
        guard let lastActive = lastActiveDate else {
            return false
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return calendar.isDate(lastActive, inSameDayAs: yesterday)
    }

    /// Display name combining category and subcategory
    var displayName: String {
        if let subcategory {
            return "\(subcategory) \(category.rawValue)"
        }
        return category.rawValue
    }
}

// MARK: - StreakResult

struct StreakResult {
    static let empty = StreakResult(
        current: 0, longest: 0, currentStart: nil,
        longestStart: nil, longestEnd: nil, lastActive: nil
    )

    let current: Int
    let longest: Int
    let currentStart: Date?
    let longestStart: Date?
    let longestEnd: Date?
    let lastActive: Date?
}

// MARK: - StreakSegment

private struct StreakSegment {
    let start: Date
    let end: Date
    let length: Int
}

// MARK: - StreakCalculator

enum StreakCalculator {
    // MARK: Internal

    /// Calculate streak from a set of active dates
    static func calculateStreak(
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
