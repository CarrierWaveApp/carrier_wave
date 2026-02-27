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
        .navigationTitle("Hunter Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Hunter log settings")
            }
        }
        .navigationDestination(isPresented: $showingSettings) {
            ActivityLogSettingsView()
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
                            requestGPSGridIfNeeded()
                        }
                    }
                )
            )
        }
        .sheet(isPresented: $showingFilterSheet) {
            SpotFilterSheet(
                filters: $spotFilters,
                selectedRegions: Binding(
                    get: { SpotRegionGroup.decode(spotRegionFilterRaw) },
                    set: { spotRegionFilterRaw = SpotRegionGroup.encode($0) }
                )
            )
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
            guard !hasLoaded else {
                return
            }
            hasLoaded = true

            manager.refreshTodayStats()
            recentQSOs = manager.fetchRecentQSOs()

            // Capture container before crossing isolation boundary
            let container = modelContext.container

            // Fire heavy cache load concurrently with monitoring setup
            async let cacheLoad: Void = workedBeforeCache.loadToday(
                container: container
            )

            spotMonitor.friendNotifier.updateFriends(
                Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
            )
            spotMonitor.startHunterMonitoring(
                myGrid: manager.activeLog?.currentGrid
            )
            requestGPSGridIfNeeded()

            await cacheLoad
        }
        .onChange(of: locationService.currentGrid) { _, newGrid in
            if let newGrid,
               manager.currentProfile?.useCurrentLocation == true
            {
                manager.updateGrid(newGrid)
            }
        }
        .onDisappear {
            spotMonitor.stopMonitoring()
        }
    }

    // MARK: Private

    @AppStorage("spotMaxAgeMinutes") private var spotMaxAgeMinutes = 12
    @AppStorage("spotRegionFilter") private var spotRegionFilterRaw = ""
    @AppStorage("huntedSpotBehavior") private var huntedSpotBehaviorRaw = HuntedSpotBehavior.crossOut.rawValue

    @State private var showingSettings = false
    @State private var showingProfilePicker = false
    @State private var showingFilterSheet = false
    @State private var showingLocationChange = false
    @State private var showingGoalAlert = false
    @State private var hasLoaded = false
    @State private var detectedGrid = ""
    @State private var recentQSOs: [QSO] = []
    @State private var currentMode = "CW"
    @State private var currentFrequency: Double?
    @State private var spotFilters = SpotFilters()
    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var spotMonitor = SpotMonitoringService()
    @State private var workedBeforeCache = WorkedBeforeCache()
    @State private var workedCacheVersion = 0
    @State private var locationService = GridLocationService()

    private var huntedBehavior: HuntedSpotBehavior {
        HuntedSpotBehavior(rawValue: huntedSpotBehaviorRaw) ?? .crossOut
    }

    private var selectedRegions: Set<SpotRegionGroup> {
        SpotRegionGroup.decode(spotRegionFilterRaw)
    }

    private var headerSection: some View {
        ActivityLogHeader(
            todayQSOCount: manager.todayQSOCount,
            todayBands: manager.todayBands,
            todayModes: manager.todayModes,
            profileName: manager.currentProfile?.name,
            profileSummary: manager.currentProfile?.summaryLine,
            grid: manager.activeLog?.currentGrid,
            useCurrentLocation: manager.currentProfile?.useCurrentLocation ?? false,
            onSwitchProfile: { showingProfilePicker = true }
        )
    }

    private var spotsSection: some View {
        ActivityLogSpotsList(
            spots: spotMonitor.hunterSpots,
            filters: $spotFilters,
            maxAgeMinutes: spotMaxAgeMinutes,
            selectedRegions: selectedRegions,
            huntedBehavior: huntedBehavior,
            workedBeforeCache: workedBeforeCache,
            workedCacheVersion: workedCacheVersion,
            manager: manager,
            container: modelContext.container,
            onShowFilterSheet: { showingFilterSheet = true },
            onSpotLogged: { freq, mode in handleSpotLogged(frequencyMHz: freq, mode: mode) }
        )
    }

    private var quickLogSection: some View {
        QuickLogSection(
            currentMode: $currentMode,
            currentFrequency: $currentFrequency
        ) { data in
            handleQuickLog(data)
        }
    }

    private var recentQSOsSection: some View {
        RecentQSOsSection(
            recentQSOs: recentQSOs,
            manager: manager,
            onQSOChanged: {
                recentQSOs = manager.fetchRecentQSOs()
                manager.refreshTodayStats()
                workedCacheVersion += 1
            }
        )
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
            workedCacheVersion += 1
            Task {
                await workedBeforeCache.recordQSO(
                    callsign: data.callsign,
                    band: data.band
                )
            }
        }
    }

    private func handleSpotLogged(frequencyMHz: Double, mode: String) {
        currentFrequency = frequencyMHz
        currentMode = mode
        manager.refreshTodayStats()
        recentQSOs = manager.fetchRecentQSOs()
        workedCacheVersion += 1
    }

    private func requestGPSGridIfNeeded() {
        if manager.currentProfile?.useCurrentLocation == true {
            locationService.requestGrid()
        }
    }
}
