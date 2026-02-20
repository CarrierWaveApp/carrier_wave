import CloudKit
import SwiftUI

/// iCloud sync settings: enable/disable toggle, status, last sync time, account info.
/// Replaces the previous ICloudSettingsView with a richer sync-aware interface.
struct CloudSyncSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            syncToggleSection
            statusSection

            if syncService.isEnabled {
                actionsSection
            }

            adifImportSection

            if syncService.errorMessage != nil || syncService.syncStatus.isError {
                errorSection
            }
        }
        .navigationTitle("iCloud")
        .onAppear {
            monitor.refreshContainerURL()
        }
    }

    // MARK: Private

    @ObservedObject private var syncService = CloudSyncService.shared
    @StateObject private var monitor = ICloudMonitor()
    @State private var isForcing = false

    // MARK: - Helpers

    private var statusColor: Color {
        switch syncService.syncStatus {
        case .disabled: .secondary
        case .upToDate: .green
        case .syncing: .blue
        case .error: .red
        }
    }

    private var accountStatusText: String {
        switch syncService.accountStatus {
        case .available: "Signed In"
        case .noAccount: "Not Signed In"
        case .restricted: "Restricted"
        case .couldNotDetermine: "Unknown"
        case .temporarilyUnavailable: "Temporarily Unavailable"
        @unknown default: "Unknown"
        }
    }

    // MARK: - Sections

    private var syncToggleSection: some View {
        Section {
            Toggle("iCloud QSO Sync", isOn: Binding(
                get: { syncService.isEnabled },
                set: { newValue in
                    Task { await syncService.setEnabled(newValue) }
                }
            ))
        } footer: {
            Text(
                "Sync QSOs, sessions, and upload status across your devices via iCloud."
            )
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Label(syncService.syncStatus.displayText,
                      systemImage: syncService.syncStatus.iconName)
                    .foregroundStyle(statusColor)
                Spacer()
            }

            if let lastSync = syncService.lastSyncDate {
                HStack {
                    Text("Last synced")
                    Spacer()
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                    Text("ago")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("iCloud Account")
                Spacer()
                Text(accountStatusText)
                    .foregroundStyle(.secondary)
            }

            if syncService.pendingCount > 0 {
                HStack {
                    Text("Pending")
                    Spacer()
                    Text("\(syncService.pendingCount) records")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Status")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    isForcing = true
                    await syncService.forceFullSync()
                    isForcing = false
                }
            } label: {
                if isForcing {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Syncing...")
                    }
                } else {
                    Text("Sync Now")
                }
            }
            .disabled(isForcing)
        }
    }

    private var adifImportSection: some View {
        Section {
            if let url = monitor.iCloudContainerURL {
                VStack(alignment: .leading) {
                    Text("ADIF Import Folder")
                        .font(.headline)
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Create Folder") {
                    monitor.createImportFolderIfNeeded()
                }
            } else {
                Text("iCloud Drive is not available")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("ADIF File Import")
        } footer: {
            Text("Place ADIF files in this folder to import them.")
        }
    }

    private var errorSection: some View {
        Section {
            if let error = syncService.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        } header: {
            Text("Errors")
        }
    }
}
