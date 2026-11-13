@preconcurrency import Foundation
import OSLog
import Synchronization

// MARK: - StartupProfiler

/// Records timestamped milestones during app launch and beyond.
///
/// Thread-safe: milestones can be recorded from any thread or actor.
/// Enable via the "Startup Profiler" toggle in Developer settings.
/// The trace persists as JSON in the app's caches directory and can be
/// shared from Settings → Developer → Startup Profile.
///
/// After startup completes, the profiler continues recording view appearances
/// and tab switches. Call `record(_:)` at any time while the profiler is active.
nonisolated final class StartupProfiler: Sendable {
    // MARK: Lifecycle

    private init() {
        _state = .init(.idle)
    }

    // MARK: Internal

    static let shared = StartupProfiler()

    /// UserDefaults key — must match `@AppStorage("startupProfilerEnabled")`.
    static let enabledKey = "startupProfilerEnabled"

    /// Whether profiling is currently active for this launch.
    var isRunning: Bool {
        switch _state.withLock({ $0 }) {
        case .recording,
             .monitoring:
            true
        default:
            false
        }
    }

    /// Completed or in-progress trace from the most recent profiled launch.
    var lastTrace: StartupTrace? {
        let qsoCount = _qsoCount.withLock { $0 }
        let env = _environment.withLock { $0 }
        return _state.withLock { state -> StartupTrace? in
            switch state {
            case let .done(trace):
                return trace
            case let .monitoring(origin, milestones, startupEnd):
                guard let env else {
                    return nil
                }
                return Self.buildTrace(
                    origin: origin,
                    milestones: milestones,
                    startupEndIndex: startupEnd,
                    qsoCount: qsoCount,
                    environment: env
                )
            case let .recording(origin, milestones):
                guard let env else {
                    return nil
                }
                return Self.buildTrace(
                    origin: origin,
                    milestones: milestones,
                    startupEndIndex: nil,
                    qsoCount: qsoCount,
                    environment: env
                )
            default:
                return nil
            }
        }
    }

    // MARK: - Public API

    /// Call once at the very start of `App.init()`.
    /// Reads the toggle from UserDefaults and begins recording if enabled.
    @MainActor
    func beginIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        guard enabled else {
            loadPersistedTrace()
            return
        }
        let env = EnvironmentSnapshot.capture()
        _environment.withLock { $0 = env }
        let origin = ProcessInfo.processInfo.systemUptime
        _state.withLock { $0 = .recording(origin, []) }
        record("profiler.started")
        // Hang detection now handled by MetricKit (MXDiagnosticPayload)
        logger.info("Startup profiler active")
    }

    /// Record a named milestone with the current wall time and process uptime.
    /// Safe to call from any thread — works during startup and monitoring phases.
    func record(_ label: String) {
        let memoryMB = currentResidentMemoryMB()
        _state.withLock { state in
            let origin: TimeInterval
            var milestones: [StartupTrace.Milestone]

            switch state {
            case let .recording(org, ms):
                origin = org
                milestones = ms
            case let .monitoring(org, ms, idx):
                origin = org
                milestones = ms
                let elapsed = ProcessInfo.processInfo.systemUptime - origin
                milestones.append(
                    StartupTrace.Milestone(
                        label: label,
                        wallTime: Date(),
                        elapsedSeconds: elapsed,
                        threadName: currentThreadName(),
                        residentMemoryMB: memoryMB,
                        hangStartElapsed: nil,
                        hangDurationSeconds: nil
                    )
                )
                state = .monitoring(origin, milestones, idx)
                return
            default:
                return
            }

            let elapsed = ProcessInfo.processInfo.systemUptime - origin
            milestones.append(
                StartupTrace.Milestone(
                    label: label,
                    wallTime: Date(),
                    elapsedSeconds: elapsed,
                    threadName: currentThreadName(),
                    residentMemoryMB: memoryMB,
                    hangStartElapsed: nil,
                    hangDurationSeconds: nil
                )
            )
            state = .recording(origin, milestones)
        }
    }

    /// Record a hang milestone with the elapsed time range for correlation.
    /// Called by `MainThreadHangDetector` when a stall is detected.
    func recordHang(label: String, startUptime: TimeInterval, duration: TimeInterval) {
        let memoryMB = currentResidentMemoryMB()
        _state.withLock { state in
            let origin: TimeInterval
            var milestones: [StartupTrace.Milestone]
            let isMonitoring: Int?

            switch state {
            case let .recording(org, ms):
                origin = org
                milestones = ms
                isMonitoring = nil
            case let .monitoring(org, ms, idx):
                origin = org
                milestones = ms
                isMonitoring = idx
            default:
                return
            }

            let hangStartElapsed = startUptime - origin
            let elapsed = hangStartElapsed + duration
            milestones.append(StartupTrace.Milestone(
                label: label,
                wallTime: Date(),
                elapsedSeconds: elapsed,
                threadName: "hang-detector",
                residentMemoryMB: memoryMB,
                hangStartElapsed: hangStartElapsed,
                hangDurationSeconds: duration
            ))

            if let idx = isMonitoring {
                state = .monitoring(origin, milestones, idx)
            } else {
                state = .recording(origin, milestones)
            }
        }
    }

    /// Marks the end of startup but continues recording view and tab events.
    /// Persists the startup trace and transitions to monitoring mode.
    func finish() {
        record("startup.complete")

        let qsoCount = _qsoCount.withLock { $0 }
        let env = _environment.withLock { $0 }
        let snapshot: StartupTrace? = _state.withLock { state in
            guard case let .recording(origin, milestones) = state,
                  let env
            else {
                return nil
            }
            let startupEndIndex = milestones.count
            state = .monitoring(origin, milestones, startupEndIndex)
            return Self.buildTrace(
                origin: origin,
                milestones: milestones,
                startupEndIndex: startupEndIndex,
                qsoCount: qsoCount,
                environment: env
            )
        }

        if let snapshot {
            persist(snapshot)
            logger.info(
                "Startup phase complete (\(snapshot.milestones.count) milestones), monitoring continues"
            )
        }
    }

    /// Stop all recording and persist the final trace.
    func stop() {
        let qsoCount = _qsoCount.withLock { $0 }
        let env = _environment.withLock { $0 }
        let completed: StartupTrace? = _state.withLock { state in
            guard let env else {
                return nil
            }
            switch state {
            case let .recording(origin, milestones):
                let trace = Self.buildTrace(
                    origin: origin,
                    milestones: milestones,
                    startupEndIndex: nil,
                    qsoCount: qsoCount,
                    environment: env
                )
                state = .done(trace)
                return trace
            case let .monitoring(origin, milestones, idx):
                let trace = Self.buildTrace(
                    origin: origin,
                    milestones: milestones,
                    startupEndIndex: idx,
                    qsoCount: qsoCount,
                    environment: env
                )
                state = .done(trace)
                return trace
            default:
                return nil
            }
        }

        if let completed {
            persist(completed)
            logger.info(
                "Profiler stopped (\(completed.milestones.count) milestones)"
            )
        }
    }

    /// Persist the current trace snapshot without stopping.
    /// Call periodically to avoid losing runtime events on crash.
    func persistSnapshot() {
        guard let trace = lastTrace else {
            return
        }
        persist(trace)
    }

    /// URL of the most recent persisted trace file, or nil.
    func traceFileURL() -> URL? {
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    /// Record the dataset size for inclusion in the trace summary.
    /// Call from the stats pipeline once the total QSO count is known.
    func setQSOCount(_ count: Int) {
        _qsoCount.withLock { $0 = count }
    }

    /// Delete the persisted trace.
    func clearTrace() {
        _state.withLock { $0 = .idle }
        try? FileManager.default.removeItem(at: Self.storageURL)
    }

    /// Load a startup profile trace from an external JSON file.
    /// Returns `true` if the trace was loaded successfully.
    @discardableResult
    func loadTrace(from url: URL) -> Bool {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url),
              let trace = try? JSONDecoder.iso8601.decode(
                  StartupTrace.self, from: data
              )
        else {
            logger.error("Failed to load trace from \(url.lastPathComponent)")
            return false
        }
        _state.withLock { $0 = .done(trace) }
        persist(trace)
        logger.info(
            "Loaded trace from \(url.lastPathComponent) (\(trace.milestones.count) milestones)"
        )
        return true
    }

    // MARK: Private

    /// Internal state machine protected by a Mutex.
    /// - `idle`: profiler not enabled
    /// - `recording`: startup phase, accumulating milestones
    /// - `monitoring`: startup done, still recording view/tab events
    /// - `done`: stopped, final trace available
    private enum State {
        case idle
        case recording(TimeInterval, [StartupTrace.Milestone])
        case monitoring(TimeInterval, [StartupTrace.Milestone], Int)
        case done(StartupTrace)
    }

    private static var storageURL: URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!
        return caches.appendingPathComponent("startup-profile.json")
    }

    private let _state: Mutex<State>

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.carrierwaveapp",
        category: "StartupProfiler"
    )

    /// Dataset size recorded by the stats pipeline for inclusion in the trace.
    private let _qsoCount = Mutex<Int?>(nil)

    /// Environment info captured once at startup on the main actor.
    private let _environment = Mutex<EnvironmentSnapshot?>(nil)

    private func loadPersistedTrace() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let trace = try? JSONDecoder.iso8601.decode(
                  StartupTrace.self, from: data
              )
        else {
            return
        }
        _state.withLock { $0 = .done(trace) }
    }

    private func persist(_ trace: StartupTrace) {
        do {
            let data = try JSONEncoder.iso8601.encode(trace)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            logger.error("Failed to persist startup trace: \(error)")
        }
    }
}

// MARK: - Trace Building Helpers

extension StartupProfiler {
    /// Snapshot of environment info that must be read outside Mutex locks.
    /// `thermalState` and `isLowPowerModeEnabled` are @MainActor-isolated
    /// in recent SDKs, so we capture them before entering nonisolated contexts.
    struct EnvironmentSnapshot {
        let osVersion: String
        let physicalMemoryMB: Int
        let processorCount: Int
        let appVersion: String?
        let buildNumber: String?
        let thermalState: String
        let isLowPowerMode: Bool

        @MainActor
        static func capture() -> EnvironmentSnapshot {
            let info = ProcessInfo.processInfo
            let bundle = Bundle.main
            return EnvironmentSnapshot(
                osVersion: info.operatingSystemVersionString,
                physicalMemoryMB: Int(info.physicalMemory / (1_024 * 1_024)),
                processorCount: info.activeProcessorCount,
                appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
                buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String,
                thermalState: thermalStateLabel(info.thermalState),
                isLowPowerMode: info.isLowPowerModeEnabled
            )
        }
    }

    nonisolated static func buildTrace(
        origin _: TimeInterval,
        milestones: [StartupTrace.Milestone],
        startupEndIndex: Int?,
        qsoCount: Int? = nil,
        environment: EnvironmentSnapshot
    ) -> StartupTrace {
        StartupTrace(
            date: Date(),
            deviceModel: deviceModel(),
            osVersion: environment.osVersion,
            milestones: milestones,
            startupEndIndex: startupEndIndex,
            appVersion: environment.appVersion,
            buildNumber: environment.buildNumber,
            physicalMemoryMB: environment.physicalMemoryMB,
            availableDiskMB: availableDiskSpaceMB(),
            thermalState: environment.thermalState,
            isLowPowerMode: environment.isLowPowerMode,
            processorCount: environment.processorCount,
            qsoCount: qsoCount
        )
    }

    nonisolated private static func availableDiskSpaceMB() -> Int? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ),
            let freeSpace = attrs[.systemFreeSize] as? Int64
        else {
            return nil
        }
        return Int(freeSpace / (1_024 * 1_024))
    }

    private static func thermalStateLabel(
        _ state: ProcessInfo.ThermalState
    ) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    nonisolated private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(
                to: CChar.self,
                capacity: 1
            ) { String(cString: $0) }
        }
    }
}
