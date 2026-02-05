import CarrierWaveCore
import Foundation

// MARK: - POTADownloadState

/// State for adaptive POTA download
struct POTADownloadState {
    // MARK: Lifecycle

    init(checkpoint: POTADownloadCheckpoint?) {
        processedKeys = checkpoint?.processedActivationKeys ?? Set<String>()
        currentBatchSize = checkpoint?.adaptiveBatchSize ?? POTADownloadConfig.initialBatchSize
    }

    // MARK: Internal

    var processedKeys: Set<String>
    var currentBatchSize: Int
    var consecutiveSuccesses: Int = 0
    var consecutiveFailures: Int = 0
    var allFetched: [POTAFetchedQSO] = []
}

// MARK: - POTAClient Adaptive Download

extension POTAClient {
    /// Process a single activation and return fetched QSOs
    func processActivation(
        _ activation: POTARemoteActivation,
        state: inout POTADownloadState
    ) async throws -> ActivationResult {
        let debugLog = SyncDebugLog.shared
        let key = "\(activation.reference)|\(activation.date)"
        let startTime = Date()

        do {
            let qsos = try await fetchActivationWithTimeout(activation)
            let fetched = qsos.compactMap { convertToFetchedQSO($0, activation: activation) }
            state.processedKeys.insert(key)

            debugLog.debug(
                "Fetched \(activation.reference) \(activation.date): \(qsos.count) QSOs",
                service: .pota
            )
            return .success(fetched)
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)

            if isTimeoutOrRateLimitError(error) {
                logTimeoutError(activation: activation, elapsed: elapsed, error: error)
                return .timeout
            }

            // For other errors, skip and continue
            let errorDesc = error.localizedDescription
            debugLog.warning(
                "Skipping \(activation.reference) \(activation.date) after error: \(errorDesc)",
                service: .pota
            )
            state.processedKeys.insert(key)
            return .skipped
        }
    }

    /// Handle timeout/rate limit by shrinking batch size
    func handleTimeout(state: inout POTADownloadState) async throws {
        let debugLog = SyncDebugLog.shared
        state.consecutiveFailures += 1
        state.consecutiveSuccesses = 0

        let oldBatchSize = state.currentBatchSize
        let minBatch = POTADownloadConfig.minimumBatchSize
        if state.currentBatchSize > minBatch {
            state.currentBatchSize = max(state.currentBatchSize / 2, minBatch)
        }

        let fails = state.consecutiveFailures
        debugLog.info(
            "Adaptive: batchSize \(oldBatchSize) → \(state.currentBatchSize), fails=\(fails)",
            service: .pota
        )

        saveDownloadCheckpoint(
            POTADownloadCheckpoint(
                processedActivationKeys: state.processedKeys,
                lastBatchDate: Date(),
                adaptiveBatchSize: state.currentBatchSize
            )
        )

        let retryDelaySec = Double(POTADownloadConfig.timeoutRetryDelay) / 1_000_000_000
        debugLog.debug("Waiting \(retryDelaySec)s before retry...", service: .pota)
        try await Task.sleep(nanoseconds: POTADownloadConfig.timeoutRetryDelay)
    }

    /// Handle successful batch completion
    func handleBatchSuccess(
        batchCount: Int,
        batchElapsed: TimeInterval,
        state: inout POTADownloadState
    ) {
        let debugLog = SyncDebugLog.shared
        state.consecutiveSuccesses += 1
        state.consecutiveFailures = 0

        let elapsedStr = String(format: "%.1f", batchElapsed)
        let totalQSOs = state.allFetched.count
        debugLog.debug(
            "Batch completed: \(batchCount) activations in \(elapsedStr)s, total QSOs=\(totalQSOs)",
            service: .pota
        )

        // Gradually increase batch size after consecutive successes
        if state.consecutiveSuccesses >= 3,
           state.currentBatchSize < POTADownloadConfig.maximumBatchSize
        {
            let oldBatchSize = state.currentBatchSize
            state.currentBatchSize = min(
                state.currentBatchSize + 5, POTADownloadConfig.maximumBatchSize
            )
            state.consecutiveSuccesses = 0
            debugLog.info(
                "Adaptive: increasing batchSize \(oldBatchSize) → \(state.currentBatchSize) after 3 successes",
                service: .pota
            )
        }

        saveDownloadCheckpoint(
            POTADownloadCheckpoint(
                processedActivationKeys: state.processedKeys,
                lastBatchDate: Date(),
                adaptiveBatchSize: state.currentBatchSize
            )
        )
    }

    /// Log timeout error with details
    private func logTimeoutError(
        activation: POTARemoteActivation,
        elapsed: TimeInterval,
        error: Error
    ) {
        let debugLog = SyncDebugLog.shared
        let ref = activation.reference
        let date = activation.date
        let elapsedStr = String(format: "%.1f", elapsed)
        let errorDesc = error.localizedDescription
        debugLog.warning(
            "Timeout/rate limit for \(ref) \(date) after \(elapsedStr)s: \(errorDesc)",
            service: .pota
        )
    }
}

// MARK: - ActivationResult

enum ActivationResult {
    case success([POTAFetchedQSO])
    case timeout
    case skipped
}
