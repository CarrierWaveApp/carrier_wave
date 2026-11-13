import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    // MARK: Internal

    let tourState: TourState
    var restoredBackup: PendingRestore?

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @Environment(\.modelContext) var modelContext
    @State var potaAuthService = POTAAuthService()
    @State var selectedTab: AppTab? = .dashboard
    @State var settingsDestination: SettingsDestination?
    @State var syncService: SyncService?
    @State var potaClient: POTAClient?
    @State var pendingMoreTabDestination: AppTab?
    @State var mapFilterState = MapFilterState()
    @State var loggerHasActiveSession = false
    @State var incomingFriendRequestCount = 0
    @State var pendingHunterSpot: [String: Any]?
    @State var pendingSpotlightQSOID: UUID?
    @State var pendingSpotlightSessionID: UUID?

    let lofiClient = LoFiClient.appDefault()
    let qrzClient = QRZClient()
    let hamrsClient = HAMRSClient()
    let lotwClient = LoTWClient()
    let tuneInManager = TuneInManager.shared

    var body: some View {
        Group {
            if isIPad, (lockedSizeClass ?? horizontalSizeClass) == .regular {
                iPadNavigation
            } else {
                iPhoneNavigation
            }
        }
        .orientationProfiled()
        .alert(
            "Database Restored",
            isPresented: $showingRestoreAlert
        ) {
            Button("OK") {
                UserDefaults.standard.removeObject(
                    forKey: "restoredFromBackup"
                )
            }
        } message: {
            Text(restoreAlertMessage)
        }
        .onAppear {
            if lockedSizeClass == nil {
                lockedSizeClass = horizontalSizeClass
            }
            if tourState.shouldShowIntroTour() {
                showIntroTour = true
            } else if tourState.shouldShowOnboarding() {
                showOnboarding = true
            }
            if restoredBackup != nil {
                showingRestoreAlert = true
            }
        }
        .task {
            // Deferred from .onAppear so the first frame commits before heavy
            // service init. dashboardTabContent gates on syncService != nil.

            // Load POTA token from Keychain (deferred from init).
            potaAuthService.loadStoredToken()

            // Yield so pending deep link notification propagates first.
            await Task.yield()

            // Create both services together to avoid double body re-evaluation.
            if syncService == nil {
                let newSync = SyncService(
                    modelContext: modelContext,
                    potaAuthService: potaAuthService
                )
                let newPota = POTAClient(authService: potaAuthService)
                syncService = newSync
                potaClient = newPota
                AutoSyncService.shared.configure(syncService: newSync)
                AutoSyncService.shared.resume()
            }
            StartupProfiler.shared.record("contentView.syncServiceReady")

            // Auto-reconnect to the previously paired CW Sweep on the
            // LAN. No-op if the user has never paired or has no token
            // stored — manual pairing remains required for first run.
            remoteSweepCoordinator.enableAutoConnect()

            // Deferred from @Query to avoid main-thread SwiftData fetch during view init
            refreshFriendRequestCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveADIFFile)) { notification in
            if let url = notification.object as? URL {
                // Handle import - for now just print
                print("Received ADIF file: \(url.lastPathComponent)")
            }
        }
        .modifier(TabSwitchNotificationModifier(
            selectedTab: $selectedTab,
            pendingSpotlightQSOID: $pendingSpotlightQSOID,
            pendingSpotlightSessionID: $pendingSpotlightSessionID
        ))
        .onReceive(
            NotificationCenter.default.publisher(for: .didSelectHunterSpot)
        ) { notification in
            guard notification.userInfo?["callsign"] is String else {
                return
            }
            pendingHunterSpot = notification.userInfo as? [String: Any]
            selectedTab = .logger
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .startContestSession)
        ) { _ in
            // For Phase 1, tapping "Log Now" in ContestDetailSheet simply
            // navigates to the Logger tab. Full template pre-selection is
            // tracked in docs/plans/2026-04-15-contest-enrichment.md Phase 2.
            selectedTab = .logger
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(tourState: tourState)
        }
        .onChange(of: tourState.hasCompletedIntroTour) { _, completed in
            // Show onboarding after intro tour completes
            if completed, tourState.shouldShowOnboarding() {
                showOnboarding = true
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Clear pending deep link when navigating away from More
            if newTab != .more {
                pendingMoreTabDestination = nil
            }
            if let newTab {
                let event = PerfEvent.now(kind: "tab.switch", label: newTab.rawValue)
                Task { await PerfUploader.shared.recordEvent(event) }
                if StartupProfiler.shared.isRunning {
                    StartupProfiler.shared.record("tab.switch.\(newTab.rawValue)")
                    StartupProfiler.shared.persistSnapshot()
                }
            }
        }
    }

    func tabTitle(_ tab: AppTab) -> String {
        if tab == .logger, roleIsHunter {
            return "Hunter Log"
        }
        return tab.title
    }

    func tabIcon(_ tab: AppTab) -> String {
        if tab == .logger, roleIsHunter {
            return "binoculars.fill"
        }
        return tab.icon
    }

    // MARK: Private

    /// Locked layout mode — set once on first appearance, never changes.
    /// Prevents size class transitions (e.g., orientation change on iPad or iPhone Max)
    /// from destroying the entire view hierarchy and resetting @State in child views.
    @State private var lockedSizeClass: UserInterfaceSizeClass?

    @State private var showIntroTour = false
    @State private var showOnboarding = false
    @State private var remoteSweepCoordinator = RemoteSweepCoordinator()
    @State private var visibleTabs: [AppTab] = TabConfiguration.visibleTabs()
    @State private var iPadTabs: [AppTab] = TabConfiguration.iPadVisibleTabs()
    @State private var iPadShowsSettings = false
    @State private var showingRestoreAlert = false

    // MARK: - Per-Tab Labels (role-aware)

    /// Read in both `iPhoneNavigation` and `iPadNavigation` to relabel the
    /// `.logger` tab as "Hunter Log" for users who chose `.hunter`. The tab's
    /// underlying enum case stays `.logger` so deep links, AppStorage keys,
    /// and notification targets are unchanged.
    @AppStorage(OperatorRole.storageKey) private var operatorRoleRaw = ""

    /// True only on iPad — prevents iOS 26's `.regular` horizontal size class
    /// on large iPhones from triggering the iPad sidebar navigation.
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var roleIsHunter: Bool {
        OperatorRole(rawValue: operatorRoleRaw) == .hunter
    }

    // MARK: - iPhone Navigation (TabView)

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab ?? .dashboard },
            set: { selectedTab = $0 }
        )
    }

    /// Hide tab bar when logger has an active session in landscape
    private var shouldHideTabBar: Bool {
        selectedTab == .logger && loggerHasActiveSession && verticalSizeClass == .compact
    }

    // MARK: - iPad Navigation (Sidebar)

    private var iPadNavigation: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(iPadTabs, id: \.self) { tab in
                    Label(tabTitle(tab), systemImage: tabIcon(tab))
                        .badge(tab == .activity ? incomingFriendRequestCount : 0)
                        .tag(tab)
                }

                Section {
                    Button {
                        iPadShowsSettings = true
                        selectedTab = nil
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    .foregroundStyle(iPadShowsSettings ? .primary : .secondary)
                }
            }
            .navigationTitle("CW Field")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .onChange(of: selectedTab) { _, newValue in
                if newValue != nil {
                    iPadShowsSettings = false
                }
            }
        } detail: {
            if iPadShowsSettings {
                iPadSettingsContent
            } else {
                // `.id(selectedTab)` forces a fresh detail pane each time the
                // sidebar selection changes. Without this, any pushed view
                // (e.g. `ActivityLogView` pushed from the Dashboard's Hunter
                // Log card via `.navigationDestination`) stays visible after
                // the user taps a different sidebar tab — selection updates
                // but the SplitView's implicit detail-column navigation stack
                // never pops. Inner `NavigationStack`s aren't an option here
                // (would re-introduce the UINavigationBar snapshot assertion
                // documented in ContentView+iPadDetail.swift).
                iPadSelectedTabContent
                    .id(selectedTab)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if tuneInManager.isActive {
                TuneInMiniPlayerView(manager: tuneInManager)
            }
        }
        .sheet(isPresented: Binding(
            get: { tuneInManager.showExpandedPlayer },
            set: { tuneInManager.showExpandedPlayer = $0 }
        )) {
            TuneInExpandedPlayerView(manager: tuneInManager)
        }
        .tuneInCellularAlert(manager: tuneInManager)
        .tuneInStrategySheet(manager: tuneInManager)
        .tuneInErrorAlert(manager: tuneInManager)
        .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
            iPadTabs = TabConfiguration.iPadVisibleTabs()
            // Ensure selected tab is still visible
            if let selected = selectedTab, !iPadTabs.contains(selected) {
                selectedTab = iPadTabs.first
            }
        }
    }

    private var iPadSettingsContent: some View {
        NavigationStack {
            SettingsMainView(
                potaAuth: potaAuthService,
                destination: $settingsDestination,
                tourState: tourState,
                syncService: syncService,
                isInNavigationContext: true
            )
        }
    }

    private var iPhoneNavigation: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(visibleTabs, id: \.self) { tab in
                selectedTabContent(for: tab)
                    .tabItem {
                        Label(tabTitle(tab), systemImage: tabIcon(tab))
                    }
                    .tag(tab)
                    .badge(tab == .activity ? incomingFriendRequestCount : 0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if tuneInManager.isActive {
                TuneInMiniPlayerView(manager: tuneInManager)
            }
        }
        .sheet(isPresented: Binding(
            get: { tuneInManager.showExpandedPlayer },
            set: { tuneInManager.showExpandedPlayer = $0 }
        )) {
            TuneInExpandedPlayerView(manager: tuneInManager)
        }
        .tuneInCellularAlert(manager: tuneInManager)
        .tuneInStrategySheet(manager: tuneInManager)
        .tuneInErrorAlert(manager: tuneInManager)
        .toolbar(shouldHideTabBar ? .hidden : .visible, for: .tabBar)
        .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
            visibleTabs = TabConfiguration.visibleTabs()
            // Ensure selected tab is still visible
            if let selected = selectedTab, !visibleTabs.contains(selected) {
                selectedTab = visibleTabs.first
            }
        }
    }
}

// MARK: - Tab Content

extension ContentView {
    @ViewBuilder
    var selectedTabContent: some View {
        if let tab = selectedTab {
            selectedTabContent(for: tab)
        } else {
            Text("Select a tab")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var dashboardTabContent: some View {
        if let syncService {
            LazyTabContent(label: "dashboard") {
                DashboardView(
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: $selectedTab,
                    settingsDestination: $settingsDestination,
                    pendingMoreTabDestination: $pendingMoreTabDestination,
                    tourState: tourState
                )
            }
        } else {
            ProgressView()
        }
    }

    var loggerTabContent: some View {
        LazyTabContent(label: "logger") {
            SessionsTabView(
                tourState: tourState,
                potaClient: potaClient,
                potaAuth: potaAuthService,
                qrzClient: qrzClient,
                pendingHunterSpot: $pendingHunterSpot,
                pendingSpotlightSessionID: $pendingSpotlightSessionID,
                onSessionStateChange: { hasSession in
                    loggerHasActiveSession = hasSession
                }
            )
        }
    }

    var logsTabContent: some View {
        LazyTabContent(label: "logs") {
            LogsContainerView(
                potaClient: potaClient,
                potaAuth: potaAuthService,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                tourState: tourState,
                pendingSpotlightQSOID: $pendingSpotlightQSOID
            )
        }
    }

    var cwDecoderTabContent: some View {
        CWTranscriptionView(
            onLog: { callsign in
                UIPasteboard.general.string = callsign
                selectedTab = .logs
            }
        )
    }

    var mapTabContent: some View {
        NavigationStack { LazyTabContent(label: "map") { ParkSearchMapView(mapFilterState: mapFilterState) } }
    }

    var activityTabContent: some View {
        NavigationStack {
            LazyTabContent(label: "activity") {
                ActivityView(tourState: tourState, isInNavigationContext: false)
            }
        }
    }

    var remoteTabContent: some View {
        LazyTabContent(label: "remote") {
            RemoteSweepRootView()
                .environment(remoteSweepCoordinator)
        }
    }

    var satellitesTabContent: some View {
        NavigationStack {
            LazyTabContent(label: "satellites") { SatellitesRootView() }
        }
    }

    var moreTabContent: some View {
        MoreTabView(
            potaAuthService: potaAuthService,
            settingsDestination: $settingsDestination,
            pendingDeepLink: $pendingMoreTabDestination,
            mapFilterState: mapFilterState,
            tourState: tourState,
            syncService: syncService
        )
        .environment(remoteSweepCoordinator)
    }

    @ViewBuilder
    func selectedTabContent(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard: dashboardTabContent
        case .logger: loggerTabContent
        case .logs: logsTabContent
        case .cwDecoder: cwDecoderTabContent
        case .map: mapTabContent
        case .activity: activityTabContent
        case .remote: remoteTabContent
        case .satellites: satellitesTabContent
        case .more: moreTabContent
        }
    }

    func refreshFriendRequestCount() {
        // Friendships live in the Rust store, published by the shared service.
        incomingFriendRequestCount = FriendsSyncService.shared.incomingRequestCount
    }

    var restoreAlertMessage: String {
        guard let backup = restoredBackup else {
            return "Database restored from backup."
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Database restored from backup (\(fmt.string(from: backup.backupTimestamp))). "
            + "iCloud sync has been paused — review your data before re-enabling."
    }
}
