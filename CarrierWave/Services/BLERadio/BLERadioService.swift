import CarrierWaveData
import Foundation

// MARK: - BLERadioService

/// UI-ready wrapper around BLERadioClient.
/// Provides @Observable state for SwiftUI and handles polling/feedback loops.
@MainActor
@Observable
final class BLERadioService {
    // MARK: Internal

    /// Shared instance (CoreBluetooth should be singleton)
    static let shared = BLERadioService()

    /// Current connection status (mirrors client state for UI)
    var connectionStatus: BLERadioClient.ConnectionState = .disconnected

    /// Current radio frequency in MHz (nil if unknown)
    var radioFrequencyMHz: Double?

    /// Current radio mode string (nil if unknown)
    var radioMode: String?

    /// Discovered BLE devices during scanning
    var discoveredDevices: [BLERadioClient.DiscoveredDevice] = []

    /// Whether currently scanning
    var isScanning = false

    /// Callback when radio frequency changes (set by session manager)
    var onRadioFrequencyChanged: ((Double) -> Void)?

    /// Callback when radio mode changes (set by session manager)
    var onRadioModeChanged: ((String) -> Void)?

    /// Saved device name (persisted)
    var savedDeviceName: String? {
        UserDefaults.standard.string(forKey: Keys.savedDeviceName)
    }

    /// Saved device UUID (persisted)
    var savedDeviceUUID: UUID? {
        guard let str = UserDefaults.standard.string(forKey: Keys.savedDeviceUUID) else {
            return nil
        }
        return UUID(uuidString: str)
    }

    /// Whether a device is configured
    var isConfigured: Bool {
        savedDeviceUUID != nil
    }

    /// Whether currently connected
    var isConnected: Bool {
        connectionStatus == .connected
    }

    /// Current protocol (persisted in UserDefaults)
    var rigProtocol: RigProtocol {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.rigProtocol),
                  let proto = RigProtocol(rawValue: raw)
            else {
                return .civ
            }
            return proto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.rigProtocol)
        }
    }

    // MARK: - Scanning

    func startScan() {
        guard !isScanning else {
            return
        }
        isScanning = true
        discoveredDevices = []
        scanTask = Task {
            let stream = await client.startScanning()
            for await devices in stream {
                self.discoveredDevices = devices.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            }
            self.isScanning = false
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        Task { await client.stopScanning() }
        isScanning = false
    }

    /// Select and save a device, then connect
    func selectDevice(_ device: BLERadioClient.DiscoveredDevice) {
        UserDefaults.standard.set(device.name, forKey: Keys.savedDeviceName)
        UserDefaults.standard.set(device.id.uuidString, forKey: Keys.savedDeviceUUID)

        stopScan()

        // Connect with the existing client that already has the peripheral
        connectToSavedDevice()
    }

    /// Forget the saved device and disconnect
    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: Keys.savedDeviceName)
        UserDefaults.standard.removeObject(forKey: Keys.savedDeviceUUID)
        radioFrequencyMHz = nil
        radioMode = nil
    }

    // MARK: - Connection

    /// Connect to the saved device
    func connectToSavedDevice() {
        guard let uuid = savedDeviceUUID else {
            return
        }
        connectionStatus = .connecting("Starting")

        // Start state monitoring
        stateTask?.cancel()
        stateTask = Task {
            let stream = await client.stateStream()
            for await state in stream {
                self.connectionStatus = state
                if state == .connected {
                    self.startPolling()
                } else if case .disconnected = state {
                    self.stopPolling()
                }
            }
        }

        Task { await client.connect(deviceUUID: uuid) }
    }

    /// Disconnect from the radio
    func disconnect() {
        stopPolling()
        stateTask?.cancel()
        stateTask = nil
        Task { await client.disconnect() }
        connectionStatus = .disconnected
    }

    // MARK: - Radio Control

    /// Set frequency on the radio (called from app → radio)
    func setFrequency(_ mhz: Double) {
        lastAppSetFrequency = mhz
        lastAppSetTime = Date()
        Task {
            try? await client.setFrequency(mhz)
        }
    }

    /// Set mode on the radio (called from app → radio)
    func setMode(_ mode: String) {
        lastAppSetMode = mode
        lastAppSetTime = Date()
        Task {
            try? await client.setMode(mode)
        }
    }

    /// Manually refresh radio state
    func refreshRadioState() {
        Task { await pollRadio() }
    }

    /// Update the rig address (from settings)
    func updateRigAddress(_ address: UInt8) {
        UserDefaults.standard.set(Int(address), forKey: Keys.rigAddress)
        reconnectWithNewClient()
    }

    /// Update the protocol and reconnect if needed.
    func updateProtocol(_ newProtocol: RigProtocol) {
        guard newProtocol != rigProtocol else {
            return
        }
        rigProtocol = newProtocol
        reconnectWithNewClient()
    }

    /// Detect protocol from a rig name and update if different.
    func setProtocolFromRig(_ rigName: String?) {
        guard let detected = RigProtocolDetector.detect(rigName: rigName) else {
            return
        }
        updateProtocol(detected)
    }

    // MARK: Private

    private enum Keys {
        static let savedDeviceName = "bleRadio.savedDeviceName"
        static let savedDeviceUUID = "bleRadio.savedDeviceUUID"
        static let rigAddress = "bleRadio.rigAddress"
        static let rigProtocol = "bleRadio.rigProtocol"
    }

    private var client = BLERadioClient()
    private var scanTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    // Feedback loop prevention
    private var lastAppSetFrequency: Double?
    private var lastAppSetMode: String?
    private var lastAppSetTime: Date?
    private let feedbackSuppressionWindow: TimeInterval = 0.5

    /// Configured CI-V rig address
    private var configuredRigAddress: UInt8 {
        let stored = UserDefaults.standard.integer(forKey: Keys.rigAddress)
        return stored > 0 ? UInt8(stored) : 0xA4
    }

    /// Recreate the client with current protocol and rig address settings
    private func recreateClient() {
        client = BLERadioClient(
            protocol: rigProtocol,
            civAddress: configuredRigAddress
        )
    }

    /// Disconnect, recreate client, and reconnect if was connected
    private func reconnectWithNewClient() {
        let wasConnected = isConnected
        if wasConnected {
            disconnect()
        }
        recreateClient()
        if wasConnected {
            connectToSavedDevice()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            // Initial read
            await pollRadio()

            // Poll every 2 seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else {
                    break
                }
                await pollRadio()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollRadio() async {
        do {
            let freq = try await client.readFrequency()
            let mode = try await client.readMode()

            // Check feedback suppression
            let now = Date()
            let suppressFreq = shouldSuppressFrequency(freq, at: now)
            let suppressMode = shouldSuppressMode(mode, at: now)

            if !suppressFreq, radioFrequencyMHz != freq {
                radioFrequencyMHz = freq
                onRadioFrequencyChanged?(freq)
            }

            if !suppressMode, radioMode != mode {
                radioMode = mode
                onRadioModeChanged?(mode)
            }
        } catch {
            // Polling errors are expected during transient disconnects
        }
    }

    // MARK: - Feedback Loop Prevention

    private func shouldSuppressFrequency(_ freq: Double, at now: Date) -> Bool {
        guard let lastFreq = lastAppSetFrequency,
              let lastTime = lastAppSetTime,
              now.timeIntervalSince(lastTime) < feedbackSuppressionWindow
        else {
            return false
        }
        // Suppress if within 100 Hz of what we just set
        return abs(freq - lastFreq) < 0.0001
    }

    private func shouldSuppressMode(_ mode: String, at now: Date) -> Bool {
        guard let lastMode = lastAppSetMode,
              let lastTime = lastAppSetTime,
              now.timeIntervalSince(lastTime) < feedbackSuppressionWindow
        else {
            return false
        }
        return mode == lastMode
    }
}
