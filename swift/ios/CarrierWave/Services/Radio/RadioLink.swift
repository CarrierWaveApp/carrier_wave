import CarrierWaveData
import UIKit

// MARK: - RadioLink

/// One independent CW Bridge over BLE: its own CoreBluetooth central,
/// CWBP bridge protocol, and radio session. `RadioService` remains the
/// primary (logger/keyer) rig; links are for secondary radios such as the
/// satellite duplex pair, where each bridge drives one handheld.
///
/// Each link persists its own bridge UUID/name under `keyPrefix`, so it
/// never touches the primary radio's saved device.
@MainActor
@Observable
final class RadioLink {
    // MARK: Lifecycle

    init(keyPrefix: String, label: String) {
        self.keyPrefix = keyPrefix
        self.label = label
    }

    // MARK: Internal

    /// Human label for logs and UI ("Uplink", "Downlink").
    let label: String

    var connectionStatus: BLERadioTransport.ConnectionState = .disconnected
    var discoveredDevices: [BLERadioTransport.DiscoveredDevice] = []
    var isScanning = false

    /// Radio name reported by the bridge after detection (nil until then).
    var detectedRadio: String?
    var bridgeUSBConnected = false
    var bridgeFirmwareVersion: String?

    /// Frequency/mode as read back from the radio by the session poll loop.
    var frequencyMHz: Double?
    var mode: String?

    var bridge: BridgeProtocol?
    var session: RadioSession?
    var rigProtocol: RigProtocol = .kenwood
    var radioIsYaesu = false
    var sessionTask: Task<Void, Never>?
    var pollTask: Task<Void, Never>?
    var bridgeEventTask: Task<Void, Never>?
    var statusPollTask: Task<Void, Never>?

    /// Most recent error message (set-verify failures, transport errors).
    var lastError: String? {
        didSet {
            if let lastError {
                RadioService.shared.addLog(.error, lastError)
            }
        }
    }

    var savedDeviceName: String? {
        UserDefaults.standard.string(forKey: keyPrefix + ".deviceName")
    }

    var savedDeviceUUID: UUID? {
        UserDefaults.standard.string(forKey: keyPrefix + ".deviceUUID").flatMap(UUID.init(uuidString:))
    }

    var isConfigured: Bool {
        savedDeviceUUID != nil
    }

    var isConnected: Bool {
        connectionStatus == .connected
    }

    /// Whether the bridge has a detected radio ready to take commands.
    var isRadioReady: Bool {
        isConnected && session != nil && bridgeUSBConnected
    }

    // MARK: - Scanning

    func startScan() {
        guard !isScanning else {
            return
        }
        isScanning = true
        discoveredDevices = []
        scanTask = Task {
            let stream = await transport.startScanning()
            for await devices in stream {
                self.discoveredDevices = devices.sorted {
                    $0.name.localizedCompare($1.name) == .orderedAscending
                }
            }
            self.isScanning = false
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        Task { await transport.stopScanning() }
    }

    func selectDevice(_ device: BLERadioTransport.DiscoveredDevice) {
        UserDefaults.standard.set(device.name, forKey: keyPrefix + ".deviceName")
        UserDefaults.standard.set(device.id.uuidString, forKey: keyPrefix + ".deviceUUID")
        stopScan()
        connect()
    }

    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: keyPrefix + ".deviceName")
        UserDefaults.standard.removeObject(forKey: keyPrefix + ".deviceUUID")
    }

    /// Adopt another link's saved bridge (used by the uplink/downlink swap).
    func adopt(deviceUUID: UUID?, deviceName: String?) {
        disconnect()
        if let deviceUUID {
            UserDefaults.standard.set(deviceUUID.uuidString, forKey: keyPrefix + ".deviceUUID")
        } else {
            UserDefaults.standard.removeObject(forKey: keyPrefix + ".deviceUUID")
        }
        if let deviceName {
            UserDefaults.standard.set(deviceName, forKey: keyPrefix + ".deviceName")
        } else {
            UserDefaults.standard.removeObject(forKey: keyPrefix + ".deviceName")
        }
    }

    // MARK: - Connection

    /// Connect to the saved bridge. Idempotent while a connection is live.
    func connect() {
        guard let uuid = savedDeviceUUID else {
            return
        }
        if stateTask != nil, connectionStatus == .connected || bridge != nil {
            return
        }
        connectionStatus = .connecting("Starting")
        resetBridgeState()

        let fallbackName = savedDeviceName
        let prefix = keyPrefix
        stateTask?.cancel()
        stateTask = Task {
            await transport.setRebindHandler { newUUID in
                UserDefaults.standard.set(newUUID.uuidString, forKey: prefix + ".deviceUUID")
            }
            await transport.setTarget(deviceUUID: uuid, fallbackName: fallbackName)
            let stream = await transport.stateStream()
            try? await transport.connect()

            for await state in stream {
                self.connectionStatus = state
                if state == .connected {
                    await self.tearDownBridge()
                    let bridge = BridgeProtocol(transport: self.transport)
                    self.bridge = bridge
                    await bridge.start()
                    self.startBridgeEventMonitoring(bridge: bridge)
                    self.startSession(bridge: bridge, frameType: .kenwood)
                } else if case .disconnected = state {
                    await self.tearDownBridge()
                }
            }
        }
    }

    func disconnect() {
        stateTask?.cancel()
        stateTask = nil
        stopPolling()
        sessionTask?.cancel()
        sessionTask = nil
        bridgeEventTask?.cancel()
        bridgeEventTask = nil
        statusPollTask?.cancel()
        statusPollTask = nil
        if let bridge {
            Task { await bridge.stop() }
        }
        bridge = nil
        session = nil
        resetBridgeState()
        frequencyMHz = nil
        mode = nil
        Task { await transport.disconnect() }
        connectionStatus = .disconnected
    }

    // MARK: - Radio control

    /// Tune the radio. `hz` is rounded to 10 Hz first — the Quansheng CAT
    /// build stores frequency in 10 Hz units and the bridge's set-verify
    /// compares the readback exactly.
    @discardableResult
    func setFrequency(hz: UInt64) async -> Bool {
        guard let session else {
            return false
        }
        let rounded = (hz / 10) * 10
        let verified = await session.tuneToFrequency(Double(rounded) / 1_000_000)
        if !verified {
            lastError = "\(label): set frequency failed"
        }
        return verified
    }

    @discardableResult
    func setMode(_ mode: String) async -> Bool {
        guard let session else {
            return false
        }
        let value = BridgeFrame.UniversalMode.from(carrierWaveMode: mode)?.rawValue
        let verified = await session.setMode(mode, universalModeRawValue: value)
        if !verified {
            lastError = "\(label): set mode failed"
        }
        return verified
    }

    /// Send a raw CAT command through the bridge (e.g. `CT0670;`).
    func sendRawCAT(_ command: String) async {
        guard let session, let data = command.data(using: .ascii) else {
            return
        }
        do {
            try await session.sendRaw(data)
        } catch {
            lastError = "\(label): \(error.localizedDescription)"
        }
    }

    // MARK: Private

    // MARK: Internal (shared with RadioLink+Bridge)

    private let keyPrefix: String
    private let transport = BLERadioTransport()

    private var scanTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    private func tearDownBridge() async {
        stopPolling()
        sessionTask?.cancel()
        sessionTask = nil
        bridgeEventTask?.cancel()
        bridgeEventTask = nil
        statusPollTask?.cancel()
        statusPollTask = nil
        if let old = bridge {
            await old.stop()
        }
        bridge = nil
        session = nil
        resetBridgeState()
    }

    private func resetBridgeState() {
        detectedRadio = nil
        bridgeUSBConnected = false
        bridgeFirmwareVersion = nil
    }
}
