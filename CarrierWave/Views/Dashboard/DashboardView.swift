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
    @State var lastSyncDate: Date?
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
            .onAppear {
                // Always create manager (needed for widget deep link navigation)
                if activityLogManager == nil {
                    activityLogManager = ActivityLogManager(modelContext: modelContext)
                }
            }
            .task {
                // Brief delay so widget deep link URL can propagate on cold start.
                // onOpenURL fires after initial view setup, so navigateToActivityLog
                // may still be false in .onAppear even on a widget launch.
                try? await Task.sleep(for: .milliseconds(100))
                if !navigateToActivityLog {
                    loadDashboardFully()
                }
            }
            .onChange(of: navigateToActivityLog) { _, isNavigating in
                // User popped back from widget deep link — now load the dashboard
                if !isNavigating, !hasLoadedDashboard {
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if hasLoadedDashboard {
                        toolbarButtons
                    }
                }
            }
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

    /// Gate navigation on manager readiness — prevents NavigationStack corruption
    /// when a widget deep link sets `navigateToActivityLog = true` before
    /// `activityLogManager` is created in `.onAppear`.
    private var activityLogNavBinding: Binding<Bool> {
        Binding(
            get: { navigateToActivityLog && activityLogManager != nil },
            set: { navigateToActivityLog = $0 }
        )
    }

    /// The full dashboard ScrollView with all cards.
    private var dashboardScrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if syncService.isSyncing {
                    SyncProgressCard(syncService: syncService)
                }
                if verticalSizeClass == .compact {
                    combinedStreaksAndStatsCard
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            activityCard
                            activityLogCard
                            friendsOnAirCard
                            friendActivityCard
                            conditionsCard
                        }
                        VStack(spacing: 16) {
                            bragSheetEntryCard
                            favoritesCard
                            equipmentCard
                            servicesList
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
                    servicesList
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Toolbar

    private var toolbarButtons: some View {
        HStack(spacing: 12) {
            if debugMode, !isSyncing {
                Button {
                    Task { await performDownloadOnly() }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .accessibilityLabel("Download only")
            }

            Button {
                Task { await performFullSync() }
            } label: {
                if isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)
            .accessibilityLabel("Sync all services")
        }
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Text("\(asyncStats.totalQSOs) QSOs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActivityGrid(
                activationData: asyncStats.activationActivityByDate,
                activityLogData: asyncStats.activityLogActivityByDate
            )

            // Show progress bar while computing
            if asyncStats.isComputing {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: asyncStats.progress)
                        .tint(.blue)
                    if !asyncStats.progressPhase.isEmpty {
                        Text(asyncStats.progressPhase)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: asyncStats.isComputing)
    }

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
