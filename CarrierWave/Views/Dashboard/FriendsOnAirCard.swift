import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - FriendsOnAirCard

/// Dashboard card showing friends currently active in POTA spots.
struct FriendsOnAirCard: View {
    // MARK: Internal

    var manager: ActivityLogManager?

    var body: some View {
        // TimelineView re-renders every 30s so timeAgo stays fresh
        TimelineView(.periodic(from: .now, by: 30)) { _ in
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
        }
        .task(id: acceptedFriends.count) {
            await loadFriendSpots()
        }
        .task {
            await autoRefreshLoop()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didSyncQSOs)
        ) { _ in
            Task { await loadFriendSpots() }
        }
        .sheet(item: $selectedSpot) { spot in
            if let manager {
                SpotLogSheet(spot: spot, manager: manager, onLogged: {
                    selectedSpot = nil
                })
            }
        }
        .overlay(alignment: .bottom) {
            if showNoLogToast {
                Text("Start Activity Log first")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { showNoLogToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: showNoLogToast)
    }

    // MARK: Private

    // MARK: - Spot Tap Handling

    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var friendSpots: [(callsign: String, spot: POTASpot)] = []
    @State private var isLoading = true
    @State private var potaClient = POTAClient(authService: POTAAuthService())
    @State private var selectedSpot: EnrichedSpot?
    @State private var showNoLogToast = false

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
                Button {
                    handleSpotTap(item.spot)
                } label: {
                    friendSpotRow(callsign: item.callsign, spot: item.spot)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func friendSpotRow(
        callsign: String,
        spot: POTASpot
    ) -> some View {
        VStack(spacing: 4) {
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
            }
            HStack {
                if let timestamp = spot.timestamp {
                    Text(Self.utcTimeFormatter.string(from: timestamp) + " UTC")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(spot.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(spot.ageColor)
            }
        }
    }

    private func handleSpotTap(_ spot: POTASpot) {
        guard manager?.activeLog != nil else {
            showNoLogToast = true
            return
        }
        selectedSpot = enrichedSpot(from: spot)
    }

    private func enrichedSpot(from spot: POTASpot) -> EnrichedSpot? {
        guard let freqKHz = spot.frequencyKHz,
              let timestamp = spot.timestamp
        else {
            return nil
        }
        let unified = UnifiedSpot(
            id: "pota-\(spot.spotId)",
            callsign: spot.activator,
            frequencyKHz: freqKHz,
            mode: spot.mode,
            timestamp: timestamp,
            source: .pota,
            snr: nil,
            wpm: nil,
            spotter: spot.spotter,
            spotterGrid: nil,
            parkRef: spot.reference,
            parkName: spot.parkName,
            comments: spot.comments,
            summitCode: nil,
            summitName: nil,
            summitPoints: nil,
            locationDesc: spot.locationDesc,
            stateAbbr: UnifiedSpot.parseState(from: spot.locationDesc)
        )
        return EnrichedSpot(spot: unified, distanceMeters: nil, region: .other)
    }

    // MARK: - Data Loading

    private func loadFriendSpots() async {
        guard !friendCallsigns.isEmpty else {
            friendSpots = []
            isLoading = false
            return
        }

        do {
            let spots = try await potaClient.fetchActiveSpots()
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
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else {
                return
            }
            await loadFriendSpots()
        }
    }
}
