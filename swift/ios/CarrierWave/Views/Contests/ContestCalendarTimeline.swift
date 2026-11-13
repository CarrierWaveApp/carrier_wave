import SwiftUI

// MARK: - CalendarFormatters

enum CalendarFormatters {
    static let utcTime: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    static let localTime24: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = .current
        return fmt
    }()

    static let localTime12: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.timeZone = .current
        return fmt
    }()

    static let dayHeader: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    static let localDayHeader: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"
        fmt.timeZone = .current
        return fmt
    }()

    static let fullDay: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    static let localFullDay: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        fmt.timeZone = .current
        return fmt
    }()

    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }

    static var localCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    static func calendar(useUTC: Bool) -> Calendar {
        useUTC ? utcCalendar : localCalendar
    }

    static func timeString(from date: Date, useUTC: Bool) -> String {
        if useUTC {
            return utcTime.string(from: date)
        }
        let use12 = UserDefaults.standard.bool(forKey: "contestCalendarUse12Hour")
        return (use12 ? localTime12 : localTime24).string(from: date)
    }

    static func dayHeaderString(from date: Date, useUTC: Bool) -> String {
        (useUTC ? dayHeader : localDayHeader).string(from: date)
    }

    static func fullDayString(from date: Date, useUTC: Bool) -> String {
        (useUTC ? fullDay : localFullDay).string(from: date)
    }

    static func hourLabel(_ hour: Int, useUTC: Bool) -> String {
        if useUTC {
            return String(format: "%02dZ", hour)
        }
        let use12 = UserDefaults.standard.bool(forKey: "contestCalendarUse12Hour")
        if use12 {
            let suffix = hour < 12 ? "a" : "p"
            let display = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            return "\(display)\(suffix)"
        }
        return String(format: "%02d", hour)
    }
}

// MARK: - WeekTimelineView

/// Week view showing 7 day columns with contest event blocks.
struct WeekTimelineView: View {
    // MARK: Internal

    @Binding var referenceDate: Date

    let contests: [Contest]
    var useUTC: Bool = true
    let onSelect: (Contest) -> Void

    var body: some View {
        VStack(spacing: 0) {
            weekNav
            Divider()
            ScrollView {
                weekContent
            }
        }
    }

    // MARK: Private

    private var cal: Calendar {
        CalendarFormatters.calendar(useUTC: useUTC)
    }

    private var weekStart: Date {
        let weekday = cal.component(.weekday, from: referenceDate)
        let delta = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -delta, to: cal.startOfDay(for: referenceDate))!
    }

    private var weekDays: [Date] {
        (0 ..< 7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let end = weekDays.last ?? weekStart
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: end))"
    }

    private var weekNav: some View {
        HStack {
            Button { adjustWeek(-1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(weekRangeLabel)
                .font(.headline)
            Spacer()
            Button { adjustWeek(1) } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var weekContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let isToday = cal.isDateInToday(day)
                    Text(CalendarFormatters.dayHeaderString(from: day, useUTC: useUTC))
                        .font(.caption2.weight(isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            Divider()

            HStack(alignment: .top, spacing: 2) {
                ForEach(weekDays, id: \.self) { day in
                    weekDayColumn(day)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private func weekDayColumn(_ day: Date) -> some View {
        let items = contestsOn(day)
        return VStack(spacing: 2) {
            ForEach(items) { contest in
                Button { onSelect(contest) } label: {
                    WeekEventBlock(contest: contest, day: day, useUTC: useUTC)
                }
                .buttonStyle(.plain)
            }
            if items.isEmpty {
                Color.clear.frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func contestsOn(_ day: Date) -> [Contest] {
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)
        else {
            return []
        }
        return contests.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
    }

    private func adjustWeek(_ delta: Int) {
        if let next = cal.date(byAdding: .weekOfYear, value: delta, to: referenceDate) {
            referenceDate = next
        }
    }
}

// MARK: - WeekEventBlock

private struct WeekEventBlock: View {
    // MARK: Internal

    let contest: Contest
    let day: Date
    var useUTC: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(contest.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(Color(.label))
            Text(CalendarFormatters.timeString(from: contest.startDate, useUTC: useUTC))
                .font(.system(size: 8).monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(blockColor, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Private

    private var blockColor: Color {
        contest.isActive ? .green.opacity(0.2) : .blue.opacity(0.15)
    }
}
