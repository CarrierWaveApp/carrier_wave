// Spot Summary View
//
// Compact summary display of RBN/POTA spots showing
// region breakdown, distance range, and spot counts.

import SwiftUI

// MARK: - SpotSummaryView

/// Compact banner showing spot monitoring summary
struct SpotSummaryView: View {
    // MARK: Internal

    @Bindable var monitoringService: SpotMonitoringService

    var body: some View {
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        if monitoringService.isMonitoring, summary.totalCount > 0 {
            VStack(spacing: 0) {
                summaryBanner
                    .onTapGesture {
                        if UIAccessibility.isReduceMotionEnabled {
                            isExpanded.toggle()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }
                    }

                if isExpanded {
                    Divider()
                    expandedContent
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Private

    /// Whether to show detailed spot list
    @State private var isExpanded = false

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var summary: SpotSummary {
        monitoringService.summary
    }

    // MARK: - Summary Banner

    private var summaryBanner: some View {
        HStack(spacing: 12) {
            // Spot icon with count
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .foregroundStyle(.blue)
                Text("\(summary.totalCount)")
                    .fontWeight(.semibold)
            }

            if summary.totalCount > 0 {
                // Region pills
                regionPills

                Spacer()

                // Distance range
                if let range = summary.distanceRange(useMetric: UnitFormatter.useMetric) {
                    Text(range)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No spots yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Expand indicator
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var regionPills: some View {
        // Snapshot region data into local let — RegionPillRowContent is a
        // standalone struct so ForEach closures don't inherit @MainActor
        // isolation from SpotSummaryView.
        // Previously used ViewThatFits, but combined with .fixedSize() it
        // caused deep layout recursion and watchdog timeouts.
        let regions = summary.regionsWithSpots
        return RegionPillRowContent(regions: regions, max: 4)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            if let error = monitoringService.lastError {
                errorRow(error)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(summary.spots.prefix(20)) { enrichedSpot in
                        spotRow(enrichedSpot)
                        if enrichedSpot.id != summary.spots.prefix(20).last?.id {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }

                    if summary.spots.count > 20 {
                        Text("\(summary.spots.count - 20) more spots...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func spotRow(_ enrichedSpot: EnrichedSpot) -> some View {
        let spot = enrichedSpot.spot
        return HStack(spacing: 8) {
            // Region indicator
            Text(enrichedSpot.region.shortName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(regionColor(enrichedSpot.region))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Spotter callsign
            if let spotter = spot.spotter {
                Text(spotter)
                    .font(.system(.caption, design: .monospaced))
            }

            Spacer()

            // SNR for RBN spots
            if let snr = spot.snr {
                Text("\(snr) dB")
                    .font(.caption2)
                    .foregroundStyle(snrColor(snr))
            }

            // Distance
            if let distance = enrichedSpot.formattedDistance(useMetric: UnitFormatter.useMetric) {
                Text(distance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Time ago
            Text(spot.timeAgo)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func regionColor(_ region: SpotRegion) -> Color {
        switch region {
        case .neUS,
             .seUS,
             .mwUS,
             .swUS,
             .nwUS:
            .blue
        case .canada:
            .red
        case .mexico,
             .caribbean,
             .southAmerica:
            .orange
        case .europe:
            .purple
        case .asia:
            .pink
        case .oceania:
            .teal
        case .africa:
            .brown
        case .other:
            .gray
        }
    }

    private func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: .green
        case 15...: .blue
        case 5...: .orange
        default: .red
        }
    }
}

// MARK: - RegionPillRowContent

/// Standalone struct for region pills.
/// Kept as a separate struct (not a method on SpotSummaryView) so ForEach
/// closures don't inherit @MainActor isolation from the parent.
private struct RegionPillRowContent: View {
    let regions: [(region: SpotRegion, count: Int)]
    let max: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(regions.prefix(max), id: \.region) { item in
                RegionPill(region: item.region, count: item.count)
            }

            if regions.count > max {
                Text("+\(regions.count - max)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }
}

// MARK: - RegionPill

/// Small pill showing region abbreviation and count
private struct RegionPill: View {
    let region: SpotRegion
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Text(region.shortName)
                .font(.caption2)
                .fontWeight(.medium)
            Text("\(count)")
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    let service = SpotMonitoringService()
    return VStack {
        SpotSummaryView(monitoringService: service)
        Spacer()
    }
    .padding()
}
