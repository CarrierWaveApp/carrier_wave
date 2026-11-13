import CarrierWaveData
import SwiftUI

// MARK: - ActivityGridMac

/// GitHub-style activity grid for the CW Sweep Dashboard, mirroring Field's
/// `ActivityGrid`: 7 weekday rows × one column per week, UTC day buckets,
/// green activation / blue hunter cells (diagonal split when both), purple
/// Another Morse Trainer practice days layered on, month labels and a legend.
/// Scrolls horizontally back to the oldest data; hover a cell for its summary.
struct ActivityGridMac: View {
    // MARK: Internal

    /// Activation (session) QSOs per UTC day; `nil` while loading.
    let activationData: [Date: Int]?
    /// Hunter / non-session QSOs per UTC day; `nil` while loading.
    let activityLogData: [Date: Int]?
    /// Another Morse Trainer practice per day, `nil` when AMT isn't connected.
    var amtData: [Date: AMTDayActivity]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActivityGridMacContent(
                activationData: activationData ?? [:],
                activityLogData: activityLogData ?? [:],
                amtData: amtData ?? [:]
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Activity grid showing QSO history")
            .opacity(isLoading ? 0.5 : 1.0)

            legend
        }
    }

    // MARK: Private

    private var isLoading: Bool {
        activationData == nil && activityLogData == nil
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendSwatch(ActivityGridColors.activation, "Activation")
            legendSwatch(ActivityGridColors.activityLog, "Hunter")
            if amtData != nil {
                legendSwatch(ActivityGridColors.amtPractice, "Morse practice")
            }
        }
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ActivityGridMacContent

private struct ActivityGridMacContent: View {
    // MARK: Internal

    let activationData: [Date: Int]
    let activityLogData: [Date: Int]
    let amtData: [Date: AMTDayActivity]

    var body: some View {
        let combined = combinedCounts()
        let maxVal = combined.values.max() ?? 1
        let oldestKey = [combined.keys.min(), amtData.keys.min()].compactMap { $0 }.min()
        let columns = totalColumns(oldestKey: oldestKey)
        let labels = labelPositions(totalColumns: columns)

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: gridToLabelSpacing) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0 ..< columns, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0 ..< rows, id: \.self) { row in
                                let date = dateFor(column: column, row: row, totalColumns: columns)
                                if isFutureDate(date) {
                                    Color.clear
                                        .frame(width: cellSize, height: cellSize)
                                } else {
                                    cell(for: date, maxCount: maxVal)
                                }
                            }
                        }
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
        .frame(height: gridHeight + gridToLabelSpacing + monthLabelHeight)
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

    private let rows = 7
    private let spacing: CGFloat = 2
    private let cellSize: CGFloat = 14
    private let monthLabelHeight: CGFloat = 14
    private let gridToLabelSpacing: CGFloat = 4
    /// A Mac window is wide enough for a full year.
    private let minColumns = 52

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private var columnWidth: CGFloat {
        cellSize + spacing
    }

    private var gridHeight: CGFloat {
        CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
    }

    private func cell(for date: Date, maxCount: Int) -> some View {
        let actCount = count(for: date, in: activationData)
        let logCount = count(for: date, in: activityLogData)
        let amt = amtData[date] ?? amtData[calendar.startOfDay(for: date)]
        let summary = summary(date: date, activation: actCount, activityLog: logCount, amt: amt)
        return ActivityGridCell(
            activationCount: actCount,
            activityLogCount: logCount,
            amt: amt,
            maxCount: maxCount
        )
        .frame(width: cellSize, height: cellSize)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .help(summary)
        .accessibilityLabel(summary)
    }

    private func combinedCounts() -> [Date: Int] {
        var combined: [Date: Int] = [:]
        for (date, count) in activationData {
            combined[date, default: 0] += count
        }
        for (date, count) in activityLogData {
            combined[date, default: 0] += count
        }
        return combined
    }

    private func totalColumns(oldestKey: Date?) -> Int {
        let today = calendar.startOfDay(for: Date())
        let oldestDate: Date
        if let minDate = oldestKey {
            let weekday = calendar.component(.weekday, from: minDate)
            oldestDate = calendar.date(byAdding: .day, value: -(weekday - 1), to: minDate) ?? minDate
        } else {
            oldestDate = calendar.date(byAdding: .weekOfYear, value: -minColumns, to: today) ?? today
        }
        let weeks = calendar.dateComponents([.weekOfYear], from: oldestDate, to: today).weekOfYear ?? 0
        return max(weeks + 1, minColumns)
    }

    private func labelPositions(totalColumns: Int) -> [(column: Int, label: String)] {
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

    private func count(for date: Date, in data: [Date: Int]) -> Int {
        data[date] ?? data[calendar.startOfDay(for: date)] ?? 0
    }

    private func summary(date: Date, activation: Int, activityLog: Int, amt: AMTDayActivity?) -> String {
        let total = activation + activityLog
        var parts = ["\(Self.tooltipDateFormatter.string(from: date)): \(total) QSO\(total == 1 ? "" : "s")"]
        if activation > 0, activityLog > 0 {
            parts.append("(\(activation) activation, \(activityLog) hunter)")
        }
        if let amt {
            parts.append("· \(amt.durationText) Morse practice")
        }
        return parts.joined(separator: " ")
    }
}
