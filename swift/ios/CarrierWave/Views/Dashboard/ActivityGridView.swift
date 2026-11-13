import CarrierWaveData
import SwiftUI

// MARK: - ActivityGrid

struct ActivityGrid: View {
    // MARK: Internal

    let activationData: [Date: Int]?
    let activityLogData: [Date: Int]?
    /// Another Morse Trainer practice per day (grid-keyed), `nil` when the user
    /// hasn't connected AMT — the legend swatch only appears when connected.
    var amtData: [Date: AMTDayActivity]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActivityGridContent(
                activationData: activationData ?? [:],
                activityLogData: activityLogData ?? [:],
                amtData: amtData ?? [:]
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Activity grid showing QSO history")
            .opacity(isLoading ? 0.5 : 1.0)

            activityGridLegend
        }
    }

    // MARK: Private

    private var isLoading: Bool {
        activationData == nil && activityLogData == nil
    }

    private var activityGridLegend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ActivityGridColors.activation)
                    .frame(width: 10, height: 10)
                Text("Activation")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ActivityGridColors.activityLog)
                    .frame(width: 10, height: 10)
                Text("Hunter")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if amtData != nil {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ActivityGridColors.amtPractice)
                        .frame(width: 10, height: 10)
                    Text("Morse practice")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - ActivityGridContent

/// Internal view that calculates and reports its ideal size.
/// Horizontally scrollable to show full QSO history back to oldest QSO.
private struct ActivityGridContent: View {
    // MARK: Internal

    let activationData: [Date: Int]
    let activityLogData: [Date: Int]
    let amtData: [Date: AMTDayActivity]

    var body: some View {
        // Precompute expensive derived values once per body evaluation
        let combined = computeCombinedData()
        let maxVal = combined.values.max() ?? 1
        let oldestKey = [combined.keys.min(), amtData.keys.min()].compactMap { $0 }.min()
        let columns = computeTotalColumns(oldestKey: oldestKey)
        let labels = computeLabelPositions(totalColumns: columns)

        ScrollViewReader { _ in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gridToLabelSpacing) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0 ..< columns, id: \.self) { column in
                            VStack(spacing: spacing) {
                                ForEach(0 ..< rows, id: \.self) { row in
                                    let date = dateFor(
                                        column: column, row: row, totalColumns: columns
                                    )
                                    let actCount = countFor(date: date, in: activationData)
                                    let logCount = countFor(date: date, in: activityLogData)
                                    let amt = amtFor(date: date)
                                    let total = actCount + logCount

                                    if isFutureDate(date) {
                                        Color.clear
                                            .frame(width: cellSize, height: cellSize)
                                    } else {
                                        NavigationLink(value: DaySummaryDestination(date: date)) {
                                            ActivityGridCell(
                                                activationCount: actCount,
                                                activityLogCount: logCount,
                                                amt: amt,
                                                maxCount: maxVal
                                            )
                                            .frame(width: cellSize, height: cellSize)
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            accessibilityLabel(
                                                date: date, activation: actCount,
                                                activityLog: logCount, total: total,
                                                amt: amt
                                            )
                                        )
                                        .accessibilityHint("Open day summary")
                                        .contextMenu {
                                            // intentionally empty — preview only
                                        } preview: {
                                            popoverContent(
                                                date: date, activation: actCount,
                                                activityLog: logCount, total: total,
                                                amt: amt
                                            )
                                            .padding()
                                            .frame(width: 220)
                                        }
                                    }
                                }
                            }
                            .id(column)
                        }
                    }
                    .frame(height: gridHeight)

                    ZStack(alignment: .topLeading) {
                        ForEach(labels, id: \.column) { item in
                            Text(item.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .offset(x: CGFloat(item.column) * columnWidth)
                        }
                    }
                    .frame(
                        width: CGFloat(columns) * columnWidth - spacing,
                        height: monthLabelHeight,
                        alignment: .topLeading
                    )
                }
                .padding(.trailing, 4)
            }
            .defaultScrollAnchor(.trailing)
        }
        .frame(height: calculatedHeight)
    }

    // MARK: Private

    private static let monthOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM ''yy"
        return formatter
    }()

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let rows = 7
    private let spacing: CGFloat = 2
    private let cellSize: CGFloat = 14
    private let monthLabelHeight: CGFloat = 14
    private let gridToLabelSpacing: CGFloat = 4

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private var minColumns: Int {
        if verticalSizeClass == .compact || horizontalSizeClass == .regular {
            return 52
        }
        return 26
    }

    private var columnWidth: CGFloat {
        cellSize + spacing
    }

    private var gridHeight: CGFloat {
        CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
    }

    private var calculatedHeight: CGFloat {
        gridHeight + gridToLabelSpacing + monthLabelHeight
    }

    private func popoverContent(
        date: Date, activation: Int, activityLog: Int, total: Int, amt: AMTDayActivity?
    ) -> some View {
        VStack(spacing: 4) {
            Text(Self.tooltipDateFormatter.string(from: date))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(total) QSO\(total == 1 ? "" : "s")")
                .font(.headline)
            if let amt {
                Label("\(amt.durationText) Morse practice", systemImage: "graduationcap.fill")
                    .font(.caption)
                    .foregroundStyle(ActivityGridColors.amtPractice)
            }
            if activation > 0 || activityLog > 0 {
                HStack(spacing: 8) {
                    if activation > 0 {
                        Label("\(activation)", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(ActivityGridColors.activation)
                    }
                    if activityLog > 0 {
                        Label("\(activityLog)", systemImage: "scope")
                            .font(.caption)
                            .foregroundStyle(ActivityGridColors.activityLog)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .presentationCompactAdaptation(.popover)
    }

    private func computeCombinedData() -> [Date: Int] {
        var combined: [Date: Int] = [:]
        for (date, count) in activationData {
            combined[date, default: 0] += count
        }
        for (date, count) in activityLogData {
            combined[date, default: 0] += count
        }
        return combined
    }

    private func computeTotalColumns(oldestKey: Date?) -> Int {
        let today = calendar.startOfDay(for: Date())

        let oldestDate: Date
        if let minDate = oldestKey {
            let weekday = calendar.component(.weekday, from: minDate)
            oldestDate =
                calendar.date(byAdding: .day, value: -(weekday - 1), to: minDate) ?? minDate
        } else {
            oldestDate =
                calendar.date(byAdding: .weekOfYear, value: -minColumns, to: today) ?? today
        }

        let weeks =
            calendar.dateComponents([.weekOfYear], from: oldestDate, to: today).weekOfYear ?? 0
        return max(weeks + 1, minColumns)
    }

    private func computeLabelPositions(totalColumns: Int) -> [(column: Int, label: String)] {
        var labels: [(Int, String)] = []
        var lastMonth = -1

        for column in 0 ..< totalColumns {
            let date = dateFor(column: column, row: 0, totalColumns: totalColumns)
            let month = calendar.component(.month, from: date)

            if month != lastMonth {
                let label = month == 1
                    ? Self.monthYearFormatter.string(from: date)
                    : Self.monthOnlyFormatter.string(from: date)
                labels.append((column, label))
                lastMonth = month
            }
        }
        return labels
    }

    private func dateFor(column: Int, row: Int, totalColumns: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let weeksBack = totalColumns - 1 - column
        let daysBack = weeksBack * 7 + (todayWeekday - 1 - row)
        return calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }

    private func isFutureDate(_ date: Date) -> Bool {
        date > calendar.startOfDay(for: Date())
    }

    private func countFor(date: Date, in data: [Date: Int]) -> Int {
        data[date] ?? data[calendar.startOfDay(for: date)] ?? 0
    }

    private func amtFor(date: Date) -> AMTDayActivity? {
        guard !amtData.isEmpty else {
            return nil
        }
        return amtData[date] ?? amtData[calendar.startOfDay(for: date)]
    }

    private func accessibilityLabel(
        date: Date, activation: Int, activityLog: Int, total: Int, amt: AMTDayActivity?
    ) -> String {
        var parts = [Self.tooltipDateFormatter.string(from: date) + ":"]
        parts.append("\(total) QSO\(total == 1 ? "" : "s")")
        if activation > 0, activityLog > 0 {
            parts.append("(\(activation) activation, \(activityLog) hunter)")
        }
        if let amt {
            parts.append("\(amt.durationText) Morse practice")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - DaySummaryDestination

/// Hashable value used by the upstream `NavigationStack` to push
/// `DaySummaryView(date:)` when a grid cell is tapped.
struct DaySummaryDestination: Hashable {
    let date: Date
}
