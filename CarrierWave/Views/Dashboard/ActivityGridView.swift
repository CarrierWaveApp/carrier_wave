import CarrierWaveData
import SwiftUI

// MARK: - ActivityGridColors

enum ActivityGridColors {
    /// Green for activations (POTA sessions) — matches original grid color
    static let activation = Color.green
    /// Blue for activity log (hunter/casual) — system color, adapts to dark mode
    static let activityLog = Color.blue
    /// Empty cell
    static let empty = Color(.systemGray5)
}

// MARK: - ActivityGrid

struct ActivityGrid: View {
    // MARK: Internal

    let activationData: [Date: Int]?
    let activityLogData: [Date: Int]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActivityGridContent(
                activationData: activationData ?? [:],
                activityLogData: activityLogData ?? [:],
                selectedDate: $selectedDate
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Activity grid showing QSO history")
            .opacity(isLoading ? 0.5 : 1.0)

            activityGridLegend
        }
    }

    // MARK: Private

    @State private var selectedDate: Date?

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
                Text("Hunter Log")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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

    @Binding var selectedDate: Date?

    var body: some View {
        // Precompute expensive derived values once per body evaluation
        let combined = computeCombinedData()
        let maxVal = combined.values.max() ?? 1
        let columns = computeTotalColumns(from: combined)
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
                                    let total = actCount + logCount

                                    if isFutureDate(date) {
                                        Color.clear
                                            .frame(width: cellSize, height: cellSize)
                                    } else {
                                        cellView(
                                            activationCount: actCount,
                                            activityLogCount: logCount,
                                            maxCount: maxVal
                                        )
                                        .frame(width: cellSize, height: cellSize)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .contentShape(Rectangle())
                                        .accessibilityLabel(
                                            accessibilityLabel(
                                                date: date, activation: actCount,
                                                activityLog: logCount, total: total
                                            )
                                        )
                                        .accessibilityHint("Tap to show details")
                                        .onTapGesture {
                                            if selectedDate == date {
                                                selectedDate = nil
                                            } else {
                                                selectedDate = date
                                            }
                                        }
                                        .popover(
                                            isPresented: Binding(
                                                get: { selectedDate == date },
                                                set: {
                                                    if !$0 {
                                                        selectedDate = nil
                                                    }
                                                }
                                            ),
                                            arrowEdge: .top
                                        ) {
                                            popoverContent(
                                                date: date, activation: actCount,
                                                activityLog: logCount, total: total
                                            )
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

    private let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
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

    @ViewBuilder
    private func cellView(
        activationCount: Int, activityLogCount: Int, maxCount: Int
    ) -> some View {
        if activationCount == 0, activityLogCount == 0 {
            RoundedRectangle(cornerRadius: 2)
                .fill(ActivityGridColors.empty)
        } else if activationCount > 0, activityLogCount > 0 {
            // Diagonal split: activation top-left, activity log bottom-right
            Canvas { context, size in
                var topLeft = Path()
                topLeft.move(to: .zero)
                topLeft.addLine(to: CGPoint(x: size.width, y: 0))
                topLeft.addLine(to: CGPoint(x: 0, y: size.height))
                topLeft.closeSubpath()
                context.fill(
                    topLeft,
                    with: .color(
                        ActivityGridColors.activation
                            .opacity(intensityFor(count: activationCount, max: maxCount))
                    )
                )

                var bottomRight = Path()
                bottomRight.move(to: CGPoint(x: size.width, y: 0))
                bottomRight.addLine(to: CGPoint(x: size.width, y: size.height))
                bottomRight.addLine(to: CGPoint(x: 0, y: size.height))
                bottomRight.closeSubpath()
                context.fill(
                    bottomRight,
                    with: .color(
                        ActivityGridColors.activityLog
                            .opacity(intensityFor(count: activityLogCount, max: maxCount))
                    )
                )
            }
        } else if activationCount > 0 {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    ActivityGridColors.activation
                        .opacity(intensityFor(count: activationCount, max: maxCount))
                )
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    ActivityGridColors.activityLog
                        .opacity(intensityFor(count: activityLogCount, max: maxCount))
                )
        }
    }

    private func popoverContent(
        date: Date, activation: Int, activityLog: Int, total: Int
    ) -> some View {
        VStack(spacing: 4) {
            Text(tooltipDateFormatter.string(from: date))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(total) QSO\(total == 1 ? "" : "s")")
                .font(.headline)
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

    private func computeTotalColumns(from combined: [Date: Int]) -> Int {
        let today = calendar.startOfDay(for: Date())

        let oldestDate: Date
        if let minDate = combined.keys.min() {
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
        let monthFormatter = DateFormatter()

        for column in 0 ..< totalColumns {
            let date = dateFor(column: column, row: 0, totalColumns: totalColumns)
            let month = calendar.component(.month, from: date)

            if month != lastMonth {
                if month == 1 {
                    monthFormatter.dateFormat = "MMM ''yy"
                } else {
                    monthFormatter.dateFormat = "MMM"
                }
                labels.append((column, monthFormatter.string(from: date)))
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
        if let count = data[date] {
            return count
        }
        let targetDay = calendar.startOfDay(for: date)
        for (key, value) in data where calendar.isDate(key, inSameDayAs: targetDay) {
            return value
        }
        return 0
    }

    private func intensityFor(count: Int, max maxCount: Int) -> Double {
        guard count > 0 else {
            return 0
        }
        return 0.3 + min(Double(count) / Double(max(maxCount, 1)), 1.0) * 0.7
    }

    private func accessibilityLabel(
        date: Date, activation: Int, activityLog: Int, total: Int
    ) -> String {
        var parts = [tooltipDateFormatter.string(from: date) + ":"]
        parts.append("\(total) QSO\(total == 1 ? "" : "s")")
        if activation > 0, activityLog > 0 {
            parts.append("(\(activation) activation, \(activityLog) activity log)")
        }
        return parts.joined(separator: " ")
    }
}
