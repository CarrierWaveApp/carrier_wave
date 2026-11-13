import CarrierWaveData
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

// MARK: - MapSessionStartRequest

/// Data needed to pre-fill a session start from the map.
struct MapSessionStartRequest: Identifiable {
    let id = UUID()
    let programs: Set<String>
    let parkReference: String?
    let sotaReference: String?
}

// MARK: - MergedPolygon + MapKit

extension MergedPolygon {
    /// Convert to MKPolygon with interior holes for MapPolygon rendering.
    func mkPolygon() -> MKPolygon {
        var coords = exterior
        if holes.isEmpty {
            return MKPolygon(coordinates: &coords, count: coords.count)
        }
        let interiorPolys = holes.map { hole in
            var holeCoords = hole
            return MKPolygon(
                coordinates: &holeCoords, count: holeCoords.count
            )
        }
        return MKPolygon(
            coordinates: &coords,
            count: coords.count,
            interiorPolygons: interiorPolys
        )
    }
}

// MARK: - MapSelection

/// Tracks what the user has selected on the map — a park, summit, or trail.
enum MapSelection: Equatable {
    case park(POTAPark)
    case summit(SOTASummit)
    case trail(TrailBoundary)

    // MARK: Internal

    var parkReference: String? {
        if case let .park(park) = self {
            return park.reference
        }
        return nil
    }

    var trailReference: String? {
        if case let .trail(trail) = self {
            return trail.reference
        }
        return nil
    }

    static func == (lhs: MapSelection, rhs: MapSelection) -> Bool {
        switch (lhs, rhs) {
        case let (.park(lp), .park(rp)):
            lp.reference == rp.reference
        case let (.summit(ls), .summit(rs)):
            ls.code == rs.code
        case let (.trail(lt), .trail(rt)):
            lt.reference == rt.reference
        default:
            false
        }
    }
}

// MARK: - ParkSearchMapView

/// Map view for browsing POTA parks and SOTA summits.
/// Fetches park boundaries from the activities server as the user pans.
struct ParkSearchMapView: View {
    // MARK: - State (internal for extension access)

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Optional filter state for QSO map navigation (passed from tab root)
    var mapFilterState: MapFilterState?

    @AppStorage("loggerDefaultGrid") var defaultGrid = ""
    @AppStorage("mapShowGridSquares") var showGridSquares = false
    @AppStorage("mapShowTotaTiles") var showTotaTiles = false
    @AppStorage("mapShowStates") var showStates = false
    @AppStorage("mapShowCounties") var showCounties = false
    @AppStorage("mapShowSotaZones") var showSotaZones = false
    @AppStorage("mapShowWWFF") var showWWFF = false

    @State var mapRegion: MKCoordinateRegion = .continentalUS
    @State var recenterToken: Int = 0
    @State var lastVisibleRegion: MKCoordinateRegion?
    @State var searchText = ""
    @State var searchResults: [POTAPark] = []
    @State var summitSearchResults: [SOTASummit] = []
    @State var visibleParks: [POTAPark] = []
    @State var visibleSummits: [SOTASummit] = []
    @State var boundariesByRef: [String: ParkBoundary] = [:]
    @State var adminBoundariesByID: [String: AdminBoundary] = [:]
    @State var adminFetchTask: Task<Void, Never>?
    @State var sotaZonesByCode: [String: SOTAZone] = [:]
    @State var sotaZoneFetchTask: Task<Void, Never>?
    @State var wwffReferences: [WWFFReference] = []
    @State var wwffByCode: [String: WWFFRenderItem] = [:]
    @State var wwffFetchTask: Task<Void, Never>?
    @State var showMultipliersSheet = false
    @State var multiplierCandidates: [MultiplierCandidate] = []
    @State var isFindingMultipliers = false
    @State var selection: MapSelection?
    @State var trailsByRef: [String: TrailBoundary] = [:]
    @State var isLoadingBoundaries = false
    @State var showBoundaries = true
    @State var showTrails = true
    @State var showParkPins = true
    @State var showSummitPins = true
    @State var boundaryFetchTask: Task<Void, Never>?
    @State var trailFetchTask: Task<Void, Never>?
    @State var pinFetchTask: Task<Void, Never>?
    @State var searchTask: Task<Void, Never>?
    @State var sessionStartRequest: MapSessionStartRequest?
    @State var sessionManager: LoggingSessionManager?
    @State var calloutDragOffset: CGFloat = 0
    @State var showRadarOverlay = false

    @Environment(\.modelContext) var modelContext
    @Environment(\.locationSessionService) var locationService

    let activitiesClient = ActivitiesClient()

    /// Resolve user's home coordinate from (in order):
    ///  1. Their saved `loggerDefaultGrid`
    ///  2. The persisted `DeviceLocationHint` (last GPS fix)
    ///  3. nil — callers show the world view / skip nearby lookups
    var homeCoordinate: CLLocationCoordinate2D? {
        if let coord = MaidenheadConverter.coordinate(from: defaultGrid) {
            return coord
        }
        return DeviceLocationHint.lastKnownCoordinate
    }

    /// Filtered to only boundaries visible in the current viewport.
    var boundaries: [ParkBoundary] {
        guard let region = lastVisibleRegion else {
            return Array(boundariesByRef.values)
        }
        return boundariesByRef.values.filter { $0.intersects(region: region) }
    }

    var trails: [TrailBoundary] {
        Array(trailsByRef.values)
    }

    var boundaryRefs: Set<String> {
        Set(boundariesByRef.keys)
    }

    /// True when zoomed in enough to show full boundary detail (narrow corridors).
    var isZoomedIn: Bool {
        guard let region = lastVisibleRegion else {
            return false
        }
        return region.span.latitudeDelta < 0.15
    }

    var displayParks: [POTAPark] {
        if !searchResults.isEmpty {
            return searchResults
        }
        return visibleParks
    }

    var displaySummits: [SOTASummit] {
        if !summitSearchResults.isEmpty {
            return summitSearchResults
        }
        return visibleSummits
    }

    var hasSearchResults: Bool {
        !searchResults.isEmpty || !summitSearchResults.isEmpty
    }

    var body: some View {
        ZStack {
            mapContent
                .ignoresSafeArea(edges: .bottom)

            overlayContent
        }
        .navigationTitle("Parks & Summits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    recenterOnMyLocation()
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel("Center on My Location")

                NavigationLink {
                    MyParksView()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("My Parks")

                if let mapFilterState {
                    NavigationLink {
                        QSOMapView(filterState: mapFilterState)
                    } label: {
                        Image(systemName: "map")
                    }
                    .accessibilityLabel("QSO Map")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Show Boundaries (\(ExperimentalFeature.parkGIS.maturity.label))", isOn: $showBoundaries)
                    Toggle("Show Trails", isOn: $showTrails)
                    Toggle("Show Park Pins", isOn: $showParkPins)
                    Toggle("Show Summit Pins", isOn: $showSummitPins)
                    if ExperimentalFeature.isEnabled(.activityLayers) {
                        let label = ExperimentalFeature.activityLayers.maturity.label
                        Section("Programs (\(label))") {
                            Toggle("SOTA Zones", isOn: $showSotaZones)
                            Toggle("WWFF", isOn: $showWWFF)
                        }
                        Section("Administrative (\(label))") {
                            Toggle("States", isOn: $showStates)
                            Toggle("Counties", isOn: $showCounties)
                        }
                        Section("Grids (\(label))") {
                            Toggle("Grid Squares", isOn: $showGridSquares)
                            Toggle("Tiles on the Air", isOn: $showTotaTiles)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            if ExperimentalFeature.isEnabled(.activityLayers) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentMultipliers()
                    } label: {
                        Image(systemName: "rosette")
                    }
                    .accessibilityLabel("Find Multipliers")
                }
            }
            if ExperimentalFeature.isEnabled(.weatherRadar) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRadarOverlay.toggle()
                    } label: {
                        Image(systemName: showRadarOverlay ? "cloud.rain.fill" : "cloud.rain")
                            .foregroundStyle(showRadarOverlay ? .cyan : .primary)
                    }
                    .accessibilityLabel(showRadarOverlay ? "Hide Weather Radar" : "Show Weather Radar")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search parks or summits")
        .onSubmit(of: .search) {
            searchForParkOrSummit()
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            if newValue.isEmpty {
                searchResults = []
                summitSearchResults = []
            } else {
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else {
                        return
                    }
                    await updateSearchResults(query: newValue)
                }
            }
        }
        .onChange(of: showStates) { _, _ in
            fetchAdminForRegion(lastVisibleRegion ?? mapRegion)
        }
        .onChange(of: showCounties) { _, _ in
            fetchAdminForRegion(lastVisibleRegion ?? mapRegion)
        }
        .onChange(of: showSotaZones) { _, isOn in
            if isOn {
                Task { await loadCachedSotaZones() }
            }
            fetchSotaZonesForRegion(lastVisibleRegion ?? mapRegion)
        }
        .onChange(of: showWWFF) { _, _ in
            if showWWFF, wwffReferences.isEmpty {
                Task { await loadWWFFReferences() }
            }
            fetchWWFFForRegion(lastVisibleRegion ?? mapRegion)
        }
        .task {
            // Seed pins for the initial viewport — subsequent pans/zooms
            // are handled by `fetchPinsForRegion` off `onRegionChange`.
            await loadPinsInBox(lastVisibleRegion ?? mapRegion)
            await loadCachedSotaZones()
        }
        .onAppear {
            locationService.start()
            // Always home in on the live GPS fix when the map opens — never
            // strand the camera on a previously-saved coordinate. The
            // coordinator's recenter path uses .follow user tracking, which
            // snaps to the real fix the moment it lands.
            recenterToken &+= 1
        }
        .onDisappear {
            locationService.stop()
        }
        .sheet(item: $sessionStartRequest) { request in
            SessionStartSheet(
                sessionManager: ensuredSessionManager(),
                onDismiss: { sessionStartRequest = nil },
                onSessionStarted: {
                    NotificationCenter.default.post(
                        name: .didStartSessionExternally,
                        object: nil
                    )
                },
                initialPrograms: request.programs,
                initialParkReference: request.parkReference,
                initialSotaReference: request.sotaReference
            )
        }
        .sheet(isPresented: $showMultipliersSheet) {
            MultipliersSheet(
                candidates: multiplierCandidates,
                isComputing: isFindingMultipliers,
                onSelect: { zoomToMultiplier($0.coordinate) }
            )
        }
    }

    var mapContent: some View {
        ParkSearchMapKit(
            region: $mapRegion,
            selection: selection,
            boundaries: boundaries,
            adminBoundaries: ExperimentalFeature.isEnabled(.activityLayers) ? adminBoundaries : [],
            sotaZones: ExperimentalFeature.isEnabled(.activityLayers) ? sotaZones : [],
            wwffItems: ExperimentalFeature.isEnabled(.activityLayers) ? wwffItems : [],
            trails: trails,
            parks: displayParks,
            summits: displaySummits,
            boundaryRefs: boundaryRefs,
            showBoundaries: showBoundaries,
            showTrails: showTrails,
            showParkPins: showParkPins,
            showSummitPins: showSummitPins,
            showRadar: showRadarOverlay,
            showGrids: ExperimentalFeature.isEnabled(.activityLayers) && showGridSquares,
            showTiles: ExperimentalFeature.isEnabled(.activityLayers) && showTotaTiles,
            isZoomedIn: isZoomedIn,
            recenterToken: recenterToken,
            homeFallback: homeCoordinate,
            onRegionChange: { region in handleRegionChange(region) },
            onTapCoordinate: { handleMapTap($0) }
        )
    }

    func handleRegionChange(_ region: MKCoordinateRegion) {
        lastVisibleRegion = region
        if showTrails {
            fetchTrailsForRegion(region)
        }
        fetchPinsForRegion(region)
        fetchAdminForRegion(region)
        fetchSotaZonesForRegion(region)
        fetchWWFFForRegion(region)
        Task {
            await fetchBoundariesForRegion(region)
        }
    }
}

extension ParkSearchMapView {
    func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        if let ref = boundaryContaining(coordinate) {
            withAnimation {
                if selection?.parkReference == ref {
                    selection = nil
                } else if let park = findPark(for: ref) {
                    selection = .park(park)
                }
            }
            return
        }
        if let trail = trailContaining(coordinate) {
            withAnimation {
                if selection?.trailReference == trail.reference {
                    selection = nil
                } else {
                    selection = .trail(trail)
                }
            }
            return
        }
        // Annotation taps route through the delegate's didSelect → also
        // come into this handler with the pin coordinate. Resolve to the
        // park/summit by exact coordinate match.
        if let park = displayParks.first(where: {
            ($0.latitude ?? .nan) == coordinate.latitude
                && ($0.longitude ?? .nan) == coordinate.longitude
        }) {
            withAnimation {
                selection = (selection?.parkReference == park.reference) ? nil : .park(park)
            }
            return
        }
        if let summit = displaySummits.first(where: {
            ($0.latitude ?? .nan) == coordinate.latitude
                && ($0.longitude ?? .nan) == coordinate.longitude
        }) {
            withAnimation {
                let already: Bool = if case let .summit(current) = selection {
                    current.code == summit.code
                } else {
                    false
                }
                selection = already ? nil : .summit(summit)
            }
            return
        }
        withAnimation { selection = nil }
    }

    func startSessionFromPark(_ park: POTAPark) {
        sessionStartRequest = MapSessionStartRequest(
            programs: ["pota"],
            parkReference: park.reference,
            sotaReference: nil
        )
    }

    func startSessionFromSummit(_ summit: SOTASummit) {
        sessionStartRequest = MapSessionStartRequest(
            programs: ["sota"],
            parkReference: nil,
            sotaReference: summit.code
        )
    }

    func ensuredSessionManager() -> LoggingSessionManager {
        if let existing = sessionManager {
            return existing
        }
        let manager = LoggingSessionManager(
            modelContext: modelContext,
            locationService: locationService
        )
        sessionManager = manager
        return manager
    }
}
