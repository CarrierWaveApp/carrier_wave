import CarrierWaveCore
import SwiftUI

// MARK: - SyncProgressCard

/// Card showing per-service sync progress during a sync operation
struct SyncProgressCard: View {
    // MARK: Internal

    @ObservedObject var syncService: SyncService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Syncing")
                .font(.headline)

            ForEach(sortedServices, id: \.0) { service, phase in
                ServiceSyncRow(
                    service: service,
                    phase: phase,
                    syncProgress: syncService.syncProgress
                )
            }

            // Processing phase at bottom
            if syncService.syncPhase == .processing {
                processingRow
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    /// Services sorted in display order
    private var sortedServices: [(ServiceType, ServiceSyncPhase)] {
        let displayOrder: [ServiceType] = [.qrz, .pota, .lofi, .hamrs, .lotw, .clublog]
        return displayOrder.compactMap { service in
            guard let phase = syncService.serviceSyncStates[service] else {
                return nil
            }
            return (service, phase)
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
}

// MARK: - ServiceSyncRow

/// Individual service row within the sync progress card
private struct ServiceSyncRow: View {
    // MARK: Internal

    let service: ServiceType
    let phase: ServiceSyncPhase
    let syncProgress: SyncProgress

    var body: some View {
        HStack(spacing: 8) {
            phaseIcon
                .frame(width: 20, alignment: .center)

            Text(service.displayName)
                .font(.subheadline)

            Spacer()

            phaseDetail
        }
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
            Text("\(count) fetched")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                let label = progress.potaPhase.isEmpty ? "Fetching" : progress.potaPhase
                Text("\(label) \(progress.potaProcessedActivations)/\(progress.potaTotalActivations)")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
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

    private func completeDetail(downloaded: Int, uploaded: Int) -> some View {
        Group {
            if uploaded > 0 {
                Text("\(downloaded) fetched, \(uploaded) uploaded")
            } else {
                Text("\(downloaded) fetched")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
