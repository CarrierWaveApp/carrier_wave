// POTA Awards Dashboard Card
//
// At-a-glance summary of POTA activator award progress for the dashboard.
// Shows unique parks count and progress toward the next tier.
// All QSO fetching runs on a background actor to avoid blocking the main thread.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - POTAUniqueParksActor

/// Background actor that computes unique activated parks count without
/// blocking the main thread. Fetches lightweight snapshots in batches,
/// groups by (park, UTC date, callsign), and counts parks with ≥10 QSOs.
private actor POTAUniqueParksActor {
    // MARK: Internal

    func computeUniqueParks(
        container: ModelContainer,
        minQSOs: Int
    ) throws -> Int {
        let groupCounts = try fetchActivationGroupCounts(container: container)
        return countUniqueParks(from: groupCounts, minQSOs: minQSOs)
    }

    // MARK: Private

    /// Fetch park QSOs in batches and accumulate activation group counts.
    /// Key format: "PARKREF|CALLSIGN|YYYY-MM-DD" → QSO count per group.
    private func fetchActivationGroupCounts(
        container: ModelContainer
    ) throws -> [String: Int] {
        let batchSize = BoundedDescriptor<QSO>.maxLimit
        var offset = 0
        var groupCounts: [String: Int] = [:]
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate {
                    $0.parkReference != nil && !$0.isHidden
                },
                limit: batchSize,
                offset: offset
            )

            guard let batch = try? context.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }

            for qso in batch {
                guard let parkRef = qso.parkReference,
                      !parkRef.isEmpty,
                      !QSOMode.isMetadata(qso.mode)
                else {
                    continue
                }
                let utcDate = utcCalendar.startOfDay(for: qso.timestamp)
                let dateStr = dateFormatter.string(from: utcDate)
                let callsign = qso.myCallsign.uppercased()
                let key = "\(parkRef.uppercased())|\(callsign)|\(dateStr)"
                groupCounts[key, default: 0] += 1
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }

        return groupCounts
    }

    /// Count unique parks from activation groups with ≥minQSOs QSOs.
    private func countUniqueParks(
        from groupCounts: [String: Int],
        minQSOs: Int
    ) -> Int {
        var parkSet = Set<String>()
        for (key, count) in groupCounts
            where count >= minQSOs
        {
            let parkRef = String(key.prefix(while: { $0 != "|" }))
            let parks = POTAClient.splitParkReferences(parkRef)
            for park in parks {
                parkSet.insert(park.uppercased())
            }
        }
        return parkSet.count
    }
}

// MARK: - POTAAwardsDashboardCard

struct POTAAwardsDashboardCard: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationLink {
            POTAAwardsView()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .task { await computeUniqueParks() }
    }

    // MARK: Private

    @State private var uniqueParksCount: Int = 0
    @State private var hasLoaded = false

    private let computeActor = POTAUniqueParksActor()

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Awards & Certificates", systemImage: "trophy.fill")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if hasLoaded {
                let result = POTARules.progress(
                    for: uniqueParksCount, category: .uniqueParks
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(uniqueParksCount) parks activated")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let tier = result.current {
                            Text(tier.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }

                    if let next = result.next {
                        ProgressView(
                            value: min(
                                Double(uniqueParksCount)
                                    / Double(next.threshold),
                                1.0
                            )
                        )
                        .tint(.blue)

                        Text("Next: \(next.label) (\(next.threshold))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func computeUniqueParks() async {
        let container = modelContext.container
        let minQSOs = POTARules.activationMinQSOs
        do {
            let count = try await computeActor.computeUniqueParks(
                container: container,
                minQSOs: minQSOs
            )
            uniqueParksCount = count
        } catch is CancellationError {
            // Task cancelled (view disappeared), no update needed
        } catch {
            // Silently degrade — show 0 parks
        }
        hasLoaded = true
    }
}
