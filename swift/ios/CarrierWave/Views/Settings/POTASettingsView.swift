import CarrierWaveData
import SwiftUI

// MARK: - POTASettingsView

struct POTASettingsView: View {
    // MARK: Internal

    var potaAuth: POTAAuthService

    let tourState: TourState
    var syncService: SyncService?

    var body: some View {
        List {
            if potaAuth.credentialsVerified {
                Section {
                    Label("Verified", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } header: {
                    Text("Status")
                } footer: {
                    Text("Credentials confirmed by a successful login. Sync signs in automatically.")
                }
            }

            Section {
                TextField("Email", text: $username)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .onChange(of: username) { invalidateVerificationIfEdited() }

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onChange(of: password) { invalidateVerificationIfEdited() }
            } header: {
                Text("Credentials")
            } footer: {
                Text(
                    "Enter your pota.app email and password — not a Google, Apple, or other " +
                        "external login. If you signed up with an external service, create a " +
                        "pota.app account at pota.app using the same email address."
                )
            }

            Section {
                Button {
                    Task { await testLogin() }
                } label: {
                    if isTesting {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Testing...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Test Login")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(username.isEmpty || password.isEmpty || isTesting)
            }

            if potaAuth.credentialsVerified || potaAuth.isConfigured {
                Section {
                    Button("Logout", role: .destructive) { logout() }
                }
            }

            Section {
                Link(destination: URL(string: "https://pota.app")!) {
                    Label("Visit POTA Website", systemImage: "arrow.up.right.square")
                }
            }

            SetupGuideSection(pages: MiniTourContent.potaAccountSetup)

            if debugMode, potaAuth.isAuthenticated, syncService != nil {
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
                        "Re-fetches all QSOs from POTA and updates existing records with fresh parsed values."
                    )
                }
            }
        }
        .navigationTitle("POTA")
        .onAppear { loadExistingCredentials() }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {}
        } message: {
            Text("Login successful! Credentials saved.")
        }
        .miniTour(.potaAccountSetup, tourState: tourState)
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @State private var username = ""
    @State private var password = ""
    @State private var loadedUsername = ""
    @State private var loadedPassword = ""
    @State private var isTesting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    /// Clears verification once the user edits either field away from the loaded credentials.
    private func invalidateVerificationIfEdited() {
        if username != loadedUsername || password != loadedPassword {
            potaAuth.credentialsVerified = false
        }
    }

    private func loadExistingCredentials() {
        if let savedUsername = potaAuth.getStoredUsername() {
            username = savedUsername
            loadedUsername = savedUsername
        }
        if let savedPassword = potaAuth.getStoredPassword() {
            password = savedPassword
            loadedPassword = savedPassword
        }
    }

    private func testLogin() async {
        isTesting = true
        defer { isTesting = false }

        do {
            // Verify credentials without storing a token; success sets credentialsVerified.
            _ = try await potaAuth.performHeadlessLogin(
                username: username, password: password, persist: false
            )

            // Login succeeded - save credentials so sync can sign in automatically.
            try potaAuth.saveCredentials(username: username, password: password)
            loadedUsername = username
            loadedPassword = password

            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func logout() {
        potaAuth.logout()
        username = ""
        password = ""
        loadedUsername = ""
        loadedPassword = ""
    }

    @MainActor
    private func forceRedownload() async {
        guard let syncService else {
            return
        }
        isRedownloading = true
        redownloadResult = nil

        do {
            let result = try await syncService.forceRedownloadFromPOTA()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }

        isRedownloading = false
    }
}
