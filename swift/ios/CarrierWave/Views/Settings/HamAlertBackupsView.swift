// HamAlert Backups View
//
// Lists stored HamAlert trigger backups with options
// to restore a backup to HamAlert or delete local backups.

import CarrierWaveData
import SwiftUI

// MARK: - HamAlertBackupsView

struct HamAlertBackupsView: View {
    // MARK: Internal

    var body: some View {
        List {
            if backups.isEmpty {
                emptyState
            } else {
                backupsList
            }
        }
        .navigationTitle("HamAlert Backups")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadBackups() }
        .alert(
            "Restore Backup?",
            isPresented: $showingRestoreConfirm,
            presenting: entryToRestore
        ) { entry in
            Button("Restore", role: .destructive) {
                Task { await restore(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(
                "This will delete all current HamAlert triggers"
                    + " and replace them with \(entry.triggerCount)"
                    + " triggers from this backup."
            )
        }
        .alert(
            "Restore Complete",
            isPresented: $showingResult,
            presenting: restoreResult
        ) { _ in
            Button("OK") {}
        } message: { result in
            Text(
                "Restored \(result.triggersRestored)"
                    + " of \(result.totalInBackup) triggers."
            )
        }
        .alert(
            "Restore Failed",
            isPresented: showingError,
            actions: { Button("OK") {} },
            message: { Text(errorMessage ?? "Unknown error") }
        )
    }

    // MARK: Private

    @State private var backups: [HamAlertBackupEntry] = []
    @State private var entryToRestore: HamAlertBackupEntry?
    @State private var showingRestoreConfirm = false
    @State private var isRestoring = false
    @State private var restoreResult: HamAlertRestoreResult?
    @State private var showingResult = false
    @State private var errorMessage: String?

    private var showingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private var hasCredentials: Bool {
        (try? KeychainHelper.shared.read(
            for: KeychainHelper.Keys.hamAlertUsername
        )) != nil
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView(
                "No Backups",
                systemImage: "arrow.counterclockwise.circle",
                description: Text(
                    "Backups are created automatically"
                        + " when you push triggers to HamAlert."
                )
            )
        }
    }

    private var backupsList: some View {
        Section {
            ForEach(backups) { entry in
                backupRow(entry)
            }
            .onDelete { offsets in
                deleteBackups(at: offsets)
            }
        } footer: {
            Text("Swipe to delete a backup. Backups are created automatically before each export.")
        }
    }

    private func backupRow(
        _ entry: HamAlertBackupEntry
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date, style: .date)
                    .font(.subheadline)
                Text(
                    "\(entry.triggerCount) triggers — "
                        + entry.date.formatted(
                            .dateTime.hour().minute()
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isRestoring, entryToRestore?.id == entry.id {
                ProgressView()
            } else {
                Button {
                    entryToRestore = entry
                    showingRestoreConfirm = true
                } label: {
                    Text("Restore")
                        .font(.subheadline)
                }
                .disabled(!hasCredentials || isRestoring)
            }
        }
    }

    private func loadBackups() {
        backups = HamAlertBackupManager.listBackups()
    }

    private func deleteBackups(at offsets: IndexSet) {
        for index in offsets {
            HamAlertBackupManager.deleteBackup(backups[index])
        }
        backups.remove(atOffsets: offsets)
    }

    private func restore(_ entry: HamAlertBackupEntry) async {
        guard
            let username = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.hamAlertUsername
            ),
            let password = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.hamAlertPassword
            )
        else {
            errorMessage = "HamAlert credentials not configured."
            return
        }

        isRestoring = true
        errorMessage = nil

        do {
            let exporter = HamAlertExporter()
            let result = try await exporter.restoreBackup(
                entry,
                username: username,
                password: password
            )
            restoreResult = result
            showingResult = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isRestoring = false
    }
}
