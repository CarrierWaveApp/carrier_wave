// Summit Picker Sheet
//
// Sheet for selecting a SOTA summit. Shows nearby summits by
// device GPS location with activation/QSO history, and supports
// filtering by summit code or name. Single-select — tapping a
// row selects and dismisses.

import CarrierWaveData
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - SummitStats

/// Activation and QSO counts for a summit
struct SummitStats: Sendable {
    let activationCount: Int
    let qsoCount: Int
}

// MARK: - SummitStatsLoader

/// Background actor for computing per-summit activation and QSO counts
private actor SummitStatsLoader {
    // MARK: Internal

    func loadStats(container: ModelContainer) async -> [String: SummitStats] {
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
                predicate: #Predicate { $0.sotaRef != nil && !$0.isHidden }
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
                guard let summit = qso.sotaRef, !summit.isEmpty,
                      !Self.metadataModes.contains(qso.mode.uppercased())
                else {
                    continue
                }
                let key = summit.uppercased()
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
            SummitStats(activationCount: $0.dates.count, qsoCount: $0.qsoCount)
        }
    }

    // MARK: Private

    /// Metadata pseudo-modes that should not count as QSOs
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]
}

// MARK: - SummitPickerSheet

/// Sheet for selecting a SOTA summit by search or nearby location
struct SummitPickerSheet: View {
    // MARK: Internal

    let userGrid: String?
    let onSelect: (SOTASummit) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                summitList
            }
            .navigationTitle("Select Summit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadNearbySummits()
        }
        .task {
            await loadSummitStats()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var locationManager = ParkLocationManager()
    @State private var nearbySummits: [(summit: SOTASummit, distanceKm: Double)] = []
    @State private var searchResults: [SOTASummit] = []
    @State private var summitStats: [String: SummitStats] = [:]
    @State private var isLoadingNearby = true

    /// Summits matching the search query
    private var filteredSummits: [(summit: SOTASummit, distance: Double?)] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return []
        }

        let nearbyMatches: [(summit: SOTASummit, distance: Double?)] = nearbySummits
            .filter { matchesSummit($0.summit, query: query) }
            .map { (summit: $0.summit, distance: Optional($0.distanceKm)) }

        let nearbyCodes = Set(nearbyMatches.map(\.summit.code))
        let additional: [(summit: SOTASummit, distance: Double?)] = searchResults
            .filter { !nearbyCodes.contains($0.code) }
            .map { (summit: $0, distance: nil) }

        return nearbyMatches + additional
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Summit name or code", text: $searchText)
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

    // MARK: - Summit List

    @ViewBuilder
    private var summitList: some View {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            nearbySummitsList
        } else if filteredSummits.isEmpty {
            noResultsState
        } else {
            filteredList
        }
    }

    private var filteredList: some View {
        List {
            ForEach(filteredSummits, id: \.summit.code) { item in
                SummitRow(
                    summit: item.summit,
                    distance: item.distance,
                    stats: summitStats[item.summit.code.uppercased()]
                ) {
                    onSelect(item.summit)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var nearbySummitsList: some View {
        if isLoadingNearby {
            loadingState
        } else if nearbySummits.isEmpty {
            noNearbyState
        } else {
            List {
                ForEach(nearbySummits, id: \.summit.code) { item in
                    SummitRow(
                        summit: item.summit,
                        distance: item.distanceKm,
                        stats: summitStats[item.summit.code.uppercased()]
                    ) {
                        onSelect(item.summit)
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
            Text("Finding nearby summits...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noNearbyState: some View {
        ContentUnavailableView {
            Label("No Nearby Summits", systemImage: "mountain.2")
        } description: {
            Text("No summits found nearby. Try searching by name or code.")
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "mountain.2")
        } description: {
            Text("No summits found matching \"\(searchText)\"")
        }
    }

    // MARK: - Search Logic

    private func matchesSummit(_ summit: SOTASummit, query: String) -> Bool {
        if summit.code.lowercased().contains(query) {
            return true
        }
        if summit.name.lowercased().contains(query) {
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

        // If query contains "/", try exact code lookup first
        if trimmed.contains("/") {
            if let summit = SOTASummitsCache.shared.lookupSummit(trimmed) {
                searchResults = [summit]
                return
            }
        }

        searchResults = SOTASummitsCache.shared.searchByName(trimmed)
    }

    // MARK: - Data Loading

    private func loadNearbySummits() async {
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
            nearbySummits = SOTASummitsCache.shared.nearbySummits(
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

        nearbySummits = SOTASummitsCache.shared.nearbySummits(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            limit: 30
        )
    }

    private func loadSummitStats() async {
        let container = modelContext.container
        let loader = SummitStatsLoader()
        summitStats = await loader.loadStats(container: container)
    }
}

// MARK: - SummitRow

/// Row displaying a summit with optional distance and activation stats
struct SummitRow: View {
    // MARK: Internal

    let summit: SOTASummit
    var distance: Double?
    var stats: SummitStats?
    let onSelect: () -> Void

    var body: some View {
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summit.code)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.green)

                    Text(summit.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        altitudeBadge
                        pointsBadge
                        if let stats, stats.qsoCount > 0 {
                            statsBadge(stats)
                        }
                    }
                }

                Spacer()

                if let distance {
                    Text(UnitFormatter.distance(distance))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var altitudeBadge: some View {
        let altText = useMetricUnits
            ? "\(summit.altitudeM)m"
            : "\(summit.altitudeFt)ft"
        return Text(altText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var pointsBadge: some View {
        let total = summit.points + summit.bonusPoints
        let label = total == summit.points
            ? "\(summit.points)pt"
            : "\(summit.points)+\(summit.bonusPoints)pt"
        return Text(label)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.1))
            .clipShape(Capsule())
    }

    private func statsBadge(_ stats: SummitStats) -> some View {
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
}
