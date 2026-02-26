import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SidebarPOTASpotsView

/// POTA and SOTA spots adapted for persistent iPad sidebar display.
/// No dismiss button, full height, auto-refresh every 60 seconds.
struct SidebarPOTASpotsView: View {
    // MARK: Lifecycle

    init(
        userCallsign: String? = nil,
        initialBand: String? = nil,
        initialMode: String? = nil,
        onSelectSpot: @escaping (POTASpot) -> Void
    ) {
        self.userCallsign = userCallsign
        self.onSelectSpot = onSelectSpot
        _bandFilter = State(initialValue: BandFilter.from(bandName: initialBand))
        _modeFilter = State(initialValue: ModeFilter.from(modeName: initialMode))
    }

    // MARK: Internal

    let userCallsign: String?
    let onSelectSpot: (POTASpot) -> Void

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            if isLoading, allSpots.isEmpty {
                POTASpotsLoadingView()
            } else if let error = errorMessage, allSpots.isEmpty {
                POTASpotsErrorView(message: error) {
                    Task { await loadSpots() }
                }
            } else if filteredSpots.isEmpty, filteredSOTASpots.isEmpty {
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
        .task {
            await loadSpots()
        }
        .task(id: "auto-refresh") {
            await autoRefreshLoop()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var allSpots: [POTASpot] = []
    @State private var allSOTASpots: [SOTASpot] = []
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

    private var filteredSOTASpots: [SOTASpot] {
        allSOTASpots.filter { spot in
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

    private var sotaSpotsByBand: [(band: String, spots: [SOTASpot])] {
        groupSOTASpotsByBand(filteredSOTASpots)
    }

    private var spotsByBand: [(band: String, spots: [POTASpot])] {
        groupSpotsByBand(filteredSpots)
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
            return "\(bandText) \u{2022} \(modeText)"
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

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text("\(filteredSpots.count + filteredSOTASpots.count) spots")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Content Views

    private var spotsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                potaSpotsSection
                sotaSpotsSection
            }
        }
    }

    private var potaSpotsSection: some View {
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
                        onSelectSpot(spot)
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

    @ViewBuilder
    private var sotaSpotsSection: some View {
        if !filteredSOTASpots.isEmpty {
            ForEach(sotaSpotsByBand, id: \.band) { section in
                Section {
                    ForEach(section.spots) { spot in
                        let callKey = spot.activatorCallsign.uppercased()
                        let result = workedResults[callKey] ?? .notWorked
                        SOTASpotRow(
                            spot: spot,
                            friendCallsigns: friendCallsigns,
                            workedResult: result
                        ) {
                            // SOTA spot tapped — not yet wired to QSO prefill
                        }
                        Divider()
                            .padding(.leading, 92)
                    }
                } header: {
                    SOTASpotsBandHeader(band: section.band)
                }
            }
        }
    }

    private func groupSpotsByBand(
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
                spots: $0.value.sorted { lhs, rhs in
                    if lhs.isHumanSpot != rhs.isHumanSpot {
                        return lhs.isHumanSpot
                    }
                    return (lhs.frequencyKHz ?? 0) < (rhs.frequencyKHz ?? 0)
                }
            )
        }
    }

    private func groupSOTASpotsByBand(
        _ spots: [SOTASpot]
    ) -> [(band: String, spots: [SOTASpot])] {
        let grouped = Dictionary(grouping: spots) { spot -> String in
            BandUtilities.deriveBand(from: spot.frequencyKHz) ?? "Other"
        }
        return grouped.sorted { lhs, rhs in
            let lhsIdx = BandUtilities.bandOrder.firstIndex(of: lhs.key) ?? 999
            let rhsIdx = BandUtilities.bandOrder.firstIndex(of: rhs.key) ?? 999
            return lhsIdx < rhsIdx
        }.map {
            (band: $0.key, spots: $0.value.sorted { ($0.frequencyKHz ?? 0) < ($1.frequencyKHz ?? 0) })
        }
    }

    // MARK: - Data Loading

    private func loadSpots() async {
        isLoading = true
        errorMessage = nil

        do {
            let client = POTAClient(authService: POTAAuthService())
            async let potaResult = client.fetchActiveSpots()
            async let sotaResult = SOTAClient().fetchSpots(count: 50)

            allSpots = try await potaResult
            allSOTASpots = await (try? sotaResult) ?? []
            isLoading = false
            await loadWorkedBefore()
        } catch {
            errorMessage = error.localizedDescription
            allSpots = []
            allSOTASpots = []
            isLoading = false
        }
    }

    private func loadWorkedBefore() async {
        let container = modelContext.container
        await workedBeforeCache.loadToday(container: container)

        let potaCallsigns = allSpots.map(\.activator)
        let sotaCallsigns = allSOTASpots.map(\.activatorCallsign)
        let allCallsigns = potaCallsigns + sotaCallsigns
        await workedBeforeCache.checkCallsigns(allCallsigns, container: container)

        var results: [String: WorkedBeforeResult] = [:]
        for spot in allSpots {
            let upper = spot.activator.uppercased()
            let band = BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
            results[upper] = await workedBeforeCache.result(
                for: upper,
                band: band
            )
        }
        for spot in allSOTASpots {
            let upper = spot.activatorCallsign.uppercased()
            let band = BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
            results[upper] = await workedBeforeCache.result(
                for: upper,
                band: band
            )
        }
        workedResults = results
    }

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else {
                return
            }
            await loadSpots()
        }
    }
}
