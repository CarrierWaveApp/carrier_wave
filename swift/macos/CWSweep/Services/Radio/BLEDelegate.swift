import CoreBluetooth
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "BLEDelegate")

// MARK: - BLEDelegate

/// CoreBluetooth delegate that forwards events to the `BLERadioTransport` actor.
/// Must be an NSObject subclass for CB delegate conformance. Explicitly
/// nonisolated because CoreBluetooth calls delegate methods on the main queue.
nonisolated final class BLEDelegate: NSObject, @unchecked Sendable {
    // MARK: Lifecycle

    init(transport: BLERadioTransport) {
        self.transport = transport
        super.init()
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        centralManager.delegate = self
    }

    // MARK: Internal

    func startScanning() {
        if centralManager.state == .poweredOn {
            beginScan()
        } else {
            pendingScan = true
        }
    }

    func stopScanning() {
        pendingScan = false
        centralManager.stopScan()
    }

    func connect(deviceUUID: UUID) {
        guard centralManager.state == .poweredOn else {
            pendingConnectUUID = deviceUUID
            Task { await transport?.handleStateChange(.connecting("Waiting for Bluetooth")) }
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

        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    // MARK: Private

    private weak var transport: BLERadioTransport?
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    private var pendingScan = false
    private var pendingConnectUUID: UUID?

    private func performConnect(deviceUUID: UUID) {
        if let peripheral = discoveredPeripherals[deviceUUID] {
            Task { await transport?.handleStateChange(.connecting("Found, linking")) }
            connectedPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
            return
        }

        Task { await transport?.handleStateChange(.connecting("Retrieving")) }
        let peripherals = centralManager.retrievePeripherals(
            withIdentifiers: [deviceUUID]
        )
        if let peripheral = peripherals.first {
            Task { await transport?.handleStateChange(.connecting("Retrieved, linking")) }
            discoveredPeripherals[deviceUUID] = peripheral
            connectedPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
        } else {
            Task {
                await transport?.handleStateChange(
                    .error("Device not found (\(discoveredPeripherals.count) known)")
                )
            }
        }
    }

    private func beginScan() {
        discoveredPeripherals.removeAll()
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
            if let uuid = pendingConnectUUID {
                pendingConnectUUID = nil
                performConnect(deviceUUID: uuid)
            }
            if pendingScan {
                pendingScan = false
                beginScan()
            }
        case .poweredOff:
            Task { await transport?.handleStateChange(.error("Bluetooth is off")) }
        case .unauthorized:
            Task {
                await transport?.handleStateChange(
                    .error("Bluetooth not authorized")
                )
            }
        case .unsupported:
            Task { await transport?.handleStateChange(.error("BLE not supported")) }
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
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
        guard let name, !name.isEmpty else {
            return
        }

        discoveredPeripherals[peripheral.identifier] = peripheral
        let device = BLERadioTransport.DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            lastSeen: Date()
        )
        Task { await transport?.handleDiscoveredDevice(device) }
    }

    func centralManager(
        _: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        Task { await transport?.handleStateChange(.connecting("Discovering services")) }
        peripheral.delegate = self
        peripheral.discoverServices([BLERadioTransport.NUS.service])
    }

    func centralManager(
        _: CBCentralManager,
        didFailToConnect _: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription ?? "Connection failed"
        Task { await transport?.handleStateChange(.error(msg)) }
    }

    func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error _: Error?
    ) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        Task { await transport?.handleStateChange(.disconnected) }
    }
}

// MARK: @preconcurrency CBPeripheralDelegate

extension BLEDelegate: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil,
              let services = peripheral.services
        else {
            Task {
                await transport?.handleStateChange(
                    .error(error?.localizedDescription ?? "No services")
                )
            }
            return
        }

        guard let nusService = services.first(where: { $0.uuid == BLERadioTransport.NUS.service }) else {
            Task {
                await transport?.handleStateChange(
                    .error("NUS service not found")
                )
            }
            return
        }
        peripheral.discoverCharacteristics(nil, for: nusService)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristics = service.characteristics
        else {
            return
        }

        for char in characteristics {
            if char.uuid == BLERadioTransport.NUS.writeChar {
                writeCharacteristic = char
                if char.properties.contains(.notify) {
                    notifyCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                }
            } else if char.uuid == BLERadioTransport.NUS.notifyChar {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }

        if writeCharacteristic != nil, notifyCharacteristic != nil {
            let deviceUUID = peripheral.identifier
            Task {
                await transport?.handleConnected(
                    deviceUUID: deviceUUID
                )
            }
        } else {
            let missing = [
                writeCharacteristic == nil ? "write" : nil,
                notifyCharacteristic == nil ? "notify" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            logger.error("Missing BLE characteristics: \(missing)")
            Task {
                await transport?.handleStateChange(
                    .error("Missing BLE characteristics: \(missing)")
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

        Task { await transport?.handleReceivedData(data) }
    }

    func peripheral(
        _: CBPeripheral,
        didWriteValueFor _: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            Task {
                await transport?.handleStateChange(
                    .error("Write failed: \(error.localizedDescription)")
                )
            }
        }
    }
}
