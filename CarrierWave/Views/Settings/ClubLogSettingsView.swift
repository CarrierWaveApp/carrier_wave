import SwiftUI

// MARK: - ClubLogSettingsView

struct ClubLogSettingsView: View {
    // MARK: Internal

    var syncService: SyncService?

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        if let callsign = storedCallsign {
                            Text(callsign)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    Button("Logout", role: .destructive) {
                        logout()
                    }
                }
            } else {
                Section {
                    Text("Connect your Club Log account to sync QSOs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Connect to Club Log") {
                        showingLogin = true
                    }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Requires a Club Log account with an Application Password.")
                }

                Section {
                    Link(destination: URL(string: "https://clublog.org")!) {
                        Label("Visit Club Log Website", systemImage: "arrow.up.right.square")
                    }
                }
            }

            if debugMode, isAuthenticated, syncService != nil {
                Section {
                    Button {
                        Task { await forceRedownload() }
                    } label: {
                        if isRedownloading {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Re-downloading...")
                            }
                        } else {
                            Text("Force Re-download All QSOs")
                        }
                    }
                    .disabled(isRedownloading)

                    if let result = redownloadResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text(
                        "Re-fetches all QSOs from Club Log and updates existing records."
                    )
                }
            }
        }
        .navigationTitle("Club Log")
        .sheet(isPresented: $showingLogin) {
            ClubLogLoginSheet(
                isAuthenticated: $isAuthenticated,
                storedCallsign: $storedCallsign,
                errorMessage: $errorMessage,
                showingError: $showingError
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            checkStatus()
        }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @State private var isAuthenticated = false
    @State private var storedCallsign: String?
    @State private var showingLogin = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    private let clublogClient = ClubLogClient()

    private func checkStatus() {
        isAuthenticated = clublogClient.isConfigured
        storedCallsign = clublogClient.getCallsign()
    }

    private func logout() {
        clublogClient.logout()
        checkStatus()
    }

    private func forceRedownload() async {
        guard let syncService else {
            return
        }
        isRedownloading = true
        redownloadResult = nil
        defer { isRedownloading = false }

        do {
            let result = try await syncService.syncClubLog(forceFullSync: true)
            redownloadResult = "Downloaded \(result.downloaded), Uploaded \(result.uploaded)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - ClubLogLoginSheet

struct ClubLogLoginSheet: View {
    // MARK: Internal

    @Binding var isAuthenticated: Bool
    @Binding var storedCallsign: String?
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Enter your Club Log email, Application Password, "
                            + "callsign, and API key."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    SecureField("App Password", text: $password)
                        .textContentType(.password)

                    TextField("Callsign", text: $callsign)
                        .autocapitalization(.allCharacters)
                        .autocorrectionDisabled()

                    TextField("API Key", text: $apiKey)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } footer: {
                    Text(
                        "Use your Application Password from Club Log Settings, "
                            + "not your main account password."
                    )
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        if isValidating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(
                        email.isEmpty || password.isEmpty
                            || callsign.isEmpty || apiKey.isEmpty || isValidating
                    )
                }
            }
            .navigationTitle("Club Log Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                loadProfileCallsign()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var callsign = ""
    @State private var apiKey = ""
    @State private var isValidating = false

    private let clublogClient = ClubLogClient()

    private func loadProfileCallsign() {
        if let profile = UserProfileService.shared.getProfile() {
            callsign = profile.callsign
        }
    }

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            try await clublogClient.validateCredentials(
                email: email, password: password, callsign: callsign
            )
            try clublogClient.saveCredentials(
                email: email, password: password, callsign: callsign
            )
            try clublogClient.saveApiKey(apiKey)

            // Auto-populate current callsign if not set
            let aliasService = CallsignAliasService.shared
            if aliasService.getCurrentCallsign() == nil {
                try aliasService.saveCurrentCallsign(callsign.uppercased())
            }

            storedCallsign = callsign.uppercased()
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
