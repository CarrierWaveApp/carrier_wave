import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivityLogView

/// Main Activity Log view, pushed from the dashboard card.
/// Quick log first, then spots list and recent QSOs below.
struct ActivityLogView: View {
    // MARK: Internal

    @Bindable var manager: ActivityLogManager
    var pendingSpotUserInfo: [String: Any]?

    @Environment(\.modelContext) var modelContext
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var body: some View {
        Group {
            if hasLoaded {
                if ft8Manager != nil {
                    ft8Layout
                } else if verticalSizeClass == .compact {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) {
            HunterPanelOverlays(state: panelState, manager: manager)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Hunter Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    ft8ToolbarButton
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Hunter log settings")
                }
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
                            RadioService.shared.setProtocolFromRig(profile.rig)
                        }
                    }
                )
            )
        }
        .sheet(isPresented: $showingFilterSheet) {
            SpotFilterSheet(
                filters: $spotFilters,
                selectedContinents: Binding(
                    get: { SpotContinent.decode(spotRegionFilterRaw) },
                    set: { spotRegionFilterRaw = SpotContinent.encode($0) }
                )
            )
        }
        .onChange(of: spotFilters.sources) { _, _ in
            // Source toggles drive the engine's fetch set + cluster
            // connection, not just display filtering.
            SpotEngineProvider.shared.applyConfig()
            SpotEngineProvider.shared.applyClusterConnection()
        }
        .onChange(of: spotFilters.savedQueryID) { _, _ in
            // "Filter by saved query" pushes the query into the engine;
            // the next publish carries `allowed_spot_ids`.
            SpotEngineProvider.shared.applyBandScopeQuery()
        }
        .sheet(isPresented: $showFT8SetupWizard) {
            FT8SetupWizardView(isPresented: $showFT8SetupWizard)
        }
        .onChange(of: ft8SetupComplete) { _, complete in
            if complete, ft8Manager == nil {
                startFT8Session()
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

            // Set radio protocol from the station profile's rig
            RadioService.shared.setProtocolFromRig(
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

            // Pending spot is passed directly to QuickLogSection via
            // initialSpotInfo — no timing hack needed.

            // Capture container before crossing isolation boundary
            let container = modelContext.container

            // Accepted friends live in the Rust store, published by the service.
            acceptedFriends = FriendsSyncService.shared.acceptedFriends

            spotMonitor.friendNotifier.updateFriends(
                Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
            )
            spotMonitor.startHunterMonitoring(
                myGrid: manager.activeLog?.currentGrid
            )
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
            if let ft8 = ft8Manager {
                Task { await ft8.stop() }
                ft8Manager = nil
            }
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
    @State private var showingGoalAlert = false
    @State private var hasLoaded = false
    @State private var recentQSOs: [QSO] = []
    @State private var currentMode = "CW"
    @State private var currentFrequency: Double?
    @AppStorage("hunterSpotFilters") private var spotFilters = SpotFilters()
    @State private var acceptedFriends: [Friendship] = []

    @State private var recalledSpot: EnrichedSpot?
    @State private var recalledQSO: QSO?
    @State private var suggestionContactCounts: [String: Int] = [:]
    @State private var spotMonitor = SpotMonitoringService()
    @State private var workedBeforeCache = WorkedBeforeCache()
    @State private var workedCacheVersion = 0
    @State private var panelState = HunterPanelState()
    @State private var ft8Manager: FT8SessionManager?
    @State private var showFT8SetupWizard = false
    @AppStorage("ft8SetupComplete") private var ft8SetupComplete = false

    private var huntedBehavior: HuntedSpotBehavior {
        HuntedSpotBehavior(rawValue: huntedSpotBehaviorRaw) ?? .crossOut
    }

    private var selectedContinents: Set<SpotContinent> {
        SpotContinent.decode(spotRegionFilterRaw)
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
        .refreshable {
            await refreshSpots()
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
            .refreshable {
                await refreshSpots()
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
            myCallsign: manager.activeLog?.myCallsign,
            useCurrentLocation: manager.currentProfile?.useCurrentLocation ?? false,
            onSwitchProfile: { showingProfilePicker = true }
        )
    }

    private var spotsSection: some View {
        ActivityLogSpotsList(
            spots: spotMonitor.hunterSpots,
            filters: $spotFilters,
            allowedSpotIds: spotFilters.savedQueryID != nil
                ? spotMonitor.allowedSpotIds
                : nil,
            lastRefresh: spotMonitor.lastRefresh,
            maxAgeMinutes: spotMaxAgeMinutes,
            selectedContinents: selectedContinents,
            huntedBehavior: huntedBehavior,
            workedBeforeCache: workedBeforeCache,
            workedCacheVersion: workedCacheVersion,
            manager: manager,
            container: modelContext.container,
            hasFetched: spotMonitor.hasFetchedHunterSpots,
            onShowFilterSheet: { showingFilterSheet = true },
            onSpotLogged: { freq, mode in handleSpotLogged(frequencyMHz: freq, mode: mode) },
            onRecallSpot: { spot in recalledSpot = spot }
        )
    }

    private var quickLogSection: some View {
        QuickLogSection(
            currentMode: $currentMode,
            currentFrequency: $currentFrequency,
            recalledSpot: $recalledSpot,
            recalledQSO: $recalledQSO,
            spotCallsigns: spotMonitor.hunterSpots.map(\.spot.callsign),
            contactCounts: suggestionContactCounts,
            initialSpotInfo: pendingSpotUserInfo,
            onLog: { data in handleQuickLog(data) },
            onMyCallChanged: { call in manager.activeLog?.myCallsign = call },
            onPanelCommand: { command in panelState.handle(command, manager: manager) }
        )
    }

    private var recentQSOsSection: some View {
        RecentQSOsSection(
            recentQSOs: recentQSOs,
            manager: manager,
            onQSOChanged: {
                recentQSOs = manager.fetchRecentQSOs()
                manager.refreshTodayStats()
                workedCacheVersion += 1
            },
            onRecall: { qso in
                recalledQSO = qso
            }
        )
    }
}

// MARK: - ActivityLogView FT8

extension ActivityLogView {
    @ViewBuilder
    var ft8ToolbarButton: some View {
        if ft8Manager != nil {
            Button {
                stopFT8Session()
            } label: {
                Label("Stop FT8", systemImage: "stop.fill")
                    .foregroundStyle(.red)
            }
            .accessibilityLabel("Stop FT8 session")
        } else {
            Button {
                startFT8Session()
            } label: {
                Image(systemName: "waveform")
            }
            .accessibilityLabel("Start FT8 session")
        }
    }

    @ViewBuilder
    var ft8Layout: some View {
        if let ft8 = ft8Manager {
            VStack(spacing: 0) {
                ActivityLogFT8View(
                    ft8Manager: ft8,
                    onStop: { stopFT8Session() }
                )
            }
        }
    }
}

// MARK: - ActivityLogView Actions

extension ActivityLogView {
    func handleQuickLog(_ data: QuickLogData) {
        let logged = manager.logQSO(
            callsign: data.callsign,
            band: data.band,
            mode: data.mode,
            frequency: data.frequency,
            rstSent: data.rstSent,
            rstReceived: data.rstReceived,
            theirGrid: data.theirGrid,
            theirParkReference: data.theirParkReference,
            notes: data.notes,
            name: data.name,
            state: data.state,
            country: data.country
        )

        if let logged {
            currentMode = data.mode
            currentFrequency = data.frequency
            recentQSOs = manager.fetchRecentQSOs()
            workedCacheVersion += 1
            Task {
                await workedBeforeCache.recordQSO(
                    callsign: data.callsign,
                    band: data.band,
                    mode: data.mode,
                    park: data.theirParkReference
                )
            }
            // Re-fetch the live QSO from the snapshot id for in-place enrichment.
            if let qso = LogbookIDBridge.fetchQSO(id: logged.id, in: modelContext) {
                Task {
                    await enrichQSOWithLookup(qso)
                }
            }
        }
    }

    /// Pull-to-refresh: one manual engine poll outside the 2-minute timer.
    /// The spinner stays up until the fetch completes; results arrive
    /// through the engine listener like any poll cycle.
    func refreshSpots() async {
        guard let engine = SpotEngineProvider.shared.engineIfBuilt else {
            return
        }
        await engine.refresh()
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

    // MARK: - FT8 Session

    func startFT8Session() {
        guard ft8Manager == nil else {
            return
        }
        guard let log = manager.activeLog else {
            return
        }

        if !ft8SetupComplete {
            showFT8SetupWizard = true
            return
        }

        ft8Manager = FT8SessionManager(
            myCallsign: log.myCallsign,
            myGrid: log.currentGrid ?? "",
            modelContext: modelContext,
            qsoLogger: manager
        )
    }

    func stopFT8Session() {
        guard let ft8 = ft8Manager else {
            return
        }
        Task {
            await ft8.stop()
        }
        ft8Manager = nil
        // Refresh stats after FT8 QSOs
        manager.refreshTodayStats()
        recentQSOs = manager.fetchRecentQSOs()
        workedCacheVersion += 1
    }
}
