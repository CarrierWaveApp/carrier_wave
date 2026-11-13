import Foundation
import Synchronization

// MARK: - MainThreadHangDetector

/// Detects main thread hangs by pinging the main run loop from a background
/// thread. When the main thread doesn't respond within the threshold (200ms),
/// a hang is recorded with its duration once the thread resumes.
///
/// Thread-safe via `Mutex`. Integrates with `StartupProfiler` — hangs are
/// recorded as milestones with labels like `hang.main(1.234s)`.
nonisolated final class MainThreadHangDetector: Sendable {
    // MARK: Lifecycle

    init(threshold: TimeInterval = 0.2, pollInterval: TimeInterval = 0.1) {
        self.threshold = threshold
        self.pollInterval = pollInterval
        _state = Mutex(.idle)
    }

    // MARK: Internal

    /// Start detecting hangs. Calls `onHang` with `(startElapsed, duration)` when
    /// a stall exceeding the threshold is detected. `startElapsed` is the
    /// `ProcessInfo.systemUptime` when the hang began — subtract the profiler
    /// origin to get the elapsed-since-launch value for milestone correlation.
    func start(onHang: @escaping @Sendable (_ startUptime: TimeInterval, _ duration: TimeInterval) -> Void) {
        _state.withLock { state in
            guard case .idle = state else {
                return
            }
            state = .running
        }

        let thread = Thread { [weak self] in
            self?.detectionLoop(onHang: onHang)
        }
        thread.name = "com.carrierwaveapp.hang-detector"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Stop the detector. Any in-progress hang is finalized.
    func stop() {
        _state.withLock { $0 = .stopped }
    }

    // MARK: Private

    private enum DetectorState {
        case idle
        case running
        case stopped
    }

    private let threshold: TimeInterval
    private let pollInterval: TimeInterval

    private let _state: Mutex<DetectorState>

    /// Atomic flag toggled by the main queue ping.
    private let _responded = Mutex(true)

    private func detectionLoop(onHang: @escaping @Sendable (TimeInterval, TimeInterval) -> Void) {
        var hangStart: TimeInterval?

        while true {
            let currentState = _state.withLock { $0 }
            if case .stopped = currentState {
                break
            }

            // Reset flag and ping main queue
            _responded.withLock { $0 = false }
            DispatchQueue.main.async { [weak self] in
                self?._responded.withLock { $0 = true }
            }

            // Wait for the poll interval
            Thread.sleep(forTimeInterval: pollInterval)

            let didRespond = _responded.withLock { $0 }

            if !didRespond {
                // Main thread is blocked
                if hangStart == nil {
                    hangStart = ProcessInfo.processInfo.systemUptime
                }
            } else if let start = hangStart {
                // Main thread resumed — record the hang
                let duration = ProcessInfo.processInfo.systemUptime - start
                if duration >= threshold {
                    onHang(start, duration)
                }
                hangStart = nil
            }
        }
    }
}
