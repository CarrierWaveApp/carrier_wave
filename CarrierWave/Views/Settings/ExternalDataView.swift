// External Data View
//
// Shows status of externally downloaded data caches like
// POTA parks database with refresh controls.

import CarrierWaveCore
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
            potaParksSection
        }
        .navigationTitle("External Data")
        .task {
            await loadStatus()
        }
    }

    // MARK: Private

    @State private var parksStatus: POTAParksCacheStatus = .notLoaded
    @State private var isRefreshing = false

    // MARK: - POTA Parks Section

    private var potaParksSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("POTA Parks", systemImage: "tree")
                        .font(.headline)

                    Spacer()

                    statusBadge
                }

                statusDetail

                if case .loaded = parksStatus {
                    HStack {
                        Button {
                            Task { await refreshParks() }
                        } label: {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Refresh Now", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshing)

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Cached Data")
        } footer: {
            Text(
                "Park names are downloaded from pota.app and refreshed automatically every two weeks."
            )
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch parksStatus {
        case .notLoaded:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .loading,
             .downloading:
            ProgressView()
                .controlSize(.small)
        case .loaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch parksStatus {
        case .notLoaded:
            Text("Not downloaded")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .loading:
            Text("Loading from cache...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading parks database...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case let .loaded(parkCount, downloadedAt):
            VStack(alignment: .leading, spacing: 4) {
                Text("\(parkCount.formatted()) parks")
                    .font(.subheadline)

                if let date = downloadedAt {
                    HStack(spacing: 4) {
                        Text("Downloaded")
                        Text(date, style: .relative)
                        Text("ago")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if isStale(date) {
                        Text("Refresh recommended")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

        case let .failed(error):
            VStack(alignment: .leading, spacing: 4) {
                Text("Download failed")
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    Task { await refreshParks() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func isStale(_ date: Date) -> Bool {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        return date < twoWeeksAgo
    }

    private func loadStatus() async {
        parksStatus = await POTAParksCache.shared.getStatus()

        // If not loaded yet, ensure it loads
        if case .notLoaded = parksStatus {
            await POTAParksCache.shared.ensureLoaded()
            parksStatus = await POTAParksCache.shared.getStatus()
        }
    }

    private func refreshParks() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await POTAParksCache.shared.forceRefresh()
        } catch {
            // Status will be updated by the cache
        }

        parksStatus = await POTAParksCache.shared.getStatus()
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
                    TextField("Username or Callsign", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Enter your QRZ.com username and password.")
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
        .navigationTitle("QRZ Callbook")
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
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzCallbookSessionKey)
        isAuthenticated = false
        savedUsername = nil
    }

    private func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let sessionKey = try await authenticateWithQRZ(username: username, password: password)
            try saveCredentials(username: username, password: password, sessionKey: sessionKey)
            savedUsername = username
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

    private func saveCredentials(username: String, password: String, sessionKey: String) throws {
        try KeychainHelper.shared.save(username, for: KeychainHelper.Keys.qrzCallbookUsername)
        try KeychainHelper.shared.save(password, for: KeychainHelper.Keys.qrzCallbookPassword)
        try KeychainHelper.shared.save(sessionKey, for: KeychainHelper.Keys.qrzCallbookSessionKey)
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
