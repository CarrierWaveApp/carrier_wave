// WAS 250 Award Section
//
// ARRL America 250 WAS award progress — work all 50 US states in 2026.
// Triple Play endorsement for CW, Phone, and Digital on all 50.

import SwiftUI

// MARK: - WAS250Section

struct WAS250Section: View {
    let progress: WAS250Progress

    var body: some View {
        Section {
            overallRow
            triplePlayRow
            stateGridView
        } header: {
            Label("America 250 WAS", systemImage: "flag.fill")
        } footer: {
            Text("Work all 50 US states in 2026. Confirmed via LoTW.")
                .font(.caption2)
        }
    }
}

// MARK: - Subviews

extension WAS250Section {
    private var overallRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("States Worked")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if progress.statesWorked.count >= 50 {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text("\(progress.statesWorked.count)/50")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(
                value: Double(progress.statesWorked.count) / 50.0
            )
            .tint(progress.statesWorked.count >= 50 ? .green : .blue)
        }
        .padding(.vertical, 4)
        .was250InfoMenu(
            methodology: Self.statesWorkedMethodology,
            pipeline: statesWorkedPipeline,
            value: progress.statesWorked.count
        )
    }

    private var triplePlayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Triple Play")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 12) {
                modeProgress(
                    label: "CW",
                    count: progress.cwStates.count,
                    color: .orange
                )
                modeProgress(
                    label: "Phone",
                    count: progress.phoneStates.count,
                    color: .blue
                )
                modeProgress(
                    label: "Digital",
                    count: progress.digitalStates.count,
                    color: .purple
                )
            }

            if progress.triplePlayComplete {
                Label(
                    "Triple Play Complete",
                    systemImage: "star.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
        .was250InfoMenu(
            methodology: Self.triplePlayMethodology,
            pipeline: triplePlayPipeline,
            value: progress.statesWorked.count
        )
    }

    private var statesWorkedPipeline: [StatFilterStage] {
        var stages: [StatFilterStage] = []
        stages.append(StatFilterStage(
            "QSOs in 2026 with a state field",
            count: progress.totalQSOs2026
        ))
        if progress.metadataExcluded > 0 {
            stages.append(StatFilterStage(
                "After excluding metadata entries",
                count: progress.totalQSOs2026 - progress.metadataExcluded
            ))
        }
        if progress.withStateField != progress.withValidState {
            stages.append(StatFilterStage(
                "QSOs with a valid US state",
                count: progress.withValidState
            ))
        }
        stages.append(StatFilterStage(
            "Unique US states worked",
            count: progress.statesWorked.count,
            isResult: true
        ))
        return stages
    }

    private var triplePlayPipeline: [StatFilterStage] {
        var stages = statesWorkedPipeline.filter { !$0.isResult }
        stages.append(StatFilterStage(
            "CW states",
            count: progress.cwStates.count,
            isResult: true
        ))
        stages.append(StatFilterStage(
            "Phone states",
            count: progress.phoneStates.count,
            isResult: true
        ))
        stages.append(StatFilterStage(
            "Digital states",
            count: progress.digitalStates.count,
            isResult: true
        ))
        return stages
    }

    private func modeProgress(
        label: String,
        count: Int,
        color: Color
    ) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(count) / 50.0)
                .tint(count >= 50 ? .green : color)
        }
        .frame(maxWidth: .infinity)
    }

    private var stateGridView: some View {
        WAS250StateGrid(
            statesWorked: progress.statesWorked,
            cwStates: progress.cwStates,
            phoneStates: progress.phoneStates,
            digitalStates: progress.digitalStates
        )
    }
}

// MARK: - WAS250StateGrid

/// Compact grid showing all 50 states with worked/unworked status.
private struct WAS250StateGrid: View {
    // MARK: Internal

    let statesWorked: Set<String>
    let cwStates: Set<String>
    let phoneStates: Set<String>
    let digitalStates: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("State Grid")
                .font(.caption.bold())

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(USStates.ordered, id: \.self) { state in
                    stateCell(state)
                }
            }

            legendRow
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 10
    )

    private var legendRow: some View {
        HStack(spacing: 12) {
            legendItem(color: .orange, label: "1 mode")
            legendItem(color: .blue, label: "2 modes")
            legendItem(color: .green, label: "3 modes")
            legendItem(
                color: Color(.systemGray5),
                label: "Not worked"
            )
        }
        .font(.caption2)
    }

    private func stateCell(_ state: String) -> some View {
        let modesWorked = modeCount(for: state)
        return Text(state)
            .font(.caption2.weight(.medium).monospaced())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(cellColor(modesWorked: modesWorked))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(modesWorked > 0 ? .white : .secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func modeCount(for state: String) -> Int {
        var count = 0
        if cwStates.contains(state) {
            count += 1
        }
        if phoneStates.contains(state) {
            count += 1
        }
        if digitalStates.contains(state) {
            count += 1
        }
        return count
    }

    private func cellColor(modesWorked: Int) -> Color {
        switch modesWorked {
        case 3: .green
        case 2: .blue
        case 1: .orange
        default: Color(.systemGray5)
        }
    }
}

// MARK: - WAS250 Methodology

extension WAS250Section {
    static let statesWorkedMethodology = StatMethodology(
        title: "America 250 — States Worked",
        summary: "Work all 50 US states in 2026 on any mode. "
            + "Confirmed via LoTW.",
        included: [
            "QSOs in 2026 (UTC) with a US state in the STATE field",
            "All modes count toward the overall total",
        ],
        excluded: [
            "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
            "Hidden/deleted QSOs",
            "QSOs outside 2026",
            "QSOs without a state field",
            "US territories (only the 50 states count)",
        ],
        edgeCases: [
            "State is taken from the QSO's STATE field, "
                + "not derived from callsign or grid",
            "State abbreviations are normalized "
                + "(e.g. 'Calif' → 'CA')",
            "Confirmation via LoTW is required for the official "
                + "award — this tracker shows worked, not confirmed",
        ],
        methodology: "Filters 2026 QSOs with a valid US state, "
            + "counts unique states"
    )

    static let triplePlayMethodology = StatMethodology(
        title: "America 250 — Triple Play",
        summary: "Work all 50 states on CW, Phone, and Digital "
            + "separately in 2026.",
        included: [
            "CW modes: CW",
            "Phone modes: SSB, USB, LSB, AM, FM, and variants",
            "Digital modes: FT8, FT4, RTTY, PSK31, JS8, "
                + "and other digital modes",
        ],
        excluded: [
            "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
            "Hidden/deleted QSOs",
            "QSOs outside 2026",
            "Modes that don't map to CW, Phone, or Digital",
        ],
        edgeCases: [
            "Each mode family is tracked independently — "
                + "a state worked on CW doesn't count for Phone",
            "Complete means all three mode families have all 50 states",
            "Some modes (e.g. SSTV) may not map to any "
                + "of the three families",
        ],
        methodology: "Groups 2026 QSOs by mode family (CW/Phone/Digital), "
            + "counts unique states per family"
    )
}

// MARK: - WAS250 Info Context Menu

private extension View {
    func was250InfoMenu(
        methodology: StatMethodology,
        pipeline: [StatFilterStage] = [],
        value: Int = 0
    ) -> some View {
        modifier(WAS250InfoModifier(
            methodology: methodology,
            filterPipeline: pipeline,
            value: value
        ))
    }
}

// MARK: - WAS250InfoModifier

private struct WAS250InfoModifier: ViewModifier {
    // MARK: Internal

    let methodology: StatMethodology
    var filterPipeline: [StatFilterStage] = []
    var value: Int = 0

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    showingInfo = true
                } label: {
                    Label("What's This?", systemImage: "info.circle")
                }

                Button {
                    showingReport = true
                } label: {
                    Label(
                        "Report Inaccuracy",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .sheet(isPresented: $showingInfo) {
                StatExplanationSheet(
                    methodology: methodology,
                    filterPipeline: filterPipeline
                )
            }
            .sheet(isPresented: $showingReport) {
                ReportInaccuracyView(
                    category: nil,
                    categoryTitle: methodology.title,
                    identifier: nil,
                    computedValue: value
                )
            }
    }

    // MARK: Private

    @State private var showingInfo = false
    @State private var showingReport = false
}
