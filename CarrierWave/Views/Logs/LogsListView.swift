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

    var body: some View {
        List {
            ForEach(filteredQSOs) { qso in
                QSORow(qso: qso, serviceConfig: serviceConfig)
            }
            .onDelete(perform: deleteQSOs)

            // Load more button if there are more QSOs to fetch
            if hasMoreQSOs {
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
        .searchable(text: $searchText, prompt: "Search callsigns or parks")
        .task {
            await loadInitialQSOs()
        }
        .onChange(of: searchText) { _, _ in
            updateFilteredQSOs()
        }
        .onChange(of: selectedBand) { _, _ in
            updateFilteredQSOs()
        }
        .onChange(of: selectedMode) { _, _ in
            updateFilteredQSOs()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Menu("Band") {
                        Button("All") { selectedBand = nil }
                        ForEach(availableBands, id: \.self) { band in
                            Button(band) { selectedBand = band }
                        }
                    }

                    Menu("Mode") {
                        Button("All") { selectedMode = nil }
                        ForEach(availableModes, id: \.self) { mode in
                            Button(mode) { selectedMode = mode }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .overlay {
            if qsos.isEmpty, !isLoadingInitial {
                ContentUnavailableView(
                    "No QSOs",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Import ADIF files or sync from LoFi to see your QSOs")
                )
            }
        }
    }

    // MARK: Private

    /// Initial batch size for loading QSOs
    private static let initialBatchSize = 500

    /// Batch size for loading more QSOs
    private static let loadMoreBatchSize = 500

    @Environment(\.modelContext) private var modelContext

    /// QSOs loaded on demand (not using @Query to avoid full table scan)
    @State private var qsos: [QSO] = []

    /// Total count of QSOs in database
    @State private var totalQSOCount: Int = 0

    @State private var searchText = ""
    @State private var selectedBand: String?
    @State private var selectedMode: String?
    @State private var serviceConfig = ServiceConfiguration()
    @State private var isLoadingInitial = true
    @State private var isLoadingMore = false

    // Cached filter results to avoid recomputation on every render
    @State private var cachedFilteredQSOs: [QSO] = []
    @State private var cachedAvailableBands: [String] = []
    @State private var cachedAvailableModes: [String] = []

    private var filteredQSOs: [QSO] {
        cachedFilteredQSOs
    }

    private var availableBands: [String] {
        cachedAvailableBands
    }

    private var availableModes: [String] {
        cachedAvailableModes
    }

    private var hasMoreQSOs: Bool {
        qsos.count < totalQSOCount
    }

    private func deleteQSOs(at offsets: IndexSet) {
        for index in offsets {
            let qso = filteredQSOs[index]
            modelContext.delete(qso)
        }
        // Refresh the list after deletion
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

        // Get total count
        await refreshQSOCount()

        // Fetch initial batch
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchLimit = Self.initialBatchSize

        if let fetched = try? modelContext.fetch(descriptor) {
            qsos = fetched
        }

        updateAvailableFilters()
        updateFilteredQSOs()
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
        }

        updateAvailableFilters()
        updateFilteredQSOs()
        isLoadingMore = false
    }

    private func refreshQSOCount() async {
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        totalQSOCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0
    }

    private func updateFilteredQSOs() {
        cachedFilteredQSOs = qsos.filter { qso in
            let matchesSearch =
                searchText.isEmpty || qso.callsign.localizedCaseInsensitiveContains(searchText)
                    || (qso.parkReference?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesBand = selectedBand == nil || qso.band == selectedBand
            let matchesMode = selectedMode == nil || qso.mode == selectedMode

            return matchesSearch && matchesBand && matchesMode
        }
    }

    private func updateAvailableFilters() {
        cachedAvailableBands = Array(Set(qsos.map(\.band))).sorted()
        cachedAvailableModes = Array(Set(qsos.map(\.mode))).sorted()
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
        // QSL confirmed (QRZ/LoTW only)
        if presence.isPresent, isConfirmed {
            return "star.fill"
        }

        // Bidirectional services: clock (not synced), arrow.down (downloaded), checkmark (fully synced)
        if isBidirectional {
            if presence.isPresent, !presence.needsUpload {
                return "checkmark"
            } else if presence.isPresent, presence.needsUpload {
                return "arrow.down"
            }
        }

        // Download-only services: checkmark when present
        if presence.isPresent {
            return "checkmark"
        }

        // Not synced - same icon for all services
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
