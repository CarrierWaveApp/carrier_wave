import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - AMTAccountSection

/// Another Morse Trainer account section for the Accounts settings tab:
/// email-link sign-in (read-only `stats:read`), the connected account and
/// practice streak, and sign-out. Drives the shared `AMTService`; the
/// PKCE/poll/refresh protocol lives in Rust, the same code Field uses.
struct AMTAccountSection: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Another Morse Trainer")
                .font(.headline)
            Text(
                "Shows your Morse practice streak on the Dashboard. "
                    + "Read-only; you can remove CW Sweep from AMT at any time."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if amt.isSignedIn {
                connected
            } else if waiting {
                waitingRow
            } else {
                signInRow
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }
        }
        .onAppear {
            amt.reloadFromStore()
            if !amt.isSignedIn, amt.pendingEmail != nil {
                waiting = true
                startPolling()
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: Private

    @State private var email = ""
    @State private var waiting = false
    @State private var isSending = false
    @State private var pollTask: Task<Void, Never>?
    @State private var status: String?
    @State private var statusIsError = false

    private var amt: AMTService {
        AMTService.shared
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var signInRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("AMT email") {
                TextField("", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit(sendLink)
            }
            HStack {
                Button(isSending ? "Sending…" : "Email Me a Sign-in Link", action: sendLink)
                    .disabled(isSending || !trimmedEmail.contains("@"))
                Text("No password — press Confirm in the email.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var waitingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Check your email")
                Text("Sent to \(amt.pendingEmail ?? trimmedEmail). Only the Confirm button signs you in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                pollTask?.cancel()
                amt.cancelPendingSignIn()
                waiting = false
            }
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Connected")
                if let account = amt.account {
                    Text(account.callsign ?? account.displayName ?? account.id)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Label("\(amt.currentStreak ?? 0) day streak", systemImage: "graduationcap.fill")
                    .foregroundStyle(.purple)
                Text("Best \(amt.longestStreak ?? 0)")
                    .foregroundStyle(.secondary)
                if let stats = amt.stats {
                    Text("\(AMTActivityFormatting.duration(seconds: Int(stats.practiceSeconds))) practised")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            HStack {
                Button("Refresh Now") {
                    Task {
                        let ok = await amt.refreshStats()
                        status = ok ? "Updated" : (amt.lastError ?? "Refresh failed")
                        statusIsError = !ok
                    }
                }
                .disabled(amt.isRefreshing)
                Button("Sign Out", role: .destructive) {
                    Task {
                        await amt.signOut()
                        status = "Signed out"
                        statusIsError = false
                    }
                }
            }
        }
    }

    private func sendLink() {
        let address = trimmedEmail
        guard address.contains("@"), !isSending else {
            return
        }
        isSending = true
        status = nil
        Task {
            defer { isSending = false }
            do {
                try await amt.startSignIn(email: address)
                waiting = true
                startPolling()
            } catch {
                status = "Couldn't send the sign-in link: \(error.localizedDescription)"
                statusIsError = true
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            do {
                let outcome = try await amt.pollForCompletion(timeoutSeconds: 16 * 60)
                guard !Task.isCancelled else {
                    return
                }
                waiting = false
                switch outcome {
                case .signedIn:
                    status = "Connected"
                    statusIsError = false
                case .timedOut:
                    amt.cancelPendingSignIn()
                    status = "We didn't see the link confirmed in time. Send a new one to try again."
                    statusIsError = true
                case .linkExpired:
                    status = "That link expired or was already used. Send a new one to try again."
                    statusIsError = true
                }
            } catch is CancellationError {
                // Cancelled by the user or the view going away.
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                waiting = false
                status = "Something went wrong finishing sign-in: \(error.localizedDescription)"
                statusIsError = true
            }
        }
    }
}
