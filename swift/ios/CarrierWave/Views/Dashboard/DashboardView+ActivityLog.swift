import CarrierWaveData
import SwiftUI

// MARK: - Activity Card, Favorites Card & Dashboard Cards

extension DashboardView {
    var activityCard: some View {
        ActivityCardContent(asyncStats: asyncStats)
    }

    var favoritesCard: some View {
        FavoritesCardWrapper(asyncStats: asyncStats, tourState: tourState)
    }

    @ViewBuilder
    var equipmentCard: some View {
        if equipmentStats.hasComputed, equipmentStats.hasData {
            EquipmentUsageCard(equipmentStats: equipmentStats)
        }
    }

    var onAirCard: some View {
        OnAirCard(tourState: tourState)
    }

    var callsignLookupCard: some View {
        CallsignLookupCard()
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
