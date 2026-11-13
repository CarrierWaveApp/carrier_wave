import CarrierWaveData
import CoreBluetooth
import Foundation

// MARK: - BLEDelegate

/// CoreBluetooth delegate that forwards events to the BLERadioTransport actor.
/// Must be a class (NSObject subclass) for CB delegate conformance.
/// Explicitly nonisolated to opt out of the project's default MainActor isolation,
/// since CoreBluetooth calls delegate methods on the main queue.
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
            // Bluetooth not ready yet — defer until centralManagerDidUpdateState
            pendingScan = true
        }
    }

    func stopScanning() {
        pendingScan = false
        centralManager.stopScan()
    }

    func connect(deviceUUID: UUID, fallbackName: String? = nil) {
        print("[BLE] connect called for \(deviceUUID), state=\(centralManager.state.rawValue)")
        targetName = fallbackName

        // Defer connection until Bluetooth is powered on (mirrors pendingScan pattern)
        guard centralManager.state == .poweredOn else {
            print("[BLE] BT not ready, deferring connect for \(deviceUUID)")
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

        // Default to .withResponse for reliable delivery of control/protocol
        // messages (handshake, CAT bytes). writeWithoutResponse can be silently
        // dropped right after subscribe (controller state / MTU negotiation
        // races) and gives us no feedback. The latency-critical CW keyer path
        // bypasses this method via `directWriter` and uses .withoutResponse
        // explicitly.
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.write)
                ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    // MARK: Private

    private weak var transport: BLERadioTransport?
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    /// Deferred scan: set when startScanning() is called before Bluetooth is powered on
    private var pendingScan = false

    /// Deferred connect: set when connect() is called before Bluetooth is powered on
    private var pendingConnectUUID: UUID?

    /// Advertised name to fall back to when the saved UUID can't connect.
    /// On timeout, a name-based scan rebinds the persisted UUID via
    /// `transport.handleRebind(...)`.
    private var targetName: String?

    /// While true, didDiscover matches `targetName` and rebinds.
    private var rebindScanActive = false

    private func performConnect(deviceUUID: UUID) {
        // Always clear any stale connection state for this UUID before
        // calling connect(). If iOS thinks the peripheral is already
        // .connecting or .connected (from a previous session that didn't
        // disconnect cleanly), connect() becomes a no-op and we hang in
        // "Found, linking" forever waiting for didConnect that never fires.
        let peripheral = discoveredPeripherals[deviceUUID]
            ?? centralManager.retrievePeripherals(withIdentifiers: [deviceUUID]).first

        guard let peripheral else {
            Task { @MainActor in
                RadioService.shared.addLog(
                    .error,
                    "BLE: peripheral \(deviceUUID) not found (\(discoveredPeripherals.count) discovered)"
                )
            }
            Task {
                await transport?.handleStateChange(
                    .error("Not found (\(discoveredPeripherals.count) known)")
                )
            }
            return
        }

        // Log the peripheral's current state so we can diagnose stuck
        // connect calls. iOS won't surface "still connected from last
        // session" any other way.
        let stateName = switch peripheral.state {
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .connected: "connected"
        case .disconnecting: "disconnecting"
        @unknown default: "unknown(\(peripheral.state.rawValue))"
        }
        Task { @MainActor in
            RadioService.shared.addLog(
                .info,
                "BLE: connecting to \(deviceUUID) (peripheral.state=\(stateName))"
            )
        }

        // Force-cancel any stale connection, then start fresh. cancelPeripheralConnection
        // is a no-op if the peripheral is already disconnected, so this is safe.
        centralManager.cancelPeripheralConnection(peripheral)

        discoveredPeripherals[deviceUUID] = peripheral
        connectedPeripheral = peripheral
        Task { await transport?.handleStateChange(.connecting("Linking")) }
        centralManager.connect(peripheral, options: nil)

        // Watchdog: 15 s gives time for BLE supervision timeout (~6 s) +
        // a fresh connect attempt to land before we declare failure.
        let snapshotID = peripheral.identifier
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self else {
                return
            }
            // Hop to main actor to read CB state safely (iOS 17+ requires
            // CB callers to be on the MainActor for state reads).
            let stillStuck: Bool = await MainActor.run {
                guard let peripheral = self.discoveredPeripherals[snapshotID] else {
                    return false
                }
                return peripheral.state == .connecting
            }
            if stillStuck {
                await handleConnectTimeout(snapshotID: snapshotID)
            }
        }
    }

    /// Called when the saved UUID's connect hangs past the watchdog.
    /// Drops the cached peripheral and either falls back to a name-based
    /// rescan (if `targetName` is set, e.g. "CW Bridge") so we can rebind
    /// to whatever address the bridge happens to advertise with now, or
    /// surfaces an error.
    private func handleConnectTimeout(snapshotID: UUID) async {
        let name = targetName
        let nameDesc = name.map { "rescanning by name '\($0)'" } ?? "no fallback name"
        await MainActor.run {
            RadioService.shared.addLog(
                .error,
                "BLE: connect to \(snapshotID) timed out — \(nameDesc)"
            )
            if let peripheral = self.discoveredPeripherals[snapshotID] {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
            self.discoveredPeripherals.removeValue(forKey: snapshotID)
            self.connectedPeripheral = nil
        }
        guard let name, !name.isEmpty else {
            await transport?.handleStateChange(
                .error("Connect timed out — re-scan from device picker")
            )
            return
        }
        await transport?.handleStateChange(.connecting("Rescanning for \(name)"))
        await MainActor.run {
            self.rebindScanActive = true
            self.beginScan()
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
        // Get name from advertisement data (more reliable) or peripheral
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
        guard let name, !name.isEmpty else {
            return
        }

        discoveredPeripherals[peripheral.identifier] = peripheral

        // Rebind path: a previous connect-by-saved-UUID timed out and we're
        // now scanning by advertised name. First device whose name matches
        // wins — we rebind to its CBPeripheral and connect.
        if rebindScanActive, let target = targetName, name == target {
            rebindScanActive = false
            centralManager.stopScan()
            let newID = peripheral.identifier
            Task { @MainActor in
                RadioService.shared.addLog(
                    .info,
                    "BLE: rebinding saved UUID → \(newID) (matched '\(name)')"
                )
            }
            // Tell the transport (and through it RadioService) to persist
            // the new UUID, then drive a fresh connect against it.
            Task { [weak self] in
                await self?.transport?.handleRebind(deviceUUID: newID)
                await MainActor.run {
                    self?.performConnect(deviceUUID: newID)
                }
            }
            return
        }

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
        let pid = peripheral.identifier
        Task { @MainActor in
            RadioService.shared.addLog(.info, "BLE: didConnect \(pid) — discovering services")
        }
        Task { await transport?.handleStateChange(.connecting("Discovering services")) }
        peripheral.delegate = self
        peripheral.discoverServices([BLERadioTransport.NUS.service])
    }

    func centralManager(
        _: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let pid = peripheral.identifier
        let errMsg = error?.localizedDescription ?? "no error"
        Task { @MainActor in
            RadioService.shared.addLog(
                .error,
                "BLE: didFailToConnect \(pid) — \(errMsg)"
            )
        }
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
        print(
            "[BLE] didDiscoverServices: \(peripheral.services?.map(\.uuid) ?? []) error: \(String(describing: error))"
        )
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

        print("[BLE] Looking for NUS service in \(services.map(\.uuid))")
        guard let nusService = services.first(where: { $0.uuid == BLERadioTransport.NUS.service }) else {
            print("[BLE] NUS service not found in discovered services")
            Task {
                await transport?.handleStateChange(
                    .error("NUS service not found")
                )
            }
            return
        }
        print("[BLE] Found NUS, discovering characteristics")
        peripheral.discoverCharacteristics(nil, for: nusService)
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
            if char.uuid == BLERadioTransport.NUS.writeChar {
                writeCharacteristic = char
                // If this char also supports notify, use it for receiving too
                if char.properties.contains(.notify) {
                    notifyCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                }
            } else if char.uuid == BLERadioTransport.NUS.notifyChar {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }

        // Both characteristics found, but DON'T fire .connected yet.
        // setNotifyValue(true) is only a request — the CCCD write is
        // still in flight. If we proceed now, BridgeProtocol.start() will
        // send HandshakeReq before the firmware sees TX_SUBSCRIBED=true,
        // and the firmware will silently drop its response (subscribed()
        // returns false), causing a 2s handshake timeout.
        // Wait for didUpdateNotificationStateFor to confirm.
        print("[BLE] write=\(writeCharacteristic != nil) notify=\(notifyCharacteristic != nil)")
        if writeCharacteristic == nil || notifyCharacteristic == nil {
            let missing = [
                writeCharacteristic == nil ? "write" : nil,
                notifyCharacteristic == nil ? "notify" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            print("[BLE] Missing characteristics: \(missing)")
            Task {
                await transport?.handleStateChange(
                    .error("Missing BLE characteristics: \(missing)")
                )
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            let charUUID = characteristic.uuid
            Task { @MainActor in
                RadioService.shared.addLog(
                    .error,
                    "BLE: subscribe failed for \(charUUID) — \(error.localizedDescription)"
                )
            }
            Task {
                await transport?.handleStateChange(
                    .error("BLE subscribe failed: \(error.localizedDescription)")
                )
            }
            return
        }
        guard characteristic == notifyCharacteristic, characteristic.isNotifying else {
            return
        }
        let charUUID = characteristic.uuid
        Task { @MainActor in
            RadioService.shared.addLog(.info, "BLE: subscribe confirmed for \(charUUID) — connected")
        }
        Task {
            await transport?.handleConnected(deviceUUID: peripheral.identifier)
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
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            let charUUID = characteristic.uuid
            let errMsg = error.localizedDescription
            Task { @MainActor in
                RadioService.shared.addLog(.error, "BLE: write failed for \(charUUID) — \(errMsg)")
            }
            Task {
                await transport?.handleStateChange(
                    .error("Write failed: \(errMsg)")
                )
            }
        } else {
            let charUUID = characteristic.uuid
            Task { @MainActor in
                RadioService.shared.addLog(.info, "BLE: write ack \(charUUID)")
            }
        }
    }
}
