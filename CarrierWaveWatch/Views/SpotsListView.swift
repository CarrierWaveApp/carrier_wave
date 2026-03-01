import SwiftUI

/// Recent spots page showing POTA activators.
struct SpotsListView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .padding()
            } else if let snapshot = spotSnapshot, !snapshot.spots.isEmpty {
                spotsList(snapshot.spots)
            } else if !networkSpots.isEmpty {
                spotsList(networkSpots)
            } else {
                emptyView
            }
        }
        .task { await loadSpots() }
    }

    // MARK: Private

    @State private var spotSnapshot: WatchSpotSnapshot?
    @State private var networkSpots: [WatchSpot] = []
    @State private var isLoading = false

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Spots")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Check network connection")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func spotsList(_ spots: [WatchSpot]) -> some View {
        List(spots) { spot in
            spotRow(spot)
        }
        .listStyle(.plain)
    }

    private func spotRow(_ spot: WatchSpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spot.callsign)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text(timeAgo(spot.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(ageColor(spot.timestamp))
            }

            HStack(spacing: 4) {
                bandBadge(spot.band)

                Text(String(format: "%.1f", spot.frequencyMHz * 1_000))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                if let parkRef = spot.parkRef {
                    Text(parkRef)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                } else if let snr = spot.snr {
                    Text("\(snr) dB")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func bandBadge(_ band: String) -> some View {
        Text(band)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func loadSpots() async {
        // Try App Group first (fast)
        if let cached = SharedDataReader.readSpots(), !cached.spots.isEmpty {
            spotSnapshot = cached
            return
        }

        // Fetch directly from POTA API
        isLoading = true
        networkSpots = await WatchNetworkService.fetchPOTASpots()
        isLoading = false
    }

    // MARK: - Helpers

    private func timeAgo(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds / 3_600))h"
    }

    private func ageColor(_ date: Date) -> Color {
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<120: return .green
        case ..<600: return .blue
        case ..<1_800: return .orange
        default: return .secondary
        }
    }
}
