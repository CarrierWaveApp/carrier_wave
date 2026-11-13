import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ContentAreaView

/// Dispatches content based on sidebar selection and active role
struct ContentAreaView: View {
    let selectedItem: SidebarItem
    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService

    var body: some View {
        switch selectedItem {
        case .logger:
            SessionsSidebarRoot(radioManager: radioManager, flexDiscovery: flexDiscovery)
        case .spots:
            SpotListView()
        case .map:
            QSOMapView()
        case .cluster:
            ClusterView()
        case .satellites:
            SatellitesView(model: SharedEnvironment.shared.satellitePassModel)
        case .qsoLog:
            QSOLogTableView()
        case .dashboard:
            DashboardView()
        case .radio:
            RadioControlView(radioManager: radioManager, flexDiscovery: flexDiscovery)
        case .winkeyer:
            KeyerControlView()
        case .rotator:
            RotatorControlView()
        case .sync:
            SyncStatusView()
        case .dxcc:
            DXCCTrackingView()
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
                SettingsLink {
                    Text("Set Up in Settings → Sync")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Sync Now") {
                    Task { await syncService.syncPending() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncService.syncStatus.isSyncing)
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
        .task { await syncService.refreshCounts() }
    }

    // MARK: Private

    private var syncService = ServerSyncService.shared

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
        case .disabled: "Carrier Wave Sync Not Set Up"
        case .upToDate: "Carrier Wave Sync Active"
        case .syncing: "Syncing…"
        case .error: "Sync Error"
        }
    }

    private var statusDetail: String {
        switch syncService.syncStatus {
        case .disabled:
            "Sign in and enter your sync passphrase to share QSOs and sessions\n"
                + "between CW Sweep and Carrier Wave: Field."
        case .upToDate:
            "QSOs and sessions sync end-to-end encrypted\nthrough \(ActivitiesServer.resolvedBaseURL)"
        case let .syncing(detail):
            detail
        case let .error(message):
            message
        }
    }
}
