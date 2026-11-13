import CarrierWaveCore
import CarrierWaveData
import Foundation
import Network
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RemoteOp")

// MARK: - RemoteOpServerStatus

//
// UI-facing facade for the remote-control LAN server. Owns the NWListener,
// the per-connection actors, and the paired-device registry. Reads radio
// state from RadioManager and SpotAggregator without holding any business
// state itself — RemoteOpService is plumbing.
//
// v1 transport: newline-delimited JSON over plain TCP with mDNS/Bonjour
// discovery and an opaque bearer token issued during pairing. TLS is a
// follow-up.

/// Status of the remote server. Surfaced to UI for the "Remote" settings tab.
enum RemoteOpServerStatus: Equatable {
    case stopped
    case starting
    case ready(port: UInt16)
    case failed(message: String)
}

// MARK: - PairedRemoteDevice

/// One paired iOS client. Persisted on disk; user can revoke.
struct PairedRemoteDevice: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var token: String
    let pairedAt: Date
    var lastSeenAt: Date?
}

// MARK: - RemoteOpService

@MainActor
@Observable
final class RemoteOpService {
    // MARK: Lifecycle

    init() {
        loadPairedDevices()
    }

    // MARK: Internal

    // MARK: - Public state

    /// Current server status.
    private(set) var status: RemoteOpServerStatus = .stopped

    /// All paired devices (across launches).
    private(set) var pairedDevices: [PairedRemoteDevice] = []

    /// Currently active (connected) device IDs.
    private(set) var activeDeviceIDs: Set<UUID> = []

    /// Codec the audio publisher is currently emitting on `radio.audio`.
    /// Set by `RemoteOpPublishers.rebuildOpusEncoder` whenever it swaps
    /// in or out the Opus path; nil falls through to PCM in
    /// `currentAudioFormatEvent`. Single-writer, main-actor only.
    var publishedAudioCodec: AudioCodec?
    /// Samples per Opus packet for the active encoder, mirrored to
    /// `AudioFormatEvent.framesPerPacket` so decoders allocate the right
    /// PCM buffer on the first packet. Nil for PCM.
    var publishedAudioFramesPerPacket: Int?

    /// 6-digit code displayed in Sweep's UI during pairing. Rotates each request.
    private(set) var pairingCode: String?

    // MARK: - Dependencies

    /// Set after init so we don't have a circular dep with RadioManager / SpotAggregator.
    weak var radioManager: RadioManager?
    weak var spotAggregator: SpotAggregator?
    /// Set after init so the CW handlers can fall back to the WinKeyer / CAT
    /// paths when the bridge keyer isn't connected. Without this, `handleSendCW`
    /// would return `bridgeUnavailableAck` for any USB or TCP-CAT radio.
    weak var winKeyerManager: WinKeyerManager?
    /// Strong since SavedQueryStore is an actor (no @Observable lifecycle to weakly hold).
    var savedQueryStore: SavedQueryStore?
    weak var queryRunner: BandScopeQueryRunner?
    /// Strong since CWKeyerService is an actor and shared with the Sweep
    /// settings tab; nil-checks allow the protocol layer to function before
    /// SharedEnvironment has wired it up.
    var cwKeyerService: CWKeyerService?
    /// Live mirror of Sweep's Quick Entry box. The remote CW keyer expands
    /// `{CALL}` / `{RST}` / `{NAME}` / etc. against this so iOS doesn't need
    /// its own parallel entry UI.
    weak var selectionState: SelectionState?

    /// SwiftData container, set by `CWSweepApp` once the schema is open.
    /// Used to fetch / mutate `LoggingSession` rows for the auto-session
    /// continuity feature so Field and Sweep stay in lock-step on the LAN.
    var modelContainer: ModelContainer?

    let serviceName = Host.current().localizedName ?? "CW Sweep"
    let networkQueue = DispatchQueue(label: "com.jsvana.CWSweep.RemoteOp", qos: .utility)

    var listener: NWListener?
    var multipeerListener: MultipeerTransportListener?
    var connections: [UUID: RemoteOpConnection] = [:]

    /// Starts (or restarts) the server. Idempotent.
    func start() {
        guard listener == nil else {
            return
        }
        status = .starting
        rotatePairingCode()
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true

            let newListener = try NWListener(using: parameters, on: .any)
            newListener.service = NWListener.Service(
                name: serviceName,
                type: RemoteOp.bonjourServiceType
            )

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.acceptConnection(connection)
                }
            }

            newListener.start(queue: networkQueue)
            listener = newListener
            if multipeerEnabled {
                startMultipeerListener()
            }
        } catch {
            status = .failed(message: error.localizedDescription)
            logger.error("Failed to start remote server: \(error.localizedDescription)")
        }
    }

    /// Stops the server and tears down active connections.
    func stop() {
        listener?.cancel()
        listener = nil
        stopMultipeerListener()
        for connection in connections.values {
            Task {
                await connection.cancel()
            }
        }
        connections.removeAll()
        activeDeviceIDs.removeAll()
        status = .stopped
    }

    /// Generates a fresh pairing code. UI calls this before showing a code,
    /// or after pairing completes.
    func rotatePairingCode() {
        pairingCode = String(format: "%06d", Int.random(in: 0 ..< 1_000_000))
    }

    /// Removes a paired device; future connections with its token are rejected.
    func revokeDevice(_ deviceID: UUID) {
        pairedDevices.removeAll { $0.id == deviceID }
        savePairedDevices()
        if let connection = connectionForDevice[deviceID] {
            Task { await connection.cancel() }
        }
    }

    // MARK: - Internal hooks (called by RemoteOpConnection)

    /// Validates a `pair` frame. Returns the new device + token on success.
    func consumePairing(code: String, requestedName: String) -> PairedRemoteDevice? {
        guard let active = pairingCode, active == code else {
            return nil
        }
        let device = PairedRemoteDevice(
            id: UUID(),
            name: requestedName.isEmpty ? "Remote Device" : requestedName,
            token: Self.generateToken(),
            pairedAt: Date(),
            lastSeenAt: Date()
        )
        pairedDevices.append(device)
        savePairedDevices()
        rotatePairingCode()
        return device
    }

    /// Returns the device matching the supplied token, or nil if unknown / revoked.
    func deviceForToken(_ token: String) -> PairedRemoteDevice? {
        pairedDevices.first { $0.token == token }
    }

    /// Reports a device as active (or inactive) so UI can show connection dots.
    func setDeviceActive(_ deviceID: UUID, active: Bool, connection: RemoteOpConnection?) {
        if active {
            activeDeviceIDs.insert(deviceID)
            connectionForDevice[deviceID] = connection
            if let idx = pairedDevices.firstIndex(where: { $0.id == deviceID }) {
                pairedDevices[idx].lastSeenAt = Date()
            }
        } else {
            activeDeviceIDs.remove(deviceID)
            connectionForDevice.removeValue(forKey: deviceID)
        }
    }

    /// "Clear" event that subscribers receive immediately on subscribe so
    /// they always start from a known state.
    func currentWaterfallClearedEvent() -> WaterfallClearedEvent {
        WaterfallClearedEvent(
            radioID: radioManager?.activeRadioId?.uuidString ?? "active",
            timestamp: Date()
        )
    }

    /// Snapshot of current radio state for `radio.state` events.
    func currentRadioStateSnapshot() -> RadioStateEvent? {
        guard let manager = radioManager, manager.isConnected else {
            return nil
        }
        let mhz = manager.frequency
        let hz = UInt64((mhz * 1_000_000).rounded())
        return RadioStateEvent(
            radioID: manager.activeRadioId?.uuidString ?? "active",
            radioName: manager.connectedRadioName,
            freqHz: hz,
            mode: manager.mode,
            vfo: nil,
            split: nil,
            isTransmitting: manager.isTransmitting,
            timestamp: Date()
        )
    }

    /// Forwarded by RemoteOpConnection when a `commandTune` frame arrives.
    func handleTune(_ command: TuneCommand) async -> Ack {
        guard let manager = radioManager else {
            return Ack(requestID: command.requestID, success: false, detail: "no radio manager")
        }
        let mhz = Double(command.freqHz) / 1_000_000
        let okFreq = await manager.tuneToFrequency(mhz)
        var okMode = true
        if let mode = command.mode, !mode.isEmpty {
            okMode = await manager.setMode(mode)
        }
        return Ack(
            requestID: command.requestID,
            success: okFreq && okMode,
            detail: okFreq && okMode ? nil : "tune failed"
        )
    }

    /// Snapshot of current spots for the spot feed initial backfill.
    func currentSpotsSnapshot(filter: SubscribeFilter?) -> [RemoteSpot] {
        spotAggregator?.remoteSpots(filter: filter) ?? []
    }

    /// Wire-format snapshot of all saved queries Sweep knows about, with each
    /// query pre-validated for whether it can drive the band scope.
    func currentQueryListSnapshot() async -> [RemoteSavedQuery] {
        guard let store = savedQueryStore else {
            return []
        }
        let queries: [SavedQuery]
        do {
            queries = try await store.list()
        } catch {
            return []
        }
        var output: [RemoteSavedQuery] = []
        output.reserveCapacity(queries.count)
        for query in queries {
            let drives = await queryRunner?.hasSpotIDColumn(sql: query.sql) ?? false
            output.append(RemoteSavedQuery(
                id: query.id,
                name: query.name,
                summary: query.description,
                drivesBandScope: drives
            ))
        }
        return output
    }

    /// Reads the operator's currently-picked filter from UserDefaults — the
    /// same `bandScopeFilterMode` key the macOS UI writes.
    func currentQuerySelectionSnapshot() -> QuerySelectionEvent {
        QuerySelectionEvent(mode: Self.readFilterMode())
    }

    /// Applies a filter-selection change requested by a remote client, then
    /// broadcasts the new selection to every connected client.
    func handleSetQuerySelection(_ command: SetQuerySelectionCommand) async -> Ack {
        switch command.mode {
        case .widgets:
            UserDefaults.standard.set("widgets", forKey: Self.filterModeKey)
            queryRunner?.setQuery(nil)
        case let .savedQuery(id):
            UserDefaults.standard.set("savedQuery:\(id.uuidString)", forKey: Self.filterModeKey)
            guard let store = savedQueryStore else {
                return Ack(requestID: command.requestID, success: false, detail: "no query store")
            }
            do {
                let queries = try await store.list()
                guard let match = queries.first(where: { $0.id == id }) else {
                    return Ack(requestID: command.requestID, success: false, detail: "unknown query id")
                }
                queryRunner?.setQuery(match)
            } catch {
                return Ack(requestID: command.requestID, success: false, detail: error.localizedDescription)
            }
        }
        broadcast(.eventQuerySelection(currentQuerySelectionSnapshot()), topic: .querySelection)
        return Ack(requestID: command.requestID, success: true)
    }

    /// Broadcasts an event frame to all active connections subscribed to a topic.
    func broadcast(_ frame: RemoteOpFrame, topic: RemoteOpTopic) {
        for connection in connections.values {
            Task { await connection.publishIfSubscribed(frame, topic: topic) }
        }
    }

    /// Connections call this when they finish their lifecycle (disconnect / error).
    func connectionDidClose(id: UUID, deviceID: UUID?) {
        connections.removeValue(forKey: id)
        if let deviceID {
            setDeviceActive(deviceID, active: false, connection: nil)
        }
    }

    // MARK: Private

    private static let filterModeKey = "bandScopeFilterMode"

    private var connectionForDevice: [UUID: RemoteOpConnection] = [:]

    // MARK: - Persistence

    private var pairedDevicesURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CWSweep", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("paired_remote_devices.json")
    }

    private static func readFilterMode() -> RemoteFilterMode {
        let raw = UserDefaults.standard.string(forKey: filterModeKey) ?? "widgets"
        if raw == "widgets" {
            return .widgets
        }
        if raw.hasPrefix("savedQuery:"),
           let id = UUID(uuidString: String(raw.dropFirst("savedQuery:".count)))
        {
            return .savedQuery(id)
        }
        return .widgets
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            let port = listener?.port?.rawValue ?? 0
            status = .ready(port: port)
            logger.info("Remote server ready on port \(port)")
        case let .failed(error):
            status = .failed(message: error.localizedDescription)
            logger.error("Remote server failed: \(error.localizedDescription)")
            stop()
        case .cancelled:
            if case .stopped = status {
                // already stopped
            } else {
                status = .stopped
            }
        default:
            break
        }
    }

    private func loadPairedDevices() {
        guard let data = try? Data(contentsOf: pairedDevicesURL) else {
            return
        }
        if let devices = try? JSONDecoder().decode([PairedRemoteDevice].self, from: data) {
            pairedDevices = devices
        }
    }

    private func savePairedDevices() {
        guard let data = try? JSONEncoder().encode(pairedDevices) else {
            return
        }
        try? data.write(to: pairedDevicesURL, options: .atomic)
    }
}

// MARK: - Audio snapshot

extension RemoteOpService {
    /// Snapshot of the currently broadcast audio format for `radio.audio`
    /// subscribers. Returns nil while no upstream radio is supplying audio.
    /// If the audio publisher has an Opus encoder live (`publishedAudioCodec`
    /// is `.opus`), the codec, `bitsPerSample = 0`, and `framesPerPacket`
    /// fields are reported so the decoder side can allocate buffers.
    func currentAudioFormatEvent() -> AudioFormatEvent? {
        guard let manager = radioManager,
              let format = manager.radioAudioBroadcaster.currentFormat
        else {
            return nil
        }
        let pcmCodec: AudioCodec
        switch format.codecTag {
        case "pcm_s16le": pcmCodec = .pcmS16LE
        default: return nil
        }
        let emittedCodec = publishedAudioCodec ?? pcmCodec
        let bits = emittedCodec == .opus ? 0 : format.bitsPerSample
        return AudioFormatEvent(
            radioID: manager.radioAudioBroadcaster.radioID,
            sourceLabel: manager.radioAudioBroadcaster.sourceLabel,
            codec: emittedCodec,
            sampleRate: format.sampleRate,
            channels: format.channels,
            bitsPerSample: bits,
            framesPerPacket: emittedCodec == .opus ? publishedAudioFramesPerPacket : nil,
            timestamp: Date()
        )
    }
}
