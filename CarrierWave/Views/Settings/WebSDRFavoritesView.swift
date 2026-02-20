import CarrierWaveCore
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - WebSDRFavoritesView

/// Settings view for managing WebSDR favorites.
struct WebSDRFavoritesView: View {
    // MARK: Internal

    @State var enrichments: [String: KiwiSDRStatusFetcher.ReceiverStatus] = [:]
    @State var selectedReceiver: KiwiSDRReceiver?

    var body: some View {
        List {
            if !filteredFavorites.isEmpty {
                favoritesSection
            }

            if isLoading {
                Section("Available") {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Loading receivers...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !filteredReceivers.isEmpty {
                nearbySection
            }

            if advancedMode, searchText.isEmpty {
                addSection
            }

            if searchText.isEmpty {
                advancedToggle
            }
        }
        .searchable(text: $searchText, prompt: "Search by name or location")
        .navigationTitle("WebSDR Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .sheet(item: $selectedReceiver) { receiver in
            ReceiverDetailSheet(
                receiver: receiver,
                enrichment: enrichments[receiver.id],
                isFavorite: isFavorite(receiver),
                onToggleFavorite: { toggleFavorite(receiver) }
            )
            .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .sheet(isPresented: $showAddSheet) {
            AddReceiverSheet { hostPort, name, location, antenna in
                addFavorite(
                    hostPort: hostPort, name: name,
                    location: location, antenna: antenna
                )
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @AppStorage("webSDRAdvancedMode") private var advancedMode = false
    @State private var favorites: [WebSDRFavorite] = []
    @State private var receivers: [KiwiSDRReceiver] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var locationService = GridLocationService()

    // MARK: - Filtering

    private var filteredReceivers: [KiwiSDRReceiver] {
        guard !searchText.isEmpty else {
            return receivers
        }
        let query = searchText.lowercased()
        return receivers.filter {
            $0.name.lowercased().contains(query)
                || $0.location.lowercased().contains(query)
        }
    }

    private var filteredFavorites: [WebSDRFavorite] {
        guard !searchText.isEmpty else {
            return favorites
        }
        let query = searchText.lowercased()
        return favorites.filter {
            $0.displayName.lowercased().contains(query)
                || $0.location.lowercased().contains(query)
        }
    }

    // MARK: - Sections

    private var favoritesSection: some View {
        Section {
            ForEach(filteredFavorites) { favorite in
                if let receiver = receiverForFavorite(favorite) {
                    compactRow(receiver)
                } else {
                    compactFavoriteRow(favorite)
                }
            }
            .onDelete(perform: deleteFavorites)
        } header: {
            Text(
                "\(filteredFavorites.count) favorite\(filteredFavorites.count == 1 ? "" : "s")"
            )
        }
    }

    private var nearbySection: some View {
        Section {
            ForEach(filteredReceivers) { receiver in
                compactRow(receiver)
            }
        } header: {
            Text("Available (\(filteredReceivers.count))")
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showAddSheet = true
            } label: {
                Label("Add by Address", systemImage: "plus")
            }
        } header: {
            Text("Manual")
        } footer: {
            Text(
                "Add a private or unlisted KiwiSDR by entering its host and port."
            )
        }
    }

    private var advancedToggle: some View {
        Section {
            Toggle("Advanced Mode", isOn: $advancedMode)
        } footer: {
            Text(
                "Advanced mode allows manually adding private or unlisted receivers by address."
            )
        }
    }

    // MARK: - Helpers

    private func receiverForFavorite(
        _ favorite: WebSDRFavorite
    ) -> KiwiSDRReceiver? {
        receivers.first { $0.id == favorite.hostPort }
    }

    private func isFavorite(_ receiver: KiwiSDRReceiver) -> Bool {
        favorites.contains { $0.hostPort == receiver.id }
    }

    private func toggleFavorite(_ receiver: KiwiSDRReceiver) {
        if let existing = favorites.first(where: {
            $0.hostPort == receiver.id
        }) {
            modelContext.delete(existing)
        } else {
            let favorite = WebSDRFavorite(
                hostPort: receiver.id,
                displayName: receiver.name,
                location: receiver.location,
                antenna: enrichments[receiver.id]?.antenna
                    ?? receiver.antenna
            )
            modelContext.insert(favorite)
        }
        try? modelContext.save()
        loadFavorites()
    }

    // MARK: - Data Loading

    private func loadData() async {
        loadFavorites()
        isLoading = true

        // Get user location for proximity sorting
        locationService.requestGrid()
        // Brief wait for GPS fix
        try? await Task.sleep(for: .seconds(1))

        let coord = resolveUserCoordinate()
        receivers = await WebSDRDirectory.shared.findNearby(
            grid: locationService.currentGrid,
            latitude: coord?.latitude,
            longitude: coord?.longitude,
            limit: 50
        )
        isLoading = false
        await enrichReceivers()
    }

    private func resolveUserCoordinate() -> CLLocationCoordinate2D? {
        if let grid = locationService.currentGrid {
            return MaidenheadConverter.coordinate(from: grid)
        }
        return nil
    }

    private func loadFavorites() {
        let descriptor = FetchDescriptor<WebSDRFavorite>(
            sortBy: [SortDescriptor(\.addedDate, order: .reverse)]
        )
        favorites = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func enrichReceivers() async {
        let stream = await KiwiSDRStatusFetcher.shared.fetchStatuses(
            for: receivers
        )
        for await status in stream {
            enrichments[status.hostPort] = status
        }
    }

    private func deleteFavorites(at offsets: IndexSet) {
        let filtered = filteredFavorites
        for index in offsets {
            let favorite = filtered[index]
            if let actual = favorites.first(where: {
                $0.id == favorite.id
            }) {
                modelContext.delete(actual)
            }
        }
        try? modelContext.save()
        loadFavorites()
    }

    private func addFavorite(
        hostPort: String, name: String,
        location: String, antenna: String?
    ) {
        let favorite = WebSDRFavorite(
            hostPort: hostPort,
            displayName: name,
            location: location,
            antenna: antenna
        )
        modelContext.insert(favorite)
        try? modelContext.save()
        loadFavorites()
    }
}
