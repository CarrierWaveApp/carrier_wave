import CarrierWaveCore
import CoreLocation
import SwiftUI

// MARK: - SatelliteTrackerModel

/// View model over the shared Rust satellite engine (`SatelliteApi`): the
/// engine owns SatNOGS/AMSAT fetching + caching, the workability gates,
/// SGP4 propagation, and pass math; this model holds main-actor published
/// state for the map and hops off-main for the blocking sync FFI calls.
@MainActor
@Observable
final class SatelliteTrackerModel {
    // MARK: Internal

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var positions: [SatellitePosition] = []
    private(set) var selectedTrack: [SatellitePosition] = []
    private(set) var searchItems: [SatelliteSearchItem] = []
    private(set) var tlesFetchedAt: Date?
    private(set) var selectedNoradID: Int?

    /// Seconds ahead of (+) or behind (−) real time; driven by the time
    /// slider. The simulated clock still advances at 1× in real time.
    private(set) var timeOffset: TimeInterval = 0

    /// Wall-clock moment `positions` was last propagated, for dead-reckoning.
    private(set) var positionsSyncedAt = Date()

    /// The observer location az/el features are computed from (readable so
    /// the UI can surface which QTH is in use).
    private(set) var observerCoordinate: CLLocationCoordinate2D?

    private(set) var transmittersByNorad: [Int: [SatNOGSTransmitter]] = [:]

    /// Last-24 h community status per catalog bird (absent = untracked by
    /// AMSAT) for the map's marker rings.
    private(set) var communityStatusByNorad: [Int: CommunityActivityStatus] = [:]

    /// Community reports for the selected bird (reporter grids on the map
    /// and the previous-orbit line), refreshed on selection.
    var selectedReports: CommunityReports?

    /// The week's activity grid (3 h cells) — the info card shows the
    /// selected bird's rows from it. Loaded with the reports.
    var communityActivity: CommunityActivity?

    var selectedReporters: [ReporterMark] {
        selectedReports?.marks ?? []
    }

    /// The selected bird's capability rows out of `communityActivity`.
    var selectedCommunityRows: [CommunityActivityRow] {
        guard let selectedNoradID, let communityActivity else {
            return []
        }
        return communityActivity.rows.filter { $0.noradID == selectedNoradID }
    }

    var selectedPosition: SatellitePosition? {
        guard let selectedNoradID else {
            return nil
        }
        return positions.first { $0.noradID == selectedNoradID }
    }

    /// The selected satellite's az/el/range from the observer's location.
    var selectedLook: SatelliteLook? {
        guard let position = selectedPosition,
              let azimuth = position.azimuthDeg,
              let elevation = position.elevationDeg
        else {
            return nil
        }
        return SatelliteLook(
            azimuthDeg: azimuth,
            elevationDeg: elevation,
            rangeKm: position.rangeKm ?? 0
        )
    }

    /// Amateur transmitters for a satellite, active ones first (the engine
    /// orders them).
    func transmitters(for noradID: Int) -> [SatNOGSTransmitter] {
        transmittersByNorad[noradID] ?? []
    }

    /// Satellite-level AMSAT community summary, when the catalog has one.
    func amsatStatus(for noradID: Int) -> AmsatSatelliteStatus? {
        summariesByNorad[noradID].flatMap(AmsatSatelliteStatus.init(summary:))
    }

    /// Curated downlink polarization from the engine's table, if known.
    func polarization(for noradID: Int) -> FfiSatPolarization? {
        summariesByNorad[noradID]?.polarization
    }

    /// Set the observer location (GPS fix or grid square) used for
    /// az/el sky positions, and re-propagate with it.
    func setObserver(_ coordinate: CLLocationCoordinate2D?) {
        observerCoordinate = coordinate
        Task {
            await refreshPositions()
        }
    }

    /// Show satellites as fast as possible, then bring the data up to date.
    /// A normal open builds the catalog from the engine's cache (any age, no
    /// network) and runs the cache-through refresh (TLEs + transmitters +
    /// AMSAT, 6 h TTL) in the background, so a slow SatNOGS download never
    /// holds the tab on its spinner. Only a first launch with nothing cached
    /// waits on the network. `forceRefresh` (Refresh / Retry) always waits
    /// for a network refresh.
    func load(forceRefresh: Bool = false) async {
        if summariesByNorad.isEmpty {
            state = .loading
        }
        let api: SatelliteApi
        do {
            api = try await SatelliteEngine.api()
        } catch {
            if summariesByNorad.isEmpty {
                state = .failed(error.localizedDescription)
            }
            return
        }
        if forceRefresh {
            await refreshFromNetwork(api, force: true)
            return
        }
        if summariesByNorad.isEmpty, let cached = try? await api.loadCached() {
            await applyCatalog(from: api, summary: cached)
        }
        if summariesByNorad.isEmpty {
            await refreshFromNetwork(api, force: false)
        } else {
            // The engine coalesces concurrent refreshes (alert scheduler,
            // re-opened tab) into one download and backs off after failures.
            Task { [weak self] in
                await self?.refreshFromNetwork(api, force: false)
            }
        }
    }

    /// Propagate every satellite to "now" through the engine. Called every
    /// 5 s by the root view; the map dead-reckons between syncs. The
    /// selected ground track is only regenerated when it has drifted stale.
    func refreshPositions() async {
        guard state == .loaded, let api = try? await SatelliteEngine.api() else {
            return
        }
        let epoch = simulatedEpoch()
        let observer = ffiObserver()
        positions = await Task.detached(priority: .userInitiated) {
            api.positions(epochSecs: epoch, observer: observer)
                .map(SatellitePosition.init(ffi:))
        }.value
        positionsSyncedAt = Date()
        if let selected = selectedNoradID,
           Date().timeIntervalSince(trackRefreshedAt) > Self.trackMaxAge
        {
            await rebuildTrack(for: selected)
        }
    }

    /// Change the selected satellite and rebuild its ground track.
    func select(_ noradID: Int?) {
        selectedNoradID = noradID
        selectedTrack = []
        selectedReports = nil
        guard let noradID else {
            return
        }
        Task {
            await rebuildTrack(for: noradID)
        }
        Task {
            await loadReports(for: noradID)
        }
    }

    /// Scrub the simulated clock. Re-propagation is coalesced so a fast
    /// slider drag doesn't queue a propagation per gesture sample.
    func setTimeOffset(_ offset: TimeInterval) {
        timeOffset = offset
        trackRefreshedAt = .distantPast
        skyTrackCache.removeAll()
        Task {
            await refreshForScrub()
        }
    }

    /// On-demand track for any satellite (sky-dome hover path), cached
    /// briefly so panning across the same satellite doesn't re-propagate.
    func skyTrack(for noradID: Int) async -> [SatellitePosition] {
        if let cached = skyTrackCache[noradID],
           Date().timeIntervalSince(cached.builtAt) < Self.trackMaxAge
        {
            return cached.track
        }
        let track = await groundTrack(for: noradID)
        if skyTrackCache.count > 32 {
            skyTrackCache.removeAll()
        }
        skyTrackCache[noradID] = (Date(), track)
        return track
    }

    /// The engine epoch for "now" under the scrubber offset.
    func simulatedEpoch() -> Int64 {
        Int64(Date().addingTimeInterval(timeOffset).timeIntervalSince1970)
    }

    /// The observer as the engine record, when a QTH is known.
    func ffiObserver() -> FfiObserver? {
        observerCoordinate.map { FfiObserver(latDeg: $0.latitude, lonDeg: $0.longitude) }
    }

    // MARK: Private

    /// Regenerate the selected track when older than this (seconds), so the
    /// forward-looking track stays anchored at the moving satellite.
    private static let trackMaxAge: TimeInterval = 60

    private var summariesByNorad: [Int: FfiSatelliteSummary] = [:]
    private var trackRefreshedAt = Date.distantPast
    private var skyTrackCache: [Int: (builtAt: Date, track: [SatellitePosition])] = [:]
    private var scrubRefreshInFlight = false

    /// Coalesced re-propagation while the time slider is dragged: one
    /// refresh runs at a time, repeating until the offset settles.
    private func refreshForScrub() async {
        guard !scrubRefreshInFlight else {
            return
        }
        scrubRefreshInFlight = true
        defer { scrubRefreshInFlight = false }
        var propagatedOffset = timeOffset
        await refreshPositions()
        while propagatedOffset != timeOffset {
            propagatedOffset = timeOffset
            await refreshPositions()
        }
    }

    /// Run the engine's cache-through refresh and apply the result. A
    /// failure only surfaces when there is nothing on screen yet; otherwise
    /// the cached catalog stays up (the engine has already degraded to it).
    private func refreshFromNetwork(_ api: SatelliteApi, force: Bool) async {
        do {
            let summary = try await api.refresh(force: force)
            await applyCatalog(from: api, summary: summary)
        } catch {
            if summariesByNorad.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Rebuild the published catalog state from the engine's installed
    /// catalog and re-propagate positions.
    private func applyCatalog(from api: SatelliteApi, summary: FfiSatelliteRefreshSummary) async {
        let catalog = await Task.detached(priority: .userInitiated) {
            api.catalog()
        }.value
        summariesByNorad = Dictionary(
            catalog.map { (Int($0.noradId), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        transmittersByNorad = summariesByNorad.mapValues { entry in
            entry.transmitters.map(SatNOGSTransmitter.init(ffi:))
        }
        communityStatusByNorad = summariesByNorad.compactMapValues { entry in
            AmsatSatelliteStatus(summary: entry)?.dayStatus
        }
        tlesFetchedAt = Date(
            timeIntervalSince1970: TimeInterval(summary.tlesFetchedAtEpoch)
        )
        searchItems = catalog
            .map {
                SatelliteSearchItem(
                    noradID: Int($0.noradId), name: $0.name, detailName: $0.detailName
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        state = .loaded
        await refreshPositions()
    }

    private func rebuildTrack(for noradID: Int) async {
        let track = await groundTrack(for: noradID)
        if selectedNoradID == noradID {
            selectedTrack = track
            trackRefreshedAt = Date()
        }
    }

    private func groundTrack(for noradID: Int) async -> [SatellitePosition] {
        guard let api = try? await SatelliteEngine.api() else {
            return []
        }
        let epoch = simulatedEpoch()
        let observer = ffiObserver()
        return await Task.detached(priority: .userInitiated) {
            api.groundTrack(noradId: UInt32(noradID), epochSecs: epoch, observer: observer)
                .map(SatellitePosition.init(ffi:))
        }.value
    }
}
