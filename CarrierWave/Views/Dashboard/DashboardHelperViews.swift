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
