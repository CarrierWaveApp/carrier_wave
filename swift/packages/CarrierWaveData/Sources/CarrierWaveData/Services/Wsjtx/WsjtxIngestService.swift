//
//  WsjtxIngestService.swift
//  CarrierWaveData
//
//  Owns the WSJT-X UDP listener (`WsjtxApi`, CAR-281) for an app, bridges its
//  Rust-thread callbacks onto the main actor, and turns `QSOLogged` /
//  `LoggedADIF` broadcasts into rows in the log — exactly once per QSO
//  (CAR-282). Shared by CW Sweep (macOS) and Carrier Wave: Field (iOS).
//
//  This file: persisted settings, live state, app hooks, and the listener
//  lifecycle. The message → QSO path (mapping, dedup, insert) lives in
//  `WsjtxIngestService+Ingest.swift`.
//
//  Write path: the mapped `FfiQso` (from `wsjtxMapQsoLogged` /
//  `wsjtxMapLoggedAdif`) is hydrated into a SwiftData `QSO` via
//  `FfiReflector.hydrate`, inserted into the container's main context, and
//  committed through `commit`. The default commit is a plain `context.save()`
//  — the app's `CwStoreMirror` (shadow/on mode) follows the save into cw-store,
//  the same way CW Sweep's own logger inserts land. iOS can point `commit` at
//  its `QSOWriteSink.commitUpsertBatch` to write cw-store first.
//
//  Dedup: before insert the candidate is checked against the store by id
//  (`FfiQso.id` is a UUIDv5 of the WSJT-X dedup key, so a QSOLogged and its
//  LoggedADIF twin share an id) and by `QSO.deduplicationKey`
//  (call | band | mode | 2-minute bucket) against rows with the same callsign
//  in a ±3-minute window — never a full-table key scan. Re-broadcasts and the
//  ADIF twin are counted in `duplicateCount` and never double-log.
//

import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - WsjtxIngestService

@MainActor
@Observable
public final class WsjtxIngestService {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - defaults: where `isEnabled` / `host` / `port` persist.
    ///   - api: the UniFFI listener; injectable for tests.
    ///   - defaultHost: bind address used until the user changes it. CW Sweep
    ///     uses loopback (WSJT-X on the same Mac); Field binds `0.0.0.0` so a
    ///     Pi/desktop on the LAN can reach the phone.
    public init(
        defaults: UserDefaults = .standard,
        api: WsjtxApi = WsjtxApi(),
        defaultHost: String = WsjtxIngestService.loopbackHost
    ) {
        self.defaults = defaults
        self.api = api
        isEnabled = defaults.bool(forKey: DefaultsKey.enabled)
        let storedHost = defaults.string(forKey: DefaultsKey.host)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        host = storedHost.isEmpty ? defaultHost : storedHost
        let storedPort = defaults.integer(forKey: DefaultsKey.port)
        port = (1 ... Int(UInt16.max)).contains(storedPort) ? UInt16(storedPort) : Self.defaultPort
    }

    // MARK: Public

    public enum DefaultsKey {
        public static let enabled = "wsjtx.listener.enabled"
        public static let host = "wsjtx.listener.host"
        public static let port = "wsjtx.listener.port"
    }

    public static let loopbackHost = "127.0.0.1"
    public static let anyHost = "0.0.0.0"
    /// WSJT-X's default UDP Server port (2237).
    public static let defaultPort: UInt16 = wsjtxDefaultPort()
    /// Ring-buffer cap for `recentEvents`.
    public static let maxRecentEvents = 60

    // MARK: Live state

    public private(set) var isRunning = false
    public private(set) var isStarting = false
    /// The OS-assigned port when running (differs from `port` only if `port == 0`).
    public private(set) var boundPort: UInt16?
    public internal(set) var lastError: String?
    /// Newest last. Bounded to `maxRecentEvents`.
    public internal(set) var recentEvents: [WsjtxIngestEvent] = []
    public internal(set) var loggedCount = 0
    public internal(set) var duplicateCount = 0
    /// e.g. "K1ABC · 20m FT8" — for a status-bar line after the last insert.
    public internal(set) var lastLoggedSummary: String?
    public internal(set) var lastLoggedAt: Date?
    public internal(set) var lastHeartbeatAt: Date?
    public internal(set) var lastStatus: WsjtxStatusSummary?
    /// `id` of the WSJT-X instance whose heartbeat we last saw.
    public internal(set) var connectedClientId: String?

    // MARK: App hooks

    /// Session to attach incoming QSOs to. Default: the most recently started
    /// `LoggingSession` whose status is `active` (casual included), or `nil`
    /// — in which case the QSO stays loose (`loggingSessionId == nil`), the
    /// same as CW Sweep's own logger when no session is running.
    public var sessionProvider: (@MainActor (ModelContext) -> LoggingSession?)?

    /// Operator callsign used when WSJT-X leaves `my_call` blank. Default:
    /// the shared Keychain callsign, then `UserDefaults["myCallsign"]`.
    public var stationCallsignProvider: @MainActor () -> String? = {
        if let keychain = try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign),
           !keychain.isEmpty
        {
            return keychain
        }
        let fallback = UserDefaults.standard.string(forKey: "myCallsign")?
            .trimmingCharacters(in: .whitespaces).uppercased()
        return (fallback?.isEmpty == false) ? fallback : nil
    }

    /// Persists freshly inserted QSOs. Default: `context.save()` (the
    /// `CwStoreMirror` follows). iOS routes this through `QSOWriteSink`.
    public var commit: @MainActor ([QSO], ModelContext) throws -> Void = { _, context in
        try context.save()
    }

    /// Fired after each successful insert (log-table refresh, toasts, enrichment).
    public var onQSOLogged: (@MainActor (QSO) -> Void)?

    /// The context inserts land in. Set by `configure(container:)`.
    /// The container inserts land in — retained so its main context stays valid.
    public private(set) var modelContainer: ModelContainer?

    // MARK: Persisted settings

    /// User intent: start the listener at launch and keep it running.
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: DefaultsKey.enabled) }
    }

    /// Bind address. `127.0.0.1` for a local WSJT-X, `0.0.0.0` to accept from the LAN.
    public var host: String {
        didSet { defaults.set(host, forKey: DefaultsKey.host) }
    }

    /// Bind port; WSJT-X → Settings → Reporting → UDP Server must send here.
    public var port: UInt16 {
        didSet { defaults.set(Int(port), forKey: DefaultsKey.port) }
    }

    /// True when a QSO can actually be written.
    public var isConfigured: Bool {
        modelContainer != nil
    }

    /// The context inserts land in — the container's main context. Set by
    /// `configure(container:)`.
    public var modelContext: ModelContext? {
        modelContainer?.mainContext
    }

    /// Parse a user-typed port; `nil` for anything outside 1...65535.
    public static func parsePort(_ text: String) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), (1 ... Int(UInt16.max)).contains(value) else {
            return nil
        }
        return UInt16(value)
    }

    public func configure(container: ModelContainer) {
        modelContainer = container
    }

    /// Call once at app launch after `configure(container:)`.
    public func startIfEnabled() async {
        guard isEnabled else {
            return
        }
        await start()
    }

    public func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        if enabled {
            await start()
        } else {
            stop()
        }
    }

    /// Update the endpoint; restarts the listener if it is running.
    public func applyEndpoint(host newHost: String, port newPort: UInt16) async {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveHost = trimmed.isEmpty ? Self.loopbackHost : trimmed
        guard effectiveHost != host || newPort != port else {
            return
        }
        host = effectiveHost
        port = newPort
        if isRunning || isStarting {
            stop()
            await start()
        }
    }

    public func start() async {
        guard !isRunning, !isStarting else {
            return
        }
        isStarting = true
        defer { isStarting = false }
        lastError = nil
        generation &+= 1
        let token = generation
        let bridge = WsjtxDelegateBridge { [weak self] event in
            Task { @MainActor in
                self?.handle(event, generation: token)
            }
        }
        self.bridge = bridge
        do {
            let bound = try await api.start(host: host, port: port, delegate: bridge)
            boundPort = bound
            isRunning = true
            record(.info, "Listening on \(host):\(bound)")
        } catch {
            isRunning = false
            boundPort = nil
            let message = Self.describe(error)
            lastError = message
            record(.error, "Could not start: \(message)")
        }
    }

    public func stop() {
        generation &+= 1
        let wasRunning = isRunning
        api.stop()
        bridge = nil
        isRunning = false
        boundPort = nil
        if wasRunning {
            record(.info, "Stopped")
        }
    }

    public func clearFeed() {
        recentEvents.removeAll()
    }

    // MARK: Internal

    static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    func record(_ kind: WsjtxIngestEvent.Kind, _ text: String) {
        recentEvents.append(WsjtxIngestEvent(kind: kind, text: text))
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - Self.maxRecentEvents)
        }
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let api: WsjtxApi
    /// Strong ref so the delegate outlives the `start` call regardless of how
    /// the Rust side retains it; replaced on every start.
    private var bridge: WsjtxDelegateBridge?
    /// Bumped on every start/stop so callbacks from a superseded listener are dropped.
    private var generation: UInt64 = 0

    private func handle(_ event: WsjtxDelegateBridge.Event, generation token: UInt64) {
        guard token == generation else {
            return
        }
        switch event {
        case let .message(message, sender):
            handleMessage(message, from: sender)
        case let .error(message):
            lastError = message
            record(.error, message)
        case .stopped:
            isRunning = false
            boundPort = nil
            bridge = nil
            if isEnabled {
                record(.info, "Listener stopped")
            }
        }
    }
}
