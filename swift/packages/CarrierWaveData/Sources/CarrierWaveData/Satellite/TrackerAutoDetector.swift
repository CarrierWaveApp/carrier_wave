import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "TrackerAutoDetect")

// MARK: - TrackerAutoDetector

/// Hands-free tracker detection. Sweeps the LAN when started, again whenever
/// the network path changes, and every few minutes after that. A unit the
/// station already uses is re-linked silently when it shows up; any other
/// S.A.T. / PSR-100 / rotctld that answers becomes a one-shot prompt
/// (`pending`) the host app shows as "CSN S.A.T. detected — Connect?".
///
/// "Not now" hides a unit for the rest of the session; "Ignore" persists.
@MainActor
@Observable
public final class TrackerAutoDetector {
    // MARK: Lifecycle

    public init(discovery: TrackerDiscoveryService, rotator: RotatorController, defaults: UserDefaults = .standard) {
        self.discovery = discovery
        self.rotator = rotator
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        ignoredHosts = Set(defaults.stringArray(forKey: Keys.ignored) ?? [])
    }

    // MARK: Public

    public let discovery: TrackerDiscoveryService
    public let rotator: RotatorController

    /// The unit waiting for a Connect / Not now / Ignore decision.
    public private(set) var pending: DiscoveredTracker?
    public private(set) var isRunning = false
    public private(set) var lastSweepAt: Date?
    /// Hosts the operator chose to ignore (persisted).
    public private(set) var ignoredHosts: Set<String>

    /// Re-sweep cadence while running.
    public var sweepInterval: Duration = .seconds(180)

    /// Background detection on/off (persisted, default on).
    public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                if wantsRunning {
                    start()
                }
            } else {
                stopLoops()
                pending = nil
            }
        }
    }

    // MARK: - Pure selection logic (unit-tested)

    /// The remembered unit to re-link silently, if the sweep saw it and the
    /// rotator isn't already connected.
    nonisolated public static func autoConnectTarget(
        discovered: [DiscoveredTracker],
        saved: TrackerEndpoint?,
        rotatorConnected: Bool
    ) -> TrackerEndpoint? {
        guard !rotatorConnected, let saved else {
            return nil
        }
        guard let seen = discovered.first(where: { $0.host == saved.host }) else {
            return nil
        }
        // What the sweep saw is ground truth for a PSR-100: the web probe
        // yields HTTP control (works across VLANs), a broadcast reply yields
        // the UDP protocol the rotor is actually set to.
        if seen.kind == .psr100, seen.endpoint.protocolKind != saved.protocolKind {
            return seen.endpoint
        }
        return saved
    }

    /// Which newly seen unit (if any) deserves a prompt. Real trackers
    /// (S.A.T., PSR-100) rank above a generic PC `rotctld`.
    nonisolated public static func promptCandidate(
        discovered: [DiscoveredTracker],
        connectedHost: String?,
        savedHost: String?,
        ignored: Set<String>,
        dismissed: Set<String>
    ) -> DiscoveredTracker? {
        discovered
            .filter { tracker in
                tracker.host != connectedHost
                    && tracker.host != savedHost
                    && !ignored.contains(tracker.host)
                    && !dismissed.contains(tracker.host)
            }
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs.kind)
                let rhsRank = rank(rhs.kind)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.host < rhs.host
            }
            .first
    }

    /// Begin detecting. Idempotent. Sweeps immediately, then on network
    /// changes and every `sweepInterval`.
    public func start() {
        wantsRunning = true
        guard isEnabled, !isRunning else {
            return
        }
        isRunning = true
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                await sweepNow()
                try? await Task.sleep(for: sweepInterval)
            }
        }
        startPathMonitor()
    }

    public func stop() {
        wantsRunning = false
        stopLoops()
    }

    /// One sweep, then reconcile: silent re-link of the remembered unit, or
    /// a prompt for a new one.
    public func sweepNow() async {
        if let saved = rotator.savedEndpoint {
            discovery.remember(host: saved.host)
        }
        await discovery.scan()
        lastSweepAt = Date()
        reconcile()
    }

    /// Operator accepted the prompt: connect and remember the unit.
    public func accept() async {
        guard let tracker = pending else {
            return
        }
        pending = nil
        discovery.remember(host: tracker.host)
        await rotator.connect(to: tracker.endpoint)
    }

    /// Operator declined for now; ask again next launch.
    public func dismiss() {
        if let host = pending?.host {
            dismissedHosts.insert(host)
        }
        pending = nil
    }

    /// Operator never wants to hear about this unit.
    public func ignore() {
        if let host = pending?.host {
            ignoredHosts.insert(host)
            persistIgnored()
        }
        pending = nil
    }

    public func unignore(host: String) {
        ignoredHosts.remove(host)
        dismissedHosts.remove(host)
        persistIgnored()
        reconcile()
    }

    public func clearIgnored() {
        ignoredHosts.removeAll()
        dismissedHosts.removeAll()
        persistIgnored()
        reconcile()
    }

    // MARK: Private

    private enum Keys {
        static let enabled = "tracker.autoDetectEnabled"
        static let ignored = "tracker.ignoredHosts"
    }

    private let defaults: UserDefaults
    private var loopTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var pathDebounce: Task<Void, Never>?
    private var dismissedHosts: Set<String> = []
    private var wantsRunning = false
    private var lastPathSignature: String?

    nonisolated private static func rank(_ kind: TrackerKind) -> Int {
        switch kind {
        case .csnSAT: 0
        case .psr100: 1
        case .hamlibRotctld: 2
        }
    }

    private func stopLoops() {
        loopTask?.cancel()
        loopTask = nil
        pathDebounce?.cancel()
        pathDebounce = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        isRunning = false
    }

    private func reconcile() {
        if let target = Self.autoConnectTarget(
            discovered: discovery.discovered,
            saved: rotator.savedEndpoint,
            rotatorConnected: rotator.isConnected
        ) {
            logger.info("auto-detect: re-linking remembered \(target.kind.displayName) at \(target.host)")
            Task { await rotator.connect(to: target) }
        }
        if pending == nil {
            pending = Self.promptCandidate(
                discovered: discovery.discovered,
                connectedHost: rotator.endpoint?.host,
                savedHost: rotator.savedEndpoint?.host,
                ignored: ignoredHosts,
                dismissed: dismissedHosts
            )
            if let pending {
                logger.info("auto-detect: \(pending.name) at \(pending.host) awaiting operator")
            }
        }
    }

    private func persistIgnored() {
        defaults.set(Array(ignoredHosts).sorted(), forKey: Keys.ignored)
    }

    /// Re-sweep ~2 s after the network path settles (Wi-Fi join, Ethernet
    /// plug-in). The first callback fires immediately on start, which the
    /// signature check swallows.
    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = path.status == .satisfied
                ? path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
                : "down"
            Task { @MainActor [weak self] in
                self?.pathChanged(signature: signature)
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    private func pathChanged(signature: String) {
        guard signature != lastPathSignature else {
            return
        }
        let isFirst = lastPathSignature == nil
        lastPathSignature = signature
        guard !isFirst, signature != "down", isRunning else {
            return
        }
        pathDebounce?.cancel()
        pathDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            await self?.sweepNow()
        }
    }
}

// MARK: - Prompt copy

public extension DiscoveredTracker {
    /// "CSN S.A.T. detected"
    var detectedTitle: String {
        "\(kind.displayName) detected"
    }

    /// "A CSN Technologies S.A.T. is answering at 192.168.1.40 (Hamlib rotctld
    /// 4533). Use it as your station rotator?"
    var detectedMessage: String {
        let how: String = switch kind {
        case .csnSAT: "Hamlib rotctld on port \(endpoint.port) plus its web UI"
        case .psr100: endpoint.protocolKind == .psr100HTTP
            ? "its web interface on port \(endpoint.port)"
            : endpoint.protocolKind.displayName
        case .hamlibRotctld: "Hamlib rotctld on port \(endpoint.port)"
        }
        return "A \(kind.vendor) \(name) is answering at \(host) (\(how)). Use it as your station rotator?"
    }
}
