import CarrierWaveCore
import SwiftUI

// MARK: - SyncReconciliationView

/// Shows service-specific reconciliation results
struct SyncReconciliationView: View {
    // MARK: Internal

    let service: ServiceType
    let reconciliation: ReconciliationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reconciliation")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            if service == .pota {
                potaReconciliation
            }

            if service == .qrz, reconciliation.qrzResetCount > 0 {
                reconciliationRow(
                    label: "Presence records reset",
                    value: reconciliation.qrzResetCount,
                    color: .orange
                )
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private var potaReconciliation: some View {
        if reconciliation.potaConfirmed > 0 {
            reconciliationRow(
                label: "Confirmed",
                value: reconciliation.potaConfirmed,
                color: .green
            )
        }
        if reconciliation.potaInProgress > 0 {
            reconciliationRow(
                label: "In progress",
                value: reconciliation.potaInProgress,
                color: .blue
            )
        }
        if reconciliation.potaFailed > 0 {
            reconciliationRow(
                label: "Failed",
                value: reconciliation.potaFailed,
                color: .red
            )
        }
        if reconciliation.potaStale > 0 {
            reconciliationRow(
                label: "Stale (reset)",
                value: reconciliation.potaStale,
                color: .orange
            )
        }
        if reconciliation.potaOrphan > 0 {
            reconciliationRow(
                label: "Orphaned (reset)",
                value: reconciliation.potaOrphan,
                color: .orange
            )
        }
    }

    private func reconciliationRow(
        label: String, value: Int, color: Color
    ) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
            Spacer()
            Text("\(value)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - SyncWarningBanner

/// Warning banner for sync issues (skipped QSOs, failures)
struct SyncWarningBanner: View {
    // MARK: Lifecycle

    init(message: String, icon: String = "exclamationmark.triangle.fill") {
        self.message = message
        self.icon = icon
    }

    // MARK: Internal

    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SyncReportSection

/// Complete sync report section for use in ServiceDetailSheet.
/// Shows header, funnel visualization, and optional reconciliation.
struct SyncReportSection: View {
    let report: ServiceSyncReport

    var body: some View {
        Section("Last Sync") {
            SyncReportHeader(report: report)

            if report.status != .error {
                SyncFunnelView(report: report)
            }

            if let reconciliation = report.reconciliation, reconciliation.hasWarnings {
                SyncReconciliationView(
                    service: report.service,
                    reconciliation: reconciliation
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("Report Section - Full") {
    List {
        SyncReportSection(report: ServiceSyncReport(
            service: .pota,
            timestamp: Date().addingTimeInterval(-120),
            status: .warning,
            downloaded: 247,
            skipped: 3,
            created: 5,
            merged: 12,
            uploaded: 8,
            reconciliation: ReconciliationReport(
                qrzResetCount: 0,
                potaConfirmed: 15,
                potaFailed: 2,
                potaStale: 1,
                potaOrphan: 0,
                potaInProgress: 3
            )
        ))
    }
}

#Preview("Report Section - Download Only") {
    List {
        SyncReportSection(report: ServiceSyncReport(
            service: .lofi,
            timestamp: Date().addingTimeInterval(-60),
            status: .success,
            downloaded: 100,
            skipped: 0,
            created: 2,
            merged: 5,
            uploaded: 0,
            reconciliation: nil
        ))
    }
}

#Preview("Report Section - No Changes") {
    List {
        SyncReportSection(report: ServiceSyncReport(
            service: .qrz,
            timestamp: Date().addingTimeInterval(-300),
            status: .success,
            downloaded: 500,
            skipped: 0,
            created: 0,
            merged: 0,
            uploaded: 0,
            reconciliation: nil
        ))
    }
}
