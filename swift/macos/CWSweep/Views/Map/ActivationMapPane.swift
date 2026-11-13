import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftData
import SwiftUI

// MARK: - ActivationMapState

/// Describes the current map display mode based on entry field state.
enum ActivationMapState {
    case idle
    case lookupPending
    case geodesicFocus(grid: String)
}

// MARK: - ActivationMapSpotMode

/// Which set of spots — if any — the activation map renders.
/// `.rbn` shows skimmer locations that heard the user's callsign.
/// `.allSpots` shows every non-self spot with a known DX grid.
/// `.savedQuery` filters `spotAggregator.spots` through a saved SQL
/// query's `spot_id` allow-list, mirroring the band scope's filter mode.
/// Persisted via `@AppStorage` on `ActivationMapPane`.
enum ActivationMapSpotMode: Equatable, RawRepresentable {
    case off
    case rbn
    case allSpots
    case savedQuery(UUID)

    // MARK: Lifecycle

    init?(rawValue: String) {
        switch rawValue {
        case "off": self = .off
        case "rbn": self = .rbn
        case "allSpots": self = .allSpots
        default:
            if rawValue.hasPrefix("savedQuery:"),
               let uuid = UUID(uuidString: String(rawValue.dropFirst("savedQuery:".count)))
            {
                self = .savedQuery(uuid)
                return
            }
            return nil
        }
    }

    // MARK: Internal

    var rawValue: String {
        switch self {
        case .off: "off"
        case .rbn: "rbn"
        case .allSpots: "allSpots"
        case let .savedQuery(uuid): "savedQuery:\(uuid.uuidString)"
        }
    }

    var savedQueryID: UUID? {
        if case let .savedQuery(uuid) = self {
            return uuid
        }
        return nil
    }
}

// MARK: - PlottableQSO

/// Value-type snapshot of a QSO for map rendering.
/// Using a struct instead of @Model objects ensures @State detects changes
/// when enrichment fills in theirGrid after the initial QSO insert.
struct PlottableQSO: Identifiable, Equatable {
    let id: UUID
    let callsign: String
    let band: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: PlottableQSO, rhs: PlottableQSO) -> Bool {
        lhs.id == rhs.id
            && lhs.callsign == rhs.callsign
            && lhs.band == rhs.band
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

// MARK: - ActivationMapPane

/// Map view for the activator layout showing QSO locations, geodesic arcs during
/// callsign entry, and a toggleable RBN propagation overlay.
struct ActivationMapPane: View {
    // MARK: Internal

    /// Band colors matching QSOMapView
    static let bandColors: [String: Color] = [
        "160m": .purple, "80m": .indigo,
        "60m": Color(red: 0.3, green: 0.3, blue: 0.7),
        "40m": .blue, "30m": .teal, "20m": .green, "17m": .mint,
        "15m": .yellow, "12m": .orange, "10m": .red, "6m": .pink,
        "2m": Color(red: 0.8, green: 0.4, blue: 0.8),
    ]

    let sessionId: UUID?

    @Environment(\.modelContext) var modelContext
    @Environment(SelectionState.self) var selectionState
    @Environment(SpotAggregator.self) var spotAggregator

    @AppStorage("myGrid") var myGrid = ""
    @AppStorage("myCallsign") var myCallsign = ""
    /// One-of mode picker — RBN skimmers, all spots, or a saved-query
    /// allow-list. RBN is the default since most activators want to see
    /// where they're being heard.
    @AppStorage("activationMapSpotMode") var spotMode: ActivationMapSpotMode = .rbn
    @Environment(\.savedQueryStore) var savedQueryStore

    /// Plottable QSO snapshots — value types so @State detects changes after enrichment.
    /// `internal` so the camera helpers (split across extension files) can read them.
    @State var plottableQSOs: [PlottableQSO] = []
    @State var cameraPosition: MapCameraPosition = .automatic
    @State var cachedRenderedCount = 0
    /// Local query runner — independent from the band scope's so the
    /// activation map can show one query while the band scope shows
    /// another (or none). Lightweight: 1Hz polling, single SQL prepare.
    @State var queryRunner = BandScopeQueryRunner()
    @State var savedQueries: [SavedQuery] = []
    @State var validQueryIDs: Set<UUID> = []

    /// Bridge to `openWindow` for the toolbar's saved-query menu items.
    /// Kept as a stored property since extensions can't declare them.
    @Environment(\.openWindow) var openWindow

    var mapState: ActivationMapState {
        guard selectionState.entryInProgress else {
            return .idle
        }
        if let grid = selectionState.entryCallsignGrid {
            return .geodesicFocus(grid: grid)
        }
        return .lookupPending
    }

    var userCoordinate: CLLocationCoordinate2D? {
        guard !myGrid.isEmpty,
              let coord = MaidenheadConverter.coordinate(from: myGrid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let queryError = queryRunner.error, case .savedQuery = spotMode {
                queryErrorBanner(queryError)
            }
            Divider()
            mapContent
        }
        .task(id: refreshToken) { await loadSessionQSOs() }
        .task {
            await refreshSavedQueries()
            applySpotMode()
        }
        // Periodic re-fetch — covers QSOs whose `theirGrid` populates
        // asynchronously (callsign enrichment, CloudKit sync inbound,
        // ADIF imports), since none of those paths flow through
        // `selectionState.logUpdatedQSORow`. 5s is fast enough that the
        // dot pops in promptly without thrashing the model context.
        .task(id: sessionId) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else {
                    break
                }
                await loadSessionQSOs()
            }
        }
        .onChange(of: selectionState.logInsertedQSORow?.id) { _, _ in refreshToken += 1 }
        .onChange(of: selectionState.logRemovedQSOId) { _, _ in refreshToken += 1 }
        .onChange(of: selectionState.logUpdatedQSORow?.id) { _, _ in refreshToken += 1 }
        .onChange(of: spotAggregator.spotsVersion) { _, _ in updateSpotCounts() }
        .onChange(of: spotMode) { _, _ in
            applySpotMode()
            updateSpotCounts()
        }
        .onChange(of: queryRunner.allowedSpotIDs) { _, _ in updateSpotCounts() }
        .onReceive(NotificationCenter.default.publisher(for: .savedQueriesChanged)) { _ in
            Task { await refreshSavedQueries() }
        }
        .onAppear { updateSpotCounts() }
    }

    // MARK: Private

    @State private var sessionQSOCount = 0
    @State private var refreshToken = 0

    // MARK: - Map Content

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            // User QTH marker
            if let coord = userCoordinate {
                Annotation("My QTH", coordinate: coord) {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.blue, in: Circle())
                }
                .annotationTitles(.hidden)
            }

            // Geodesic paths from activator to each QSO
            if let myCoord = userCoordinate {
                ForEach(plottableQSOs) { qso in
                    MapPolyline(
                        coordinates: geodesicPath(
                            from: myCoord, to: qso.coordinate
                        )
                    )
                    .stroke(.white.opacity(0.5), lineWidth: 2.5)
                }
            }

            // QSO markers
            ForEach(plottableQSOs) { qso in
                Annotation(qso.callsign, coordinate: qso.coordinate) {
                    Circle()
                        .fill(Self.bandColors[qso.band] ?? .gray)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                }
                .annotationTitles(.hidden)
            }

            // Geodesic arc
            arcOverlay

            // Mode-driven spot rendering — single source of truth so RBN,
            // all-spots, and SQL-query modes can't double-draw.
            if spotMode == .rbn {
                rbnAnnotations
            }
            if spotMode == .allSpots {
                spotAnnotations
            }
            if case .savedQuery = spotMode {
                queryAnnotations
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onChange(of: mapState.cameraKey) { _, _ in updateCamera() }
        .onChange(of: plottableQSOs.count) { _, _ in
            if case .idle = mapState {
                updateCamera()
            }
        }
        .onAppear { updateCamera() }
    }

    // MARK: - Data Loading

    private func updateSpotCounts() {
        switch spotMode {
        case .off:
            cachedRenderedCount = 0
        case .rbn:
            cachedRenderedCount = rbnSkimmerSpots.count
        case .allSpots:
            cachedRenderedCount = plottableSpots.count
        case .savedQuery:
            cachedRenderedCount = querySpots.count
        }
    }

    /// Reload the saved-query list from the actor-backed store, then
    /// classify which queries can drive a spot allow-list (i.e. include
    /// a `spot_id` column). Mirrors `BandMapView.refreshSavedQueries`.
    private func refreshSavedQueries() async {
        guard let store = savedQueryStore else {
            return
        }
        let list = await (try? store.list()) ?? []
        savedQueries = list
        var valid: Set<UUID> = []
        for query in list where await queryRunner.hasSpotIDColumn(sql: query.sql) {
            valid.insert(query.id)
        }
        validQueryIDs = valid
    }

    /// Wire the local query runner to reflect the current mode. Modes
    /// other than `.savedQuery` clear the runner so it isn't polling
    /// stale SQL in the background.
    private func applySpotMode() {
        switch spotMode {
        case .off,
             .rbn,
             .allSpots:
            queryRunner.setQuery(nil)
        case let .savedQuery(uuid):
            Task {
                await refreshSavedQueries()
                if let query = savedQueries.first(where: { $0.id == uuid }) {
                    queryRunner.setQuery(query)
                } else {
                    spotMode = .rbn
                }
            }
        }
    }

    private func loadSessionQSOs() async {
        guard let sessionId else {
            plottableQSOs = []
            sessionQSOCount = 0
            return
        }
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.loggingSessionId == sessionId && !qso.isHidden
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)],
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        let fetched = (try? modelContext.boundedFetch(descriptor)) ?? []
        sessionQSOCount = fetched.count
        plottableQSOs = fetched.compactMap { qso -> PlottableQSO? in
            guard let grid = qso.theirGrid,
                  MaidenheadConverter.isValid(grid),
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return PlottableQSO(
                id: qso.id,
                callsign: qso.callsign,
                band: qso.band,
                coordinate: CLLocationCoordinate2D(
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
            )
        }
    }
}
