import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - BackupSettingsView

struct BackupSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "clock.arrow.circlepath",
                tint: .gray,
                title: "Backups",
                subtitle: "Automatic snapshots that protect against data loss."
            )
            backupNowSection
            settingsSection
            ledgerSection
            restoreSection
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isRestoring {
                restoreOverlay
            }
        }
        .task {
            await loadBackups()
            ledgerFiles = QSOLedger.allFiles()
        }
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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
    @State private var isRestoring = false
    @State private var restoreStatus = ""
    @State private var restoreFilesReady = 0
    @State private var restoreFilesTotal = 0

    @AppStorage("autoBackupEnabled") private var autoBackupEnabled = true
    @AppStorage("iCloudBackupEnabled") private var iCloudBackupEnabled = true

    @State private var ledgerFiles: [LedgerFile] = []

    private var lastBackupText: String {
        guard let latest = backups.first else {
            return "Never"
        }
        return Self.relativeFormatter.localizedString(for: latest.timestamp, relativeTo: Date())
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

    private var ledgerSection: some View {
        Section {
            if ledgerFiles.isEmpty {
                Text("No ledger data yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ledgerFiles) { file in
                    LedgerFileRow(file: file)
                }
            }
        } header: {
            Text("Safety Ledger")
        } footer: {
            Text(
                "Append-only monthly ADIF and QSON files that record "
                    + "every QSO independently of the database. "
                    + "Mirrored to iCloud Drive next to SQLite "
                    + "backups. Import to recover contacts after "
                    + "data loss."
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

    private var restoreOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(restoreStatus)
                    .font(.headline)
                if restoreFilesTotal > 0 {
                    Text(
                        "\(restoreFilesReady) of \(restoreFilesTotal) files ready"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    ProgressView(
                        value: Double(restoreFilesReady),
                        total: Double(restoreFilesTotal)
                    )
                    .frame(maxWidth: 220)
                }
            }
            .padding(24)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
    }

    private func restoreConfirmationMessage(for backup: BackupEntry) -> String {
        "This will replace your current database with the "
            + "backup from \(Self.backupDateFormatter.string(from: backup.timestamp)). "
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

        let count = BackupService.visibleQSOCount(
            in: modelContext.container
        )
        let entry = await BackupService.shared.snapshot(
            trigger: .manual, storeURL: storeURL,
            qsoCount: count
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

        isRestoring = true
        restoreStatus = backup.location == .icloud
            ? "Downloading backup from iCloud…"
            : "Preparing restore…"
        restoreFilesReady = 0
        restoreFilesTotal = 0
        defer { isRestoring = false }

        do {
            try await BackupService.shared.stageRestore(
                entry: backup, storeURL: storeURL,
                downloadProgress: { ready, total in
                    Task { @MainActor in
                        restoreFilesReady = ready
                        restoreFilesTotal = total
                    }
                }
            )
            restoreStatus = "Restart required"
            showingRestartRequired = true
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

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var formattedDate: String {
        Self.rowDateFormatter.string(from: backup.timestamp)
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

// MARK: - LedgerFileRow

private struct LedgerFileRow: View {
    // MARK: Internal

    let file: LedgerFile

    var body: some View {
        ShareLink(
            item: file.url,
            preview: SharePreview(
                file.url.lastPathComponent,
                image: Image(systemName: "doc.text")
            )
        ) {
            HStack(spacing: 8) {
                Label(
                    file.displayName,
                    systemImage: "doc.text"
                )
                Text(file.format)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(formatColor.opacity(0.2))
                    .foregroundStyle(formatColor)
                    .clipShape(Capsule())
                Spacer()
                Text(sizeText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Private

    private var sizeText: String {
        ByteCountFormatter.string(
            fromByteCount: file.sizeBytes,
            countStyle: .file
        )
    }

    private var formatColor: Color {
        switch file.format {
        case "ADIF": .blue
        case "QSON": .purple
        default: .gray
        }
    }
}
