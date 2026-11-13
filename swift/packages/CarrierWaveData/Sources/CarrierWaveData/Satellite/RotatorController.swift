import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "RotatorController")

// MARK: - RotatorController

/// Drives one rotator (S.A.T., PSR-100, rotctld) from satellite look angles.
///
/// The host app feeds `setTarget(_:)` each time the tracker's az/el changes;
/// the controller re-sends only when the target moved more than the
/// deadband (the PSR-100 resolves whole degrees), clamps elevation at the
/// horizon, polls the rotor's actual position at `pollInterval`, and reports
/// everything as observable state for the UI. Follow mode is explicit so an
/// operator can connect, watch the readout, and only then let the antenna
/// move.
@MainActor
@Observable
public final class RotatorController {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.endpoint),
           let saved = try? JSONDecoder().decode(TrackerEndpoint.self, from: data)
        {
            savedEndpoint = saved
        }
        minElevationDeg = defaults.object(forKey: Keys.minElevation) as? Double ?? 0
        deadbandDeg = defaults.object(forKey: Keys.deadband) as? Double ?? 1.0
    }

    // MARK: Public

    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        /// Linked and polling; not moving the antenna on its own.
        case idle
        /// Linked and pushing targets.
        case following
        case error(String)

        // MARK: Public

        public var isConnected: Bool {
            switch self {
            case .idle,
                 .following: true
            default: false
            }
        }

        public var label: String {
            switch self {
            case .disconnected: "Disconnected"
            case .connecting: "Connecting…"
            case .idle: "Linked"
            case .following: "Tracking"
            case let .error(message): "Error: \(message)"
            }
        }
    }

    public private(set) var state: State = .disconnected
    /// What the rotor last reported.
    public private(set) var position: RotatorPosition?
    public private(set) var positionUpdatedAt: Date?
    /// The last target the app asked for (even when not following).
    public private(set) var target: RotatorPosition?
    /// The last target actually sent to the rotor.
    public private(set) var commandedTarget: RotatorPosition?
    /// Diagnostics for the UI: the last move/stop sent and what came back.
    public private(set) var lastCommand: String?
    public private(set) var lastReply: String?
    public private(set) var lastCommandAt: Date?
    public private(set) var endpoint: TrackerEndpoint?
    public private(set) var lastError: String?
    /// Remembered across launches; `connectSaved()` uses it.
    public private(set) var savedEndpoint: TrackerEndpoint?

    public var pollInterval: Duration = .seconds(1)

    /// Elevation floor sent to the rotor (mast limit / local horizon).
    public var minElevationDeg: Double {
        didSet { defaults.set(minElevationDeg, forKey: Keys.minElevation) }
    }

    /// Don't re-send a target that moved less than this (degrees).
    public var deadbandDeg: Double {
        didSet { defaults.set(deadbandDeg, forKey: Keys.deadband) }
    }

    public var isConnected: Bool {
        state.isConnected
    }

    public var isFollowing: Bool {
        state == .following
    }

    /// Pointing error between the rotor and the target, when both are known.
    public var pointingErrorDeg: Double? {
        guard let position, let target else {
            return nil
        }
        return position.maxAxisError(to: target.normalized(minElevation: minElevationDeg))
    }

    /// Where a manual jog starts from: the last commanded target, else the
    /// rotor's reported position, else north/horizon.
    public var manualBase: RotatorPosition {
        commandedTarget ?? position ?? RotatorPosition(azimuthDeg: 0, elevationDeg: 0)
    }

    /// Pure jog math (unit-tested): wrap azimuth into 0 ..< 360, clamp
    /// elevation to `minElevation` … 90.
    nonisolated public static func jogged(
        from base: RotatorPosition,
        dAz: Double,
        dEl: Double,
        minElevation: Double
    ) -> RotatorPosition {
        RotatorPosition(azimuthDeg: base.azimuthDeg + dAz, elevationDeg: base.elevationDeg + dEl)
            .normalized(minElevation: minElevation)
    }

    /// Connect to a unit and remember it as the station rotator.
    ///
    /// A PSR-100 asked for over one of its UDP protocols is first tried over
    /// its web server (HTTP control): UDP replies don't cross VLANs and need
    /// the rotor's TX port to point back at us, HTTP just works wherever the
    /// web UI loads. The UDP request is honoured only when HTTP doesn't answer.
    public func connect(to requested: TrackerEndpoint) async {
        await disconnect()
        // Overlapping connects (auto-detect re-link racing a manual tap) must
        // not leave a stale error from the attempt that got superseded.
        connectGeneration &+= 1
        let generation = connectGeneration
        var endpoint = requested
        state = .connecting
        lastError = nil
        var transport = transportFactory(endpoint)
        if requested.kind == .psr100, requested.protocolKind != .psr100HTTP {
            let http = TrackerEndpoint(kind: .psr100, host: requested.host, protocolKind: .psr100HTTP)
            let httpTransport = transportFactory(http)
            let httpOK = await (try? httpTransport.connect()) != nil
            guard generation == connectGeneration else {
                await httpTransport.disconnect()
                return
            }
            if httpOK {
                logger.info("PSR-100 at \(requested.host, privacy: .public): using HTTP control")
                endpoint = http
                transport = httpTransport
            }
        }
        if endpoint == requested {
            do {
                try await transport.connect()
            } catch {
                guard generation == connectGeneration else {
                    return
                }
                logger
                    .error(
                        "rotator connect to \(endpoint.host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                self.endpoint = endpoint
                state = .error(error.localizedDescription)
                lastError = error.localizedDescription
                return
            }
        }
        guard generation == connectGeneration else {
            await transport.disconnect()
            return
        }
        self.endpoint = endpoint
        savedEndpoint = endpoint
        if let data = try? JSONEncoder().encode(endpoint) {
            defaults.set(data, forKey: Keys.endpoint)
        }
        self.transport = transport
        state = .idle
        lastError = nil
        consecutivePollFailures = 0
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollPosition()
                guard let self else {
                    return
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    /// Reconnect to the remembered unit, if any.
    public func connectSaved() async {
        guard let savedEndpoint else {
            return
        }
        await connect(to: savedEndpoint)
    }

    public func forgetSaved() {
        savedEndpoint = nil
        defaults.removeObject(forKey: Keys.endpoint)
    }

    public func disconnect() async {
        pollTask?.cancel()
        pollTask = nil
        if let transport {
            await transport.disconnect()
        }
        transport = nil
        endpoint = nil
        state = .disconnected
        position = nil
        commandedTarget = nil
    }

    /// Start pushing targets to the rotor. The current target (if any) is
    /// sent immediately.
    public func startFollowing() async {
        guard state.isConnected else {
            return
        }
        state = .following
        if let target {
            await push(target, force: true)
        }
    }

    /// Stop pushing targets; the rotor stays where it is.
    public func stopFollowing() {
        if state == .following {
            state = .idle
        }
    }

    /// Update the desired pointing. Sent to the rotor only while following
    /// and only when it moved past the deadband.
    public func setTarget(_ newTarget: RotatorPosition) async {
        target = newTarget
        guard state == .following else {
            return
        }
        await push(newTarget, force: false)
    }

    /// Clear the target (satellite set / deselected). Does not move the rotor.
    public func clearTarget() {
        target = nil
    }

    /// Halt both axes and leave follow mode.
    public func stop() async {
        stopFollowing()
        guard let transport, let endpoint else {
            return
        }
        let command = RotatorProtocolCodec.stopCommand(protocolKind: endpoint.protocolKind)
        lastCommand = String(bytes: command, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastCommandAt = Date()
        let expectsReply = endpoint.protocolKind.expectsReply
        lastReply = try? await Task {
            try await transport.send(command, expectReply: expectsReply, timeout: .seconds(2))
        }
        .value?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        // A stop also resets the manual base to wherever the rotor says it is.
        commandedTarget = nil
    }

    /// Point at a fixed position (park, pre-position at AOS azimuth…).
    public func moveTo(_ position: RotatorPosition) async {
        stopFollowing()
        await push(position, force: true)
    }

    /// Park north at the horizon.
    public func park() async {
        await moveTo(RotatorPosition(azimuthDeg: 0, elevationDeg: 0))
    }

    /// Jog by a step (degrees); leaves follow mode. Azimuth wraps, elevation
    /// clamps to the mast range.
    public func nudge(azimuthBy dAz: Double = 0, elevationBy dEl: Double = 0) async {
        let base = manualBase
        await moveTo(Self.jogged(from: base, dAz: dAz, dEl: dEl, minElevation: minElevationDeg))
    }

    // MARK: Internal

    /// Builds the link for an endpoint; tests swap in a fake.
    var transportFactory: @MainActor (TrackerEndpoint) -> any RotatorTransport = { $0.makeTransport() }

    /// One position poll, for tests.
    func pollOnceForTesting() async {
        await pollPosition()
    }

    // MARK: Private

    private enum Keys {
        static let endpoint = "rotator.endpoint"
        static let minElevation = "rotator.minElevationDeg"
        static let deadband = "rotator.deadbandDeg"
    }

    private let defaults: UserDefaults
    private var transport: (any RotatorTransport)?

    private var pollTask: Task<Void, Never>?
    private var consecutivePollFailures = 0
    private var connectGeneration: UInt64 = 0

    private func push(_ requested: RotatorPosition, force: Bool) async {
        guard let transport, let endpoint else {
            return
        }
        let clamped = requested.normalized(minElevation: minElevationDeg)
        if !force, let commandedTarget, commandedTarget.maxAxisError(to: clamped) < deadbandDeg {
            return
        }
        let command = RotatorProtocolCodec.moveCommand(clamped, protocolKind: endpoint.protocolKind)
        lastCommand = String(bytes: command, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastCommandAt = Date()
        lastReply = nil
        // Record the base for the next jog before the request is in flight,
        // so two quick presses compound instead of both starting from the
        // same position.
        commandedTarget = clamped
        do {
            // Detach the send from the caller's task: a jog button that
            // cancels its task on finger-up must not cancel a move that is
            // already on its way (URLSession would report "cancelled").
            let expectsReply = endpoint.protocolKind.expectsReply
            let reply = try await Task { try await transport.send(
                command,
                expectReply: expectsReply,
                timeout: .seconds(2)
            ) }
            .value
            let trimmedReply = reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lastReply = trimmedReply.isEmpty ? nil : trimmedReply
            let rejected = switch endpoint.protocolKind {
            case .hamlibRotctl: !RotatorProtocolCodec.hamlibReplyIsOK(trimmedReply)
            case .psr100HTTP: trimmedReply.localizedCaseInsensitiveContains("invalid")
            case .easycommII,
                 .gs232B,
                 .csnSATxml: false
            }
            lastError = rejected ? "Rotator rejected move: \(trimmedReply)" : nil
        } catch {
            // The request left; the rotor most likely acted on it, so the
            // optimistic base above stands.
            lastError = "Move sent, no reply: \(error.localizedDescription)"
            logger.error("rotator move failed: \(error.localizedDescription)")
        }
    }

    private func pollPosition() async {
        guard let transport, let endpoint else {
            return
        }
        var partial = RotatorProtocolCodec.PartialPosition()
        do {
            for query in RotatorProtocolCodec.positionQueries(protocolKind: endpoint.protocolKind) {
                guard let reply = try await transport.send(query, expectReply: true, timeout: .seconds(1)),
                      let parsed = RotatorProtocolCodec.parsePosition(reply)
                else {
                    continue
                }
                if let az = parsed.azimuthDeg {
                    partial.azimuthDeg = az
                }
                if let el = parsed.elevationDeg {
                    partial.elevationDeg = el
                }
            }
            if let merged = partial.merged(onto: position) {
                position = merged
                positionUpdatedAt = Date()
            }
            consecutivePollFailures = 0
            if case .error = state {
                state = .idle
            }
        } catch {
            consecutivePollFailures += 1
            let failures = consecutivePollFailures
            logger
                .error(
                    "rotator poll \(failures) failed (\(endpoint.protocolKind.rawValue, privacy: .public) \(endpoint.host, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
            if consecutivePollFailures >= 5, state.isConnected {
                lastError = "Rotator stopped answering (\(endpoint.protocolKind.displayName)): \(error.localizedDescription)"
                state = .error("no reply")
            }
        }
    }
}
