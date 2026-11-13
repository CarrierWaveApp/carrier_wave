// Needs Dashboard Card
//
// Dashboard card showing needs currently on the air.
// Tapping navigates to the Activity Log with needs filter active.

import CarrierWaveData
import SwiftUI

// MARK: - NeedsDashboardCard

struct NeedsDashboardCard: View {
    // MARK: Internal

    let summary: NeedsOnAirSummary
    let dxccProgress: DXCCNeeds
    let wasProgress: WASNeeds
    let onNavigateToActivityLog: () -> Void
    let onShowDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            progressSection
            if summary.hasMatches {
                onAirSection
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onShowDetail() }
    }

    // MARK: Private

    private var headerRow: some View {
        HStack {
            Label("Needs", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            ExperimentalBadge(feature: .needs)
            Spacer()
            if summary.hasMatches {
                Button(action: onNavigateToActivityLog) {
                    HStack(spacing: 4) {
                        Text("View Spots")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
    }

    private var progressSection: some View {
        HStack(spacing: 16) {
            dxccProgressPill
            progressPill(
                label: "WAS",
                value: "\(wasProgress.statesWorkedCount)/50",
                detail: wasProgress.isComplete
                    ? "Complete"
                    : "\(wasProgress.statesMissing.count) needed"
            )
        }
    }

    private var dxccProgressPill: some View {
        let tier = dxccProgress.nextTier
        let worked = dxccProgress.entitiesWorkedCount
        let detail = if let tierName = tier.name {
            "\(tier.threshold - worked) to \(tierName)"
        } else {
            "All tiers earned"
        }
        return progressPill(
            label: "DXCC",
            value: "\(worked)/\(tier.threshold)",
            detail: detail
        )
    }

    @ViewBuilder
    private var onAirSection: some View {
        Divider()
        Button(action: onNavigateToActivityLog) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(summary.summaryText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func progressPill(
        label: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospaced())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
