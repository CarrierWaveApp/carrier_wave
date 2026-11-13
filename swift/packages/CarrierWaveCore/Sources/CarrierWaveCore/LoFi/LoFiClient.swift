import Foundation

// MARK: - LoFiError

public enum LoFiError: Error, LocalizedError {
    case notConfigured
    case notLinked
    case registrationFailed(String)
    case authenticationRequired
    case networkError(Error)
    case invalidResponse(String)
    case apiError(Int, String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "LoFi is not configured. Please set up your callsign."
        case .notLinked:
            "Device not linked. Please check your email to confirm."
        case let .registrationFailed(msg):
            "Registration failed: \(msg)"
        case .authenticationRequired:
            "Authentication required. Please re-register."
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(msg):
            "Invalid response: \(msg)"
        case let .apiError(code, msg):
            "API error (\(code)): \(msg)"
        }
    }
}

// MARK: - LoFiClient

public final class LoFiClient: Sendable {
    // MARK: Lifecycle

    public init(credentials: LoFiCredentialStore, logger: LoFiLogger, verbose: Bool = false) {
        self.credentials = credentials
        self.logger = logger
        self.verbose = verbose
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: Public

    /// Progress info passed to callback during sync
    public struct SyncProgressInfo: Sendable {
        // MARK: Lifecycle

        public init(
            totalQSOs: Int,
            totalOperations: Int,
            downloadedQSOs: Int,
            processedOperations: Int
        ) {
            self.totalQSOs = totalQSOs
            self.totalOperations = totalOperations
            self.downloadedQSOs = downloadedQSOs
            self.processedOperations = processedOperations
        }

        // MARK: Public

        /// Total QSOs expected (from accounts endpoint)
        public let totalQSOs: Int
        /// Total operations expected
        public let totalOperations: Int
        /// QSOs downloaded so far
        public let downloadedQSOs: Int
        /// Operations processed so far
        public let processedOperations: Int
    }

    public let credentials: LoFiCredentialStore
    public let logger: LoFiLogger
    public let verbose: Bool

    // MARK: - Configuration

    public var isConfigured: Bool {
        (try? credentials.getString(.clientKey)) != nil
            && (try? credentials.getString(.callsign)) != nil
    }

    public var isLinked: Bool {
        (try? credentials.getString(.deviceLinked)) == "true"
    }

    public var hasToken: Bool {
        (try? credentials.getString(.authToken)) != nil
    }

    public func hasCredentials() -> Bool {
        isConfigured && isLinked
    }

    public func getCallsign() -> String? {
        try? credentials.getString(.callsign)
    }

    public func getEmail() -> String? {
        try? credentials.getString(.email)
    }

    public func getLastSyncMillis() -> Int64 {
        guard let str = try? credentials.getString(.lastSyncMillis),
              let value = Int64(str)
        else {
            return 0
        }
        return value
    }

    /// Get the sync flags from the last registration, or defaults if not available
    public func getSyncFlags() -> LoFiSyncFlags {
        guard let data = try? credentials.getData(.syncFlags),
              let flags = try? JSONDecoder().decode(LoFiSyncFlags.self, from: data)
        else {
            return .defaults
        }
        return flags
    }

    /// Get the recommended interval between sync checks (in seconds)
    public func getSuggestedSyncCheckInterval() -> TimeInterval {
        TimeInterval(getSyncFlags().suggestedSyncCheckPeriod) / 1_000.0
    }

    // MARK: - Setup

    /// Configure LoFi with callsign and optional email
    /// Generates client key and secret automatically
    public func configure(callsign: String, email: String?) throws {
        let clientKey = UUID().uuidString
        let clientSecret = generateClientSecret()

        try credentials.setString(clientKey, for: .clientKey)
        try credentials.setString(clientSecret, for: .clientSecret)
        try credentials.setString(callsign.uppercased(), for: .callsign)
        if let email {
            try credentials.setString(email, for: .email)
        }
        try credentials.setString("false", for: .deviceLinked)
    }

    /// Register with LoFi and get bearer token
    public func register() async throws -> LoFiRegistrationResponse {
        guard let clientKey = try? credentials.getString(.clientKey),
              let clientSecret = try? credentials.getString(.clientSecret),
              let callsign = try? credentials.getString(.callsign)
        else {
            throw LoFiError.notConfigured
        }

        let request = LoFiRegistrationRequest(
            client: LoFiClientCredentials(key: clientKey, name: clientName, secret: clientSecret),
            account: LoFiAccountRequest(call: callsign),
            meta: LoFiMetaRequest(app: appName)
        )

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/client")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await loggedData(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.registrationFailed("\(httpResponse.statusCode) - \(body)")
        }

        let registration = try JSONDecoder().decode(LoFiRegistrationResponse.self, from: data)

        // Save the token
        try credentials.setString(registration.token, for: .authToken)

        // Store sync flags for use during sync operations
        storeSyncFlags(registration.meta.flags)

        return registration
    }

    /// Link device via email confirmation
    public func linkDevice(email: String) async throws {
        let token = try getToken()

        let request = LoFiLinkDeviceRequest(email: email)

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/client/link")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await loggedData(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        // Save the email for future reference
        try credentials.setString(email, for: .email)
    }

    /// Mark device as linked (call after user confirms email)
    public func markAsLinked() throws {
        try credentials.setString("true", for: .deviceLinked)
    }

    /// Refresh the bearer token
    public func refreshToken() async throws -> String {
        let registration = try await register()
        return registration.token
    }

    // MARK: - Clear

    /// Reset just the sync timestamp so QSOs can be re-downloaded
    public func resetSyncTimestamp() {
        try? credentials.delete(.lastSyncMillis)
    }

    public func clearCredentials() throws {
        try? credentials.delete(.authToken)
        try? credentials.delete(.clientKey)
        try? credentials.delete(.clientSecret)
        try? credentials.delete(.callsign)
        try? credentials.delete(.email)
        try? credentials.delete(.deviceLinked)
        try? credentials.delete(.lastSyncMillis)
        try? credentials.delete(.syncFlags)
    }

    // MARK: Internal

    let baseURL = "https://lofi.ham2k.net"
    let clientName = "CarrierWave"
    let appName = "CarrierWave"
    let session: URLSession

    /// Store sync flags from registration response
    func storeSyncFlags(_ flags: LoFiSyncFlags) {
        guard let data = try? JSONEncoder().encode(flags) else {
            return
        }
        try? credentials.setData(data, for: .syncFlags)
    }
}
