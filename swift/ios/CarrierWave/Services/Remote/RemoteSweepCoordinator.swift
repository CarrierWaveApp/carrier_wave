import CarrierWaveCore
import CarrierWaveData
import Network
import SwiftData
import UIKit

// MARK: - RemoteSweepCoordinator

//
// @Observable hub for the iOS Remote tab. Owns the active RemoteSweepClient,
// surfaces typed live state to views, and exposes the pair / connect /
// disconnect / tune actions UI binds to. Reconnect-on-drop is implemented as
// exponential backoff while a "preferred" sweep is selected.

@MainActor
@Observable
final class RemoteSweepCoordinator {
    // MARK: Lifecycle

    init() {
        preferredSweepName = UserDefaults.standard.string(forKey: Self.preferredKey)
        registerLocalSessionObserver()
    }

    deinit {
        // task will hold a strong ref; nothing to do here
    }

    // MARK: Internal

    // MARK: - Public state

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case awaitingPairing
        case connected
        case error(String)
    }

    static let preferredKey = "remote.sweep.preferredSweepName"

    /// Internally settable so the `+Multipeer` extension can drive the
    /// connect lifecycle from a different file.
    var connectionState: ConnectionState = .idle
    private(set) var serverName: String?
    private(set) var serverVersion: String?
    var serverPlatform: String = ""
    private(set) var radioState: RadioStateEvent?
    /// Internal-set so `RemoteSweepCoordinator+Spots` can mutate.
    var spots: [RemoteSpot] = []
    /// Last error surfaced by any Remote-side action; nil when the
    /// coordinator is healthy. Cross-file extensions write via
    /// `recordError(_)` instead of touching the property directly.
    var lastError: String?

    /// Saved queries Sweep is offering. Empty until the queries.list event
    /// arrives after subscribe.
    private(set) var savedQueries: [RemoteSavedQuery] = []
    /// The filter mode Sweep currently has active.
    private(set) var filterMode: RemoteFilterMode = .widgets
    /// Live mirror of Sweep's bridge keyer state. nil until first cw.keyer
    /// event arrives (or when Sweep has no radio connected).
    private(set) var cwStatus: CWStatusEvent?
    /// Live mirror of Sweep's CW memory slots (1...8, includes empty slots
    /// so the editor can target them). Populated from the cw.slots topic.
    private(set) var cwSlots: [RemoteCWSlot] = []
    /// Last LAN-delivered active session snapshot from Sweep. Used by
    /// the continuity hook to detect when Sweep just started a new
    /// activation we should mirror locally. Written by
    /// `RemoteSweepCoordinator+Session.handleRemoteActiveSession`.
    var remoteActiveSession: RemoteSessionState?

    /// Per-topic loading flags so views can show progress while initial
    /// snapshots are still in flight after subscribe. Each flips to false
    /// either when the first event arrives or after a short watchdog.
    private(set) var radioStateLoading = false
    private(set) var spotsLoading = false
    private(set) var queriesLoading = false
    private(set) var cwStatusLoading = false
    private(set) var cwSlotsLoading = false

    /// Live mirror of Sweep's waterfall (newest line first, 0..1 floats).
    /// Empty until the user opens a waterfall view (we don't subscribe by
    /// default to keep the LAN budget low when no one's watching).
    /// Mutated by `RemoteSweepCoordinator+Waterfall` — kept at internal-set
    /// so the extension can write without making everyone a free editor.
    var waterfallLines: [RegisteredWaterfallLine] = []
    var waterfallSourceLabel: String = "None"
    var waterfallCenterMHz: Double = 0
    var waterfallSpanKHz: Double = 0
    var waterfallActiveBinCount: Int = 0
    /// Toggled by the iOS waterfall view when it appears / disappears.
    var waterfallSubscribed = false
    /// Sequence cursor used to drop out-of-order events.
    var waterfallLastSequence: UInt64 = 0

    /// Audio relay state mutated by `RemoteSweepCoordinator+Audio`.
    var audioFormat: AudioFormatEvent?
    var audioSubscribed = false
    var audioLastSequence: UInt32 = 0
    let audioPlayer = RemoteSweepAudioPlayer()
    /// Read by `RemoteSweepCoordinator+Session` to push session
    /// snapshots. Written only by `connect` / `disconnect`.
    var client: RemoteSweepClient?
    /// Most-recent local active-session snapshot we've heard about
    /// from `LoggingSessionManager`. Pushed on every connect and on
    /// every change while connected.
    var pendingLocalSessionPush: RemoteSessionState?

    var currentSweepName: String?

    /// The Sweep most recently picked / paired with. Persisted by name.
    /// Internally settable so the multipeer/LAN connect helpers in the
    /// `+Multipeer` extension can update it without re-declaring storage.
    var preferredSweepName: String? {
        didSet { UserDefaults.standard.set(preferredSweepName, forKey: Self.preferredKey) }
    }

    /// True iff Sweep has reported that its bridge keyer is connected and
    /// usable. Views should disable CW controls when this is false.
    var isRemoteCWKeyerAvailable: Bool {
        cwStatus?.keyerAvailable ?? false
    }

    static func deviceName() async -> String {
        await MainActor.run { UIDevice.current.name }
    }

    /// Enable silent auto-reconnect to the previously paired Sweep.
    /// Idempotent. Once enabled, the coordinator watches for the
    /// preferred Sweep on the LAN whenever the app is foregrounded
    /// and reconnects with the stored token.
    func enableAutoConnect() {
        guard autoConnect == nil else {
            return
        }
        let helper = RemoteSweepAutoConnect(coordinator: self)
        autoConnect = helper
        helper.start()
    }

    /// Begin a connection to a discovered Sweep. If we have a token cached for
    /// its host name, we'll reconnect silently; otherwise the UI will prompt
    /// for a pairing code.
    func connect(to sweep: RemoteSweepDiscovery.DiscoveredSweep) async {
        await establish(serverName: sweep.name) {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let connection = NWConnection(to: sweep.endpoint, using: parameters)
            let queue = DispatchQueue(label: "app.carrierwave.field.remote-sweep", qos: .utility)
            return NWConnectionTransport(connection: connection, queue: queue)
        }
    }

    /// Disconnect without forgetting the preferred sweep.
    func disconnect() async {
        if let client {
            await client.disconnect()
        }
        client = nil
        currentSweepName = nil
        radioState = nil
        spots.removeAll()
        savedQueries.removeAll()
        cwStatus = nil
        cwSlots.removeAll()
        waterfallLines.removeAll()
        waterfallActiveBinCount = 0
        waterfallSubscribed = false
        waterfallLastSequence = 0
        audioFormat = nil
        audioSubscribed = false
        audioLastSequence = 0
        audioPlayer.stop()
        radioStateLoading = false
        spotsLoading = false
        queriesLoading = false
        cwStatusLoading = false
        cwSlotsLoading = false
        loadingWatchdogs.values.forEach { $0.cancel() }
        loadingWatchdogs.removeAll()
        if connectionState != .idle {
            connectionState = .idle
        }
    }

    /// Forget the preferred sweep AND disconnect; revoking the token from the
    /// macOS side is a separate user action there.
    func unpair() async {
        if let name = currentSweepName ?? preferredSweepName {
            RemoteSweepKeychain.deleteToken(for: name)
        }
        preferredSweepName = nil
        await disconnect()
    }

    /// Submit a 6-digit pairing code typed by the user.
    func submitPairingCode(_ code: String) async {
        guard let client else {
            return
        }
        do {
            _ = try await client.submitPairing(code: code)
            // Token will be persisted by the .paired event handler.
        } catch {
            connectionState = .error("Pairing failed: \(error.localizedDescription)")
        }
    }

    /// Ask Sweep to switch the band-scope filter to widgets or to a specific
    /// saved query. Returns true on ack.success.
    @discardableResult
    func setFilterMode(_ mode: RemoteFilterMode) async -> Bool {
        guard let client else {
            return false
        }
        do {
            let ack = try await client.setQuerySelection(mode: mode)
            if !ack.success {
                lastError = ack.detail ?? "set filter failed"
            }
            return ack.success
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Convenience: send a tune command to the active radio.
    @discardableResult
    func tune(freqHz: UInt64, mode: String? = nil) async -> Bool {
        guard let client else {
            return false
        }
        do {
            let ack = try await client.sendTune(freqHz: freqHz, mode: mode)
            if !ack.success {
                lastError = ack.detail ?? "tune failed"
            }
            return ack.success
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func runCWCommand(
        label: String,
        action: (RemoteSweepClient) async throws -> Ack
    ) async -> Bool {
        guard let client else {
            lastError = "\(label): not connected"
            return false
        }
        do {
            let ack = try await action(client)
            if !ack.success {
                lastError = ack.detail ?? "\(label) failed"
            }
            return ack.success
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func handle(event: RemoteSweepClient.Event, sweepName: String) {
        switch event {
        case let .status(status):
            apply(status: status)
        case let .helloAck(ack):
            serverName = ack.serverName
            serverVersion = ack.serverVersion
            serverPlatform = ack.serverPlatform
        case let .paired(paired):
            RemoteSweepKeychain.saveToken(paired.token, for: sweepName)
            connectionState = .connected
            Task {
                await subscribeAll()
            }
        case let .radioState(state):
            radioState = state
            finishLoading(.radioState)
        case let .spot(spot):
            applySpot(spot)
            finishLoading(.spotsFeed)
        case let .queriesList(queries):
            savedQueries = queries
            finishLoading(.queriesList)
        case let .querySelection(mode):
            filterMode = mode
            // When Sweep switches to widgets/another query, the spot stream
            // it sends will already reflect the new filter; clear local cache
            // so we don't show stale entries from the previous filter.
            spots.removeAll()
        case let .cwStatus(status):
            cwStatus = status
            finishLoading(.cwKeyer)
        case let .cwSlots(slots):
            cwSlots = slots
            finishLoading(.cwSlots)
        case let .activeSession(event):
            handleRemoteActiveSession(event)
        case let .waterfallLine(event):
            applyWaterfallLine(event)
        case let .waterfallCleared(event):
            applyWaterfallCleared(event)
        case let .audioFormat(event):
            applyAudioFormat(event)
        case let .audioFrame(event):
            applyAudioFrame(event)
        case let .error(err):
            lastError = "\(err.code.rawValue): \(err.message)"
        }
    }

    // MARK: Private

    private var loadingWatchdogs: [RemoteOpTopic: Task<Void, Never>] = [:]
    private var autoConnect: RemoteSweepAutoConnect?

    private func apply(status: RemoteSweepClient.Status) {
        switch status {
        case .disconnected:
            connectionState = .idle
        case .connecting,
             .authenticating:
            connectionState = .connecting
        case .awaitingPairing:
            connectionState = .awaitingPairing
        case .connected:
            connectionState = .connected
            Task { await subscribeAll() }
        case let .failed(message):
            connectionState = .error(message)
        }
    }

    private func subscribeAll() async {
        guard let client else {
            return
        }
        beginLoading(.radioState, watchdog: 2.5)
        beginLoading(.spotsFeed, watchdog: 2.5)
        beginLoading(.queriesList, watchdog: 5)
        beginLoading(.cwKeyer, watchdog: 2.5)
        beginLoading(.cwSlots, watchdog: 2.5)
        await client.subscribe(.radioState)
        await client.subscribe(.spotsFeed)
        await client.subscribe(.queriesList)
        await client.subscribe(.querySelection)
        await client.subscribe(.cwKeyer)
        await client.subscribe(.cwSlots)
        await client.subscribe(.activeSession)
        // Push our current session so Sweep can adopt it without
        // waiting for CloudKit. No-op if we don't have one locally.
        if let pending = pendingLocalSessionPush {
            _ = try? await client.setActiveSession(pending)
        }
    }

    private func beginLoading(_ topic: RemoteOpTopic, watchdog seconds: TimeInterval) {
        setLoading(topic, true)
        loadingWatchdogs[topic]?.cancel()
        loadingWatchdogs[topic] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else {
                return
            }
            self?.finishLoading(topic)
        }
    }

    private func finishLoading(_ topic: RemoteOpTopic) {
        loadingWatchdogs[topic]?.cancel()
        loadingWatchdogs.removeValue(forKey: topic)
        setLoading(topic, false)
    }

    private func setLoading(_ topic: RemoteOpTopic, _ value: Bool) {
        switch topic {
        case .radioState: radioStateLoading = value
        case .spotsFeed: spotsLoading = value
        case .queriesList: queriesLoading = value
        case .cwKeyer: cwStatusLoading = value
        case .cwSlots: cwSlotsLoading = value
        case .activeSession,
             .radioMeters,
             .querySelection,
             .waterfall,
             .audio: break
        }
    }
}
