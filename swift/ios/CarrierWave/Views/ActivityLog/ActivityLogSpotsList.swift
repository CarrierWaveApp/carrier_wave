import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SpotSortOrder

/// How to sort the spot list
enum SpotSortOrder: String, CaseIterable {
    case recent = "Recent"
    case frequency = "Frequency"
    case needs = "Needs"
}

// MARK: - ActivityLogSpotsList

/// Spot list for the hunter workflow. Shows POTA, SOTA, and RBN spots with
/// worked-before badges, filtering, and sort options.
struct ActivityLogSpotsList: View {
    // MARK: Internal

    let spots: [EnrichedSpot]
    @Binding var filters: SpotFilters

    /// Engine `allowed_spot_ids` when "Filter by saved query" is active;
    /// nil = no SQL filter (widget filters only).
    let allowedSpotIds: Set<String>?

    /// When the engine last completed a poll (nil = never this session).
    let lastRefresh: Date?

    let maxAgeMinutes: Int
    let selectedContinents: Set<SpotContinent>
    let huntedBehavior: HuntedSpotBehavior
    let workedBeforeCache: WorkedBeforeCache
    let workedCacheVersion: Int
    let manager: ActivityLogManager
    let container: ModelContainer
    let hasFetched: Bool
    let onShowFilterSheet: () -> Void
    let onSpotLogged: (_ frequencyMHz: Double, _ mode: String) -> Void
    var onRecallSpot: ((EnrichedSpot) -> Void)?

    @State var spotConfirm = SpotConfirmContext()

    /// Read by `ActivityLogSpotsList+UnreadDivider` to gate the divider on a
    /// time-based sort.
    @State var sortOrder: SpotSortOrder = .recent
    /// Most recent spot timestamp the user had seen as of the previous time
    /// they were on this surface (`Date.timeIntervalSince1970`). Persisted so
    /// it survives tab switches and app launches. 0 = never viewed.
    @AppStorage("hunterLastViewedSpotTimestamp")
    var lastViewedSpotTimestamp: Double = 0

    /// Frozen copy of `lastViewedSpotTimestamp` captured on `.onAppear`. Used
    /// to position the "new since last view" divider so it doesn't jump
    /// while the user is reading — without this, the divider would slide as
    /// each poll cycle pushes more spots above it and we re-saved the
    /// high-water mark. Read by the divider helpers in
    /// `ActivityLogSpotsList+UnreadDivider`.
    @State var sessionDividerBoundary: Double = 0

    /// Internal so `ActivityLogSpotsList+UnreadDivider` can compute the
    /// non-dupe / dupe partition for `sortedSpots`.
    @State var workedResults: [String: WorkedBeforeResult] = [:]

    /// Summary of needs matched in current spot set.
    var needsSummary: NeedsOnAirSummary {
        SpotNeedsMatcher.summarize(filteredSpots)
    }

    /// Internal so `ActivityLogSpotsList+UnreadDivider.sortedSpots` can read
    /// the filtered set when computing the primary order.
    var filteredSpots: [EnrichedSpot] {
        filters.apply(
            to: spots,
            workedResults: workedResults,
            maxAgeMinutes: maxAgeMinutes,
            selectedContinents: selectedContinents,
            allowedSpotIds: allowedSpotIds
        )
    }

    /// Dedup by callsign+band, preferring POTA > SOTA > RBN and newest timestamp.
    /// When huntedBehavior is .hide, filters out spots already worked today on same band.
    /// Internal so `ActivityLogSpotsList+UnreadDivider.sortedSpots` can read it.
    var dedupedSpots: [EnrichedSpot] {
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
                return !result.isDupe(on: spot.spot.band, mode: spot.spot.mode, park: spot.spot.parkRef)
            }
        }
        return results
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            spotsHeader
            filterChips

            NeedsSummaryCard(summary: needsSummary) {
                filters.needsOnly.toggle()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            sortPicker

            if sortedSpots.isEmpty {
                if spots.isEmpty, !hasFetched {
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
                let park = spot.spot.parkRef
                Task {
                    await workedBeforeCache.recordQSO(
                        callsign: callsign,
                        band: band,
                        mode: mode,
                        park: park
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
        .modifier(SpotConfirmAlertModifier(
            context: $spotConfirm,
            onConfirm: { sendSpot($0) }
        ))
        .task(id: WorkedRefreshKey(
            spotIDs: spots.map(\.id),
            version: workedCacheVersion,
            utcDate: Self.currentUTCDateString
        )) {
            await loadWorkedBefore()
        }
        .onAppear {
            // Freeze the divider at the previous high-water mark for this
            // viewing session; the divider stays anchored even as new spots
            // arrive every 2 minutes.
            sessionDividerBoundary = lastViewedSpotTimestamp
        }
        .onDisappear {
            // Advance the persisted mark to the newest spot we showed, so the
            // next viewing session anchors against it. `max` avoids regressing
            // on a tab switch that returned empty results.
            if let newest = spots.map(\.spot.timestamp).max() {
                let candidate = newest.timeIntervalSince1970
                if candidate > lastViewedSpotTimestamp {
                    lastViewedSpotTimestamp = candidate
                }
            }
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

    @State private var selectedSpot: EnrichedSpot?
    @State private var showAll = false
    @State private var dupeConfirmSpot: EnrichedSpot?
    @State private var showDupeAlert = false

    private var acceptedFriends: [Friendship] {
        FriendsSyncService.shared.acceptedFriends
    }

    private var friendCallsigns: Set<String> {
        Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
    }

    // MARK: - Header & controls

    private var spotsHeader: some View {
        HStack {
            Text("Spots")
                .font(.subheadline.weight(.semibold))
            if let lastRefresh {
                lastRefreshPill(lastRefresh)
            }
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
            Text(
                "Spots from POTA, SOTA, and RBN refresh automatically about "
                    + "every 2 minutes. Pull down to refresh now."
            )
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
        let boundary = newSinceLastViewIndex(in: rowSpots)
        return ForEach(Array(rowSpots.enumerated()), id: \.element.id) { index, spot in
            VStack(spacing: 0) {
                if let boundary, index == boundary {
                    newSinceLastViewDivider(newCount: boundary)
                }

                ActivityLogSpotRow(
                    spot: spot,
                    workedResult: workedResults[spot.spot.callsign.uppercased()]
                        ?? .notWorked,
                    huntedBehavior: huntedBehavior,
                    isFriend: friendCallsigns.contains(
                        spot.spot.callsign.uppercased()
                    ),
                    onTap: { handleSpotTap(spot) },
                    onTuneIn: { handleTuneIn(spot) },
                    onRecall: { onRecallSpot?(spot) },
                    onSpot: { handleSpot(spot) }
                )

                if spot.id != rowSpots.last?.id {
                    Divider()
                        .padding(.leading, 92)
                }
            }
        }
    }
}

// MARK: - Actions & Data Loading

extension ActivityLogSpotsList {
    /// "X ago" pill for the last completed engine poll. `.relative` keeps
    /// the text ticking without a timer.
    func lastRefreshPill(_ date: Date) -> some View {
        Text("\(Text(date, style: .relative)) ago")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
            .accessibilityLabel("Spots last refreshed")
    }

    func handleSpotTap(_ spot: EnrichedSpot) {
        tuneRadioToSpot(spot)

        let result = workedResults[spot.spot.callsign.uppercased()] ?? .notWorked
        if result.isDupe(on: spot.spot.band, mode: spot.spot.mode, park: spot.spot.parkRef) {
            dupeConfirmSpot = spot
            showDupeAlert = true
        } else {
            selectedSpot = spot
        }
    }

    func tuneRadioToSpot(_ spot: EnrichedSpot) {
        let radio = RadioService.shared
        guard radio.isConnected else {
            return
        }
        let resolvedMode = RadioCommandParser.resolveMode(
            spot.spot.mode,
            frequencyMHz: spot.spot.frequencyMHz
        )
        radio.setFrequency(spot.spot.frequencyMHz)
        radio.setMode(resolvedMode)
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
