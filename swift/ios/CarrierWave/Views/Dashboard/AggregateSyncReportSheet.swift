import CarrierWaveData
import SwiftUI

// MARK: - AggregateSyncReportSheet

/// Sheet showing combined sync results across all services.
/// Displays an aggregate funnel with diamond split (new vs enriched)
/// followed by a per-service breakdown table.
struct AggregateSyncReportSheet: View {
    // MARK: Internal

    let reports: [ServiceType: ServiceSyncReport]

    var body: some View {
        NavigationStack {
            List {
                if !sortedReports.isEmpty {
                    aggregateFunnelSection
                    perServiceSection
                } else {
                    noDataSection
                }
            }
            .navigationTitle("Last Sync Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 12

    private var sortedReports: [ServiceSyncReport] {
        reports.values
            .sorted { $0.downloaded > $1.downloaded }
    }

    private var mostRecentTimestamp: Date? {
        reports.values.map(\.timestamp).max()
    }

    private var aggregateReport: ServiceSyncReport {
        let totalDownloaded = sortedReports.reduce(0) { $0 + $1.downloaded }
        let totalSkipped = sortedReports.reduce(0) { $0 + $1.skipped }
        let totalCreated = sortedReports.reduce(0) { $0 + $1.created }
        let totalMerged = sortedReports.reduce(0) { $0 + $1.merged }
        let totalUploaded = sortedReports.reduce(0) { $0 + $1.uploaded }

        let hasError = sortedReports.contains { $0.status == .error }
        let hasWarning = sortedReports.contains { $0.status == .warning }
        let status: SyncReportStatus = if hasError {
            .error
        } else if hasWarning || totalSkipped > 0 {
            .warning
        } else {
            .success
        }

        return ServiceSyncReport(
            service: .qrz, // placeholder — not displayed
            timestamp: mostRecentTimestamp ?? Date(),
            status: status,
            downloaded: totalDownloaded,
            skipped: totalSkipped,
            created: totalCreated,
            merged: totalMerged,
            uploaded: totalUploaded,
            reconciliation: nil
        )
    }

    // MARK: - Sections

    private var aggregateFunnelSection: some View {
        Section {
            if let timestamp = mostRecentTimestamp {
                HStack {
                    Text(timestamp, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("ago")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    SyncStatusBadge(
                        status: aggregateReport.status,
                        badgeSize: badgeSize
                    )
                }
            }

            SyncFunnelView(report: aggregateReport)
        } header: {
            Text("All Services")
        }
    }

    private var perServiceSection: some View {
        Section {
            ForEach(sortedReports, id: \.service) { report in
                ServiceSyncSummaryRow(report: report)
            }
        } header: {
            Text("Per Service")
        }
    }

    private var noDataSection: some View {
        Section {
            Text("No sync data yet. Tap Sync to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ServiceSyncSummaryRow

/// Compact row showing one service's sync results with fetched/enriched/uploaded counts.
private struct ServiceSyncSummaryRow: View {
    // MARK: Internal

    let report: ServiceSyncReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(report.service.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(report.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                syncStatPill(
                    value: report.downloaded,
                    label: "Fetched",
                    color: .blue
                )
                if let qsls = report.qslsApplied {
                    syncStatPill(
                        value: qsls,
                        label: "QSLs",
                        color: .green
                    )
                }
                syncStatPill(
                    value: report.merged,
                    label: "Enriched",
                    color: .teal
                )
                syncStatPill(
                    value: report.uploaded,
                    label: "Uploaded",
                    color: .indigo
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Private

    private var accessibilityText: String {
        var parts = [report.service.displayName, "\(report.downloaded) fetched"]
        if let qsls = report.qslsApplied {
            parts.append("\(qsls) QSLs")
        }
        parts.append("\(report.merged) enriched")
        parts.append("\(report.uploaded) uploaded")
        return parts.joined(separator: ", ")
    }

    private func syncStatPill(
        value: Int,
        label: String,
        color: Color
    ) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(value > 0 ? color : Color(.tertiaryLabel))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Aggregate Report") {
    AggregateSyncReportSheet(reports: [
        .qrz: ServiceSyncReport(
            service: .qrz,
            timestamp: Date().addingTimeInterval(-720),
            status: .success,
            downloaded: 180,
            skipped: 0,
            created: 15,
            merged: 94,
            uploaded: 52,
            reconciliation: nil,
            qslsApplied: 23
        ),
        .pota: ServiceSyncReport(
            service: .pota,
            timestamp: Date().addingTimeInterval(-720),
            status: .success,
            downloaded: 42,
            skipped: 3,
            created: 8,
            merged: 38,
            uploaded: 22,
            reconciliation: nil
        ),
        .lotw: ServiceSyncReport(
            service: .lotw,
            timestamp: Date().addingTimeInterval(-720),
            status: .success,
            downloaded: 25,
            skipped: 0,
            created: 5,
            merged: 15,
            uploaded: 0,
            reconciliation: nil,
            qslsApplied: 18
        ),
    ])
}

#Preview("No Data") {
    AggregateSyncReportSheet(reports: [:])
}
