import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - WebSDRPickerSheet

/// Sheet for selecting a nearby KiwiSDR receiver.
/// Shows favorites (if any) then receivers sorted by proximity.
struct WebSDRPickerSheet: View {
    // MARK: Internal

    let myGrid: String?
    let operatingBand: String?
    let onSelect: (KiwiSDRReceiver) -> Void

    var body: some View {
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if receivers.isEmpty {
                    emptyView
                } else {
                    receiverList
                }
            }
            .navigationTitle("Nearby WebSDRs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadReceivers() }
        }
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var receivers: [KiwiSDRReceiver] = []
    @State private var favorites: [WebSDRFavorite] = []
    @State private var enrichments: [String: KiwiSDRStatusFetcher.ReceiverStatus] = [:]
    @State private var isLoading = true

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding nearby WebSDRs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No WebSDRs found")
                .font(.headline)
            Text("Check your internet connection and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await loadReceivers() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var receiverList: some View {
        List {
            favoritesSection
            nearbySection
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let favoriteReceivers = receivers.filter { isFavorite($0) }
        if !favoriteReceivers.isEmpty {
            Section("Favorites") {
                ForEach(favoriteReceivers) { receiver in
                    receiverButton(receiver)
                }
            }
        }
    }

    private var nearbySection: some View {
        Section(favorites.isEmpty ? "Nearby" : "All Nearby") {
            ForEach(receivers) { receiver in
                receiverButton(receiver)
            }
        }
    }

    private func receiverButton(_ receiver: KiwiSDRReceiver) -> some View {
        Button {
            onSelect(receiver)
        } label: {
            WebSDRReceiverRow(
                receiver: receiver,
                enrichment: enrichments[receiver.id],
                isFavorite: isFavorite(receiver),
                operatingBand: operatingBand,
                onToggleFavorite: { toggleFavorite(receiver) }
            )
        }
        .disabled(!receiver.isAvailable)
    }

    private func isFavorite(_ receiver: KiwiSDRReceiver) -> Bool {
        favorites.contains { $0.hostPort == receiver.id }
    }

    private func loadReceivers() async {
        isLoading = true
        loadFavorites()
        await WebSDRDirectory.shared.refresh()
        let grid = myGrid
            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
        receivers = await WebSDRDirectory.shared.findNearby(
            grid: grid,
            limit: 20
        )
        isLoading = false
        await enrichReceivers()
    }

    private func loadFavorites() {
        let descriptor = FetchDescriptor<WebSDRFavorite>(
            sortBy: [SortDescriptor(\.addedDate, order: .reverse)]
        )
        favorites = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func toggleFavorite(_ receiver: KiwiSDRReceiver) {
        if let existing = favorites.first(where: { $0.hostPort == receiver.id }) {
            modelContext.delete(existing)
        } else {
            let favorite = WebSDRFavorite(
                hostPort: receiver.id,
                displayName: receiver.name,
                location: receiver.location,
                antenna: enrichments[receiver.id]?.antenna ?? receiver.antenna
            )
            modelContext.insert(favorite)
        }
        try? modelContext.save()
        loadFavorites()
    }

    private func enrichReceivers() async {
        let stream = await KiwiSDRStatusFetcher.shared.fetchStatuses(for: receivers)
        for await status in stream {
            enrichments[status.hostPort] = status
        }
    }
}
