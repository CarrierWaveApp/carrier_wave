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
        }
        .searchable(text: $searchText, prompt: "Search callsigns or parks")
        .onAppear {
            loadServiceConfiguration()
            updateAvailableFilters()
            updateFilteredQSOs()
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
        .onChange(of: qsos.count) { _, _ in
            if qsos.count != lastQSOCount {
                updateAvailableFilters()
                updateFilteredQSOs()
            }
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
            if qsos.isEmpty {
                ContentUnavailableView(
                    "No QSOs",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Import ADIF files or sync from LoFi to see your QSOs")
                )
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<QSO> { !$0.isHidden },
        sort: \QSO.timestamp,
        order: .reverse
    ) private var qsos: [QSO]

    @State private var searchText = ""
    @State private var selectedBand: String?
    @State private var selectedMode: String?
    @State private var serviceConfig = ServiceConfiguration()

    // Cached filter results to avoid recomputation on every render
    @State private var cachedFilteredQSOs: [QSO] = []
    @State private var cachedAvailableBands: [String] = []
    @State private var cachedAvailableModes: [String] = []
    @State private var lastQSOCount: Int = 0

    private var filteredQSOs: [QSO] {
        cachedFilteredQSOs
    }

    private var availableBands: [String] {
        cachedAvailableBands
    }

    private var availableModes: [String] {
        cachedAvailableModes
    }

    private func deleteQSOs(at offsets: IndexSet) {
        for index in offsets {
            let qso = filteredQSOs[index]
            modelContext.delete(qso)
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
        lastQSOCount = qsos.count
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
