import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SettingsMainView

struct SettingsMainView: View {
    // MARK: Internal

    @ObservedObject var potaAuth: POTAAuthService
    @Binding var destination: SettingsDestination?

    let tourState: TourState
    var syncService: SyncService?

    /// When true, the view is already inside a navigation context (e.g., "More" tab)
    /// and should not add its own NavigationStack
    var isInNavigationContext: Bool = false

    // MARK: - State (accessible to extensions)

    @Environment(\.modelContext) var modelContext

    @State var navigationPath = NavigationPath()
    @State var searchText = ""
    @State var showingClearAllConfirmation = false
    @State var isClearingQSOs = false
    @State var showingError = false
    @State var errorMessage = ""
    @State var showingBugReport = false
    @State var showIntroTour = false
    @State var showOnboarding = false
    @State var userProfile: UserProfile?

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("readOnlyMode") var readOnlyMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassPOTAMaintenance = false
    @AppStorage("cwswlServerURL") var cwswlServerURL = "https://swl.carrierwave.app"

    @StateObject var iCloudMonitor = ICloudMonitor()

    let lofiClient = LoFiClient.appDefault()

    var searchResults: [SettingsSearchItem] {
        SettingsSearchIndex.search(
            query: searchText,
            debugMode: debugMode
        )
    }

    var body: some View {
        if isInNavigationContext {
            settingsContent
        } else {
            NavigationStack(path: $navigationPath) {
                settingsContent
            }
        }
    }

    // MARK: Private

    private var settingsContent: some View {
        List {
            if searchText.isEmpty {
                profileSection
                appearanceSection
                loggingSection
                syncDataSection
                developerSection
                aboutSection
            } else {
                SettingsSearchResultsView(
                    results: searchResults
                ) { dest in
                    searchDestinationView(for: dest)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search settings")
        .navigationDestination(for: SettingsDestination.self) { dest in
            switch dest {
            case .qrz:
                QRZSettingsView(syncService: syncService)
            case .pota:
                POTASettingsView(
                    potaAuth: potaAuth,
                    tourState: tourState,
                    syncService: syncService
                )
            case .lofi:
                LoFiSettingsView(
                    tourState: tourState,
                    syncService: syncService
                )
            case .hamrs:
                HAMRSSettingsView(syncService: syncService)
            case .lotw:
                LoTWSettingsView(syncService: syncService)
            case .clublog:
                ClubLogSettingsView(syncService: syncService)
            case .icloud:
                CloudSyncSettingsView()
            }
        }
        .onAppear {
            userProfile = UserProfileService.shared.getProfile()
        }
        .task(id: destination) {
            guard let dest = destination else {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            navigationPath.append(dest)
            destination = nil
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert(
            "Clear All QSOs?",
            isPresented: $showingClearAllConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                Task { await clearAllQSOs() }
            }
        } message: {
            Text(
                "This will permanently delete all QSOs from this device. "
                    + "This cannot be undone."
            )
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportView(
                syncService: syncService,
                potaAuth: potaAuth,
                iCloudMonitor: iCloudMonitor
            )
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(tourState: tourState, potaAuth: potaAuth)
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if !isShowing {
                userProfile = UserProfileService.shared.getProfile()
            }
        }
    }
}
