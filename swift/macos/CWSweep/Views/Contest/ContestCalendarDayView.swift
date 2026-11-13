import SwiftUI

// MARK: - DayTimelineView

/// Day view with a 24-hour timeline and contest event blocks
/// positioned by start/end time. Shows hint bars for contests
/// extending beyond the visible day boundaries.
struct DayTimelineView: View {
    // MARK: Internal

    @Binding var referenceDate: Date

    let contests: [CalendarContest]
    let onSelect: (CalendarContest) -> Void

    var body: some View {
        VStack(spacing: 0) {
            dayNav
            Divider()
            aboveHint
            ScrollViewReader { proxy in
                ScrollView {
                    dayTimeline
                        .id("timeline")
                        .onGeometryChange(for: CGFloat.self) { geo in
                            geo.frame(in: .named("dayScroll")).minY
                        } action: { newVal in
                            scrollOffset = newVal
                        }
                }
                .coordinateSpace(name: "dayScroll")
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.height
                } action: { newVal in
                    viewportHeight = newVal
                }
                .onAppear {
                    proxy.scrollTo(scrollAnchorHour, anchor: .top)
                }
            }
            belowHint
        }
    }

    // MARK: Private

    private struct EventFrame {
        var offset: CGFloat
        var height: CGFloat
    }

    private struct ColumnAssignment {
        var index: Int
        var total: Int
    }

    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 600

    private let hourHeight: CGFloat = 60

    private var cal: Calendar {
        CalendarFormatters.utcCalendar
    }

    private var dayStart: Date {
        cal.startOfDay(for: referenceDate)
    }

    private var dayEnd: Date {
        cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    private var dayContests: [CalendarContest] {
        contests.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
    }

    private var visibleTop: CGFloat {
        -scrollOffset
    }

    private var visibleBottom: CGFloat {
        visibleTop + viewportHeight
    }

    private var contestsAbove: [CalendarContest] {
        dayContests.filter { contest in
            let frame = eventFrame(contest: contest, hourHeight: hourHeight)
            return (frame.offset + frame.height) < visibleTop
        }
    }

    private var contestsBelow: [CalendarContest] {
        dayContests.filter { contest in
            let frame = eventFrame(contest: contest, hourHeight: hourHeight)
            return frame.offset > visibleBottom
        }
    }

    private var scrollAnchorHour: Int {
        let hour = cal.component(.hour, from: Date())
        return max(0, hour - 1)
    }

    private var dayNav: some View {
        HStack {
            Button { adjustDay(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
            VStack(spacing: 2) {
                Text(CalendarFormatters.fullDayString(from: dayStart))
                    .font(.headline)
                HStack(spacing: 6) {
                    if cal.isDateInToday(dayStart) {
                        Text("Today")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    Text("UTC")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button { adjustDay(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var aboveHint: some View {
        if !contestsAbove.isEmpty {
            let count = contestsAbove.count
            let names = contestsAbove.prefix(2).map(\.title).joined(separator: ", ")
            let label = count > 2 ? "\(names) +\(count - 2) more" : names
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.background.secondary)
        }
    }

    @ViewBuilder
    private var belowHint: some View {
        if !contestsBelow.isEmpty {
            let count = contestsBelow.count
            let names = contestsBelow.prefix(2).map(\.title).joined(separator: ", ")
            let label = count > 2 ? "\(names) +\(count - 2) more" : names
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.background.secondary)
        }
    }

    private var dayTimeline: some View {
        let totalHeight = hourHeight * 24
        let columns = assignColumns(dayContests)
        let leadingPad: CGFloat = 42
        let trailingPad: CGFloat = 8

        return GeometryReader { geo in
            let eventWidth = geo.size.width - leadingPad - trailingPad
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0 ..< 24, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 4) {
                            Text(CalendarFormatters.hourLabel(hour))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                            VStack {
                                Divider()
                                Spacer()
                            }
                        }
                        .frame(height: hourHeight)
                        .id(hour)
                    }
                }

                ForEach(dayContests) { contest in
                    let frame = eventFrame(contest: contest, hourHeight: hourHeight)
                    let col = columns[contest.id] ?? ColumnAssignment(index: 0, total: 1)
                    let colWidth = eventWidth / CGFloat(col.total)
                    let colOffset = leadingPad + colWidth * CGFloat(col.index)

                    Button { onSelect(contest) } label: {
                        DayEventBlock(contest: contest)
                    }
                    .buttonStyle(.plain)
                    .frame(width: colWidth - 2, height: max(frame.height, 32))
                    .offset(x: colOffset, y: frame.offset)
                }

                if cal.isDateInToday(dayStart) {
                    let nowOffset = currentTimeOffset(hourHeight: hourHeight)
                    HStack(spacing: 0) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Rectangle().fill(.red).frame(height: 1)
                    }
                    .padding(.leading, 34)
                    .offset(y: nowOffset - 4)
                }
            }
        }
        .frame(height: totalHeight)
        .padding(.vertical, 4)
    }

    private func assignColumns(_ contests: [CalendarContest]) -> [String: ColumnAssignment] {
        guard !contests.isEmpty else {
            return [:]
        }
        let sorted = contests.sorted { $0.startDate < $1.startDate }
        var clusters: [[(contest: CalendarContest, col: Int)]] = []
        for contest in sorted {
            var placed = false
            for ci in clusters.indices {
                let clusterEnd = clusters[ci].map(\.contest.endDate).max() ?? .distantPast
                if contest.startDate < clusterEnd {
                    let usedCols = Set(clusters[ci].map(\.col))
                    var col = 0
                    while usedCols.contains(col) {
                        col += 1
                    }
                    clusters[ci].append((contest, col))
                    placed = true
                    break
                }
            }
            if !placed {
                clusters.append([(contest, 0)])
            }
        }
        var result: [String: ColumnAssignment] = [:]
        for cluster in clusters {
            let total = (cluster.map(\.col).max() ?? 0) + 1
            for item in cluster {
                result[item.contest.id] = ColumnAssignment(index: item.col, total: total)
            }
        }
        return result
    }

    private func eventFrame(contest: CalendarContest, hourHeight: CGFloat) -> EventFrame {
        let startSeconds = contest.startDate.timeIntervalSince(dayStart)
        let endSeconds = contest.endDate.timeIntervalSince(dayStart)
        let clampedStart = max(0, startSeconds)
        let clampedEnd = min(24 * 3_600, endSeconds)
        let offset = CGFloat(clampedStart / 3_600) * hourHeight
        let height = CGFloat((clampedEnd - clampedStart) / 3_600) * hourHeight
        return EventFrame(offset: offset, height: height)
    }

    private func currentTimeOffset(hourHeight: CGFloat) -> CGFloat {
        let now = Date()
        let seconds = now.timeIntervalSince(dayStart)
        return CGFloat(seconds / 3_600) * hourHeight
    }

    private func adjustDay(_ delta: Int) {
        if let next = cal.date(byAdding: .day, value: delta, to: referenceDate) {
            referenceDate = next
        }
    }
}

// MARK: - DayEventBlock

/// Event block for the day timeline — title, time range, and mode labels.
private struct DayEventBlock: View {
    // MARK: Internal

    let contest: CalendarContest

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(contest.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(timeRange)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if !contest.modes.isEmpty {
                        Text(contest.modes.joined(separator: " / "))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(accentColor)
                    }
                    Text(contest.durationLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 6)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Private

    private var timeRange: String {
        let start = CalendarFormatters.timeString(from: contest.startDate)
        let end = CalendarFormatters.timeString(from: contest.endDate)
        return "\(start)–\(end)"
    }

    private var accentColor: Color {
        contest.isActive ? .green : .blue
    }
}
