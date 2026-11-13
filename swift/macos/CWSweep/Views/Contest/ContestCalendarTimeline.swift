import SwiftUI

// MARK: - CalendarContest

/// Lightweight contest representation for calendar views, built from
/// ContestBrowserEntry + ContestOccurrence pairs.
struct CalendarContest: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let modes: [String]
    let bands: [String]
    let entryID: String

    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var durationLabel: String {
        let hours = Int(duration.rounded() / 3_600)
        if hours >= 24, hours.isMultiple(of: 24) {
            let days = hours / 24
            return days == 1 ? "24h" : "\(days)d"
        }
        if hours <= 6 {
            return "\(hours)h sprint"
        }
        return "\(hours)h"
    }
}

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

    static let dayHeader: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    static let fullDay: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }

    static func timeString(from date: Date) -> String {
        utcTime.string(from: date)
    }

    static func dayHeaderString(from date: Date) -> String {
        dayHeader.string(from: date)
    }

    static func fullDayString(from date: Date) -> String {
        fullDay.string(from: date)
    }

    static func hourLabel(_ hour: Int) -> String {
        String(format: "%02dZ", hour)
    }
}

// MARK: - WeekTimelineView

/// Week view showing 7 day columns with contest event blocks.
struct WeekTimelineView: View {
    // MARK: Internal

    @Binding var referenceDate: Date

    let contests: [CalendarContest]
    let onSelect: (CalendarContest) -> Void

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
        CalendarFormatters.utcCalendar
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
            .buttonStyle(.borderless)
            Spacer()
            Text(weekRangeLabel)
                .font(.headline)
            Spacer()
            Button { adjustWeek(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var weekContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let isToday = cal.isDateInToday(day)
                    Text(CalendarFormatters.dayHeaderString(from: day))
                        .font(.caption.weight(isToday ? .bold : .medium))
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
        return VStack(spacing: 3) {
            ForEach(items) { contest in
                Button { onSelect(contest) } label: {
                    WeekEventBlock(contest: contest)
                }
                .buttonStyle(.plain)
            }
            if items.isEmpty {
                Color.clear.frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func contestsOn(_ day: Date) -> [CalendarContest] {
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
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

    let contest: CalendarContest

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(contest.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(CalendarFormatters.timeString(from: contest.startDate))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(contest.durationLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(blockColor, in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: Private

    private var blockColor: Color {
        contest.isActive ? .green.opacity(0.2) : .blue.opacity(0.15)
    }
}
