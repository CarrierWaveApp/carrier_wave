import SwiftUI

// MARK: - Activity Log Card & Favorites Card

extension DashboardView {
    var activityLogCard: some View {
        Group {
            if let manager = activityLogManager {
                if let log = manager.activeLog {
                    NavigationLink {
                        ActivityLogView(manager: manager)
                    } label: {
                        ActivityLogCard(
                            activeLog: log,
                            todayQSOCount: manager.todayQSOCount,
                            todayBands: manager.todayBands,
                            profileSummary: manager.currentProfile?.summaryLine,
                            grid: log.currentGrid,
                            showSetup: {}
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ActivityLogCard(
                        activeLog: nil,
                        todayQSOCount: 0,
                        todayBands: [],
                        profileSummary: nil,
                        grid: nil,
                        showSetup: { showingActivityLogSetup = true }
                    )
                }
            }
        }
        .miniTour(.activityLog, tourState: tourState)
        .onAppear {
            activityLogManager?.refreshCurrentProfile()
        }
    }

    @ViewBuilder
    var favoritesCard: some View {
        if asyncStats.hasComputed {
            FavoritesCard(asyncStats: asyncStats, tourState: tourState)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Favorites")
                    .font(.headline)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    var equipmentCard: some View {
        if equipmentStats.hasComputed, equipmentStats.hasData {
            EquipmentUsageCard(equipmentStats: equipmentStats)
        }
    }

    var conditionsCard: some View {
        ConditionsCard(tourState: tourState)
    }

    var friendsOnAirCard: some View {
        FriendsOnAirCard()
    }

    var friendActivityCard: some View {
        FriendActivityCard(onActivityTap: navigateToActivityFeed)
    }

    private func navigateToActivityFeed() {
        if TabConfiguration.isTabEnabled(.activity) {
            selectedTab = .activity
        } else {
            pendingMoreTabDestination = .activity
            selectedTab = .more
        }
    }
}
