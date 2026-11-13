import CarrierWaveData
import SwiftUI

// MARK: - EQSLSettingsView

struct EQSLSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack {
                        Label(
                            "Connected",
                            systemImage: "checkmark.circle.fill"
                        )
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
                    Text(
                        "Connect your eQSL account to upload QSOs "
                            + "and download confirmations."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button("Connect to eQSL") {
                        showingLogin = true
                    }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Uses your eQSL.cc username and password.")
                }

                Section {
                    Link(
                        destination: URL(string: "https://www.eqsl.cc")!
                    ) {
                        Label(
                            "Visit eQSL Website",
                            systemImage: "arrow.up.right.square"
                        )
                    }
                }
            }
        }
        .navigationTitle("eQSL")
        .sheet(isPresented: $showingLogin) {
            EQSLLoginSheet(
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

    @State private var isAuthenticated = false
    @State private var username = ""
    @State private var showingLogin = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private let eqslClient = EQSLClient()

    private func checkStatus() {
        isAuthenticated = eqslClient.hasCredentials()
        if isAuthenticated {
            if let creds = try? eqslClient.getCredentials() {
                username = creds.username
            }
        }
    }

    private func logout() {
        eqslClient.clearCredentials()
        checkStatus()
    }
}

// MARK: - EQSLLoginSheet

struct EQSLLoginSheet: View {
    // MARK: Internal

    @Binding var isAuthenticated: Bool
    @Binding var storedUsername: String
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your eQSL.cc login credentials.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

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
                    .disabled(
                        username.isEmpty || password.isEmpty || isValidating
                    )
                }
            }
            .navigationTitle("eQSL Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isValidating = false

    private let eqslClient = EQSLClient()

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            try await eqslClient.testCredentials(
                username: username, password: password
            )
            try eqslClient.saveCredentials(
                username: username, password: password
            )
            storedUsername = username
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
