import CarrierWaveCore
import CarrierWaveData
import Charts
import SwiftData
import SwiftUI

// MARK: - OnAirCard

/// Unified dashboard card combining conditions, DXpeditions, and contests
/// into a single "On Air Now" glanceable summary with progressive disclosure.
struct OnAirCard: View {
    // MARK: Internal

    /// How recently `loadAllData` must have completed for `.task` to
    /// short-circuit. Solar / DX / spot data changes on the order of
    /// minutes, not seconds, so 60 s is a comfortable freshness window.
    static let loadFreshnessWindow: TimeInterval = 60

    let tourState: TourState

    @Environment(\.modelContext) var modelContext

    // Conditions state.
    //
    // Previously used `@Query<SolarSnapshot>` for reactivity, but that
    // created a dependency on every container save (CloudKit sync, QSO
    // inserts, etc.) and tanked dashboard scroll performance — every save
    // invalidated `body` and forced a full re-render of the card mid-scroll.
    // Now: one-shot fetch in `loadConditions()` plus a refresh on the
    // `.didStoreSolarSnapshot` notification (fires at most every 30 min
    // due to `SolarPollingService`'s dedup window).
    @State var latestSolar: SolarSnapshot?
    @State var snapshots: [EnvironmentalSnapshot] = []
    @State var solarData: HamQSLSolarData?
    @State var bandEstimates: [BandPropagation] = []

    // DXpeditions state
    @State var expeditions: [Ham365DXpedition] = []
    @State var onAirSpots: [String: [RBNSpot]] = [:]
    @State var dxError: String?

    // Friend spots state
    //
    // `@State` + manual fetch instead of `@Query` — `@Query` on Friendship
    // observes EVERY SwiftData container save (CloudKit syncs, QSO inserts,
    // ActivityItem writes, anything), invalidating this card's body on each
    // unrelated save and cascading into dashboard scroll jank. Friendships
    // change rarely; refetch in `.task` (re-fires on view re-appear).
    @State var acceptedFriends: [Friendship] = []
    @State var friendSpots: [(callsign: String, spot: POTASpot)] = []

    // POTA/SOTA spot state
    @State var potaSpots: [POTASpot] = []
    @State var sotaSpots: [SOTASpot] = []

    /// Operator names looked up from QRZ/HamDB/Polo notes, keyed by callsign.
    @State var operatorNames: [String: String] = [:]

    /// Total QSO contact counts by callsign, for badge display.
    @State var contactCounts: [String: Int] = [:]

    /// Contests state
    @State var contestService = ContestPollingService.shared

    // Section visibility prefs
    @AppStorage("onAirShowConditions") var showConditions = true
    @AppStorage("onAirShowDXpeditions") var showDXpeditions = true
    @AppStorage("onAirShowContests") var showContests = true
    @AppStorage("onAirShowFriendSpots") var showFriendSpots = true
    @AppStorage("onAirShowPOTASpots") var showPOTASpots = true
    @AppStorage("onAirShowSOTASpots") var showSOTASpots = true
    @AppStorage("onAirBandFilter") var bandFilterRaw = ""
    @AppStorage("onAirModeFilter") var modeFilterRaw = ""

    /// Read from the same canonical key as `OperatorRole.storageKey`. When the
    /// user has explicitly chosen `.hunter`, the dashboard suppresses the
    /// inline POTA/SOTA/Friend spot sections — they are a strictly less
    /// capable duplicate of the Hunter Log spot list (no worked-before /
    /// dupe / needs / clubs enrichment) and only one tap away. Non-hunter
    /// roles see the existing sections unchanged.
    @AppStorage(OperatorRole.storageKey) var operatorRoleRaw = ""
    /// Loading
    @State var isLoading = true

    /// Timestamp of the most recent successful `loadAllData` call. Used to
    /// skip redundant reloads when SwiftUI re-fires `.task` on tab switch
    /// back to the dashboard. Each `loadAllData` kicks off 5 parallel
    /// network/database requests and emits ~11 staged `@Observable` writes
    /// at completion — re-firing on every tab return cascaded into body
    /// invalidations and visible scroll chop.
    @State var lastLoadedAt: Date = .distantPast

    @AppStorage("onAirSpotMaxAgeMinutes") var spotMaxAgeMinutes = 30

    let dataActor = EnvironmentalDataActor()
    let ham365Client = Ham365Client()
    let rbnClient = RBNClient()

    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .onTapGesture {
                showingSheet = true
            }
            .sheet(isPresented: $showingSheet) {
                OnAirSheet(
                    tourState: tourState,
                    snapshots: snapshots,
                    solarData: solarData,
                    bandEstimates: bandEstimates,
                    expeditions: expeditions,
                    onAirSpots: onAirSpots,
                    contestService: contestService,
                    friendSpots: friendSpots,
                    potaSpots: potaSpots,
                    sotaSpots: sotaSpots,
                    operatorNames: operatorNames,
                    contactCounts: contactCounts
                )
            }
            .task {
                await loadAllData()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didStoreSolarSnapshot)
            ) { _ in
                Task { await refreshLatestSolar() }
            }
    }

    // MARK: Private

    // MARK: - Computed

    private struct ExpeditionPartitions {
        var onAir: [Ham365DXpedition] = []
        var activeToday: [Ham365DXpedition] = []
        var upcoming: [Ham365DXpedition] = []
    }

    @State private var showingSheet = false

    private var roleIsHunter: Bool {
        OperatorRole(rawValue: operatorRoleRaw) == .hunter
    }

    private var partitions: ExpeditionPartitions {
        var result = ExpeditionPartitions()
        for exp in expeditions {
            if exp.isOnAir {
                result.onAir.append(exp)
            } else if exp.isActiveToday {
                result.activeToday.append(exp)
            } else if !exp.activeDays.isEmpty {
                result.upcoming.append(exp)
            }
        }
        return result
    }

    private var liveCount: Int {
        var count = 0
        if showDXpeditions {
            count += partitions.onAir.count
        }
        if showContests {
            count += contestService.activeContests.count
        }
        return count
    }

    private var latestSolarSnapshot: EnvironmentalSnapshot? {
        snapshots.last { $0.hasSolarData }
    }

    /// Priority-sorted merged list of DXpeditions and contests for compact display.
    private var mergedItems: [OnAirItem] {
        let parts = partitions
        var items: [OnAirItem] = []

        // 1. ON AIR DXpeditions (by spot count desc)
        for dx in parts.onAir.sorted(by: { spotCount($0) > spotCount($1) }) {
            items.append(.dxpedition(dx, isLive: true))
        }

        // 2. Active contests (ending soonest first)
        for contest in contestService.activeContests {
            items.append(.contest(contest, isLive: true))
        }

        // 3. Active-today DXpeditions
        for dx in parts.activeToday {
            items.append(.dxpedition(dx, isLive: false))
        }

        // 4. Upcoming contests
        for contest in contestService.upcomingContests.prefix(2) {
            items.append(.contest(contest, isLive: false))
        }

        // 5. Upcoming DXpeditions
        for dx in parts.upcoming {
            items.append(.dxpedition(dx, isLive: false))
        }

        return Array(items.prefix(4))
    }

    /// Merged items filtered by section visibility prefs.
    private var filteredMergedItems: [OnAirItem] {
        mergedItems.filter { item in
            switch item {
            case .dxpedition: showDXpeditions
            case .contest: showContests
            }
        }
    }

    private var spotBands: Set<String> {
        OnAirSpotFilter.decodeSet(from: bandFilterRaw)
    }

    private var spotModes: Set<String> {
        OnAirSpotFilter.decodeSet(from: modeFilterRaw)
    }

    private var filteredPOTASpots: [POTASpot] {
        OnAirSpotFilter.filterPOTA(
            potaSpots, bands: spotBands, modes: spotModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    private var filteredSOTASpots: [SOTASpot] {
        OnAirSpotFilter.filterSOTA(
            sotaSpots, bands: spotBands, modes: spotModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    private var filteredFriendSpots: [(callsign: String, spot: POTASpot)] {
        OnAirSpotFilter.filterFriends(
            friendSpots, bands: spotBands, modes: spotModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    // MARK: - Card Content

    private var activeFiltersRow: some View {
        OnAirActiveFiltersView(
            bands: spotBands, modes: spotModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            activeFiltersRow
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                if showConditions {
                    conditionsRow
                    SpaceWeatherConditionRow()
                }
                let filteredItems = filteredMergedItems
                if filteredItems.isEmpty {
                    if !showDXpeditions, !showContests {
                        EmptyView()
                    } else {
                        emptyState
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(
                            Array(filteredItems.enumerated()),
                            id: \.offset
                        ) { _, item in
                            itemRow(item)
                        }
                    }
                }
                // Glance surface: spots collapse to a one-line count summary
                // (full rows live on the sheet, one tap away). Hunters route
                // to the strictly-more-capable Hunter Log instead.
                if roleIsHunter {
                    openHunterLogLink
                } else {
                    spotsSummaryRow(
                        potaCount: showPOTASpots ? filteredPOTASpots.count : 0,
                        sotaCount: showSOTASpots ? filteredSOTASpots.count : 0,
                        friendCount: showFriendSpots ? filteredFriendSpots.count : 0
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack {
            Image(systemName: "radio")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text("On Air Now")
                .font(.headline)

            if liveCount > 0 {
                Text("\(liveCount) live")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .badgePill(Color.green)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var conditionsRow: some View {
        // Prefer the cached `SolarSnapshot` (refreshed on .didStoreSolarSnapshot)
        // over the one-shot EnvironmentalSnapshot history fallback.
        let kVal: Double? = latestSolar?.kIndex ?? latestSolarSnapshot?.solarKIndex
        let sfi: Double? = latestSolar?.solarFlux ?? latestSolarSnapshot?.solarFlux
        let aIdx: Int? = latestSolar?.aIndex ?? latestSolarSnapshot?.solarAIndex
        let rating: String? = latestSolar?.propagationRating ?? solarData?.propagationRating

        if kVal != nil || sfi != nil || aIdx != nil {
            HStack(spacing: 8) {
                if let kVal {
                    conditionPill(
                        icon: "waveform",
                        label: "K",
                        value: String(format: "%.0f", kVal),
                        color: kIndexColor(kVal)
                    )
                }
                if let sfi {
                    conditionPill(
                        icon: "sun.max.fill",
                        label: "SFI",
                        value: "\(Int(sfi))",
                        color: .orange
                    )
                }
                if let aIdx {
                    conditionPill(
                        icon: "waveform.path",
                        label: "A",
                        value: "\(aIdx)",
                        color: .purple
                    )
                }
                if let rating {
                    Spacer()
                    Text(rating)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ratingColor(rating))
                        .badgePill(ratingColor(rating).opacity(0.12))
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("No activity right now")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }
}
