import SwiftUI

// MARK: - ContentAreaView

/// Dispatches content based on sidebar selection and active role
struct ContentAreaView: View {
    // MARK: Internal

    let selectedItem: SidebarItem
    let activeRole: OperatingRole
    let radioManager: RadioManager

    var body: some View {
        switch selectedItem {
        case .logger:
            roleSpecificLoggerView
        case .spots:
            SpotListView()
        case .map:
            QSOMapView()
        case .bandMap:
            BandMapView()
        case .cluster:
            ClusterView()
        case .pota:
            SpotListView(initialSourceFilter: .pota)
        case .ft8:
            PlaceholderView(title: "FT8", icon: "waveform", description: "FT8 decode/encode — Phase 4")
        case .cw:
            PlaceholderView(title: "CW", icon: "waveform.path", description: "CW decoder — Phase 4")
        case .sdr:
            SDRPlayerView()
        case .recordings:
            RecordingLibraryView()
        case .qsoLog:
            QSOLogTableView()
        case .dashboard:
            DashboardView()
        case .multipliers:
            MultiplierTrackerView()
        case .contestScore:
            ScoreSummaryView()
        case .radio:
            RadioControlView(radioManager: radioManager)
        case .winkeyer:
            WinKeyerView()
        case .sync:
            SyncStatusView()
        case .sessions:
            SessionsListView()
        }
    }

    // MARK: Private

    @ViewBuilder
    private var roleSpecificLoggerView: some View {
        switch activeRole {
        case .contester:
            ContesterLayout(radioManager: radioManager)
        case .hunter:
            HunterLayout(radioManager: radioManager)
        case .activator:
            ActivatorLayout(radioManager: radioManager)
        case .dxer:
            DXerLayout(radioManager: radioManager)
        case .casual:
            CasualLayout(radioManager: radioManager)
        }
    }
}

// MARK: - SyncStatusView

struct SyncStatusView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: syncService.syncStatus.iconName)
                .font(.system(size: 48))
                .foregroundStyle(statusColor)

            Text(statusTitle)
                .font(.title3)

            Text(statusDetail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            if !syncService.isEnabled {
                Button("Enable iCloud Sync") {
                    Task { await syncService.setEnabled(true) }
                }
                .buttonStyle(.borderedProminent)

                Text("Or enable in Settings → Sync")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if syncService.counts.totalDirty > 0 {
                Button("Sync Now") {
                    Task { await syncService.syncPending() }
                }
                .buttonStyle(.borderedProminent)
            }

            if let goal = syncService.uploadGoal, goal > 0 {
                ProgressView(
                    value: Double(syncService.uploadedCount),
                    total: Double(goal)
                )
                .frame(width: 200)
                Text("Uploaded \(syncService.uploadedCount) of \(goal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = syncService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Private

    private var syncService = CloudSyncService.shared

    private var statusColor: Color {
        switch syncService.syncStatus {
        case .disabled: .secondary
        case .upToDate: .green
        case .syncing: .blue
        case .error: .red
        }
    }

    private var statusTitle: String {
        switch syncService.syncStatus {
        case .disabled: "iCloud Sync Disabled"
        case .upToDate: "iCloud Sync Active"
        case .syncing: "Syncing..."
        case .error: "Sync Error"
        }
    }

    private var statusDetail: String {
        switch syncService.syncStatus {
        case .disabled:
            "Enable iCloud sync to share QSOs and sessions\nbetween CW Sweep and Carrier Wave."
        case .upToDate:
            "QSOs, sessions, and settings sync automatically\nvia iCloud.com.jsvana.FullDuplex\n\n\(syncService.counts.totalSynced) records synced"
        case let .syncing(detail):
            detail
        case let .error(message):
            message
        }
    }
}
