// Park Picker Sheet
//
// Sheet for selecting POTA parks. Shows nearby parks by device
// GPS location with activation/QSO history, and supports
// filtering by park number or name. Supports multi-select
// for n-fer activations.

import CoreLocation
import SwiftData
import SwiftUI

// MARK: - ParkStats

/// Activation and QSO counts for a park
struct ParkStats: Sendable {
    let activationCount: Int
    let qsoCount: Int
}

// MARK: - ParkStatsLoader

/// Background actor for computing per-park activation and QSO counts
private actor ParkStatsLoader {
    // MARK: Internal

    func loadStats(container: ModelContainer) async -> [String: ParkStats] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var stats: [String: (qsoCount: Int, dates: Set<String>)] = [:]
        let batchSize = 1_000
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.parkReference != nil && !$0.isHidden }
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset

            guard let batch = try? context.fetch(descriptor) else {
                break
            }
            if batch.isEmpty {
                break
            }

            for qso in batch {
                guard let park = qso.parkReference, !park.isEmpty,
                      !Self.metadataModes.contains(qso.mode.uppercased())
                else {
                    continue
                }
                let key = park.uppercased()
                let dateStr = dateFormatter.string(from: qso.timestamp)
                var entry = stats[key, default: (qsoCount: 0, dates: [])]
                entry.qsoCount += 1
                entry.dates.insert(dateStr)
                stats[key] = entry
            }

            offset += batchSize
            await Task.yield()
        }

        return stats.mapValues {
            ParkStats(activationCount: $0.dates.count, qsoCount: $0.qsoCount)
        }
    }

    // MARK: Private

    /// Metadata pseudo-modes that should not count as QSOs
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]
}

// MARK: - ParkPickerSheet

/// Sheet for adding parks by search or nearby location (multi-select)
struct ParkPickerSheet: View {
    // MARK: Lifecycle

    init(
        selectedParks: [String],
        userGrid: String?,
        defaultCountry: String = "US",
        onAdd: @escaping (POTAPark) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _selectedParks = State(initialValue: Set(selectedParks.map { $0.uppercased() }))
        self.userGrid = userGrid
        self.defaultCountry = defaultCountry
        self.onAdd = onAdd
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    let userGrid: String?
    let defaultCountry: String
    let onAdd: (POTAPark) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                parkList
            }
            .navigationTitle("Add Park")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadNearbyParks()
        }
        .task {
            await loadParkStats()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    /// Parks already selected (shown with checkmark, not dismissing on tap)
    @State private var selectedParks: Set<String>
    @State private var searchText = ""
    @State private var locationManager = ParkLocationManager()
    @State private var nearbyParks: [(park: POTAPark, distanceKm: Double)] = []
    @State private var searchResults: [POTAPark] = []
    @State private var parkStats: [String: ParkStats] = [:]
    @State private var isLoadingNearby = true

    /// Parks matching the search query
    private var filteredParks: [(park: POTAPark, distance: Double?)] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return []
        }

        let nearbyMatches: [(park: POTAPark, distance: Double?)] = nearbyParks
            .filter { matchesPark($0.park, query: query) }
            .map { (park: $0.park, distance: Optional($0.distanceKm)) }

        let nearbyRefs = Set(nearbyMatches.map(\.park.reference))
        let additional: [(park: POTAPark, distance: Double?)] = searchResults
            .filter { !nearbyRefs.contains($0.reference) }
            .map { (park: $0, distance: nil) }

        return nearbyMatches + additional
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Park name or number", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    performSearch(query: newValue)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Park List

    @ViewBuilder
    private var parkList: some View {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            nearbyParksList
        } else if filteredParks.isEmpty {
            noResultsState
        } else {
            filteredList
        }
    }

    private var filteredList: some View {
        List {
            ForEach(filteredParks, id: \.park.reference) { item in
                ParkRow(
                    park: item.park,
                    distance: item.distance,
                    stats: parkStats[item.park.reference],
                    isSelected: isSelected(item.park)
                ) {
                    addPark(item.park)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var nearbyParksList: some View {
        if isLoadingNearby {
            loadingState
        } else if nearbyParks.isEmpty {
            noNearbyState
        } else {
            List {
                ForEach(nearbyParks, id: \.park.reference) { item in
                    ParkRow(
                        park: item.park,
                        distance: item.distanceKm,
                        stats: parkStats[item.park.reference],
                        isSelected: isSelected(item.park)
                    ) {
                        addPark(item.park)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Empty States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding nearby parks...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noNearbyState: some View {
        ContentUnavailableView {
            Label("No Nearby Parks", systemImage: "tree")
        } description: {
            Text("No parks found nearby. Try searching by name or number.")
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "tree")
        } description: {
            Text("No parks found matching \"\(searchText)\"")
        }
    }

    private func isSelected(_ park: POTAPark) -> Bool {
        selectedParks.contains(park.reference.uppercased())
    }

    // MARK: - Search Logic

    private func matchesPark(_ park: POTAPark, query: String) -> Bool {
        if park.reference.lowercased().contains(query) {
            return true
        }
        if park.numericPart.lowercased().contains(query) {
            return true
        }
        if park.name.lowercased().contains(query) {
            return true
        }
        return false
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        if let park = POTAParksCache.shared.lookupPark(
            trimmed, defaultCountry: defaultCountry
        ) {
            searchResults = [park]
            return
        }

        searchResults = POTAParksCache.shared.searchByName(trimmed)
    }

    // MARK: - Data Loading

    private func loadNearbyParks() async {
        isLoadingNearby = true
        defer { isLoadingNearby = false }

        locationManager.requestLocation()

        for _ in 0 ..< 30 {
            if locationManager.location != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        if let location = locationManager.location {
            nearbyParks = POTAParksCache.shared.nearbyParks(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                limit: 30
            )
            return
        }

        guard let grid = userGrid, !grid.isEmpty,
              let coordinate = MaidenheadConverter.coordinate(from: grid)
        else {
            return
        }

        nearbyParks = POTAParksCache.shared.nearbyParks(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            limit: 30
        )
    }

    private func loadParkStats() async {
        let container = modelContext.container
        let loader = ParkStatsLoader()
        parkStats = await loader.loadStats(container: container)
    }

    private func addPark(_ park: POTAPark) {
        guard !isSelected(park) else {
            return
        }
        selectedParks.insert(park.reference.uppercased())
        onAdd(park)
    }
}

// MARK: - ParkRow

/// Row displaying a park with optional distance and activation stats
struct ParkRow: View {
    // MARK: Internal

    let park: POTAPark
    var distance: Double?
    var stats: ParkStats?
    var isSelected: Bool = false
    let onSelect: () -> Void

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(park.reference)
                            .font(.subheadline.monospaced().weight(.semibold))
                            .foregroundStyle(.green)

                        Text(park.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if let state = park.state {
                                Text(state)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let stats, stats.qsoCount > 0 {
                                statsBadge(stats)
                            }
                        }
                    }

                    Spacer()

                    if let distance {
                        Text(formatDistance(distance))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isSelected)

            Button { showDetail = true } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(park.reference)")
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showDetail) {
            ParkDetailSheet(reference: park.reference)
        }
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false
    @State private var showDetail = false

    private func statsBadge(_ stats: ParkStats) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption2)
            Text("\(stats.activationCount)")
                .font(.caption.monospacedDigit())
            Text("·")
                .font(.caption)
            Text("\(stats.qsoCount) Qs")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }

    private func formatDistance(_ km: Double) -> String {
        UnitFormatter.distance(km)
    }
}
