import SwiftData
import SwiftUI

// MARK: - ActivityLogSpotsList

/// Spot list for the hunter workflow. Shows POTA + RBN spots with
/// worked-before badges and tap-to-log.
struct ActivityLogSpotsList: View {
    // MARK: Internal

    let spots: [EnrichedSpot]
    let workedBeforeCache: WorkedBeforeCache
    let manager: ActivityLogManager
    let container: ModelContainer
    let onSpotLogged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            spotsHeader

            if spots.isEmpty {
                emptyState
            } else {
                spotRows
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

    @State private var selectedSpot: EnrichedSpot?
    @State private var workedResults: [String: WorkedBeforeResult] = [:]

    private var spotsHeader: some View {
        HStack {
            Text("Spots")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(spots.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Spots from POTA and RBN will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var spotRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(spots) { spot in
                ActivityLogSpotRow(
                    spot: spot,
                    workedResult: workedResults[spot.spot.callsign.uppercased()]
                        ?? .notWorked,
                    onTap: { selectedSpot = spot }
                )

                if spot.id != spots.last?.id {
                    Divider()
                        .padding(.leading, 92)
                }
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
