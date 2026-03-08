// POTA Awards Dashboard Card
//
// At-a-glance summary of POTA activator award progress for the dashboard.
// Shows unique parks count and progress toward the next tier.

import CarrierWaveData
import SwiftData
import SwiftUI

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

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("POTA Awards", systemImage: "trophy.fill")
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
        let countDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate {
                $0.parkReference != nil && !$0.isHidden
            }
        )
        let totalCount = (
            try? modelContext.fetchCount(countDescriptor)
        ) ?? 0

        guard totalCount > 0 else {
            hasLoaded = true
            return
        }

        // Load park QSOs in batches
        var allQSOs: [QSO] = []
        var offset = 0
        let batchSize = 500
        while offset < totalCount {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate {
                    $0.parkReference != nil && !$0.isHidden
                }
            )
            descriptor.sortBy = [
                SortDescriptor(\QSO.timestamp, order: .reverse),
            ]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }
            if batch.isEmpty {
                break
            }
            allQSOs.append(contentsOf: batch)
            offset += batch.count
        }

        let activations = POTAActivation.groupQSOs(allQSOs)
        var parkSet = Set<String>()
        for activation in activations
            where activation.qsoCount >= POTARules.activationMinQSOs
        {
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                parkSet.insert(park.uppercased())
            }
        }

        uniqueParksCount = parkSet.count
        hasLoaded = true
    }
}
