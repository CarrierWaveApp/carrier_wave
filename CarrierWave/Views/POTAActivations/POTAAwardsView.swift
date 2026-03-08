// POTA Activator Awards View
//
// Displays POTA activator award progress with tier tracking for 8 award categories.
// Loads park QSOs via FetchDescriptor in .task (no @Query).

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - POTAAwardsView

struct POTAAwardsView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    var body: some View {
        List {
            if isLoading {
                Section { ProgressView("Loading activations...") }
            } else {
                overviewSection
                tieredAwardsSection
                specialAwardsSection
            }
        }
        .navigationTitle("POTA Awards")
        .task { await loadParkQSOs() }
    }

    // MARK: Private

    @State private var allParkQSOs: [QSO] = []
    @State private var isLoading = true

    private var activations: [POTAActivation] {
        POTAActivation.groupQSOs(allParkQSOs)
    }

    private var progress: POTAAwardsProgress {
        POTAAwardsComputation.compute(
            from: activations, allParkQSOs: allParkQSOs
        )
    }
}

// MARK: - Sections

extension POTAAwardsView {
    @ViewBuilder
    private var overviewSection: some View {
        let prog = progress
        Section("Overview") {
            HStack {
                POTAAwardStatPill(
                    label: "Parks",
                    value: "\(prog.uniqueParksCount)",
                    icon: "tree.fill",
                    color: .green
                )
                POTAAwardStatPill(
                    label: "P2P QSOs",
                    value: "\(prog.parkToParkCount)",
                    icon: "arrow.left.arrow.right",
                    color: .blue
                )
                POTAAwardStatPill(
                    label: "Rover Best",
                    value: "\(prog.roverMaxParks)",
                    icon: "car.fill",
                    color: .orange
                )
            }
        }
    }

    @ViewBuilder
    private var tieredAwardsSection: some View {
        let prog = progress
        Section("Award Progress") {
            uniqueParksRow(prog)
            dxEntitiesRow(prog)
            workedAllStatesRow(prog)
            roverRow(prog)
            repeatOffenderRow(prog)
            parkToParkRow(prog)
        }
    }

    @ViewBuilder
    private var specialAwardsSection: some View {
        let prog = progress
        Section("Special Awards") {
            kiloRow(prog)
            laPortaRow(prog)
            sixPackRow(prog)
        }
    }
}

// MARK: - Tiered Award Rows

extension POTAAwardsView {
    @ViewBuilder
    private func uniqueParksRow(_ prog: POTAAwardsProgress) -> some View {
        let result = POTARules.progress(
            for: prog.uniqueParksCount, category: .uniqueParks
        )
        if let next = result.next {
            POTAAwardProgressRow(
                title: "Unique Parks Activated",
                current: prog.uniqueParksCount,
                target: next.threshold,
                currentTier: result.current?.label,
                nextTier: next.label
            )
        } else {
            POTAAwardCompletedRow(
                title: "Unique Parks Activated",
                value: prog.uniqueParksCount,
                tier: result.current?.label ?? "Max"
            )
        }
    }

    @ViewBuilder
    private func dxEntitiesRow(_ prog: POTAAwardsProgress) -> some View {
        let result = POTARules.progress(
            for: prog.dxEntitiesCount, category: .dxEntities
        )
        if let next = result.next {
            POTAAwardProgressRow(
                title: "DX Entities Activated",
                current: prog.dxEntitiesCount,
                target: next.threshold,
                currentTier: result.current?.label,
                nextTier: next.label
            )
        } else if prog.dxEntitiesCount > 0 {
            POTAAwardCompletedRow(
                title: "DX Entities Activated",
                value: prog.dxEntitiesCount,
                tier: result.current?.label ?? "Max"
            )
        }
    }

    @ViewBuilder
    private func workedAllStatesRow(
        _ prog: POTAAwardsProgress
    ) -> some View {
        let stateCount = prog.statesActivated.count
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activator WAS")
                    .font(.subheadline.weight(.medium))
                Text("Activate a park in all 50 US states")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if stateCount >= 50 {
                Label("Earned", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Text("\(stateCount)/50")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func roverRow(_ prog: POTAAwardsProgress) -> some View {
        let result = POTARules.progress(
            for: prog.roverMaxParks, category: .rover
        )
        if let next = result.next {
            POTAAwardProgressRow(
                title: "Rover (parks in one day)",
                current: prog.roverMaxParks,
                target: next.threshold,
                currentTier: result.current?.label,
                nextTier: next.label
            )
        } else if prog.roverMaxParks > 0 {
            POTAAwardCompletedRow(
                title: "Rover",
                value: prog.roverMaxParks,
                tier: result.current?.label ?? "Lion"
            )
        }
    }

    @ViewBuilder
    private func repeatOffenderRow(_ prog: POTAAwardsProgress) -> some View {
        let result = POTARules.progress(
            for: prog.repeatOffenderMaxCount, category: .repeatOffender
        )
        if let next = result.next {
            POTAAwardProgressRow(
                title: "Repeat Offender (one park)",
                current: prog.repeatOffenderMaxCount,
                target: next.threshold,
                currentTier: result.current?.label,
                nextTier: next.label
            )
        } else if prog.repeatOffenderMaxCount > 0 {
            POTAAwardCompletedRow(
                title: "Repeat Offender",
                value: prog.repeatOffenderMaxCount,
                tier: result.current?.label ?? "Max"
            )
        }
    }

    @ViewBuilder
    private func parkToParkRow(_ prog: POTAAwardsProgress) -> some View {
        let result = POTARules.progress(
            for: prog.parkToParkCount, category: .parkToPark
        )
        if let next = result.next {
            POTAAwardProgressRow(
                title: "Park to Park QSOs",
                current: prog.parkToParkCount,
                target: next.threshold,
                currentTier: result.current?.label,
                nextTier: next.label
            )
        } else if prog.parkToParkCount > 0 {
            POTAAwardCompletedRow(
                title: "Park to Park",
                value: prog.parkToParkCount,
                tier: result.current?.label ?? "Max"
            )
        }
    }
}

// MARK: - Special Award Rows

extension POTAAwardsView {
    private func kiloRow(_ prog: POTAAwardsProgress) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kilo")
                    .font(.subheadline.weight(.medium))
                Text("1,000+ QSOs from a single park")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if prog.kiloParks.isEmpty {
                Text("Not earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(prog.kiloParks.count) park(s)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private func laPortaRow(_ prog: POTAAwardsProgress) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LaPorta N1CC")
                    .font(.subheadline.weight(.medium))
                Text("10 parks on 10 bands")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            binaryBadge(earned: prog.laPortaEarned)
        }
        .padding(.vertical, 4)
    }

    private func sixPackRow(_ prog: POTAAwardsProgress) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Six Pack")
                    .font(.subheadline.weight(.medium))
                Text("10 QSOs on 6m from 6 parks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            binaryBadge(earned: prog.sixPackEarned)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func binaryBadge(earned: Bool) -> some View {
        if earned {
            Label("Earned", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        } else {
            Text("Not earned")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Data Loading

extension POTAAwardsView {
    private static let batchSize = 500

    private func loadParkQSOs() async {
        isLoading = true
        defer { isLoading = false }

        var loadedQSOs: [QSO] = []

        let countDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.parkReference != nil && !$0.isHidden }
        )
        let totalCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        var offset = 0
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
            descriptor.fetchLimit = Self.batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }
            if batch.isEmpty {
                break
            }
            loadedQSOs.append(contentsOf: batch)
            offset += batch.count
        }

        allParkQSOs = loadedQSOs
    }
}

// MARK: - POTAAwardStatPill

private struct POTAAwardStatPill: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - POTAAwardProgressRow

private struct POTAAwardProgressRow: View {
    let title: String
    let current: Int
    let target: Int
    let currentTier: String?
    let nextTier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(current)/\(target)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: min(Double(current) / Double(target), 1.0)
            )
            .tint(current >= target ? .green : .blue)

            HStack {
                if let tier = currentTier {
                    Text(tier)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Text("Next: \(nextTier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - POTAAwardCompletedRow

private struct POTAAwardCompletedRow: View {
    let title: String
    let value: Int
    let tier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(value)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.green)
            }
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(tier)
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
