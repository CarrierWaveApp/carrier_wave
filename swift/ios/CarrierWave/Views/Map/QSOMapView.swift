import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - QSOMapView

struct QSOMapView: View {
    // MARK: Internal

    /// Filter state passed from parent to preserve across view recreations
    @Bindable var filterState: MapFilterState

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Total count of QSOs (for stats display)
    @State var totalQSOCount: Int = 0

    @State var showingFilterSheet = false
    @State var selectedAnnotation: QSOAnnotation?
    @State var cameraPosition: MapCameraPosition = .automatic
    @State var isLoadingQSOs = true
    @State var hasLoadedInitialData = false

    // Cached computed values to avoid expensive recalculation on every render
    @State var cachedAnnotations: [QSOAnnotation] = []
    @State var cachedArcs: [QSOArc] = []
    @State var cachedUniqueStates: Int = 0
    @State var cachedUniqueDXCCEntities: Int = 0
    @State var cachedAvailableBands: [String] = []
    @State var cachedAvailableModes: [String] = []
    @State var cachedAvailableParks: [String] = []
    @State var cachedEarliestQSODate: Date?

    // Additional cached values to avoid computed property access in view body
    @State var cachedFilteredSnapshotCount: Int = 0
    @State var cachedIsLimited: Bool = false
    @State var cachedStatistics: MapStatistics = .empty

    /// Grid overlay polygons (worked/confirmed status coloring)
    @State var cachedGridPolygons: [GridMapPolygon] = []

    // Grid square overlay state (dynamic boundaries + search)
    @State var visibleGridSquares: [GridSquareInfo] = []
    @State var centerGridLocator: String = ""
    @State var gridSearchText: String = ""
    @State var isGridSearchExpanded: Bool = false
    @State var mapRegion: MKCoordinateRegion?

    var body: some View {
        ZStack {
            Group {
                if isLoadingQSOs {
                    loadingView
                } else {
                    mapContentView
                }
            }
            .ignoresSafeArea(edges: .bottom) // Allow map to extend under tab bar

            // Overlays respect safe area
            overlayView
        }
        .navigationTitle("QSO Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    AzimuthalStandaloneView()
                } label: {
                    Image(systemName: "scope")
                }
                .accessibilityLabel("Azimuthal View")
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        filterState.showGridOverlay.toggle()
                        if filterState.showGridOverlay, cachedGridPolygons.isEmpty {
                            Task { await loadGridOverlay() }
                        }
                    } label: {
                        Image(
                            systemName: filterState.showGridOverlay
                                ? "square.grid.3x3.fill"
                                : "square.grid.3x3"
                        )
                    }
                    .accessibilityLabel(
                        filterState.showGridOverlay ? "Hide grid overlay" : "Show grid overlay"
                    )

                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(
                            systemName: filterState.hasActiveFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .accessibilityLabel(
                        filterState.hasActiveFilters ? "Filter (active)" : "Filter"
                    )
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            MapFilterSheet(
                filterState: filterState,
                availableBands: cachedAvailableBands,
                availableModes: cachedAvailableModes,
                availableParks: cachedAvailableParks,
                earliestDate: cachedEarliestQSODate
            )
            .landscapeAdaptiveDetents(portrait: [.medium, .large])
        }
        .task {
            // Only load if we haven't loaded initial data yet
            guard !hasLoadedInitialData else {
                return
            }
            await reloadFromMapApi()
        }
        .onChange(of: filterState.selectedBand) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.selectedMode) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.selectedPark) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.startDate) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.endDate) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.confirmedOnly) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.showAllQSOs) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.showIndividualQSOs) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.showPaths) { _, _ in
            Task { await reloadFromMapApi() }
        }
        .onChange(of: filterState.showGridOverlay) { _, _ in
            if let region = mapRegion {
                updateGridOverlay(for: region)
            }
        }
    }

    // MARK: Private

    // MARK: - View Components

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading QSOs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var mapContentView: some View {
        Map(position: $cameraPosition) {
            // Worked/confirmed grid coloring (loaded from QSO data)
            ForEach(cachedGridPolygons) { polygon in
                MapPolygon(coordinates: polygon.coordinates)
                    .foregroundStyle(GridOverlayRenderer.fillColor(for: polygon.status))
                    .stroke(
                        GridOverlayRenderer.strokeColor(for: polygon.status),
                        lineWidth: 0.5
                    )
            }

            // Dynamic grid boundary lines + labels (visible when overlay toggled)
            if filterState.showGridOverlay {
                GridSquareMapContent(visibleGrids: visibleGridSquares)
            }

            ForEach(cachedAnnotations) { annotation in
                Annotation(
                    annotation.displayTitle,
                    coordinate: annotation.coordinate,
                    anchor: .bottom
                ) {
                    QSOMarkerView(
                        annotation: annotation,
                        isSelected: selectedAnnotation?.id == annotation.id
                    )
                    .onTapGesture {
                        withAnimation {
                            if selectedAnnotation?.id == annotation.id {
                                selectedAnnotation = nil
                            } else {
                                selectedAnnotation = annotation
                            }
                        }
                    }
                }
            }

            if filterState.showPaths {
                ForEach(cachedArcs) { arc in
                    MapPolyline(coordinates: arc.path)
                        .stroke(.white.opacity(0.5), lineWidth: 2.5)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange(frequency: .onEnd) { context in
            mapRegion = context.region
            updateGridOverlay(for: context.region)
        }
    }

    private var overlayView: some View {
        VStack {
            if !isLoadingQSOs {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        ActiveFiltersView(
                            filterState: filterState,
                            earliestDate: cachedEarliestQSODate,
                            latestDate: Date()
                        )
                        .onTapGesture {
                            showingFilterSheet = true
                        }

                        HStack(spacing: 6) {
                            if !centerGridLocator.isEmpty {
                                CurrentGridLabel(grid: centerGridLocator)
                            }

                            GridSearchBar(
                                searchText: $gridSearchText,
                                isExpanded: $isGridSearchExpanded
                            ) { grid in
                                navigateToGrid(grid)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        MapStatsOverlay(
                            totalQSOs: totalQSOCount,
                            visibleQSOs: cachedFilteredSnapshotCount,
                            gridCount: cachedAnnotations.count,
                            stateCount: cachedUniqueStates,
                            dxccCount: cachedUniqueDXCCEntities,
                            statistics: cachedStatistics
                        )

                        if cachedIsLimited {
                            Text("Limited to \(MapFilterState.maxQSOsDefault) for performance")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
                .padding()
            }

            Spacer()

            if let annotation = selectedAnnotation {
                QSOCalloutView(annotation: annotation)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .easeInOut, value: selectedAnnotation?.id)
    }
}

// MARK: - QSOMapView Data Loading & Grid Helpers

extension QSOMapView {
    /// Load everything from MapApi in one call.
    func reloadFromMapApi() async {
        isLoadingQSOs = cachedAnnotations.isEmpty // spinner only on first load
        do {
            let store = try await CwStoreProvider.shared.store()
            let api = MapApi(store: store)
            let filter = Self.ffiFilter(from: filterState)
            let data = try await Task.detached { try api.qsoMap(filter: filter) }.value

            cachedAnnotations = data.annotations.map(Self.annotation(from:))
            cachedArcs = data.arcs.map(Self.arc(from:))
            cachedStatistics = Self.statistics(from: data.stats)
            cachedUniqueStates = Int(data.stats.uniqueStates)
            cachedUniqueDXCCEntities = Int(data.stats.uniqueDxcc)
            cachedFilteredSnapshotCount = Int(data.filteredCount)
            cachedIsLimited = data.isLimited
            totalQSOCount = Int(data.totalCount)
            cachedAvailableBands = data.availableBands
            cachedAvailableModes = data.availableModes
            cachedAvailableParks = data.availableParks
            cachedEarliestQSODate = data.earliestDate
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }

            if let bounds = data.bounds, !hasLoadedInitialData {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: bounds.centerLat, longitude: bounds.centerLon
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: bounds.cameraLatSpan,
                        longitudeDelta: bounds.cameraLonSpan
                    )
                ))
            }
            hasLoadedInitialData = true
        } catch {
            RadioService.shared.addLog(.error, "Map load failed: \(error)")
        }
        isLoadingQSOs = false
    }

    /// Update grid overlay when the map region changes
    func updateGridOverlay(for region: MKCoordinateRegion) {
        // Always update center grid locator
        let centerCoord = region.center
        centerGridLocator = MaidenheadConverter.grid(from: centerCoord)
            .prefix(4).uppercased()

        // Only compute visible grids when overlay is enabled
        if filterState.showGridOverlay {
            visibleGridSquares = GridSquareComputation.visibleGrids(in: region)
        } else {
            visibleGridSquares = []
        }
    }

    /// Navigate the map camera to center on a grid square
    func navigateToGrid(_ grid: String) {
        guard let coordinate = MaidenheadConverter.coordinate(from: grid) else {
            return
        }
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 10)
                )
            )
        }
    }

    /// Load grid overlay polygons via the store-only grid summary loader.
    func loadGridOverlay() async {
        do {
            let summary = try await GridSummaryLoader.load()
            cachedGridPolygons = GridOverlayRenderer.buildPolygons(from: summary)
        } catch {
            RadioService.shared.addLog(.error, "Grid overlay load failed: \(error)")
        }
    }
}
