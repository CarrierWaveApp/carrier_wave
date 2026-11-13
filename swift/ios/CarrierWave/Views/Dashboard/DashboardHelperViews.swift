import CarrierWaveData
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

// MARK: - CountStatBox

struct CountStatBox: View {
    let value: Int
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - MetricsCard

struct MetricsCard: View {
    // MARK: Internal

    let asyncStats: AsyncQSOStatistics

    var body: some View {
        let _ = metric1RawValue
        let _ = metric2RawValue

        VStack(alignment: .leading, spacing: 12) {
            Text(cardTitle)
                .font(.headline)

            HStack(spacing: 12) {
                metricColumn(for: metric1)

                if let m2 = metric2 {
                    Divider()
                    metricColumn(for: m2)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @AppStorage("dashboardMetric1") private var metric1RawValue =
        DashboardMetricType.onAir.rawValue
    @AppStorage("dashboardMetric2") private var metric2RawValue =
        DashboardMetricType.activation.rawValue

    private var metric1: DashboardMetricType {
        DashboardMetricType(rawValue: metric1RawValue) ?? .onAir
    }

    private var metric2: DashboardMetricType? {
        metric2RawValue.isEmpty ? nil : DashboardMetricType(rawValue: metric2RawValue)
    }

    private var cardTitle: String {
        let types = [metric1, metric2].compactMap { $0 }
        if types.allSatisfy(\.isStreak) {
            return "Streaks"
        }
        return "Metrics"
    }

    private func metricColumn(for type: DashboardMetricType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch asyncStats.metricValue(for: type) {
            case let .streak(info):
                StreakStatBox(streak: info ?? .placeholder)
                    .opacity(info == nil ? 0.6 : 1.0)
            case let .count(value):
                CountStatBox(value: value, subtitle: type.subtitle)
            }
        }
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

// MARK: - LazyStreakDetailView

/// Wrapper that uses pre-computed streak data from AsyncQSOStatistics.
/// All data is already computed on the background StatsComputationActor,
/// so this view never blocks the main thread with QSO fetches or computation.
struct LazyStreakDetailView: View {
    let asyncStats: AsyncQSOStatistics
    let tourState: TourState

    var body: some View {
        if asyncStats.hasComputed {
            StreakDetailView(asyncStats: asyncStats, tourState: tourState)
        } else {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - StatsProgressIndicator

/// Isolated view for stats computation progress display.
/// Prevents progress updates from invalidating sibling views (e.g. ActivityGrid).
struct StatsProgressIndicator: View {
    // MARK: Internal

    let asyncStats: AsyncQSOStatistics

    var body: some View {
        if asyncStats.isComputing {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: asyncStats.progress)
                    .tint(.blue)
                if !asyncStats.progressPhase.isEmpty {
                    Text(asyncStats.progressPhase)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: asyncStats.isComputing)
        }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

// MARK: - StatsQSOCountLabel

/// Isolated view for the QSO count in the activity card header.
/// Prevents count updates from invalidating the ActivityGrid.
struct StatsQSOCountLabel: View {
    let asyncStats: AsyncQSOStatistics

    var body: some View {
        Text("\(asyncStats.totalQSOs) QSOs")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - DashboardSectionLabel

/// Lightweight section divider for creating visual breaks between card groups.
/// Uses uppercase caption text with tracking to differentiate from card titles.
struct DashboardSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

// LazyStatDetailView has been moved to DashboardIsolatedCards.swift
// with background actor computation to avoid blocking the main thread.
