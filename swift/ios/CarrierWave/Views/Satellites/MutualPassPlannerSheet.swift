import CarrierWaveData
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - ResolvedStation

/// Station B once its input (grid, callsign, or friend) has been resolved
/// to a location, with a note about where the grid came from.
nonisolated struct ResolvedStation: Equatable {
    let label: String
    let grid: String
    let latitude: Double
    let longitude: Double
    let sourceNote: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - MutualPassPlannerSheet

/// Mutual-pass planner: windows where a satellite is visible from your QTH
/// and a second station at the same time. Station A defaults to the
/// observer QTH; station B takes a grid, a callsign (resolved from the
/// most recent logged QSO with a grid), or a friend from the friends list.
struct MutualPassPlannerSheet: View {
    let model: SatelliteTrackerModel

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    /// The app-wide shared satellite filter — the same selection as the
    /// map and pass lists (sky sectors excluded: they're geometry from
    /// YOUR horizon and mutual passes carry no azimuths).
    @AppStorage(SatelliteModeFilter.storageKey) var sharedModeRaw = ""
    @AppStorage(SatelliteModeFilter.uplinkBandKey) var sharedUplinkRaw = ""
    @AppStorage(SatelliteModeFilter.downlinkBandKey) var sharedDownlinkRaw = ""
    @AppStorage(SatelliteModeFilter.minPeakElevationKey) var minPeakElevation = 0
    @AppStorage(SatelliteModeFilter.heardRecentlyKey) var heardRecentlyOnly = false
    @AppStorage(SatelliteModeFilter.favoritesOnlyKey) var favoritesOnly = false
    @State var stationAGrid = ""
    @State var stationBInput = ""
    @State var resolvedB: ResolvedStation?
    @State var passes: [MutualPass]?
    @State var isSearching = false
    @State var errorMessage: String?
    /// Autocomplete candidates for the "Them" field: friends first, then
    /// callsigns from the QSO log, filtered by the typed prefix.
    @State var suggestions: [StationSuggestion] = []
    @State var suggestionTask: Task<Void, Never>?
    /// Your horizon mask, applied to YOUR side of the window now that
    /// mutual passes carry station-A azimuths.
    @AppStorage(SatelliteModeFilter.horizonMaskKey) var horizonMaskRaw = ""

    var body: some View {
        NavigationStack {
            List {
                stationsSection
                resultsSection
            }
            .navigationTitle("Mutual Passes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: MutualPass.self) { pass in
                if let station = resolvedB {
                    MutualPassProfileView(
                        model: model,
                        pass: pass,
                        stationAGrid: stationAGrid,
                        stationB: station
                    )
                }
            }
        }
        .task {
            if stationAGrid.isEmpty, let observer = model.observerCoordinate {
                stationAGrid = MaidenheadConverter.grid(from: observer, precision: .six)
            }
        }
        // Bucket changes alter the engine sweep's candidate pool — refresh
        // standing results (band/heard/favorites/elevation are post-filters
        // and apply live).
        .onChange(of: sharedModeRaw) {
            if passes != nil {
                Task { await runSearch() }
            }
        }
    }
}

// MARK: - Planner internals

private extension MutualPassPlannerSheet {
    /// The shared filter's work-type buckets mapped onto the engine's
    /// sweep categories (telemetry has no two-way category — nothing you
    /// could work each other through — so it contributes none).
    var selectedModes: Set<SatelliteModeCategory> {
        let buckets = SatelliteModeFilter.selection(from: sharedModeRaw)
        if buckets.count == SatelliteFilterBucket.allCases.count {
            return Set(SatelliteModeCategory.allCases)
        }
        var modes = Set<SatelliteModeCategory>()
        if buckets.contains(.fm) {
            modes.insert(.voiceFM)
        }
        if buckets.contains(.linear) {
            modes.formUnion([.linear, .morse])
        }
        if buckets.contains(.digital) {
            modes.insert(.digital)
        }
        return modes.isEmpty ? Set(SatelliteModeCategory.allCases) : modes
    }

    var filterSelections: SatelliteFilterSelections {
        SatelliteFilterSelections(
            modeRaw: sharedModeRaw,
            uplinkRaw: sharedUplinkRaw,
            downlinkRaw: sharedDownlinkRaw,
            heardRecentlyOnly: heardRecentlyOnly
        )
    }

    /// The app-wide filter strip — sectors included now that mutual
    /// windows carry your-station azimuths.
    var modeChips: some View {
        SatelliteModeFilterChips()
    }

    var stationsSection: some View {
        Section {
            HStack {
                Text("You")
                    .foregroundStyle(.secondary)
                TextField("Grid (e.g. CM87)", text: $stationAGrid)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            HStack {
                Text("Them")
                    .foregroundStyle(.secondary)
                TextField("Grid or callsign", text: $stationBInput)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: stationBInput) {
                        refreshSuggestions()
                    }
                    .task {
                        refreshSuggestions()
                    }
            }
            if !suggestions.isEmpty {
                suggestionChips
            }
            if let resolvedB {
                Label {
                    Text("\(resolvedB.label) → \(resolvedB.grid) · \(resolvedB.sourceNote)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                }
            }
            modeChips
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await runSearch() }
            } label: {
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Scanning 24 hours…")
                    }
                } else {
                    Label("Find Mutual Passes", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .disabled(isSearching || stationAGrid.isEmpty || stationBInput.isEmpty)
        } footer: {
            Text("Windows where the satellite is above the horizon at both stations at once."
                + " Callsigns resolve to the most recent grid in your log, or by callsign lookup.")
        }
    }

    /// The limiting-elevation floor: the app-wide 10° workable rule (the
    /// old funnel toggle, now always on — a sub-10° mutual window is
    /// junk) raised by the shared threshold when it's higher.
    var elevationFloor: Double {
        max(SatelliteWorkability.minWorkablePassElevationDeg, Double(minPeakElevation))
    }

    var visiblePasses: [MutualPass] {
        guard let passes else {
            return []
        }
        let selections = filterSelections
        let mask = SatelliteModeFilter.horizonMask(from: horizonMaskRaw)
        let floor = elevationFloor
        return passes.filter { pass in
            pass.peakMinElevationDeg >= floor
                && SatelliteModeFilter.horizonAllows(
                    peakAzimuthDeg: pass.peakAzimuthADeg,
                    peakElevationDeg: pass.peakElevationADeg,
                    mask: mask
                )
                && (!favoritesOnly || FavoriteSatellitesStore.shared.isFavorite(pass.noradID))
                && SatelliteModeFilter.matches(
                    model.transmitters(for: pass.noradID), selections: selections
                )
        }
    }

    @ViewBuilder
    var resultsSection: some View {
        if let passes {
            Section {
                if visiblePasses.isEmpty {
                    Text(passes.isEmpty
                        ? "No mutual passes in the next 24 hours."
                        : "No mutual windows clear your filters (limiting peak ≥ "
                        + "\(Int(elevationFloor))° + horizon mask)"
                        + " in the next 24 hours.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visiblePasses) { pass in
                        NavigationLink(value: pass) {
                            MutualPassRow(
                                pass: pass,
                                transmitter: primaryTransmitter(for: pass.noradID),
                                amsatStatus: model.amsatStatus(for: pass.noradID)
                            )
                        }
                    }
                }
            } footer: {
                if !visiblePasses.isEmpty {
                    Text("Next 24 hours · satellites with an active transmitter"
                        + " · limiting peak ≥ \(Int(elevationFloor))°"
                        + " · your horizon mask applies to your side"
                        + " · tap a pass for the profile view")
                }
            }
        }
    }

    func runSearch() async {
        errorMessage = nil
        guard MaidenheadConverter.coordinate(from: stationAGrid) != nil else {
            errorMessage = "Your grid doesn't parse — use a 4 or 6 character Maidenhead grid."
            return
        }
        isSearching = true
        defer { isSearching = false }
        guard let station = await resolveStationB() else {
            return
        }
        resolvedB = station
        passes = await model.mutualPasses(with: station.coordinate, modes: selectedModes)
    }

    /// Transmitter shown on a row: active, matching the mode filter, with a
    /// downlink when one exists.
    func primaryTransmitter(for noradID: Int) -> SatNOGSTransmitter? {
        let matching = model.transmitters(for: noradID).filter { transmitter in
            transmitter.isActive && selectedModes.contains(SatelliteModeCategory.category(for: transmitter))
        }
        return matching.first { $0.downlinkLow != nil } ?? matching.first
    }

    /// Grid input wins; otherwise treat it as a callsign and use the most
    /// recent logged QSO with that call that carries a valid grid.
    func resolveStationB() async -> ResolvedStation? {
        let input = stationBInput.trimmingCharacters(in: .whitespaces).uppercased()
        if let coordinate = MaidenheadConverter.coordinate(from: input) {
            return ResolvedStation(
                label: input,
                grid: input,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                sourceNote: "grid"
            )
        }
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.callsign == input },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let qsos = (try? modelContext.fetch(descriptor)) ?? []
        for qso in qsos {
            guard let grid = qso.theirGrid?.trimmingCharacters(in: .whitespaces).uppercased(),
                  let coordinate = MaidenheadConverter.coordinate(from: grid)
            else {
                continue
            }
            let when = qso.timestamp.formatted(date: .abbreviated, time: .omitted)
            return ResolvedStation(
                label: input,
                grid: grid,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                sourceNote: "from your log, \(when)"
            )
        }
        // Nothing in the log — fall back to the shared callsign lookup
        // chain (Polo notes → QRZ callbook → HamDB).
        let service = CallsignLookupService(modelContext: modelContext)
        let lookedUp = await service.lookup(input)?.grid?.trimmingCharacters(in: .whitespaces).uppercased()
        if let grid = lookedUp, let coordinate = MaidenheadConverter.coordinate(from: grid) {
            return ResolvedStation(
                label: input,
                grid: grid,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                sourceNote: "from callsign lookup"
            )
        }
        errorMessage = "No grid found for \(input) — enter their grid directly."
        return nil
    }
}
