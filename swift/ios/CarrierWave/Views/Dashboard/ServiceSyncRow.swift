import CarrierWaveData
import SwiftUI

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
