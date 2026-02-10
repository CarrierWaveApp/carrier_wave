import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SpotSortOrder

/// How to sort the spot list
enum SpotSortOrder: String, CaseIterable {
    case recent = "Recent"
    case frequency = "Frequency"
}

// MARK: - ActivityLogSpotsList

/// Spot list for the hunter workflow. Shows POTA + RBN spots with
/// worked-before badges, filtering, and sort options.
struct ActivityLogSpotsList: View {
    // MARK: Internal

    let spots: [EnrichedSpot]
    @Binding var filters: SpotFilters

    let maxAgeMinutes: Int
    let proximityRadiusMiles: Int
    let workedBeforeCache: WorkedBeforeCache
    let manager: ActivityLogManager
    let container: ModelContainer
    let onShowFilterSheet: () -> Void
    let onSpotLogged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            spotsHeader
            filterChips
            sortPicker

            if sortedSpots.isEmpty {
                emptyState
            } else {
                spotContent
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $selectedSpot) { spot in
            SpotLogSheet(
                spot: spot,
                manager: manager
            ) {
                Task {
                    await workedBeforeCache.recordQSO(
                        callsign: spot.spot.callsign,
                        band: spot.spot.band
                    )
                }
                onSpotLogged()
            }
        }
        .task {
            await loadWorkedBefore()
        }
    }

    // MARK: Private

    private static let visibleLimit = 50

    @State private var selectedSpot: EnrichedSpot?
    @State private var workedResults: [String: WorkedBeforeResult] = [:]
    @State private var sortOrder: SpotSortOrder = .recent
    @State private var showAll = false

    private var filteredSpots: [EnrichedSpot] {
        filters.apply(
            to: spots,
            workedResults: workedResults,
            maxAgeMinutes: maxAgeMinutes,
            proximityRadiusMiles: proximityRadiusMiles
        )
    }

    /// Dedup by callsign+band, preferring POTA over RBN and newest timestamp
    private var dedupedSpots: [EnrichedSpot] {
        var best: [String: EnrichedSpot] = [:]
        for spot in filteredSpots {
            let key = "\(spot.spot.callsign.uppercased())|\(spot.spot.band)"
            if let existing = best[key] {
                let preferNew = spot.spot.source == .pota && existing.spot.source != .pota
                    || spot.spot.source == existing.spot.source
                    && spot.spot.timestamp > existing.spot.timestamp
                if preferNew {
                    best[key] = spot
                }
            } else {
                best[key] = spot
            }
        }
        return Array(best.values)
    }

    private var sortedSpots: [EnrichedSpot] {
        switch sortOrder {
        case .recent:
            dedupedSpots.sorted { $0.spot.timestamp > $1.spot.timestamp }
        case .frequency:
            dedupedSpots.sorted { $0.spot.frequencyKHz < $1.spot.frequencyKHz }
        }
    }

    // MARK: - Header & controls

    private var spotsHeader: some View {
        HStack {
            Text("Spots")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(sortedSpots.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            filterButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var filterButton: some View {
        Button {
            onShowFilterSheet()
        } label: {
            Image(systemName: filters.hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .font(.subheadline)
                .foregroundStyle(filters.hasActiveFilters ? .blue : .secondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(
            filters.hasActiveFilters ? "Filters active, show filter options" : "Filter spots"
        )
    }

    private var filterChips: some View {
        SpotFilterBar(filters: $filters)
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sortOrder) {
            ForEach(SpotSortOrder.allCases, id: \.self) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No spots yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Spots from POTA and RBN refresh automatically every 45 seconds")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var spotContent: some View {
        let visible = showAll
            ? sortedSpots
            : Array(sortedSpots.prefix(Self.visibleLimit))
        let hasMore = !showAll && sortedSpots.count > Self.visibleLimit

        return LazyVStack(spacing: 0) {
            spotRows(visible)
            if hasMore {
                Button {
                    showAll = true
                } label: {
                    Text("Show \(sortedSpots.count - Self.visibleLimit) More")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Spot rows

    private func spotRows(_ rowSpots: [EnrichedSpot]) -> some View {
        ForEach(rowSpots) { spot in
            ActivityLogSpotRow(
                spot: spot,
                workedResult: workedResults[spot.spot.callsign.uppercased()]
                    ?? .notWorked,
                onTap: { selectedSpot = spot }
            )

            if spot.id != rowSpots.last?.id {
                Divider()
                    .padding(.leading, 92)
            }
        }
    }

    private func loadWorkedBefore() async {
        let callsigns = spots.map(\.spot.callsign)
        await workedBeforeCache.checkCallsigns(callsigns, container: container)

        var results: [String: WorkedBeforeResult] = [:]
        for spot in spots {
            let key = spot.spot.callsign.uppercased()
            results[key] = await workedBeforeCache.result(
                for: spot.spot.callsign,
                band: spot.spot.band
            )
        }
        workedResults = results
    }
}

// MARK: - EnrichedSpot + Equatable

extension EnrichedSpot: Equatable {
    static func == (lhs: EnrichedSpot, rhs: EnrichedSpot) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - EnrichedSpot + Hashable

extension EnrichedSpot: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
