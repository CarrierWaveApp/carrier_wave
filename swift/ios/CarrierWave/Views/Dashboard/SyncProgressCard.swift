import CarrierWaveData
import SwiftUI

// MARK: - SyncCard

/// Unified card showing services (idle) and sync progress (syncing).
/// Replaces the separate SyncProgressCard + ServiceListView.
struct SyncCard: View {
    // MARK: Internal

    var syncService: SyncService

    let services: [ServiceInfo]
    let onServiceTap: (ServiceIdentifier) -> Void
    let onSync: () async -> Void
    let onShowReport: () -> Void

    // MARK: - Idle State

    var diagnosticStore = UploadDiagnosticStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if syncService.isSyncing {
                syncingContent
            } else {
                idleContent
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: syncService.isSyncing)
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Last sync date — prefer in-memory (current session), fall back to persisted report timestamps
    private var mostRecentSyncDate: Date? {
        syncService.lastSyncDate
            ?? syncService.lastSyncResults.values.map(\.timestamp).max()
    }

    private var sortedSyncServices: [(ServiceType, ServiceSyncPhase)] {
        let displayOrder: [ServiceType] = [.qrz, .pota, .lofi, .hamrs, .lotw, .clublog]
        return displayOrder.compactMap { service in
            guard let phase = syncService.serviceSyncStates[service] else {
                return nil
            }
            return (service, phase)
        }
    }

    private var issueSummaryText: String {
        let actionCount = diagnosticStore.actionRequiredCount
        let retryCount = diagnosticStore.willRetryCount
        var parts: [String] = []
        if actionCount > 0 {
            let qsoText = actionCount == 1 ? "1 needs attention" : "\(actionCount) need attention"
            parts.append(qsoText)
        }
        if retryCount > 0 {
            let retryText = retryCount == 1 ? "1 will retry" : "\(retryCount) will retry"
            parts.append(retryText)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Compact Stat Helpers

    private var totalSynced: Int {
        services.compactMap { info -> Int? in
            guard let stat = info.primaryStat,
                  let number = Int(stat.components(separatedBy: " ").first ?? "")
            else {
                return nil
            }
            return number
        }
        .reduce(0, +)
    }

    private var secondaryStatText: String? {
        var parts: [String] = []

        let totalPending = services.compactMap { info -> Int? in
            guard let stat = info.secondaryStat,
                  stat.contains("pending"),
                  let number = Int(stat.components(separatedBy: " ").first ?? "")
            else {
                return nil
            }
            return number
        }.reduce(0, +)

        if totalPending > 0 {
            parts.append("\(totalPending) pending uploads")
        }

        let totalQSLs = services.compactMap { info -> Int? in
            guard let stat = info.secondaryStat,
                  stat.contains("QSL"),
                  let number = Int(stat.components(separatedBy: " ").first ?? "")
            else {
                return nil
            }
            return number
        }.reduce(0, +)

        if totalQSLs > 0 {
            parts.append("\(totalQSLs) QSL confirmations")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var idleContent: some View {
        compactHeader
            .padding(.horizontal, 16)

        servicePills
            .padding(.horizontal, 16)
            .padding(.top, 4)

        if diagnosticStore.hasIssues {
            uploadIssueBanner
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }

        compactStats
            .padding(.horizontal, 16)
            .padding(.top, 8)

        compactFooter
    }

    // MARK: - Compact Card Components

    private var compactHeader: some View {
        HStack {
            Text("Logbook Services")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()

            Button {
                Task { await onSync() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Sync all services")
        }
    }

    private var servicePills: some View {
        HStack(spacing: 8) {
            ForEach(services, id: \.id) { service in
                HStack(spacing: 5) {
                    Circle()
                        .fill(service.status.color)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(service.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var compactStats: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(totalSynced)")
                    .font(.title)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text("synced")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let secondary = secondaryStatText {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var compactFooter: some View {
        Button {
            onShowReport()
        } label: {
            HStack {
                if let lastSync = mostRecentSyncDate {
                    Text("Synced \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View sync report details")
    }

    // MARK: - Sync Issue Banner

    private var uploadIssueBanner: some View {
        NavigationLink {
            UploadDiagnosticsView(store: diagnosticStore)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 2) {
                    let count = diagnosticStore.diagnostics.count
                    Text(count == 1 ? "1 sync issue" : "\(count) sync issues")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(issueSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Syncing State

    @ViewBuilder
    private var syncingContent: some View {
        syncingHeader
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        ForEach(sortedSyncServices, id: \.0) { service, phase in
            ServiceSyncRow(
                service: service,
                phase: phase,
                syncProgress: syncService.syncProgress,
                existingSynced: existingSyncedCount(for: service)
            )
            .padding(.horizontal, 16)
        }

        if syncService.syncPhase == .processing {
            processingRow
                .padding(.horizontal, 16)
        }
    }

    private var syncingHeader: some View {
        HStack(spacing: 8) {
            Text("Syncing...")
                .font(.headline)

            ProgressView()
                .controlSize(.small)

            Spacer()
        }
    }

    @ViewBuilder
    private var processingRow: some View {
        let progress = syncService.syncProgress
        HStack(spacing: 8) {
            if let processingProgress = progress.processingProgress {
                ProgressView(value: processingProgress)
                    .frame(maxWidth: 80)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text("Processing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !progress.processingPhase.isEmpty {
                Text(progress.processingPhase)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }

    /// Look up the existing synced count for a service from the idle services list.
    /// Returns the numeric prefix from primaryStat (e.g., "312 synced" → 312).
    private func existingSyncedCount(for serviceType: ServiceType) -> Int? {
        guard let info = services.first(where: { $0.serviceType == serviceType }),
              let stat = info.primaryStat,
              let number = Int(stat.components(separatedBy: " ").first ?? "")
        else {
            return nil
        }
        return number
    }
}
