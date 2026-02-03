import SwiftUI

// MARK: - LoTWSettingsView

struct LoTWSettingsView: View {
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
                        Text(username)
                            .foregroundStyle(.secondary)
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
                    Text("Connect your LoTW account to import QSOs and QSL confirmations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Connect to LoTW") {
                        showingLogin = true
                    }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Uses your LoTW website username and password.")
                }

                Section {
                    Link(destination: URL(string: "https://lotw.arrl.org")!) {
                        Label("Visit LoTW Website", systemImage: "arrow.up.right.square")
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
                        "Re-fetches all QSOs from LoTW and updates existing records with fresh parsed values."
                    )
                }
            }
        }
        .navigationTitle("LoTW")
        .sheet(isPresented: $showingLogin) {
            LoTWLoginSheet(
                isAuthenticated: $isAuthenticated,
                storedUsername: $username,
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
    @State private var username = ""
    @State private var showingLogin = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    private let lotwClient = LoTWClient()

    private func checkStatus() {
        isAuthenticated = lotwClient.hasCredentials()
        if isAuthenticated {
            if let creds = try? lotwClient.getCredentials() {
                username = creds.username
            }
        }
    }

    private func logout() {
        lotwClient.clearCredentials()
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
            let result = try await syncService.forceRedownloadFromLoTW()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - LoTWLoginSheet

struct LoTWLoginSheet: View {
    // MARK: Internal

    @Binding var isAuthenticated: Bool
    @Binding var storedUsername: String
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your LoTW website login credentials.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Username")
                        Spacer()
                        Text(username)
                            .foregroundStyle(.secondary)
                    }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
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
                    .disabled(password.isEmpty || isValidating)
                }
            }
            .navigationTitle("LoTW Login")
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

    @State private var username = ""
    @State private var password = ""
    @State private var isValidating = false

    private let lotwClient = LoTWClient()

    private func loadProfileCallsign() {
        if let profile = UserProfileService.shared.getProfile() {
            username = profile.callsign
        }
    }

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            try await lotwClient.testCredentials(username: username, password: password)
            try lotwClient.saveCredentials(username: username, password: password)
            storedUsername = username
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
