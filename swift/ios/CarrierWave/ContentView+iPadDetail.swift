import CarrierWaveData
import SwiftUI

// MARK: - iPad Detail Content

/// iPad-specific detail content that skips inner NavigationStack wrappers,
/// preventing a UINavigationBar assertion crash when the system takes a
/// snapshot during adaptive layout transitions.
///
/// When the app goes to background on iPad, UIKit snapshots the window.
/// This triggers the split view's adaptive layout transition, which
/// repositions the UINavigationBar. Nested UINavigationControllers
/// (from inner NavigationStacks in detail content) cause an assertion
/// failure in `-[UINavigationBar layoutSubviews]`. By passing
/// `isInNavigationContext: true` to child views, they skip their own
/// NavigationStack and rely on NavigationSplitView's navigation context.
extension ContentView {
    @ViewBuilder
    var iPadSelectedTabContent: some View {
        if let tab = selectedTab {
            iPadTabContent(for: tab)
        } else {
            Text("Select a tab")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func iPadTabContent(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard: iPadDashboard
        case .logger: iPadLogger
        case .logs: iPadLogs
        case .cwDecoder: iPadCWDecoder
        case .map: iPadMap
        case .activity: iPadActivity
        case .remote: remoteTabContent
        case .satellites: iPadSatellites
        case .more: moreTabContent
        }
    }

    // MARK: - Per-Tab iPad Builders

    @ViewBuilder
    private var iPadDashboard: some View {
        if let syncService {
            LazyTabContent(label: "dashboard") {
                DashboardView(
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    isInNavigationContext: true,
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

    private var iPadLogger: some View {
        LazyTabContent(label: "logger") {
            SessionsTabView(
                tourState: tourState,
                potaClient: potaClient,
                potaAuth: potaAuthService,
                qrzClient: qrzClient,
                isInNavigationContext: true,
                pendingHunterSpot: $pendingHunterSpot,
                pendingSpotlightSessionID: $pendingSpotlightSessionID,
                onSessionStateChange: { hasSession in
                    loggerHasActiveSession = hasSession
                }
            )
        }
    }

    private var iPadLogs: some View {
        LazyTabContent(label: "logs") {
            LogsContainerView(
                potaClient: potaClient,
                potaAuth: potaAuthService,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                tourState: tourState,
                isInNavigationContext: true,
                pendingSpotlightQSOID: $pendingSpotlightQSOID
            )
        }
    }

    private var iPadCWDecoder: some View {
        CWTranscriptionView(
            isInNavigationContext: true,
            onLog: { callsign in
                UIPasteboard.general.string = callsign
                selectedTab = .logs
            }
        )
    }

    private var iPadMap: some View {
        LazyTabContent(label: "map") {
            ParkSearchMapView(mapFilterState: mapFilterState)
        }
    }

    private var iPadActivity: some View {
        LazyTabContent(label: "activity") {
            ActivityView(tourState: tourState, isInNavigationContext: true)
        }
    }

    private var iPadSatellites: some View {
        LazyTabContent(label: "satellites") {
            SatellitesRootView()
        }
    }
}
