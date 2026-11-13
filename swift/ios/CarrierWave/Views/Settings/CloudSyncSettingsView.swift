import CarrierWaveData
import CloudKit
import SwiftData
import SwiftUI

/// iCloud sync settings: enable/disable toggle, status, last sync time, account info.
/// Replaces the previous ICloudSettingsView with a richer sync-aware interface.
struct CloudSyncSettingsView: View {
    // MARK: Internal

    var syncService = CloudSyncService.shared

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "icloud.fill",
                tint: .blue,
                title: "iCloud Sync",
                subtitle: "Keep your logbook in sync across devices with iCloud."
            )
            syncToggleSection
            statusSection

            if syncService.isEnabled {
                recordCountsSection
                activitySummarySection
                actionsSection
            }

            if syncService.errorMessage != nil || syncService.syncStatus.isError {
                errorSection
            }
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await syncService.refreshCounts()
                await syncService.refreshSyncEvents()
            }
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
                    ExperimentalBadge(feature: .icloudSync)
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
                countRow("  Service records", count: counts.dirtyServicePresence)
                countRow("  Sessions", count: counts.dirtySessions)
                countRow("  Activations", count: counts.dirtyMetadata)
                countRow("  Spots", count: counts.dirtySpots)
                countRow("  Activity logs", count: counts.dirtyLogs)
            }
        } header: {
            Text("Records")
        } footer: {
            Text(
                "Pending upload = local changes not yet bundled into the next "
                    + "journal entry."
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
