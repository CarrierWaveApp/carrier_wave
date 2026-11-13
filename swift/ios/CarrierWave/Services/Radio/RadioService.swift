import CarrierWaveData
import Foundation

// MARK: - RadioLogEntry

/// A single entry in the radio data log for debugging CI-V traffic and auth.
struct RadioLogEntry: Identifiable {
    enum Direction {
        case sent
        case received
        case info
        case error
    }

    let id = UUID()
    let timestamp = Date()
    let direction: Direction
    let message: String
    let hexData: String?
}

// MARK: - RadioService

/// Transport-agnostic radio service supporting BLE and WiFi connections.
/// Replaces BLERadioService with a unified interface for all radio transports.
@MainActor
@Observable
final class RadioService {
    // MARK: Lifecycle

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.transportType),
           let type = TransportType(rawValue: raw)
        {
            transportType = type
        }
    }

    // MARK: Internal

    /// Transport type for radio connection
    enum TransportType: String, CaseIterable {
        case ble
        case wifi
        case flex
        case scuLan10

        // MARK: Internal

        var displayName: String {
            switch self {
            case .ble: "BLE"
            case .wifi: "WiFi"
            case .flex: "Flex"
            case .scuLan10: "SCU-LAN10"
            }
        }
    }

    // MARK: Internal (accessed by RadioService+Connection extension)

    // `Keys` (UserDefaults/Keychain key namespace) lives in RadioService+Keys.swift

    /// Shared singleton instance
    static let shared = RadioService()

    /// Current connection status
    var connectionStatus: BLERadioTransport.ConnectionState = .disconnected

    /// Current radio frequency in MHz (nil if unknown)
    var radioFrequencyMHz: Double?

    /// Current radio mode string (nil if unknown)
    var radioMode: String?

    /// Discovered BLE devices during scanning
    var discoveredDevices: [BLERadioTransport.DiscoveredDevice] = []

    /// Whether currently scanning
    var isScanning = false

    /// Callback when radio frequency changes (set by session manager)
    var onRadioFrequencyChanged: ((Double) -> Void)?

    /// Callback when radio mode changes (set by session manager)
    var onRadioModeChanged: ((String) -> Void)?

    /// Running data log for CI-V traffic and auth events.
    var dataLog: [RadioLogEntry] = []

    /// Radios discovered via SmartLink
    var smartLinkRadios: [SmartLinkRadio] = []

    /// Whether SmartLink is currently connecting/discovering
    var isSmartLinkConnecting = false

    let smartLinkAuth = SmartLinkAuth()
    let smartLinkClient = SmartLinkClient()
    var smartLinkTask: Task<Void, Never>?

    var bleTransport = BLERadioTransport()
    var bridgeProtocol: BridgeProtocol?
    var session: RadioSession?

    // MARK: - Bridge Status (CWBP)

    /// Firmware version of the connected CW Bridge (nil if legacy or disconnected).
    var bridgeFirmwareVersion: String?

    /// Whether the bridge's USB port has a device connected.
    var bridgeUSBConnected: Bool = false

    /// Detected radio name from the bridge (e.g. "Elecraft KX2").
    var bridgeDetectedRadio: String?

    /// Whether the bridge is currently probing for a radio.
    var bridgeDetecting: Bool = false

    /// Whether the bridge uses CWBP (true) or legacy passthrough (false).
    var bridgeIsFramed: Bool = false

    // MARK: - Satellite Doppler State (CW Sat Bridge)

    /// Whether the connected bridge runs the satellite doppler executor.
    var bridgeHasSatDoppler: Bool = false

    /// Latest executor status pushed by the sat bridge (nil until one arrives).
    var satBridgeStatus: SatBridgeStatus?

    // MARK: - CW Keyer State (CWBP)

    /// Whether the bridge supports CW keyer commands.
    var bridgeHasCWKeyer: Bool = false

    /// Slot currently transmitting (nil if idle).
    var cwSendingSlot: Int?

    /// CW keyer service instance.
    let cwKeyer = CWKeyerService()

    /// Session QSO count for CW serial number. Set by LoggerView.
    var cwSerialNumber: Int = 1

    var scanTask: Task<Void, Never>?
    var stateTask: Task<Void, Never>?
    var sessionTask: Task<Void, Never>?
    var pollTask: Task<Void, Never>?
    var bridgeEventTask: Task<Void, Never>?
    var bridgeStatusPollTask: Task<Void, Never>?

    // Feedback loop prevention
    var lastAppSetFrequency: Double?
    var lastAppSetMode: String?
    var lastAppSetTime: Date?
    let feedbackSuppressionWindow: TimeInterval = 0.5

    /// `true` when the bridge-detected radio is a Yaesu (4-digit ID). Yaesu
    /// speaks Kenwood-compatible CAT but answers `MD` with a different format
    /// (`MD0<char>;`), so the Kenwood handler is built with this flag set.
    var radioIsYaesu = false

    // MARK: - SmartLink State

    /// Whether SmartLink mode is enabled for Flex connections (stored for @Observable tracking)
    var useSmartLink: Bool = UserDefaults.standard.bool(forKey: Keys.flexUseSmartLink) {
        didSet { UserDefaults.standard.set(useSmartLink, forKey: Keys.flexUseSmartLink) }
    }

    /// SmartLink login email (persisted)
    var smartLinkEmail: String? {
        get { UserDefaults.standard.string(forKey: Keys.smartLinkEmail) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.smartLinkEmail) }
    }

    /// Whether we have a stored SmartLink refresh token
    var isSmartLinkLoggedIn: Bool {
        (try? KeychainHelper.shared.readString(
            for: Keys.smartLinkKeychainRefreshToken
        )) != nil
    }

    /// Active transport type (persisted, stored for @Observable tracking)
    var transportType: TransportType = .ble {
        didSet {
            UserDefaults.standard.set(transportType.rawValue, forKey: Keys.transportType)
            if oldValue != transportType {
                // WiFi always uses CI-V (RS-BA1 protocol)
                if transportType == .wifi {
                    rigProtocol = .civ
                }
                disconnectAndRecreate()
            }
        }
    }

    /// Saved BLE device name (persisted)
    var savedDeviceName: String? {
        UserDefaults.standard.string(forKey: Keys.savedDeviceName)
    }

    /// Saved BLE device UUID (persisted)
    var savedDeviceUUID: UUID? {
        guard let str = UserDefaults.standard.string(forKey: Keys.savedDeviceUUID) else {
            return nil
        }
        return UUID(uuidString: str)
    }

    /// Whether a device/connection is configured
    var isConfigured: Bool {
        switch transportType {
        case .ble:
            savedDeviceUUID != nil
        case .wifi:
            wifiIPAddress != nil && !wifiIPAddress!.isEmpty
        case .flex:
            flexIPAddress != nil && !flexIPAddress!.isEmpty
        case .scuLan10:
            sculan10IPAddress != nil && !sculan10IPAddress!.isEmpty
        }
    }

    /// Whether currently connected
    var isConnected: Bool {
        connectionStatus == .connected
    }

    /// Current protocol (persisted, stored for @Observable tracking)
    var rigProtocol: RigProtocol = {
        guard let raw = UserDefaults.standard.string(forKey: Keys.rigProtocol),
              let proto = RigProtocol(rawValue: raw)
        else {
            return .civ
        }
        return proto
    }() {
        didSet {
            UserDefaults.standard.set(rigProtocol.rawValue, forKey: Keys.rigProtocol)
        }
    }

    // MARK: - WiFi Configuration

    /// WiFi IP address (persisted)
    var wifiIPAddress: String? {
        get { UserDefaults.standard.string(forKey: Keys.wifiIPAddress) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.wifiIPAddress) }
    }

    /// Configured CI-V rig address
    var configuredRigAddress: UInt8 {
        let stored = UserDefaults.standard.integer(forKey: Keys.rigAddress)
        return stored > 0 ? UInt8(stored) : 0xA4
    }

    // MARK: - Flex Configuration

    /// Flex radio IP address (persisted)
    var flexIPAddress: String? {
        get { UserDefaults.standard.string(forKey: Keys.flexIPAddress) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.flexIPAddress) }
    }

    /// Flex radio TCP port (persisted, default 4992)
    var flexPort: UInt16 {
        get {
            let stored = UserDefaults.standard.integer(forKey: Keys.flexPort)
            return stored > 0 ? UInt16(stored) : 4_992
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: Keys.flexPort)
        }
    }

    /// Flex slice index to control (persisted, default 0)
    var flexSliceIndex: Int {
        get { UserDefaults.standard.integer(forKey: Keys.flexSliceIndex) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.flexSliceIndex) }
    }

    // SCU-LAN10 configuration + connection live in RadioService+SCULAN10.swift

    /// Persist a new BLE device UUID. Called by `BLERadioTransport` when a
    /// name-based rescan finds the bridge at a new address (e.g. after the
    /// firmware's BD_ADDR changed) so future connects skip the rescan.
    func updateSavedDeviceUUID(_ uuid: UUID) {
        UserDefaults.standard.set(uuid.uuidString, forKey: Keys.savedDeviceUUID)
    }

    // MARK: - BLE Scanning

    func startScan() {
        guard !isScanning else {
            return
        }
        isScanning = true
        discoveredDevices = []
        scanTask = Task {
            let stream = await bleTransport.startScanning()
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
        Task { await bleTransport.stopScanning() }
        isScanning = false
    }

    /// Select and save a BLE device, then connect
    func selectDevice(_ device: BLERadioTransport.DiscoveredDevice) {
        UserDefaults.standard.set(device.name, forKey: Keys.savedDeviceName)
        UserDefaults.standard.set(device.id.uuidString, forKey: Keys.savedDeviceUUID)
        stopScan()
        connectToSavedDevice()
    }

    /// Forget the saved BLE device and disconnect
    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: Keys.savedDeviceName)
        UserDefaults.standard.removeObject(forKey: Keys.savedDeviceUUID)
        radioFrequencyMHz = nil
        radioMode = nil
    }

    // MARK: - Connection

    /// Connect to the saved device (BLE), configured WiFi, or Flex radio
    func connectToSavedDevice() {
        switch transportType {
        case .ble:
            connectBLE()
        case .wifi:
            connectWiFi()
        case .flex:
            connectFlex()
        case .scuLan10:
            connectSCULAN10()
        }
    }

    /// Disconnect from the radio
    func disconnect() {
        stopStatePolling()
        stateTask?.cancel()
        stateTask = nil
        sessionTask?.cancel()
        sessionTask = nil
        bridgeEventTask?.cancel()
        bridgeEventTask = nil
        bridgeStatusPollTask?.cancel()
        bridgeStatusPollTask = nil

        if let session {
            Task { await session.stop() }
        }
        session = nil

        // For BLE, also disconnect transport-level
        if transportType == .ble {
            if let bridge = bridgeProtocol {
                Task { await bridge.stop() }
            }
            bridgeProtocol = nil
            Task { await bleTransport.disconnect() }
        }

        bridgeFirmwareVersion = nil
        bridgeUSBConnected = false
        bridgeDetectedRadio = nil
        bridgeDetecting = false
        bridgeIsFramed = false
        connectionStatus = .disconnected
    }

    // MARK: - Radio Control

    /// Set frequency on the radio (called from app -> radio)
    func setFrequency(_ mhz: Double) {
        addLog(.sent, "Set freq \(String(format: "%.6f", mhz)) MHz")
        lastAppSetFrequency = mhz
        lastAppSetTime = Date()
        guard let session else {
            return
        }
        Task {
            let verified = await session.tuneToFrequency(mhz)
            if !verified {
                self.addLog(.error, "Set freq verify failed")
            }
        }
    }

    /// Set mode on the radio (called from app -> radio)
    func setMode(_ mode: String) {
        addLog(.sent, "Set mode \(mode)")
        lastAppSetMode = mode
        lastAppSetTime = Date()
        guard let session else {
            return
        }
        Task {
            let modeValue = BridgeFrame.UniversalMode.from(carrierWaveMode: mode)?.rawValue
            let verified = await session.setMode(mode, universalModeRawValue: modeValue)
            if !verified {
                self.addLog(.error, "Set mode verify failed")
            }
        }
    }

    /// Manually refresh radio state
    func refreshRadioState() {
        // State is continuously updated via polling in RadioSession
        // This is a no-op since RadioSession already polls at 200ms
    }

    /// Update the rig address (from settings)
    func updateRigAddress(_ address: UInt8) {
        UserDefaults.standard.set(Int(address), forKey: Keys.rigAddress)
        reconnectWithNewSession()
    }

    /// Update the protocol and reconnect if needed.
    func updateProtocol(_ newProtocol: RigProtocol) {
        guard newProtocol != rigProtocol else {
            return
        }
        rigProtocol = newProtocol
        reconnectWithNewSession()
    }

    // MARK: - Data Log

    func addLog(
        _ direction: RadioLogEntry.Direction,
        _ message: String,
        data: Data? = nil
    ) {
        let hex = data.map {
            $0.prefix(200).map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        dataLog.append(RadioLogEntry(
            direction: direction,
            message: message,
            hexData: hex
        ))
        if dataLog.count > 200 {
            dataLog.removeFirst(dataLog.count - 200)
        }
    }

    func clearLog() {
        dataLog.removeAll()
    }

    /// Detect protocol from a rig name and update if different.
    func setProtocolFromRig(_ rigName: String?) {
        guard let detected = RigProtocolDetector.detect(rigName: rigName) else {
            return
        }
        updateProtocol(detected)
    }
}
