import CarrierWaveCore
import Foundation

// MARK: - POTADownloadCheckpoint

/// Checkpoint for resumable POTA downloads (in-progress state)
struct POTADownloadCheckpoint: Codable {
    let processedActivationKeys: Set<String>
    let lastBatchDate: Date
    let adaptiveBatchSize: Int?
}

// MARK: - POTASyncState

/// Persistent state for incremental POTA syncs (persisted between syncs)
struct POTASyncState: Codable {
    let processedActivationKeys: Set<String>
    let lastSyncDate: Date
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
    // MARK: - In-Progress Checkpoint (cleared after successful sync)

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

    // MARK: - Persistent Sync State (persisted between syncs for incremental)

    func loadSyncState() -> POTASyncState? {
        guard
            let data = try? KeychainHelper.shared.read(
                for: KeychainHelper.Keys.potaLastSyncDate
            ),
            let state = try? JSONDecoder().decode(POTASyncState.self, from: data)
        else {
            return nil
        }
        return state
    }

    func saveSyncState(_ state: POTASyncState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        try? KeychainHelper.shared.save(data, for: KeychainHelper.Keys.potaLastSyncDate)
    }

    func clearSyncState() {
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.potaLastSyncDate)
    }

    // MARK: - Fetch All QSOs

    /// Fetch all QSOs with adaptive batching and incremental sync
    /// On first sync: processes all activations
    /// On subsequent syncs: only processes new activations not in saved state
    /// Adjusts batch size based on timeouts and API responsiveness
    func fetchAllQSOs() async throws -> [POTAFetchedQSO] {
        let debugLog = SyncDebugLog.shared
        let activations = try await fetchActivations()

        let (state, savedState) = initializeDownloadState()
        var mutableState = state

        logIncrementalDownloadStart(
            activations: activations, state: mutableState, savedState: savedState
        )

        let remainingActivations = filterRemainingActivations(activations, state: mutableState)
        guard !remainingActivations.isEmpty else {
            debugLog.info("No new activations to process (incremental sync)", service: .pota)
            clearDownloadCheckpoint()
            return mutableState.allFetched
        }

        debugLog.info("Processing \(remainingActivations.count) new activations", service: .pota)

        try await processAllBatches(remainingActivations, state: &mutableState)
        finalizeDownload(state: mutableState, newActivationCount: remainingActivations.count)

        return mutableState.allFetched
    }

    /// Initialize download state by merging persistent sync state with any in-progress checkpoint
    private func initializeDownloadState() -> (POTADownloadState, POTASyncState?) {
        let savedState = loadSyncState()
        let checkpoint = loadDownloadCheckpoint()

        // Start with previously synced keys from persistent state
        var initialKeys = savedState?.processedActivationKeys ?? Set<String>()
        // Add any keys from an interrupted download
        if let checkpointKeys = checkpoint?.processedActivationKeys {
            initialKeys.formUnion(checkpointKeys)
        }

        var state = POTADownloadState(checkpoint: checkpoint)
        state.processedKeys = initialKeys

        return (state, savedState)
    }

    /// Process all remaining activations in batches
    private func processAllBatches(
        _ remainingActivations: [POTARemoteActivation],
        state: inout POTADownloadState
    ) async throws {
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
    }

    /// Finalize download by saving sync state and clearing checkpoint
    private func finalizeDownload(state: POTADownloadState, newActivationCount: Int) {
        let debugLog = SyncDebugLog.shared

        saveSyncState(
            POTASyncState(
                processedActivationKeys: state.processedKeys,
                lastSyncDate: Date()
            )
        )
        clearDownloadCheckpoint()

        debugLog.info(
            "Download complete: \(state.allFetched.count) QSOs from \(newActivationCount) new activations",
            service: .pota
        )
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

    private func logIncrementalDownloadStart(
        activations: [POTARemoteActivation],
        state: POTADownloadState,
        savedState: POTASyncState?
    ) {
        let debugLog = SyncDebugLog.shared
        let count = activations.count
        let processed = state.processedKeys.count

        if let savedState {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Starting incremental POTA download (last sync: \(formatter.string(from: savedState.lastSyncDate)))",
                service: .pota
            )
            debugLog.info(
                "Found \(count) total activations, \(processed) already synced",
                service: .pota
            )
        } else {
            debugLog.info(
                "Starting full POTA download (no previous sync): \(count) activations",
                service: .pota
            )
        }

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
