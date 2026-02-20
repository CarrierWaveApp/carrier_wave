import CarrierWaveCore
import SwiftData
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

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var allSpots: [POTASpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var bandFilter: BandFilter
    @State private var modeFilter: ModeFilter
    @State private var showFilterSheet = false
    @State private var workedBeforeCache = WorkedBeforeCache()
    @State private var workedResults: [String: WorkedBeforeResult] = [:]

    private var friendCallsigns: Set<String> {
        Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
    }

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
        Self.groupSpotsByBand(filteredSpots)
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

            Text("\(filteredSpots.count) spots")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - Content Views

    private var spotsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(spotsByBand, id: \.band) { section in
                    Section {
                        ForEach(section.spots) { spot in
                            let result = workedResults[spot.activator.uppercased()]
                                ?? .notWorked
                            POTASpotRow(
                                spot: spot,
                                userCallsign: userCallsign,
                                friendCallsigns: friendCallsigns,
                                workedResult: result
                            ) {
                                onSelectSpot?(spot)
                            }
                            .opacity(spot.isAutomatedSpot ? 0.7 : 1.0)
                            Divider()
                                .padding(.leading, 92)
                        }
                    } header: {
                        POTASpotsBandHeader(band: section.band)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private static func groupSpotsByBand(
        _ spots: [POTASpot]
    ) -> [(band: String, spots: [POTASpot])] {
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
                // Human spots first, then RBN; secondary sort by frequency
                spots: $0.value.sorted { lhs, rhs in
                    if lhs.isHumanSpot != rhs.isHumanSpot {
                        return lhs.isHumanSpot
                    }
                    return (lhs.frequencyKHz ?? 0) < (rhs.frequencyKHz ?? 0)
                }
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
            await loadWorkedBefore()
        } catch {
            errorMessage = error.localizedDescription
            allSpots = []
            isLoading = false
        }
    }

    private func loadWorkedBefore() async {
        let container = modelContext.container
        await workedBeforeCache.loadToday(container: container)

        let callsigns = allSpots.map(\.activator)
        await workedBeforeCache.checkCallsigns(callsigns, container: container)

        var results: [String: WorkedBeforeResult] = [:]
        for spot in allSpots {
            let upper = spot.activator.uppercased()
            let band = BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
            results[upper] = await workedBeforeCache.result(
                for: upper,
                band: band
            )
        }
        workedResults = results
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
