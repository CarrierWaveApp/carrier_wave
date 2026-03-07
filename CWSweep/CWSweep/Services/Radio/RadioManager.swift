import Foundation
import os

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioManager")

// MARK: - RadioManager

/// Manages radio connections and publishes state to the UI.
/// Supports multiple simultaneous radio connections (SO2R ready).
@MainActor
@Observable
final class RadioManager {
    // MARK: Internal

    private(set) var sessions: [UUID: RadioSession] = [:]
    private(set) var activeRadioId: UUID?

    /// Currently active frequency in MHz
    var frequency: Double = 0

    /// Currently active mode
    var mode: String = ""

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
    private(set) var connectedPortPath: String?

    /// Name of the currently connected radio (nil when disconnected)
    private(set) var connectedRadioName: String?

    /// In-app command log for radio TX/RX visibility
    let commandLog = RadioCommandLog()

    /// Current radio state for the active radio
    var activeState: RadioSession.RadioState? {
        get async {
            guard let id = activeRadioId, let session = sessions[id] else {
                return nil
            }
            return await session.state
        }
    }

    /// Device fingerprint of the last connected radio (for auto-reconnect).
    private(set) var lastDeviceFingerprint: String? {
        get { UserDefaults.standard.string(forKey: "radio.lastDeviceFingerprint") }
        set { UserDefaults.standard.set(newValue, forKey: "radio.lastDeviceFingerprint") }
    }

    /// Connect to a radio using a discovered port (saves fingerprint for auto-reconnect).
    func connect(profile: RadioProfile, port: SerialPortMonitor.SerialPortInfo) async throws -> UUID {
        lastDeviceFingerprint = port.deviceFingerprint
        return try await connect(profile: profile)
    }

    /// Auto-connect to the last-used radio if the device is present.
    func autoConnect(ports: [SerialPortMonitor.SerialPortInfo], defaultRadioModel: String, defaultBaudRate: Int) async {
        guard !isConnected,
              UserDefaults.standard.bool(forKey: "autoConnect"),
              let fingerprint = lastDeviceFingerprint,
              let match = ports.first(where: { $0.deviceFingerprint == fingerprint })
        else {
            return
        }

        let model = RadioModel.knownModels.first { $0.id == defaultRadioModel } ?? RadioModel.knownModels[0]
        var profile = RadioProfile.from(model: model, portPath: match.path)
        profile.baudRate = defaultBaudRate
        logger.info("Auto-connecting radio to \(match.path) (fingerprint match)")
        do {
            _ = try await connect(profile: profile, port: match)
        } catch {
            logger.error("Auto-connect failed: \(error)")
        }
    }

    /// Connect to a radio with the given profile
    func connect(profile: RadioProfile) async throws -> UUID {
        let proto = profile.protocolType.rawValue
        logger.info(
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
        case .yaesu,
             .flex:
            KenwoodProtocolHandler() // Placeholder
        }

        let session = RadioSession(transport: transport, protocolHandler: handler)
        let id = UUID()
        sessions[id] = session

        try await session.start()
        logger.info("Session started, radio connected")

        if activeRadioId == nil {
            activeRadioId = id
        }

        isConnected = true
        connectedPortPath = profile.serialPortPath
        connectedRadioName = profile.name
        commandLog.append(direction: .status, text: "Connected to \(profile.name) on \(profile.serialPortPath)")

        // Start state polling
        Task { [weak self] in
            guard let self else {
                return
            }
            await pollActiveState()
        }

        return id
    }

    func disconnect(id: UUID) async {
        guard let session = sessions[id] else {
            return
        }
        await session.stop()
        sessions.removeValue(forKey: id)

        if activeRadioId == id {
            activeRadioId = sessions.keys.first
        }

        isConnected = !sessions.isEmpty
        if !isConnected {
            connectedPortPath = nil
            connectedRadioName = nil
        }
        commandLog.append(direction: .status, text: "Disconnected")
    }

    func disconnectAll() async {
        for (id, session) in sessions {
            await session.stop()
            sessions.removeValue(forKey: id)
        }
        activeRadioId = nil
        isConnected = false
        connectedPortPath = nil
        connectedRadioName = nil
        commandLog.append(direction: .status, text: "Disconnected all radios")
    }

    func tuneToFrequency(_ freqMHz: Double) async throws {
        guard let id = activeRadioId, let session = sessions[id] else {
            return
        }
        try await session.tuneToFrequency(freqMHz)
    }

    func setMode(_ mode: String) async throws {
        guard let id = activeRadioId, let session = sessions[id] else {
            return
        }
        try await session.setMode(mode)
    }

    func setPTT(_ on: Bool) async throws {
        guard let id = activeRadioId, let session = sessions[id] else {
            return
        }
        try await session.setPTT(on)
    }

    func setXIT(_ on: Bool) async throws {
        guard let id = activeRadioId, let session = sessions[id] else {
            return
        }
        try await session.setXIT(on)
    }

    func setXITOffset(_ hz: Int) async throws {
        guard let id = activeRadioId, let session = sessions[id] else {
            return
        }
        try await session.setXITOffset(hz)
    }

    func clearRITXIT() async throws {
        guard let id = activeRadioId, let session = sessions[id] else {
            return
        }
        try await session.clearRITXIT()
    }

    // MARK: Private

    private func pollActiveState() async {
        while !Task.isCancelled {
            if let id = activeRadioId, let session = sessions[id] {
                let state = await session.state
                frequency = state.frequency
                mode = state.mode
                xitEnabled = state.xitEnabled
                ritEnabled = state.ritEnabled
                ritXitOffset = state.ritXitOffset
                isTransmitting = state.isTransmitting
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
