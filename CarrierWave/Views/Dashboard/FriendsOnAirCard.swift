import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - FriendsOnAirCard

/// Dashboard card showing friends currently active in POTA spots.
struct FriendsOnAirCard: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if friendSpots.isEmpty {
                emptyState
            } else {
                spotRows
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await loadFriendSpots()
            await autoRefreshLoop()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var friendSpots: [(callsign: String, spot: POTASpot)] = []
    @State private var isLoading = true

    private var friendCallsigns: Set<String> {
        Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.green)
            Text("Friends On Air")
                .font(.headline)
            if !friendSpots.isEmpty {
                Text("\(friendSpots.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        Text("No friends on air")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var spotRows: some View {
        VStack(spacing: 8) {
            ForEach(friendSpots.prefix(3), id: \.callsign) { item in
                friendSpotRow(callsign: item.callsign, spot: item.spot)
            }
        }
    }

    private func friendSpotRow(
        callsign: String,
        spot: POTASpot
    ) -> some View {
        HStack(spacing: 8) {
            Text(callsign)
                .font(.subheadline.weight(.semibold).monospaced())
            Text(spot.reference)
                .font(.caption)
                .foregroundStyle(.green)
            Spacer()
            if let band = BandUtilities.deriveBand(from: spot.frequencyKHz) {
                Text(band)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(spot.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(spot.timeAgo)
                .font(.caption2)
                .foregroundStyle(spot.ageColor)
        }
    }

    // MARK: - Data Loading

    private func loadFriendSpots() async {
        guard !friendCallsigns.isEmpty else {
            friendSpots = []
            isLoading = false
            return
        }

        do {
            let client = POTAClient(authService: POTAAuthService())
            let spots = try await client.fetchActiveSpots()
            friendSpots = spots
                .filter { friendCallsigns.contains($0.activator.uppercased()) }
                .map { (callsign: $0.activator.uppercased(), spot: $0) }
        } catch {
            // Keep existing data on error
        }
        isLoading = false
    }

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else {
                return
            }
            await loadFriendSpots()
        }
    }
}
