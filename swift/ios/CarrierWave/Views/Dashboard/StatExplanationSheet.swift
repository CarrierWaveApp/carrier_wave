import SwiftUI

// MARK: - StatExplanationSheet

/// Sheet presenting a structured explanation of how a statistic
/// is calculated — what's included, excluded, and edge cases.
/// When a filter pipeline is provided, shows the user's actual
/// numbers at each filter stage.
struct StatExplanationSheet: View {
    // MARK: Internal

    let methodology: StatMethodology
    var filterPipeline: [StatFilterStage] = []

    var body: some View {
        NavigationStack {
            List {
                summarySection
                pipelineSection
                includedSection
                excludedSection
                edgeCasesSection
                methodologySection
            }
            .navigationTitle(methodology.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}

// MARK: - Sections

extension StatExplanationSheet {
    private var summarySection: some View {
        Section {
            Text(methodology.summary)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var pipelineSection: some View {
        if !filterPipeline.isEmpty {
            Section("Your Numbers") {
                ForEach(filterPipeline) { stage in
                    pipelineRow(stage)
                }
            }
        }
    }

    private func pipelineRow(
        _ stage: StatFilterStage
    ) -> some View {
        HStack {
            if stage.isResult {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
            } else {
                Image(
                    systemName: "line.3.horizontal.decrease.circle"
                )
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
            Text(stage.label)
                .font(stage.isResult ? .subheadline.bold() : .subheadline)
            Spacer()
            Text(stage.count.formatted())
                .font(.subheadline.monospacedDigit())
                .fontWeight(stage.isResult ? .bold : .regular)
                .foregroundStyle(
                    stage.isResult ? .primary : .secondary
                )
        }
    }

    private var includedSection: some View {
        Section("Included") {
            ForEach(methodology.included, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .labelStyle(ExplanationLabelStyle(color: .green))
            }
        }
    }

    private var excludedSection: some View {
        Section("Excluded") {
            ForEach(methodology.excluded, id: \.self) { item in
                Label(item, systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .labelStyle(ExplanationLabelStyle(color: .red))
            }
        }
    }

    @ViewBuilder
    private var edgeCasesSection: some View {
        if !methodology.edgeCases.isEmpty {
            Section("Edge Cases") {
                ForEach(methodology.edgeCases, id: \.self) { item in
                    Label(
                        item,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .labelStyle(
                        ExplanationLabelStyle(color: .orange)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var methodologySection: some View {
        if let detail = methodology.methodology {
            Section("How It's Calculated") {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ExplanationLabelStyle

/// Label style that tints the icon while keeping text primary.
private struct ExplanationLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.icon
                .foregroundStyle(color)
                .font(.subheadline)
            configuration.title
        }
    }
}
