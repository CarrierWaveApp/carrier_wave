// Dashboard View + Needs
//
// Adds the Smart Spots needs card to the dashboard.
// Computes needs snapshot in background and shows on-air summary.

import SwiftData
import SwiftUI

extension DashboardView {
    /// The needs card showing DXCC/WAS progress and on-air matches.
    var needsCard: some View {
        NeedsDashboardCard(
            summary: needsOnAirSummary,
            dxccProgress: needsSnapshot.dxcc,
            wasProgress: needsSnapshot.was,
            onNavigateToActivityLog: {
                selectedTab = .logger
            },
            onShowDetail: {
                showingNeedsDetail = true
            }
        )
        // Needs computation is now serialized in the main stats pipeline
        // (DashboardView.swift .task(id: hasLoadedDashboard)) to avoid
        // concurrent full-table scans that spike peak memory.
        .onChange(of: syncService.lastSyncDate) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                hasComputedNeeds = false
                await recomputeNeeds()
                hasComputedNeeds = true
            }
        }
        .sheet(isPresented: $showingNeedsDetail) {
            NavigationStack {
                NeedsManagementView(snapshot: needsSnapshot)
            }
        }
    }

    // MARK: - Computation

    @MainActor
    func computeNeeds() async {
        StartupProfiler.shared.record("needs.compute.start")
        let snap = await NeedsEngine.shared.recompute(
            container: modelContext.container
        )
        needsSnapshot = snap
        StartupProfiler.shared.record("needs.compute.done")
    }

    @MainActor
    func recomputeNeeds() async {
        await NeedsEngine.shared.invalidate()
        let snap = await NeedsEngine.shared.recompute(
            container: modelContext.container
        )
        needsSnapshot = snap
    }
}
