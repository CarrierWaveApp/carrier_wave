import SwiftData
import SwiftUI

// MARK: - BackupSettingsView

struct BackupSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            backupNowSection
            settingsSection
            restoreSection
        }
        .navigationTitle("Backups")
        .task { await loadBackups() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert(
            "Restore Database?",
            isPresented: $showingRestoreConfirmation,
            presenting: selectedBackup
        ) { backup in
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task { await performRestore(backup) }
            }
        } message: { backup in
            Text(restoreConfirmationMessage(for: backup))
        }
        .alert(
            "Delete Backup?",
            isPresented: $showingDeleteConfirmation,
            presenting: backupToDelete
        ) { backup in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await BackupService.shared.deleteBackup(backup)
                    await loadBackups()
                }
            }
        } message: { _ in
            Text("This backup will be permanently deleted.")
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var backups: [BackupEntry] = []
    @State private var isCreatingBackup = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackup: BackupEntry?
    @State private var showingRestartRequired = false
    @State private var showingDeleteConfirmation = false
    @State private var backupToDelete: BackupEntry?

    @AppStorage("autoBackupEnabled") private var autoBackupEnabled = true
    @AppStorage("iCloudBackupEnabled") private var iCloudBackupEnabled = true

    private var lastBackupText: String {
        guard let latest = backups.first else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: latest.timestamp, relativeTo: Date())
    }

    // MARK: - Sections

    private var backupNowSection: some View {
        Section {
            Button {
                Task { await createManualBackup() }
            } label: {
                if isCreatingBackup {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Backing up...")
                    }
                } else {
                    HStack {
                        Text("Back Up Now")
                        Spacer()
                        Text(lastBackupText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isCreatingBackup)
        } footer: {
            Text(
                "Creates a snapshot of your QSO database. "
                    + "Backups are stored on this device."
            )
        }
    }

    private var settingsSection: some View {
        Section {
            Toggle("Auto-backup", isOn: $autoBackupEnabled)
            Toggle("iCloud backup", isOn: $iCloudBackupEnabled)
        } footer: {
            Text(
                "Auto-backup creates snapshots on app launch, "
                    + "before sync, and before import. "
                    + "iCloud backup copies the 2 most recent "
                    + "snapshots to iCloud Drive."
            )
        }
    }

    private var restoreSection: some View {
        Section {
            if backups.isEmpty {
                Text("No backups available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backups) { backup in
                    BackupRow(backup: backup)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedBackup = backup
                            showingRestoreConfirmation = true
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                backupToDelete = backup
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            Text("Restore from Backup")
        } footer: {
            if !backups.isEmpty {
                Text(
                    "Tap a backup to restore. "
                        + "Swipe left to delete. "
                        + "Up to 5 backups are kept on device."
                )
            }
        }
    }

    private func restoreConfirmationMessage(for backup: BackupEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "This will replace your current database with the "
            + "backup from \(formatter.string(from: backup.timestamp)). "
            + "A safety backup of your current data will be "
            + "created first.\n\n"
            + "The app must restart to complete the restore. "
            + "iCloud sync will be paused until you re-enable it."
    }

    @MainActor
    private func createManualBackup() async {
        isCreatingBackup = true
        defer { isCreatingBackup = false }

        guard let storeURL = modelContext.container
            .configurations.first?.url
        else {
            errorMessage = "Could not locate database."
            showingError = true
            return
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Could not save before backup: "
                + "\(error.localizedDescription)"
            showingError = true
            return
        }

        let entry = await BackupService.shared.snapshot(
            trigger: .manual, storeURL: storeURL
        )
        if entry == nil {
            errorMessage = "Backup failed. Check available storage."
            showingError = true
        }

        await loadBackups()
    }

    private func loadBackups() async {
        backups = await BackupService.shared.availableBackups()
    }

    @MainActor
    private func performRestore(_ backup: BackupEntry) async {
        guard let storeURL = modelContext.container
            .configurations.first?.url
        else {
            errorMessage = "Could not locate database."
            showingError = true
            return
        }

        do {
            try await BackupService.shared.stageRestore(
                entry: backup, storeURL: storeURL
            )
            showingRestartRequired = true
            // Exit the app so restore applies on next launch
            exit(0)
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - BackupRow

private struct BackupRow: View {
    // MARK: Internal

    let backup: BackupEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedDate)
                    .font(.body)
                Spacer()
                Text(triggerLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(triggerColor.opacity(0.2))
                    .foregroundStyle(triggerColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label(
                    "\(backup.qsoCount) QSOs",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                Label(formattedSize, systemImage: "internaldrive")
                if backup.location == .icloud {
                    Label("iCloud", systemImage: "icloud")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: backup.timestamp)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: backup.sizeBytes,
            countStyle: .file
        )
    }

    private var triggerLabel: String {
        switch backup.trigger {
        case .launch: "Launch"
        case .preSync: "Pre-Sync"
        case .preImport: "Pre-Import"
        case .manual: "Manual"
        case .preRestore: "Safety"
        }
    }

    private var triggerColor: Color {
        switch backup.trigger {
        case .launch: .blue
        case .preSync: .orange
        case .preImport: .purple
        case .manual: .green
        case .preRestore: .red
        }
    }
}
