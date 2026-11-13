import Foundation
import OSLog

// MARK: - RegistryListEntry

/// Summary row returned from `GET /v1/macros`.
public struct RegistryListEntry: Codable, Sendable, Identifiable {
    public enum CodingKeys: String, CodingKey {
        case slug
        case name
        case icon
        case description
        case tags
        case appliesTo = "applies_to"
        case format
        case version
        case authorCallsign = "author_callsign"
        case publishedAt = "published_at"
    }

    public let slug: String
    public let name: String
    public let icon: String?
    public let description: String?
    public let tags: [String]
    public let appliesTo: [String]
    public let format: Int
    public let version: Int
    public let authorCallsign: String?
    public let publishedAt: Date

    public var id: String {
        slug
    }
}

// MARK: - RegistryListResponse

public struct RegistryListResponse: Codable, Sendable {
    public let entries: [RegistryListEntry]
}

// MARK: - RegistryMacroDocument

/// Full `GET /v1/macros/:slug` payload. Server returns a server-shaped
/// `spec` object — `toRadioMacroDocument()` adapts it to the local
/// `RadioMacroDocument` shape used by the importer.
public struct RegistryMacroDocument: Codable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case slug
        case spec
        case format
        case version
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
        case authorCallsign = "author_callsign"
    }

    public let slug: String
    public let spec: RegistryMacroSpec
    public let format: Int
    public let version: Int
    public let publishedAt: Date
    public let updatedAt: Date
    public let authorCallsign: String?
}

// MARK: - RegistryMacroSpec

public struct RegistryMacroSpec: Codable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case name
        case icon
        case description
        case tags
        case appliesTo = "applies_to"
        case capabilities
        case args
        case steps
    }

    public let name: String
    public let icon: String?
    public let description: String?
    public let tags: [String]
    public let appliesTo: [String]
    public let capabilities: RadioMacroCapabilities
    /// Raw JSON value preserved through the wire round-trip; the importer
    /// re-decodes these into `[RadioMacroArg]` / `[RadioMacroStep]` so we
    /// don't have to keep two parallel decoders in sync.
    public let args: [RadioMacroArg]
    public let steps: [RadioMacroStep]
}

// MARK: - RegistryVersionInfo

public struct RegistryVersionInfo: Codable, Sendable, Hashable {
    // MARK: Lifecycle

    public init(version: Int, format: Int) {
        self.version = version
        self.format = format
    }

    // MARK: Public

    public let version: Int
    public let format: Int
}

// MARK: - RegistryTombstoneEntry

public struct RegistryTombstoneEntry: Codable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case slug
        case reason
        case tombstonedAt = "tombstoned_at"
    }

    public let slug: String
    public let reason: String
    public let tombstonedAt: Date
}

// MARK: - RegistryTombstonesResponse

public struct RegistryTombstonesResponse: Codable, Sendable {
    public let entries: [RegistryTombstoneEntry]
}

// MARK: - RegistryRunEventBody

public struct RegistryRunEventBody: Codable, Sendable {
    // MARK: Lifecycle

    public init(success: Bool, failedStepIndex: Int?, errorCode: String?, occurredAt: Date? = nil) {
        self.success = success
        self.failedStepIndex = failedStepIndex
        self.errorCode = errorCode
        self.occurredAt = occurredAt
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case success
        case failedStepIndex = "failed_step_index"
        case errorCode = "error_code"
        case occurredAt = "occurred_at"
    }

    public let success: Bool
    public let failedStepIndex: Int?
    public let errorCode: String?
    public let occurredAt: Date?

    /// Map a `MacroExecutionOutcome` to a wire body. Lives here so the
    /// iOS-side `MacroTelemetryReporter` can stay a thin wrapper and the
    /// shape transform is testable in the package.
    public static func from(outcome: MacroExecutionOutcome) -> RegistryRunEventBody {
        switch outcome {
        case .success:
            RegistryRunEventBody(success: true, failedStepIndex: nil, errorCode: nil)
        case let .failure(reason, stepIndex):
            RegistryRunEventBody(
                success: false,
                failedStepIndex: stepIndex,
                errorCode: shortenErrorCode(reason)
            )
        case .cancelled:
            RegistryRunEventBody(success: false, failedStepIndex: nil, errorCode: "cancelled")
        }
    }

    // MARK: Internal

    /// First 4 alphanumeric-or-dash tokens of the reason, lowercased, capped
    /// at 64 characters. Keeps user-typed callsigns/frequencies off the wire
    /// even if the error message includes them.
    static func shortenErrorCode(_ reason: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let trimmed = reason
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "-")
        let capped = String(trimmed.prefix(64))
        return capped.isEmpty ? "unspecified" : capped
    }
}

// MARK: - MacrosRegistryClientError

public enum MacrosRegistryClientError: Error, Sendable, Equatable {
    case invalidURL
    case notAuthenticated
    case server(status: Int, body: String?)
    case decoding(String)
    case transport(String)
}

// MARK: - Auth provider

/// Closure that resolves a Bearer token for authenticated endpoints. The
/// iOS app wires this to `ActivitiesClient.ensureAuthToken()` so the
/// registry client doesn't need to know about Keychain plumbing.
public typealias RegistryAuthTokenProvider = @Sendable () async -> String?

// MARK: - MacrosRegistryClient

public actor MacrosRegistryClient {
    // MARK: Lifecycle

    /// Convenience: pin the base URL at construction. Used by tests and any
    /// call site where the server address can't change at runtime. Prefer
    /// the `baseURLProvider` initializer when the URL can be edited in
    /// Settings — capturing a snapshot here leaves the client stuck on the
    /// old URL until app relaunch.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: RegistryAuthTokenProvider? = nil
    ) {
        self.init(
            baseURLProvider: { baseURL },
            session: session,
            authTokenProvider: authTokenProvider
        )
    }

    /// Use this when the configured server URL can change at runtime (e.g.
    /// a developer override in Settings). The closure is invoked once per
    /// request, so flipping the underlying UserDefaults key takes effect
    /// on the next poll without rebuilding the client.
    public init(
        baseURLProvider: @escaping @Sendable () -> URL,
        session: URLSession = .shared,
        authTokenProvider: RegistryAuthTokenProvider? = nil
    ) {
        self.baseURLProvider = baseURLProvider
        self.session = session
        self.authTokenProvider = authTokenProvider
    }

    // MARK: Public

    public func list(
        maxFormat: Int = RadioMacroDocument.currentFormat,
        tag: String? = nil,
        appliesTo: String? = nil,
        search: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> RegistryListResponse {
        try await send(
            .list(maxFormat: maxFormat, tag: tag, appliesTo: appliesTo, search: search, limit: limit, offset: offset),
            decode: RegistryListResponse.self
        )
    }

    public func get(slug: String) async throws -> RegistryMacroDocument {
        try await send(.get(slug: slug), decode: RegistryMacroDocument.self)
    }

    public func versions(slugs: [String]) async throws -> [String: RegistryVersionInfo] {
        guard !slugs.isEmpty else {
            return [:]
        }
        return try await send(.versions(slugs: slugs), decode: [String: RegistryVersionInfo].self)
    }

    public func tombstones(since: Date?) async throws -> RegistryTombstonesResponse {
        try await send(.tombstones(since: since), decode: RegistryTombstonesResponse.self)
    }

    public func reportRunEvent(slug: String, body: RegistryRunEventBody) async throws {
        try await sendEmpty(.runEvent(slug: slug), jsonBody: body)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "MacrosRegistryClient"
    )

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        return encoder
    }()

    private let baseURLProvider: @Sendable () -> URL
    private let session: URLSession
    private let authTokenProvider: RegistryAuthTokenProvider?

    private func send<T: Decodable & Sendable>(
        _ endpoint: RegistryEndpoint,
        decode _: T.Type
    ) async throws -> T {
        let data = try await execute(endpoint, jsonBody: RegistryRunEventBody?.none)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw MacrosRegistryClientError.decoding(String(describing: error))
        }
    }

    private func sendEmpty(_ endpoint: RegistryEndpoint, jsonBody: some Encodable & Sendable) async throws {
        _ = try await execute(endpoint, jsonBody: jsonBody)
    }

    private func execute(
        _ endpoint: RegistryEndpoint,
        jsonBody: (some Encodable & Sendable)?
    ) async throws -> Data {
        guard let url = endpoint.url(relativeTo: baseURLProvider()) else {
            throw MacrosRegistryClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        if endpoint.requiresAuth {
            guard let token = await authTokenProvider?(), !token.isEmpty else {
                throw MacrosRegistryClientError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MacrosRegistryClientError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw MacrosRegistryClientError.transport("non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw MacrosRegistryClientError.server(status: http.statusCode, body: body)
        }
        return data
    }
}

// MARK: - JSON helpers

private extension JSONDecoder.DateDecodingStrategy {
    /// The activities-server emits ISO-8601 timestamps both with and without
    /// fractional seconds (e.g., `2026-05-25T10:11:12Z` and
    /// `…12.345Z`). The default `.iso8601` parser only accepts the former.
    static let iso8601WithFractionalSeconds = custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = isoWithFractionalSecondsFormatter.date(from: raw) {
            return date
        }
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO-8601 date: \(raw)")
    }
}

private extension JSONEncoder.DateEncodingStrategy {
    static let iso8601WithFractionalSeconds = custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(isoWithFractionalSecondsFormatter.string(from: date))
    }
}

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let isoWithFractionalSecondsFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
