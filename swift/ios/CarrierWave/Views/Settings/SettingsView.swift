import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SettingsMainView

struct SettingsMainView: View {
    // MARK: Internal

    var potaAuth: POTAAuthService
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
    @State var showingSendDiagnostics = false
    @State var showIntroTour = false
    @State var showOnboarding = false
    @State var showWhatsNew = false
    @State var userProfile: UserProfile?
    @State var pendingCallsignChange: PendingCallsignChange?

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassPOTAMaintenance = false
    @AppStorage("cwswlServerURL") var cwswlServerURL = "https://swl.carrierwave.app"
    @AppStorage("activitiesServerURLOverride") var activitiesServerURL = ""
    @AppStorage("startupProfilerEnabled") var startupProfilerEnabled = false

    let lofiClient = LoFiClient.appDefault()

    var searchResults: [SettingsSearchItem] {
        SettingsSearchIndex.search(
            query: searchText,
            debugMode: debugMode
        )
    }

    var body: some View {
        if isInNavigationContext {
            settingsListContent
        } else {
            NavigationStack(path: $navigationPath) {
                settingsListContent
                    .navigationDestination(
                        for: SettingsDestination.self
                    ) { dest in
                        settingsDestinationView(for: dest)
                    }
                    .task(id: destination) {
                        guard let dest = destination else {
                            return
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        navigationPath.append(dest)
                        destination = nil
                    }
            }
        }
    }

    // MARK: Private

    /// The settings List with sections and modifiers shared by both
    /// standalone and embedded navigation contexts.
    private var settingsListContent: some View {
        List {
            if searchText.isEmpty {
                profileSection
                accountDataSection
                servicesSection
                featuresSection
                hardwareSection
                generalSection
                developerSection
                helpSection
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
        .onAppear {
            userProfile = UserProfileService.shared.getProfile()
            pendingCallsignChange = CallsignChangeGuide.shared.pending
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
                    + "If iCloud QSO Sync is enabled, your logbook will "
                    + "be re-downloaded from iCloud immediately. Disable "
                    + "sync first if you want a clean wipe."
            )
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportView(
                syncService: syncService,
                potaAuth: potaAuth,
                showSendDiagnostics: $showingSendDiagnostics
            )
        }
        .sheet(isPresented: $showingSendDiagnostics) {
            SendDiagnosticsView(
                showingSendDiagnostics: $showingSendDiagnostics
            )
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet(entries: WhatsNewCatalog.entries.filter {
                $0.platforms.contains(.iOS)
            }) {
                showWhatsNew = false
            }
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(tourState: tourState)
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if !isShowing {
                userProfile = UserProfileService.shared.getProfile()
            }
        }
    }

    /// Destination view for programmatic deep-link navigation
    @ViewBuilder
    private func settingsDestinationView(
        for dest: SettingsDestination
    ) -> some View {
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
            ClubLogSettingsView()
        case .eqsl:
            EQSLSettingsView()
        case .icloud:
            CloudSyncSettingsView()
        case .tota:
            TOTASettingsView()
        }
    }
}
