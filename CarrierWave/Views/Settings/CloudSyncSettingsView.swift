import CarrierWaveData
import CloudKit
import SwiftData
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
                recordCountsSection
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
            Task { await syncService.refreshCounts() }
        }
        .alert(
            "Enable Experimental Sync?",
            isPresented: $showEnableConfirmation
        ) {
            Button("Enable", role: .destructive) {
                Task { await enableWithBackup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "iCloud sync is experimental and may overwrite local data. "
                    + "A backup will be created before enabling."
            )
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var syncService = CloudSyncService.shared
    @StateObject private var monitor = ICloudMonitor()
    @State private var showEnableConfirmation = false

    // MARK: - Helpers

    private var counts: CloudSyncRecordCounts {
        syncService.counts
    }

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

    private var syncedRows: [(label: String, count: Int)] {
        counts.syncedRecords
            .sorted { $0.key < $1.key }
            .map { (label: displayName(for: $0.key), count: $0.value) }
    }

    private var isUploading: Bool {
        syncService.uploadGoal != nil
    }

    private var pendingDisabled: Bool {
        isUploading || counts.totalDirty == 0
    }

    // MARK: - Sections

    private var syncToggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { syncService.isEnabled },
                set: { newValue in
                    if newValue {
                        showEnableConfirmation = true
                    } else {
                        Task { await syncService.setEnabled(false) }
                    }
                }
            )) {
                HStack {
                    Text("iCloud QSO Sync")
                    Text("Experimental")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.orange.opacity(0.15))
                        )
                }
            }
        } footer: {
            Text(
                "Sync QSOs, sessions, and upload status across your devices via iCloud. "
                    + "This feature is experimental — a backup is created automatically when enabled."
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

            if let goal = syncService.uploadGoal, goal > 0 {
                uploadProgressRow(goal: goal, uploaded: syncService.uploadedCount)
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
        } header: {
            Text("Status")
        }
    }

    private var recordCountsSection: some View {
        Section {
            countRow("Pending upload", count: counts.totalDirty)

            if counts.totalDirty > 0 {
                countRow("  QSOs", count: counts.dirtyQSOs)
                countRow("  Service status", count: counts.dirtyServicePresence)
                countRow("  Sessions", count: counts.dirtySessions)
                countRow("  Activations", count: counts.dirtyMetadata)
                countRow("  Spots", count: counts.dirtySpots)
                countRow("  Activity logs", count: counts.dirtyLogs)
            }

            countRow("Synced to iCloud", count: counts.totalSynced)

            if counts.totalSynced > 0 {
                ForEach(syncedRows, id: \.label) { row in
                    countRow("  \(row.label)", count: row.count)
                }
            }
        } header: {
            Text("Records")
        } footer: {
            Text(
                "Pending upload = local changes not yet in iCloud. "
                    + "Synced = records iCloud knows about."
            )
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await syncService.syncPending() }
            } label: {
                Label(
                    "Upload \(counts.totalDirty) Pending",
                    systemImage: "icloud.and.arrow.up"
                )
                .foregroundStyle(pendingDisabled ? Color.gray.opacity(0.3) : Color.blue)
            }
            .disabled(pendingDisabled)

            Button {
                Task { await syncService.forceFullSync() }
            } label: {
                Label(
                    "Force Full Re-sync",
                    systemImage: "arrow.triangle.2.circlepath.icloud"
                )
                .foregroundStyle(isUploading ? Color.gray.opacity(0.3) : Color.blue)
            }
            .disabled(isUploading)
        } footer: {
            Text(
                "Upload Pending pushes only dirty records. "
                    + "Force Full Re-sync marks everything dirty and re-uploads all data."
            )
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

    private func uploadProgressRow(goal: Int, uploaded: Int) -> some View {
        let done = min(uploaded, goal)
        let fraction = Double(done) / Double(goal)
        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: fraction)
                .tint(.blue)
            Text("\(done) of \(goal) uploaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func countRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func displayName(for entityType: String) -> String {
        switch entityType {
        case "QSO": "QSOs"
        case "ServicePresence": "Service status"
        case "LoggingSession": "Sessions"
        case "ActivationMetadata": "Activations"
        case "SessionSpot": "Spots"
        case "ActivityLog": "Activity logs"
        default: entityType
        }
    }

    private func enableWithBackup() async {
        if let storeURL = modelContext.container
            .configurations.first?.url
        {
            let count = BackupService.visibleQSOCount(
                in: modelContext.container
            )
            await BackupService.shared.snapshot(
                trigger: .preSync,
                storeURL: storeURL,
                qsoCount: count
            )
        }
        await syncService.setEnabled(true)
    }
}
