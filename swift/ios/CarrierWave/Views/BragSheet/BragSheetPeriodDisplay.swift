import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - FfiBragPeriod display + windowing

/// Host-side display metadata and UTC windowing for `FfiBragPeriod`. The window
/// math mirrors the shared Rust `BragPeriod::window` (Monday-00:00Z week start,
/// month first-day start) and is used only for share-card snapshot filtering and
/// the on-screen period label; all stat values come from Rust `computeBrag`.
extension FfiBragPeriod {
    static var displayCases: [FfiBragPeriod] {
        [.weekly, .monthly, .allTime]
    }

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

    /// (start, end) window in the UTC calendar; end is the current moment.
    nonisolated func dateRange(now: Date = Date()) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday

        switch self {
        case .weekly:
            let weekday = calendar.component(.weekday, from: now)
            let daysFromMonday = (weekday + 5) % 7
            let monday = calendar.date(
                byAdding: .day, value: -daysFromMonday,
                to: calendar.startOfDay(for: now)
            )!
            return (start: monday, end: now)

        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: now)
            let monthStart = calendar.date(from: components)!
            return (start: monthStart, end: now)

        case .allTime:
            return (start: .distantPast, end: now)
        }
    }

    /// Formatted label (e.g. "Feb 17–23, 2026" or "February 2026").
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
