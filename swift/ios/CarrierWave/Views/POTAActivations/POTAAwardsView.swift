// POTA Activator Awards View
//
// Displays POTA activator award progress with tier tracking for 8 award categories.
// All computation runs on a background actor to avoid blocking the main thread.

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
            } else if let progress {
                overviewSection(progress)
                if let was250Progress {
                    WAS250Section(progress: was250Progress)
                }
                tieredAwardsSection(progress)
                specialAwardsSection(progress)
            }
        }
        .navigationTitle("Awards & Certificates")
        .environment(\.potaAwardsProgress, progress)
        .task { await loadAwards() }
    }

    // MARK: Private

    @State private var progress: POTAAwardsProgress?
    @State private var was250Progress: WAS250Progress?
    @State private var isLoading = true

    private let computeActor = POTAAwardsActor()
}

// MARK: - Sections

extension POTAAwardsView {
    private func overviewSection(
        _ prog: POTAAwardsProgress
    ) -> some View {
        Section("Overview") {
            POTAAwardStatPill(
                label: "Parks",
                value: "\(prog.uniqueParksCount)",
                icon: "tree.fill",
                color: .green,
                category: .uniqueParks,
                numericValue: prog.uniqueParksCount
            )
            POTAAwardStatPill(
                label: "P2P QSOs",
                value: "\(prog.parkToParkCount)",
                icon: "arrow.left.arrow.right",
                color: .blue,
                category: .parkToPark,
                numericValue: prog.parkToParkCount
            )
            POTAAwardStatPill(
                label: "Rover Best",
                value: "\(prog.roverMaxParks)",
                icon: "car.fill",
                color: .orange,
                category: .rover,
                numericValue: prog.roverMaxParks
            )
        }
    }

    private func tieredAwardsSection(
        _ prog: POTAAwardsProgress
    ) -> some View {
        Section("Award Progress") {
            uniqueParksRow(prog)
            dxEntitiesRow(prog)
            workedAllStatesRow(prog)
            roverRow(prog)
            repeatOffenderRow(prog)
            parkToParkRow(prog)
        }
    }

    private func specialAwardsSection(
        _ prog: POTAAwardsProgress
    ) -> some View {
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
                nextTier: next.label,
                category: .uniqueParks
            )
        } else {
            POTAAwardCompletedRow(
                title: "Unique Parks Activated",
                value: prog.uniqueParksCount,
                tier: result.current?.label ?? "Max",
                category: .uniqueParks
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
                nextTier: next.label,
                category: .dxEntities
            )
        } else if prog.dxEntitiesCount > 0 {
            POTAAwardCompletedRow(
                title: "DX Entities Activated",
                value: prog.dxEntitiesCount,
                tier: result.current?.label ?? "Max",
                category: .dxEntities
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
        .potaAwardInfoMenu(category: .workedAllStates)
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
                nextTier: next.label,
                category: .rover
            )
        } else if prog.roverMaxParks > 0 {
            POTAAwardCompletedRow(
                title: "Rover",
                value: prog.roverMaxParks,
                tier: result.current?.label ?? "Lion",
                category: .rover
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
                nextTier: next.label,
                category: .repeatOffender
            )
        } else if prog.repeatOffenderMaxCount > 0 {
            POTAAwardCompletedRow(
                title: "Repeat Offender",
                value: prog.repeatOffenderMaxCount,
                tier: result.current?.label ?? "Max",
                category: .repeatOffender
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
                nextTier: next.label,
                category: .parkToPark
            )
        } else if prog.parkToParkCount > 0 {
            POTAAwardCompletedRow(
                title: "Park to Park",
                value: prog.parkToParkCount,
                tier: result.current?.label ?? "Max",
                category: .parkToPark
            )
        }
    }
}

// MARK: - Special Award Rows

extension POTAAwardsView {
    private func kiloRow(_ prog: POTAAwardsProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kilo")
                        .font(.subheadline.weight(.medium))
                    Text("1,000+ QSOs from a single park")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !prog.kiloParks.isEmpty {
                    Text("\(prog.kiloParks.count) park(s)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text("\(prog.bestSingleParkTotal)/1,000")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if prog.kiloParks.isEmpty, prog.bestSingleParkTotal > 0 {
                ProgressView(
                    value: Double(prog.bestSingleParkTotal) / 1_000.0
                )
                .tint(.blue)
            }

            if !prog.kiloParks.isEmpty {
                kiloEarnedList(prog.kiloParks)
            }

            if !prog.nearKiloParks.isEmpty {
                nearKiloList(prog.nearKiloParks)
            }
        }
        .padding(.vertical, 4)
        .potaAwardInfoMenu(
            category: .kilo, value: prog.bestSingleParkTotal
        )
    }

    private func kiloEarnedList(_ parks: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(parks, id: \.self) { ref in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(ref)
                        .font(.caption.monospaced())
                }
            }
        }
    }

    @ViewBuilder
    private func nearKiloList(
        _ parks: [NearKiloPark]
    ) -> some View {
        Divider()
        Text("Approaching Kilo")
            .font(.caption.bold())
            .foregroundStyle(.primary)

        ForEach(parks) { park in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(park.reference)
                        .font(.caption.monospaced())
                    Spacer()
                    Text("\(park.qsoCount)/1,000")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(
                    value: Double(park.qsoCount) / 1_000.0
                )
                .tint(.orange)
            }
        }
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
            if prog.laPortaEarned {
                binaryBadge(earned: true)
            } else {
                Text("\(prog.laPortaQualifyingParks)/10")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .potaAwardInfoMenu(category: .laPorta)
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
        .potaAwardInfoMenu(category: .sixPack)
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
    private func loadAwards() async {
        isLoading = true
        defer { isLoading = false }

        let container = modelContext.container
        do {
            let result = try await computeActor.compute(
                container: container
            )
            progress = result.progress
            was250Progress = result.was250Progress
        } catch is CancellationError {
            // View disappeared, no update needed
        } catch {
            // Silently degrade — show empty state
        }
    }
}
