import CarrierWaveData
import Foundation
import OSLog

private let radioManagerLogger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioManager")

// MARK: - RadioManager

/// Manages radio connections and publishes state to the UI.
/// Supports multiple simultaneous radio connections (SO2R ready).
@MainActor
@Observable
final class RadioManager {
    // MARK: Lifecycle

    init() {
        let store = waterfallStore
        sculan10Waterfall = SCULAN10WaterfallData(
            store: store,
            geometryProvider: { @MainActor in (centerMHz: 0, spanKHz: 0) }
        )
        flexPanadapter = FlexPanadapterService(store: store)
        iqPanadapter = IQPanadapterService(store: store)
        icomWaterfall = IcomWaterfallData(store: store)
        // Replace with a self-capturing provider now that all stored
        // properties are initialized.
        sculan10Waterfall = SCULAN10WaterfallData(
            store: store,
            geometryProvider: { @MainActor [weak self] in
                (
                    centerMHz: self?.frequency ?? 0,
                    spanKHz: self?.scopeSpanKHz ?? 0
                )
            }
        )
        iqPanadapter.startIfEnabled()
    }

    // MARK: Internal

    var sessions: [UUID: RadioSession] = [:]
    var activeRadioId: UUID?

    /// Slot → session UUID mapping. Populated alongside `sessions` so callers
    /// can address radios by stable label (`.a`, `.b`) rather than by the
    /// lifetime-bound UUID. See `RadioManager+Slots`.
    var slots: [RadioSlot: UUID] = [:]

    /// Per-slot observable state. New UI surfaces should consume these
    /// directly; the legacy single-radio fields below mirror the focused
    /// slot for backward compat.
    var slotStates: [RadioSlot: RadioSlotState] = [:]

    /// User-visible focus pointer. Tune commands without an explicit slot,
    /// `radio.frequency`/`radio.mode` reads, and the band-map cursor all
    /// follow this slot. Initialized to `.a` so first-connect lands here.
    var focusedSlot: RadioSlot = .a

    /// Currently active frequency in MHz
    var frequency: Double = 0

    /// Currently active mode
    var mode: String = ""

    /// Scope span in kHz (queried from radio via SS05 command, 0 = unknown)
    var scopeSpanKHz: Double = 0

    /// Whether any radio is connected
    var isConnected: Bool = false

    /// Whether XIT is enabled on the active radio
    var xitEnabled: Bool = false

    /// Whether RIT is enabled on the active radio
    var ritEnabled: Bool = false

    /// Current RIT/XIT offset in Hz
    var ritXitOffset: Int = 0

    /// Whether the active radio is transmitting
    var isTransmitting: Bool = false

    /// Port path of the currently connected radio (nil when disconnected)
    var connectedPortPath: String?

    /// Name of the currently connected radio (nil when disconnected)
    var connectedRadioName: String?

    // MARK: - CW Bridge state (CWBP)

    /// Firmware version of the connected CW Bridge (nil if disconnected).
    var bridgeFirmwareVersion: String?
    /// Bridge capability flag bitmask (see BridgeFrame.Capabilities).
    var bridgeCapabilities: UInt8 = 0
    /// Whether the bridge's USB port has a device connected.
    var bridgeUSBConnected: Bool = false
    /// Detected radio name from the bridge (e.g. "Elecraft K3/KX").
    var bridgeDetectedRadio: String?
    /// Whether the bridge is currently probing for a radio.
    var bridgeDetecting: Bool = false
    /// Whether the bridge has completed CWBP handshake and is framed.
    var bridgeIsFramed: Bool = false
    /// Whether the bridge advertises CW keyer capability.
    var bridgeHasCWKeyer: Bool = false
    /// CW state echoed from firmware (encoder + slot/cwProgress feedback).
    var bridgeCWSendingSlot: Int?
    var bridgeCWSpeed: UInt8 = 25
    var bridgeCWFlags: BridgeFrame.CWProgressFlags = []
    var bridgeCWBufferDepth: UInt8 = 0
    /// Active BridgeProtocol instance (used for CW keyer commands).
    var activeBridge: BridgeProtocol?
    /// Underlying BLE transport for the active bridge session.
    var activeBridgeTransport: BLERadioTransport?
    /// Session ID owned by the active bridge connection.
    var activeBridgeSessionId: UUID?
    /// Running task monitoring bridge events.
    var bridgeEventTask: Task<Void, Never>?
    /// Periodic interrogation of bridge state — polls `requestStatus` so
    /// missed/raced status pushes don't leave the UI stuck.
    var bridgeStatusPollTask: Task<Void, Never>?
    /// Running task monitoring BLE connection state.
    var bridgeStateTask: Task<Void, Never>?

    /// In-app command log for radio TX/RX visibility
    let commandLog = RadioCommandLog()

    /// Source-agnostic waterfall store. Producers (SCU-LAN10 scope, FlexRadio
    /// VITA-49 panadapter) push lines into this store; the layout panel and
    /// the Remote LAN broadcaster both observe it.
    let waterfallStore = WaterfallStore()

    /// SCU-LAN10 producer that drives `waterfallStore` while a Yaesu network
    /// adapter is connected. Initialized in `init()` so its provider closure
    /// can capture `self`.
    private(set) var sculan10Waterfall: SCULAN10WaterfallData

    /// FlexRadio panadapter producer that drives `waterfallStore` while a
    /// SmartSDR connection is active. Initialized in `init()` for symmetry.
    private(set) var flexPanadapter: FlexPanadapterService

    /// External SDR (IF tap or direct RF) feeding the waterfall; driven by
    /// the focused slot's CAT state in `pollAllSessions`.
    private(set) var iqPanadapter: IQPanadapterService
    /// Icom scope producer (IC-9700 LAN, IC-705/7610 WiFi) that drives
    /// `waterfallStore` from `27 00` waveform frames.
    private(set) var icomWaterfall: IcomWaterfallData

    /// Session that has scope waveform output enabled, plus the frames that
    /// restore the scope state read on connect. See `RadioManager+Transport`.
    var icomScopeSession: (id: UUID, restorePayloads: [[UInt8]], restoreFrames: [Data])?

    /// Satellite mode (`16 5A`) as found when the satellite CAT controller
    /// armed IC-9700 duplex, keyed by session, so disarm / disconnect can
    /// put it back. See `RadioManager+Duplex`.
    var satelliteModeRestore: [UUID: Bool] = [:]

    /// Debug: reference to active SCU-LAN10 transport for stats polling
    var activeSCULAN10: SCULAN10Transport?

    /// Plays SCU-LAN10 RX audio through the local default output device while
    /// a Yaesu network adapter is connected.
    let sculan10AudioPlayer = SCULAN10AudioPlayer()

    /// Fan-out for the active radio's RX audio: local Mac player + Remote
    /// LAN publisher both subscribe via `RadioManager+Audio`.
    let radioAudioBroadcaster = RadioAudioBroadcaster()
    var sculan10AudioListenerID: UUID?

    var lastDebugStats: SCULAN10DebugStats = .empty

    /// Slot whose RX audio is routed to the Mac speaker. Defaults to `.a`
    /// so single-radio installs see no change. Multi-radio installs can
    /// flip via the status bar audio pill or `setAudioRoutedSlot(_:)`.
    var audioRoutedSlot: RadioSlot = .a

    /// Connection log for UI display during SCU-LAN10 connect
    var connectionLog: [String] = []

    /// Slot the next `connect(profile:)` or `connect(profile:port:)` call
    /// should bind to. Set by the caller (UI / autoConnect) before invoking
    /// connect; cleared on read. Nil means "first available slot".
    var pendingConnectSlot: RadioSlot?

    /// Latest SCU-LAN10 channel counters for the radio pane debug view.
    /// Returns `nil` when no SCU-LAN10 is connected so the view can hide
    /// the section instead of rendering stale numbers.
    var sculan10DebugStats: SCULAN10DebugStats? {
        activeSCULAN10 == nil ? nil : lastDebugStats
    }

    /// Current radio state for the active radio
    var activeState: RadioSession.RadioState? {
        get async {
            guard let id = activeRadioId, let session = sessions[id] else {
                return nil
            }
            return await session.state
        }
    }

    /// Device fingerprint of the last connected radio in slot A. Read-only
    /// shim retained for legacy callers; new code should use
    /// `lastFingerprint(for:)` from `RadioManager+Persistence`.
    var lastDeviceFingerprint: String? {
        lastFingerprint(for: .a)
    }

    func appendConnectionLog(_ msg: String) {
        let ts = DateFormatter.localizedString(
            from: Date(), dateStyle: .none, timeStyle: .medium
        )
        connectionLog.append("\(ts) \(msg)")
    }

    /// Connect using a discovered port; saves fingerprint + profile for auto-reconnect.
    /// `slot` (default nil = first available) lets the caller pin the new
    /// session to a specific slot.
    func connect(
        profile: RadioProfile,
        port: SerialPortMonitor.SerialPortInfo,
        slot: RadioSlot? = nil
    ) async throws -> UUID {
        if let slot, slots[slot] != nil {
            throw RadioConnectError.slotOccupied(slot)
        }
        if let existing = slotForPortPath(port.path) {
            throw RadioConnectError.duplicatePort(path: port.path, slot: existing)
        }
        let targetSlot = slot ?? nextAvailableSlot() ?? .a
        setLastFingerprint(port.deviceFingerprint, for: targetSlot)
        saveProfile(profile, for: port.deviceFingerprint)
        pendingConnectSlot = targetSlot
        return try await connect(profile: profile)
    }

    /// Auto-connect to the last-used USB radio when the device + saved profile are present.
    /// Calls the multi-slot variant under the hood.
    func autoConnect(ports: [SerialPortMonitor.SerialPortInfo]) async {
        await autoConnectAllSlots(ports: ports)
    }

    /// Connect to a radio with the given profile
    func connect(profile: RadioProfile) async throws -> UUID {
        if profile.protocolType == .cwBridge {
            return try await startBridgeConnection(profile: profile)
        }

        let (transport, handler) = try createTransportAndHandler(for: profile)

        let frameType: FrameAssembler.FrameType =
            if handler is CIVProtocolHandler {
                .civ
            } else if handler is FlexProtocolHandler {
                .smartsdr
            } else {
                .kenwood
            }
        let session = RadioSession(
            transport: transport,
            protocolHandler: handler,
            frameType: frameType
        )

        // Flex radios use push-based status via subscriptions — no polling needed
        if handler is FlexProtocolHandler {
            await session.setSkipPolling(true)
        }

        let id = UUID()
        sessions[id] = session

        await installScopeSpanHook(on: session, sessionId: id)

        do {
            try await session.start()
            radioManagerLogger.info("Session started, radio connected")
            try await registerFlexSubscriptions(handler: handler, session: session)
        } catch {
            // Don't leave a dead session behind. IcomWiFiSection retries a
            // failed connect, and the leftover session from the failed attempt
            // was stopped again by disconnectAll() ("disconnect: begin" twice).
            sessions.removeValue(forKey: id)
            await session.stop()
            throw error
        }
        await enableIcomScopeIfNeeded(profile: profile, session: session, sessionId: id)

        // Query scope span once after connecting (SS05 = main band span, Yaesu
        // only). Never send the ASCII command into a CI-V stream.
        if !(handler is FlexProtocolHandler),
           !(handler is CIVProtocolHandler),
           let spanCmd = "SS05;".data(using: .ascii)
        {
            try? await session.sendRaw(spanCmd)
        }

        updateConnectionState(id: id, profile: profile)

        // Start state polling
        Task { [weak self] in
            guard let self else {
                return
            }
            await pollActiveState()
        }

        return id
    }

    /// Connect to a discovered FlexRadio
    func connectFlex(radio: DiscoveredFlexRadio, model: RadioModel) async throws -> UUID {
        let profile = RadioProfile.fromFlex(
            model: model,
            host: radio.ipAddress,
            port: radio.port,
            radioName: radio.displayName
        )
        return try await connect(profile: profile)
    }

    /// Connect to a FlexRadio by manual IP address
    func connectFlexManual(host: String, port: UInt16 = 4_992, model: RadioModel) async throws -> UUID {
        let profile = RadioProfile.fromFlex(
            model: model,
            host: host,
            port: port
        )
        return try await connect(profile: profile)
    }

    /// Connect to an Icom radio via WiFi (RS-BA1 protocol)
    func connectIcomWiFi(
        host: String,
        username: String,
        password: String,
        model: RadioModel
    ) async throws -> UUID {
        let profile = RadioProfile.fromIcomWiFi(
            model: model,
            host: host,
            username: username,
            password: password
        )
        return try await connect(profile: profile)
    }

    /// Connect to an SCU-LAN10
    func connectSCULAN10(
        host: String,
        port: UInt16 = 50_000,
        username: String,
        password: String,
        model: RadioModel
    ) async throws -> UUID {
        let profile = RadioProfile.fromSCULAN10(
            model: model,
            host: host,
            port: port,
            username: username,
            password: password
        )
        return try await connect(profile: profile)
    }

    func disconnect(id: UUID) async {
        // Remove before awaiting the teardown so a re-entrant call (double
        // click while the transport is closing) finds nothing to stop.
        guard let session = sessions.removeValue(forKey: id) else {
            return
        }
        await disableIcomScopeIfNeeded(session: session, sessionId: id)
        if let slot = slotForSession(id), let address = slotStates[slot]?.profile.civAddress {
            await restoreSatelliteModeIfNeeded(session: session, sessionId: id, address: address)
        }
        await session.stop()
        unregisterSlot(sessionId: id)

        if activeRadioId == id {
            activeRadioId = slots[focusedSlot] ?? sessions.keys.first
        }

        isConnected = !sessions.isEmpty
        if !isConnected {
            connectedPortPath = nil
            connectedRadioName = nil
            sculan10Waterfall.stopConsuming()
            icomWaterfall.stopConsuming()
            detachLocalAudioPlayer()
            radioAudioBroadcaster.stopConsuming()
            flexPanadapter.stop()
        }
        commandLog.append(direction: .status, text: "Disconnected")
    }

    func disconnectAll() async {
        // Take the sessions out first so a second disconnectAll() that runs
        // during the awaits below (e.g. a double click) finds nothing to stop.
        let stopping = sessions
        sessions.removeAll()
        for (id, session) in stopping {
            await disableIcomScopeIfNeeded(session: session, sessionId: id)
            if let slot = slotForSession(id), let address = slotStates[slot]?.profile.civAddress {
                await restoreSatelliteModeIfNeeded(session: session, sessionId: id, address: address)
            }
            await session.stop()
        }
        unregisterAllSlots()
        activeRadioId = nil
        isConnected = false
        connectedPortPath = nil
        connectedRadioName = nil
        sculan10Waterfall.stopConsuming()
        icomWaterfall.stopConsuming()
        detachLocalAudioPlayer()
        radioAudioBroadcaster.stopConsuming()
        flexPanadapter.stop()
        commandLog.append(direction: .status, text: "Disconnected all radios")
    }
}

// MARK: - RadioManager+Private

extension RadioManager {
    func sculan10Stats(_ tr: SCULAN10Transport) async -> SCULAN10DebugStats {
        await SCULAN10DebugStats(
            controlReceived: tr.ctrlChanReceived,
            catReceived: tr.catChanReceived,
            scopeReceived: tr.scopeChanReceived,
            audioReceived: tr.audioChanReceived,
            catSent: tr.catChanSent,
            catSendErrors: Int(tr.catSendErr)
        )
    }

    private func createTransportAndHandler(
        for profile: RadioProfile
    ) throws -> (any RadioTransport, any RadioProtocolHandler) {
        if profile.protocolType == .scuLan10 {
            return try createSCULAN10Transport(for: profile)
        }

        if profile.protocolType == .icomWiFi {
            return try createIcomWiFiTransport(for: profile)
        }

        if profile.protocolType == .flex {
            return try createFlexTransport(for: profile)
        }

        let proto = profile.protocolType.rawValue
        radioManagerLogger.info(
            "Connecting: \(profile.name) via \(profile.serialPortPath) (\(proto), \(profile.baudRate) baud)"
        )
        let transport = SerialRadioTransport(
            profile: profile,
            logCallback: commandLog.makeCallback()
        )
        let handler: any RadioProtocolHandler = switch profile.protocolType {
        case .civ:
            CIVProtocolHandler(civAddress: profile.civAddress ?? 0x94)
        case .kenwood:
            KenwoodProtocolHandler()
        case .elecraft:
            ElecraftProtocolHandler()
        case .yaesu:
            YaesuProtocolHandler()
        case .flex:
            FlexProtocolHandler()
        case .scuLan10:
            YaesuProtocolHandler()
        case .icomWiFi:
            CIVProtocolHandler(civAddress: profile.civAddress ?? 0xA4)
        case .cwBridge:
            fatalError("CW Bridge uses BLE transport, not serial — use startBridgeConnection()")
        }
        return (transport, handler)
    }

    private func registerFlexSubscriptions(
        handler: any RadioProtocolHandler,
        session: RadioSession
    ) async throws {
        guard let flexHandler = handler as? FlexProtocolHandler else {
            return
        }
        let setupCmd = flexHandler.encodeClientSetupForSweep()
        try await session.sendRaw(setupCmd)
        for subCmd in flexHandler.encodeSubscriptions() {
            try await session.sendRaw(subCmd)
        }
        // Once the standard subscriptions are in flight, request the
        // panadapter stream. The service has already bound a UDP port; we
        // send `client udpport` and `display pan create` over the same TCP
        // session and start matching VITA-49 stream IDs to the assigned
        // handle as response lines come back.
        await flexPanadapter.attach(session: session, handler: flexHandler)
        radioManagerLogger.info("Flex subscriptions registered")
    }

    private func updateConnectionState(id: UUID, profile: RadioProfile) {
        if activeRadioId == nil {
            activeRadioId = id
        }

        isConnected = true
        let portPath = profile.isNetworkRadio
            ? profile.networkHost ?? ""
            : profile.serialPortPath
        connectedPortPath = portPath
        connectedRadioName = profile.name
        // Bind this session to the next free slot. Bridge sessions register
        // their own slot in `connectBridge(...)` because the slot needs to
        // exist before the BLE handshake task starts mutating its bridge
        // state.
        if slotForSession(id) == nil {
            _ = registerSlotState(sessionId: id, profile: profile, portPath: portPath)
        }
        let connectTarget = profile.isNetworkRadio
            ? "\(profile.networkHost ?? ""):\(profile.networkPort)"
            : profile.serialPortPath
        commandLog.append(
            direction: .status,
            text: "Connected to \(profile.name) on \(connectTarget)"
        )
    }

    func pollActiveState() async {
        await pollAllSessions()
    }
}
