// WWFF Reference Picker Sheet
//
// Sheet for selecting a WWFF reference. Shows nearby references by
// device GPS location with activation/QSO history, and supports
// filtering by reference code or name. Single-select — tapping a
// row selects and dismisses.

import CarrierWaveCore
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - WWFFRefStats

/// Activation and QSO counts for a WWFF reference
struct WWFFRefStats: Sendable {
    let activationCount: Int
    let qsoCount: Int
}

// MARK: - WWFFRefStatsLoader

/// Background actor for computing per-reference activation and QSO counts
private actor WWFFRefStatsLoader {
    // MARK: Internal

    func loadStats(
        container: ModelContainer
    ) async -> [String: WWFFRefStats] {
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
                predicate: #Predicate {
                    $0.wwffRef != nil && !$0.isHidden
                }
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
                guard let ref = qso.wwffRef, !ref.isEmpty,
                      !Self.metadataModes.contains(qso.mode.uppercased())
                else {
                    continue
                }
                let key = ref.uppercased()
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
            WWFFRefStats(
                activationCount: $0.dates.count, qsoCount: $0.qsoCount
            )
        }
    }

    // MARK: Private

    private static let metadataModes: Set<String> = [
        "WEATHER", "SOLAR", "NOTE",
    ]
}

// MARK: - WWFFReferencePickerSheet

/// Sheet for selecting a WWFF reference by search or nearby location
struct WWFFReferencePickerSheet: View {
    // MARK: Internal

    let userGrid: String?
    let onSelect: (WWFFReference) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                referenceList
            }
            .navigationTitle("Select WWFF Reference")
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
            await WWFFReferencesCache.shared.ensureLoaded()
            await loadNearbyReferences()
        }
        .task {
            await loadRefStats()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var locationManager = ParkLocationManager()
    @State private var nearbyRefs: [(
        reference: WWFFReference, distanceKm: Double
    )] = []
    @State private var searchResults: [WWFFReference] = []
    @State private var refStats: [String: WWFFRefStats] = [:]
    @State private var isLoadingNearby = true

    private var filteredRefs: [(
        reference: WWFFReference, distance: Double?
    )] {
        let query = searchText
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return []
        }

        let nearbyMatches: [(reference: WWFFReference, distance: Double?)] =
            nearbyRefs
                .filter { matchesRef($0.reference, query: query) }
                .map { (reference: $0.reference, distance: Optional($0.distanceKm)) }

        let nearbyCodes = Set(nearbyMatches.map(\.reference.reference))
        let additional: [(reference: WWFFReference, distance: Double?)] =
            searchResults
                .filter { !nearbyCodes.contains($0.reference) }
                .map { (reference: $0, distance: nil) }

        return nearbyMatches + additional
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Area name or reference", text: $searchText)
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

    // MARK: - Reference List

    @ViewBuilder
    private var referenceList: some View {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            nearbyRefsList
        } else if filteredRefs.isEmpty {
            noResultsState
        } else {
            filteredList
        }
    }

    private var filteredList: some View {
        List {
            ForEach(filteredRefs, id: \.reference.reference) { item in
                WWFFRefRow(
                    reference: item.reference,
                    distance: item.distance,
                    stats: refStats[item.reference.reference.uppercased()]
                ) {
                    onSelect(item.reference)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var nearbyRefsList: some View {
        if isLoadingNearby {
            loadingState
        } else if nearbyRefs.isEmpty {
            noNearbyState
        } else {
            List {
                ForEach(nearbyRefs, id: \.reference.reference) { item in
                    WWFFRefRow(
                        reference: item.reference,
                        distance: item.distanceKm,
                        stats: refStats[
                            item.reference.reference.uppercased()
                        ]
                    ) {
                        onSelect(item.reference)
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
            Text("Finding nearby WWFF areas...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noNearbyState: some View {
        ContentUnavailableView {
            Label("No Nearby Areas", systemImage: "leaf.fill")
        } description: {
            Text("No WWFF areas found nearby. Try searching by name or reference.")
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "leaf.fill")
        } description: {
            Text("No WWFF areas matching \"\(searchText)\"")
        }
    }

    // MARK: - Search Logic

    private func matchesRef(
        _ ref: WWFFReference, query: String
    ) -> Bool {
        if ref.reference.lowercased().contains(query) {
            return true
        }
        if ref.name.lowercased().contains(query) {
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

        // Try exact code lookup first
        if let ref = WWFFReferencesCache.shared.lookupReference(trimmed) {
            searchResults = [ref]
            return
        }

        searchResults = WWFFReferencesCache.shared.searchByName(trimmed)
    }

    // MARK: - Data Loading

    private func loadNearbyReferences() async {
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
            nearbyRefs = WWFFReferencesCache.shared.nearbyReferences(
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

        nearbyRefs = WWFFReferencesCache.shared.nearbyReferences(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            limit: 30
        )
    }

    private func loadRefStats() async {
        let container = modelContext.container
        let loader = WWFFRefStatsLoader()
        refStats = await loader.loadStats(container: container)
    }
}

// MARK: - WWFFRefRow

/// Row displaying a WWFF reference with optional distance and stats
struct WWFFRefRow: View {
    // MARK: Internal

    let reference: WWFFReference
    var distance: Double?
    var stats: WWFFRefStats?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reference.reference)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.mint)

                    Text(reference.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let country = reference.country {
                            Text(country)
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

    private func statsBadge(_ stats: WWFFRefStats) -> some View {
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
