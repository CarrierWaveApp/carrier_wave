import CarrierWaveCore
import SwiftUI

// MARK: - Computed Properties & Helpers

extension ClusterView {
    // MARK: - Time Formatting

    static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func formatTime(_ date: Date) -> String {
        Self.utcTimeFormatter.string(from: date)
    }

    // MARK: - Computed Spots

    /// Enriched spots from SpotAggregator for the Smart view (includes RBN, cluster, DX web)
    /// Sources relevant to the DX cluster view (cluster spots + RBN skimmer)
    private static let clusterSources: Set<SpotSource> = [.cluster, .rbn]

    var enrichedSmartSpots: [EnrichedSpot] {
        var spots = spotAggregator.spots.filter {
            Self.clusterSources.contains($0.spot.source)
        }

        if selectedBand != "All" {
            spots = spots.filter { $0.spot.band == selectedBand }
        }

        if selectedMode != .all {
            spots = spots.filter { selectedMode.matches(mode: $0.spot.mode) }
        }

        if !selectedContinents.isEmpty {
            spots = spots.filter { selectedContinents.contains($0.region.continent) }
        }
        if !selectedRegions.isEmpty {
            spots = spots.filter { selectedRegions.contains($0.region.group) }
        }

        if !filterText.isEmpty {
            let query = filterText.lowercased()
            spots = spots.filter {
                $0.spot.callsign.lowercased().contains(query)
                    || ($0.spot.spotter?.lowercased().contains(query) ?? false)
                    || ($0.spot.comments?.lowercased().contains(query) ?? false)
                    || ($0.dxccEntity?.lowercased().contains(query) ?? false)
            }
        }

        return spots.sorted { $0.spot.timestamp > $1.spot.timestamp }
    }

    /// Raw cluster spots for live feed mode (chronological, not deduplicated)
    var filteredLiveSpots: [DXClusterSpot] {
        var spots = clusterManager.parsedSpots

        if selectedBand != "All" {
            spots = spots.filter { $0.band == selectedBand }
        }

        if selectedMode != .all {
            spots = spots.filter { selectedMode.matches(mode: $0.parsedMode) }
        }

        if !filterText.isEmpty {
            let query = filterText.lowercased()
            spots = spots.filter {
                $0.callsign.lowercased().contains(query)
                    || $0.spotter.lowercased().contains(query)
                    || $0.comment.lowercased().contains(query)
            }
        }

        return spots
    }

    var selectedSpot: EnrichedSpot? {
        guard let spotID = selectedSpotID else {
            return nil
        }
        return enrichedSmartSpots.first { $0.id == spotID }
    }

    var newestSpotAge: String? {
        let spots = smartAggregated ? enrichedSmartSpots : []
        let liveSpots = smartAggregated ? [] : filteredLiveSpots
        let newest = spots.first?.spot.timestamp ?? liveSpots.first?.timestamp
        guard let timestamp = newest else {
            return nil
        }
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "<1m"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3_600))h"
        }
    }

    var spotCountForMode: Int {
        switch viewMode {
        case .smart:
            smartAggregated ? enrichedSmartSpots.count : filteredLiveSpots.count
        case .allSpots:
            clusterManager.parsedSpots.count
        case .raw:
            clusterManager.scrollback.count
        }
    }

    var hasStatusData: Bool {
        !clusterManager.solarWeather.isEmpty || clusterManager.filterConfig != nil
    }

    var statusColor: Color {
        switch clusterManager.connectionState {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .red
        case .failed: .red
        }
    }

    // MARK: - Actions

    func tuneAndLogButton(for spot: EnrichedSpot) -> some View {
        Button("Tune & Log") {
            Task {
                await radioManager.tuneToSpot(
                    frequencyMHz: spot.spot.frequencyMHz,
                    mode: spot.spot.mode,
                    autoXITEnabled: autoXITEnabled,
                    autoXITOffsetHz: autoXITOffsetHz
                )
            }
        }
    }

    func clusterTuneAndLogButton(for spot: DXClusterSpot) -> some View {
        Button("Tune & Log") {
            Task {
                await radioManager.tuneToSpot(
                    frequencyMHz: spot.frequencyMHz,
                    mode: spot.parsedMode,
                    autoXITEnabled: autoXITEnabled,
                    autoXITOffsetHz: autoXITOffsetHz
                )
            }
        }
    }
}
