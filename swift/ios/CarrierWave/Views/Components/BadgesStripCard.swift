import CarrierWaveData
import SwiftUI

// MARK: - BadgesStripCard

/// Self-contained badges card showing the earned profile badges for a
/// callsign as a horizontal strip. Tap a tile to see its detail sheet,
/// or hit "All" to push the full showcase. Used by AboutMeView (own
/// profile) and CallsignHistoryView (any callsign).
struct BadgesStripCard: View {
    // MARK: Internal

    let callsign: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: callsign) {
            await load()
        }
        .sheet(item: $selected) { achievement in
            AchievementDetailSheet(
                achievement: achievement,
                earned: earnedIDs.contains(achievement.id)
            )
        }
    }

    // MARK: Private

    @State private var catalog: [Achievement] = []
    @State private var earnedIDs: Set<String> = []
    @State private var earnedCount: Int?
    @State private var loadFailed = false
    @State private var selected: Achievement?

    private var earnedBadges: [Achievement] {
        catalog
            .filter { earnedIDs.contains($0.id) }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Badges")
                .font(.subheadline.weight(.semibold))
            if let count = earnedCount {
                Text("\(count) earned")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                AchievementShowcaseContainer(callsign: callsign)
            } label: {
                HStack(spacing: 4) {
                    Text("All")
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
            }
            .accessibilityLabel("View all badges for \(callsign)")
        }
    }

    @ViewBuilder
    private var content: some View {
        if loadFailed, catalog.isEmpty {
            placeholderRow(
                systemImage: "wifi.exclamationmark",
                title: "Couldn't load badges",
                detail: "Check your connection and pull to refresh."
            )
        } else if catalog.isEmpty {
            skeletonRow
        } else if earnedBadges.isEmpty {
            placeholderRow(
                systemImage: "rosette",
                title: "No badges yet",
                detail: "Logging activity earns badges across the ecosystem."
            )
        } else {
            scrollRow
        }
    }

    private var scrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(earnedBadges) { badge in
                    Button {
                        selected = badge
                    } label: {
                        BadgeStripTile(badge: badge)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows badge details")
                }

                NavigationLink {
                    AchievementShowcaseContainer(callsign: callsign)
                } label: {
                    BadgeStripMoreTile()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all badges")
            }
            .padding(.vertical, 2)
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 10) {
            ForEach(0 ..< 4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 96)
                    .accessibilityHidden(true)
            }
            Spacer()
        }
        .opacity(0.6)
    }

    private func placeholderRow(
        systemImage: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        let client = ActivitiesClient()
        let baseURL = ActivitiesClient.resolvedBaseURL
        async let catalogFetch = client.fetchAchievementCatalog(sourceURL: baseURL)
        async let awardsFetch = client.fetchUserAchievements(
            callsign: callsign,
            sourceURL: baseURL
        )
        guard
            let loadedCatalog = try? await catalogFetch,
            let awards = try? await awardsFetch
        else {
            loadFailed = true
            return
        }
        catalog = loadedCatalog
        earnedIDs = Set(awards.map(\.achievementId))
        earnedCount = awards.count
        loadFailed = false
    }
}

// MARK: - BadgeStripTile

/// Compact badge tile sized for a horizontal strip on the profile page.
struct BadgeStripTile: View {
    // MARK: Internal

    let badge: Achievement

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: badge.iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accentColor.opacity(0.18)))
            Text(badge.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(width: 88, height: 96)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.name), earned. \(badge.description)")
    }

    // MARK: Private

    private var accentColor: Color {
        badge.accentHex.flatMap(Color.init(hex:)) ?? .accentColor
    }
}

// MARK: - BadgeStripMoreTile

/// Trailing tile in the strip that pushes the full showcase.
struct BadgeStripMoreTile: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
            Text("All Badges")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(width: 88, height: 96)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color(.separator).opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
        )
    }
}
