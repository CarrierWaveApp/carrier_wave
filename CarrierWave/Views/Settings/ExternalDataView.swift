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
    var body: some View {
        List {
            SCPCacheSection()
            POTACacheSection()
            SOTACacheSection()
            WWFFCacheSection()
        }
        .navigationTitle("External Data")
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
            let normalizedUsername = username.uppercased()
            let sessionKey = try await authenticateWithQRZ(
                username: normalizedUsername, password: password
            )
            try saveCredentials(
                username: normalizedUsername, password: password, sessionKey: sessionKey
            )
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
