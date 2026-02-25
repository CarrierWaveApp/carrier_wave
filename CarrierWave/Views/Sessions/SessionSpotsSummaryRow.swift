import SwiftData
import SwiftUI

// MARK: - SessionSpotsSummaryRow

/// Compact expandable spots summary for session list rows.
/// Aggregates recorded spots by region with pills, matching
/// the logger's SpotSummaryView pattern.
struct SessionSpotsSummaryRow: View {
    // MARK: Internal

    let sessionId: UUID

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = useMetricUnits
        VStack(alignment: .leading, spacing: 0) {
            if !spots.isEmpty {
                summaryBanner
                if isExpanded {
                    Divider()
                    expandedContent
                }
            }
        }
        .task { await loadSpots() }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @AppStorage("useMetricUnits") private var useMetricUnits = false
    @State private var spots: [SessionSpot] = []
    @State private var isExpanded = false
}

// MARK: - Subviews

extension SessionSpotsSummaryRow {
    private var summaryBanner: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .foregroundStyle(.blue)
                    Text("\(spots.count)")
                        .fontWeight(.semibold)
                }

                regionPills

                Spacer()

                if let range = distanceRange {
                    Text(range)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(spots.count) spot\(spots.count == 1 ? "" : "s"), "
                + "tap to \(isExpanded ? "collapse" : "expand")"
        )
    }

    /// Region pills using ViewThatFits for adaptive layout.
    /// Data is snapshotted before ViewThatFits to avoid background-thread access.
    private var regionPills: some View {
        let regions = spotsGroupedByRegion
        return ViewThatFits(in: .horizontal) {
            regionPillRow(regions, max: 4)
            regionPillRow(regions, max: 3)
            regionPillRow(regions, max: 2)
        }
    }

    private func regionPillRow(
        _ regions: [(region: SpotRegion, count: Int)],
        max limit: Int
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(regions.prefix(limit), id: \.region) { item in
                HStack(spacing: 2) {
                    Text(item.region.shortName)
                        .font(.caption2)
                        .fontWeight(.medium)
                    Text("\(item.count)")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if regions.count > limit {
                Text("+\(regions.count - limit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(spots.prefix(10))) { spot in
                SessionSpotRow(spot: spot, isPOTAHighlight: spot.isPOTA)
                    .padding(.vertical, 2)
            }
            if spots.count > 10 {
                Text("+\(spots.count - 10) more spots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Data

extension SessionSpotsSummaryRow {
    private var spotsGroupedByRegion: [(region: SpotRegion, count: Int)] {
        Dictionary(grouping: spots, by: \.spotRegion)
            .map { (region: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var distanceRange: String? {
        let distances = spots.compactMap(\.distanceMeters)
        guard let minD = distances.min(), let maxD = distances.max() else {
            return nil
        }
        return UnitFormatter.distanceRange(minMeters: minD, maxMeters: maxD)
    }

    /// Load spots using FetchDescriptor (no @Query per performance rules)
    private func loadSpots() async {
        let sid = sessionId
        let predicate = #Predicate<SessionSpot> { spot in
            spot.loggingSessionId == sid
        }
        var descriptor = FetchDescriptor<SessionSpot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        spots = (try? modelContext.fetch(descriptor)) ?? []
    }
}
