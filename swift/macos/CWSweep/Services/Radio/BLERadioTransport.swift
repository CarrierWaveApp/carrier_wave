import CarrierWaveData
import CoreBluetooth
import Foundation

// MARK: - BLERadioTransport

/// Low-level CoreBluetooth transport for BLE radio control over Nordic UART Service.
/// Conforms to `RadioTransport` — forwards raw bytes only. Protocol framing is
/// handled by `BridgeProtocol`, which wraps this transport.
actor BLERadioTransport {
    // MARK: Internal

    /// NUS (Nordic UART Service) UUIDs
    enum NUS {
        nonisolated(unsafe) static let service = CBUUID(
            string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        )
        nonisolated(unsafe) static let writeChar = CBUUID(
            string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        )
        nonisolated(unsafe) static let notifyChar = CBUUID(
            string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
        )
    }

    /// Connection state
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting(String)
        case connected
        case error(String)
    }

    /// A discovered BLE device
    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let lastSeen: Date
    }

    /// Direct BLE writer for latency-critical paths (CW keyer). Safe because
    /// BLEDelegate is nonisolated and @unchecked Sendable.
    nonisolated(unsafe) private(set) var directWriter: BLEDelegate?

    /// Current connection state
    var currentState: ConnectionState {
        state
    }

    /// Create a fresh data stream. Each call replaces the active continuation —
    /// previous streams stop receiving data. This supports reconnect cycles.
    func makeDataStream() -> AsyncStream<Data> {
        AsyncStream<Data> { continuation in
            self.dataContinuation = continuation
        }
    }

    // MARK: - Scanning

    func startScanning() -> AsyncStream<[DiscoveredDevice]> {
        state = .scanning
        let stream = AsyncStream<[DiscoveredDevice]> { continuation in
            self.scanContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.handleScanTermination() }
            }
        }
        delegate.startScanning()
        return stream
    }

    func stopScanning() {
        delegate.stopScanning()
        scanContinuation?.finish()
        scanContinuation = nil
        if state == .scanning {
            state = .disconnected
        }
    }

    // MARK: - Connection

    func setTarget(deviceUUID: UUID) {
        targetDeviceUUID = deviceUUID
    }

    func stateStream() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearStateContinuation() }
            }
        }
    }

    // MARK: - Delegate Callbacks

    func handleStateChange(_ newState: ConnectionState) {
        let oldState = state
        state = newState

        if case .disconnected = newState,
           case .connected = oldState,
           targetDeviceUUID != nil
        {
            startAutoReconnect()
        }
    }

    func handleDiscoveredDevice(_ device: DiscoveredDevice) {
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[idx] = device
        } else {
            discoveredDevices.append(device)
        }
        scanContinuation?.yield(discoveredDevices)
    }

    func handleConnected(deviceUUID: UUID) {
        targetDeviceUUID = deviceUUID
        reconnectAttempts = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        state = .connected
    }

    func handleReceivedData(_ data: Data) {
        dataContinuation?.yield(data)
    }

    // MARK: Private

    private var _delegate: BLEDelegate?

    private var discoveredDevices: [DiscoveredDevice] = []
    private var scanContinuation: AsyncStream<[DiscoveredDevice]>.Continuation?
    private var stateContinuation: AsyncStream<ConnectionState>.Continuation?
    private var dataContinuation: AsyncStream<Data>.Continuation?
    private var targetDeviceUUID: UUID?

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    private var state: ConnectionState = .disconnected {
        didSet {
            stateContinuation?.yield(state)
        }
    }

    private var delegate: BLEDelegate {
        if _delegate == nil {
            _delegate = BLEDelegate(transport: self)
            directWriter = _delegate
        }
        return _delegate!
    }

    private func handleScanTermination() {
        scanContinuation = nil
    }

    private func clearStateContinuation() {
        stateContinuation = nil
    }

    private func startAutoReconnect() {
        guard let uuid = targetDeviceUUID,
              reconnectAttempts < maxReconnectAttempts
        else {
            state = .disconnected
            return
        }

        reconnectTask?.cancel()
        reconnectAttempts += 1

        let delay = min(Double(1 << reconnectAttempts), 30.0)
        let attempt = reconnectAttempts

        reconnectTask = Task {
            state = .error("Reconnecting (\(attempt))...")
            stateContinuation?.yield(state)

            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            connectToDevice(deviceUUID: uuid)
        }
    }

    private func connectToDevice(deviceUUID: UUID) {
        state = .connecting("BLE link")
        delegate.connect(deviceUUID: deviceUUID)
    }
}

// MARK: @preconcurrency RadioTransport

extension BLERadioTransport: @preconcurrency RadioTransport {
    nonisolated var receivedData: AsyncStream<Data> {
        AsyncStream { _ in }
    }

    var isConnected: Bool {
        state == .connected
    }

    func connect() async throws {
        guard state != .connected else {
            return
        }
        guard let uuid = targetDeviceUUID else {
            throw BLETransportError.noTargetDevice
        }
        connectToDevice(deviceUUID: uuid)
    }

    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        targetDeviceUUID = nil
        delegate.disconnect()
        state = .disconnected
    }

    func send(_ data: Data) async throws {
        guard state == .connected else {
            throw BLETransportError.notConnected
        }
        delegate.writeData(data)
    }
}

// MARK: - BLETransportError

enum BLETransportError: LocalizedError {
    case notConnected
    case noTargetDevice

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to radio"
        case .noTargetDevice: "No target device set — call setTarget(deviceUUID:) first"
        }
    }
}
