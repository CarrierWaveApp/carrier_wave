import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ContestCalendarView

/// Full-screen calendar browser for upcoming and active contests with
/// traditional month, week, and day views showing contests as event blocks.
///
/// Dual-mode:
/// - **Browse mode** (default, `onSelectDefinition == nil`): tap a catalog row
///   to push `ContestDetailView`; tap a calendar event to open
///   `ContestDetailSheet`.
/// - **Picker mode** (`onSelectDefinition` is set): the screen is presented
///   inside a sheet from session-start / QSO-edit flows. Catalog rows become
///   tap-to-select buttons that invoke the callback with the loaded
///   `ContestDefinition`; calendar events still open `ContestDetailSheet` for
///   info (selection from calendar deferred to a follow-up). A Cancel toolbar
///   item is added in picker mode.
struct ContestCalendarView: View {
    // MARK: Internal

    var contestService: ContestPollingService = .shared

    /// When set, the view is in **picker mode**. Catalog rows invoke this
    /// callback instead of pushing to `ContestDetailView`; the parent sheet
    /// is responsible for dismissal. See type-level docs.
    var onSelectDefinition: ((ContestDefinition) -> Void)?

    @State var refresher = ContestDefinitionsRefresher()
    @State var searchText = ""

    @State var pickerLoadingID: String?
    @State var showLoadError = false
    @State var loadErrorMessage: String?
    @Environment(\.dismiss) var dismiss

    /// True when this view is acting as a picker (callback set). Used by
    /// `+Catalog` to branch row rendering and by the toolbar to add Cancel.
    var isPickerMode: Bool {
        onSelectDefinition != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            picker
            if mode != .list {
                Divider()
            }
            content
        }
        .navigationTitle("Contests")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search contests")
        .toolbar { toolbar }
        .sheet(item: $selectedContest) { contest in
            ContestDetailSheet(contest: contest)
        }
        .alert("Could not load contest", isPresented: $showLoadError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(loadErrorMessage ?? "The contest definition could not be downloaded.")
        })
        .task {
            await refresher.refreshIfStale()
        }
    }

    // MARK: Private

    private enum Mode: String, CaseIterable, Identifiable {
        case month
        case week
        case day
        case list

        // MARK: Internal

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .list: "Catalog"
            default: rawValue.capitalized
            }
        }
    }

    @AppStorage("contestCalendarUseUTC") private var useUTC = true
    @AppStorage("contestCalendarMode") private var mode: Mode = .month
    @State private var visibleDate = Date()
    @State private var selectedContest: Contest?

    private var allContests: [Contest] {
        let rssContests = contestService.activeContests + contestService.upcomingContests
        let definitionContests = Self.contestsFromDefinitions(
            refresher.definitions, around: visibleDate
        )
        let merged = Self.mergeContests(
            rss: rssContests, definitions: definitionContests
        )
        return merged.sorted { $0.startDate < $1.startDate }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isPickerMode {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if mode != .list {
                    Button {
                        visibleDate = Date()
                    } label: {
                        Text("Today").font(.caption.weight(.semibold))
                    }
                }
                if refresher.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var filteredCalendarContests: [Contest] {
        guard !searchText.isEmpty else {
            return allContests
        }
        let query = searchText.lowercased()
        return allContests.filter { $0.title.lowercased().contains(query) }
    }

    private var picker: some View {
        Picker("View", selection: $mode) {
            ForEach(Mode.allCases) { md in
                Text(md.label).tag(md)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .month:
            MonthGrid(
                month: $visibleDate,
                contests: filteredCalendarContests,
                onSelect: { selectedContest = $0 }
            )
        case .week:
            WeekTimelineView(
                referenceDate: $visibleDate,
                contests: filteredCalendarContests,
                useUTC: useUTC,
                onSelect: { selectedContest = $0 }
            )
        case .day:
            DayTimelineView(
                referenceDate: $visibleDate,
                contests: filteredCalendarContests,
                useUTC: useUTC,
                onSelect: { selectedContest = $0 }
            )
        case .list:
            catalogList
        }
    }

    // catalogList, sortedEntries, filteredEntries, liveEntries,
    // catalogRow are in ContestCalendarView+Catalog.swift

    /// Convert downloaded contest definitions into `Contest` objects using
    /// their schedule to compute concrete occurrences around a reference date.
    private static func contestsFromDefinitions(
        _ definitions: [ContestDefinition],
        around referenceDate: Date
    ) -> [Contest] {
        definitions.flatMap { definition in
            ContestScheduleEvaluator.occurrences(
                schedule: definition.schedule,
                around: referenceDate
            ).map { occurrence in
                Contest(
                    id: "\(definition.id)-\(Int(occurrence.start.timeIntervalSince1970))",
                    title: definition.displayName,
                    link: nil,
                    startDate: occurrence.start,
                    endDate: occurrence.end,
                    enrichment: ContestEnrichment(
                        modes: definition.modes,
                        bands: definition.bands,
                        matchedTemplateId: definition.id
                    )
                )
            }
        }
    }

    /// Merge RSS and definition-derived contests, removing duplicates.
    private static func mergeContests(
        rss: [Contest],
        definitions: [Contest]
    ) -> [Contest] {
        var result = rss
        for defContest in definitions {
            let isDuplicate = rss.contains { rssContest in
                startsNear(rssContest, defContest)
                    && titlesMatch(rssContest.title, defContest.title)
            }
            if !isDuplicate {
                result.append(defContest)
            }
        }
        return result
    }

    private static func startsNear(_ lhs: Contest, _ rhs: Contest) -> Bool {
        abs(lhs.startDate.timeIntervalSince(rhs.startDate)) < 6 * 3_600
    }

    private static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.lowercased()
        let right = rhs.lowercased()
        return left.contains(right) || right.contains(left)
    }
}

// MARK: - MonthGrid

private struct MonthGrid: View {
    // MARK: Internal

    @Binding var month: Date

    let contests: [Contest]
    let onSelect: (Contest) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                monthHeader
                    .padding(.bottom, 12)
                weekdayRow
                    .padding(.bottom, 4)
                daysGrid
                    .padding(.bottom, 16)
                selectedDayList
            }
            .padding(.horizontal)
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
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
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
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var monthHeader: some View {
        HStack {
            Button { adjustMonth(-1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(Self.monthFormatter.string(from: monthStart))
                .font(.headline)
            Spacer()
            Button { adjustMonth(1) } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4), count: 7
        )
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0 ..< leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 40)
            }
            ForEach(daysInMonth, id: \.self) { day in
                DayCell(
                    day: day,
                    contests: contestsOn(day),
                    isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
                    onTap: { selectedDay = day }
                )
            }
        }
    }

    @ViewBuilder
    private var selectedDayList: some View {
        if let selectedDay {
            let items = contestsOn(selectedDay)
            VStack(alignment: .leading, spacing: 8) {
                Text(dayLabel(selectedDay))
                    .font(.subheadline.weight(.semibold))
                if items.isEmpty {
                    Text("No contests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { contest in
                            Button { onSelect(contest) } label: {
                                ContestRowContent(
                                    contest: contest,
                                    isActive: contest.isActive,
                                    showTimes: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.top, 8)
        }
    }

    private func contestsOn(_ day: Date) -> [Contest] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(
            byAdding: .day, value: 1, to: dayStart
        ) else {
            return []
        }
        return contests.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
    }

    private func adjustMonth(_ delta: Int) {
        if let next = calendar.date(
            byAdding: .month, value: delta, to: monthStart
        ) {
            month = next
            selectedDay = nil
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: day)
    }
}

// MARK: - DayCell

private struct DayCell: View {
    // MARK: Internal

    let day: Date
    let contests: [Contest]
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text(dayText)
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : .primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isToday ? Color.blue : Color.clear))
                markers
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }

    /// Compare the UTC day against the current UTC day, not local time.
    private var isToday: Bool {
        Self.utcCalendar.isDateInToday(day)
    }

    private var dayText: String {
        "\(Self.utcCalendar.component(.day, from: day))"
    }

    @ViewBuilder
    private var markers: some View {
        if contests.isEmpty {
            Spacer().frame(height: 6)
        } else {
            HStack(spacing: 3) {
                ForEach(contests.prefix(3)) { contest in
                    Circle()
                        .fill(markerColor(for: contest))
                        .frame(width: 5, height: 5)
                }
                if contests.count > 3 {
                    Text("+\(contests.count - 3)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 6)
        }
    }

    private func markerColor(for contest: Contest) -> Color {
        if contest.isActive {
            return .green
        }
        switch contest.enrichment.popularity ?? 1 {
        case 5: return .red
        case 4: return .orange
        case 3: return .yellow
        default: return .blue
        }
    }
}
