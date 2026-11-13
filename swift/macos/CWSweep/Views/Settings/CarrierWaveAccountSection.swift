import SwiftUI

// MARK: - CarrierWaveAccountSection

/// Settings → Accounts → "Carrier Wave Account": sign in with a magic link
/// (callsign + optional email), wait for the click, or sign out. The account
/// is what Carrier Wave Sync keys its tenant on, so this is the first step
/// of enabling sync on the Mac.
struct CarrierWaveAccountSection: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Carrier Wave Account")
                .font(.headline)
            if account.isSignedIn {
                signedInRows
            } else {
                switch account.phase {
                case .waiting:
                    waitingRows
                case .idle,
                     .sending,
                     .failed:
                    entryRows
                }
            }
        }
        .task {
            await account.refresh()
            if callsign.isEmpty {
                callsign = myCallsign.uppercased()
            }
        }
    }

    // MARK: Private

    @AppStorage("myCallsign") private var myCallsign = ""
    @State private var callsign = ""
    @State private var email = ""

    private var account = AccountService.shared

    @ViewBuilder
    private var signedInRows: some View {
        LabeledContent("Status") {
            Label("Signed in to \(account.server)", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
        if let accountID = account.accountID {
            LabeledContent("Account") {
                Text(accountID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        Button("Sign Out") {
            Task { await account.signOut() }
        }
    }

    @ViewBuilder
    private var waitingRows: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Check your email and click the sign-in link. This finishes automatically.")
                .foregroundStyle(.secondary)
        }
        Button("Cancel") {
            account.cancel()
        }
    }

    @ViewBuilder
    private var entryRows: some View {
        TextField("Callsign", text: $callsign)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
        TextField("Email (only if your callsign has no published address)", text: $email)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
        HStack {
            Button(account.phase == .sending ? "Sending…" : "Send Sign-in Link") {
                account.requestLink(callsign: callsign, email: email)
            }
            .disabled(account.phase == .sending || callsign.trimmingCharacters(in: .whitespaces).isEmpty)
            if account.phase == .sending {
                ProgressView()
                    .controlSize(.small)
            }
        }
        if case let .failed(message) = account.phase {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        Text("We email a sign-in link to your callsign's published address. Signing in links this Mac "
            + "to your Carrier Wave account, which Carrier Wave Sync uses.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
