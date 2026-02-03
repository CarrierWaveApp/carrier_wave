import Foundation

// MARK: - LoTWClient Adaptive Windowing

@MainActor
extension LoTWClient {
    /// Fetch QSOs using adaptive date windowing
    /// Starts with large windows, shrinks on rate limit errors
    func fetchQSOsWithAdaptiveWindowing(
        credentials: (username: String, password: String),
        startDate: Date,
        endDate: Date
    ) async throws -> LoTWResponse {
        let debugLog = SyncDebugLog.shared
        var state = AdaptiveWindowState(
            startDate: startDate,
            endDate: endDate
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
                credentials: credentials, startDate: state.currentStart, endDate: windowEnd
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

        // Rate limited - shrink window or wait
        if state.windowDays <= 30 {
            // Already at minimum, wait and retry
            debugLog.warning(
                "Rate limited at min window (\(state.windowDays)d), wait 30s (#\(state.consecutiveFailures))",
                service: .lotw
            )
            try await Task.sleep(nanoseconds: 30_000_000_000)
        } else {
            // Shrink window
            let oldWindow = state.windowDays
            state.windowDays = max(state.windowDays / 2, 30)
            debugLog.info(
                "Adaptive: rate limited, shrinking \(oldWindow) → \(state.windowDays) days, waiting 5s",
                service: .lotw
            )
            try await Task.sleep(nanoseconds: 5_000_000_000)
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

    init(startDate: Date, endDate: Date) {
        currentStart = startDate
        self.endDate = endDate
    }

    // MARK: Internal

    var currentStart: Date
    let endDate: Date
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
