import CarrierWaveData
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

    var potaAuthService: POTAAuthService
    @Binding var settingsDestination: SettingsDestination?
    @Binding var pendingDeepLink: AppTab?
    @Bindable var mapFilterState: MapFilterState

    let tourState: TourState
    let syncService: SyncService?

    var body: some View {
        NavigationStack {
            List {
                // Show hidden configurable tabs
                if !hiddenTabs.isEmpty {
                    Section {
                        ForEach(hiddenTabs, id: \.self) { tab in
                            NavigationLink {
                                LazyView { tabContent(for: tab) }
                            } label: {
                                Label(tab.title, systemImage: tab.icon)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        LazyView { ExploreView() }
                    } label: {
                        Label("Explore Features", systemImage: "sparkles")
                    }

                    if ExperimentalFeature.isEnabled(.propagationCheck) {
                        NavigationLink {
                            LazyView { PropagationCheckRootView() }
                        } label: {
                            HStack {
                                Label("Propagation Check", systemImage: "dot.radiowaves.up.forward")
                                Spacer()
                                ExperimentalBadge(feature: .propagationCheck)
                            }
                        }
                    }
                } header: {
                    Text("Discover")
                }

                Section {
                    NavigationLink {
                        LazyView { settingsContent }
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationDestination(item: $pendingDeepLink) { tab in
                LazyView { tabContent(for: tab) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
            updateHiddenTabs()
        }
        .onAppear {
            updateHiddenTabs()
        }
    }

    // MARK: Private

    @State private var hiddenTabs: [AppTab] = TabConfiguration.tabsForMoreList()

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
            ParkSearchMapView(mapFilterState: mapFilterState)
        case .activity:
            ActivityView(tourState: tourState, isInNavigationContext: true)
        case .dashboard:
            // Dashboard needs sync service, show placeholder if not available
            if let syncService {
                DashboardView(
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: .constant(.dashboard),
                    settingsDestination: $settingsDestination,
                    pendingMoreTabDestination: .constant(nil),
                    tourState: tourState
                )
            } else {
                Text("Dashboard unavailable")
            }
        case .logger:
            SessionsTabView(
                tourState: tourState,
                potaClient: nil,
                potaAuth: potaAuthService,
                qrzClient: nil,
                pendingHunterSpot: .constant(nil),
                pendingSpotlightSessionID: .constant(nil)
            )
        case .logs:
            LogsContainerView(
                potaClient: nil,
                potaAuth: potaAuthService,
                lofiClient: LoFiClient.appDefault(),
                qrzClient: QRZClient(),
                hamrsClient: HAMRSClient(),
                lotwClient: LoTWClient(),
                tourState: tourState,
                isInNavigationContext: true,
                pendingSpotlightQSOID: .constant(nil)
            )
        case .cwDecoder:
            CWTranscriptionView(onLog: { _ in })
        case .remote:
            // Hosted here too (not just as a first-class tab): the shared
            // coordinator is injected by ContentView around MoreTabView.
            RemoteSweepRootView()
        case .satellites:
            SatellitesRootView()
        case .more:
            EmptyView()
        }
    }

    private func updateHiddenTabs() {
        // Includes both explicitly hidden tabs and overflow tabs that
        // don't fit on the tab bar (capped at TabConfiguration.maxTabBarTabs).
        hiddenTabs = TabConfiguration.tabsForMoreList()
    }
}
