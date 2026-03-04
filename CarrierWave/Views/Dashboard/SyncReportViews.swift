import CarrierWaveData
import SwiftUI

// MARK: - SyncReportHeader

/// Shows status badge + relative timestamp for a sync report
struct SyncReportHeader: View {
    // MARK: Internal

    let report: ServiceSyncReport

    var body: some View {
        HStack {
            Text(report.timestamp, style: .relative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            SyncStatusBadge(status: report.status, badgeSize: badgeSize)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 12

    private var headerAccessibilityLabel: String {
        let timeAgo = report.timestamp.formatted(.relative(presentation: .named))
        let statusText = switch report.status {
        case .success:
            "Synced successfully"
        case .warning:
            "Synced with warnings"
        case .error:
            "Sync failed"
        }
        return "\(statusText) \(timeAgo)"
    }
}

// MARK: - SyncStatusBadge

/// Colored status indicator with icon
struct SyncStatusBadge: View {
    // MARK: Internal

    let status: SyncReportStatus
    let badgeSize: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: badgeSize))
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
    }

    // MARK: Private

    private var iconName: String {
        switch status {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var label: String {
        switch status {
        case .success: "OK"
        case .warning: "Attention"
        case .error: "Error"
        }
    }
}

// MARK: - SyncFunnelView

/// Visual funnel showing how QSOs flow through sync stages.
/// Bars narrow at each stage to convey the filtering effect.
struct SyncFunnelView: View {
    // MARK: Internal

    let report: ServiceSyncReport

    var body: some View {
        let stages = buildStages()
        VStack(alignment: .leading, spacing: stageSpacing) {
            ForEach(stages) { stage in
                funnelStage(stage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sync funnel")
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .caption) private var stageSpacing: CGFloat = 4
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var maxNarrowing: CGFloat = 72

    private var changesStage: FunnelStage {
        let changed = report.created + report.merged
        var changeParts: [String] = []
        if report.created > 0 {
            changeParts.append("\(report.created) new")
        }
        if report.merged > 0 {
            changeParts.append("\(report.merged) enriched existing")
        }
        let changeNote = changeParts.isEmpty
            ? nil : changeParts.joined(separator: ", ")
        let changeDesc = changed > 0
            ? "QSOs added or updated in your log after deduplication"
            : "All fetched QSOs already existed — nothing to add or update"

        return FunnelStage(
            label: changed > 0 ? "Changes applied" : "No changes",
            description: changeDesc,
            count: changed,
            proportion: 0.6,
            color: changed > 0 ? .green : Color(.systemGray3),
            icon: changed > 0 ? "plus.circle" : "equal.circle",
            note: changeNote
        )
    }

    private func funnelStage(_ stage: FunnelStage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Colored bar with count + label
            HStack(spacing: 6) {
                Image(systemName: stage.icon)
                    .font(.caption)
                    .foregroundStyle(stage.color)
                    .frame(width: 16)

                Text("\(stage.count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                Text(stage.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: barHeight)
            .background(
                stage.color.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .padding(.trailing, trailingPad(stage.proportion))

            // Explanation of what this stage means
            Text(stage.description)
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.leading, 32)

            // Optional note below the description
            if let note = stage.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(stage.noteColor ?? Color(.tertiaryLabel))
                    .padding(.leading, 32)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.label): \(stage.count). \(stage.description)")
    }

    private func trailingPad(_ proportion: CGFloat) -> CGFloat {
        (1.0 - proportion) * maxNarrowing
    }

    private func buildStages() -> [FunnelStage] {
        var stages: [FunnelStage] = []
        let serviceName = report.service.displayName

        stages.append(FunnelStage(
            label: "Fetched",
            description: "Total QSOs downloaded from \(serviceName)",
            count: report.downloaded,
            proportion: 1.0,
            color: .blue,
            icon: "arrow.down.circle"
        ))

        if report.skipped > 0 {
            stages.append(FunnelStage(
                label: "Passed validation",
                description: "QSOs with all required fields (callsign, date, band)",
                count: report.downloaded - report.skipped,
                proportion: 0.85,
                color: .cyan,
                icon: "checkmark.circle",
                note: "\(report.skipped) skipped (missing required fields)",
                noteColor: .orange
            ))
        }

        stages.append(changesStage)

        if report.uploaded > 0 {
            stages.append(FunnelStage(
                label: "Uploaded",
                description: "QSOs from your log sent back to \(serviceName)",
                count: report.uploaded,
                proportion: 0.4,
                color: .indigo,
                icon: "arrow.up.circle"
            ))
        }

        return stages
    }
}

// MARK: - FunnelStage

private struct FunnelStage: Identifiable {
    let label: String
    let description: String
    let count: Int
    let proportion: CGFloat
    let color: Color
    let icon: String
    var note: String?
    var noteColor: Color?

    var id: String {
        label
    }
}

// MARK: - Previews

#Preview("Funnel - Full Sync") {
    List {
        let report = ServiceSyncReport(
            service: .qrz,
            timestamp: Date().addingTimeInterval(-180),
            status: .success,
            downloaded: 247,
            skipped: 0,
            created: 5,
            merged: 12,
            uploaded: 8,
            reconciliation: nil
        )

        Section("Last Sync") {
            SyncReportHeader(report: report)
            SyncFunnelView(report: report)
        }
    }
}

#Preview("Funnel - With Skipped") {
    List {
        let report = ServiceSyncReport(
            service: .lofi,
            timestamp: Date().addingTimeInterval(-60),
            status: .warning,
            downloaded: 100,
            skipped: 3,
            created: 2,
            merged: 5,
            uploaded: 0,
            reconciliation: nil
        )

        Section("Last Sync") {
            SyncReportHeader(report: report)
            SyncFunnelView(report: report)
        }
    }
}

#Preview("Funnel - No Changes") {
    List {
        let report = ServiceSyncReport(
            service: .qrz,
            timestamp: Date().addingTimeInterval(-300),
            status: .success,
            downloaded: 500,
            skipped: 0,
            created: 0,
            merged: 0,
            uploaded: 0,
            reconciliation: nil
        )

        Section("Last Sync") {
            SyncReportHeader(report: report)
            SyncFunnelView(report: report)
        }
    }
}
