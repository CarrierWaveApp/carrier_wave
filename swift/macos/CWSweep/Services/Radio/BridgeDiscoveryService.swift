import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "BridgeDiscovery")

// MARK: - BridgeDiscoveryService

/// BLE scanner for CW Bridge devices.
/// Maintains a short-lived `BLERadioTransport` used purely for discovery
/// so that the active bridge connection owns its own transport instance.
@MainActor
@Observable
final class BridgeDiscoveryService {
    // MARK: Internal

    private(set) var discoveredDevices: [BLERadioTransport.DiscoveredDevice] = []
    private(set) var isScanning: Bool = false
    private(set) var statusMessage: String?

    /// Saved peripheral UUID for the last paired CW Bridge.
    var savedDeviceUUID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.savedUUID) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set {
            if let uuid = newValue {
                UserDefaults.standard.set(uuid.uuidString, forKey: Keys.savedUUID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.savedUUID)
            }
        }
    }

    /// Human-readable name of the saved CW Bridge.
    var savedDeviceName: String? {
        get { UserDefaults.standard.string(forKey: Keys.savedName) }
        set {
            if let name = newValue {
                UserDefaults.standard.set(name, forKey: Keys.savedName)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.savedName)
            }
        }
    }

    /// Start a BLE scan for CW Bridge devices advertising NUS.
    func startScan() {
        guard !isScanning else {
            return
        }
        isScanning = true
        statusMessage = "Scanning for CW Bridge devices..."
        discoveredDevices = []

        let transport = BLERadioTransport()
        scanTransport = transport

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let stream = await transport.startScanning()
            for await devices in stream {
                guard let self else {
                    return
                }
                discoveredDevices = devices.sorted {
                    $0.name.localizedCompare($1.name) == .orderedAscending
                }
            }
            await MainActor.run {
                self?.isScanning = false
            }
        }

        // Automatically stop scanning after 20 seconds.
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else {
                return
            }
            self?.stopScan()
        }
    }

    /// Stop scanning and release the discovery transport.
    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        autoStopTask?.cancel()
        autoStopTask = nil
        if let transport = scanTransport {
            Task { await transport.stopScanning() }
        }
        scanTransport = nil
        isScanning = false
        statusMessage = nil
    }

    /// Persist the user's CW Bridge selection.
    func select(_ device: BLERadioTransport.DiscoveredDevice) {
        savedDeviceUUID = device.id
        savedDeviceName = device.name
        logger.info("Selected CW Bridge \(device.name)")
        stopScan()
    }

    /// Forget the saved device.
    func forgetDevice() {
        savedDeviceUUID = nil
        savedDeviceName = nil
    }

    // MARK: Private

    private enum Keys {
        static let savedUUID = "cwBridge.savedDeviceUUID"
        static let savedName = "cwBridge.savedDeviceName"
    }

    private var scanTransport: BLERadioTransport?
    private var scanTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
}
