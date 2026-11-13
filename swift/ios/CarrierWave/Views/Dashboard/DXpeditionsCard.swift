import CarrierWaveCore
import SwiftUI

// MARK: - DXpeditionsCard

/// Dashboard card showing active and upcoming DXpeditions from Ham365.net.
/// ON AIR expeditions are enriched with live RBN spot data showing frequencies and modes.
struct DXpeditionsCard: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if displayedExpeditions.isEmpty {
                emptyState
            } else {
                expeditionRows
                seeAllLink
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await loadExpeditions()
        }
    }

    // MARK: Private

    private struct ExpeditionPartitions {
        var onAir: [Ham365DXpedition] = []
        var activeToday: [Ham365DXpedition] = []
        var upcoming: [Ham365DXpedition] = []
    }

    @State private var expeditions: [Ham365DXpedition] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// RBN spots keyed by DXpedition callsign (only populated for ON AIR expeditions)
    @State private var onAirSpots: [String: [RBNSpot]] = [:]

    private let client = Ham365Client()
    private let rbnClient = RBNClient()

    private var partitions: ExpeditionPartitions {
        var result = ExpeditionPartitions()
        for exp in expeditions {
            if exp.isOnAir {
                result.onAir.append(exp)
            } else if exp.isActiveToday {
                result.activeToday.append(exp)
            } else if !exp.activeDays.isEmpty {
                result.upcoming.append(exp)
            }
        }
        return result
    }

    /// Show on-air first, then active today, up to 5 entries.
    private var displayedExpeditions: [Ham365DXpedition] {
        let parts = partitions
        return Array((parts.onAir + parts.activeToday + parts.upcoming).prefix(5))
    }

    private var daysInMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now) else {
            return 31
        }
        return range.count
    }

    private var header: some View {
        HStack {
            Image(systemName: "globe.americas")
                .foregroundStyle(.orange)
            Text("DXpeditions")
                .font(.headline)
            let onAirCount = partitions.onAir.count
            if onAirCount > 0 {
                Text("\(onAirCount) on air")
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
        Text("No active DXpeditions this month")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var expeditionRows: some View {
        VStack(spacing: 8) {
            ForEach(displayedExpeditions) { expedition in
                expeditionRow(expedition)
            }
        }
    }

    private var seeAllLink: some View {
        NavigationLink {
            DXpeditionsView(isInNavigationContext: true)
        } label: {
            HStack {
                Spacer()
                Text("See All DXpeditions")
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.blue)
        }
        .padding(.top, 4)
    }

    private func errorState(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                Task { await loadExpeditions() }
            }
            .font(.caption)
        }
    }

    private func expeditionRow(
        _ expedition: Ham365DXpedition
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(expedition.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())

                Text(expedition.entity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if expedition.isOnAir {
                    Text("ON AIR")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green, in: RoundedRectangle(cornerRadius: 3))
                } else if expedition.isActiveToday {
                    Text("ACTIVE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 3))
                } else {
                    Text(expedition.dateRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if expedition.isOnAir, let spots = onAirSpots[expedition.callsign], !spots.isEmpty {
                spotSummaryRow(spots)
            }
        }
    }

    /// Compact band/mode pills showing where an ON AIR DXpedition is active.
    private func spotSummaryRow(_ spots: [RBNSpot]) -> some View {
        let grouped = DXpeditionSpotGrouper.group(spots)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(grouped, id: \.label) { entry in
                    Text(entry.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Color.green.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                }
            }
        }
    }

    private func loadExpeditions() async {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        do {
            expeditions = try await client.fetchDXpeditions(
                month: month, year: year
            )
            await fetchOnAirSpots()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetch RBN spots for each ON AIR DXpedition, searching all callsign variants.
    private func fetchOnAirSpots() async {
        let onAir = expeditions.filter(\.isOnAir)
        guard !onAir.isEmpty else {
            return
        }

        var spotsByCall: [String: [RBNSpot]] = [:]
        await withTaskGroup(of: (String, [RBNSpot]).self) { group in
            for expedition in onAir {
                group.addTask { [rbnClient] in
                    let spots = await (try? rbnClient.spots(
                        forVariants: expedition.searchCallsigns,
                        hours: 1, limit: 20
                    )) ?? []
                    return (expedition.callsign, spots)
                }
            }
            for await (callsign, spots) in group {
                spotsByCall[callsign] = spots
            }
        }
        onAirSpots = spotsByCall
    }
}
