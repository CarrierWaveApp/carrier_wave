import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    var potaAuth: POTAAuthService
    var syncService: SyncService
    var isInNavigationContext: Bool = false
    var cloudSyncService = CloudSyncService.shared
    @Binding var selectedTab: AppTab?
    @Binding var settingsDestination: SettingsDestination?
    @Binding var pendingMoreTabDestination: AppTab?
    let tourState: TourState

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassPOTAMaintenance = false
    @AppStorage(DashboardLayoutPrefs.hiddenCardsKey) var hiddenCards = ""
    @AppStorage(DashboardLayoutPrefs.collapsedSectionsKey) var collapsedSections = ""

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
    @State var eqslIsConfigured: Bool = false
    @State var eqslUsername: String?

    /// Service detail sheet state
    @State var selectedService: ServiceIdentifier?

    /// Dashboard customize sheet
    @State var showingCustomizeSheet = false

    /// Aggregate sync report sheet
    @State var showingSyncReport = false

    /// Needs detail sheet
    @State var showingNeedsDetail = false

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

    /// Needs snapshot — computed in background from QSO data
    @State var needsSnapshot = NeedsSnapshot.empty

    /// On-air needs summary — updated when hunter spots are matched
    @State var needsOnAirSummary = NeedsOnAirSummary.empty

    /// Guard against re-running needs computation on every tab switch.
    @State var hasComputedNeeds = false

    /// Bumped when experiment toggles change so dashboard card visibility updates.
    @State var experimentRefreshID = UUID()

    /// Whether the full dashboard (cards, stats, services) has been loaded.
    /// False on widget cold start — only the navigation destination renders.
    @State var hasLoadedDashboard = false

    /// Track whether we've already run the one-time checks (callsign aliases, POTA repair)
    /// to avoid re-running expensive queries on every tab switch
    @State var hasCheckedCallsignAliases = false

    /// Guard against duplicate stats pipeline execution.
    /// SwiftUI can re-fire `.task(id:)` on view re-appear (tab switch back)
    /// and during initial layout (double-evaluation). Tab-switch recomputes
    /// are handled by `.onChange(of: selectedTab)` with generation guards.
    @State var hasRunStatsPipeline = false

    /// CAR-244: coalesces sync-driven recomputes. CloudKit can fire many
    /// `lastSyncDate` updates per second during a batch sync; without this we
    /// run four full QSO-table scans per tick and write the App-Group widget
    /// plist on each — sustained 60–133 MB/s disk writes in TestFlight.
    @State var syncRecomputeTask: Task<Void, Never>?

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
        if isInNavigationContext {
            dashboardContent
        } else {
            NavigationStack {
                dashboardContent
            }
        }
    }

    // MARK: Private

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        Group {
            if hasLoadedDashboard {
                dashboardScrollContent
                    .id(experimentRefreshID)
            } else {
                // Widget deep link or first load: lightweight placeholder
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }
        }
        .task {
            loadDashboardFully()
        }
        .task {
            // Another Morse Trainer streak/practice days; throttled inside.
            await AMTService.shared.refreshStatsIfNeeded()
        }
        .task(id: hasLoadedDashboard) {
            guard hasLoadedDashboard, !hasRunStatsPipeline else {
                return
            }
            hasRunStatsPipeline = true
            let profiler = StartupProfiler.shared
            let container = modelContext.container
            profiler.record("dashboard.statsStart")

            // Serialize all stats computations to cap peak memory.
            // Each scan loads QSOs in batches; running them concurrently
            // multiplies peak memory and causes OOM on 4 GB devices.
            // Order: above-the-fold stats → presence → equipment → brag → needs.
            profiler.record("dashboard.asyncStats.start")
            asyncStats.compute(from: container)
            await asyncStats.waitUntilComplete()
            profiler.record("dashboard.asyncStats.done")

            profiler.record("dashboard.presenceCounts.start")
            presenceCounts.compute(from: container)
            await presenceCounts.waitUntilComplete()
            profiler.record("dashboard.presenceCounts.done")

            // Equipment is lightweight (LoggingSession, not QSOs)
            profiler.record("dashboard.equipmentStats.start")
            equipmentStats.compute(from: container)
            await equipmentStats.waitUntilComplete()
            profiler.record("dashboard.equipmentStats.done")

            profiler.record("dashboard.bragSheet.start")
            bragSheetStats.compute(from: container)
            await bragSheetStats.waitUntilComplete()
            profiler.record("dashboard.bragSheet.done")

            // Needs was previously a separate .task on the needs card,
            // running concurrently with the above. Now serialized here.
            if !hasComputedNeeds {
                hasComputedNeeds = true
                profiler.record("dashboard.needs.start")
                await computeNeeds()
                profiler.record("dashboard.needs.done")
            }

            profiler.record("dashboard.statsComplete")

            // Signal that the startup stats pipeline is done so deferred
            // services (CloudSync, backup) can start without concurrent
            // full-table scans that trigger the scene-update watchdog.
            NotificationCenter.default.post(
                name: .statsPipelineComplete, object: nil
            )

            // Fire-and-forget: repairs are one-time migrations that don't
            // need to block the stats pipeline task.
            Task { await runRepairChainIfNeeded(profiler: profiler) }
        }
        .onChange(of: syncService.lastSyncDate) { _, _ in
            scheduleCoalescedSyncRecompute()
        }
        .onChange(of: cloudSyncService.lastSyncDate) { _, _ in
            scheduleCoalescedSyncRecompute()
        }
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .dashboard else {
                return
            }
            // Cheap and throttled inside; AMT syncs happen in another app.
            Task { await AMTService.shared.refreshStatsIfNeeded() }
            guard hasLoadedDashboard, asyncStats.hasComputed else {
                return
            }
            // Only recompute if data changed since last computation.
            // dataGeneration is incremented by didLogQSO / sync / clear handlers.
            guard asyncStats.dataGeneration != asyncStats.computedGeneration else {
                let profiler = StartupProfiler.shared
                profiler.record("dashboard.tabSwitch.skipped")
                return
            }
            let profiler = StartupProfiler.shared
            profiler.record("dashboard.tabSwitch.recompute")
            // Serialize and defer. Previously this kicked off 4 full-table
            // QSO scans concurrently, each of which emits staged
            // `@Observable` property writes back to the main actor — so the
            // dashboard body re-evaluated many times while the user was
            // trying to scroll, producing visible chop on every tab switch
            // back. The startup pipeline serializes these stages with
            // `waitUntilComplete()`; mirror that here, plus a small delay
            // so the tab transition animation finishes before scans start.
            // Matches CLAUDE.md "Serialize concurrent full-table scans".
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                asyncStats.recompute(from: modelContext)
                await asyncStats.waitUntilComplete()
                presenceCounts.recompute(from: modelContext)
                await presenceCounts.waitUntilComplete()
                equipmentStats.recompute(from: modelContext.container)
                await equipmentStats.waitUntilComplete()
                bragSheetStats.recompute(from: modelContext.container)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clubMembershipDidChange)) { _ in
            // Roster changed (e.g. a club's member list grew server-side):
            // refresh the club counts baked into session brag sheets.
            Task.detached(priority: .utility) { [self] in
                await backfillSessionClubMembersIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didLogQSO)) { _ in
            asyncStats.dataGeneration += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .didClearQSOs)) { _ in
            asyncStats.reset()
            equipmentStats.reset()
            presenceCounts.recompute(from: modelContext)
            asyncStats.compute(from: modelContext)
            equipmentStats.compute(from: modelContext.container)
            bragSheetStats.recompute(from: modelContext.container)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .tabConfigurationChanged)
        ) { _ in
            experimentRefreshID = UUID()
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
            ToolbarItem(placement: .topBarLeading) {
                BrandWordmark()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCustomizeSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Customize dashboard")
            }
        }
        .sheet(isPresented: $showingCustomizeSheet) {
            DashboardCustomizeSheet(hiddenCardsRaw: $hiddenCards)
        }
        .sheet(item: $selectedService) { service in
            serviceDetailSheet(for: service)
        }
        .sheet(isPresented: $showingSyncReport) {
            AggregateSyncReportSheet(reports: syncService.lastSyncResults)
        }
        .navigationDestination(for: DaySummaryDestination.self) { destination in
            DaySummaryView(date: destination.date)
        }
    }

    /// The full dashboard ScrollView with all cards.
    /// Uses `TwoColumnLayout` to avoid destroying/recreating views on rotation.
    private var dashboardScrollContent: some View {
        ScrollView {
            adaptiveDashboardContent
                .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        )
        .background(Color(.systemGroupedBackground))
    }

    // Layout content is in DashboardView+Layout.swift
    // Activity card is in DashboardView+ActivityLog.swift

    /// Load the full dashboard: Keychain reads, service status, stats.
    /// Skipped on widget cold start, runs when user pops back or on normal launch.
    private func loadDashboardFully() {
        guard !hasLoadedDashboard else {
            return
        }
        let profiler = StartupProfiler.shared
        loadQRZConfig()
        profiler.record("dashboard.qrzConfig")
        refreshServiceStatus()
        profiler.record("dashboard.serviceStatus")
        hasLoadedDashboard = true
    }
}

// MARK: - CAR-244: Sync Recompute Coalescing

extension DashboardView {
    /// CAR-244: cancel any in-flight sync recompute and schedule a fresh one
    /// 3 s out. CloudKit and the legacy provider sync can write `lastSyncDate`
    /// many times per second during a batch; without coalescing each tick
    /// triggered four full QSO scans (asyncStats, equipmentStats,
    /// presenceCounts, bragSheetStats) plus two App-Group widget plist writes.
    /// At sync-storm pace this sustained 60–133 MB/s of disk writes and
    /// triggered watchdog terminations.
    func scheduleCoalescedSyncRecompute() {
        guard hasLoadedDashboard, asyncStats.hasComputed else {
            // The initial stats-pipeline `.task` handles cold-start compute;
            // post-sync recomputes only matter once we've shown stats once.
            return
        }
        syncRecomputeTask?.cancel()
        syncRecomputeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }
            // Bump dataGeneration so future tab-switch guards know a sync may
            // have changed underlying data. Widget writes inside the recompute
            // are individually hash-skipped if values actually didn't move.
            asyncStats.dataGeneration += 1
            asyncStats.recompute(from: modelContext)
            equipmentStats.recompute(from: modelContext.container)
            presenceCounts.recompute(from: modelContext)
            bragSheetStats.recompute(from: modelContext.container)
        }
    }
}

// Stats grid and streak row are in DashboardView+Stats.swift

// Services list and detail sheets are in DashboardView+Services.swift
// Action methods are in DashboardView+Actions.swift
// Helper views are in DashboardHelperViews.swift
