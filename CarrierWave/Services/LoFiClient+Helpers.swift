import Foundation

// MARK: - QSODownloadAccumulator

/// Actor to safely accumulate QSO results from parallel downloads
actor QSODownloadAccumulator {
    // MARK: Lifecycle

    init(initialSyncMillis: Int64) {
        maxSyncMillis = initialSyncMillis
        currentConcurrency = initialConcurrency
    }

    // MARK: Internal

    let minConcurrency = 4
    let maxConcurrency = 16
    let initialConcurrency = 8
    let baseBackoffMs: UInt64 = 100
    let maxBackoffMs: UInt64 = 5_000

    func addResults(_ qsos: [(LoFiQso, LoFiOperation)], syncMillis: Int64) {
        for (qso, op) in qsos where qsosByUUID[qso.uuid] == nil {
            qsosByUUID[qso.uuid] = (qso, op)
        }
        maxSyncMillis = max(maxSyncMillis, syncMillis)
        processedCount += 1
        consecutiveErrors = 0
        // Reset backoff on success
        backoffDelayMs = 0
    }

    func recordError() {
        consecutiveErrors += 1
        // Reduce concurrency on errors
        if consecutiveErrors >= 2, currentConcurrency > minConcurrency {
            currentConcurrency = max(minConcurrency, currentConcurrency - 1)
            NSLog(
                "[LoFi Progress] Reducing concurrency to %d after %d consecutive errors",
                currentConcurrency, consecutiveErrors
            )
        }
        // Exponential backoff
        if backoffDelayMs == 0 {
            backoffDelayMs = baseBackoffMs
        } else {
            backoffDelayMs = min(backoffDelayMs * 2, maxBackoffMs)
        }
    }

    func getBackoffDelay() -> UInt64 {
        backoffDelayMs
    }

    func increaseIfStable() {
        // Increase concurrency if we're doing well (no recent errors)
        if consecutiveErrors == 0, currentConcurrency < maxConcurrency {
            currentConcurrency = min(maxConcurrency, currentConcurrency + 1)
        }
    }

    func getConcurrency() -> Int {
        currentConcurrency
    }

    func getProcessedCount() -> Int {
        processedCount
    }

    func getQSOCount() -> Int {
        qsosByUUID.count
    }

    func getResults() -> ([String: (LoFiQso, LoFiOperation)], Int64) {
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

// MARK: - LoFiClient Private Helpers

@MainActor
extension LoFiClient {
    func getToken() throws -> String {
        guard let token = try? keychain.readString(for: KeychainHelper.Keys.lofiAuthToken) else {
            throw LoFiError.authenticationRequired
        }
        return token
    }

    func generateClientSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        logResponseDetails(httpResponse, data: data)

        if httpResponse.statusCode == 401 {
            throw LoFiError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            logResponseCounts(decoded)
            return decoded
        } catch {
            throw LoFiError.invalidResponse("JSON decode error: \(error)")
        }
    }

    private func logResponseDetails(_ response: HTTPURLResponse, data: Data) {
        // Verbose logging disabled - use SyncDebugLog for structured logging
    }

    private func logResponseCounts(_ decoded: some Any) {
        // Verbose logging disabled - use SyncDebugLog for structured logging
    }
}
