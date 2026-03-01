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
    var remoteQSOMap: POTARemoteQSOMap = [:]
}

// MARK: - POTAClient Adaptive Download

extension POTAClient {
    /// Process a single activation: fetch QSOs, build remote map, convert to FetchedQSO
    func processActivation(
        _ activation: POTARemoteActivation,
        state: inout POTADownloadState
    ) async throws -> ActivationResult {
        let debugLog = SyncDebugLog.shared
        let key = "\(activation.reference)|\(activation.date)"
        let startTime = Date()

        do {
            let qsos = try await fetchActivationWithTimeout(activation)
            state.processedKeys.insert(key)

            // Build dedup keys from raw remote QSOs for gap repair.
            // Use formUnion — POTA may report multiple activations for the same
            // park+callsign+date (e.g. morning and evening sessions). Overwriting
            // with `=` would discard earlier sessions, causing gap repair to flag
            // those QSOs as missing and re-upload them as duplicates.
            let activationKey = buildActivationKeyForRemote(activation)
            let dedupKeys = Set(qsos.compactMap { buildRemoteDedupKey($0) })
            if !dedupKeys.isEmpty {
                state.remoteQSOMap[activationKey, default: Set()].formUnion(dedupKeys)
            }

            let fetched = qsos.compactMap { convertToFetchedQSO($0, activation: activation) }
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

// MARK: - POTA Dedup Key Normalization

extension POTAClient {
    /// Strip portable/mobile suffixes from callsigns for activation key matching.
    /// POTA may store "K7ABC/P" while the local QSO has "K7ABC" or vice versa.
    /// Strips trailing segments of 1-3 chars (common suffixes: /P, /M, /MM, /QRP, /R).
    nonisolated static func normalizeCallsign(_ callsign: String) -> String {
        var base = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        // Strip trailing short suffixes (e.g., /P, /M, /QRP)
        while let slashRange = base.range(of: "/", options: .backwards) {
            let suffix = base[base.index(after: slashRange.lowerBound)...]
            guard suffix.count <= 3 else {
                break
            }
            base = String(base[..<slashRange.lowerBound])
        }
        return base
    }

    /// Normalize mode for dedup key matching.
    /// POTA normalizes phone sub-modes (USB, LSB, FM, AM) to "SSB" in its `mode` field.
    /// We must do the same locally so keys match.
    nonisolated static func normalizeModeForDedup(_ mode: String) -> String {
        let upper = mode.uppercased().trimmingCharacters(in: .whitespaces)
        if ModeEquivalence.phoneModes.contains(upper) {
            return "SSB"
        }
        return upper
    }
}

// MARK: - Remote Dedup Key Helpers

extension POTAClient {
    /// Build an activation key from a remote activation for gap repair matching.
    /// Format: "PARKREF|CALLSIGN|YYYY-MM-DD"
    func buildActivationKeyForRemote(_ activation: POTARemoteActivation) -> String {
        let call = POTAClient.normalizeCallsign(activation.callsign)
        return "\(activation.reference.uppercased())|\(call)|\(activation.date)"
    }

    /// Build a dedup key from a remote QSO for gap repair comparison.
    /// Format: "WORKEDCALL|BAND|MODE|HHMM" where HHMM is 2-minute bucketed.
    func buildRemoteDedupKey(_ qso: POTARemoteQSO) -> String? {
        guard let band = qso.band, let mode = qso.mode else {
            return nil
        }
        let call = qso.workedCallsign.uppercased().trimmingCharacters(in: .whitespaces)
        let bandStr = band.uppercased().trimmingCharacters(in: .whitespaces)
        let modeStr = POTAClient.normalizeModeForDedup(mode)

        // Parse qsoDateTime ("yyyy-MM-dd'T'HH:mm:ss") to extract HH:MM bucketed
        let time = bucketRemoteTime(qso.qsoDateTime)
        return "\(call)|\(bandStr)|\(modeStr)|\(time)"
    }

    /// Bucket a remote QSO datetime string to 2-minute resolution.
    /// Input format: "yyyy-MM-dd'T'HH:mm:ss". Returns "HHMM".
    private func bucketRemoteTime(_ dateTimeStr: String) -> String {
        // Extract HH:mm from the datetime string (chars 11-15)
        let components = dateTimeStr.split(separator: "T")
        guard components.count == 2 else {
            return "0000"
        }
        let timeParts = components[1].split(separator: ":")
        guard timeParts.count >= 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1])
        else {
            return "0000"
        }
        let bucketed = minute - (minute % 2)
        return String(format: "%02d%02d", hour, bucketed)
    }
}

// MARK: - ActivationResult

enum ActivationResult {
    case success([POTAFetchedQSO])
    case timeout
    case skipped
}
