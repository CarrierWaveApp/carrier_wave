import Foundation
#if canImport(Security)
    import Security
#endif

// MARK: - QSODownloadAccumulator

/// Actor to safely accumulate QSO results from parallel downloads
public actor QSODownloadAccumulator {
    // MARK: Lifecycle

    public init(initialSyncMillis: Int64) {
        maxSyncMillis = initialSyncMillis
        currentConcurrency = initialConcurrency
    }

    // MARK: Public

    public let minConcurrency = 4
    public let maxConcurrency = 16
    public let initialConcurrency = 8
    public let baseBackoffMs: UInt64 = 100
    public let maxBackoffMs: UInt64 = 5_000

    public func addResults(_ qsos: [(LoFiQso, LoFiOperation)], syncMillis: Int64) {
        for (qso, op) in qsos where qsosByUUID[qso.uuid] == nil {
            qsosByUUID[qso.uuid] = (qso, op)
        }
        maxSyncMillis = max(maxSyncMillis, syncMillis)
        processedCount += 1
        consecutiveErrors = 0
        backoffDelayMs = 0
    }

    public func recordError() {
        consecutiveErrors += 1
        if consecutiveErrors >= 2, currentConcurrency > minConcurrency {
            currentConcurrency = max(minConcurrency, currentConcurrency - 1)
        }
        if backoffDelayMs == 0 {
            backoffDelayMs = baseBackoffMs
        } else {
            backoffDelayMs = min(backoffDelayMs * 2, maxBackoffMs)
        }
    }

    public func getBackoffDelay() -> UInt64 {
        backoffDelayMs
    }

    public func increaseIfStable() {
        if consecutiveErrors == 0, currentConcurrency < maxConcurrency {
            currentConcurrency = min(maxConcurrency, currentConcurrency + 1)
        }
    }

    public func getConcurrency() -> Int {
        currentConcurrency
    }

    public func getProcessedCount() -> Int {
        processedCount
    }

    public func getQSOCount() -> Int {
        qsosByUUID.count
    }

    public func getResults() -> ([String: (LoFiQso, LoFiOperation)], Int64) {
        (qsosByUUID, maxSyncMillis)
    }

    // MARK: Private

    private var qsosByUUID: [String: (LoFiQso, LoFiOperation)] = [:]
    private var maxSyncMillis: Int64 = 0
    private var processedCount = 0
    private var currentConcurrency: Int
    private var consecutiveErrors = 0
    private var backoffDelayMs: UInt64 = 0
}

// MARK: - LoFiClient helpers

public extension LoFiClient {
    func getToken() throws -> String {
        guard let token = try? credentials.getString(.authToken) else {
            throw LoFiError.authenticationRequired
        }
        return token
    }

    /// Wraps URLSession.data(for:) with optional verbose logging of request and response
    func loggedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        if verbose {
            let method = request.httpMethod ?? "GET"
            let url = request.url?.absoluteString ?? "<none>"
            logger.info("→ \(method) \(url)")
            for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
                logger.info("→ \(key): \(value)")
            }
            if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
                logger.info("→ Body: \(text)")
            }
        }

        let (data, response) = try await session.data(for: request)

        if verbose, let http = response as? HTTPURLResponse {
            logger.info("← HTTP \(http.statusCode)")
            for (key, value) in http.allHeaderFields.sorted(by: { "\($0.key)" < "\($1.key)" }) {
                logger.info("← \(key): \(value)")
            }
            if let text = String(data: data, encoding: .utf8) {
                logger.info("← Body: \(text)")
            }
        }

        return (data, response)
    }

    func generateClientSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        #else
            for i in 0 ..< bytes.count {
                bytes[i] = UInt8.random(in: 0 ... 255)
            }
        #endif
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await loggedData(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        if httpResponse.statusCode == 401 {
            throw LoFiError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LoFiError.invalidResponse("JSON decode error: \(error)")
        }
    }
}
