import CarrierWaveCore
import SwiftUI

// MARK: - SidebarP2PView

/// P2P opportunities adapted for persistent iPad sidebar display.
/// Only meaningful during POTA activations; shows empty state otherwise.
struct SidebarP2PView: View {
    // MARK: Lifecycle

    init(
        userCallsign: String?,
        userGrid: String?,
        isPOTAActivation: Bool,
        initialBand: String? = nil,
        initialMode: String? = nil,
        onSelectOpportunity: @escaping (P2POpportunity) -> Void
    ) {
        self.userCallsign = userCallsign
        self.userGrid = userGrid
        self.isPOTAActivation = isPOTAActivation
        self.onSelectOpportunity = onSelectOpportunity
        _bandFilter = State(initialValue: BandFilter.from(bandName: initialBand))
        _modeFilter = State(initialValue: ModeFilter.from(modeName: initialMode))
    }

    // MARK: Internal

    let userCallsign: String?
    let userGrid: String?
    let isPOTAActivation: Bool
    let onSelectOpportunity: (P2POpportunity) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !isPOTAActivation {
                notActivatingView
            } else if userGrid == nil || userGrid?.isEmpty == true {
                noGridView
            } else {
                filterBar
                Divider()

                if isLoading, allOpportunities.isEmpty {
                    loadingView
                } else if let error = errorMessage, allOpportunities.isEmpty {
                    errorView(error)
                } else if filteredOpportunities.isEmpty {
                    emptyView
                } else {
                    opportunitiesList
                }
            }
        }
        .task {
            if isPOTAActivation, let grid = userGrid, !grid.isEmpty {
                await loadOpportunities()
            }
        }
        .task(id: "auto-refresh") {
            guard isPOTAActivation, let grid = userGrid, !grid.isEmpty else {
                return
            }
            await autoRefreshLoop()
        }
    }

    // MARK: Private

    @State private var allOpportunities: [P2POpportunity] = []
    @State private var isLoading = true
    @State private var loadingProgress: P2PProgress = .fetchingPOTASpots
    @State private var errorMessage: String?
    @State private var bandFilter: BandFilter
    @State private var modeFilter: ModeFilter
    @State private var showFilterSheet = false

    private var filteredOpportunities: [P2POpportunity] {
        allOpportunities.filter { opportunity in
            if let targetBand = bandFilter.bandName {
                guard opportunity.band == targetBand else {
                    return false
                }
            }
            guard modeFilter.matches(opportunity.mode) else {
                return false
            }
            return true
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

    private var filterDisplayText: String {
        let bandText = bandFilter == .all ? "All Bands" : bandFilter.rawValue
        let modeText = modeFilter == .all ? "All Modes" : modeFilter.rawValue

        if bandFilter == .all, modeFilter == .all {
            return "All"
        } else if modeFilter == .all {
            return bandText
        } else if bandFilter == .all {
            return modeText
        } else {
            return "\(bandText) \u{2022} \(modeText)"
        }
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
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
                filterSheet
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text("\(filteredOpportunities.count) P2P")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Band") {
                    Picker("Band", selection: $bandFilter) {
                        ForEach(BandFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Mode") {
                    Picker("Mode", selection: $modeFilter) {
                        ForEach(ModeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filter P2P")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilterSheet = false }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        bandFilter = .all
                        modeFilter = .all
                    }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
    }

    // MARK: - Content Views

    private var notActivatingView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("P2P requires a POTA activation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Start a POTA session to find P2P opportunities")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noGridView: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Grid square required")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Set your grid in session settings to find P2P opportunities")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No P2P opportunities right now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if bandFilter != .all || modeFilter != .all {
                Button("Clear Filters") {
                    bandFilter = .all
                    modeFilter = .all
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var opportunitiesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(opportunitiesByBand, id: \.band) { section in
                    Section {
                        ForEach(section.opportunities) { opportunity in
                            P2POpportunityRow(opportunity: opportunity) {
                                onSelectOpportunity(opportunity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

// MARK: - Data Loading

extension SidebarP2PView {
    func loadOpportunities() async {
        isLoading = true
        errorMessage = nil
        loadingProgress = .fetchingPOTASpots

        guard let callsign = userCallsign, let grid = userGrid else {
            return
        }

        do {
            let rbnClient = RBNClient()
            let potaClient = POTAClient(authService: POTAAuthService())
            let service = P2PService(rbnClient: rbnClient, potaClient: potaClient)

            allOpportunities = try await service.findOpportunities(
                userGrid: grid,
                userCallsign: callsign
            ) { @Sendable progress in
                Task { @MainActor in
                    loadingProgress = progress
                }
            }
            isLoading = false
        } catch let error as P2PError {
            errorMessage = error.errorDescription
            if allOpportunities.isEmpty {
                isLoading = false
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            if allOpportunities.isEmpty {
                isLoading = false
            }
            isLoading = false
        }
    }

    func autoRefreshLoop() async {
        while !Task.isCancelled {
            // P2P involves RBN queries so use longer interval
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else {
                return
            }
            await loadOpportunities()
        }
    }
}
