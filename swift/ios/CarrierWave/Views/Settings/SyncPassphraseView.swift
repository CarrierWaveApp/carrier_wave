import CarrierWaveData
import SwiftUI

// MARK: - SyncPassphraseView

/// Set up or unlock the E2E sync passphrase (Server Sync experiment). Mints and
/// escrows the data key on first use, or recovers it on a new device.
struct SyncPassphraseView: View {
    // MARK: Internal

    var body: some View {
        Form {
            SettingsHeroHeader(
                icon: "lock.icloud.fill",
                tint: .teal,
                title: "Carrier Wave Sync",
                subtitle: "End-to-end encrypted sync with the Carrier Wave server."
            )
            headerSection

            if hasAccountSession == false {
                signInRequiredSection
            } else {
                switch service.status {
                case .unknown: unknownSection
                case .notConfigured: createSection
                case .lockedNeedsPassphrase: unlockSection
                case .ready: readySection
                }

                if let error = service.lastError {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
        }
        .navigationTitle("Carrier Wave Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshSession() }
        .onReceive(
            NotificationCenter.default.publisher(for: .didCompleteOAuthVerification)
        ) { _ in
            Task { await refreshSession() }
        }
    }

    // MARK: Private

    @State private var service = SyncKeyService()
    /// Whether an account-backed OAuth session exists. Sync requires one (the
    /// server rejects legacy device tokens with ACCOUNT_REQUIRED); nil = not
    /// checked yet.
    @State private var hasAccountSession: Bool?
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var isWorking = false

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
        Section {
            HStack {
                ExperimentalBadge(feature: .syncServer)
                Spacer()
            }
            Text(
                "Your log is end-to-end encrypted with a passphrase only you know. "
                    + "The server stores it wrapped — it can never read your data."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("Server: \(ActivitiesClient.resolvedBaseURL)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
            Button {
                Task { await create() }
            } label: {
                buttonLabel("Create Passphrase")
            }
            .disabled(!canCreate)
            progressRow
        } footer: {
            Text(
                "If you forget this passphrase it cannot be recovered, and neither "
                    + "can your synced data. Store it somewhere safe."
            )
        }
    }

    private var unlockSection: some View {
        Section {
            SecureField("Passphrase", text: $passphrase)
            Button {
                Task { await unlock() }
            } label: {
                buttonLabel("Unlock This Device")
            }
            .disabled(passphrase.isEmpty || isWorking)
            progressRow
        } header: {
            Text("Enter your passphrase")
        } footer: {
            Text("This account already has a sync passphrase. Enter it to set up sync on this device.")
        }
    }

    private var readySection: some View {
        Section {
            Label("This device is set up for sync.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button {
                Task { await syncNow() }
            } label: {
                buttonLabel("Sync Now")
            }
            .disabled(isWorking)
            Button {
                Task { await uploadFullLog() }
            } label: {
                buttonLabel("Upload Full Log")
            }
            .disabled(isWorking)
            progressRow
            if let summary = service.lastSyncSummary {
                Text(
                    "Last sync: \(summary.pushed) uploaded, \(summary.pulled) downloaded "
                        + "· \(String(format: "%.1fs", summary.seconds))"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let profile = service.lastProfile {
                ShareLink("Share Sync Report", item: profile.report)
            }
            Button(role: .destructive) {
                Task { isWorking = true; await service.forgetOnThisDevice(); isWorking = false }
            } label: {
                Text("Forget on This Device")
            }
            .disabled(isWorking)
        } footer: {
            Text(
                "Sync uploads this device's new QSOs (encrypted) and downloads any "
                    + "from your other devices. Forget removes the key from this device only."
            )
        }
    }

    /// Shown until the user verifies their callsign + email: sync data must be
    /// recoverable via a real account, so there's no passphrase UI without one.
    private var signInRequiredSection: some View {
        Section {
            NavigationLink {
                OAuthVerifyView()
            } label: {
                Label("Sign In with Your Callsign", systemImage: "person.crop.circle.badge.checkmark")
            }
        } header: {
            Text("Account Required")
        } footer: {
            Text(
                "Carrier Wave Sync requires an account with a verified email, so your "
                    + "synced log can always be recovered. Verify your callsign — you'll "
                    + "get a sign-in link by email."
            )
        }
    }

    private var unknownSection: some View {
        Section {
            Button {
                Task { await service.refreshStatus() }
            } label: {
                buttonLabel("Retry")
            }
        } footer: {
            Text("Couldn't reach the sync server. Make sure you're signed in and online.")
        }
    }

    /// Live status while an operation runs: spinner + current phase + elapsed time.
    @ViewBuilder private var progressRow: some View {
        if isWorking {
            HStack(spacing: 8) {
                ProgressView()
                Text(service.phase.label)
                    .font(.footnote)
                Spacer()
                if let start = service.operationStart {
                    TimelineView(.periodic(from: start, by: 0.1)) { context in
                        Text(elapsed(since: start, now: context.date))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func buttonLabel(_ title: String) -> some View {
        Text(title)
    }

    private func elapsed(since start: Date, now: Date) -> String {
        String(format: "%.1fs", max(0, now.timeIntervalSince(start)))
    }

    /// Re-check the account session; only probe the sync server once signed in.
    private func refreshSession() async {
        let signedIn = await ActivitiesClient().oauth.hasSession()
        hasAccountSession = signedIn
        if signedIn {
            await service.refreshStatus()
        }
    }

    private func syncNow() async {
        isWorking = true
        _ = await service.runSyncOnce()
        isWorking = false
    }

    private func uploadFullLog() async {
        isWorking = true
        _ = await service.uploadFullLog()
        isWorking = false
    }

    private func create() async {
        isWorking = true
        if await service.createPassphrase(passphrase) {
            passphrase = ""
            confirmPassphrase = ""
        }
        isWorking = false
    }

    private func unlock() async {
        isWorking = true
        if await service.unlock(passphrase) {
            passphrase = ""
        }
        isWorking = false
    }
}
