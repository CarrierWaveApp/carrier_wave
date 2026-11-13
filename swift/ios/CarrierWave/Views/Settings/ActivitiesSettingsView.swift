import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivitiesSettingsView

struct ActivitiesSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "person.2.fill",
                tint: .green,
                title: "Community",
                subtitle: "Friends, clubs, and the activity feed."
            )

            Section {
                Toggle("Enable community features", isOn: $activitiesEnabled)
                    .onChange(of: activitiesEnabled) { _, enabled in
                        handleActivitiesToggle(enabled: enabled)
                    }
            } header: {
                Text("Community")
            } footer: {
                Text(
                    "When enabled, your callsign is discoverable in friend search "
                        + "and you can participate in clubs."
                )
            }

            Section {
                HStack {
                    Text("Callsign")
                    Spacer()
                    Text(stationCallsign.isEmpty ? "Not Set" : stationCallsign)
                        .foregroundStyle(stationCallsign.isEmpty ? .secondary : .primary)
                }
            } header: {
                Text("Your Station")
            } footer: {
                Text("Uses your station callsign from Logger settings.")
            }

            if activitiesEnabled {
                Section {
                    if oauthVerified {
                        Label("Verified", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Sign Out", role: .destructive, action: signOutOAuth)
                    } else {
                        NavigationLink {
                            OAuthVerifyView()
                        } label: {
                            Label("Verify Callsign", systemImage: "checkmark.shield")
                        }
                    }
                } header: {
                    Text("Callsign Verification")
                } footer: {
                    Text(
                        "Verify ownership of your callsign to secure your account. "
                            + "Optional today; required in a future update."
                    )
                }
            }

            Section {
                Toggle("Share activity to feed", isOn: $shareActivities)
            } header: {
                Text("Sharing")
            } footer: {
                Text(
                    "When enabled, your milestones and session summaries appear "
                        + "in friends' activity feeds."
                )
            }

            Section {
                Toggle("Friend spot alerts", isOn: $friendSpotNotifications)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Show alerts when friends appear in POTA or RBN spots.")
            }

            if activitiesEnabled {
                Section {
                    NavigationLink {
                        SMSSpottingSettingsView()
                    } label: {
                        Label("SMS Spotting", systemImage: "message")
                    }
                } header: {
                    Text("Spotting")
                } footer: {
                    Text("Spot POTA/SOTA activations via text message when you have no data.")
                }
            }

            if activitiesEnabled {
                Section {
                    Button(role: .destructive) {
                        showingDeleteAccountConfirmation = true
                    } label: {
                        if isDeletingAccount {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Deleting...")
                            }
                        } else {
                            Label("Delete Community Account", systemImage: "trash")
                        }
                    }
                    .disabled(isDeletingAccount)
                } footer: {
                    Text(
                        "Permanently deletes your community data from the server, "
                            + "including friends and activity history."
                    )
                }
            }
        }
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await refreshOAuthStatus() } }
        .onReceive(NotificationCenter.default.publisher(for: .didCompleteOAuthVerification)) { _ in
            Task { await refreshOAuthStatus() }
        }
        .alert("Delete Community Account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text(
                "This will permanently delete your community data from the server, "
                    + "including friends and activity history. "
                    + "This cannot be undone."
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @AppStorage("loggerDefaultCallsign") private var stationCallsign = ""
    @AppStorage("activitiesServerEnabled") private var activitiesEnabled = false
    @AppStorage("friendSpotNotificationsEnabled") private var friendSpotNotifications = true
    @AppStorage("shareActivitiesEnabled") private var shareActivities = true

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var oauthVerified = false

    private var activitiesSourceURL: String {
        let override = UserDefaults.standard.string(forKey: "activitiesServerURLOverride") ?? ""
        return override.isEmpty ? "https://activities.carrierwave.app" : override
    }

    private func refreshOAuthStatus() async {
        oauthVerified = await ActivitiesClient().oauth.hasSession()
    }

    private func signOutOAuth() {
        Task {
            await ActivitiesClient().oauth.logout()
            await refreshOAuthStatus()
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await ActivitiesClient().deleteAccount()
            activitiesEnabled = false
        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func handleActivitiesToggle(enabled: Bool) {
        if enabled {
            let client = ActivitiesClient()
            guard !client.hasAuthToken(), !stationCallsign.isEmpty else {
                return
            }
            Task {
                do {
                    let uppercased = stationCallsign.uppercased()
                    _ = try await client.register(
                        callsign: uppercased,
                        deviceName: UIDevice.current.name,
                        sourceURL: activitiesSourceURL
                    )
                    UserDefaults.standard.set(
                        uppercased,
                        forKey: ActivitiesClient.registeredCallsignKey
                    )
                } catch {
                    errorMessage = "Registration failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        } else {
            ActivitiesClient().clearAuthToken()
        }
    }
}

#Preview {
    NavigationStack {
        ActivitiesSettingsView()
    }
}
