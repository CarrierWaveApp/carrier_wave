import CarrierWaveCore
import SwiftUI

// MARK: - POTASpotsView

/// Panel showing active POTA spots with filtering
struct POTASpotsView: View {
    // MARK: Lifecycle

    init(
        userCallsign: String? = nil,
        initialBand: String? = nil,
        initialMode: String? = nil,
        onDismiss: @escaping () -> Void,
        onSelectSpot: ((POTASpot) -> Void)? = nil
    ) {
        self.userCallsign = userCallsign
        self.onDismiss = onDismiss
        self.onSelectSpot = onSelectSpot
        _bandFilter = State(initialValue: BandFilter.from(bandName: initialBand))
        _modeFilter = State(initialValue: ModeFilter.from(modeName: initialMode))
    }

    // MARK: Internal

    let userCallsign: String?
    let onDismiss: () -> Void
    let onSelectSpot: ((POTASpot) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()

            if isLoading {
                POTASpotsLoadingView()
            } else if let error = errorMessage {
                POTASpotsErrorView(message: error) {
                    Task { await loadSpots() }
                }
            } else if filteredSpots.isEmpty {
                POTASpotsEmptyView(
                    hasFilters: bandFilter != .all || modeFilter != .all,
                    onClearFilters: {
                        bandFilter = .all
                        modeFilter = .all
                    }
                )
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
    @State private var showAutomatedSpots = false

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

    /// Human-generated spots (highlighted, shown first)
    private var humanSpots: [POTASpot] {
        filteredSpots.filter(\.isHumanSpot)
    }

    /// Automated spots from RBN (collapsed by default)
    private var automatedSpots: [POTASpot] {
        filteredSpots.filter(\.isAutomatedSpot)
    }

    private var spotsByBand: [(band: String, spots: [POTASpot])] {
        Self.groupSpotsByBand(humanSpots)
    }

    private var automatedSpotsByBand: [(band: String, spots: [POTASpot])] {
        Self.groupSpotsByBand(automatedSpots)
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
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                POTASpotsFilterSheet(
                    bandFilter: $bandFilter,
                    modeFilter: $modeFilter,
                    isPresented: $showFilterSheet
                )
            }

            Spacer()

            // Show human/total breakdown
            if automatedSpots.isEmpty {
                Text("\(filteredSpots.count) spots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(humanSpots.count) + \(automatedSpots.count) RBN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - Content Views

    private var spotsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                // Human spots first (by band)
                ForEach(spotsByBand, id: \.band) { section in
                    Section {
                        ForEach(section.spots) { spot in
                            POTASpotRow(spot: spot, userCallsign: userCallsign) {
                                onSelectSpot?(spot)
                            }
                            Divider()
                                .padding(.leading, 92)
                        }
                    } header: {
                        POTASpotsBandHeader(band: section.band)
                    }
                }

                // Collapsible automated spots section
                if !automatedSpots.isEmpty {
                    AutomatedSpotsSection(
                        automatedSpots: automatedSpots,
                        automatedSpotsByBand: automatedSpotsByBand,
                        userCallsign: userCallsign,
                        onSelectSpot: onSelectSpot,
                        isExpanded: $showAutomatedSpots
                    )
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private static func groupSpotsByBand(_ spots: [POTASpot]) -> [(band: String, spots: [POTASpot])] {
        let grouped = Dictionary(grouping: spots) { spot -> String in
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
        userCallsign: "W1AW",
        initialBand: "20m",
        initialMode: "CW",
        onDismiss: {}
    )
    .frame(height: 500)
    .padding()
}
