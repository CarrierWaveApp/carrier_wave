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
    let tourState: TourState

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassPOTAMaintenance = false

    // Sync state
    @State var isSyncing = false
    @State var syncingService: ServiceType?
    @State var lastSyncDate: Date?
    @State var lofiSyncResult: String?

    // QRZ state
    @State var qrzCallsign: String?
    @State var qrzIsConfigured: Bool = false
    @State var qrzSyncResult: String?

    /// POTA state
    @State var potaSyncResult: String?

    /// HAMRS state
    @State var hamrsSyncResult: String?

    /// LoTW state
    @State var lotwSyncResult: String?

    // Service configuration state (refreshed on appear)
    @State var lofiIsConfigured: Bool = false
    @State var lofiIsLinked: Bool = false
    @State var lofiCallsign: String?
    @State var hamrsIsConfigured: Bool = false
    @State var lotwIsConfigured: Bool = false

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

    /// Progressive statistics - computes expensive stats in background for large datasets
    @State var asyncStats = AsyncQSOStatistics()

    /// Service presence counts - computed in background
    @State var presenceCounts = AsyncServicePresenceCounts()

    let lofiClient = LoFiClient()
    let qrzClient = QRZClient()
    let hamrsClient = HAMRSClient()
    let lotwClient = LoTWClient()

    let aliasService = CallsignAliasService.shared

    var importService: ImportService {
        ImportService(modelContext: modelContext)
    }

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
            ScrollView {
                VStack(spacing: 16) {
                    activityCard
                    // In landscape on iPhone (compact vertical), combine streaks and stats
                    if verticalSizeClass == .compact {
                        combinedStreaksAndStatsCard
                    } else {
                        streaksCard
                        summaryCard
                    }
                    favoritesCard
                    servicesList
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                loadQRZConfig()
                refreshServiceStatus()
            }
            .task {
                // Compute stats and presence counts in background on first load
                asyncStats.compute(from: modelContext)
                presenceCounts.compute(from: modelContext)
            }
            .task {
                // Check for callsign aliases after stats are computed (only once per session)
                // Wait a bit for asyncStats to populate uniqueMyCallsigns
                guard !hasCheckedCallsignAliases else {
                    return
                }
                hasCheckedCallsignAliases = true
                try? await Task.sleep(for: .milliseconds(500))
                await checkForUnconfiguredCallsigns()
                await checkForMismarkedPOTAPresence()
                await checkForTwoferDuplicates()
            }
            .onChange(of: syncService.lastSyncDate) { _, _ in
                // Recompute stats after sync completes
                // Delay to ensure background saves are fully committed to SQLite
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    asyncStats.recompute(from: modelContext)
                    presenceCounts.recompute(from: modelContext)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didClearQSOs)) { _ in
                // Reset and recompute stats after QSOs are cleared
                asyncStats.reset()
                presenceCounts.recompute(from: modelContext)
                // Recompute after reset to show zeros
                asyncStats.compute(from: modelContext)
            }
            // NOTE: No .onDisappear cancellation - computation continues in background
            // when user switches tabs. This is intentional because:
            // 1. TabView keeps the view alive, so @State persists
            // 2. Cooperative yielding (Task.yield) prevents blocking other tabs
            // 3. Results will be ready when user returns to dashboard
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    toolbarButtons
                }
            }
            .sheet(item: $selectedService) { service in
                serviceDetailSheet(for: service)
            }
        }
    }

    /// Derived counts from ServicePresence (computed in background)
    func uploadedCount(for service: ServiceType) -> Int {
        presenceCounts.uploadedCount(for: service)
    }

    func pendingCount(for service: ServiceType) -> Int {
        presenceCounts.pendingCount(for: service)
    }

    // MARK: Private

    /// Track whether we've already run the one-time checks (callsign aliases, POTA repair)
    /// to avoid re-running expensive queries on every tab switch
    @State private var hasCheckedCallsignAliases = false

    // MARK: - Toolbar

    private var toolbarButtons: some View {
        HStack(spacing: 12) {
            if debugMode {
                Button {
                    Task { await performDownloadOnly() }
                } label: {
                    if isSyncing {
                        syncProgressLabel
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .disabled(isSyncing)
                .accessibilityLabel("Download only")
            }

            Button {
                Task { await performFullSync() }
            } label: {
                if isSyncing {
                    syncProgressLabel
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)
            .accessibilityLabel("Sync all services")
        }
    }

    @ViewBuilder
    private var syncProgressLabel: some View {
        if syncService.syncPhase == .processing,
           let processingProgress = syncService.syncProgress.processingProgress
        {
            // Show progress bar for processing phase
            HStack(spacing: 6) {
                ProgressView(value: processingProgress)
                    .frame(width: 60)
                Text(syncService.syncProgress.processingPhase)
                    .font(.caption)
                    .lineLimit(1)
            }
        } else if let lofiProgress = syncService.syncProgress.lofiProgress {
            // Show progress bar for LoFi sync (regardless of current phase, since downloads are parallel)
            HStack(spacing: 6) {
                ProgressView(value: lofiProgress)
                    .frame(width: 60)
                Text("\(syncService.syncProgress.lofiDownloadedQSOs)")
                    .font(.caption)
                    .monospacedDigit()
            }
        } else {
            // Show spinner with count for other services
            HStack(spacing: 4) {
                ProgressView()
                if syncService.syncProgress.downloadedQSOCount > 0 {
                    Text("\(syncService.syncProgress.downloadedQSOCount)")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
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

            ActivityGrid(activityData: asyncStats.activityByDate)

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

    // MARK: - Streaks Card

    private var streaksCard: some View {
        NavigationLink {
            LazyStreakDetailView(asyncStats: asyncStats, tourState: tourState)
        } label: {
            StreaksCard(
                dailyStreak: asyncStats.dailyStreak, potaStreak: asyncStats.potaActivationStreak
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                Spacer()
                if let lastSync = lastSyncDate {
                    Text("Synced \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            statsGrid
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Combined Streaks and Stats Card (Landscape)

    private var combinedStreaksAndStatsCard: some View {
        HStack(alignment: .top, spacing: 16) {
            // Streaks section (left side)
            NavigationLink {
                LazyStreakDetailView(asyncStats: asyncStats, tourState: tourState)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Streaks")
                        .font(.headline)

                    VStack(spacing: 12) {
                        streakRow(title: "Daily", streak: asyncStats.dailyStreak)
                        streakRow(title: "POTA", streak: asyncStats.potaActivationStreak)
                    }
                }
            }
            .buttonStyle(.plain)

            Divider()

            // Stats section (right side)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Statistics")
                        .font(.headline)
                    Spacer()
                    if let lastSync = lastSyncDate {
                        Text("Synced \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                statsGrid
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Favorites Card

    @ViewBuilder
    private var favoritesCard: some View {
        if asyncStats.hasComputed {
            FavoritesCard(asyncStats: asyncStats, tourState: tourState)
        } else {
            // Show placeholder while stats are loading
            VStack(alignment: .leading, spacing: 12) {
                Text("Favorites")
                    .font(.headline)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Stats grid and streak row are in DashboardView+Stats.swift

// Services list and detail sheets are in DashboardView+Services.swift
// Action methods are in DashboardView+Actions.swift
// Helper views are in DashboardHelperViews.swift
