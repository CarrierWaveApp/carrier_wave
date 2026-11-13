import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RecoveryModeView

/// Full-screen takeover shown at app launch when
/// `ContainerSetup.createModelContainer` failed to open the on-disk
/// SwiftData store. Replaces the silent auto-wipe behavior with three
/// explicit, user-confirmed actions: restore from the most recent
/// backup, send diagnostics so we can debug it, or destructively reset.
///
/// The user is locked into this view across launches until they pick
/// one of the actions. The broken `default.store` on disk is left
/// intact (a copy is also in `Library/EmergencyBackup/`) so the
/// in-progress restore or future diagnostic export can use it.
struct RecoveryModeView: View {
    // MARK: Internal

    let failureRecord: ContainerInitFailureRecord
    let storeURL: URL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    Divider()
                    backupSection
                    Divider()
                    actionsSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Database Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
        .task {
            mostRecentBackup = await loadMostRecentBackup()
        }
        .sheet(isPresented: $showingSendDiagnostics) {
            SendDiagnosticsView(
                showingSendDiagnostics: $showingSendDiagnostics
            )
        }
    }

    // MARK: Private

    private enum ActionKind: Equatable {
        case restoring
        case resetting
    }

    // MARK: - State

    @State private var mostRecentBackup: BackupEntry?
    @State private var resetConfirmText: String = ""
    @State private var showingResetConfirmation: Bool = false
    @State private var actionInFlight: ActionKind?
    @State private var errorMessage: String?
    @State private var showingSendDiagnostics: Bool = false

    private var isBusy: Bool {
        actionInFlight != nil
    }

    // MARK: - Helpers

    private var headerSubtitle: String {
        "Your QSO history is safe — backups are intact. "
            + "Pick what to do below. The app will quit after the "
            + "action; relaunch to continue."
    }

    private var failureTimestampString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: failureRecord.timestamp)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("Carrier Wave couldn't open your database")
                .font(.title2.weight(.semibold))
            Text(headerSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            failureDetailRow(
                "When", failureTimestampString
            )
            failureDetailRow(
                "Error", failureRecord.errorDescription
            )
            if let backupName = failureRecord.emergencyBackupFilename {
                failureDetailRow(
                    "Saved copy", "EmergencyBackup/\(backupName)"
                )
            }
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your most recent backup")
                .font(.headline)
            if let backup = mostRecentBackup {
                Text("\(backup.qsoCount) QSOs")
                    .font(.title3.weight(.semibold))
                Text(backupTimestampString(backup.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("App version \(backup.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Loading backup info…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            restoreButton
            sendDiagnosticsButton
            resetButton
        }
    }

    // MARK: - Buttons

    private var restoreButton: some View {
        Button {
            Task { await stageRestore() }
        } label: {
            HStack {
                if actionInFlight == .restoring {
                    ProgressView()
                        .tint(.white)
                }
                Text("Restore from this backup")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(mostRecentBackup == nil || isBusy)
    }

    private var sendDiagnosticsButton: some View {
        Button {
            showingSendDiagnostics = true
        } label: {
            Label(
                "Send diagnostics", systemImage: "ladybug"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isBusy)
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            showingResetConfirmation = true
        } label: {
            Label(
                "Reset to empty database",
                systemImage: "trash"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isBusy)
        .alert(
            "Erase database?",
            isPresented: $showingResetConfirmation
        ) {
            TextField(
                "Type RESET to confirm", text: $resetConfirmText
            )
            .textInputAutocapitalization(.characters)
            Button("Cancel", role: .cancel) {
                resetConfirmText = ""
            }
            Button("Erase", role: .destructive) {
                if resetConfirmText == "RESET" {
                    performReset()
                }
                resetConfirmText = ""
            }
        } message: {
            Text(
                "This deletes the broken database. "
                    + "Your most recent backup is unaffected, but "
                    + "this won't restore from it. Type RESET to "
                    + "confirm."
            )
        }
    }

    private func failureDetailRow(
        _ label: String, _ value: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func backupTimestampString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func loadMostRecentBackup() async -> BackupEntry? {
        let manifest = await BackupService.shared.loadManifest()
        return manifest
            .filter { $0.qsoCount > 0 }
            .max { $0.timestamp < $1.timestamp }
    }

    private func stageRestore() async {
        guard let backup = mostRecentBackup else {
            return
        }
        actionInFlight = .restoring
        errorMessage = nil
        do {
            try await BackupService.shared.stageRestore(
                entry: backup, storeURL: storeURL
            )
            // Clear the failure record so the next launch — after
            // applyPendingRestore swaps the backup into place —
            // boots into the normal app, not back into recovery.
            ContainerSetup.clearFailureRecord()
            // exit so the staged restore applies on next launch.
            // Mirrors the existing in-app restore flow in
            // BackupSettingsView.
            exit(0)
        } catch {
            actionInFlight = nil
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func performReset() {
        actionInFlight = .resetting
        errorMessage = nil
        ContainerSetup.confirmedReset(storeURL: storeURL)
        // Same exit-and-relaunch pattern: a fresh launch will see no
        // failure record and create an empty container normally.
        exit(0)
    }
}
