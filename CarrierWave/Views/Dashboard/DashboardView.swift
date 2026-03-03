import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @ObservedObject var iCloudMonitor: ICloudMonitor
    @ObservedObject var potaAuth: POTAAuthService
    @ObservedObject var syncService: SyncService
    @Binding var selectedTab: AppTab?
    @Binding var settingsDestination: SettingsDestination?
    @Binding var pendingMoreTabDestination: AppTab?
    let tourState: TourState
    @Binding var navigateToActivityLog: Bool

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassPOTAMaintenance = false

    // Activity log state
    @State var activityLogManager: ActivityLogManager?
    @State var showingActivityLogSetup = false

    // Sync state
    @State var isSyncing = false
    @State var syncingService: ServiceType?
    // QRZ state
    @State var qrzCallsign: String?
    @State var qrzIsConfigured: Bool = false

    // Service configuration state (refreshed on appear)
    @State var lofiIsConfigured: Bool = false
    @State var lofiIsLinked: Bool = false
    @State var lofiCallsign: String?
    @State var hamrsIsConfigured: Bool = false
    @State var lotwIsConfigured: Bool = false
    @State var clublogIsConfigured: Bool = false
    @State var clublogCallsign: String?

    /// Service detail sheet state
    @State var selectedService: ServiceIdentifier?

    /// Callsign alias detection state
    @State var unconfiguredCallsigns: Set<String> = []
    @State var showingCallsignAliasAlert = false

    /// POTA presence repair state
    @State var mismarkedPOTACount = 0
    @State var showingPOTARepairAlert = false

    /// Two-fer duplicate QSO repair state
    @State var twoferDuplicateCount = 0
    @State var showingTwoferRepairAlert = false

    /// PHONE/SSB duplicate QSO repair state
    @State var phoneSSBDuplicateCount = 0
    @State var showingPhoneSSBRepairAlert = false

    /// Progressive statistics - computes expensive stats in background for large datasets
    @State var asyncStats = AsyncQSOStatistics()

    /// Equipment usage statistics - computed in background from LoggingSession data
    @State var equipmentStats = AsyncEquipmentStats()

    /// Service presence counts - computed in background
    @State var presenceCounts = AsyncServicePresenceCounts()

    /// Brag sheet statistics - pre-computes all periods in background
    @State var bragSheetStats = AsyncBragSheetStats()

    let lofiClient = LoFiClient.appDefault()
    let qrzClient = QRZClient()
    let hamrsClient = HAMRSClient()
    let lotwClient = LoTWClient()
    let clublogClient = ClubLogClient()

    let aliasService = CallsignAliasService.shared

    var statsGridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 6 columns (all stats in one row)
            Array(repeating: GridItem(.flexible()), count: 6)
        } else {
            // iPhone: 3 columns (2 rows)
            Array(repeating: GridItem(.flexible()), count: 3)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasLoadedDashboard {
                    dashboardScrollContent
                } else {
                    // Widget deep link or first load: lightweight placeholder
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }
            }
            .task {
                // Create manager in .task (not .onAppear) so the first frame
                // commits without blocking on SwiftData fetches + Keychain reads.
                if activityLogManager == nil {
                    activityLogManager = ActivityLogManager(modelContext: modelContext)
                }

                if navigateToActivityLog {
                    // Widget deep link: yield so the first DashboardView frame
                    // commits before NavigationStack resolves the push destination.
                    // Without this, ActivityLogView construction blocks the first frame.
                    await Task.yield()
                    readyToNavigate = true
                } else {
                    loadDashboardFully()
                }
            }
            .onChange(of: navigateToActivityLog) { _, isNavigating in
                if isNavigating, activityLogManager == nil {
                    // Deep link arrived before .task — create manager for navigation
                    activityLogManager = ActivityLogManager(modelContext: modelContext)
                }
                if isNavigating {
                    // Defer push so current frame commits first
                    Task { @MainActor in
                        readyToNavigate = true
                    }
                }
                // User popped back from widget deep link — now load the dashboard
                if !isNavigating, !hasLoadedDashboard {
                    readyToNavigate = false
                    loadDashboardFully()
                }
            }
            .task(id: hasLoadedDashboard) {
                guard hasLoadedDashboard else {
                    return
                }
                // Compute stats and presence counts in background
                asyncStats.compute(from: modelContext)
                equipmentStats.compute(from: modelContext.container)
                presenceCounts.compute(from: modelContext)
                bragSheetStats.compute(from: modelContext.container)
            }
            .task(id: hasLoadedDashboard) {
                guard hasLoadedDashboard else {
                    return
                }
                // Check for callsign aliases after stats are computed (only once)
                guard !hasCheckedCallsignAliases else {
                    return
                }
                hasCheckedCallsignAliases = true
                try? await Task.sleep(for: .milliseconds(500))
                await checkForUnconfiguredCallsigns()
                await checkForMismarkedPOTAPresence()
                await checkForTwoferDuplicates()
                await backfillWPMIfNeeded()
                await backfillConditionsIfNeeded()
                await backfillCommentParkRefsIfNeeded()
                await repairHuntingParkRefsIfNeeded()
                await repairPOTAMidnightSplitIfNeeded()
                await repairKIndexIfNeeded()
                await repairActivityLogQSOsIfNeeded()
                await repairDuplicateQSOsIfNeeded()
                await repairDuplicatePresenceIfNeeded()
                await repairDuplicateSpotNotesIfNeeded()
                await repairPhoneSSBDuplicatesIfNeeded()
            }
            .onChange(of: syncService.lastSyncDate) { _, _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    asyncStats.recompute(from: modelContext)
                    equipmentStats.recompute(from: modelContext.container)
                    presenceCounts.recompute(from: modelContext)
                    bragSheetStats.recompute(from: modelContext.container)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didClearQSOs)) { _ in
                asyncStats.reset()
                equipmentStats.reset()
                presenceCounts.recompute(from: modelContext)
                asyncStats.compute(from: modelContext)
                equipmentStats.compute(from: modelContext.container)
                bragSheetStats.recompute(from: modelContext.container)
            }
            .callsignAliasDetectionAlert(
                unconfiguredCallsigns: $unconfiguredCallsigns,
                showingAlert: $showingCallsignAliasAlert,
                onAccept: { await addUnconfiguredCallsignsAsAliases() },
                onOpenSettings: {
                    selectedTab = .more
                    settingsDestination = nil
                }
            )
            .potaPresenceRepairAlert(
                mismarkedCount: $mismarkedPOTACount,
                showingAlert: $showingPOTARepairAlert,
                onRepair: { await repairMismarkedPOTAPresence() }
            )
            .twoferDuplicateRepairAlert(
                duplicateCount: $twoferDuplicateCount,
                showingAlert: $showingTwoferRepairAlert,
                onRepair: { await repairTwoferDuplicates() }
            )
            .phoneSSBDuplicateRepairAlert(
                duplicateCount: $phoneSSBDuplicateCount,
                showingAlert: $showingPhoneSSBRepairAlert,
                onRepair: { await performPhoneSSBDuplicateRepair() }
            )
            .syncImportConfirmationAlert(syncService: syncService)
            .syncExportConfirmationAlert(syncService: syncService)
            // Toolbar intentionally empty — sync trigger is in SyncCard
            .sheet(item: $selectedService) { service in
                serviceDetailSheet(for: service)
            }
            .sheet(isPresented: $showingActivityLogSetup) {
                ActivityLogSetupSheet(manager: activityLogManager)
            }
            .navigationDestination(isPresented: activityLogNavBinding) {
                if let manager = activityLogManager {
                    ActivityLogView(manager: manager)
                }
            }
        }
    }

    // MARK: Private

    /// Whether the full dashboard (cards, stats, services) has been loaded.
    /// False on widget cold start — only the navigation destination renders.
    @State private var hasLoadedDashboard = false

    /// Track whether we've already run the one-time checks (callsign aliases, POTA repair)
    /// to avoid re-running expensive queries on every tab switch
    @State private var hasCheckedCallsignAliases = false

    /// Deferred navigation flag — set after a yield so the first DashboardView
    /// frame commits before NavigationStack resolves the push destination.
    @State private var readyToNavigate = false

    /// Gate navigation on manager readiness AND deferred flag — prevents
    /// NavigationStack from pushing during initial layout.
    private var activityLogNavBinding: Binding<Bool> {
        Binding(
            get: { readyToNavigate && activityLogManager != nil },
            set: { newValue in
                navigateToActivityLog = newValue
                if !newValue {
                    readyToNavigate = false
                }
            }
        )
    }

    /// The full dashboard ScrollView with all cards.
    private var dashboardScrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if verticalSizeClass == .compact {
                    combinedStreaksAndStatsCard
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            activityCard
                            activityLogCard
                            friendsOnAirCard
                            friendActivityCard
                            conditionsCard
                            contestsCard
                            callsignLookupCard
                        }
                        VStack(spacing: 16) {
                            bragSheetEntryCard
                            favoritesCard
                            equipmentCard
                            syncCard
                        }
                    }
                } else {
                    activityCard
                    activityLogCard
                    friendsOnAirCard
                    friendActivityCard
                    streaksCard
                    summaryCard
                    bragSheetEntryCard
                    favoritesCard
                    equipmentCard
                    conditionsCard
                    contestsCard
                    callsignLookupCard
                    syncCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // Activity card is in DashboardView+ActivityLog.swift

    /// Load the full dashboard: Keychain reads, service status, stats.
    /// Skipped on widget cold start, runs when user pops back or on normal launch.
    private func loadDashboardFully() {
        guard !hasLoadedDashboard else {
            return
        }
        loadQRZConfig()
        refreshServiceStatus()
        hasLoadedDashboard = true
    }
}

// Stats grid and streak row are in DashboardView+Stats.swift

// Services list and detail sheets are in DashboardView+Services.swift
// Action methods are in DashboardView+Actions.swift
// Helper views are in DashboardHelperViews.swift
