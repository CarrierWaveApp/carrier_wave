import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SidebarRBNSpotsView

/// RBN/My Spots adapted for persistent iPad sidebar display.
/// Shows user's spots by default, with optional target callsign.
struct SidebarRBNSpotsView: View {
    // MARK: Internal

    let callsign: String
    let targetCallsign: String?
    let onSelectSpot: (UnifiedSpot) -> Void

    var displayCallsign: String {
        targetCallsign ?? callsign
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if isLoading, spots.isEmpty {
                loadingView
            } else if let error = errorMessage, spots.isEmpty {
                errorView(error)
            } else if spots.isEmpty {
                emptyView
            } else {
                spotsList
            }
        }
        .task {
            await loadData()
        }
        .task(id: "auto-refresh") {
            await autoRefreshLoop()
        }
        .onChange(of: targetCallsign) { _, _ in
            Task { await loadData() }
        }
    }

    // MARK: Private

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var spots: [UnifiedSpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showMap = false
    @State private var targetGrid: String?

    @State private var spotsService = SpotsService(
        rbnClient: RBNClient(),
        potaClient: POTAClient(authService: POTAAuthService())
    )

    private var friendCallsigns: Set<String> {
        Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
    }

    private var hasMappableSpots: Bool {
        spots.contains { $0.spotterGrid != nil }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            if targetCallsign != nil {
                Text(displayCallsign)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text("\(spots.count) spots")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasMappableSpots {
                Button {
                    showMap.toggle()
                } label: {
                    Image(systemName: showMap ? "list.bullet" : "map")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading spots...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots for \(displayCallsign)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if targetCallsign == nil {
                Text("Start transmitting to be spotted!")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var spotsList: some View {
        Group {
            if showMap {
                SpotsMiniMapView(
                    spots: spots,
                    targetCallsign: displayCallsign,
                    targetGrid: targetGrid
                )
                .frame(height: 200)
            } else {
                spotsListContent
            }
        }
    }

    private var spotsListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(spots) { spot in
                    Button {
                        onSelectSpot(spot)
                    } label: {
                        spotRow(spot)
                    }
                    .buttonStyle(.plain)
                    if spot.id != spots.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadData() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func spotRow(_ spot: UnifiedSpot) -> some View {
        HStack(spacing: 12) {
            sourceIndicator(spot)
            spotBadge(spot)
            spotDetails(spot)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func spotBadge(_ spot: UnifiedSpot) -> some View {
        if spot.isSelfSpot(userCallsign: callsign) {
            Text("SELF")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.indigo)
                .clipShape(Capsule())
        } else if friendCallsigns.contains(spot.callsign.uppercased()) {
            Text("FRIEND")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .clipShape(Capsule())
        }
    }

    private func spotDetails(_ spot: UnifiedSpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            spotHeaderRow(spot)
            spotMetadataRow(spot)
        }
    }

    private func spotHeaderRow(_ spot: UnifiedSpot) -> some View {
        HStack {
            if let spotter = spot.spotter {
                Text(spotter)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            Spacer()
            Text(spot.formattedFrequency)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func spotMetadataRow(_ spot: UnifiedSpot) -> some View {
        HStack {
            if let snr = spot.snr {
                Text("\(snr) dB")
                    .font(.caption)
                    .foregroundStyle(snrColor(snr))
            }
            if let wpm = spot.wpm {
                Text("\(wpm) WPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let parkRef = spot.parkRef {
                Text(parkRef)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Text(spot.mode)
                .font(.caption)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Spacer()
            Text(spot.timeAgo)
                .font(.caption2)
                .foregroundStyle(spot.ageColor)
        }
    }

    private func sourceIndicator(_ spot: UnifiedSpot) -> some View {
        ZStack {
            Circle()
                .fill(sourceColor(spot).opacity(0.2))
                .frame(width: 32, height: 32)
            Image(systemName: sourceIcon(spot))
                .font(.system(size: 14))
                .foregroundStyle(sourceColor(spot))
        }
    }
}

// MARK: - SidebarRBNSpotsView + Helpers

extension SidebarRBNSpotsView {
    func sourceColor(_ spot: UnifiedSpot) -> Color {
        switch spot.source {
        case .rbn:
            if let snr = spot.snr {
                return snrColor(snr)
            }
            return .blue
        case .pota:
            return .green
        case .sota:
            return .orange
        case .wwff:
            return .mint
        }
    }

    func sourceIcon(_ spot: UnifiedSpot) -> String {
        switch spot.source {
        case .rbn:
            if let snr = spot.snr {
                return signalIcon(snr: snr)
            }
            return "antenna.radiowaves.left.and.right"
        case .pota:
            return "leaf.fill"
        case .sota:
            return "mountain.2.fill"
        case .wwff:
            return "leaf.fill"
        }
    }

    func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: .green
        case 15...: .blue
        case 5...: .orange
        default: .red
        }
    }

    func signalIcon(snr: Int) -> String {
        switch snr {
        case 25...: "wifi"
        case 15...: "wifi"
        case 5...: "wifi.exclamationmark"
        default: "wifi.slash"
        }
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let spotsTask = spotsService.fetchSpots(for: displayCallsign, minutes: 10)
            async let gridTask = spotsService.lookupGrid(for: displayCallsign)

            spots = try await spotsTask
            targetGrid = await gridTask

            if showMap, !spots.contains(where: { $0.spotterGrid != nil }) {
                showMap = false
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else {
                return
            }
            await loadData()
        }
    }
}
