import CarrierWaveCore
import MapKit
import SwiftData
import SwiftUI

// MARK: - QSOMapView

struct QSOMapView: View {
    // MARK: Internal

    /// Filter state passed from parent to preserve across view recreations
    @Bindable var filterState: MapFilterState

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
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFilterSheet = true
                } label: {
                    Image(
                        systemName: filterState.hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
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
            .presentationDetents([.medium, .large])
        }
        .task {
            // Only load if we haven't loaded initial data yet
            guard !hasLoadedInitialData else {
                return
            }
            await loadDataInBackground()
        }
        .onChange(of: filterState.selectedBand) { _, _ in
            updateCachedMapData()
        }
        .onChange(of: filterState.selectedMode) { _, _ in
            updateCachedMapData()
        }
        .onChange(of: filterState.selectedPark) { _, _ in
            updateCachedMapData()
        }
        .onChange(of: filterState.startDate) { _, _ in
            updateCachedMapData()
        }
        .onChange(of: filterState.endDate) { _, _ in
            updateCachedMapData()
        }
        .onChange(of: filterState.confirmedOnly) { _, _ in
            updateCachedMapData()
        }
        .onChange(of: filterState.showAllQSOs) { _, _ in
            // Reload QSOs when showAllQSOs changes since it affects fetch limit
            hasLoadedInitialData = false
            Task {
                await loadDataInBackground()
            }
        }
        .onChange(of: filterState.showIndividualQSOs) { _, _ in
            updateCachedMapData()
        }
        .onChange(of: filterState.showPaths) { _, _ in
            updateCachedMapData()
        }
    }

    // MARK: Private

    /// Background actor for loading data off the main thread
    private static let loadingActor = MapDataLoadingActor()

    @Environment(\.modelContext) private var modelContext

    /// Snapshots fetched from background actor
    @State private var allSnapshots: [MapQSOSnapshot] = []

    /// Total count of QSOs (for stats display)
    @State private var totalQSOCount: Int = 0

    @State private var showingFilterSheet = false
    @State private var selectedAnnotation: QSOAnnotation?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoadingQSOs = true
    @State private var hasLoadedInitialData = false
    @State private var loadingProgress: Int = 0

    // Cached computed values to avoid expensive recalculation on every render
    @State private var cachedAnnotations: [QSOAnnotation] = []
    @State private var cachedArcs: [QSOArc] = []
    @State private var cachedUniqueStates: Int = 0
    @State private var cachedUniqueDXCCEntities: Int = 0
    @State private var cachedAvailableBands: [String] = []
    @State private var cachedAvailableModes: [String] = []
    @State private var cachedAvailableParks: [String] = []
    @State private var cachedEarliestQSODate: Date?

    // Additional cached values to avoid computed property access in view body
    @State private var cachedFilteredSnapshotCount: Int = 0
    @State private var cachedIsLimited: Bool = false

    /// Filter snapshots based on current filter state
    private var filteredSnapshots: [MapQSOSnapshot] {
        Self.filterSnapshots(allSnapshots, with: filterState)
    }

    /// Snapshots to display on map, limited for performance unless showAllQSOs is enabled
    private var displayedSnapshots: [MapQSOSnapshot] {
        if filterState.showAllQSOs {
            return filteredSnapshots
        }
        return Array(filteredSnapshots.prefix(MapFilterState.maxQSOsDefault))
    }

    /// Compute annotations from displayed snapshots
    private var annotations: [QSOAnnotation] {
        Self.computeAnnotations(
            from: displayedSnapshots, showIndividual: filterState.showIndividualQSOs
        )
    }

    /// Compute arcs from displayed snapshots
    private var arcs: [QSOArc] {
        guard filterState.showPaths else {
            return []
        }
        return Self.computeArcs(from: displayedSnapshots)
    }

    // MARK: - View Components

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            if totalQSOCount > 0 {
                Text("Loading QSOs... \(loadingProgress)/\(totalQSOCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Loading QSOs...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var mapContentView: some View {
        Map(position: $cameraPosition) {
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
                    MapPolyline(coordinates: arc.geodesicPath())
                        .stroke(.blue.opacity(0.5), lineWidth: 2.5)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private var overlayView: some View {
        VStack {
            if !isLoadingQSOs {
                HStack(alignment: .top) {
                    ActiveFiltersView(
                        filterState: filterState,
                        earliestDate: cachedEarliestQSODate,
                        latestDate: Date()
                    )
                    .onTapGesture {
                        showingFilterSheet = true
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        MapStatsOverlay(
                            totalQSOs: totalQSOCount,
                            visibleQSOs: cachedFilteredSnapshotCount,
                            gridCount: cachedAnnotations.count,
                            stateCount: cachedUniqueStates,
                            dxccCount: cachedUniqueDXCCEntities
                        )

                        if cachedIsLimited {
                            Text("Limited to \(MapFilterState.maxQSOsDefault) for performance")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thickMaterial, in: Capsule())
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
        .animation(.easeInOut, value: selectedAnnotation?.id)
    }

    /// Update cached annotations and arcs when data or filters change
    private func updateCachedMapData() {
        // Cache filtered snapshots first since other computations depend on it
        let filtered = filteredSnapshots
        cachedFilteredSnapshotCount = filtered.count
        cachedIsLimited = !filterState.showAllQSOs && filtered.count > MapFilterState.maxQSOsDefault

        // Now compute annotations and arcs
        cachedAnnotations = annotations
        cachedArcs = arcs

        // Update stats that depend on filtered snapshots
        cachedUniqueStates = Set(filtered.compactMap(\.state).filter { !$0.isEmpty }).count
        cachedUniqueDXCCEntities = Set(filtered.compactMap(\.dxccNumber)).count
    }

    /// Load data using background actor to avoid blocking the main thread
    private func loadDataInBackground() async {
        isLoadingQSOs = true
        loadingProgress = 0
        totalQSOCount = 0

        let container = modelContext.container
        let fetchLimit = filterState.showAllQSOs ? nil : MapFilterState.maxQSOsDefault * 2

        do {
            let data = try await Self.loadingActor.loadMapData(
                container: container,
                fetchLimit: fetchLimit,
                onProgress: { [self] progress in
                    Task { @MainActor in
                        loadingProgress = progress.loaded
                        totalQSOCount = progress.total
                    }
                }
            )

            // Apply results on main actor
            allSnapshots = data.snapshots
            totalQSOCount = data.totalCount
            cachedAvailableBands = data.availableBands
            cachedAvailableModes = data.availableModes
            cachedAvailableParks = data.availableParks
            cachedEarliestQSODate = data.earliestDate

            updateCachedMapData()
            hasLoadedInitialData = true
        } catch {
            // Handle cancellation silently, log other errors
            if !(error is CancellationError) {
                print("Map data loading failed: \(error)")
            }
        }

        isLoadingQSOs = false
    }
}
