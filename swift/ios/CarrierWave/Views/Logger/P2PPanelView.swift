import CarrierWaveData
import SwiftUI

// MARK: - P2PPanelView

/// Panel showing park-to-park opportunities from nearby RBN skimmers
struct P2PPanelView: View {
    // MARK: Lifecycle

    init(
        userCallsign: String,
        userGrid: String,
        initialBand: String? = nil,
        initialMode: String? = nil,
        onDismiss: @escaping () -> Void,
        onSelectOpportunity: ((P2POpportunity) -> Void)? = nil
    ) {
        self.userCallsign = userCallsign
        self.userGrid = userGrid
        self.onDismiss = onDismiss
        self.onSelectOpportunity = onSelectOpportunity

        var bands = Set<String>()
        if let band = initialBand {
            bands.insert(band)
        }
        _selectedBands = State(initialValue: bands)

        var modes = Set<String>()
        if let mode = initialMode {
            let filter = ModeFilter.from(modeName: mode)
            if filter != .all {
                modes.insert(filter.rawValue)
            }
        }
        _selectedModes = State(initialValue: modes)
    }

    // MARK: Internal

    let userCallsign: String
    let userGrid: String
    let onDismiss: () -> Void
    let onSelectOpportunity: ((P2POpportunity) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if filteredOpportunities.isEmpty {
                emptyView
            } else {
                opportunitiesList
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadOpportunities()
        }
    }

    // MARK: Private

    @State private var allOpportunities: [P2POpportunity] = []
    @State private var isLoading = true
    @State private var loadingProgress: P2PProgress = .fetchingPOTASpots
    @State private var errorMessage: String?
    @State private var selectedBands: Set<String>
    @State private var selectedModes: Set<String>
    @State private var showFilterSheet = false

    @AppStorage("huntSpotMaxAgeMinutes") private var spotMaxAgeMinutes = 30

    private var filteredOpportunities: [P2POpportunity] {
        allOpportunities.filter { opp in
            OnAirSpotFilter.matchesBandByName(opp.band, bands: selectedBands)
                && OnAirSpotFilter.matchesModeValue(opp.mode, modes: selectedModes)
                && OnAirSpotFilter.matchesAge(
                    opp.timestamp, maxAgeMinutes: spotMaxAgeMinutes
                )
        }
    }

    private var opportunitiesByBand: [(band: String, opportunities: [P2POpportunity])] {
        let grouped = Dictionary(grouping: filteredOpportunities) { $0.band }
        return grouped.sorted { lhs, rhs in
            let lhsIdx = BandUtilities.bandOrder.firstIndex(of: lhs.key) ?? 999
            let rhsIdx = BandUtilities.bandOrder.firstIndex(of: rhs.key) ?? 999
            return lhsIdx < rhsIdx
        }.map {
            (band: $0.key, opportunities: $0.value)
        }
    }

    private var hasActiveFilters: Bool {
        !selectedBands.isEmpty || !selectedModes.isEmpty
    }

    private var filterIcon: String {
        hasActiveFilters
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    private var filterDisplayText: String {
        guard hasActiveFilters else {
            return "All"
        }
        var parts: [String] = []
        if !selectedBands.isEmpty {
            parts.append(sortedBandNames(selectedBands))
        }
        if !selectedModes.isEmpty {
            parts.append(selectedModes.sorted().joined(separator: ", "))
        }
        return parts.joined(separator: " \u{2022} ")
    }

    private var progressText: String {
        switch loadingProgress {
        case .fetchingPOTASpots:
            "Fetching POTA spots..."
        case let .queryingRBN(current, total):
            "Querying RBN (\(current)/\(total))..."
        case .filteringByDistance:
            "Finding nearby spotters..."
        case .complete:
            "Complete"
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.orange)
            Text("P2P Opportunities")
                .font(.headline)
            Spacer()
            Button {
                Task { await loadOpportunities() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: filterIcon)
                        .font(.caption)
                    Text(filterDisplayText)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                P2PFilterSheet(
                    selectedBands: $selectedBands,
                    selectedModes: $selectedModes,
                    isPresented: $showFilterSheet
                )
            }

            Spacer()

            Text("\(filteredOpportunities.count) P2P")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No P2P opportunities right now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try again in a few minutes")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if hasActiveFilters {
                Button("Clear Filters") {
                    selectedBands = []
                    selectedModes = []
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var opportunitiesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(opportunitiesByBand, id: \.band) { section in
                    Section {
                        ForEach(section.opportunities) { opportunity in
                            P2POpportunityRow(opportunity: opportunity) {
                                onSelectOpportunity?(opportunity)
                            }
                            Divider()
                                .padding(.leading, 92)
                        }
                    } header: {
                        sectionHeader(section.band)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadOpportunities() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func sectionHeader(_ band: String) -> some View {
        HStack {
            Text(band)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Helpers

    private func sortedBandNames(_ bands: Set<String>) -> String {
        bands.sorted { lhs, rhs in
            let lhsNum = lhs.filter(\.isNumber)
            let rhsNum = rhs.filter(\.isNumber)
            return (Int(lhsNum) ?? 0) > (Int(rhsNum) ?? 0)
        }.joined(separator: ", ")
    }

    // MARK: - Data Loading

    private func loadOpportunities() async {
        isLoading = true
        errorMessage = nil
        loadingProgress = .fetchingPOTASpots

        do {
            let rbnClient = RBNClient()
            let potaClient = POTAClient(authService: POTAAuthService())
            let service = P2PService(rbnClient: rbnClient, potaClient: potaClient)

            allOpportunities = try await service.findOpportunities(
                userGrid: userGrid,
                userCallsign: userCallsign
            ) { @Sendable progress in
                Task { @MainActor in
                    loadingProgress = progress
                }
            }
            isLoading = false
        } catch let error as P2PError {
            errorMessage = error.errorDescription
            allOpportunities = []
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            allOpportunities = []
            isLoading = false
        }
    }
}
