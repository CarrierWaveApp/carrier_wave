// WWFF Activation Progress View
//
// Displays activation progress toward WWFF award tiers.
// Shows per-reference QSO counts (target: 44) and overall
// activator/hunter award progression.

import SwiftUI

// MARK: - WWFFActivationProgressView

struct WWFFActivationProgressView: View {
    let summaries: [WWFFActivationSummary]

    var body: some View {
        List {
            overviewSection
            awardProgressSection
            activationsSection
        }
        .navigationTitle("WWFF Progress")
    }

    // MARK: - Overview Section

    @ViewBuilder
    private var overviewSection: some View {
        let activated = summaries.filter(\.isActivated).count
        let inProgress = summaries.filter { !$0.isActivated }.count
        let totalPoints = summaries.reduce(0) { $0 + $1.activatorPoints }

        Section("Overview") {
            HStack {
                StatPill(
                    label: "Activated",
                    value: "\(activated)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                StatPill(
                    label: "In Progress",
                    value: "\(inProgress)",
                    icon: "circle.lefthalf.filled",
                    color: .orange
                )
                StatPill(
                    label: "Points",
                    value: "\(totalPoints)",
                    icon: "star.fill",
                    color: .yellow
                )
            }
        }
    }

    // MARK: - Award Progress Section

    @ViewBuilder
    private var awardProgressSection: some View {
        let activatedCount = summaries.filter(\.isActivated).count
        let totalPoints = summaries.reduce(0) { $0 + $1.activatorPoints }
        let refProgress = WWFFRules.progress(
            for: activatedCount,
            category: .activatorReferences
        )
        let pointsProgress = WWFFRules.progress(
            for: totalPoints,
            category: .activatorPoints
        )

        Section("Award Progress") {
            if let next = refProgress.next {
                AwardProgressRow(
                    title: "Activator References",
                    current: activatedCount,
                    target: next.threshold,
                    currentTier: refProgress.current?.label,
                    nextTier: next.label
                )
            }

            if let next = pointsProgress.next {
                AwardProgressRow(
                    title: "Activator Points",
                    current: totalPoints,
                    target: next.threshold,
                    currentTier: pointsProgress.current?.label,
                    nextTier: next.label
                )
            }
        }
    }

    // MARK: - Activations Section

    @ViewBuilder
    private var activationsSection: some View {
        let sorted = summaries.sorted { lhs, rhs in
            if lhs.isActivated != rhs.isActivated {
                return !lhs.isActivated // Show in-progress first
            }
            return lhs.reference < rhs.reference
        }

        Section("References (\(summaries.count))") {
            ForEach(sorted) { summary in
                ActivationSummaryRow(summary: summary)
            }
        }
    }
}

// MARK: - StatPill

private struct StatPill: View {
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

// MARK: - AwardProgressRow

private struct AwardProgressRow: View {
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

            ProgressView(value: min(Double(current) / Double(target), 1.0))
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

// MARK: - ActivationSummaryRow

private struct ActivationSummaryRow: View {
    let summary: WWFFActivationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.reference)
                    .font(.subheadline.monospaced().weight(.medium))

                if summary.isActivated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                Spacer()

                Text(summary.progressLabel)
                    .font(.caption)
                    .foregroundStyle(summary.isActivated ? .green : .secondary)
            }

            ProgressView(value: min(summary.progress, 1.0))
                .tint(summary.isActivated ? .green : .orange)

            HStack {
                if summary.visitCount > 1 {
                    Label(
                        "\(summary.visitCount) visits",
                        systemImage: "calendar"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if summary.activatorPoints > 0 {
                    Label(
                        "\(summary.activatorPoints) pts",
                        systemImage: "star.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                }

                Spacer()

                Text(summary.uniqueBands.sorted().joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
