import CarrierWaveCore
import SwiftUI

// MARK: - SyncCard

/// Unified card showing services (idle) and sync progress (syncing).
/// Replaces the separate SyncProgressCard + ServiceListView.
struct SyncCard: View {
    // MARK: Internal

    @ObservedObject var syncService: SyncService

    let services: [ServiceInfo]
    let onServiceTap: (ServiceIdentifier) -> Void
    let onSync: () async -> Void
    let onDownloadOnly: (() async -> Void)?

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

    // MARK: - Idle State

    @ViewBuilder
    private var idleContent: some View {
        idleHeader
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
            Button {
                onServiceTap(service.id)
            } label: {
                ServiceRow(
                    service: service,
                    serviceSyncStates: syncService.serviceSyncStates
                )
            }
            .buttonStyle(.plain)

            if index < services.count - 1 {
                Divider()
                    .padding(.leading, 38)
            }
        }
    }

    private var idleHeader: some View {
        HStack {
            Text("Services")
                .font(.headline)

            Spacer()

            if let lastSync = mostRecentSyncDate {
                Text("Synced \(lastSync, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let onDownloadOnly {
                Button {
                    Task { await onDownloadOnly() }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.body)
                }
                .accessibilityLabel("Download only")
            }

            Button {
                Task { await onSync() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Sync all services")
        }
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

// MARK: - ServiceSyncRow

/// Individual service row within the sync progress card
struct ServiceSyncRow: View {
    // MARK: Internal

    let service: ServiceType
    let phase: ServiceSyncPhase
    let syncProgress: SyncProgress
    /// Pre-existing synced count from before this sync started (for delta context)
    var existingSynced: Int?

    var body: some View {
        HStack(spacing: 8) {
            phaseIcon
                .frame(width: 20, alignment: .center)

            Text(service.displayName)
                .font(.subheadline)

            Spacer()

            phaseDetail
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .waiting:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .downloaded:
            Image(systemName: "checkmark")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        case .uploading:
            ProgressView()
                .controlSize(.small)
        case .uploaded:
            Image(systemName: "checkmark")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var phaseDetail: some View {
        switch phase {
        case .waiting:
            Text("Waiting")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .downloading:
            downloadingDetail
        case let .downloaded(count):
            downloadedDetail(count: count)
        case .uploading:
            Text("Uploading")
                .font(.caption)
                .foregroundStyle(.blue)
        case let .uploaded(count):
            Text("\(count) uploaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .complete(downloaded, uploaded):
            completeDetail(downloaded: downloaded, uploaded: uploaded)
        case let .error(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var downloadingDetail: some View {
        switch service {
        case .pota:
            potaDownloadingDetail
        case .lofi:
            lofiDownloadingDetail
        default:
            Text("Downloading")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private var potaDownloadingDetail: some View {
        let progress = syncProgress
        if progress.potaTotalActivations > 0 {
            HStack(spacing: 6) {
                ProgressView(value: progress.potaProgress ?? 0)
                    .frame(width: 50)
                VStack(alignment: .trailing, spacing: 1) {
                    let label = progress.potaPhase.isEmpty ? "Fetching" : progress.potaPhase
                    Text(
                        "\(label) \(progress.potaProcessedActivations)/"
                            + "\(progress.potaTotalActivations) activations"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    if progress.potaDownloadedQSOs > 0 {
                        Text("\(progress.potaDownloadedQSOs) QSOs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("Downloading")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private var lofiDownloadingDetail: some View {
        let progress = syncProgress
        if let lofiProgress = progress.lofiProgress {
            HStack(spacing: 6) {
                ProgressView(value: lofiProgress)
                    .frame(width: 50)
                Text("\(progress.lofiDownloadedQSOs)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }
        } else {
            Text("Downloading")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func downloadedDetail(count: Int) -> some View {
        if let synced = existingSynced, synced > 0 {
            Text("\(count) new · \(synced) synced")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(count) fetched")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func completeDetail(downloaded: Int, uploaded: Int) -> some View {
        if uploaded > 0 {
            Text("\(downloaded) new, \(uploaded) uploaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let synced = existingSynced, synced > 0 {
            Text("\(downloaded) new · \(synced) synced")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(downloaded) fetched")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
