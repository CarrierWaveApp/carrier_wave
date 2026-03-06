import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivityLogView

/// Main Activity Log view, pushed from the dashboard card.
/// Quick log first, then spots list and recent QSOs below.
struct ActivityLogView: View {
    // MARK: Internal

    @Bindable var manager: ActivityLogManager

    @Environment(\.modelContext) var modelContext
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var body: some View {
        Group {
            if hasLoaded {
                if verticalSizeClass == .compact {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }
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
                            BLERadioService.shared.setProtocolFromRig(profile.rig)
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

            // Set BLE protocol from the station profile's rig
            BLERadioService.shared.setProtocolFromRig(
                manager.currentProfile?.rig
            )

            manager.refreshTodayStats()
            recentQSOs = manager.fetchRecentQSOs()

            // Mark loaded so the view body switches from placeholder to content.
            // This frame commits before heavy spot monitoring begins below.
            hasLoaded = true

            // Yield so the first content frame renders before spot monitoring
            // starts 3 network requests + HamDB lookups on @MainActor.
            await Task.yield()

            // Capture container before crossing isolation boundary
            let container = modelContext.container

            // Load accepted friends (deferred from @Query to avoid blocking
            // view construction with a synchronous SwiftData fetch on cold start)
            let friendDescriptor = FetchDescriptor<Friendship>(
                predicate: #Predicate<Friendship> { $0.statusRawValue == "accepted" }
            )
            acceptedFriends = (try? modelContext.fetch(friendDescriptor)) ?? []

            spotMonitor.friendNotifier.updateFriends(
                Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
            )
            spotMonitor.startHunterMonitoring(
                myGrid: manager.activeLog?.currentGrid
            )
            requestGPSGridIfNeeded()

            // Fire heavy loads as fire-and-forget to avoid blocking this task.
            // Blocking with `await` risks the task being cancelled (view lifecycle)
            // after monitoring starts but before awaited work completes.
            Task {
                await workedBeforeCache.loadToday(container: container)
            }
            Task.detached {
                let counts = CallsignSuggestionProvider.loadContactCounts(
                    container: container
                )
                await MainActor.run { suggestionContactCounts = counts }
            }
        }
        .onChange(of: locationService.currentGrid) { _, newGrid in
            if let newGrid,
               manager.currentProfile?.useCurrentLocation == true
            {
                manager.updateGrid(newGrid)
            }
        }
        .onAppear {
            // Restart monitoring if the view reappears after onDisappear stopped it.
            // The initial start happens in .task; this covers navigate-away-and-back.
            guard hasLoaded, !spotMonitor.isMonitoring else {
                return
            }
            spotMonitor.startHunterMonitoring(
                myGrid: manager.activeLog?.currentGrid
            )
        }
        .onDisappear {
            spotMonitor.stopMonitoring()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didSyncQSOs)
        ) { _ in
            workedCacheVersion += 1
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
    @AppStorage("hunterSpotFilters") private var spotFilters = SpotFilters()
    @State private var acceptedFriends: [Friendship] = []

    @State private var suggestionContactCounts: [String: Int] = [:]
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

    /// Portrait layout: vertical scroll with all sections stacked
    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                quickLogSection
                spotsSection
                recentQSOsSection
            }
            .padding()
        }
    }

    /// Landscape layout: quick log on the left, spots on the right
    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    headerSection
                    quickLogSection
                    recentQSOsSection
                }
                .padding()
            }
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                spotsSection
                    .padding()
            }
            .frame(maxWidth: .infinity)
        }
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
            currentFrequency: $currentFrequency,
            spotCallsigns: spotMonitor.hunterSpots.map(\.spot.callsign),
            contactCounts: suggestionContactCounts
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
}

// MARK: - ActivityLogView Actions

extension ActivityLogView {
    func handleQuickLog(_ data: QuickLogData) {
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

        if let qso {
            currentMode = data.mode
            currentFrequency = data.frequency
            recentQSOs = manager.fetchRecentQSOs()
            workedCacheVersion += 1
            Task {
                await workedBeforeCache.recordQSO(
                    callsign: data.callsign,
                    band: data.band,
                    mode: data.mode
                )
            }
            Task {
                await enrichQSOWithLookup(qso)
            }
        }
    }

    func handleSpotLogged(frequencyMHz: Double, mode: String) {
        currentFrequency = frequencyMHz
        currentMode = mode
        manager.refreshTodayStats()
        recentQSOs = manager.fetchRecentQSOs()
        workedCacheVersion += 1
    }

    func enrichQSOWithLookup(_ qso: QSO) async {
        let service = CallsignLookupService(modelContext: modelContext)
        guard let info = await service.lookup(qso.callsign) else {
            return
        }
        if qso.name == nil {
            qso.name = info.name
        }
        if qso.theirGrid == nil {
            qso.theirGrid = info.grid
        }
        if qso.state == nil {
            qso.state = info.state
        }
        if qso.country == nil {
            qso.country = info.country
        }
        if qso.qth == nil {
            qso.qth = info.qth
        }
        if qso.theirLicenseClass == nil {
            qso.theirLicenseClass = info.licenseClass
        }
        qso.callsignChangeNote = info.callsignChangeNote
        try? modelContext.save()
    }

    func requestGPSGridIfNeeded() {
        if manager.currentProfile?.useCurrentLocation == true {
            locationService.requestGrid()
        }
    }
}
