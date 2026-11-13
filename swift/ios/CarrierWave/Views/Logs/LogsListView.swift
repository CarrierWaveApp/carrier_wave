import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LogsListContentView

/// Content-only view for embedding in LogsContainerView
struct LogsListContentView: View {
    // MARK: Internal

    // MARK: Internal (accessed from LogsListDataLoading)

    static let initialBatchSize = 500
    static let loadMoreBatchSize = 500
    static let searchBatchSize = 1_000

    let lofiClient: LoFiClient
    let qrzClient: QRZClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let potaAuth: POTAAuthService
    let tourState: TourState

    /// QSO ID set by `SpotlightNotifications` when the user taps a CoreSpotlight
    /// QSO result. The view consumes (and clears) it via `task(id:)`, fetches
    /// the QSO from SwiftData, and pushes `QSODetailView`.
    @Binding var pendingSpotlightQSOID: UUID?

    @Environment(\.modelContext) var modelContext

    /// The page-accumulated rows for the current query, rendered backend-agnostically.
    @State var snapshots: [QSORowSnapshot] = []

    // Delete & select state
    @State var snapshotToDelete: QSORowSnapshot?
    @State var showDeleteConfirm = false
    @State var isSelectMode = false
    @State var selectedQSOIDs: Set<String> = []
    @State var showBulkDeleteConfirm = false
    @State var groupingSummary: GroupIntoSessionSheet.Summary?

    /// Whole-log (`!isHidden`) count — drives the slow-query analysis gate.
    @State var totalQSOCount: Int = 0
    /// Match count for the *current* query — drives "Load More".
    @State var currentMatchCount: Int = 0
    @State var queryText = ""
    @State var debouncedQueryText = ""
    @State var isLoadingInitial = true
    @State var isLoadingMore = false
    @State var isSearching = false
    @State var proceedWithSlowQuery = false
    @State var didInitialLoad = false
    /// The query string whose results are currently loaded; guards redundant reloads
    /// (e.g. tab switches) and lets a confirmed slow query re-trigger.
    @State var lastLoadedQuery: String?

    @AppStorage(CwStoreQSOMode.appStorageKey) var qsoMode = CwStoreQSOMode.on

    // Query state. Parsing + analysis run in the shared Rust core
    // (`QueryAnalyzer.analyzeViaRust`); only the analysis result is kept.
    @State var queryAnalysis: QueryAnalysis?
    @State var showFileImporter = false
    @State var showLogScanner = false

    @State var showQueryHelp = false

    /// `true` when filtered queries paginate over the whole match set (Rust `.on`),
    /// `false` when filtered search returns a single bounded batch (SwiftData).
    var paginatesFilteredFully: Bool {
        qsoMode == .on
    }

    var hasMoreRows: Bool {
        guard snapshots.count < currentMatchCount else {
            return false
        }
        return !hasActiveQuery || paginatesFilteredFully
    }

    var hasActiveQuery: Bool {
        !queryText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let analysis = queryAnalysis, analysis.shouldWarn {
                QueryWarningBanner(
                    analysis: analysis,
                    onProceed: { proceedWithSlowQuery = true },
                    onAddFilter: addSuggestedFilter
                )
            }

            List(selection: $selectedQSOIDs) {
                if !hasActiveQuery {
                    QuickFilterChipsView(queryText: $queryText)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                if hasActiveQuery, isImplicitCallsignSearch {
                    Label(
                        "Plain text searches callsigns by prefix. Use field:value for other filters.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Text("Searching...")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                } else {
                    ForEach(groupedByDate, id: \.key) { section in
                        Section {
                            ForEach(section.qsos) { snapshot in
                                NavigationLink {
                                    QSODetailLoader(snapshotID: snapshot.id, serviceConfig: serviceConfig)
                                } label: {
                                    QSORow(snapshot: snapshot, serviceConfig: serviceConfig)
                                }
                                .tag(snapshot.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        snapshotToDelete = snapshot
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            DateSectionHeader(label: section.label, count: section.qsos.count)
                        }
                    }

                    // Load more button if there are more rows to fetch
                    if hasMoreRows {
                        HStack {
                            Spacer()
                            Button {
                                Task {
                                    await loadMoreQSOs()
                                }
                            } label: {
                                if isLoadingMore {
                                    ProgressView()
                                        .padding(.vertical, 8)
                                } else {
                                    Text("Load More (\(currentMatchCount - snapshots.count) remaining)")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .disabled(isLoadingMore)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.editMode, isSelectMode ? .constant(.active) : .constant(.inactive))
            .overlay(alignment: .bottom) {
                if isSelectMode, !selectedQSOIDs.isEmpty {
                    bulkDeleteBar
                }
            }
            .alert(
                "Delete QSO",
                isPresented: $showDeleteConfirm
            ) {
                Button("Delete", role: .destructive) {
                    if let snapshot = snapshotToDelete {
                        deleteSnapshots([snapshot])
                    }
                    snapshotToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    snapshotToDelete = nil
                }
            } message: {
                if let snapshot = snapshotToDelete {
                    Text("Delete QSO with \(snapshot.callsign)?")
                }
            }
            .onChange(of: snapshotToDelete) { _, newValue in
                showDeleteConfirm = newValue != nil
            }
            .alert(
                "Delete \(selectedQSOIDs.count) QSOs",
                isPresented: $showBulkDeleteConfirm
            ) {
                Button(
                    "Delete \(selectedQSOIDs.count)",
                    role: .destructive
                ) {
                    bulkDeleteSelected()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will hide \(selectedQSOIDs.count) QSOs from your log. "
                        + "They can be recovered by re-syncing."
                )
            }
        }
        .searchable(text: $queryText, prompt: "Search callsign, or use band:20m, after:30d...")
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveQSYLookup)
        ) { notification in
            if let callsign = notification.userInfo?["callsign"] as? String {
                queryText = callsign
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didLogQSO)
        ) { _ in
            Task {
                await refreshAfterNewQSO()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didSyncQSOs)
        ) { _ in
            Task {
                await refreshAfterNewQSO()
            }
        }
        .task {
            await loadInitialQSOs()
        }
        .task(id: debouncedQueryText) {
            await executeQuery()
        }
        .task(id: pendingSpotlightQSOID) {
            await consumePendingSpotlightQSO()
        }
        .navigationDestination(item: $spotlightQSO) { qso in
            QSODetailView(qso: qso, serviceConfig: serviceConfig)
        }
        .onChange(of: proceedWithSlowQuery) { _, proceed in
            if proceed {
                Task { await executeQuery() }
            }
        }
        .onChange(of: queryText) { _, newValue in
            // Debounce query execution
            queryDebounceTask?.cancel()
            queryDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled {
                    debouncedQueryText = newValue
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { toolbarMenu }
            ToolbarItem(placement: .topBarLeading) { leadingToolbarContent }
        }
        .overlay {
            if snapshots.isEmpty, !isLoadingInitial, !isSearching {
                if hasActiveQuery {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No QSOs match your search query")
                    )
                } else {
                    ContentUnavailableView(
                        "No QSOs",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Import ADIF files or sync from LoFi to see your QSOs")
                    )
                }
            }
        }
        .sheet(isPresented: $showQueryHelp) {
            QueryHelpSheet()
        }
        .sheet(item: $groupingSummary) { summary in
            GroupIntoSessionSheet(
                summary: summary,
                onCancel: { groupingSummary = nil },
                onCreate: { result in
                    groupingSummary = nil
                    createSessionFromSelection(result)
                }
            )
        }
        .adifImportable(isPresented: $showFileImporter)
        .fullScreenCover(isPresented: $showLogScanner) {
            LogScanImportView()
        }
        .miniTour(.logs, tourState: tourState)
    }

    func loadServiceConfiguration() {
        serviceConfig = ServiceConfiguration(
            qrz: qrzClient.hasApiKey(),
            pota: potaAuth.isConfigured,
            lofi: lofiClient.isConfigured && lofiClient.isLinked,
            hamrs: hamrsClient.isConfigured,
            lotw: lotwClient.isConfigured,
            clublog: ClubLogClient().isConfigured
        )
    }

    /// Fetches the QSO referenced by `pendingSpotlightQSOID` from SwiftData
    /// and assigns it to `spotlightQSO` so the navigation destination pushes
    /// `QSODetailView`. Clears the pending binding so it isn't re-consumed.
    func consumePendingSpotlightQSO() async {
        guard let qsoID = pendingSpotlightQSOID else {
            return
        }
        pendingSpotlightQSOID = nil
        loadServiceConfiguration()
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == qsoID }
        )
        descriptor.fetchLimit = 1
        spotlightQSO = try? modelContext.fetch(descriptor).first
    }

    // MARK: Private

    @State private var serviceConfig = ServiceConfiguration()
    @State private var queryDebounceTask: Task<Void, Never>?

    /// QSO loaded from SwiftData via the spotlight deep-link path. Drives a
    /// `navigationDestination(item:)` push to `QSODetailView`.
    @State private var spotlightQSO: QSO?

    /// True when the query text has no field qualifiers (e.g., "W1AW" not "band:20m")
    private var isImplicitCallsignSearch: Bool {
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains(":") && !trimmed.contains("*")
    }
}
