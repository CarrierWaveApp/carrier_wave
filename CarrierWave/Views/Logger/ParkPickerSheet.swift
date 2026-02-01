// Park Picker Sheet
//
// Sheet for selecting a POTA park by search or nearby location.
// Provides two tabs: search by name and nearby parks based on grid.

import CoreLocation
import SwiftUI

// MARK: - ParkPickerSheet

/// Sheet for selecting a park by search or nearby location
struct ParkPickerSheet: View {
    // MARK: Lifecycle

    init(
        selectedPark: Binding<String>,
        userGrid: String?,
        defaultCountry: String = "US",
        onDismiss: @escaping () -> Void
    ) {
        _selectedPark = selectedPark
        self.userGrid = userGrid
        self.defaultCountry = defaultCountry
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    enum Tab: String, CaseIterable {
        case search = "Search"
        case nearby = "Nearby"
    }

    @Binding var selectedPark: String

    let userGrid: String?
    let defaultCountry: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .search:
                    searchTab
                case .nearby:
                    nearbyTab
                }
            }
            .navigationTitle("Select Park")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
    }

    // MARK: Private

    @State private var selectedTab: Tab = .search
    @State private var searchText = ""
    @State private var searchResults: [POTAPark] = []
    @State private var nearbyParks: [(park: POTAPark, distanceKm: Double)] = []
    @State private var isLoadingNearby = false
    @State private var nearbyError: String?

    // MARK: - Search Tab

    private var searchTab: some View {
        VStack(spacing: 0) {
            searchField
            searchResultsList
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search park name or reference", text: $searchText)
                .textInputAutocapitalization(.words)
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

    private var searchResultsList: some View {
        Group {
            if searchText.isEmpty {
                searchEmptyState
            } else if searchResults.isEmpty {
                noResultsState
            } else {
                List {
                    ForEach(searchResults, id: \.reference) { park in
                        ParkRow(park: park, distance: nil) {
                            selectPark(park)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var searchEmptyState: some View {
        ContentUnavailableView {
            Label("Search Parks", systemImage: "magnifyingglass")
        } description: {
            Text("Enter a park name or reference to search")
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "tree")
        } description: {
            Text("No parks found matching \"\(searchText)\"")
        }
    }

    // MARK: - Nearby Tab

    private var nearbyTab: some View {
        Group {
            if userGrid == nil || userGrid?.isEmpty == true {
                gridNotSetState
            } else if isLoadingNearby {
                loadingState
            } else if let error = nearbyError {
                errorState(message: error)
            } else if nearbyParks.isEmpty {
                noNearbyParksState
            } else {
                nearbyParksList
            }
        }
    }

    private var gridNotSetState: some View {
        ContentUnavailableView {
            Label("Grid Not Set", systemImage: "location.slash")
        } description: {
            Text("Set your grid square in Settings to see nearby parks")
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding nearby parks...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noNearbyParksState: some View {
        ContentUnavailableView {
            Label("No Nearby Parks", systemImage: "tree")
        } description: {
            Text("No POTA parks found within 100km of your location")
        }
    }

    private var nearbyParksList: some View {
        List {
            ForEach(nearbyParks, id: \.park.reference) { item in
                ParkRow(park: item.park, distance: item.distanceKm) {
                    selectPark(item.park)
                }
            }
        }
        .listStyle(.plain)
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        // First try direct reference lookup
        if let park = POTAParksCache.shared.lookupPark(trimmed, defaultCountry: defaultCountry) {
            searchResults = [park]
            return
        }

        // Fall back to name search
        searchResults = POTAParksCache.shared.searchByName(trimmed)
    }

    private func loadNearbyParks() async {
        guard let grid = userGrid, !grid.isEmpty else {
            return
        }

        guard let coordinate = MaidenheadConverter.coordinate(from: grid) else {
            nearbyError = "Invalid grid square format"
            return
        }

        isLoadingNearby = true
        nearbyError = nil

        // Small delay to allow UI to update
        try? await Task.sleep(for: .milliseconds(100))

        nearbyParks = POTAParksCache.shared.nearbyParks(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        isLoadingNearby = false
    }

    private func selectPark(_ park: POTAPark) {
        selectedPark = park.reference
        onDismiss()
    }
}

// MARK: - ParkRow

/// Row displaying a park with optional distance
struct ParkRow: View {
    // MARK: Internal

    let park: POTAPark
    var distance: Double?
    let onSelect: () -> Void

    var body: some View {
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

                    if let state = park.state {
                        Text(state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private func formatDistance(_ km: Double) -> String {
        if km < 1 {
            String(format: "%.0f m", km * 1_000)
        } else if km < 10 {
            String(format: "%.1f km", km)
        } else {
            String(format: "%.0f km", km)
        }
    }
}

// MARK: - Preview

#Preview("Search Tab") {
    ParkPickerSheet(
        selectedPark: .constant(""),
        userGrid: "FN31",
        defaultCountry: "US",
        onDismiss: {}
    )
}

#Preview("No Grid") {
    ParkPickerSheet(
        selectedPark: .constant(""),
        userGrid: nil,
        defaultCountry: "US",
        onDismiss: {}
    )
}
