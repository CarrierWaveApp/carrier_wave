import CarrierWaveData
import SwiftUI

// MARK: - DashboardView Stats Grid Extension

extension DashboardView {
    var statsGrid: some View {
        StatsSummaryGrid(
            asyncStats: asyncStats,
            columns: statsGridColumns,
            lotwIsConfigured: lotwIsConfigured,
            tourState: tourState,
            onQSOsTapped: { selectedTab = .logs }
        )
    }

    // MARK: - Streaks Card

    var streaksCard: some View {
        NavigationLink {
            LazyStreakDetailView(asyncStats: asyncStats, tourState: tourState)
        } label: {
            MetricsCard(asyncStats: asyncStats)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Card

    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            statsGrid
        }
    }

    // MARK: - WAS Card

    var wasCard: some View {
        WASCardWrapper(asyncStats: asyncStats)
    }

    // MARK: - Combined Streaks and Stats Card (Landscape)

    var combinedStreaksAndStatsCard: some View {
        HStack(alignment: .top, spacing: 16) {
            // Streaks section (left side)
            NavigationLink {
                LazyStreakDetailView(asyncStats: asyncStats, tourState: tourState)
            } label: {
                MetricsCard(asyncStats: asyncStats)
            }
            .buttonStyle(.plain)

            Divider()

            // Stats section (right side)
            VStack(alignment: .leading, spacing: 12) {
                Text("Statistics")
                    .font(.headline)

                statsGrid
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - POTA Awards Card

    var potaAwardsCard: some View {
        POTAAwardsDashboardCard()
    }
}
