import SwiftData
import SwiftUI

// MARK: - AppTab

enum AppTab: String, Hashable, CaseIterable, Codable {
    case dashboard
    case logger
    case logs
    case cwDecoder
    case map
    case activity
    case more

    // MARK: Internal

    /// Tabs that can be reordered/hidden by the user
    /// Note: cwDecoder is intentionally excluded - feature is disabled
    static var configurableTabs: [AppTab] {
        [.dashboard, .logger, .logs, .map, .activity]
    }

    /// Default tab order
    static var defaultOrder: [AppTab] {
        [.dashboard, .logger, .logs, .cwDecoder, .map, .activity, .more]
    }

    /// Default hidden tabs (not shown in tab bar initially)
    static var defaultHidden: Set<AppTab> {
        [.logger, .cwDecoder, .activity]
    }

    /// Tabs that are completely disabled and should never appear anywhere
    /// These are filtered out from all tab lists
    static var disabledTabs: Set<AppTab> {
        [.cwDecoder]
    }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .logger: "Logger"
        case .logs: "Logs"
        case .cwDecoder: "CW"
        case .map: "Map"
        case .activity: "Activity"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .logger: "pencil.and.list.clipboard"
        case .logs: "list.bullet"
        case .cwDecoder: "waveform"
        case .map: "map"
        case .activity: "person.2"
        case .more: "ellipsis"
        }
    }

    var description: String {
        switch self {
        case .dashboard: "QSO statistics and sync status"
        case .logger: "Log QSOs during activations"
        case .logs: "View and search logged QSOs"
        case .cwDecoder: "CW transcription and decoding"
        case .map: "QSO locations on a map"
        case .activity: "Friends, clubs, and activity feed"
        case .more: "Settings and hidden tabs"
        }
    }
}

// MARK: - TabConfiguration

/// Manages tab visibility and ordering
enum TabConfiguration {
    // MARK: Internal

    /// Get the ordered list of visible tabs
    static func visibleTabs() -> [AppTab] {
        let order = tabOrder()
        let hidden = hiddenTabs()
        return order.filter { !hidden.contains($0) && !AppTab.disabledTabs.contains($0) }
    }

    /// Get the current tab order (including hidden tabs, but excluding disabled tabs)
    static func tabOrder() -> [AppTab] {
        guard let data = UserDefaults.standard.data(forKey: orderKey),
              let order = try? JSONDecoder().decode([AppTab].self, from: data)
        else {
            return AppTab.defaultOrder.filter { !AppTab.disabledTabs.contains($0) }
        }
        // Ensure all tabs are present (in case new tabs were added)
        // Filter out disabled tabs
        var result = order.filter {
            AppTab.allCases.contains($0) && !AppTab.disabledTabs.contains($0)
        }
        for tab in AppTab.defaultOrder
            where !result.contains(tab) && !AppTab.disabledTabs.contains(tab)
        {
            if tab == .more {
                result.append(tab)
            } else {
                result.insert(tab, at: max(0, result.count - 1))
            }
        }
        return result
    }

    /// Get hidden tabs (excludes disabled tabs which shouldn't appear anywhere)
    static func hiddenTabs() -> Set<AppTab> {
        // Check if user has ever configured tabs
        guard UserDefaults.standard.data(forKey: hiddenKey) != nil else {
            // First launch: use default hidden tabs (minus disabled ones)
            return AppTab.defaultHidden.subtracting(AppTab.disabledTabs)
        }
        guard let data = UserDefaults.standard.data(forKey: hiddenKey),
              let hidden = try? JSONDecoder().decode([AppTab].self, from: data)
        else {
            return AppTab.defaultHidden.subtracting(AppTab.disabledTabs)
        }
        // Filter out disabled tabs - they shouldn't appear even in hidden list
        return Set(hidden).subtracting(AppTab.disabledTabs)
    }

    /// Save tab order
    static func saveOrder(_ order: [AppTab]) {
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: orderKey)
        }
    }

    /// Save hidden tabs
    static func saveHidden(_ hidden: Set<AppTab>) {
        if let data = try? JSONEncoder().encode(Array(hidden)) {
            UserDefaults.standard.set(data, forKey: hiddenKey)
        }
    }

    /// Check if a specific tab is enabled
    static func isTabEnabled(_ tab: AppTab) -> Bool {
        !hiddenTabs().contains(tab)
    }

    /// Set whether a tab is enabled
    static func setTabEnabled(_ tab: AppTab, enabled: Bool) {
        var hidden = hiddenTabs()
        if enabled {
            hidden.remove(tab)
        } else {
            hidden.insert(tab)
        }
        saveHidden(hidden)
    }

    /// Move a tab from one position to another
    static func moveTab(from source: Int, to destination: Int) {
        var order = tabOrder()
        let tab = order.remove(at: source)
        order.insert(tab, at: destination)
        saveOrder(order)
    }

    /// Reset to defaults
    static func reset() {
        UserDefaults.standard.removeObject(forKey: orderKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }

    // MARK: Private

    private static let orderKey = "tabOrder"
    private static let hiddenKey = "hiddenTabs"
}

// MARK: - SettingsDestination

enum SettingsDestination: Hashable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw
    case icloud
}

// MARK: - Notifications

extension Notification.Name {
    static let tabConfigurationChanged = Notification.Name("tabConfigurationChanged")
}

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

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadNavigation
            } else {
                iPhoneNavigation
            }
        }
        .onAppear {
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
        .onChange(of: selectedTab) { _, _ in
            // Reset navigation paths when switching tabs to avoid stale submenu state
            moreTabNavigationPath = NavigationPath()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @StateObject private var iCloudMonitor = ICloudMonitor()
    @StateObject private var potaAuthService = POTAAuthService()
    @State private var selectedTab: AppTab? = .dashboard
    @State private var settingsDestination: SettingsDestination?
    @State private var syncService: SyncService?
    @State private var potaClient: POTAClient?
    @State private var showIntroTour = false
    @State private var showOnboarding = false
    @State private var moreTabNavigationPath = NavigationPath()
    @State private var visibleTabs: [AppTab] = TabConfiguration.visibleTabs()
    @State private var iPadTabs: [AppTab] = TabConfiguration.tabOrder()
    @State private var mapFilterState = MapFilterState()

    private let lofiClient = LoFiClient()
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

    // MARK: - iPad Navigation (Sidebar)

    private var iPadNavigation: some View {
        NavigationSplitView {
            // iPad shows all tabs in sidebar (plenty of room)
            List(iPadTabs, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .navigationTitle("Carrier Wave")
        } detail: {
            selectedTabContent
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
            // Update tab order (iPad shows all tabs, just respects order)
            iPadTabs = TabConfiguration.tabOrder()
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
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
            visibleTabs = TabConfiguration.visibleTabs()
            // Ensure selected tab is still visible
            if let selected = selectedTab, !visibleTabs.contains(selected) {
                selectedTab = visibleTabs.first
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var selectedTabContent: some View {
        if let tab = selectedTab {
            selectedTabContent(for: tab)
        } else {
            Text("Select a tab")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dashboardTabContent: some View {
        if let syncService {
            LazyTabContent {
                DashboardView(
                    iCloudMonitor: iCloudMonitor,
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: $selectedTab,
                    settingsDestination: $settingsDestination,
                    tourState: tourState
                )
            }
        } else {
            ProgressView()
        }
    }

    private var loggerTabContent: some View {
        LoggerView(
            tourState: tourState,
            onSessionEnd: {
                selectedTab = .logs
            }
        )
    }

    private var logsTabContent: some View {
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

    private var cwDecoderTabContent: some View {
        CWTranscriptionView(
            onLog: { callsign in
                UIPasteboard.general.string = callsign
                selectedTab = .logs
            }
        )
    }

    private var mapTabContent: some View {
        NavigationStack {
            LazyTabContent {
                QSOMapView(filterState: mapFilterState)
            }
        }
    }

    private var activityTabContent: some View {
        NavigationStack {
            LazyTabContent {
                ActivityView(tourState: tourState, isInNavigationContext: false)
            }
        }
    }

    private var moreTabContent: some View {
        MoreTabView(
            potaAuthService: potaAuthService,
            settingsDestination: $settingsDestination,
            navigationPath: $moreTabNavigationPath,
            mapFilterState: mapFilterState,
            tourState: tourState,
            syncService: syncService
        )
    }

    @ViewBuilder
    private func selectedTabContent(for tab: AppTab) -> some View {
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
}

#Preview {
    ContentView(tourState: TourState())
        .modelContainer(
            for: [QSO.self, ServicePresence.self, UploadDestination.self, POTAUploadAttempt.self],
            inMemory: true
        )
}
