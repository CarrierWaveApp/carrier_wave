import MapKit
import SwiftData
import SwiftUI

// MARK: - QSOMapView

struct QSOMapView: View {
    // MARK: Internal

    var body: some View {
        ZStack {
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

            VStack {
                HStack(alignment: .top) {
                    ActiveFiltersView(
                        filterState: filterState,
                        earliestDate: earliestQSODate,
                        latestDate: Date()
                    )

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        MapStatsOverlay(
                            totalQSOs: totalQSOCount,
                            visibleQSOs: filteredQSOs.count,
                            gridCount: cachedAnnotations.count,
                            stateCount: uniqueStates,
                            dxccCount: uniqueDXCCEntities
                        )

                        if isLimited {
                            Text("Limited to \(MapFilterState.maxQSOsDefault) for performance")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                .padding()

                Spacer()

                if let annotation = selectedAnnotation {
                    QSOCalloutView(annotation: annotation)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: selectedAnnotation?.id)
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
                availableBands: availableBands,
                availableModes: availableModes,
                availableParks: availableParks,
                earliestDate: earliestQSODate
            )
            .presentationDetents([.medium, .large])
        }
        .task {
            await loadQSOsInBackground()
        }
        .onChange(of: totalQSOCount) { _, newCount in
            if newCount != lastQSOCount {
                Task {
                    await loadFilterOptionsInBackground()
                }
            }
            updateCachedMapData()
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
            Task {
                await loadQSOsInBackground()
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

    @Environment(\.modelContext) private var modelContext

    /// Modes that represent activation metadata, not actual QSOs
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Batch size for fetching filter options
    private static let filterOptionsBatchSize = 500

    /// QSOs fetched on demand (not using @Query to avoid full table scan)
    @State private var allQSOs: [QSO] = []

    /// Total count of QSOs (for stats display)
    @State private var totalQSOCount: Int = 0

    @State private var filterState = MapFilterState()
    @State private var showingFilterSheet = false
    @State private var selectedAnnotation: QSOAnnotation?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoadingQSOs = false

    // Cached computed values to avoid expensive recalculation on every render
    @State private var cachedAnnotations: [QSOAnnotation] = []
    @State private var cachedArcs: [QSOArc] = []
    @State private var cachedUniqueStates: Int = 0
    @State private var cachedUniqueDXCCEntities: Int = 0
    @State private var cachedAvailableBands: [String] = []
    @State private var cachedAvailableModes: [String] = []
    @State private var cachedAvailableParks: [String] = []
    @State private var cachedEarliestQSODate: Date?
    @State private var lastQSOCount: Int = 0

    private var filteredQSOs: [QSO] {
        allQSOs.filter { qso in
            // Must have their grid
            guard qso.theirGrid?.isEmpty == false else {
                return false
            }

            // Date range filter
            if let start = filterState.startDate, qso.timestamp < start {
                return false
            }
            if let end = filterState.endDate, qso.timestamp > end {
                return false
            }

            // Band filter
            if let band = filterState.selectedBand, qso.band != band {
                return false
            }

            // Mode filter
            if let mode = filterState.selectedMode, qso.mode != mode {
                return false
            }

            // Park filter
            if let park = filterState.selectedPark, qso.parkReference != park {
                return false
            }

            // Confirmed filter (include if confirmed by either QRZ or LoTW)
            if filterState.confirmedOnly, !qso.lotwConfirmed, !qso.qrzConfirmed {
                return false
            }

            return true
        }
    }

    /// QSOs to display on map, limited for performance unless showAllQSOs is enabled
    private var displayedQSOs: [QSO] {
        if filterState.showAllQSOs {
            return filteredQSOs
        }
        return Array(filteredQSOs.prefix(MapFilterState.maxQSOsDefault))
    }

    /// Whether the display is limited due to too many QSOs
    private var isLimited: Bool {
        !filterState.showAllQSOs && filteredQSOs.count > MapFilterState.maxQSOsDefault
    }

    private var annotations: [QSOAnnotation] {
        if filterState.showIndividualQSOs {
            // Show each QSO as an individual marker
            return displayedQSOs.compactMap { qso -> QSOAnnotation? in
                guard let grid = qso.theirGrid, grid.count >= 4,
                      let coordinate = MaidenheadConverter.coordinate(from: grid)
                else {
                    return nil
                }

                return QSOAnnotation(
                    id: qso.id.uuidString,
                    coordinate: coordinate,
                    gridSquare: String(grid.prefix(4)).uppercased(),
                    qsoCount: 1,
                    callsigns: [qso.callsign],
                    mostRecentDate: qso.timestamp
                )
            }
        } else {
            // Group QSOs by 4-char grid for clustering
            var gridGroups: [String: [QSO]] = [:]

            for qso in displayedQSOs {
                guard let grid = qso.theirGrid, grid.count >= 4 else {
                    continue
                }
                let gridKey = String(grid.prefix(4)).uppercased()
                gridGroups[gridKey, default: []].append(qso)
            }

            return gridGroups.compactMap { gridKey, qsos -> QSOAnnotation? in
                guard let coordinate = MaidenheadConverter.coordinate(from: gridKey) else {
                    return nil
                }

                let callsigns = qsos.map(\.callsign).sorted()
                let mostRecent = qsos.map(\.timestamp).max() ?? Date()

                return QSOAnnotation(
                    id: gridKey,
                    coordinate: coordinate,
                    gridSquare: gridKey,
                    qsoCount: qsos.count,
                    callsigns: callsigns,
                    mostRecentDate: mostRecent
                )
            }
        }
    }

    private var arcs: [QSOArc] {
        guard filterState.showPaths else {
            return []
        }

        var result: [QSOArc] = []

        for qso in displayedQSOs {
            guard let myGrid = qso.myGrid,
                  let theirGrid = qso.theirGrid,
                  let from = MaidenheadConverter.coordinate(from: myGrid),
                  let to = MaidenheadConverter.coordinate(from: theirGrid)
            else {
                continue
            }

            result.append(
                QSOArc(
                    id: qso.id.uuidString,
                    from: from,
                    to: to,
                    callsign: qso.callsign
                )
            )
        }

        return result
    }

    private var availableBands: [String] {
        cachedAvailableBands
    }

    private var availableModes: [String] {
        cachedAvailableModes
    }

    /// Earliest QSO date for date picker defaults
    private var earliestQSODate: Date? {
        cachedEarliestQSODate
    }

    private var availableParks: [String] {
        cachedAvailableParks
    }

    /// Unique US states from filtered QSOs
    private var uniqueStates: Int {
        cachedUniqueStates
    }

    /// Unique DXCC entities from filtered QSOs
    private var uniqueDXCCEntities: Int {
        cachedUniqueDXCCEntities
    }

    private func bandSortOrder(_ band: String) -> Int {
        let order = [
            "160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M",
            "70CM",
        ]
        return order.firstIndex(of: band.uppercased()) ?? 999
    }

    /// Update cached annotations and arcs when data or filters change
    private func updateCachedMapData() {
        cachedAnnotations = annotations
        cachedArcs = arcs

        // Update stats that depend on filtered QSOs
        let filtered = filteredQSOs
        cachedUniqueStates = Set(filtered.compactMap(\.state).filter { !$0.isEmpty }).count
        cachedUniqueDXCCEntities = Set(filtered.compactMap { $0.dxccEntity?.number }).count
    }

    /// Update cached filter options from loaded QSOs
    private func updateCachedFilterOptions() {
        cachedAvailableBands = Array(Set(allQSOs.map(\.band))).sorted { band1, band2 in
            bandSortOrder(band1) < bandSortOrder(band2)
        }
        cachedAvailableModes = Array(Set(allQSOs.map(\.mode)))
            .filter { !Self.metadataModes.contains($0.uppercased()) }
            .sorted()
        cachedAvailableParks = Array(Set(allQSOs.compactMap(\.parkReference))).sorted()
        cachedEarliestQSODate = allQSOs.map(\.timestamp).min()
        lastQSOCount = totalQSOCount
    }

    /// Load QSOs in background with pagination
    private func loadQSOsInBackground() async {
        isLoadingQSOs = true

        // First get total count
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        totalQSOCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        // Determine how many to fetch based on filter settings
        let fetchLimit = filterState.showAllQSOs ? totalQSOCount : MapFilterState.maxQSOsDefault * 2

        // Fetch QSOs with limit
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchLimit = fetchLimit

        if let fetched = try? modelContext.fetch(descriptor) {
            allQSOs = fetched
        }

        // Load filter options in background
        await loadFilterOptionsInBackground()

        updateCachedMapData()
        isLoadingQSOs = false
    }

    /// Load filter options by scanning QSOs in batches (for large datasets)
    private func loadFilterOptionsInBackground() async {
        var bands: Set<String> = []
        var modes: Set<String> = []
        var parks: Set<String> = []
        var earliestDate: Date?

        // For small datasets, just use loaded QSOs
        if totalQSOCount <= MapFilterState.maxQSOsDefault * 2 {
            updateCachedFilterOptions()
            return
        }

        // For large datasets, scan in batches
        var offset = 0
        let batchSize = Self.filterOptionsBatchSize

        while offset < totalQSOCount {
            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }

            if batch.isEmpty {
                break
            }

            // Collect unique values
            for qso in batch {
                bands.insert(qso.band)
                modes.insert(qso.mode)
                if let park = qso.parkReference {
                    parks.insert(park)
                }
                if earliestDate == nil || qso.timestamp < earliestDate! {
                    earliestDate = qso.timestamp
                }
            }

            offset += batchSize
            await Task.yield()
        }

        // Update cached values
        cachedAvailableBands = Array(bands).sorted { band1, band2 in
            bandSortOrder(band1) < bandSortOrder(band2)
        }
        cachedAvailableModes = Array(modes)
            .filter { !Self.metadataModes.contains($0.uppercased()) }
            .sorted()
        cachedAvailableParks = Array(parks).sorted()
        cachedEarliestQSODate = earliestDate
        lastQSOCount = totalQSOCount
    }
}
