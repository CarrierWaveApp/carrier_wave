import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ServiceConfiguration

/// Tracks which services are configured/authenticated
struct ServiceConfiguration {
    var qrz: Bool = false
    var pota: Bool = false
    var lofi: Bool = false
    var hamrs: Bool = false
    var lotw: Bool = false
    var clublog: Bool = false

    func isConfigured(_ serviceType: ServiceType) -> Bool {
        switch serviceType {
        case .qrz: qrz
        case .pota: pota
        case .lofi: lofi
        case .hamrs: hamrs
        case .lotw: lotw
        case .clublog: clublog
        }
    }
}

// MARK: - LogsListContentView

/// Content-only view for embedding in LogsContainerView
struct LogsListContentView: View {
    // MARK: Internal

    let lofiClient: LoFiClient
    let qrzClient: QRZClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let potaAuth: POTAAuthService
    let tourState: TourState

    var body: some View {
        VStack(spacing: 0) {
            // Query warnings banner
            if let analysis = queryAnalysis, analysis.shouldWarn {
                QueryWarningBanner(
                    analysis: analysis,
                    onProceed: { proceedWithSlowQuery = true },
                    onAddFilter: addSuggestedFilter
                )
            }

            // Implicit callsign search hint
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
            }

            // Main list
            List {
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
                    ForEach(filteredQSOs) { qso in
                        NavigationLink {
                            QSODetailView(qso: qso, serviceConfig: serviceConfig)
                        } label: {
                            QSORow(qso: qso, serviceConfig: serviceConfig)
                        }
                    }
                    .onDelete(perform: deleteQSOs)

                    // Load more button if there are more QSOs to fetch
                    if hasMoreQSOs, !hasActiveQuery {
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
                                    Text("Load More (\(totalQSOCount - qsos.count) remaining)")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .disabled(isLoadingMore)
                            Spacer()
                        }
                    }
                }
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
        .task {
            await loadInitialQSOs()
        }
        .task(id: debouncedQueryText) {
            await executeQuery()
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showQueryHelp = true
                    } label: {
                        Label("Search Help", systemImage: "questionmark.circle")
                    }

                    Divider()

                    // Quick filters
                    Menu("Quick Filters") {
                        Button("Last 7 days") { queryText = "after:7d" }
                        Button("Last 30 days") { queryText = "after:30d" }
                        Button("This year") {
                            queryText = "date:\(Calendar.current.component(.year, from: Date()))"
                        }

                        Divider()

                        Button("CW contacts") { queryText = "mode:CW" }
                        Button("FT8 contacts") { queryText = "mode:FT8" }
                        Button("SSB contacts") { queryText = "mode:SSB" }

                        Divider()

                        Button("POTA activations") { queryText = "park:K-*" }
                        Button("LoTW confirmed") { queryText = "confirmed:lotw" }
                        Button("Pending upload") { queryText = "pending:yes" }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                if hasActiveQuery {
                    Text("\(filteredQSOs.count) matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if qsos.isEmpty, !isLoadingInitial, !isSearching {
                ContentUnavailableView(
                    "No QSOs",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Import ADIF files or sync from LoFi to see your QSOs")
                )
            } else if filteredQSOs.isEmpty, hasActiveQuery, !isSearching {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: Text("No QSOs match your search query")
                )
            }
        }
        .sheet(isPresented: $showQueryHelp) {
            QueryHelpSheet()
        }
        .miniTour(.logs, tourState: tourState)
    }

    // MARK: Private

    private static let initialBatchSize = 500
    private static let loadMoreBatchSize = 500
    private static let searchBatchSize = 1_000

    @Environment(\.modelContext) private var modelContext

    @State private var qsos: [QSO] = []
    @State private var totalQSOCount: Int = 0
    @State private var queryText = ""
    @State private var debouncedQueryText = ""
    @State private var serviceConfig = ServiceConfiguration()
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false
    @State private var isSearching = false
    @State private var showQueryHelp = false
    @State private var proceedWithSlowQuery = false
    @State private var queryDebounceTask: Task<Void, Never>?

    // Query state
    @State private var parsedQuery: ParsedQuery?
    @State private var queryError: QueryError?
    @State private var queryAnalysis: QueryAnalysis?
    @State private var compiledFilter: ((QSO) -> Bool)?

    /// Cached results
    @State private var cachedFilteredQSOs: [QSO] = []

    private var filteredQSOs: [QSO] {
        cachedFilteredQSOs
    }

    private var hasMoreQSOs: Bool {
        qsos.count < totalQSOCount
    }

    private var hasActiveQuery: Bool {
        !queryText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when the query text has no field qualifiers (e.g., "W1AW" not "band:20m")
    private var isImplicitCallsignSearch: Bool {
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains(":") && !trimmed.contains("*")
    }

    private func deleteQSOs(at offsets: IndexSet) {
        // Collect QSOs to delete BEFORE any mutations to avoid index invalidation
        let qsosToDelete = offsets.compactMap { index -> QSO? in
            guard index < cachedFilteredQSOs.count else {
                return nil
            }
            return cachedFilteredQSOs[index]
        }

        guard !qsosToDelete.isEmpty else {
            return
        }

        // Get the IDs to remove from our cached arrays
        let idsToRemove = Set(qsosToDelete.map(\.id))

        // Update cached arrays BEFORE deleting from model context
        // This prevents SwiftUI from seeing stale data during the update cycle
        cachedFilteredQSOs.removeAll { idsToRemove.contains($0.id) }
        qsos.removeAll { idsToRemove.contains($0.id) }

        // Soft-delete: hide instead of hard-deleting to protect against data loss
        for qso in qsosToDelete {
            qso.isHidden = true
            qso.cloudDirtyFlag = true
            qso.modifiedAt = Date()
        }
        try? modelContext.save()

        Task {
            await refreshQSOCount()
        }
    }

    private func loadServiceConfiguration() {
        serviceConfig = ServiceConfiguration(
            qrz: qrzClient.hasApiKey(),
            pota: potaAuth.isConfigured,
            lofi: lofiClient.isConfigured && lofiClient.isLinked,
            hamrs: hamrsClient.isConfigured,
            lotw: lotwClient.isConfigured,
            clublog: ClubLogClient().isConfigured
        )
    }
}

// MARK: - Data Loading & Query Execution

extension LogsListContentView {
    func loadInitialQSOs() async {
        // Skip if already loaded to avoid re-fetching on tab switch
        guard qsos.isEmpty else {
            isLoadingInitial = false
            return
        }

        isLoadingInitial = true
        loadServiceConfiguration()

        await refreshQSOCount()

        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchLimit = Self.initialBatchSize

        if let fetched = try? modelContext.fetch(descriptor) {
            qsos = fetched
            cachedFilteredQSOs = fetched
        }

        isLoadingInitial = false
    }

    func loadMoreQSOs() async {
        guard !isLoadingMore, hasMoreQSOs else {
            return
        }

        isLoadingMore = true

        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchOffset = qsos.count
        descriptor.fetchLimit = Self.loadMoreBatchSize

        if let fetched = try? modelContext.fetch(descriptor) {
            qsos.append(contentsOf: fetched)
            if !hasActiveQuery {
                cachedFilteredQSOs = qsos
            }
        }

        isLoadingMore = false
    }

    func refreshQSOCount() async {
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        totalQSOCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0
    }

    func executeQuery() async {
        let trimmed = debouncedQueryText.trimmingCharacters(in: .whitespaces)

        // Empty query - show all loaded QSOs
        if trimmed.isEmpty {
            parsedQuery = nil
            queryError = nil
            queryAnalysis = nil
            compiledFilter = nil
            cachedFilteredQSOs = qsos
            proceedWithSlowQuery = false
            return
        }

        // Parse the query
        switch QueryParser.parse(trimmed) {
        case let .success(query):
            parsedQuery = query
            queryError = nil

            // Analyze performance
            let analysis = QueryAnalyzer.analyze(query, qsoCount: totalQSOCount)
            queryAnalysis = analysis

            // Check if we need confirmation for slow queries
            if analysis.requiresConfirmation, !proceedWithSlowQuery, totalQSOCount > 5_000 {
                // Don't execute yet - wait for user to confirm
                cachedFilteredQSOs = []
                return
            }

            // Compile and execute
            isSearching = true
            let compiled = QueryCompiler.compileWithPredicate(query)
            compiledFilter = compiled.filter

            // Execute search in background using both predicate and filter
            await searchWithCompiledQuery(compiled)
            isSearching = false

        case let .failure(error):
            parsedQuery = nil
            queryError = error
            queryAnalysis = nil
            compiledFilter = nil
            // On error, keep showing current results
        }
    }

    func searchWithCompiledQuery(_ compiled: CompiledQuery) async {
        // Build descriptor using the compiled predicate if available
        // This pushes filtering to the database for indexed fields
        var descriptor =
            if let predicate = compiled.predicate {
                // Combine with !isHidden check
                FetchDescriptor<QSO>(predicate: predicate)
            } else {
                FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            }
        descriptor.sortBy = compiled.sortDescriptors

        // When we have a predicate, let the database do the work - no limit needed
        // When we don't have a predicate, we still need to scan but use a larger batch
        if compiled.predicate == nil {
            descriptor.fetchLimit = Self.searchBatchSize
        }

        guard let fetched = try? modelContext.fetch(descriptor) else {
            cachedFilteredQSOs = []
            return
        }

        // Apply the full filter for any conditions the predicate couldn't handle
        // (e.g., complex boolean logic, non-indexed fields)
        var results: [QSO] = []
        for (index, qso) in fetched.enumerated() {
            // Skip hidden QSOs (in case predicate didn't include this check)
            guard !qso.isHidden else {
                continue
            }

            if compiled.filter(qso) {
                results.append(qso)
            }
            // Yield periodically to keep UI responsive
            if index.isMultiple(of: 100) {
                await Task.yield()
            }
        }

        cachedFilteredQSOs = results
    }

    func addSuggestedFilter(_ suggestion: String) {
        if queryText.isEmpty {
            queryText = suggestion
        } else {
            queryText = "\(queryText) \(suggestion)"
        }
    }
}
