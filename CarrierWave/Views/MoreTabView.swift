import CarrierWaveCore
import SwiftUI

// MARK: - LazyView

/// Defers view initialization until the view actually appears.
/// Used to prevent NavigationLink destinations from triggering @Query
/// or other expensive initializations when building the parent view.
private struct LazyView<Content: View>: View {
    // MARK: Lifecycle

    init(_ build: @escaping () -> Content) {
        self.build = build
    }

    // MARK: Internal

    let build: () -> Content

    var body: some View {
        build()
    }
}

// MARK: - MoreTabView

/// A custom "More" tab that shows hidden tabs and Settings
/// in a single NavigationStack to avoid nested navigation issues.
struct MoreTabView: View {
    // MARK: Internal

    @ObservedObject var potaAuthService: POTAAuthService
    @Binding var settingsDestination: SettingsDestination?
    @Binding var navigationPath: NavigationPath
    @Bindable var mapFilterState: MapFilterState

    let tourState: TourState
    let syncService: SyncService?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                // Show hidden configurable tabs
                if !hiddenTabs.isEmpty {
                    Section {
                        ForEach(hiddenTabs, id: \.self) { tab in
                            NavigationLink {
                                // Use LazyView to defer view initialization until navigation.
                                // This prevents @Query and other expensive initializations
                                // from running when MoreTabView is first displayed.
                                LazyView { tabContent(for: tab) }
                            } label: {
                                Label(tab.title, systemImage: tab.icon)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        LazyView { settingsContent }
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .navigationTitle("More")
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
            updateHiddenTabs()
        }
        .onAppear {
            updateHiddenTabs()
        }
    }

    // MARK: Private

    @State private var hiddenTabs: [AppTab] = []

    private var settingsContent: some View {
        SettingsMainView(
            potaAuth: potaAuthService,
            destination: $settingsDestination,
            tourState: tourState,
            syncService: syncService,
            isInNavigationContext: true
        )
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .map:
            QSOMapView(filterState: mapFilterState)
        case .activity:
            ActivityView(tourState: tourState, isInNavigationContext: true)
        case .dashboard:
            // Dashboard needs sync service, show placeholder if not available
            if let syncService {
                DashboardView(
                    iCloudMonitor: ICloudMonitor(),
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: .constant(.dashboard),
                    settingsDestination: $settingsDestination,
                    tourState: tourState,
                    navigateToActivityLog: .constant(false)
                )
            } else {
                Text("Dashboard unavailable")
            }
        case .logger:
            LoggerView(tourState: tourState, onSessionEnd: {})
        case .logs:
            LogsContainerView(
                potaClient: nil,
                potaAuth: potaAuthService,
                lofiClient: LoFiClient.appDefault(),
                qrzClient: QRZClient(),
                hamrsClient: HAMRSClient(),
                lotwClient: LoTWClient(),
                tourState: tourState
            )
        case .cwDecoder:
            CWTranscriptionView(onLog: { _ in })
        case .more:
            EmptyView()
        }
    }

    private func updateHiddenTabs() {
        let hidden = TabConfiguration.hiddenTabs()
        let order = TabConfiguration.tabOrder()
        // Get configurable tabs that are hidden, in their configured order
        hiddenTabs = order.filter { tab in
            tab != .more && hidden.contains(tab)
        }
    }
}
