import Foundation

// MARK: - POTADownloadCheckpoint

/// Checkpoint for resumable POTA downloads
struct POTADownloadCheckpoint: Codable {
    let processedActivationKeys: Set<String>
    let lastBatchDate: Date
    let adaptiveBatchSize: Int?
}

// MARK: - POTADownloadConfig

/// Configuration for adaptive POTA downloads
enum POTADownloadConfig {
    /// Starting batch size (number of activations per batch)
    static let initialBatchSize = 25
    /// Minimum batch size when adapting down
    static let minimumBatchSize = 5
    /// Maximum batch size
    static let maximumBatchSize = 50
    /// Delay between activations in nanoseconds
    static let interActivationDelay: UInt64 = 100_000_000 // 100ms
    /// Delay after timeout before retry in nanoseconds
    static let timeoutRetryDelay: UInt64 = 2_000_000_000 // 2s
    /// Per-activation timeout in seconds
    static let perActivationTimeout: TimeInterval = 30
}

// MARK: - POTAClient Checkpoint Methods

extension POTAClient {
    func loadDownloadCheckpoint() -> POTADownloadCheckpoint? {
        guard
            let data = try? KeychainHelper.shared.read(
                for: KeychainHelper.Keys.potaDownloadProgress
            ),
            let checkpoint = try? JSONDecoder().decode(POTADownloadCheckpoint.self, from: data)
        else {
            return nil
        }
        return checkpoint
    }

    func saveDownloadCheckpoint(_ checkpoint: POTADownloadCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else {
            return
        }
        try? KeychainHelper.shared.save(data, for: KeychainHelper.Keys.potaDownloadProgress)
    }

    func clearDownloadCheckpoint() {
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.potaDownloadProgress)
    }

    // MARK: - Fetch All QSOs

    /// Fetch all QSOs with adaptive batching
    /// Adjusts batch size based on timeouts and API responsiveness
    func fetchAllQSOs() async throws -> [POTAFetchedQSO] {
        let debugLog = SyncDebugLog.shared
        let activations = try await fetchActivations()
        var state = POTADownloadState(checkpoint: loadDownloadCheckpoint())

        logDownloadStart(activations: activations, state: state)

        let remainingActivations = filterRemainingActivations(activations, state: state)
        guard !remainingActivations.isEmpty else {
            debugLog.info("No remaining activations to process", service: .pota)
            clearDownloadCheckpoint()
            return state.allFetched
        }

        debugLog.info(
            "Processing \(remainingActivations.count) remaining activations", service: .pota
        )

        var activationIndex = 0
        while activationIndex < remainingActivations.count {
            let batchEnd = min(activationIndex + state.currentBatchSize, remainingActivations.count)
            let batch = Array(remainingActivations[activationIndex ..< batchEnd])

            logBatchStart(
                index: activationIndex, batchEnd: batchEnd, total: remainingActivations.count,
                state: state
            )

            let result = try await processBatch(batch, state: &state)

            if result.succeeded {
                handleBatchSuccess(
                    batchCount: batch.count, batchElapsed: result.elapsed, state: &state
                )
                activationIndex = batchEnd
            }

            if state.consecutiveFailures >= 5 {
                logAbort(state: state)
                break
            }
        }

        clearDownloadCheckpoint()
        debugLog.info(
            "Download complete: \(state.allFetched.count) total QSOs from \(state.processedKeys.count) activations",
            service: .pota
        )
        return state.allFetched
    }

    // MARK: - Batch Processing Helpers

    private func processBatch(
        _ batch: [POTARemoteActivation],
        state: inout POTADownloadState
    ) async throws -> (succeeded: Bool, elapsed: TimeInterval) {
        let batchStartTime = Date()

        for activation in batch {
            let result = try await processActivation(activation, state: &state)

            switch result {
            case let .success(fetched):
                state.allFetched.append(contentsOf: fetched)
            case .timeout:
                try await handleTimeout(state: &state)
                return (false, Date().timeIntervalSince(batchStartTime))
            case .skipped:
                break
            }

            try await Task.sleep(nanoseconds: POTADownloadConfig.interActivationDelay)
        }

        return (true, Date().timeIntervalSince(batchStartTime))
    }

    private func filterRemainingActivations(
        _ activations: [POTARemoteActivation],
        state: POTADownloadState
    ) -> [POTARemoteActivation] {
        activations.filter { activation in
            let key = "\(activation.reference)|\(activation.date)"
            return !state.processedKeys.contains(key)
        }
    }

    private func logDownloadStart(activations: [POTARemoteActivation], state: POTADownloadState) {
        let debugLog = SyncDebugLog.shared
        let count = activations.count
        let processed = state.processedKeys.count
        debugLog.info(
            "Starting adaptive download: \(count) activations, \(processed) already processed",
            service: .pota
        )
        let minB = POTADownloadConfig.minimumBatchSize
        let maxB = POTADownloadConfig.maximumBatchSize
        let timeout = POTADownloadConfig.perActivationTimeout
        debugLog.debug(
            "Adaptive: batch=\(state.currentBatchSize), min=\(minB), max=\(maxB), timeout=\(timeout)s",
            service: .pota
        )
    }

    private func logBatchStart(index: Int, batchEnd: Int, total: Int, state: POTADownloadState) {
        let debugLog = SyncDebugLog.shared
        let batchNum = index / state.currentBatchSize + 1
        let ok = state.consecutiveSuccesses
        let fail = state.consecutiveFailures
        debugLog.debug(
            "Batch \(batchNum): \(index + 1)-\(batchEnd)/\(total), ok=\(ok), fail=\(fail)",
            service: .pota
        )
    }

    private func logAbort(state: POTADownloadState) {
        let debugLog = SyncDebugLog.shared
        let processed = state.processedKeys.count
        let qsoCount = state.allFetched.count
        debugLog.error(
            "Aborting: \(state.consecutiveFailures) failures (processed \(processed) activations, \(qsoCount) QSOs)",
            service: .pota
        )
    }

    /// Fetch a single activation with timeout
    func fetchActivationWithTimeout(_ activation: POTARemoteActivation) async throws
        -> [POTARemoteQSO]
    {
        try await withThrowingTaskGroup(of: [POTARemoteQSO].self) { group in
            group.addTask {
                try await self.fetchAllActivationQSOs(
                    reference: activation.reference, date: activation.date
                )
            }

            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(POTADownloadConfig.perActivationTimeout * 1_000_000_000)
                )
                throw POTAError.fetchFailed("Activation fetch timed out")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Check if error indicates timeout or rate limiting
    func isTimeoutOrRateLimitError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        return desc.contains("timed out")
            || desc.contains("timeout")
            || desc.contains("rate limit")
            || desc.contains("too many requests")
            || (error as NSError).code == NSURLErrorTimedOut
    }

    // MARK: - Job Status Methods

    func fetchJobs() async throws -> [POTAJob] {
        let debugLog = SyncDebugLog.shared
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/jobs") else {
            debugLog.error("Invalid URL for POTA jobs", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        debugLog.debug("GET /user/jobs", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.fetchFailed("Invalid response")
        }

        debugLog.debug("Jobs response: \(httpResponse.statusCode)", service: .pota)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog.error(
                "Jobs fetch failed: \(httpResponse.statusCode) - \(body)", service: .pota
            )
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let jobs = try JSONDecoder().decode([POTAJob].self, from: data)
        debugLog.info("Fetched \(jobs.count) POTA jobs", service: .pota)
        return jobs
    }
}

// MARK: - Array Chunking Extension

extension Array {
    /// Splits array into chunks of the specified size
    nonisolated func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
