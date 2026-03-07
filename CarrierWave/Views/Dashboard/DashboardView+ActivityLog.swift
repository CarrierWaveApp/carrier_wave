import CarrierWaveData
import SwiftUI

// MARK: - Activity Card, Activity Log Card & Favorites Card

extension DashboardView {
    var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                StatsQSOCountLabel(asyncStats: asyncStats)
            }

            ActivityGrid(
                activationData: asyncStats.activationActivityByDate,
                activityLogData: asyncStats.activityLogActivityByDate
            )

            StatsProgressIndicator(asyncStats: asyncStats)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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
                    .miniTour(.activityLog, tourState: tourState)
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

    var contestsCard: some View {
        ContestsCard()
    }

    var callsignLookupCard: some View {
        CallsignLookupCard()
    }

    var friendsOnAirCard: some View {
        FriendsOnAirCard(manager: activityLogManager)
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
