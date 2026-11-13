import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - AMTSettingsView

/// Another Morse Trainer: email-link sign-in (read-only `stats:read`), the
/// connected account, the practice streak, and sign-out. Drives the shared
/// `AMTService`; the PKCE/poll/refresh protocol lives in Rust. There is no
/// password: the user types their AMT email, presses Confirm in the email,
/// and this screen finishes by polling.
struct AMTSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "graduationcap.fill",
                tint: ActivityGridColors.amtPractice,
                title: "Another Morse Trainer",
                subtitle: "Show your Morse practice streak and practice days alongside your QSOs. "
                    + "Read-only; you can remove Carrier Wave from AMT at any time."
            )

            if amt.isSignedIn {
                connectedSection
                streakSection
                dashboardSection
                signOutSection
            } else if phase == .waiting || amt.pendingEmail != nil {
                waitingSection
            } else {
                signInSection
            }
        }
        .navigationTitle("Another Morse Trainer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            amt.reloadFromStore()
            if !amt.isSignedIn, amt.pendingEmail != nil {
                // A link was sent before the app was closed — keep waiting.
                phase = .waiting
                startPolling()
            }
        }
        .onDisappear { pollTask?.cancel() }
        .alert("Couldn't Sign In", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    private enum Phase: Equatable {
        case entry
        case waiting
    }

    @AppStorage("dashboardMetric2") private var dashboardMetric2 =
        DashboardMetricType.activation.rawValue
    @AppStorage("dashboardMetric1") private var dashboardMetric1 =
        DashboardMetricType.onAir.rawValue

    @State private var email = ""
    @State private var phase: Phase = .entry
    @State private var isSending = false
    @State private var pollTask: Task<Void, Never>?
    @State private var showingError = false
    @State private var errorMessage = ""

    private var amt: AMTService {
        AMTService.shared
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsOnDashboard: Bool {
        dashboardMetric1 == DashboardMetricType.amtPractice.rawValue
            || dashboardMetric2 == DashboardMetricType.amtPractice.rawValue
    }

    // MARK: Sign-in

    private var signInSection: some View {
        Section {
            TextField("AMT account email", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .submitLabel(.send)
                .onSubmit(sendLink)

            Button(action: sendLink) {
                if isSending {
                    HStack {
                        ProgressView()
                        Text("Sending…").padding(.leading, 4)
                    }
                } else {
                    Text("Email Me a Sign-in Link")
                }
            }
            .disabled(isSending || trimmedEmail.isEmpty || !trimmedEmail.contains("@"))
        } header: {
            Text("Sign In")
        } footer: {
            Text(
                "AMT emails you a link that works for 15 minutes. Open it and press Confirm; "
                    + "this screen finishes automatically. Carrier Wave never sees your password or email address."
            )
        }
    }

    private var waitingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check your email")
                        .font(.headline)
                    Text("Sent to \(amt.pendingEmail ?? trimmedEmail). Press Confirm in the email.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Button("Cancel", role: .cancel) {
                pollTask?.cancel()
                amt.cancelPendingSignIn()
                phase = .entry
            }
        } footer: {
            Text("Opening the link alone does nothing — only the Confirm button signs you in.")
        }
    }

    // MARK: Connected

    private var connectedSection: some View {
        Section {
            HStack {
                Label("Connected", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
                if let account = amt.account {
                    Text(account.callsign ?? account.displayName ?? "AMT account")
                        .foregroundStyle(.secondary)
                }
            }
            if let account = amt.account, let name = account.displayName, account.callsign != nil {
                LabeledContent("Name", value: name)
            }
        } header: {
            Text("Account")
        }
    }

    private var streakSection: some View {
        Section {
            if let streak = amt.streakInfo {
                StreakRow(streak: streak)
                if let stats = amt.stats {
                    LabeledContent(
                        "Practice",
                        value: AMTActivityFormatting.duration(seconds: Int(stats.practiceSeconds))
                    )
                    LabeledContent("Sessions", value: "\(stats.sessions)")
                    LabeledContent("Practice days", value: "\(stats.activity.count)")
                    if let accuracy = stats.accuracy {
                        LabeledContent("Accuracy", value: accuracy.formatted(.percent.precision(.fractionLength(0))))
                    }
                }
            } else {
                Text("No practice stats yet.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await amt.refreshStats() }
            } label: {
                HStack {
                    Text("Refresh Now")
                    Spacer()
                    if amt.isRefreshing {
                        ProgressView()
                    }
                }
            }
            .disabled(amt.isRefreshing)
        } header: {
            Text("Practice")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let fetched = amt.stats?.fetchedAt, fetched > 0 {
                    Text("Checked \(Date(timeIntervalSince1970: TimeInterval(fetched)), style: .relative) ago.")
                }
                if let updated = amt.stats?.updatedAt, updated > 0 {
                    let synced = Date(timeIntervalSince1970: TimeInterval(updated) / 1_000)
                    Text("AMT last synced \(synced, style: .relative) ago.")
                }
                if let error = amt.lastError {
                    Text(error).foregroundStyle(.red)
                }
                Text(
                    "Stats refresh when you open the dashboard or return to the app. "
                        + "They stay at zero until your AMT apps start syncing."
                )
            }
        }
    }

    private var dashboardSection: some View {
        Section {
            Toggle("Show Streak on Dashboard", isOn: Binding(
                get: { showsOnDashboard },
                set: { on in
                    if on {
                        dashboardMetric2 = DashboardMetricType.amtPractice.rawValue
                    } else if dashboardMetric2 == DashboardMetricType.amtPractice.rawValue {
                        dashboardMetric2 = DashboardMetricType.activation.rawValue
                    } else if dashboardMetric1 == DashboardMetricType.amtPractice.rawValue {
                        dashboardMetric1 = DashboardMetricType.onAir.rawValue
                    }
                }
            ))
        } footer: {
            Text(
                "Uses the second slot of the Streaks card. Change either slot under Dashboard Metrics. "
                    + "Practice days always appear in the activity grid in purple."
            )
        }
    }

    private var signOutSection: some View {
        Section {
            Button("Sign Out of AMT", role: .destructive) {
                Task { await amt.signOut() }
            }
        } footer: {
            Text("Removes Carrier Wave from your AMT devices and forgets the cached stats on this device.")
        }
    }

    private func sendLink() {
        let address = trimmedEmail
        guard !address.isEmpty, !isSending else {
            return
        }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await amt.startSignIn(email: address)
                phase = .waiting
                startPolling()
            } catch {
                errorMessage = "Couldn't send the sign-in link: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            do {
                // Links live 15 minutes; poll a little past that.
                let outcome = try await amt.pollForCompletion(timeoutSeconds: 16 * 60)
                guard !Task.isCancelled else {
                    return
                }
                switch outcome {
                case .signedIn:
                    phase = .entry
                case .timedOut:
                    amt.cancelPendingSignIn()
                    phase = .entry
                    errorMessage = "We didn't see the link confirmed in time. Send a new one to try again."
                    showingError = true
                case .linkExpired:
                    phase = .entry
                    errorMessage = "That link expired or was already used. Send a new one to try again."
                    showingError = true
                }
            } catch is CancellationError {
                // User left / cancelled.
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                phase = .entry
                errorMessage = "Something went wrong finishing sign-in: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}
