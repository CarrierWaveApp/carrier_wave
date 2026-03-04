import CarrierWaveData
import Foundation

// MARK: - LoTWClient Adaptive Windowing

@MainActor
extension LoTWClient {
    /// Fetch QSOs using adaptive date windowing
    /// Starts with large windows, shrinks on rate limit errors
    /// - Parameter ownCall: If provided, filters to QSOs where the user operated as this callsign
    func fetchQSOsWithAdaptiveWindowing(
        credentials: (username: String, password: String),
        startDate: Date,
        endDate: Date,
        ownCall: String? = nil
    ) async throws -> LoTWResponse {
        let debugLog = SyncDebugLog.shared
        var state = AdaptiveWindowState(
            startDate: startDate,
            endDate: endDate,
            ownCall: ownCall
        )

        let totalDays =
            Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        debugLog.info(
            "Starting adaptive download: \(formatDate(startDate)) to \(formatDate(endDate)) (\(totalDays) days)",
            service: .lotw
        )
        debugLog.debug(
            "Adaptive config: initialWindow=\(state.windowDays) days, minWindow=30 days, maxWindow=365 days",
            service: .lotw
        )

        while state.currentStart < endDate {
            let windowEnd = min(
                Calendar.current.date(
                    byAdding: .day, value: state.windowDays, to: state.currentStart
                )!,
                endDate
            )

            let result = try await processWindow(
                credentials: credentials,
                windowEnd: windowEnd,
                state: &state
            )

            if case .abort = result {
                break
            }
        }

        debugLog.info(
            "Adaptive download complete: \(state.allQSOs.count) total QSOs", service: .lotw
        )

        return LoTWResponse(
            qsos: state.allQSOs,
            lastQSL: state.lastQSL,
            lastQSORx: state.lastQSORx,
            recordCount: state.allQSOs.count
        )
    }

    // MARK: - Window Processing

    private func processWindow(
        credentials: (username: String, password: String),
        windowEnd: Date,
        state: inout AdaptiveWindowState
    ) async throws -> WindowResult {
        let debugLog = SyncDebugLog.shared
        let windowStartTime = Date()
        let windowInfo =
            "\(formatDate(state.currentStart)) to \(formatDate(windowEnd)) (\(state.windowDays)d)"
        debugLog.debug(
            "Window: \(windowInfo), ok=\(state.consecutiveSuccesses), fail=\(state.consecutiveFailures)",
            service: .lotw
        )

        do {
            let response = try await fetchQSOsForDateRange(
                credentials: credentials, startDate: state.currentStart, endDate: windowEnd,
                ownCall: state.ownCall
            )

            handleWindowSuccess(response: response, windowStartTime: windowStartTime, state: &state)
            advanceWindow(to: windowEnd, state: &state)
            // LoTW enforces strict rate limits - use 3 second delay between requests
            // to avoid "Page Request Limit!" 503 errors
            try await Task.sleep(nanoseconds: 3_000_000_000)
            return .continue
        } catch let error as LoTWError {
            if case let .serviceError(message) = error, isRateLimitError(message) {
                return try await handleRateLimit(state: &state)
            }
            throw error
        }
    }

    private func handleWindowSuccess(
        response: LoTWResponse,
        windowStartTime: Date,
        state: inout AdaptiveWindowState
    ) {
        let debugLog = SyncDebugLog.shared
        let elapsed = Date().timeIntervalSince(windowStartTime)
        state.consecutiveSuccesses += 1
        state.consecutiveFailures = 0

        debugLog.debug(
            "Window succeeded: \(response.qsos.count) QSOs in \(String(format: "%.1f", elapsed))s",
            service: .lotw
        )

        state.allQSOs.append(contentsOf: response.qsos)
        if let qsl = response.lastQSL {
            state.lastQSL = qsl
        }
        if let rx = response.lastQSORx {
            state.lastQSORx = rx
        }
    }

    private func advanceWindow(to windowEnd: Date, state: inout AdaptiveWindowState) {
        let debugLog = SyncDebugLog.shared
        state.currentStart = Calendar.current.date(byAdding: .day, value: 1, to: windowEnd)!

        // Gradually increase window size on success (up to 1 year)
        if state.windowDays < 365, state.consecutiveSuccesses >= 2 {
            let oldWindow = state.windowDays
            state.windowDays = min(state.windowDays * 2, 365)
            state.consecutiveSuccesses = 0
            debugLog.info(
                "Adaptive: increasing window \(oldWindow) → \(state.windowDays) days after 2 successes",
                service: .lotw
            )
        }
    }

    private func handleRateLimit(state: inout AdaptiveWindowState) async throws -> WindowResult {
        let debugLog = SyncDebugLog.shared
        state.consecutiveFailures += 1
        state.consecutiveSuccesses = 0

        // Use exponential backoff: base delay doubles with each consecutive failure
        // LoTW rate limit is per-concurrent-request, and large queries can take 30-60+ seconds
        // to generate server-side, so we need generous delays
        let baseDelaySeconds: UInt64
        let backoffMultiplier = min(state.consecutiveFailures, 4) // Cap at 4x to avoid excessive waits

        // Rate limited - shrink window or wait
        if state.windowDays <= 30 {
            // Already at minimum window, use exponential backoff starting at 30s
            // 30s -> 60s -> 120s -> 240s (capped)
            baseDelaySeconds = 30 * UInt64(1 << (backoffMultiplier - 1))
            let msg =
                "Rate limited at min window (\(state.windowDays)d), "
                    + "wait \(baseDelaySeconds)s (#\(state.consecutiveFailures))"
            debugLog.warning(msg, service: .lotw)
            try await Task.sleep(nanoseconds: baseDelaySeconds * 1_000_000_000)
        } else {
            // Shrink window and use shorter exponential backoff starting at 5s
            // 5s -> 10s -> 20s -> 40s (capped)
            let oldWindow = state.windowDays
            state.windowDays = max(state.windowDays / 2, 30)
            baseDelaySeconds = 5 * UInt64(1 << (backoffMultiplier - 1))
            let msg =
                "Adaptive: rate limited, shrinking \(oldWindow) → \(state.windowDays) days, "
                    + "waiting \(baseDelaySeconds)s"
            debugLog.info(msg, service: .lotw)
            try await Task.sleep(nanoseconds: baseDelaySeconds * 1_000_000_000)
        }

        // Safety: bail if too many consecutive failures
        if state.consecutiveFailures >= 5 {
            debugLog.error(
                "Aborting: \(state.consecutiveFailures) rate limits (got \(state.allQSOs.count) QSOs)",
                service: .lotw
            )
            return .abort
        }
        return .continue
    }
}

// MARK: - AdaptiveWindowState

struct AdaptiveWindowState {
    // MARK: Lifecycle

    init(startDate: Date, endDate: Date, ownCall: String? = nil) {
        currentStart = startDate
        self.endDate = endDate
        self.ownCall = ownCall
    }

    // MARK: Internal

    var currentStart: Date
    let endDate: Date
    let ownCall: String?
    var windowDays = 365
    var consecutiveSuccesses = 0
    var consecutiveFailures = 0
    var allQSOs: [LoTWFetchedQSO] = []
    var lastQSL: Date?
    var lastQSORx: Date?
}

// MARK: - WindowResult

private enum WindowResult {
    case `continue`
    case abort
}
