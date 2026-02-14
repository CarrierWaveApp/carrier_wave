import SwiftData
import SwiftUI

// MARK: - ActivityLogView

/// Main Activity Log view, pushed from the dashboard card.
/// Quick log first, then spots list and recent QSOs below.
struct ActivityLogView: View {
    // MARK: Internal

    @Bindable var manager: ActivityLogManager

    @Environment(\.modelContext) var modelContext

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                quickLogSection
                spotsSection
                recentQSOsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ActivityLogSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Activity log settings")
            }
        }
        .sheet(isPresented: $showingProfilePicker) {
            StationProfilePicker(
                selectedProfileId: Binding(
                    get: { manager.activeLog?.stationProfileId },
                    set: { newId in
                        if let newId,
                           let profile = StationProfileStorage.profile(for: newId)
                        {
                            manager.switchProfile(profile)
                        }
                    }
                )
            )
        }
        .sheet(isPresented: $showingFilterSheet) {
            SpotFilterSheet(filters: $spotFilters)
        }
        .sheet(isPresented: $showingLocationChange) {
            if let oldGrid = manager.activeLog?.currentGrid,
               !detectedGrid.isEmpty
            {
                LocationChangeSheet(
                    oldGrid: oldGrid,
                    newGrid: detectedGrid,
                    profiles: StationProfileStorage.load(),
                    currentProfileId: manager.activeLog?.stationProfileId,
                    onUpdate: { grid, profileId in
                        manager.updateGrid(grid)
                        if let profileId,
                           let profile = StationProfileStorage.profile(for: profileId)
                        {
                            manager.switchProfile(profile)
                        }
                        showingLocationChange = false
                    },
                    onKeep: { showingLocationChange = false }
                )
            }
        }
        .alert(
            "Daily Goal Reached!",
            isPresented: $showingGoalAlert
        ) {
            Button("OK") {}
        } message: {
            Text("\(manager.todayQSOCount) QSOs today!")
        }
        .onChange(of: manager.dailyGoalReached) { _, reached in
            if reached {
                showingGoalAlert = true
                manager.consumeDailyGoalReached()
            }
        }
        .task {
            manager.refreshTodayStats()
            recentQSOs = manager.fetchRecentQSOs()
            await workedBeforeCache.loadToday(
                container: modelContext.container
            )
            spotMonitor.startHunterMonitoring(
                myGrid: manager.activeLog?.currentGrid
            )
        }
        .onDisappear {
            spotMonitor.stopMonitoring()
        }
    }

    // MARK: Private

    @AppStorage("spotMaxAgeMinutes") private var spotMaxAgeMinutes = 12
    @AppStorage("spotProximityRadiusMiles") private var proximityRadiusMiles = 500

    @State private var showingProfilePicker = false
    @State private var showingFilterSheet = false
    @State private var showingLocationChange = false
    @State private var showingGoalAlert = false
    @State private var detectedGrid = ""
    @State private var recentQSOs: [QSO] = []
    @State private var currentMode = "CW"
    @State private var currentFrequency: Double?
    @State private var spotFilters = SpotFilters()
    @State private var spotMonitor = SpotMonitoringService()
    @State private var workedBeforeCache = WorkedBeforeCache()

    private var headerSection: some View {
        ActivityLogHeader(
            todayQSOCount: manager.todayQSOCount,
            todayBands: manager.todayBands,
            todayModes: manager.todayModes,
            profileName: manager.currentProfile?.name,
            profileSummary: manager.currentProfile?.summaryLine,
            grid: manager.activeLog?.currentGrid,
            onSwitchProfile: { showingProfilePicker = true }
        )
    }

    private var spotsSection: some View {
        ActivityLogSpotsList(
            spots: spotMonitor.hunterSpots,
            filters: $spotFilters,
            maxAgeMinutes: spotMaxAgeMinutes,
            proximityRadiusMiles: proximityRadiusMiles,
            workedBeforeCache: workedBeforeCache,
            manager: manager,
            container: modelContext.container,
            onShowFilterSheet: { showingFilterSheet = true },
            onSpotLogged: { handleSpotLogged() }
        )
    }

    private var quickLogSection: some View {
        QuickLogSection(
            currentMode: currentMode,
            currentFrequency: currentFrequency
        ) { data in
            handleQuickLog(data)
        }
    }

    private var recentQSOsSection: some View {
        RecentQSOsSection(recentQSOs: recentQSOs, manager: manager)
    }

    private func handleQuickLog(_ data: QuickLogData) {
        let qso = manager.logQSO(
            callsign: data.callsign,
            band: data.band,
            mode: data.mode,
            frequency: data.frequency,
            rstSent: data.rstSent,
            rstReceived: data.rstReceived,
            theirGrid: data.theirGrid,
            theirParkReference: data.theirParkReference,
            notes: data.notes,
            state: data.state
        )

        if qso != nil {
            currentMode = data.mode
            currentFrequency = data.frequency
            recentQSOs = manager.fetchRecentQSOs()
            Task {
                await workedBeforeCache.recordQSO(
                    callsign: data.callsign,
                    band: data.band
                )
            }
        }
    }

    private func handleSpotLogged() {
        manager.refreshTodayStats()
        recentQSOs = manager.fetchRecentQSOs()
    }
}
