import CarrierWaveCore
import CarrierWaveData
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
        .task {
            // Refresh the friend list before loading spots. Was previously
            // gated on `acceptedFriends.count` from a `@Query`, but that
            // observation invalidated the card body on every unrelated
            // SwiftData save and tanked dashboard scroll perf. Re-firing
            // `.task` on view re-appear is sufficient since friendships
            // change rarely.
            loadAcceptedFriends()
            guard !hasLoadedSpots
                || acceptedFriends.count != loadedFriendCount
            else {
                return
            }
            hasLoadedSpots = true
            loadedFriendCount = acceptedFriends.count
            await loadFriendSpots()
        }
        .task {
            // Auto-refresh loop: sleep first since initial load is handled
            // by the task(id:) above. Sleeping first avoids a duplicate
            // network call on every tab switch (where .task re-fires).
            await autoRefreshLoop()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didSyncQSOs)
        ) { _ in
            // Debounce sync-triggered loads — sync can post multiple
            // notifications in quick succession (per batch).
            let now = Date()
            guard now.timeIntervalSince(lastSyncLoad) >= 5 else {
                return
            }
            lastSyncLoad = now
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
                        AccessibilityNotification.Announcement("Start Activity Log first").post()
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { showNoLogToast = false }
                        }
                    }
            }
        }
        .animation(reduceMotion ? .none : .easeInOut, value: showNoLogToast)
    }

    // MARK: Private

    // MARK: - Spot Tap Handling

    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.modelContext) private var modelContext

    /// Friendship list — `@State` + manual fetch. `@Query` observes every
    /// container save and would invalidate this card's body on unrelated
    /// CloudKit / QSO writes during dashboard scroll.
    @State private var acceptedFriends: [Friendship] = []

    @State private var friendSpots: [(callsign: String, spot: POTASpot)] = []
    @State private var isLoading = true
    @State private var hasLoadedSpots = false
    @State private var loadedFriendCount: Int = -1
    @State private var potaClient = POTAClient(authService: POTAAuthService())
    @State private var selectedSpot: EnrichedSpot?
    @State private var showNoLogToast = false
    @State private var lastSyncLoad: Date = .distantPast
    @State private var lastSpotLoadTime: Date = .distantPast

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
                .accessibilityLabel(spotAccessibilityLabel(callsign: item.callsign, spot: item.spot))
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

    private func spotAccessibilityLabel(callsign: String, spot: POTASpot) -> String {
        let band = BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
        return "\(callsign) at \(spot.reference), \(band) \(spot.mode), \(spot.timeAgo)"
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
        return EnrichedSpot(
            spot: unified, distanceMeters: nil,
            bearingDegrees: nil, region: .other
        )
    }

    // MARK: - Data Loading

    private func loadFriendSpots() async {
        guard !friendCallsigns.isEmpty else {
            friendSpots = []
            isLoading = false
            return
        }

        // Debounce: skip if last load was less than 10s ago (unless first load)
        let now = Date()
        guard lastSpotLoadTime == .distantPast
            || now.timeIntervalSince(lastSpotLoadTime) >= 10
        else {
            return
        }
        lastSpotLoadTime = now

        StartupProfiler.shared.record("friendSpots.load.start")
        do {
            let spots = try await potaClient.fetchActiveSpots()
            friendSpots = spots
                .filter { friendCallsigns.contains($0.activator.uppercased()) }
                .map { (callsign: $0.activator.uppercased(), spot: $0) }
        } catch {
            // Keep existing data on error
        }
        isLoading = false
        StartupProfiler.shared.record("friendSpots.load.done")
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

    /// One-shot fetch of accepted Friendships. Replaces a `@Query` that
    /// fired body invalidations on every unrelated container save.
    private func loadAcceptedFriends() {
        acceptedFriends = FriendsSyncService.shared.acceptedFriends
    }
}
