import CarrierWaveCore
import SwiftUI

// MARK: - Smart Spot Table (Enriched with RBN + Cluster + DX Web)

extension ClusterView {
    var smartSpotTableView: some View {
        Group {
            if enrichedSmartSpots.isEmpty {
                emptySmartView
            } else {
                enrichedSpotTable
            }
        }
    }

    // MARK: Private

    private var emptySmartView: some View {
        ContentUnavailableView {
            Label("No Spots", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            if spotAggregator.spots.isEmpty {
                Text("Connect to a cluster or wait for RBN spots")
            } else {
                Text("No spots match the current filters")
            }
        }
    }

    private var enrichedSpotTable: some View {
        Table(of: EnrichedSpot.self, selection: $selectedSpotID) {
            TableColumn("Time") { spot in
                Text(formatTime(spot.spot.timestamp))
                    .font(.caption.monospacedDigit())
            }
            .width(min: 28, ideal: 45)

            TableColumn("Callsign") { spot in
                callsignCell(for: spot)
            }
            .width(min: 55, ideal: 100)

            TableColumn("Freq") { spot in
                Text(String(format: "%.1f", spot.spot.frequencyKHz))
                    .monospacedDigit()
            }
            .width(min: 45, ideal: 70)

            TableColumn("Mode") { spot in
                Text(spot.spot.mode)
                    .font(.caption)
            }
            .width(min: 28, ideal: 50)

            TableColumn("Band") { spot in
                Text(spot.spot.band)
                    .font(.caption)
            }
            .width(min: 24, ideal: 40)

            TableColumn("Source") { spot in
                sourceLabel(for: spot)
            }
            .width(min: 30, ideal: 55)

            TableColumn("Distance") { spot in
                if let dist = spot.formattedDistanceAndBearing() {
                    Text(dist)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("\u{2014}")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 45, ideal: 90)

            TableColumn("Spotter") { spot in
                Text(spot.spot.spotter ?? "\u{2014}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 45, ideal: 80)

            TableColumn("Info") { spot in
                Text(spot.spot.comments ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 50, ideal: 120)
        } rows: {
            ForEach(enrichedSmartSpots) { spot in
                TableRow(spot)
                    .contextMenu {
                        tuneAndLogButton(for: spot)
                    }
            }
        }
        .alternatingRowBackgrounds()
    }

    private func callsignCell(for spot: EnrichedSpot) -> some View {
        let isWorked = workedChecker.isWorked(
            callsign: spot.spot.callsign,
            band: spot.spot.band,
            mode: spot.spot.mode
        )

        return HStack(spacing: 4) {
            if spot.neededStatus == .newEntity {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            } else if spot.neededStatus == .newBandSlot {
                Image(systemName: "star")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }

            Text(spot.spot.callsign)
                .fontWeight(.medium)
                .strikethrough(isWorked, color: .secondary)
                .foregroundStyle(isWorked ? .secondary : .primary)

            if isWorked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
            }
        }
    }

    private func sourceLabel(for spot: EnrichedSpot) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(sourceColor(for: spot.spot.source))
                .frame(width: 6, height: 6)
            Text(spot.spot.source.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceColor(for source: SpotSource) -> Color {
        switch source {
        case .rbn: .blue
        case .pota: .green
        case .sota: .orange
        case .wwff: .teal
        case .dxSummit: .purple
        case .dxHeat: .red
        case .dxWatch: .indigo
        case .cluster: .yellow
        }
    }

    // MARK: - Live Feed Table (line-by-line, not deduplicated)

    var liveFeedTableView: some View {
        Group {
            if filteredLiveSpots.isEmpty {
                emptyLiveFeedView
            } else {
                liveFeedTable
            }
        }
    }

    private var emptyLiveFeedView: some View {
        ContentUnavailableView {
            Label("No Spots", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            if clusterManager.parsedSpots.isEmpty {
                Text("Connect to a cluster node to see live spots")
            } else {
                Text("No spots match the current filters")
            }
        }
    }

    private var liveFeedTable: some View {
        Table(of: DXClusterSpot.self) {
            TableColumn("Time") { spot in
                Text(formatTime(spot.timestamp))
                    .font(.caption.monospacedDigit())
            }
            .width(min: 28, ideal: 45)

            TableColumn("Callsign") { spot in
                liveFeedCallsignCell(for: spot)
            }
            .width(min: 55, ideal: 100)

            TableColumn("Freq") { spot in
                Text(String(format: "%.1f", spot.frequencyKHz))
                    .monospacedDigit()
            }
            .width(min: 45, ideal: 70)

            TableColumn("Mode") { spot in
                Text(spot.parsedMode)
                    .font(.caption)
            }
            .width(min: 28, ideal: 50)

            TableColumn("Band") { spot in
                Text(spot.band)
                    .font(.caption)
            }
            .width(min: 24, ideal: 40)

            TableColumn("Speed") { spot in
                if let wpm = spot.cwSpeed {
                    Text("\(wpm) WPM")
                        .font(.caption.monospacedDigit())
                } else {
                    Text("\u{2014}")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 38, ideal: 60)

            TableColumn("Spotter") { spot in
                Text(spot.spotter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 45, ideal: 80)

            TableColumn("Comment") { spot in
                Text(spot.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 50, ideal: 120)
        } rows: {
            ForEach(filteredLiveSpots) { spot in
                TableRow(spot)
                    .contextMenu {
                        clusterTuneAndLogButton(for: spot)
                    }
            }
        }
        .alternatingRowBackgrounds()
    }

    private func liveFeedCallsignCell(for spot: DXClusterSpot) -> some View {
        let isWorked = workedChecker.isWorked(
            callsign: spot.callsign,
            band: spot.band,
            mode: spot.parsedMode
        )

        return Text(spot.callsign)
            .fontWeight(.medium)
            .strikethrough(isWorked, color: .secondary)
            .foregroundStyle(isWorked ? .secondary : .primary)
    }
}
