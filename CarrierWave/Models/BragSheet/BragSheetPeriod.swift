import Foundation

// MARK: - BragSheetPeriod

/// Time windows for brag sheet cards.
enum BragSheetPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case monthly
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .allTime: "All Time"
        }
    }

    var shortName: String {
        switch self {
        case .weekly: "Week"
        case .monthly: "Month"
        case .allTime: "All"
        }
    }

    var systemImage: String {
        switch self {
        case .weekly: "calendar.badge.clock"
        case .monthly: "calendar"
        case .allTime: "infinity"
        }
    }

    /// Default preset for this period.
    var defaultPreset: BragSheetPreset {
        switch self {
        case .weekly: .contester
        case .monthly: .general
        case .allTime: .dxer
        }
    }

    /// Date range for this period using UTC calendar.
    /// Returns (start, end) where start is inclusive and end is the current moment.
    func dateRange(now: Date = Date()) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday

        switch self {
        case .weekly:
            // Monday 0000Z through now
            let weekday = calendar.component(.weekday, from: now)
            // weekday: 1=Sun, 2=Mon, ..., 7=Sat
            let daysFromMonday = (weekday + 5) % 7
            let monday = calendar.date(
                byAdding: .day, value: -daysFromMonday,
                to: calendar.startOfDay(for: now)
            )!
            return (start: monday, end: now)

        case .monthly:
            // First of current month 0000Z through now
            let components = calendar.dateComponents([.year, .month], from: now)
            let monthStart = calendar.date(from: components)!
            return (start: monthStart, end: now)

        case .allTime:
            return (start: .distantPast, end: now)
        }
    }

    /// Formatted label for the period (e.g., "Feb 17–23, 2026" or "February 2026").
    func periodLabel(now: Date = Date()) -> String {
        let range = dateRange(now: now)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!

        switch self {
        case .weekly:
            formatter.dateFormat = "MMM d"
            let start = formatter.string(from: range.start)
            let endCalendar = Calendar(identifier: .gregorian)
            let endOfWeek = endCalendar.date(
                byAdding: .day, value: 6, to: range.start
            ) ?? range.end
            formatter.dateFormat = "d, yyyy"
            let end = formatter.string(from: endOfWeek)
            return "\(start)–\(end)"

        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: range.start)

        case .allTime:
            return "All Time"
        }
    }
}
