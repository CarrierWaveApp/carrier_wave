import CarrierWaveData
import SwiftUI

// MARK: - ContestCalendarView

/// Calendar browser for contest occurrences with month, week, and day
/// views. Selecting a contest in any view calls `onSelectEntry` with
/// the entry ID so the parent can show the detail pane.
struct ContestCalendarView: View {
    // MARK: Internal

    let entries: [ContestBrowserEntry]
    var onSelectEntry: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: Private

    private enum Mode: String, CaseIterable, Identifiable {
        case month
        case week
        case day

        // MARK: Internal

        var id: String {
            rawValue
        }

        var label: String {
            rawValue.capitalized
        }
    }

    @State private var mode: Mode = .month
    @State private var visibleDate = Date()

    private var calendarContests: [CalendarContest] {
        entries.flatMap { entry -> [CalendarContest] in
            guard let definition = entry.definition else {
                return []
            }
            let occs = ContestScheduleEvaluator.occurrences(
                schedule: definition.schedule,
                around: visibleDate
            )
            return occs.map { occ in
                CalendarContest(
                    id: "\(entry.id)-\(Int(occ.start.timeIntervalSince1970))",
                    title: entry.displayName,
                    startDate: occ.start,
                    endDate: occ.end,
                    modes: definition.modes,
                    bands: definition.bands,
                    entryID: entry.id
                )
            }
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private var header: some View {
        HStack {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            Button("Today") {
                visibleDate = Date()
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .month:
            MonthGrid(
                month: $visibleDate,
                contests: calendarContests,
                onSelect: { onSelectEntry?($0.entryID) }
            )
        case .week:
            WeekTimelineView(
                referenceDate: $visibleDate,
                contests: calendarContests,
                onSelect: { onSelectEntry?($0.entryID) }
            )
        case .day:
            DayTimelineView(
                referenceDate: $visibleDate,
                contests: calendarContests,
                onSelect: { onSelectEntry?($0.entryID) }
            )
        }
    }
}

// MARK: - MonthGrid

private struct MonthGrid: View {
    // MARK: Internal

    @Binding var month: Date

    let contests: [CalendarContest]
    let onSelect: (CalendarContest) -> Void

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    weekdayRow
                        .padding(.horizontal)
                        .padding(.top, 8)
                    daysGrid
                        .padding(.horizontal)
                        .padding(.top, 4)
                    Divider()
                        .padding(.top, 12)
                    selectedDayDetail
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: Private

    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    @State private var selectedDay: Date?

    private var calendar: Calendar {
        CalendarFormatters.utcCalendar
    }

    private var monthStart: Date {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: month)
        ) ?? month
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart)
        else {
            return []
        }
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }

    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var monthHeader: some View {
        HStack {
            Button { adjustMonth(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(Self.monthFormatter.string(from: monthStart))
                .font(.headline)
            Spacer()
            Button { adjustMonth(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0 ..< leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 56)
            }
            ForEach(daysInMonth, id: \.self) { day in
                let dayContests = contestsOn(day)
                CalendarDayCell(
                    day: day,
                    contests: dayContests,
                    isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
                    isToday: calendar.isDateInToday(day),
                    onTap: { selectedDay = day }
                )
            }
        }
    }

    @ViewBuilder
    private var selectedDayDetail: some View {
        if let selectedDay {
            let items = contestsOn(selectedDay)
            VStack(alignment: .leading, spacing: 8) {
                Text(dayLabel(selectedDay))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal)

                if items.isEmpty {
                    Text("No contests on this day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                } else {
                    VStack(spacing: 4) {
                        ForEach(items) { contest in
                            Button { onSelect(contest) } label: {
                                CalendarContestRow(contest: contest)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        } else {
            Text("Select a day to see contests")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding()
        }
    }

    private func contestsOn(_ day: Date) -> [CalendarContest] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        return contests.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
    }

    private func adjustMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthStart) {
            month = next
            selectedDay = nil
        }
    }

    private func dayLabel(_ day: Date) -> String {
        CalendarFormatters.fullDayString(from: day)
    }
}

// MARK: - CalendarDayCell

private struct CalendarDayCell: View {
    let day: Date
    let contests: [CalendarContest]
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(CalendarFormatters.utcCalendar.component(.day, from: day))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : .primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isToday ? Color.blue : Color.clear))

                if contests.isEmpty {
                    Spacer().frame(height: 8)
                } else {
                    HStack(spacing: 3) {
                        ForEach(contests.prefix(3)) { contest in
                            Circle()
                                .fill(contest.isActive ? .green : .blue)
                                .frame(width: 5, height: 5)
                        }
                        if contests.count > 3 {
                            Text("+\(contests.count - 3)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CalendarContestRow

private struct CalendarContestRow: View {
    // MARK: Internal

    let contest: CalendarContest

    var body: some View {
        HStack(spacing: 8) {
            if contest.isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contest.title)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(timeRange)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if !contest.modes.isEmpty {
                        ContestModeChips(modes: contest.modes)
                    }
                }
            }
            Spacer()
            Text(contest.durationLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Private

    private var timeRange: String {
        let start = CalendarFormatters.timeString(from: contest.startDate)
        let end = CalendarFormatters.timeString(from: contest.endDate)
        return "\(start)–\(end)"
    }
}
