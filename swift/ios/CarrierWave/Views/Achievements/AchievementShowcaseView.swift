import CarrierWaveData
import SwiftUI

// MARK: - AchievementShowcaseView

/// Grid of all catalog achievements grouped by category, with a tile per achievement.
/// Earned ones light up; unearned ones are dimmed (or hidden behind a lock if secret).
struct AchievementShowcaseView: View {
    // MARK: Internal

    let catalog: [Achievement]
    let earnedIDs: Set<String>

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(grouped, id: \.0) { category, items in
                    section(title: title(for: category), items: items)
                }
            }
            .padding()
        }
        .navigationTitle("Badges")
        .sheet(item: $selected) { achievement in
            AchievementDetailSheet(
                achievement: achievement,
                earned: earnedIDs.contains(achievement.id)
            )
        }
    }

    // MARK: Private

    @State private var selected: Achievement?

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 12),
    ]

    private var grouped: [(Achievement.Category, [Achievement])] {
        let visible = catalog.filter { !$0.secret || earnedIDs.contains($0.id) }
        let buckets = Dictionary(grouping: visible, by: \.category)
        return Achievement.Category.allCases.compactMap { category in
            guard let items = buckets[category]?.sorted(by: { $0.sortOrder < $1.sortOrder }),
                  !items.isEmpty
            else {
                return nil
            }
            return (category, items)
        }
    }

    private func section(title: String, items: [Achievement]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    Button {
                        selected = item
                    } label: {
                        AchievementBadgeView(
                            achievement: item,
                            earned: earnedIDs.contains(item.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows badge details")
                }
            }
        }
    }

    private func title(for category: Achievement.Category) -> String {
        switch category {
        case .creator: "Creators"
        case .community: "Community"
        case .activity: "On the Air"
        case .ecosystem: "Ecosystem"
        case .streak: "Streaks"
        case .quirky: "Curiosities"
        case .unknown: "Other"
        }
    }
}

#Preview {
    NavigationStack {
        AchievementShowcaseView(
            catalog: [
                .preview(id: "creator", name: "Creator", iconName: "hammer.fill"),
                .preview(id: "first-qso", name: "First QSO", iconName: "antenna.radiowaves.left.and.right"),
                .preview(id: "qso-100", name: "Centurion", iconName: "antenna.radiowaves.left.and.right"),
            ],
            earnedIDs: ["creator"]
        )
    }
}
