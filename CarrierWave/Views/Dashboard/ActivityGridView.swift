import SwiftUI

// MARK: - ActivityGrid

struct ActivityGrid: View {
    // MARK: Internal

    let activityData: [Date: Int]?

    var body: some View {
        ActivityGridContent(activityData: activityData ?? [:], selectedDate: $selectedDate)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Activity grid showing QSO history")
            .opacity(activityData == nil ? 0.5 : 1.0)
    }

    // MARK: Private

    @State private var selectedDate: Date?
}

// MARK: - ActivityGridContent

/// Internal view that calculates and reports its ideal size.
/// Horizontally scrollable to show full QSO history back to oldest QSO.
private struct ActivityGridContent: View {
    // MARK: Internal

    let activityData: [Date: Int]

    @Binding var selectedDate: Date?

    var body: some View {
        ScrollViewReader { _ in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gridToLabelSpacing) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0 ..< totalColumns, id: \.self) { column in
                            VStack(spacing: spacing) {
                                ForEach(0 ..< rows, id: \.self) { row in
                                    let date = dateFor(column: column, row: row)
                                    let count = countFor(date: date)

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(colorFor(count: count))
                                        .frame(width: cellSize, height: cellSize)
                                        .accessibilityLabel(
                                            "\(tooltipDateFormatter.string(from: date)): "
                                                + "\(count) QSO\(count == 1 ? "" : "s")"
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
                                            VStack(spacing: 4) {
                                                Text(tooltipDateFormatter.string(from: date))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text("\(count) QSO\(count == 1 ? "" : "s")")
                                                    .font(.headline)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .presentationCompactAdaptation(.popover)
                                        }
                                }
                            }
                            .id(column)
                        }
                    }
                    .frame(height: gridHeight)

                    ZStack(alignment: .topLeading) {
                        ForEach(labelPositions, id: \.column) { item in
                            Text(item.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .offset(x: CGFloat(item.column) * columnWidth)
                        }
                    }
                    .frame(
                        width: CGFloat(totalColumns) * columnWidth - spacing,
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

    private let rows = 7
    private let spacing: CGFloat = 2
    private let cellSize: CGFloat = 14
    private let monthLabelHeight: CGFloat = 14
    private let gridToLabelSpacing: CGFloat = 4
    private let minColumns = 26

    private let calendar = Calendar.current

    private let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private var maxCount: Int {
        activityData.values.max() ?? 1
    }

    /// Calculate total columns needed to show all QSO history
    private var totalColumns: Int {
        let today = calendar.startOfDay(for: Date())

        // Find oldest date with activity, or default to minColumns weeks ago
        let oldestDate: Date
        if let minDate = activityData.keys.min() {
            // Align to start of that week
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

    private var columnWidth: CGFloat {
        cellSize + spacing
    }

    private var gridHeight: CGFloat {
        CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
    }

    private var calculatedHeight: CGFloat {
        gridHeight + gridToLabelSpacing + monthLabelHeight
    }

    /// Returns label positions for month markers.
    /// Shows year on January (e.g., "Jan '26").
    private var labelPositions: [(column: Int, label: String)] {
        var labels: [(Int, String)] = []
        var lastMonth = -1
        let monthFormatter = DateFormatter()

        for column in 0 ..< totalColumns {
            let date = dateFor(column: column, row: 0)
            let month = calendar.component(.month, from: date)

            if month != lastMonth {
                // Show year on January
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

    private func dateFor(column: Int, row: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let weeksBack = totalColumns - 1 - column
        let daysBack = weeksBack * 7 + (todayWeekday - 1 - row)
        return calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }

    /// Look up count for a date, handling potential Date precision mismatches
    private func countFor(date: Date) -> Int {
        // First try direct lookup
        if let count = activityData[date] {
            return count
        }

        // Fall back to finding a matching date within the same calendar day
        // This handles cases where Date objects have slightly different times
        let targetDay = calendar.startOfDay(for: date)
        for (key, value) in activityData where calendar.isDate(key, inSameDayAs: targetDay) {
            return value
        }

        return 0
    }

    private func colorFor(count: Int) -> Color {
        if count == 0 {
            return Color(.systemGray5)
        }
        let intensity = min(Double(count) / Double(max(maxCount, 1)), 1.0)
        return Color.green.opacity(0.3 + intensity * 0.7)
    }
}
