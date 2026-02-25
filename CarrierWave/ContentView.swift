import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - LazyTabContent

/// Defers content creation until the view appears, improving tab switch performance.
/// Shows a brief loading indicator on first appearance.
struct LazyTabContent<Content: View>: View {
    // MARK: Internal

    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if hasAppeared {
                content()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
            }
        }
    }

    // MARK: Private

    @State private var hasAppeared = false
}

// MARK: - ContentView

struct ContentView: View {
    // MARK: Internal

    let tourState: TourState
    var restoredBackup: PendingRestore?

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var body: some View {
        Group {
            if (lockedSizeClass ?? horizontalSizeClass) == .regular {
                iPadNavigation
            } else {
                iPhoneNavigation
            }
        }
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
            iCloudMonitor.startMonitoring()
            if syncService == nil {
                syncService = SyncService(
                    modelContext: modelContext,
                    potaAuthService: potaAuthService
                )
            }
            if potaClient == nil {
                potaClient = POTAClient(authService: potaAuthService)
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
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveADIFFile)) { notification in
            if let url = notification.object as? URL {
                // Handle import - for now just print
                print("Received ADIF file: \(url.lastPathComponent)")
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveChallengeInvite)
        ) { notification in
            guard let userInfo = notification.userInfo,
                  userInfo["source"] is String,
                  userInfo["challengeId"] is UUID
            else {
                return
            }
            // Navigate to More tab (Activity is now within More)
            selectedTab = .more
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveWidgetDeepLink)
        ) { notification in
            guard let target = notification.userInfo?["target"] as? String else {
                return
            }
            switch target {
            case "activitylog":
                selectedTab = .dashboard
                pendingActivityLogNavigation = true
            case "dashboard":
                selectedTab = .dashboard
            case "logger":
                selectedTab = .logger
            default:
                break
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveWatchStartSession)
        ) { _ in
            // Navigate to logger tab — session manager will pick up the request
            selectedTab = .logger
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(tourState: tourState, potaAuth: potaAuthService)
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
        }
    }

    // MARK: Private

    /// Locked layout mode — set once on first appearance, never changes.
    /// Prevents size class transitions (e.g., orientation change on iPad or iPhone Max)
    /// from destroying the entire view hierarchy and resetting @State in child views.
    @State private var lockedSizeClass: UserInterfaceSizeClass?

    @Environment(\.modelContext) private var modelContext
    @StateObject private var iCloudMonitor = ICloudMonitor()
    @StateObject private var potaAuthService = POTAAuthService()
    @State private var selectedTab: AppTab? = .dashboard
    @State private var settingsDestination: SettingsDestination?
    @State private var syncService: SyncService?
    @State private var potaClient: POTAClient?
    @State private var showIntroTour = false
    @State private var showOnboarding = false
    @State private var pendingMoreTabDestination: AppTab?
    @State private var visibleTabs: [AppTab] = TabConfiguration.visibleTabs()
    @State private var iPadTabs: [AppTab] = TabConfiguration.iPadVisibleTabs()
    @State private var iPadShowsSettings = false
    @State private var mapFilterState = MapFilterState()
    @State private var pendingActivityLogNavigation = false
    @State private var loggerHasActiveSession = false
    @State private var showingRestoreAlert = false

    @Query(
        filter: #Predicate<Friendship> { $0.statusRawValue == "pending" && $0.isOutgoing == false }
    )
    private var incomingFriendRequests: [Friendship]

    private let lofiClient = LoFiClient.appDefault()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()

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
                    Label(tab.title, systemImage: tab.icon)
                        .badge(tab == .activity ? incomingFriendRequests.count : 0)
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
            .navigationTitle("Carrier Wave")
            .onChange(of: selectedTab) { _, newValue in
                if newValue != nil {
                    iPadShowsSettings = false
                }
            }
        } detail: {
            if iPadShowsSettings {
                iPadSettingsContent
            } else {
                selectedTabContent
            }
        }
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
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
                    .badge(tab == .activity ? incomingFriendRequests.count : 0)
            }
        }
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
            LazyTabContent {
                DashboardView(
                    iCloudMonitor: iCloudMonitor,
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: $selectedTab,
                    settingsDestination: $settingsDestination,
                    pendingMoreTabDestination: $pendingMoreTabDestination,
                    tourState: tourState,
                    navigateToActivityLog: $pendingActivityLogNavigation
                )
            }
        } else {
            ProgressView()
        }
    }

    var loggerTabContent: some View {
        SessionsTabView(
            tourState: tourState,
            potaClient: potaClient,
            potaAuth: potaAuthService,
            onSessionStateChange: { hasSession in
                loggerHasActiveSession = hasSession
            }
        )
    }

    var logsTabContent: some View {
        LazyTabContent {
            LogsContainerView(
                potaClient: potaClient,
                potaAuth: potaAuthService,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                tourState: tourState
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
        NavigationStack {
            LazyTabContent {
                QSOMapView(filterState: mapFilterState)
            }
        }
    }

    var activityTabContent: some View {
        NavigationStack {
            LazyTabContent {
                ActivityView(tourState: tourState, isInNavigationContext: false)
            }
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
        case .more: moreTabContent
        }
    }

    var restoreAlertMessage: String {
        guard let backup = restoredBackup else {
            return "Database restored from backup."
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Database restored from backup "
            + "(\(formatter.string(from: backup.backupTimestamp))). "
            + "iCloud sync has been paused "
            + "— review your data before re-enabling."
    }
}

#Preview {
    ContentView(tourState: TourState(), restoredBackup: nil)
        .modelContainer(
            for: [QSO.self, ServicePresence.self, UploadDestination.self, POTAUploadAttempt.self],
            inMemory: true
        )
}
