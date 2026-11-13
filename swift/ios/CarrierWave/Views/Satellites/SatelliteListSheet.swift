import SwiftUI

// MARK: - SatelliteListSheet

/// Every satellite in the catalog as a list that points you at the bird.
/// Each row carries the next pass (24 h window) and a compass arrow toward
/// the satellite — its live azimuth while it's up, its rise azimuth
/// otherwise — rotated against the device heading so the arrow points at
/// the real sky. Tapping a row selects the bird and opens the antenna
/// pointing view (compass tape + elevation scale); "Show on Map" just
/// selects it.
struct SatelliteListSheet: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let motion: AntennaMotionService
    /// Select the bird on the map.
    let onSelect: (Int) -> Void
    /// Select the bird and open the pointing view once the sheet is gone.
    let onPoint: (Int) -> Void

    var body: some View {
        NavigationStack {
            content
                // Above the list (not in it) so the chips stay reachable
                // when the filter empties the catalog.
                .safeAreaInset(edge: .top) {
                    SatelliteModeFilterChips()
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
                .searchable(text: $searchText, prompt: "Satellite name or NORAD ID")
                .navigationTitle("Satellites")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .task {
            await headingSampler.run(motion: motion)
        }
        .task {
            // The next-pass sweep refreshes opportunistically; the rows'
            // live az/el ride on the root view's 5 s position sync.
            while !Task.isCancelled {
                let passes = await model.upcomingPasses(withinHours: Self.windowHours)
                var next = [Int: SatellitePass]()
                for item in passes where next[item.noradID] == nil {
                    next[item.noradID] = item.pass
                }
                nextPassByNorad = next
                isLoading = false
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    // MARK: Private

    private static let windowHours = 24.0

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var nextPassByNorad = [Int: SatellitePass]()
    @State private var isLoading = true
    @State private var headingSampler = SatelliteHeadingSampler()

    /// Shared filter state (empty/false = off).
    @AppStorage(SatelliteModeFilter.storageKey) private var modeFilterRaw = ""
    @AppStorage(SatelliteModeFilter.uplinkBandKey) private var uplinkBandRaw = ""
    @AppStorage(SatelliteModeFilter.downlinkBandKey) private var downlinkBandRaw = ""
    @AppStorage(SatelliteModeFilter.heardRecentlyKey) private var heardRecentlyOnly = false
    @AppStorage(SatelliteModeFilter.favoritesOnlyKey) private var favoritesOnly = false

    private var favorites: FavoriteSatellitesStore {
        .shared
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// Catalog under the shared transmitter filter and the search text.
    private var filteredItems: [SatelliteSearchItem] {
        let selections = SatelliteFilterSelections(
            modeRaw: modeFilterRaw,
            uplinkRaw: uplinkBandRaw,
            downlinkRaw: downlinkBandRaw,
            heardRecentlyOnly: heardRecentlyOnly
        )
        let query = query
        return model.searchItems.filter { item in
            (query.isEmpty || matches(item, query: query))
                && (!favoritesOnly || favorites.isFavorite(item.noradID))
                && SatelliteModeFilter.matches(
                    model.transmitters(for: item.noradID), selections: selections
                )
        }
    }

    /// Rows ordered by what's workable soonest: birds up now first (ending
    /// soonest), then by rise time, then everything with no pass in the
    /// window alphabetically.
    private var entries: [SatelliteListEntry] {
        let now = Date().addingTimeInterval(model.timeOffset)
        let positions = Dictionary(
            model.positions.map { ($0.noradID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return filteredItems
            .map { item in
                SatelliteListEntry(
                    item: item,
                    position: positions[item.noradID],
                    nextPass: nextPassByNorad[item.noradID]
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.sortKey(at: now), rhs.sortKey(at: now)) {
                case let (.some(left), .some(right)) where left != right:
                    left < right
                case (.some, .none):
                    true
                case (.none, .some):
                    false
                default:
                    lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
                }
            }
    }

    private var favoriteEntries: [SatelliteListEntry] {
        entries.filter { favorites.isFavorite($0.id) }
    }

    private var otherEntries: [SatelliteListEntry] {
        entries.filter { !favorites.isFavorite($0.id) }
    }

    @ViewBuilder
    private var content: some View {
        if model.searchItems.isEmpty {
            ProgressView("Loading orbital data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            list
        }
    }

    private var list: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date.addingTimeInterval(model.timeOffset)
            List {
                if query.isEmpty, !favoriteEntries.isEmpty {
                    Section("Favorites") {
                        rows(favoriteEntries, now: now)
                    }
                    Section("Everything Else") {
                        rows(otherEntries, now: now)
                    }
                } else {
                    Section {
                        rows(entries, now: now)
                    } footer: {
                        footer
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text(
            (model.observerCoordinate == nil
                ? "Set your grid square or allow location access to predict passes and bearings."
                : "Next \(Int(Self.windowHours)) hours · the arrow points at the bird (or where it rises)"
                + (isLoading ? " · scanning the sky…" : ""))
                + " · tap a satellite to point at it"
        )
    }

    private func rows(_ items: [SatelliteListEntry], now: Date) -> some View {
        ForEach(items) { entry in
            Button {
                onPoint(entry.id)
                dismiss()
            } label: {
                SatelliteListRow(
                    entry: entry,
                    transmitter: primaryTransmitter(for: entry.id),
                    amsatStatus: model.amsatStatus(for: entry.id),
                    isFavorite: favorites.isFavorite(entry.id),
                    sampler: headingSampler,
                    now: now
                )
                // Plain buttons hit-test only their content; make the
                // whole row (gaps included) tappable.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading) {
                Button {
                    favorites.toggle(entry.id)
                } label: {
                    Label(
                        favorites.isFavorite(entry.id) ? "Unfavorite" : "Favorite",
                        systemImage: favorites.isFavorite(entry.id) ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
            }
            .contextMenu {
                Button {
                    onSelect(entry.id)
                    dismiss()
                } label: {
                    Label("Show on Map", systemImage: "map")
                }
            }
        }
    }

    private func matches(_ item: SatelliteSearchItem, query: String) -> Bool {
        item.name.localizedCaseInsensitiveContains(query)
            || (item.detailName?.localizedCaseInsensitiveContains(query) ?? false)
            || String(item.noradID).hasPrefix(query)
    }

    /// The transmitter shown on a row: first active one with a downlink.
    private func primaryTransmitter(for noradID: Int) -> SatNOGSTransmitter? {
        let transmitters = model.transmitters(for: noradID)
        return transmitters.first { $0.isActive && $0.downlinkLow != nil }
            ?? transmitters.first { $0.downlinkLow != nil }
    }
}

// MARK: - SatelliteListEntry

/// One catalog satellite with what the list needs to order and point:
/// its live look (when propagated) and its next pass (when in the sweep).
struct SatelliteListEntry: Identifiable {
    let item: SatelliteSearchItem
    let position: SatellitePosition?
    let nextPass: SatellitePass?

    var id: Int {
        item.noradID
    }

    var isAboveHorizon: Bool {
        position?.isAboveHorizon ?? false
    }

    /// Where to point: the bird itself when up, else where it rises.
    var bearingDeg: Double? {
        if isAboveHorizon, let azimuth = position?.azimuthDeg {
            return azimuth
        }
        return nextPass?.aosAzimuthDeg
    }

    /// Up now sorts by set time, else by rise time; nil = no pass known.
    func sortKey(at now: Date) -> Date? {
        if isAboveHorizon {
            return nextPass.map { $0.isInProgress(at: now) ? $0.los : now } ?? now
        }
        return nextPass?.aos
    }
}

// MARK: - SatelliteListRow

/// One satellite: name + primary transmitter, next-pass line, and the
/// bearing arrow with its compass label.
private struct SatelliteListRow: View {
    // MARK: Internal

    let entry: SatelliteListEntry
    let transmitter: SatNOGSTransmitter?
    let amsatStatus: AmsatSatelliteStatus?
    let isFavorite: Bool
    let sampler: SatelliteHeadingSampler
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    CommunityDot(status: amsatStatus)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(entry.item.name)
                        .font(.subheadline.weight(.semibold).monospaced())
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let detail = entry.item.detailName {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                if let transmitter {
                    HStack(spacing: 6) {
                        SatelliteModeBadge(mode: transmitter.mode)
                        if let downlink = transmitter.downlinkLow {
                            Text(String(format: "↓ %.3f", Double(downlink) / 1_000_000))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                passLine
            }
            Spacer(minLength: 4)
            bearing
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    /// Elevation above which the live state reads as "up" in green.
    private var passLine: some View {
        HStack(spacing: 6) {
            if entry.isAboveHorizon, let elevation = entry.position?.elevationDeg {
                Label("Up now", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text(String(format: "· el %.0f°", elevation))
                if let pass = entry.nextPass, pass.isInProgress(at: now) {
                    Text("· \(remainingLabel(pass))")
                }
            } else if let pass = entry.nextPass {
                Text(countdown(pass))
                Text("·")
                Text(durationLabel(pass))
                Text("·")
                Text(String(format: "%.0f° max", pass.peakElevationDeg))
                    .foregroundStyle(peakStyle(pass))
            } else {
                Text("No pass in 24 h")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    @ViewBuilder
    private var bearing: some View {
        if let bearingDeg = entry.bearingDeg {
            VStack(spacing: 2) {
                SatelliteBearingArrow(
                    azimuthDeg: bearingDeg,
                    isAboveHorizon: entry.isAboveHorizon,
                    sampler: sampler
                )
                Text(SatellitePassRow.compassLabel(bearingDeg))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                (entry.isAboveHorizon ? "Satellite at " : "Rises at ")
                    + SatellitePassRow.compassLabel(bearingDeg)
            )
        }
    }

    private func countdown(_ pass: SatellitePass) -> String {
        let interval = pass.aos.timeIntervalSince(now)
        guard interval > 0 else {
            return "now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "in \(max(minutes, 1))m"
        }
        return "in \(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    private func durationLabel(_ pass: SatellitePass) -> String {
        "\(max(Int((pass.duration / 60).rounded()), 1)) min"
    }

    private func remainingLabel(_ pass: SatellitePass) -> String {
        let interval = pass.los.timeIntervalSince(now)
        guard interval > 0 else {
            return "setting"
        }
        return "\(max(Int(interval / 60), 1))m left"
    }

    private func peakStyle(_ pass: SatellitePass) -> Color {
        if pass.peakElevationDeg >= 45 {
            return .green
        }
        if pass.peakElevationDeg >= SatelliteWorkability.recommendedPassElevationDeg {
            return .primary
        }
        return .secondary
    }
}
