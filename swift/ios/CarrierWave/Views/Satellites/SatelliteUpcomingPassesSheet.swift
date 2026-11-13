import SwiftUI

// MARK: - SatelliteUpcomingPassesSheet

/// "What's next" across the whole sky: every upcoming pass over the
/// observer's QTH within the window, across all satellites with an active
/// amateur transmitter, sorted by rise time. Tapping a pass selects that
/// satellite on the map.
struct SatelliteUpcomingPassesSheet: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            content
                // Above the list (not in it) so the chips stay reachable
                // when the filter empties the sky.
                .safeAreaInset(edge: .top) {
                    SatelliteModeFilterChips()
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
                .navigationTitle("Upcoming Passes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            workableOnly.toggle()
                        } label: {
                            Image(systemName: workableOnly
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(workableOnly
                            ? "Showing workable passes only — tap to show all"
                            : "Showing all passes — tap to show workable only")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .task {
            passes = await model.upcomingPasses(withinHours: Self.windowHours)
            isLoading = false
        }
        .sheet(item: $satBridgeItem) { item in
            SatBridgePassSheet(item: item, model: model)
        }
    }

    // MARK: Private

    private static let windowHours = 6.0

    @Environment(\.dismiss) private var dismiss
    @State private var passes = [UpcomingSatellitePass]()
    @State private var isLoading = true
    /// Pass being sent to the CW Sat Bridge (presents the control sheet).
    @State private var satBridgeItem: UpcomingSatellitePass?

    /// Hide horizon-scraper passes (peak < 10°) by default (persisted).
    @AppStorage(SatelliteWorkability.workablePassFilterKey) private var workableOnly = true

    /// Shared filter state (empty/0/false = off).
    @AppStorage(SatelliteModeFilter.storageKey) private var modeFilterRaw = ""
    @AppStorage(SatelliteModeFilter.uplinkBandKey) private var uplinkBandRaw = ""
    @AppStorage(SatelliteModeFilter.downlinkBandKey) private var downlinkBandRaw = ""
    @AppStorage(SatelliteModeFilter.minPeakElevationKey) private var minPeakElevation = 0
    @AppStorage(SatelliteModeFilter.heardRecentlyKey) private var heardRecentlyOnly = false
    @AppStorage(SatelliteModeFilter.favoritesOnlyKey) private var favoritesOnly = false
    @AppStorage(SatelliteModeFilter.horizonMaskKey) private var skySectorsRaw = ""

    private var favorites: FavoriteSatellitesStore {
        .shared
    }

    private var visiblePasses: [UpcomingSatellitePass] {
        let selections = SatelliteFilterSelections(
            modeRaw: modeFilterRaw,
            uplinkRaw: uplinkBandRaw,
            downlinkRaw: downlinkBandRaw,
            heardRecentlyOnly: heardRecentlyOnly
        )
        let mask = SatelliteModeFilter.horizonMask(from: skySectorsRaw)
        return passes.filter { item in
            SatelliteModeFilter.matches(
                model.transmitters(for: item.noradID), selections: selections
            )
                && (!favoritesOnly || favorites.isFavorite(item.noradID))
                && item.pass.peakElevationDeg >= Double(minPeakElevation)
                && SatelliteModeFilter.horizonAllows(
                    peakAzimuthDeg: item.pass.peakAzimuthDeg,
                    peakElevationDeg: item.pass.peakElevationDeg,
                    mask: mask
                )
                && (!workableOnly
                    || item.pass.peakElevationDeg
                    >= SatelliteWorkability.minWorkablePassElevationDeg)
        }
    }

    private var favoritePasses: [UpcomingSatellitePass] {
        visiblePasses.filter { favorites.isFavorite($0.noradID) }
    }

    private var otherPasses: [UpcomingSatellitePass] {
        visiblePasses.filter { !favorites.isFavorite($0.noradID) }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Scanning the sky…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.observerCoordinate == nil {
            ContentUnavailableView(
                "QTH Not Set",
                systemImage: "location.slash",
                description: Text("Set your grid square or allow location access to predict passes.")
            )
        } else if visiblePasses.isEmpty {
            ContentUnavailableView {
                Label("Quiet Sky", systemImage: "moon.zzz")
            } description: {
                Text(passes.isEmpty
                    ? "No passes rise above your horizon in the next \(Int(Self.windowHours)) hours."
                    : "No workable passes (peak ≥ "
                    + "\(Int(SatelliteWorkability.minWorkablePassElevationDeg))°)"
                    + " in the next \(Int(Self.windowHours)) hours.")
            } actions: {
                if !passes.isEmpty {
                    Button("Show All Passes") {
                        workableOnly = false
                    }
                }
            }
        } else {
            passList
        }
    }

    private var passList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date.addingTimeInterval(model.timeOffset)
            List {
                if !favoritePasses.isEmpty {
                    Section("Favorites") {
                        passRows(favoritePasses, now: now)
                    }
                }
                Section {
                    passRows(otherPasses, now: now)
                } header: {
                    if !favoritePasses.isEmpty {
                        Text("Everything Else")
                    }
                } footer: {
                    Text("Next \(Int(Self.windowHours)) hours · satellites with an active transmitter"
                        +
                        (workableOnly ? " · peak ≥ \(Int(SatelliteWorkability.minWorkablePassElevationDeg))° only" :
                            "")
                        + " · tap a pass to select it on the map")
                }
            }
        }
    }

    private func passRows(_ items: [UpcomingSatellitePass], now: Date) -> some View {
        ForEach(items) { item in
            Button {
                onSelect(item.noradID)
                dismiss()
            } label: {
                UpcomingPassRow(
                    item: item,
                    transmitter: primaryTransmitter(for: item.noradID),
                    amsatStatus: model.amsatStatus(for: item.noradID),
                    isFavorite: favorites.isFavorite(item.noradID),
                    now: now
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                if SatBridgeController.shared.bridgeAvailable {
                    Button {
                        satBridgeItem = item
                    } label: {
                        Label("Send to Bridge", systemImage: "dot.radiowaves.up.forward")
                    }
                }
            }
        }
    }

    /// The transmitter shown on a row: first active one with a downlink.
    private func primaryTransmitter(for noradID: Int) -> SatNOGSTransmitter? {
        let transmitters = model.transmitters(for: noradID)
        return transmitters.first { $0.isActive && $0.downlinkLow != nil }
            ?? transmitters.first { $0.downlinkLow != nil }
    }
}

// MARK: - UpcomingPassRow

/// One pass in the all-sky schedule: satellite name + primary transmitter,
/// countdown/in-progress state, duration, color-graded peak elevation, and
/// the azimuth path.
private struct UpcomingPassRow: View {
    // MARK: Internal

    let item: UpcomingSatellitePass
    let transmitter: SatNOGSTransmitter?
    let amsatStatus: AmsatSatelliteStatus?
    let isFavorite: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Name line: the name always gets the room it needs — the
            // transmitter chips live on their own line below, so a
            // chip-heavy bird like AO-7 can't crush it.
            HStack(spacing: 6) {
                CommunityDot(status: amsatStatus)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(item.name)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
                    .layoutPriority(1)
                if let detail = item.detailName {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if SatelliteWorkability.isMarginal(peakElevationDeg: item.pass.peakElevationDeg) {
                    MarginalPassTag()
                }
                Text(String(format: "%.0f° max", item.pass.peakElevationDeg))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(peakStyle)
                    .lineLimit(1)
                    .fixedSize()
            }
            if transmitter != nil || amsatStatus != nil {
                HStack(spacing: 6) {
                    if let transmitter {
                        SatelliteModeBadge(mode: transmitter.mode)
                        if let downlink = transmitter.downlinkLow {
                            Text(String(format: "↓ %.3f", Double(downlink) / 1_000_000))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let amsatStatus {
                        AmsatStatusBadge(status: amsatStatus)
                    }
                    Spacer()
                }
            }
            HStack(spacing: 6) {
                if item.pass.isInProgress(at: now) {
                    Label("In progress", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    Text("· \(remainingLabel)")
                } else {
                    Text(countdown)
                    Text("·")
                    Text(durationLabel)
                }
                Spacer()
                Text(azimuthPath)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var countdown: String {
        let interval = item.pass.aos.timeIntervalSince(now)
        guard interval > 0 else {
            return "now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "in \(max(minutes, 1))m"
        }
        return "in \(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    private var durationLabel: String {
        "\(max(Int((item.pass.duration / 60).rounded()), 1)) min"
    }

    private var remainingLabel: String {
        let interval = item.pass.los.timeIntervalSince(now)
        guard interval > 0 else {
            return "setting"
        }
        return "\(max(Int(interval / 60), 1))m left"
    }

    private var azimuthPath: String {
        let rise = SatellitePassRow.compassLabel(item.pass.aosAzimuthDeg)
        let set = SatellitePassRow.compassLabel(item.pass.losAzimuthDeg)
        return "\(rise) → \(set)"
    }

    private var peakStyle: Color {
        if item.pass.peakElevationDeg >= 45 {
            return .green
        }
        if item.pass.peakElevationDeg >= SatelliteWorkability.recommendedPassElevationDeg {
            return .primary
        }
        return .secondary
    }
}
