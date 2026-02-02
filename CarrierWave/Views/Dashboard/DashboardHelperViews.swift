import SwiftData
import SwiftUI

// MARK: - StatBox

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - StatBoxDeferred

/// StatBox variant for deferred (progressively computed) values.
/// Shows "--" with reduced opacity when value is nil (still computing).
struct StatBoxDeferred: View {
    let title: String
    let value: Int?
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Group {
                if let value {
                    Text("\(value)")
                } else {
                    Text("--")
                }
            }
            .font(.title2)
            .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(value == nil ? 0.6 : 1.0)
    }
}

// MARK: - ActivationsStatBox

struct ActivationsStatBox: View {
    let successful: Int?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "leaf")
                .font(.title3)
                .foregroundStyle(.blue)
            Group {
                if let successful {
                    Text("\(successful)")
                } else {
                    Text("--")
                }
            }
            .font(.title2)
            .fontWeight(.bold)
            Text("Activations")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(successful == nil ? 0.6 : 1.0)
    }
}

// MARK: - StreakStatBox

struct StreakStatBox: View {
    let streak: StreakInfo

    var body: some View {
        VStack(spacing: 4) {
            Text("\(streak.currentStreak)")
                .font(.title)
                .fontWeight(.bold)
            Text("Best: \(streak.longestStreak)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - StreaksCard

struct StreaksCard: View {
    let dailyStreak: StreakInfo?
    let potaStreak: StreakInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streaks")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily QSOs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    StreakStatBox(streak: dailyStreak ?? .placeholder)
                }
                .opacity(dailyStreak == nil ? 0.6 : 1.0)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("POTA Activations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    StreakStatBox(streak: potaStreak ?? .placeholder)
                }
                .opacity(potaStreak == nil ? 0.6 : 1.0)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

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

/// Internal view that calculates and reports its ideal size
private struct ActivityGridContent: View {
    // MARK: Internal

    let activityData: [Date: Int]

    @Binding var selectedDate: Date?

    var body: some View {
        GeometryReader { geometry in
            let gridWidth = geometry.size.width
            let calculatedColumns = Int((gridWidth + spacing) / (targetCellSize + spacing))
            let columnCount = min(max(calculatedColumns, 26), 52)
            let cellSize = (gridWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
            let gridHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
            let columnWidth = cellSize + spacing

            VStack(alignment: .leading, spacing: gridToLabelSpacing) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0 ..< columnCount, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0 ..< rows, id: \.self) { row in
                                let date = dateFor(
                                    column: column, row: row, totalColumns: columnCount
                                )
                                let count = activityData[date] ?? 0

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
                    }
                }
                .frame(height: gridHeight)

                ZStack(alignment: .topLeading) {
                    ForEach(monthLabelPositions(columnCount: columnCount), id: \.column) { item in
                        Text(item.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: CGFloat(item.column) * columnWidth)
                    }
                }
                .frame(width: gridWidth, height: monthLabelHeight, alignment: .topLeading)
            }
        }
        .frame(height: calculatedHeight)
    }

    // MARK: Private

    private let rows = 7
    private let spacing: CGFloat = 2
    private let targetCellSize: CGFloat = 14
    private let monthLabelHeight: CGFloat = 14
    private let gridToLabelSpacing: CGFloat = 4

    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private var maxCount: Int {
        activityData.values.max() ?? 1
    }

    /// Calculate the expected height based on target cell size
    /// This provides an ideal height that works across different widths
    private var calculatedHeight: CGFloat {
        // Use target cell size for consistent height calculation
        let gridHeight = CGFloat(rows) * targetCellSize + CGFloat(rows - 1) * spacing
        return gridHeight + gridToLabelSpacing + monthLabelHeight
    }

    private func monthLabelPositions(columnCount: Int) -> [(column: Int, label: String)] {
        var labels: [(Int, String)] = []
        var lastMonth = -1

        for column in 0 ..< columnCount {
            let date = dateFor(column: column, row: 0, totalColumns: columnCount)
            let month = calendar.component(.month, from: date)

            if month != lastMonth {
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

    private func colorFor(count: Int) -> Color {
        if count == 0 {
            return Color(.systemGray5)
        }
        let intensity = min(Double(count) / Double(max(maxCount, 1)), 1.0)
        return Color.green.opacity(0.3 + intensity * 0.7)
    }
}

// MARK: - FavoritesCard

struct FavoritesCard: View {
    let asyncStats: AsyncQSOStatistics
    let tourState: TourState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites")
                .font(.headline)

            VStack(spacing: 0) {
                // Top Frequency
                AsyncFavoriteRow(
                    title: "Top Frequency",
                    icon: "dial.medium.fill",
                    identifier: asyncStats.topFrequency.map { "\($0) MHz" },
                    count: asyncStats.topFrequencyCount,
                    category: .frequencies,
                    asyncStats: asyncStats,
                    tourState: tourState
                )

                Divider()
                    .padding(.leading, 44)

                // Best Friend
                AsyncFavoriteRow(
                    title: "Best Friend",
                    icon: "person.2.fill",
                    identifier: asyncStats.topFriend,
                    count: asyncStats.topFriendCount,
                    category: .bestFriends,
                    asyncStats: asyncStats,
                    tourState: tourState
                )

                Divider()
                    .padding(.leading, 44)

                // Best Hunter
                AsyncFavoriteRow(
                    title: "Best Hunter",
                    icon: "scope",
                    identifier: asyncStats.topHunter,
                    count: asyncStats.topHunterCount,
                    category: .bestHunters,
                    asyncStats: asyncStats,
                    tourState: tourState
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - AsyncFavoriteRow

/// Favorite row that uses pre-computed data from AsyncQSOStatistics
/// and lazily loads full stats only when navigating to detail view
private struct AsyncFavoriteRow: View {
    let title: String
    let icon: String
    let identifier: String?
    let count: Int
    let category: StatCategoryType
    let asyncStats: AsyncQSOStatistics
    let tourState: TourState

    var body: some View {
        NavigationLink {
            // Load full stats lazily when navigating
            LazyStatDetailView(
                category: category,
                asyncStats: asyncStats,
                tourState: tourState
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let identifier {
                        Text(identifier)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text("No data yet")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if identifier != nil {
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LazyStatDetailView

/// Wrapper that lazily loads QSOStatistics when the view appears
private struct LazyStatDetailView: View {
    // MARK: Internal

    let category: StatCategoryType
    let asyncStats: AsyncQSOStatistics
    let tourState: TourState

    var body: some View {
        Group {
            if let items {
                StatDetailView(category: category, items: items, tourState: tourState)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Load stats on background-ish (still main actor but deferred)
            if let stats = asyncStats.getStats() {
                items = stats.items(for: category)
            } else {
                // Fall back to computing fresh if needed
                var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
                descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
                if let qsos = try? modelContext.fetch(descriptor) {
                    let stats = QSOStatistics(qsos: qsos)
                    items = stats.items(for: category)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var items: [StatCategoryItem]?
}
