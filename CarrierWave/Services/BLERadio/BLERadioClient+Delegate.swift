import CarrierWaveData
import CoreBluetooth
import Foundation

// MARK: - BLEDelegate

/// CoreBluetooth delegate that forwards events to the BLERadioClient actor.
/// Must be a class (NSObject subclass) for CB delegate conformance.
/// Explicitly nonisolated to opt out of the project's default MainActor isolation,
/// since CoreBluetooth calls delegate methods on the main queue.
nonisolated final class BLEDelegate: NSObject, @unchecked Sendable {
    // MARK: Lifecycle

    init(client: BLERadioClient) {
        self.client = client
        super.init()
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        centralManager.delegate = self
    }

    // MARK: Internal

    func startScanning() {
        if centralManager.state == .poweredOn {
            beginScan()
        } else {
            // Bluetooth not ready yet — defer until centralManagerDidUpdateState
            pendingScan = true
        }
    }

    func stopScanning() {
        pendingScan = false
        centralManager.stopScan()
    }

    func connect(deviceUUID: UUID) {
        print("[BLE] connect called for \(deviceUUID), state=\(centralManager.state.rawValue)")

        // Defer connection until Bluetooth is powered on (mirrors pendingScan pattern)
        guard centralManager.state == .poweredOn else {
            print("[BLE] BT not ready, deferring connect for \(deviceUUID)")
            pendingConnectUUID = deviceUUID
            Task { await client?.handleStateChange(.connecting("Waiting for Bluetooth")) }
            return
        }

        pendingConnectUUID = nil
        performConnect(deviceUUID: deviceUUID)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
    }

    func writeData(_ data: Data) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic
        else {
            return
        }

        // Use writeWithoutResponse for lower latency when supported
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    // MARK: Private

    private weak var client: BLERadioClient?
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    /// Deferred scan: set when startScanning() is called before Bluetooth is powered on
    private var pendingScan = false

    /// Deferred connect: set when connect() is called before Bluetooth is powered on
    private var pendingConnectUUID: UUID?

    private func performConnect(deviceUUID: UUID) {
        print("[BLE] performConnect for \(deviceUUID)")
        print("[BLE] discoveredPeripherals: \(discoveredPeripherals.keys)")

        // Try to find from already-discovered peripherals
        if let peripheral = discoveredPeripherals[deviceUUID] {
            Task { await client?.handleStateChange(.connecting("Found, linking")) }
            connectedPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
            return
        }

        // Try to retrieve known peripheral
        Task { await client?.handleStateChange(.connecting("Retrieving")) }
        let peripherals = centralManager.retrievePeripherals(
            withIdentifiers: [deviceUUID]
        )
        if let peripheral = peripherals.first {
            Task { await client?.handleStateChange(.connecting("Retrieved, linking")) }
            discoveredPeripherals[deviceUUID] = peripheral
            connectedPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
        } else {
            Task {
                await client?.handleStateChange(
                    .error("Not found (\(discoveredPeripherals.count) known)")
                )
            }
        }
    }

    private func beginScan() {
        discoveredPeripherals.removeAll()
        // Scan without service filter — some BLE stacks don't include
        // 128-bit NUS UUID in advertisement packets.
        // No AllowDuplicates — one report per device keeps the list stable.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: nil
        )
    }
}

// MARK: @preconcurrency CBCentralManagerDelegate

extension BLEDelegate: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Retry deferred connect if one was requested before BT was ready
            if let uuid = pendingConnectUUID {
                pendingConnectUUID = nil
                performConnect(deviceUUID: uuid)
            }
            // Start deferred scan if one was requested before BT was ready
            if pendingScan {
                pendingScan = false
                beginScan()
            }
        case .poweredOff:
            Task { await client?.handleStateChange(.error("Bluetooth is off")) }
        case .unauthorized:
            Task {
                await client?.handleStateChange(
                    .error("Bluetooth not authorized")
                )
            }
        case .unsupported:
            Task { await client?.handleStateChange(.error("BLE not supported")) }
        default:
            break
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Get name from advertisement data (more reliable) or peripheral
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
        guard let name, !name.isEmpty else {
            return
        }

        discoveredPeripherals[peripheral.identifier] = peripheral
        let device = BLERadioClient.DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            lastSeen: Date()
        )
        Task { await client?.handleDiscoveredDevice(device) }
    }

    func centralManager(
        _: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        Task { await client?.handleStateChange(.connecting("Discovering services")) }
        peripheral.delegate = self
        peripheral.discoverServices([BLERadioClient.NUS.service])
    }

    func centralManager(
        _: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        print("[BLE] didFailToConnect: \(peripheral.identifier) error: \(String(describing: error))")
        let msg = error?.localizedDescription ?? "Connection failed"
        Task { await client?.handleStateChange(.error(msg)) }
    }

    func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error _: Error?
    ) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        Task { await client?.handleStateChange(.disconnected) }
    }
}

// MARK: @preconcurrency CBPeripheralDelegate

extension BLEDelegate: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        print(
            "[BLE] didDiscoverServices: \(peripheral.services?.map(\.uuid) ?? []) error: \(String(describing: error))"
        )
        guard error == nil,
              let services = peripheral.services
        else {
            Task {
                await client?.handleStateChange(
                    .error(error?.localizedDescription ?? "No services")
                )
            }
            return
        }

        print("[BLE] Looking for NUS service in \(services.map(\.uuid))")
        for service in services where service.uuid == BLERadioClient.NUS.service {
            print("[BLE] Found NUS, discovering characteristics")
            // Discover all characteristics — some BLE stacks combine
            // write+notify on a single characteristic
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let charUUIDs = service.characteristics?.map(\.uuid) ?? []
        print("[BLE] didDiscoverCharacteristics: \(charUUIDs) error: \(String(describing: error))")
        guard error == nil,
              let characteristics = service.characteristics
        else {
            return
        }

        for char in characteristics {
            print("[BLE] Char: \(char.uuid) props: \(char.properties.rawValue)")

            // Standard NUS: separate write (6E400002) and notify (6E400003) chars
            // Some BLE stacks (like ble_cat) combine both on the write char
            if char.uuid == BLERadioClient.NUS.writeChar {
                writeCharacteristic = char
                // If this char also supports notify, use it for receiving too
                if char.properties.contains(.notify) {
                    notifyCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                }
            } else if char.uuid == BLERadioClient.NUS.notifyChar {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }

        // Both characteristics found — we're connected
        print("[BLE] write=\(writeCharacteristic != nil) notify=\(notifyCharacteristic != nil)")
        if writeCharacteristic != nil, notifyCharacteristic != nil {
            Task {
                await client?.handleConnected(
                    deviceUUID: peripheral.identifier
                )
            }
        }
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic == notifyCharacteristic,
              let data = characteristic.value
        else {
            return
        }

        Task { await client?.handleReceivedData(data) }
    }

    func peripheral(
        _: CBPeripheral,
        didWriteValueFor _: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            Task {
                await client?.handleStateChange(
                    .error("Write failed: \(error.localizedDescription)")
                )
            }
        }
    }
}
