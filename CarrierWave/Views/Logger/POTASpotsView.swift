import SwiftUI

// MARK: - POTASpotsView

/// Panel showing active POTA spots with filtering
struct POTASpotsView: View {
    // MARK: Lifecycle

    init(
        initialBand: String? = nil,
        initialMode: String? = nil,
        onDismiss: @escaping () -> Void,
        onSelectSpot: ((POTASpot) -> Void)? = nil
    ) {
        self.onDismiss = onDismiss
        self.onSelectSpot = onSelectSpot
        _bandFilter = State(initialValue: BandFilter.from(bandName: initialBand))
        _modeFilter = State(initialValue: ModeFilter.from(modeName: initialMode))
    }

    // MARK: Internal

    let onDismiss: () -> Void
    let onSelectSpot: ((POTASpot) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if filteredSpots.isEmpty {
                emptyView
            } else {
                spotsList
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadSpots()
        }
    }

    // MARK: Private

    @State private var allSpots: [POTASpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var bandFilter: BandFilter
    @State private var modeFilter: ModeFilter
    @State private var showFilterSheet = false

    private var filteredSpots: [POTASpot] {
        allSpots.filter { spot in
            if let targetBand = bandFilter.bandName {
                guard let spotBand = BandUtilities.deriveBand(from: spot.frequencyKHz),
                      spotBand == targetBand
                else {
                    return false
                }
            }
            guard modeFilter.matches(spot.mode) else {
                return false
            }
            return true
        }
    }

    private var spotsByBand: [(band: String, spots: [POTASpot])] {
        let grouped = Dictionary(grouping: filteredSpots) { spot -> String in
            BandUtilities.deriveBand(from: spot.frequencyKHz) ?? "Other"
        }
        return grouped.sorted { lhs, rhs in
            let lhsIdx = BandUtilities.bandOrder.firstIndex(of: lhs.key) ?? 999
            let rhsIdx = BandUtilities.bandOrder.firstIndex(of: rhs.key) ?? 999
            return lhsIdx < rhsIdx
        }.map {
            (
                band: $0.key,
                spots: $0.value.sorted { ($0.frequencyKHz ?? 0) < ($1.frequencyKHz ?? 0) }
            )
        }
    }

    private var filterDisplayText: String {
        let bandText = bandFilter == .all ? "All Bands" : bandFilter.rawValue
        let modeText = modeFilter == .all ? "All Modes" : modeFilter.rawValue

        if bandFilter == .all, modeFilter == .all {
            return "All Spots"
        } else if modeFilter == .all {
            return bandText
        } else if bandFilter == .all {
            return modeText
        } else {
            return "\(bandText) • \(modeText)"
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "tree.fill")
                .foregroundStyle(.green)
            Text("POTA Spots")
                .font(.headline)
            Spacer()
            Button {
                Task { await loadSpots() }
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
        VStack(spacing: 8) {
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                    Text(filterDisplayText)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
            }

            Text("Showing \(filteredSpots.count) of \(allSpots.count) Spots")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
            .navigationTitle("Filter Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showFilterSheet = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        bandFilter = .all
                        modeFilter = .all
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading POTA spots...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tree")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots match filters")
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
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var spotsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(spotsByBand, id: \.band) { section in
                    Section {
                        ForEach(section.spots) { spot in
                            POTASpotRow(spot: spot) {
                                onSelectSpot?(spot)
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
                Task { await loadSpots() }
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

    // MARK: - Data Loading

    private func loadSpots() async {
        isLoading = true
        errorMessage = nil

        do {
            let client = POTAClient(authService: POTAAuthService())
            allSpots = try await client.fetchActiveSpots()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            allSpots = []
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview {
    POTASpotsView(
        initialBand: "20m",
        initialMode: "CW",
        onDismiss: {}
    )
    .frame(height: 500)
    .padding()
}
