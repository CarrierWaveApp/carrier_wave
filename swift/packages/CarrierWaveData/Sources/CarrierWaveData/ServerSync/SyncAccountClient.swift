import Foundation

// MARK: - SyncAccountError

public enum SyncAccountError: LocalizedError {
    case notAuthenticated
    case invalidServerURL
    case invalidResponse(String)
    case networkError(Error)
    case serverError(Int, String?)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Carrier Wave Sync requires a signed-in account."
        case .invalidServerURL:
            "The server address is invalid."
        case let .invalidResponse(detail):
            "Unexpected response from the server: \(detail)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .serverError(status, message):
            "Server error \(status)\(message.map { ": \($0)" } ?? "")"
        }
    }
}

// MARK: - SyncAccountClient

/// The slice of the activities-server API that Carrier Wave Sync needs on every
/// platform: an account-backed bearer token and the passphrase-escrow endpoint.
/// The E2E sync data key is escrowed on the server wrapped by an Argon2id KEK
/// derived from the user's sync passphrase; the server stores opaque bytes it
/// cannot read, so only a device that knows the passphrase can unwrap it.
public final class SyncAccountClient: Sendable {
    // MARK: Lifecycle

    public init(baseURL: String? = nil, oauth: OAuthClient? = nil) {
        self.baseURL = ActivitiesServer.normalizeBase(baseURL ?? ActivitiesServer.resolvedBaseURL)
        self.oauth = oauth ?? OAuthClient(baseURL: self.baseURL)
    }

    // MARK: Public

    public let baseURL: String
    public let oauth: OAuthClient

    /// Whether this device holds an account session.
    public func hasSession() async -> Bool {
        await oauth.hasSession()
    }

    /// Token for `/v1/sync/*` routes, which require an account-backed OAuth
    /// session (verified via a magic-link email) — the server rejects legacy
    /// device tokens there with 403 ACCOUNT_REQUIRED. Nil when the user hasn't
    /// signed in yet.
    public func syncAuthToken() async -> String? {
        guard await oauth.hasSession() else {
            return nil
        }
        return try? await oauth.validAccessToken()
    }

    /// Escrow the passphrase-wrapped data key on the server. `kdfParamsJSON` is
    /// the raw JSON object string produced by `createSyncEscrow`; it is spliced
    /// back in as an object (not a string) so the server stores structured
    /// `kdfParams`.
    public func putSyncKey(wrappedKeyB64: String, kdfParamsJSON: String) async throws {
        guard let token = await syncAuthToken() else {
            throw SyncAccountError.notAuthenticated
        }
        var request = try buildRequest(path: "/v1/sync/key", method: "PUT", authToken: token)
        let kdfObject = try JSONSerialization.jsonObject(with: Data(kdfParamsJSON.utf8))
        let body: [String: Any] = ["wrappedKey": wrappedKeyB64, "kdfParams": kdfObject]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }

    /// Fetch the escrowed key blob, or `nil` if none has been stored (404).
    public func getSyncKey() async throws -> SyncKeyBlob? {
        guard let token = await syncAuthToken() else {
            throw SyncAccountError.notAuthenticated
        }
        let request = try buildRequest(path: "/v1/sync/key", method: "GET", authToken: token)
        let (data, response) = try await performRequest(request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }
        try validateResponse(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wrapped = object["wrappedKey"] as? String,
              let kdf = object["kdfParams"]
        else {
            throw SyncAccountError.invalidResponse("Malformed sync key blob")
        }
        let kdfData = try JSONSerialization.data(withJSONObject: kdf)
        guard let kdfJSON = String(bytes: kdfData, encoding: .utf8) else {
            throw SyncAccountError.invalidResponse("Malformed sync key blob")
        }
        return SyncKeyBlob(wrappedKeyB64: wrapped, kdfParamsJSON: kdfJSON)
    }

    // MARK: Private

    private func buildRequest(path: String, method: String, authToken: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw SyncAccountError.invalidServerURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw SyncAccountError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SyncAccountError.invalidResponse("Not an HTTP response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
                ?? String(data: data, encoding: .utf8)
            throw SyncAccountError.serverError(http.statusCode, message)
        }
    }
}

// MARK: - SyncKeyBlob

/// The escrowed, passphrase-wrapped data key as stored on the server.
public struct SyncKeyBlob: Equatable, Sendable {
    // MARK: Lifecycle

    public init(wrappedKeyB64: String, kdfParamsJSON: String) {
        self.wrappedKeyB64 = wrappedKeyB64
        self.kdfParamsJSON = kdfParamsJSON
    }

    // MARK: Public

    public let wrappedKeyB64: String
    public let kdfParamsJSON: String
}
