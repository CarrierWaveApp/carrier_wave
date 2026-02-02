// swiftlint:disable file_length type_body_length function_body_length
import Foundation

// MARK: - LoFiError

enum LoFiError: Error, LocalizedError {
    case notConfigured
    case notLinked
    case registrationFailed(String)
    case authenticationRequired
    case networkError(Error)
    case invalidResponse(String)
    case apiError(Int, String)

    // MARK: Internal

    var errorDescription: String? {
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

@MainActor
final class LoFiClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Progress info passed to callback during sync
    struct SyncProgressInfo {
        /// Total QSOs expected (from accounts endpoint)
        let totalQSOs: Int
        /// Total operations expected
        let totalOperations: Int
        /// QSOs downloaded so far
        let downloadedQSOs: Int
        /// Operations processed so far
        let processedOperations: Int
    }

    // MARK: Internal (for extension access)

    let baseURL = "https://lofi.ham2k.net"
    let clientName = "CarrierWave"
    let appName = "CarrierWave"
    let keychain = KeychainHelper.shared
    let session: URLSession

    // MARK: - Configuration

    var isConfigured: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiClientKey)) != nil
            && (try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)) != nil
    }

    var isLinked: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiDeviceLinked)) == "true"
    }

    var hasToken: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiAuthToken)) != nil
    }

    func hasCredentials() -> Bool {
        isConfigured && isLinked
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)
    }

    func getEmail() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.lofiEmail)
    }

    func getLastSyncMillis() -> Int64 {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.lofiLastSyncMillis),
              let value = Int64(str)
        else {
            return 0
        }
        return value
    }

    // MARK: - Setup

    /// Configure LoFi with callsign and optional email
    /// Generates client key and secret automatically
    func configure(callsign: String, email: String?) throws {
        let clientKey = UUID().uuidString
        let clientSecret = generateClientSecret()

        try keychain.save(clientKey, for: KeychainHelper.Keys.lofiClientKey)
        try keychain.save(clientSecret, for: KeychainHelper.Keys.lofiClientSecret)
        try keychain.save(callsign.uppercased(), for: KeychainHelper.Keys.lofiCallsign)
        if let email {
            try keychain.save(email, for: KeychainHelper.Keys.lofiEmail)
        }
        try keychain.save("false", for: KeychainHelper.Keys.lofiDeviceLinked)
    }

    /// Register with LoFi and get bearer token
    func register() async throws -> LoFiRegistrationResponse {
        guard let clientKey = try? keychain.readString(for: KeychainHelper.Keys.lofiClientKey),
              let clientSecret = try? keychain.readString(for: KeychainHelper.Keys.lofiClientSecret),
              let callsign = try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)
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

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.registrationFailed("\(httpResponse.statusCode) - \(body)")
        }

        let registration = try JSONDecoder().decode(LoFiRegistrationResponse.self, from: data)

        // Log account details including cutoff date
        logRegistrationDetails(registration)

        // Save the token
        try keychain.save(registration.token, for: KeychainHelper.Keys.lofiAuthToken)

        return registration
    }

    /// Link device via email confirmation
    func linkDevice(email: String) async throws {
        let token = try getToken()

        let request = LoFiLinkDeviceRequest(email: email)

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/client/link")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        // Save the email for future reference
        try keychain.save(email, for: KeychainHelper.Keys.lofiEmail)
    }

    /// Mark device as linked (call after user confirms email)
    func markAsLinked() throws {
        try keychain.save("true", for: KeychainHelper.Keys.lofiDeviceLinked)
    }

    /// Refresh the bearer token
    func refreshToken() async throws -> String {
        let registration = try await register()
        return registration.token
    }

    // MARK: - Fetch Account Info

    /// Fetch account info including total QSO and operation counts
    /// Used to display sync progress
    func fetchAccountInfo() async throws -> LoFiAccountsResponse {
        let token = try getToken()

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/accounts")!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    // MARK: - Fetch Operations

    /// Fetch operations with pagination
    /// - Parameter otherClientsOnly: When true, excludes operations uploaded by this client.
    ///   Should be false for fresh sync to get ALL operations.
    /// - Parameter deleted: When true, fetches only deleted operations. When nil/false, fetches only active.
    ///   Note: The server checks `if params[:deleted]` so passing "false" is treated as truthy.
    ///   Only pass this parameter when true, omit it entirely for active operations.
    func fetchOperations(
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50,
        otherClientsOnly: Bool = true,
        deleted: Bool = false
    ) async throws -> LoFiOperationsResponse {
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        // Only include deleted param when true - server treats any value as truthy
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch QSOs for a specific operation
    /// - Parameter otherClientsOnly: When true, excludes QSOs uploaded by this client.
    ///   Should be false for fresh sync to get ALL QSOs.
    /// - Parameter deleted: When true, fetches deleted QSOs. When nil/false, fetches active QSOs.
    ///   Note: The server checks `if params[:deleted]` so passing "false" is treated as truthy.
    ///   Only pass this parameter when true, omit it entirely for active QSOs.
    func fetchOperationQsos(
        operationUUID: String,
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50,
        otherClientsOnly: Bool = true,
        deleted: Bool = false
    ) async throws -> LoFiQsosResponse {
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations/\(operationUUID)/qsos")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        // Only include deleted param when true - server treats any value as truthy
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch all QSOs from all operations since last sync
    /// - Parameter onProgress: Optional callback invoked as QSOs are downloaded
    func fetchAllQsosSinceLastSync(
        onProgress: ((SyncProgressInfo) -> Void)? = nil
    ) async throws -> [(LoFiQso, LoFiOperation)] {
        let lastSyncMillis = getLastSyncMillis()
        let isFreshSync = lastSyncMillis == 0
        let debugLog = SyncDebugLog.shared

        debugLog.info("Starting LoFi sync", service: .lofi)
        debugLog.info("Callsign: \(getCallsign() ?? "unknown")", service: .lofi)

        if lastSyncMillis > 0 {
            let lastSyncDate = Date(timeIntervalSince1970: Double(lastSyncMillis) / 1_000.0)
            let formatter = ISO8601DateFormatter()
            debugLog.info("Last sync: \(formatter.string(from: lastSyncDate))", service: .lofi)
        } else {
            debugLog.info("Last sync: Never (fresh sync)", service: .lofi)
        }

        // Re-register to get fresh account info (including cutoff date)
        do {
            let registration = try await register()
            logRegistrationToDebugLog(registration, debugLog: debugLog)
        } catch {
            debugLog.warning(
                "Could not refresh registration: \(error.localizedDescription)", service: .lofi
            )
        }

        // Fetch account info for progress tracking
        var totalQSOs = 0
        var totalOperations = 0
        NSLog("[LoFi Progress] onProgress callback is %@", onProgress != nil ? "PROVIDED" : "nil")
        if let onProgress {
            do {
                let accountInfo = try await fetchAccountInfo()
                totalQSOs = accountInfo.qsos.syncable
                totalOperations = accountInfo.operations.syncable
                debugLog.info(
                    "Account has \(totalQSOs) syncable QSOs in \(totalOperations) operations",
                    service: .lofi
                )
                // Initialize progress bar immediately with totals
                NSLog(
                    "[LoFi Progress] Calling initial onProgress with total=%d, operations=%d",
                    totalQSOs, totalOperations
                )
                onProgress(
                    SyncProgressInfo(
                        totalQSOs: totalQSOs,
                        totalOperations: totalOperations,
                        downloadedQSOs: 0,
                        processedOperations: 0
                    )
                )
                NSLog("[LoFi Progress] Initial onProgress call completed")
            } catch {
                NSLog(
                    "[LoFi Progress] Failed to fetch account info: %@",
                    error.localizedDescription
                )
                debugLog.warning(
                    "Could not fetch account info for progress: \(error.localizedDescription)",
                    service: .lofi
                )
            }
        }

        // Fetch all operations (both active and deleted)
        let operations = try await fetchAllOperations(isFreshSync: isFreshSync, debugLog: debugLog)

        // Fetch QSOs for each operation with progress tracking
        let (qsosByUUID, maxSyncMillis) = try await fetchQsosForOperations(
            operations,
            lastSyncMillis: lastSyncMillis,
            isFreshSync: isFreshSync,
            debugLog: debugLog,
            onProgress: onProgress.map { callback in
                { downloadedQSOs, processedOperations in
                    callback(
                        SyncProgressInfo(
                            totalQSOs: totalQSOs,
                            totalOperations: totalOperations,
                            downloadedQSOs: downloadedQSOs,
                            processedOperations: processedOperations
                        )
                    )
                }
            }
        )

        // Update last sync timestamp
        if maxSyncMillis > lastSyncMillis {
            try? keychain.save(String(maxSyncMillis), for: KeychainHelper.Keys.lofiLastSyncMillis)
        }

        let allQsos = Array(qsosByUUID.values)

        // Log comprehensive summary
        logSyncSummary(operations: operations, qsos: allQsos, debugLog: debugLog)

        return allQsos
    }

    /// Fetch ALL QSOs from all operations (ignoring last sync timestamp, for force re-download)
    func fetchAllQsos() async throws -> [(LoFiQso, LoFiOperation)] {
        let debugLog = SyncDebugLog.shared

        debugLog.info("Force re-downloading ALL QSOs", service: .lofi)

        // Re-register to get fresh account info (including cutoff date)
        do {
            let registration = try await register()
            logRegistrationToDebugLog(registration, debugLog: debugLog)
        } catch {
            debugLog.warning(
                "Could not refresh registration: \(error.localizedDescription)", service: .lofi
            )
        }

        // Fetch all operations (treat as fresh sync to get everything)
        let operations = try await fetchAllOperations(isFreshSync: true, debugLog: debugLog)

        // Fetch all QSOs starting from 0
        let (qsosByUUID, _) = try await fetchQsosForOperations(
            operations,
            lastSyncMillis: 0,
            isFreshSync: true,
            debugLog: debugLog
        )

        let allQsos = Array(qsosByUUID.values)

        // Log comprehensive summary
        logSyncSummary(operations: operations, qsos: allQsos, debugLog: debugLog)

        return allQsos
    }

    // MARK: - Clear

    /// Reset just the sync timestamp so QSOs can be re-downloaded
    func resetSyncTimestamp() {
        try? keychain.delete(for: KeychainHelper.Keys.lofiLastSyncMillis)
    }

    func clearCredentials() throws {
        try? keychain.delete(for: KeychainHelper.Keys.lofiAuthToken)
        try? keychain.delete(for: KeychainHelper.Keys.lofiClientKey)
        try? keychain.delete(for: KeychainHelper.Keys.lofiClientSecret)
        try? keychain.delete(for: KeychainHelper.Keys.lofiCallsign)
        try? keychain.delete(for: KeychainHelper.Keys.lofiEmail)
        try? keychain.delete(for: KeychainHelper.Keys.lofiDeviceLinked)
        try? keychain.delete(for: KeychainHelper.Keys.lofiLastSyncMillis)
    }

    // MARK: Private

    private func logRegistrationDetails(_ registration: LoFiRegistrationResponse) {
        // Logging handled by logRegistrationToDebugLog for sync debug log
    }

    private func logRegistrationToDebugLog(
        _ registration: LoFiRegistrationResponse, debugLog: SyncDebugLog
    ) {
        debugLog.info("Account: \(registration.account.call)", service: .lofi)

        if let cutoffDate = registration.account.cutoffDate {
            debugLog.warning(
                "⚠️ CUTOFF DATE: \(cutoffDate) - older QSOs may not sync", service: .lofi
            )
        } else {
            debugLog.info("No cutoff date restriction", service: .lofi)
        }

        if let cutoffMillis = registration.account.cutoffDateMillis {
            let date = Date(timeIntervalSince1970: Double(cutoffMillis) / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.warning("Cutoff: \(formatter.string(from: date))", service: .lofi)
        }
    }

    private func logSyncSummary(
        operations: [LoFiOperation],
        qsos: [(LoFiQso, LoFiOperation)],
        debugLog: SyncDebugLog
    ) {
        debugLog.info("Total operations: \(operations.count)", service: .lofi)

        let expectedQsoCount = operations.reduce(0) { $0 + $1.qsoCount }
        debugLog.info("Expected QSOs: \(expectedQsoCount), Actual: \(qsos.count)", service: .lofi)

        if qsos.count != expectedQsoCount {
            let diff = expectedQsoCount - qsos.count
            debugLog.warning(
                "⚠️ QSO MISMATCH: expected \(expectedQsoCount), got \(qsos.count) (missing \(diff))",
                service: .lofi
            )
        }

        // Log date range of fetched QSOs
        if !qsos.isEmpty {
            let timestamps = qsos.compactMap(\.0.startAtMillis)
            let minTimestamp = timestamps.min() ?? 0
            let maxTimestamp = timestamps.max() ?? 0
            let minDate = Date(timeIntervalSince1970: minTimestamp / 1_000.0)
            let maxDate = Date(timeIntervalSince1970: maxTimestamp / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            debugLog.info(
                "QSO date range: \(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))",
                service: .lofi
            )
        }

        // Count operations with QSO count mismatches
        var mismatchCount = 0
        for op in operations {
            let opQsos = qsos.filter { $0.1.uuid == op.uuid }
            if opQsos.count != op.qsoCount {
                mismatchCount += 1
            }
        }
        if mismatchCount > 0 {
            debugLog.warning(
                "\(mismatchCount) operations have QSO count mismatches", service: .lofi
            )
        }
    }

    private func fetchAllOperations(
        isFreshSync: Bool,
        debugLog: SyncDebugLog
    ) async throws -> [LoFiOperation] {
        var operationsByUUID: [String: LoFiOperation] = [:]

        debugLog.info("Fetching operations (fresh=\(isFreshSync))", service: .lofi)

        for deleted in [false, true] {
            var syncedSince: Int64 = 0
            var pageCount = 0
            var totalFetched = 0

            while true {
                pageCount += 1
                let response = try await fetchOperations(
                    syncedSinceMillis: syncedSince,
                    limit: 50,
                    otherClientsOnly: !isFreshSync,
                    deleted: deleted
                )

                totalFetched += response.operations.count
                for operation in response.operations {
                    operationsByUUID[operation.uuid] = operation
                }

                if response.meta.operations.recordsLeft == 0 {
                    break
                }
                // Server returns next_updated_at_millis when using synced_since_millis pagination
                guard
                    let next = response.meta.operations.nextUpdatedAtMillis
                    ?? response.meta.operations.nextSyncedAtMillis
                else {
                    debugLog.warning(
                        "recordsLeft=\(response.meta.operations.recordsLeft) but no nextUpdatedAtMillis",
                        service: .lofi
                    )
                    break
                }
                syncedSince = Int64(next)
            }

            let opType = deleted ? "deleted" : "active"
            debugLog.info(
                "Fetched \(totalFetched) \(opType) operations in \(pageCount) pages", service: .lofi
            )
        }

        let operations = Array(operationsByUUID.values)
        let expectedQsos = operations.reduce(0) { $0 + $1.qsoCount }

        debugLog.info(
            "Total operations: \(operations.count), expected QSOs: \(expectedQsos)", service: .lofi
        )

        // Log date range of operations
        if !operations.isEmpty {
            let minMillis = operations.compactMap(\.startAtMillisMin).min() ?? 0
            let maxMillis = operations.compactMap(\.startAtMillisMax).max() ?? 0
            if minMillis > 0, maxMillis > 0 {
                let minDate = Date(timeIntervalSince1970: minMillis / 1_000.0)
                let maxDate = Date(timeIntervalSince1970: maxMillis / 1_000.0)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                debugLog.info(
                    "Operations span: \(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))",
                    service: .lofi
                )
            }
        }

        return operations
    }

    private func fetchQsosForOperations(
        _ operations: [LoFiOperation],
        lastSyncMillis: Int64,
        isFreshSync: Bool,
        debugLog: SyncDebugLog,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> ([String: (LoFiQso, LoFiOperation)], Int64) {
        let qsoSyncStart: Int64 = isFreshSync ? 0 : lastSyncMillis
        let totalOperations = operations.count

        debugLog.info(
            "Fetching QSOs from \(totalOperations) operations with parallel downloads",
            service: .lofi
        )

        // Use actor for thread-safe accumulation with adaptive concurrency
        let accumulator = QSODownloadAccumulator(initialSyncMillis: lastSyncMillis)

        // Process operations in batches with adaptive concurrency
        var operationIndex = 0
        while operationIndex < totalOperations {
            let concurrency = await accumulator.getConcurrency()
            let batchEnd = min(operationIndex + concurrency, totalOperations)
            let batch = Array(operations[operationIndex ..< batchEnd])

            // Launch parallel fetches for this batch
            await withTaskGroup(
                of: Result<([(LoFiQso, LoFiOperation)], Int64), Error>.self
            ) { group in
                for operation in batch {
                    group.addTask { [self] in
                        do {
                            let result = try await fetchQsosForOperation(
                                operation,
                                syncStart: qsoSyncStart,
                                isFreshSync: isFreshSync,
                                debugLog: debugLog
                            )
                            return .success(result)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                // Collect results
                for await result in group {
                    switch result {
                    case .success(let (qsos, syncMillis)):
                        await accumulator.addResults(qsos, syncMillis: syncMillis)
                    case let .failure(error):
                        await accumulator.recordError()
                        debugLog.warning(
                            "Operation fetch failed: \(error.localizedDescription)",
                            service: .lofi
                        )
                    }
                }
            }

            // Update progress after each batch
            let processedCount = await accumulator.getProcessedCount()
            let qsoCount = await accumulator.getQSOCount()

            if let onProgress {
                if processedCount == batch.count || processedCount.isMultiple(of: 50) {
                    NSLog(
                        "[LoFi Progress] %d QSOs, %d/%d operations (concurrency: %d)",
                        qsoCount, processedCount, totalOperations, concurrency
                    )
                }
                onProgress(qsoCount, processedCount)
            }

            // Apply backoff delay if there were errors
            let backoffDelay = await accumulator.getBackoffDelay()
            if backoffDelay > 0 {
                try await Task.sleep(nanoseconds: backoffDelay * 1_000_000)
            }

            // Periodically try to increase concurrency if stable
            if operationIndex.isMultiple(of: 20) {
                await accumulator.increaseIfStable()
            }

            operationIndex = batchEnd
            await Task.yield()
        }

        return await accumulator.getResults()
    }

    private func fetchQsosForOperation(
        _ operation: LoFiOperation,
        syncStart: Int64,
        isFreshSync: Bool,
        debugLog: SyncDebugLog
    ) async throws -> ([(LoFiQso, LoFiOperation)], Int64) {
        var qsos: [(LoFiQso, LoFiOperation)] = []
        var maxSyncMillis: Int64 = 0

        for deleted in [false, true] {
            var qsoSyncedSince = syncStart

            while true {
                let response = try await fetchOperationQsos(
                    operationUUID: operation.uuid,
                    syncedSinceMillis: qsoSyncedSince,
                    limit: 50,
                    otherClientsOnly: !isFreshSync,
                    deleted: deleted
                )

                for qso in response.qsos {
                    qsos.append((qso, operation))
                    if let syncedAt = qso.syncedAtMillis {
                        maxSyncMillis = max(maxSyncMillis, Int64(syncedAt))
                    }
                }

                if response.meta.qsos.recordsLeft == 0 {
                    break
                }
                // Server returns next_updated_at_millis when using synced_since_millis pagination
                guard
                    let next = response.meta.qsos.nextUpdatedAtMillis
                    ?? response.meta.qsos.nextSyncedAtMillis
                else {
                    debugLog.warning(
                        "Op \(operation.uuid): recordsLeft=\(response.meta.qsos.recordsLeft) but no next page",
                        service: .lofi
                    )
                    break
                }
                qsoSyncedSince = Int64(next)
            }
        }

        if qsos.count != operation.qsoCount {
            let opTitle = operation.title ?? "untitled"
            let diff = operation.qsoCount - qsos.count

            // Calculate operation date range
            var dateInfo = "unknown dates"
            if let minMillis = operation.startAtMillisMin,
               let maxMillis = operation.startAtMillisMax
            {
                let minDate = Date(timeIntervalSince1970: minMillis / 1_000.0)
                let maxDate = Date(timeIntervalSince1970: maxMillis / 1_000.0)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                dateInfo =
                    "\(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))"
            }

            // Only log to debugLog if significant (>0 missing QSOs)
            if diff > 0 {
                debugLog.warning(
                    "Op mismatch: \(opTitle) (\(dateInfo)) expected \(operation.qsoCount), got \(qsos.count)",
                    service: .lofi
                )
            }

            // If we got 0 QSOs for an operation that should have some, log extra warning
            if qsos.isEmpty, operation.qsoCount > 0 {
                debugLog.warning(
                    "⚠️ ZERO QSOs for op with qsoCount=\(operation.qsoCount) - likely cutoff_date restriction",
                    service: .lofi
                )
            }
        }
        return (qsos, maxSyncMillis)
    }
}

// Helper methods are in LoFiClient+Helpers.swift
