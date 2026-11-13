import CarrierWaveData
import SwiftUI

// MARK: - CarrierWaveSyncSettingsTab

/// Settings → Sync: Carrier Wave Sync (E2E-encrypted sync with the Carrier
/// Wave server). Account check, passphrase create / unlock / forget, and the
/// sync status + manual controls. Mirrors the iOS `SyncPassphraseView`.
struct CarrierWaveSyncSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            headerSection
            if !account.isSignedIn {
                signInRequiredSection
            } else {
                switch keyService.status {
                case .unknown: unknownSection
                case .notConfigured: createSection
                case .lockedNeedsPassphrase: unlockSection
                case .ready: readySection
                }
                if let error = keyService.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await sync.refreshEnablement()
        }
        .onChange(of: account.isSignedIn) { _, _ in
            Task { await sync.refreshEnablement() }
        }
    }

    // MARK: Private

    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var isWorking = false

    private var sync = ServerSyncService.shared
    private var account = AccountService.shared

    private var keyService: SyncKeyService {
        sync.keyService
    }

    private var canCreate: Bool {
        passphrase.count >= 8 && passphrase == confirmPassphrase && !isWorking
    }

    /// Why the Create button is disabled, or nil when it's ready.
    private var createHint: String? {
        if passphrase.isEmpty {
            return nil
        }
        if passphrase.count < 8 {
            return "Use at least 8 characters."
        }
        if confirmPassphrase.isEmpty {
            return "Re-enter your passphrase in the second field to confirm."
        }
        if passphrase != confirmPassphrase {
            return "Passphrases don't match."
        }
        return nil
    }

    private var headerSection: some View {
        Section("Carrier Wave Sync") {
            Text("Your log is end-to-end encrypted with a passphrase only you know. "
                + "The server stores it wrapped — it can never read your data. QSOs and "
                + "sessions sync between CW Sweep and Carrier Wave: Field.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LabeledContent("Server") {
                Text(ActivitiesServer.resolvedBaseURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var signInRequiredSection: some View {
        Section {
            Text("Carrier Wave Sync requires an account with a verified email, so your synced log can "
                + "always be recovered. Sign in with your callsign in the Accounts tab first.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Account Required")
        }
    }

    private var unknownSection: some View {
        Section {
            Button("Retry") {
                Task { await sync.refreshEnablement() }
            }
        } footer: {
            Text("Couldn't reach the sync server. Make sure you're signed in and online.")
        }
    }

    private var createSection: some View {
        Section {
            SecureField("Passphrase (8+ characters)", text: $passphrase)
            SecureField("Confirm passphrase", text: $confirmPassphrase)
            if let hint = createHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button("Create Passphrase") {
                Task { await create() }
            }
            .disabled(!canCreate)
            progressRow
        } header: {
            Text("Set up sync")
        } footer: {
            Text("If you forget this passphrase it cannot be recovered, and neither can your synced data. "
                + "Store it somewhere safe.")
        }
    }

    private var unlockSection: some View {
        Section {
            SecureField("Passphrase", text: $passphrase)
            Button("Unlock This Mac") {
                Task { await unlock() }
            }
            .disabled(passphrase.isEmpty || isWorking)
            progressRow
        } header: {
            Text("Enter your passphrase")
        } footer: {
            Text("This account already has a sync passphrase. Enter it to set up sync on this Mac.")
        }
    }

    private var readySection: some View {
        Section {
            Label("This Mac is set up for sync.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Image(systemName: sync.syncStatus.iconName)
                    Text(sync.syncStatus.displayText)
                        .foregroundStyle(.secondary)
                }
            }
            if let last = sync.lastSyncDate {
                LabeledContent("Last sync") {
                    Text(last, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }
            if sync.counts.totalDirty > 0 {
                LabeledContent("Pending upload") {
                    Text("\(sync.counts.totalDirty) QSOs")
                        .foregroundStyle(.orange)
                }
            }
            HStack {
                Button("Sync Now") {
                    Task { await syncNow() }
                }
                .disabled(isWorking || sync.syncStatus.isSyncing)
                Button("Upload Full Log") {
                    Task { await uploadFullLog() }
                }
                .disabled(isWorking || sync.syncStatus.isSyncing)
            }
            progressRow
            if let summary = keyService.lastSyncSummary {
                Text("Last sync: \(summary.pushed) uploaded, \(summary.pulled) downloaded "
                    + "· \(String(format: "%.1fs", summary.seconds))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let profile = keyService.lastProfile {
                ShareLink("Share Sync Report", item: profile.report)
            }
            Button("Forget on This Mac", role: .destructive) {
                Task {
                    isWorking = true
                    await keyService.forgetOnThisDevice()
                    await sync.refreshEnablement()
                    isWorking = false
                }
            }
            .disabled(isWorking)
        } header: {
            Text("Sync")
        } footer: {
            Text("Sync runs automatically after you log, every few minutes, and when the Mac wakes. "
                + "Forget removes the key from this Mac only.")
        }
    }

    /// Live status while an operation runs: spinner + current phase + elapsed time.
    @ViewBuilder private var progressRow: some View {
        if isWorking || sync.syncStatus.isSyncing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(keyService.phase.label.isEmpty ? sync.syncStatus.displayText : keyService.phase.label)
                    .font(.footnote)
                Spacer()
                if let start = keyService.operationStart {
                    TimelineView(.periodic(from: start, by: 0.1)) { context in
                        Text(String(format: "%.1fs", max(0, context.date.timeIntervalSince(start))))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func syncNow() async {
        isWorking = true
        await sync.syncPending()
        isWorking = false
    }

    private func uploadFullLog() async {
        isWorking = true
        await sync.forceFullSync()
        isWorking = false
    }

    private func create() async {
        isWorking = true
        if await keyService.createPassphrase(passphrase) {
            passphrase = ""
            confirmPassphrase = ""
            await sync.refreshEnablement()
        }
        isWorking = false
    }

    private func unlock() async {
        isWorking = true
        if await keyService.unlock(passphrase) {
            passphrase = ""
            await sync.refreshEnablement()
        }
        isWorking = false
    }
}
