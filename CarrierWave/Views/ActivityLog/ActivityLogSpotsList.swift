import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SpotSortOrder

/// How to sort the spot list
enum SpotSortOrder: String, CaseIterable {
    case recent = "Recent"
    case frequency = "Frequency"
}

// MARK: - ActivityLogSpotsList

/// Spot list for the hunter workflow. Shows POTA, SOTA, and RBN spots with
/// worked-before badges, filtering, and sort options.
struct ActivityLogSpotsList: View {
    // MARK: Internal

    let spots: [EnrichedSpot]
    @Binding var filters: SpotFilters

    let maxAgeMinutes: Int
    let selectedRegions: Set<SpotRegionGroup>
    let huntedBehavior: HuntedSpotBehavior
    let workedBeforeCache: WorkedBeforeCache
    let workedCacheVersion: Int
    let manager: ActivityLogManager
    let container: ModelContainer
    let onShowFilterSheet: () -> Void
    let onSpotLogged: (_ frequencyMHz: Double, _ mode: String) -> Void

    var sortedSpots: [EnrichedSpot] {
        let primarySorted: [EnrichedSpot] = switch sortOrder {
        case .recent:
            dedupedSpots.sorted { $0.spot.timestamp > $1.spot.timestamp }
        case .frequency:
            dedupedSpots.sorted { $0.spot.frequencyKHz < $1.spot.frequencyKHz }
        }

        // Partition: non-dupes first, dupes last (stable within each group)
        let nonDupes = primarySorted.filter { spot in
            let key = spot.spot.callsign.uppercased()
            let result = workedResults[key] ?? .notWorked
            return !result.isDupe(on: spot.spot.band, mode: spot.spot.mode)
        }
        let dupes = primarySorted.filter { spot in
            let key = spot.spot.callsign.uppercased()
            let result = workedResults[key] ?? .notWorked
            return result.isDupe(on: spot.spot.band, mode: spot.spot.mode)
        }
        return nonDupes + dupes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            spotsHeader
            filterChips
            sortPicker

            if sortedSpots.isEmpty {
                if spots.isEmpty {
                    loadingState
                } else {
                    emptyState
                }
            } else {
                spotContent
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $selectedSpot) { spot in
            SpotLogSheet(
                spot: spot,
                manager: manager
            ) {
                let callsign = spot.spot.callsign
                let band = spot.spot.band
                let mode = spot.spot.mode
                Task {
                    await workedBeforeCache.recordQSO(
                        callsign: callsign,
                        band: band,
                        mode: mode
                    )
                    let key = callsign.uppercased()
                    let updated = await workedBeforeCache.result(
                        for: callsign, band: band
                    )
                    workedResults[key] = updated
                }
                onSpotLogged(spot.spot.frequencyMHz, spot.spot.mode)
            }
        }
        .alert(
            "Duplicate QSO",
            isPresented: $showDupeAlert,
            presenting: dupeConfirmSpot
        ) { spot in
            Button("Log Anyway") { selectedSpot = spot }
            Button("Cancel", role: .cancel) {}
        } message: { spot in
            Text(
                "You already worked \(spot.spot.callsign) on \(spot.spot.band) today."
            )
        }
        .task(id: WorkedRefreshKey(
            spotIDs: spots.map(\.id),
            version: workedCacheVersion,
            utcDate: Self.currentUTCDateString
        )) {
            await loadWorkedBefore()
        }
    }

    // MARK: Private

    private static let visibleLimit = 50

    private static var currentUTCDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var selectedSpot: EnrichedSpot?
    @State private var workedResults: [String: WorkedBeforeResult] = [:]
    @State private var sortOrder: SpotSortOrder = .recent
    @State private var showAll = false
    @State private var dupeConfirmSpot: EnrichedSpot?
    @State private var showDupeAlert = false

    private var friendCallsigns: Set<String> {
        Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
    }

    private var filteredSpots: [EnrichedSpot] {
        filters.apply(
            to: spots,
            workedResults: workedResults,
            maxAgeMinutes: maxAgeMinutes,
            selectedRegions: selectedRegions
        )
    }

    /// Dedup by callsign+band, preferring POTA > SOTA > RBN and newest timestamp.
    /// When huntedBehavior is .hide, filters out spots already worked today on same band.
    private var dedupedSpots: [EnrichedSpot] {
        var best: [String: EnrichedSpot] = [:]
        for spot in filteredSpots {
            let key = "\(spot.spot.callsign.uppercased())|\(spot.spot.band)"
            if let existing = best[key] {
                let preferNew = spot.spot.source == .pota && existing.spot.source != .pota
                    || spot.spot.source == .wwff && existing.spot.source == .rbn
                    || spot.spot.source == .sota && existing.spot.source == .rbn
                    || spot.spot.source == existing.spot.source
                    && spot.spot.timestamp > existing.spot.timestamp
                if preferNew {
                    best[key] = spot
                }
            } else {
                best[key] = spot
            }
        }

        var results = Array(best.values)
        if huntedBehavior == .hide {
            results = results.filter { spot in
                let callKey = spot.spot.callsign.uppercased()
                let result = workedResults[callKey] ?? .notWorked
                return !result.isDupe(on: spot.spot.band, mode: spot.spot.mode)
            }
        }
        return results
    }

    // MARK: - Header & controls

    private var spotsHeader: some View {
        HStack {
            Text("Spots")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(clubFilteredSpots.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            filterButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var filterButton: some View {
        Button {
            onShowFilterSheet()
        } label: {
            Image(systemName: filters.hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .font(.subheadline)
                .foregroundStyle(filters.hasActiveFilters ? .blue : .secondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(
            filters.hasActiveFilters ? "Filters active, show filter options" : "Filter spots"
        )
    }

    private var filterChips: some View {
        SpotFilterBar(filters: $filters)
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sortOrder) {
            ForEach(SpotSortOrder.allCases, id: \.self) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading spots...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No spots yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Spots from POTA, SOTA, and RBN refresh automatically every 45 seconds")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var spotContent: some View {
        let total = clubFilteredSpots.count
        let hasMore = !showAll && total > Self.visibleLimit

        return LazyVStack(spacing: 0) {
            if !clubMemberSpots.isEmpty {
                clubSectionHeader("Club Members")
                spotRows(clubMemberSpots)

                if !otherSpots.isEmpty {
                    clubSectionHeader("Other Spots")
                }
            }

            let visibleOther: [EnrichedSpot] = if clubMemberSpots.isEmpty {
                showAll
                    ? clubFilteredSpots
                    : Array(clubFilteredSpots.prefix(Self.visibleLimit))
            } else {
                showAll
                    ? otherSpots
                    : Array(otherSpots.prefix(
                        max(Self.visibleLimit - clubMemberSpots.count, 0)
                    ))
            }
            spotRows(visibleOther)

            if hasMore {
                Button {
                    showAll = true
                } label: {
                    Text("Show \(total - Self.visibleLimit) More")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Spot rows

    private func spotRows(_ rowSpots: [EnrichedSpot]) -> some View {
        ForEach(rowSpots) { spot in
            ActivityLogSpotRow(
                spot: spot,
                workedResult: workedResults[spot.spot.callsign.uppercased()]
                    ?? .notWorked,
                huntedBehavior: huntedBehavior,
                isFriend: friendCallsigns.contains(spot.spot.callsign.uppercased()),
                onTap: { handleSpotTap(spot) },
                onTuneIn: { handleTuneIn(spot) }
            )

            if spot.id != rowSpots.last?.id {
                Divider()
                    .padding(.leading, 92)
            }
        }
    }
}

// MARK: - Actions & Data Loading

extension ActivityLogSpotsList {
    func handleSpotTap(_ spot: EnrichedSpot) {
        tuneRadioToSpot(spot)

        let result = workedResults[spot.spot.callsign.uppercased()] ?? .notWorked
        if result.isDupe(on: spot.spot.band, mode: spot.spot.mode) {
            dupeConfirmSpot = spot
            showDupeAlert = true
        } else {
            selectedSpot = spot
        }
    }

    func tuneRadioToSpot(_ spot: EnrichedSpot) {
        let radio = BLERadioService.shared
        guard radio.isConnected else {
            return
        }
        radio.setFrequency(spot.spot.frequencyMHz)
        radio.setMode(spot.spot.mode)
    }

    @MainActor
    func handleTuneIn(_ spot: EnrichedSpot) {
        let tuneInSpot = TuneInSpot(from: spot.spot)
        TuneInManager.shared.requestTuneIn(to: tuneInSpot)
    }

    func loadWorkedBefore() async {
        await workedBeforeCache.invalidateHistory()
        await workedBeforeCache.loadToday(container: container)
        let callsigns = spots.map(\.spot.callsign)
        await workedBeforeCache.checkCallsigns(callsigns, container: container)

        var results: [String: WorkedBeforeResult] = [:]
        for spot in spots {
            let key = spot.spot.callsign.uppercased()
            results[key] = await workedBeforeCache.result(
                for: spot.spot.callsign,
                band: spot.spot.band
            )
        }
        workedResults = results
    }
}

// MARK: - WorkedRefreshKey

/// Composite key for .task(id:) — re-runs when spots change, QSOs are modified,
/// or UTC date rolls over
private struct WorkedRefreshKey: Equatable {
    let spotIDs: [String]
    let version: Int
    let utcDate: String
}

// MARK: - EnrichedSpot + Equatable

extension EnrichedSpot: Equatable {
    static func == (lhs: EnrichedSpot, rhs: EnrichedSpot) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - EnrichedSpot + Hashable

extension EnrichedSpot: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
