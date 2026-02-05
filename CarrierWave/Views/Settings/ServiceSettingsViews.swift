import CarrierWaveCore
import SwiftUI

// MARK: - QRZApiKeySheet

struct QRZApiKeySheet: View {
    // MARK: Internal

    @Binding var apiKey: String
    @Binding var callsign: String?
    @Binding var isAuthenticated: Bool
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your QRZ Logbook API key from your QRZ logbook settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "https://logbook.qrz.com/logbook")!) {
                        Label("Get API key from QRZ Logbook", systemImage: "arrow.up.right.square")
                    }

                    TextField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
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
                    .disabled(apiKey.isEmpty || isValidating)
                }
            }
            .navigationTitle("QRZ API Key")
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
    @State private var isValidating = false

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            let client = QRZClient()
            let status = try await client.validateApiKey(apiKey)
            try client.saveApiKey(apiKey)
            try client.saveCallsign(status.callsign)
            // Save the bookId for this callsign (used when uploading)
            if let bookId = status.bookId {
                try client.saveBookId(bookId, for: status.callsign)
            }
            callsign = status.callsign
            isAuthenticated = true

            // Auto-populate current callsign in CallsignAliasService
            let aliasService = CallsignAliasService.shared
            if aliasService.getCurrentCallsign() == nil {
                try aliasService.saveCurrentCallsign(status.callsign)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - QRZSettingsView

struct QRZSettingsView: View {
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
                        if let callsign {
                            Text(callsign).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Status")
                }

                Section { Button("Logout", role: .destructive) { logout() } }
            } else {
                Section {
                    Text("Connect your QRZ Logbook to sync QSOs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Connect to QRZ") { showingLogin = true }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Requires QRZ XML Logbook Data subscription.")
                }

                Section {
                    Link(
                        destination: URL(
                            string: "https://shop.qrz.com/collections/subscriptions/products/"
                                + "xml-logbook-data-subscription-1-year"
                        )!
                    ) {
                        Label("Get QRZ Subscription", systemImage: "arrow.up.right.square")
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
                        "Re-fetches all QSOs from QRZ and updates existing records with fresh parsed values."
                    )
                }
            }
        }
        .navigationTitle("QRZ Logbook")
        .sheet(isPresented: $showingLogin) {
            QRZApiKeySheet(
                apiKey: $apiKey, callsign: $callsign, isAuthenticated: $isAuthenticated,
                errorMessage: $errorMessage, showingError: $showingError
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear { checkStatus() }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @State private var isAuthenticated = false
    @State private var callsign: String?
    @State private var showingLogin = false
    @State private var apiKey = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    private let qrzClient = QRZClient()

    private func checkStatus() {
        isAuthenticated = qrzClient.hasApiKey()
        callsign = qrzClient.getCallsign()
    }

    private func logout() {
        qrzClient.logout()
        checkStatus()
    }

    @MainActor
    private func forceRedownload() async {
        guard let syncService else {
            return
        }
        isRedownloading = true
        redownloadResult = nil

        do {
            let result = try await syncService.forceRedownloadFromQRZ()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }

        isRedownloading = false
    }
}

// MARK: - POTASettingsView

struct POTASettingsView: View {
    // MARK: Internal

    @ObservedObject var potaAuth: POTAAuthService

    let tourState: TourState
    var syncService: SyncService?

    var body: some View {
        List {
            if let token = potaAuth.currentToken, !token.isExpired {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        if let callsign = token.callsign {
                            Text(callsign).foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Session Expires")
                        Spacer()
                        Text(token.expiresAt, style: .relative)
                            .foregroundStyle(token.isExpiringSoon() ? .orange : .secondary)
                    }
                } header: {
                    Text("Status")
                } footer: {
                    Text("Session will auto-refresh using saved credentials.")
                }
            }

            Section {
                TextField("Email", text: $username)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Credentials")
            } footer: {
                Text("Your credentials are stored securely and used to automatically log in.")
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

            if potaAuth.isAuthenticated {
                Section {
                    Button("Logout", role: .destructive) { logout() }
                }
            }

            Section {
                Link(destination: URL(string: "https://pota.app")!) {
                    Label("Visit POTA Website", systemImage: "arrow.up.right.square")
                }
            }

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
    @State private var isTesting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    private func loadExistingCredentials() {
        if let savedUsername = potaAuth.getStoredUsername() {
            username = savedUsername
        }
        if let savedPassword = potaAuth.getStoredPassword() {
            password = savedPassword
        }
    }

    private func testLogin() async {
        isTesting = true
        defer { isTesting = false }

        do {
            // Try to login with entered credentials
            _ = try await potaAuth.performHeadlessLogin(username: username, password: password)

            // Login succeeded - save credentials
            try potaAuth.saveCredentials(username: username, password: password)

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
