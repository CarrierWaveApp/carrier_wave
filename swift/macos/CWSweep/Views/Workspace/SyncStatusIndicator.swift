import CarrierWaveData
import SwiftUI

// MARK: - SyncStatusIndicator

/// Compact Carrier Wave Sync status indicator for the status bar. Click to show detail popover.
struct SyncStatusIndicator: View {
    // MARK: Internal

    let syncService: ServerSyncService
    let onSyncRequest: () -> Void

    var body: some View {
        Button {
            showDetail.toggle()
        } label: {
            HStack(spacing: 4) {
                syncIcon
                syncLabel
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .help("Click for sync details")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .popover(isPresented: $showDetail, arrowEdge: .top) {
            SyncDetailPopover(syncService: syncService, onSyncRequest: onSyncRequest)
        }
    }

    // MARK: Private

    @State private var showDetail = false

    private var accessibilityText: String {
        switch syncService.syncStatus {
        case .disabled:
            "Carrier Wave Sync not set up"
        case .upToDate:
            "Carrier Wave Sync up to date"
        case let .syncing(detail):
            "Carrier Wave Sync: \(detail)"
        case let .error(message):
            "Carrier Wave Sync error: \(message)"
        }
    }

    @ViewBuilder
    private var syncIcon: some View {
        switch syncService.syncStatus {
        case .disabled:
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .foregroundStyle(.secondary)
        case .upToDate:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var syncLabel: some View {
        switch syncService.syncStatus {
        case .disabled:
            Text("Not set up")
                .foregroundStyle(.secondary)
        case .upToDate:
            if let lastSync = syncService.lastSyncDate {
                Text(lastSync, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            } else {
                Text("Synced")
                    .foregroundStyle(.secondary)
            }
        case let .syncing(detail):
            Text(detail)
                .foregroundStyle(.secondary)
        case .error:
            Text("Sync Error")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - SyncDetailPopover

private struct SyncDetailPopover: View {
    // MARK: Internal

    let syncService: ServerSyncService
    let onSyncRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.blue)
                Text("Carrier Wave Sync")
                    .font(.headline)
                Spacer()
                Button("Sync Now", action: onSyncRequest)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!syncService.isEnabled)
            }

            Divider()

            // Status
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    statusBadge
                }

                if syncService.counts.totalDirty > 0 {
                    GridRow {
                        Text("Pending")
                            .foregroundStyle(.secondary)
                        Label(
                            "\(syncService.counts.totalDirty) records awaiting upload",
                            systemImage: "arrow.up.circle"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                GridRow {
                    Text("Last Sync")
                        .foregroundStyle(.secondary)
                    if let date = syncService.lastSyncDate {
                        Text(date, format: Self.timestampFormat)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }

                GridRow {
                    Text("Pending")
                        .foregroundStyle(.secondary)
                    Text("\(syncService.counts.totalDirty) records")
                }
            }

            // Upload progress
            if let goal = syncService.uploadGoal, goal > 0 {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(
                        value: Double(syncService.uploadedCount),
                        total: Double(goal)
                    )
                    Text("Uploaded \(syncService.uploadedCount) of \(goal)")
                        .foregroundStyle(.secondary)
                }
            }

            // Error
            if let error = syncService.errorMessage {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 380)
        .font(.caption)
    }

    // MARK: Private

    private static let timestampFormat: Date.FormatStyle = .dateTime
        .month(.abbreviated).day().hour().minute().second()

    @ViewBuilder
    private var statusBadge: some View {
        switch syncService.syncStatus {
        case .disabled:
            Label("Not set up", systemImage: "arrow.triangle.2.circlepath.circle")
                .foregroundStyle(.secondary)
        case .upToDate:
            Label("Up to Date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .syncing:
            Label("Syncing", systemImage: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
        case .error:
            Label("Error", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
