// External Data View
//
// Shows status of externally downloaded data caches like
// POTA parks and SOTA summits databases with refresh controls.

import CarrierWaveData
import SwiftUI

// MARK: - QRZCallbookError

enum QRZCallbookError: LocalizedError {
    case invalidURL
    case serverError
    case invalidResponse
    case apiError(String)
    case loginFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .serverError:
            "Server error. Please try again."
        case .invalidResponse:
            "Invalid response from server"
        case let .apiError(message):
            message
        case .loginFailed:
            "Login failed. Check your credentials."
        }
    }
}

// MARK: - ExternalDataView

struct ExternalDataView: View {
    // MARK: Internal

    var body: some View {
        List {
            if needsRecovery {
                recoverySection
            }

            Section {
                Button {
                    Task { await downloadAll() }
                } label: {
                    HStack(spacing: 12) {
                        if isDownloadingAll {
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading All Sources…")
                        } else {
                            Label("Download All Sources", systemImage: "arrow.down.circle")
                        }
                        Spacer()
                    }
                }
                .disabled(isDownloadingAll)
            } footer: {
                Text("Refresh every cached database below in parallel.")
            }

            FCCCacheSection()
            SCPCacheSection()
            EquipmentCatalogCacheSection()
            POTACacheSection()
            SOTACacheSection()
            SOTAZonesCacheSection()
            WWFFCacheSection()
            ContestsCacheSection()
        }
        .id(refreshTrigger)
        .navigationTitle("External Data")
        .task {
            needsRecovery = await recovery.storeNeedsRecovery()
            hasRecoveryBlob = CwStoreKeyRecovery.hasRecoveryBlob
        }
        .sheet(isPresented: $showRecoverySheet) {
            CwStoreRecoverySheet { recovered in
                showRecoverySheet = false
                if recovered {
                    Task {
                        needsRecovery = await recovery.storeNeedsRecovery()
                        refreshTrigger += 1
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var isDownloadingAll = false
    @State private var refreshTrigger = 0
    @State private var needsRecovery = false
    @State private var hasRecoveryBlob = false
    @State private var showRecoverySheet = false

    private var recovery = CwStoreRecoveryService.shared

    private var recoverySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Local database can't be opened", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(
                    "The encrypted on-device database is unreadable, so downloads "
                        + "below can't be saved. Your logbook is safe — it's stored separately. "
                        + "Rebuilding recreates the database from your logbook; the old file is "
                        + "kept, never deleted."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                switch recovery.state {
                case .rebuilding:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Rebuilding…").font(.subheadline)
                    }
                case .done:
                    Label("Database rebuilt from your logbook.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                case let .failed(message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    recoveryActions
                case .idle:
                    recoveryActions
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var recoveryActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasRecoveryBlob {
                Button {
                    showRecoverySheet = true
                } label: {
                    Label("Recover with Passphrase", systemImage: "key.horizontal")
                }
                .buttonStyle(.borderedProminent)

                Text("Uses your sync passphrase — recovers the original database, offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                Task {
                    await recovery.rebuildFromSwiftData()
                    needsRecovery = await recovery.storeNeedsRecovery()
                    refreshTrigger += 1
                }
            } label: {
                Label("Rebuild from Logbook", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
        }
    }

    private func downloadAll() async {
        isDownloadingAll = true
        defer {
            isDownloadingAll = false
            refreshTrigger += 1
        }

        async let fcc: Void = FCCLookupService.shared.forceRefresh()
        async let scp: Void = SCPService.shared.forceRefresh()
        async let equipment: Void = EquipmentCatalogService.shared.forceRefresh()
        async let pota: Void = refreshPOTA()
        async let sota: Void = refreshSOTA()
        async let sotaZones: Void = refreshSOTAZones()
        async let wwff: Void = refreshWWFF()
        async let contests: Void = ContestDefinitionsRefresher().refresh()

        _ = await (fcc, scp, equipment, pota, sota, sotaZones, wwff, contests)
    }

    private func refreshPOTA() async {
        try? await POTAParksCache.shared.forceRefresh()
    }

    private func refreshSOTA() async {
        try? await SOTASummitsCache.shared.forceRefresh()
    }

    private func refreshSOTAZones() async {
        await SOTASummitsCache.shared.ensureLoaded()
        try? await SOTAZonesCache.shared.forceRefresh()
    }

    private func refreshWWFF() async {
        try? await WWFFReferencesCache.shared.forceRefresh()
    }
}

// MARK: - QRZCallbookSettingsView

struct QRZCallbookSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        if let username = savedUsername {
                            Text(username)
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
                    TextField("Callsign", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Enter your QRZ.com callsign and password.")
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        if isLoggingIn {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Login")
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
                }

                Section {
                    Link(
                        destination: URL(
                            string: "https://shop.qrz.com/collections/subscriptions/"
                                + "xml-logbook-data-subscription-1-year"
                        )!
                    ) {
                        Label("Get QRZ XML Subscription", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Requires QRZ XML Logbook Data subscription for callsign lookups.")
                }
            }
        }
        .navigationTitle("QRZ Callsign Lookup")
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
    @State private var savedUsername: String?
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private func checkStatus() {
        savedUsername = try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.qrzCallbookUsername
        )
        isAuthenticated =
            savedUsername != nil
                && (try? KeychainHelper.shared.readString(
                    for: KeychainHelper.Keys.qrzCallbookPassword
                )) != nil
    }

    private func logout() {
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzCallbookUsername)
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzCallbookPassword)
        // Legacy: no longer written, but clear any session key persisted by
        // older builds (lookups now run through QrzApi's own session).
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzCallbookSessionKey)
        isAuthenticated = false
        savedUsername = nil
        NotificationCenter.default.post(name: .qrzCallbookCredentialsChanged, object: nil)
    }

    private func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let normalizedUsername = username.uppercased()
            // Validates the credentials (throws on bad login). The returned
            // session key is no longer persisted — QRZ lookups run through the
            // shared `QrzApi`, which manages its own session.
            _ = try await authenticateWithQRZ(
                username: normalizedUsername, password: password
            )
            try saveCredentials(username: normalizedUsername, password: password)
            savedUsername = normalizedUsername
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func authenticateWithQRZ(username: String, password: String) async throws -> String {
        guard var urlComponents = URLComponents(string: "https://xmldata.qrz.com/xml/current/")
        else {
            throw QRZCallbookError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "agent", value: "CarrierWave"),
        ]

        guard let url = urlComponents.url else {
            throw QRZCallbookError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw QRZCallbookError.serverError
        }

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw QRZCallbookError.invalidResponse
        }

        if let errorMsg = parseXMLValue(from: xmlString, tag: "Error") {
            throw QRZCallbookError.apiError(errorMsg)
        }

        guard let sessionKey = parseXMLValue(from: xmlString, tag: "Key") else {
            throw QRZCallbookError.loginFailed
        }

        return sessionKey
    }

    private func saveCredentials(username: String, password: String) throws {
        try KeychainHelper.shared.save(username, for: KeychainHelper.Keys.qrzCallbookUsername)
        try KeychainHelper.shared.save(password, for: KeychainHelper.Keys.qrzCallbookPassword)
        NotificationCenter.default.post(name: .qrzCallbookCredentialsChanged, object: nil)
    }

    private func parseXMLValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)
              ),
              let range = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[range])
    }
}

#Preview {
    NavigationStack {
        ExternalDataView()
    }
}

#Preview("QRZ Callbook") {
    NavigationStack {
        QRZCallbookSettingsView()
    }
}
