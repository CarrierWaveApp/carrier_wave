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

    func isConfigured(_ serviceType: ServiceType) -> Bool {
        switch serviceType {
        case .qrz: qrz
        case .pota: pota
        case .lofi: lofi
        case .hamrs: hamrs
        case .lotw: lotw
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
                        QSORow(qso: qso, serviceConfig: serviceConfig)
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
        .searchable(text: $queryText, prompt: "Search: W1AW, K-1234, band:20m, after:30d...")
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

        // Now delete from model context
        for qso in qsosToDelete {
            modelContext.delete(qso)
        }

        Task {
            await refreshQSOCount()
        }
    }

    private func loadServiceConfiguration() {
        serviceConfig = ServiceConfiguration(
            qrz: qrzClient.hasApiKey(),
            pota: potaAuth.isAuthenticated,
            lofi: lofiClient.isConfigured && lofiClient.isLinked,
            hamrs: hamrsClient.isConfigured,
            lotw: lotwClient.isConfigured
        )
    }

    private func loadInitialQSOs() async {
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

    private func loadMoreQSOs() async {
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

    private func refreshQSOCount() async {
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        totalQSOCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0
    }

    private func executeQuery() async {
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
            let filter = QueryCompiler.compile(query)
            compiledFilter = filter

            // Execute search in background
            await searchWithFilter(filter)
            isSearching = false

        case let .failure(error):
            parsedQuery = nil
            queryError = error
            queryAnalysis = nil
            compiledFilter = nil
            // On error, keep showing current results
        }
    }

    private func searchWithFilter(_ filter: @escaping (QSO) -> Bool) async {
        // For queries, we may need to fetch more data than currently loaded
        // Use a larger batch and apply the filter
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchLimit = Self.searchBatchSize

        guard let fetched = try? modelContext.fetch(descriptor) else {
            cachedFilteredQSOs = []
            return
        }

        // Apply filter with cooperative yielding for large datasets
        var results: [QSO] = []
        for (index, qso) in fetched.enumerated() {
            if filter(qso) {
                results.append(qso)
            }
            // Yield periodically to keep UI responsive
            if index.isMultiple(of: 100) {
                await Task.yield()
            }
        }

        cachedFilteredQSOs = results
    }

    private func addSuggestedFilter(_ suggestion: String) {
        if queryText.isEmpty {
            queryText = suggestion
        } else {
            queryText = "\(queryText) \(suggestion)"
        }
    }
}

// MARK: - QueryWarningBanner

struct QueryWarningBanner: View {
    // MARK: Internal

    let analysis: QueryAnalysis
    let onProceed: () -> Void
    let onAddFilter: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(analysis.warnings.prefix(2)) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning.severity.icon)
                        .foregroundStyle(warningColor(warning.severity))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.message)
                            .font(.caption)

                        if let suggestion = warning.suggestion {
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if analysis.requiresConfirmation {
                HStack {
                    Button("Search Anyway") {
                        onProceed()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let suggestion = analysis.warnings.first?.suggestion,
                       suggestion.contains("after:")
                    {
                        Button("Add Date Filter") {
                            onAddFilter("after:30d")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: Private

    private func warningColor(_ severity: QueryWarning.Severity) -> Color {
        switch severity {
        case .hint: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}

// MARK: - QueryHelpSheet

struct QueryHelpSheet: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            List {
                Section("Basic Search") {
                    helpRow("W1AW", "Find contacts with W1AW")
                    helpRow("K-1234", "Find contacts at park K-1234")
                    helpRow("W1*", "Callsigns starting with W1")
                }

                Section("Field Filters") {
                    helpRow("band:20m", "20 meter contacts")
                    helpRow("mode:CW", "CW mode contacts")
                    helpRow("state:CA", "California stations")
                    helpRow("park:K-*", "Any US POTA park")
                    helpRow("grid:FN31", "Specific grid square")
                }

                Section("Date Filters") {
                    helpRow("date:today", "Today's contacts")
                    helpRow("after:7d", "Last 7 days")
                    helpRow("after:30d", "Last 30 days")
                    helpRow("date:2024-01", "January 2024")
                    helpRow("before:2024-06-01", "Before June 1, 2024")
                }

                Section("Status Filters") {
                    helpRow("confirmed:lotw", "LoTW confirmed")
                    helpRow("confirmed:qrz", "QRZ QSL confirmed")
                    helpRow("synced:pota", "Uploaded to POTA")
                    helpRow("pending:yes", "Needs upload")
                }

                Section("Combining Filters") {
                    helpRow("W1AW 20m", "W1AW on 20m (AND)")
                    helpRow("W1AW | K1ABC", "W1AW or K1ABC (OR)")
                    helpRow("-mode:FT8", "Exclude FT8")
                    helpRow("band:20m mode:CW after:30d", "20m CW in last 30 days")
                }

                Section("Numeric Filters") {
                    helpRow("freq:14.074", "Specific frequency")
                    helpRow("freq:>14.0", "Above 14 MHz")
                    helpRow("power:>100", "Over 100W")
                }
            }
            .navigationTitle("Search Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func helpRow(_ query: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(query)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - QSORow

struct QSORow: View {
    // MARK: Internal

    let qso: QSO
    let serviceConfig: ServiceConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(qso.callsign)
                    .font(.headline)

                Spacer()

                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let freq = qso.frequency {
                    Label(FrequencyFormatter.format(freq), systemImage: "waveform")
                }
                Label(qso.band, systemImage: "antenna.radiowaves.left.and.right")
                Label(qso.mode, systemImage: "dot.radiowaves.left.and.right")

                if let park = qso.parkReference {
                    if let name = parkName {
                        Label("\(park) - \(name)", systemImage: "tree")
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    } else {
                        Label(park, systemImage: "tree")
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(sortedPresence) { presence in
                    ServicePresenceBadge(
                        presence: presence,
                        qso: qso,
                        isServiceConfigured: serviceConfig.isConfigured(presence.serviceType)
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            if let park = qso.parkReference {
                parkName = await POTAParksCache.shared.name(for: park)
            }
        }
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @State private var parkName: String?

    private var formattedTimestamp: String {
        Self.utcFormatter.string(from: qso.timestamp) + "Z"
    }

    private var sortedPresence: [ServicePresence] {
        qso.servicePresence.sorted { $0.serviceType.rawValue < $1.serviceType.rawValue }
    }
}

// MARK: - ServicePresenceBadge

struct ServicePresenceBadge: View {
    // MARK: Internal

    let presence: ServicePresence
    let qso: QSO
    let isServiceConfigured: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
            Text(presence.serviceType.displayName)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }

    // MARK: Private

    private var isBidirectional: Bool {
        switch presence.serviceType {
        case .qrz,
             .pota,
             .hamrs:
            true
        case .lofi,
             .lotw:
            false
        }
    }

    private var isConfirmed: Bool {
        switch presence.serviceType {
        case .lotw:
            qso.lotwConfirmed
        case .qrz:
            qso.qrzConfirmed
        default:
            false
        }
    }

    private var iconName: String {
        if presence.isPresent, isConfirmed {
            return "star.fill"
        }

        if isBidirectional {
            if presence.isPresent, !presence.needsUpload {
                return "checkmark"
            } else if presence.isPresent, presence.needsUpload {
                return "arrow.down"
            }
        }

        if presence.isPresent {
            return "checkmark"
        }

        return "clock"
    }

    private var backgroundColor: Color {
        if presence.isPresent {
            .green
        } else if isServiceConfigured {
            .orange
        } else {
            .gray
        }
    }
}
