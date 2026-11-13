import CarrierWaveData
import CoreBluetooth
import Foundation

// MARK: - BLERadioTransport

/// Low-level CoreBluetooth transport for BLE radio control over Nordic UART Service.
/// Conforms to `RadioTransport` — forwards raw bytes only. No protocol handling.
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
        case connecting(String) // phase description
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

    /// Direct BLE writer for latency-critical paths (CW keyer).
    /// Safe because BLEDelegate is nonisolated and @unchecked Sendable.
    nonisolated(unsafe) private(set) var directWriter: BLEDelegate?

    /// Current connection state
    var currentState: ConnectionState {
        state
    }

    /// Create a fresh data stream. Each call replaces the active continuation —
    /// previous streams stop receiving data. This supports reconnect cycles
    /// where the old consumer is discarded and a new one starts.
    func makeDataStream() -> AsyncStream<Data> {
        AsyncStream<Data> { continuation in
            self.dataContinuation = continuation
        }
    }

    // MARK: - Scanning

    /// Start scanning for BLE devices advertising NUS.
    /// Returns an AsyncStream of discovered device lists.
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

    /// Stop scanning
    func stopScanning() {
        delegate.stopScanning()
        scanContinuation?.finish()
        scanContinuation = nil
        if state == .scanning {
            state = .disconnected
        }
    }

    // MARK: - Connection

    /// Set the target device UUID before calling connect().
    ///
    /// `fallbackName` is the advertised name used for a name-based rescan
    /// when the saved UUID is stale. When nil, the primary radio's saved
    /// bridge name from `RadioService` is used.
    func setTarget(deviceUUID: UUID, fallbackName: String? = nil) {
        targetDeviceUUID = deviceUUID
        targetFallbackName = fallbackName
    }

    /// Install a handler for name-based rebinds. Secondary transports (the
    /// satellite duplex links) persist their own UUIDs; when nil, the
    /// primary `RadioService` UUID is updated.
    func setRebindHandler(_ handler: (@Sendable (UUID) -> Void)?) {
        rebindHandler = handler
    }

    /// Subscribe to connection state changes
    func stateStream() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearStateContinuation() }
            }
        }
    }

    // MARK: - Delegate Callbacks (called from BLEDelegate)

    func handleStateChange(_ newState: ConnectionState) {
        let oldState = state
        state = newState
        // Note: state's didSet already yields to stateContinuation

        // Handle disconnect with auto-reconnect
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
        // Note: state's didSet already yields to stateContinuation
    }

    /// Called by the BLE delegate when a name-based rescan finds the device
    /// at a new address. Updates the persisted UUID so future connects skip
    /// the rescan, and updates our in-memory target so auto-reconnect uses
    /// the right peripheral.
    func handleRebind(deviceUUID: UUID) {
        targetDeviceUUID = deviceUUID
        if let rebindHandler {
            rebindHandler(deviceUUID)
            return
        }
        // Persist the new UUID through RadioService's UserDefaults-backed
        // accessor — has to hop to MainActor because RadioService is
        // @Observable @MainActor.
        Task { @MainActor in
            RadioService.shared.updateSavedDeviceUUID(deviceUUID)
            RadioService.shared.addLog(
                .info,
                "BLE: saved bridge UUID updated to \(deviceUUID)"
            )
        }
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
    private var targetFallbackName: String?
    private var rebindHandler: (@Sendable (UUID) -> Void)?

    // Auto-reconnect
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

    // MARK: - Auto-Reconnect

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
        // Pull the saved bridge name (e.g. "CW Bridge") so the delegate can
        // fall back to a name-based rescan if the saved UUID is stale.
        // Read UserDefaults directly — it's thread-safe and avoids hopping
        // to MainActor (we'd crash with assumeIsolated since this actor's
        // executor isn't the main one).
        let fallbackName = targetFallbackName
            ?? UserDefaults.standard.string(forKey: "bleRadio.savedDeviceName")
        delegate.connect(deviceUUID: deviceUUID, fallbackName: fallbackName)
    }
}

// MARK: @preconcurrency RadioTransport

extension BLERadioTransport: @preconcurrency RadioTransport {
    /// Satisfies RadioTransport — creates a fresh stream each access.
    /// Use `makeDataStream()` directly for explicit lifecycle control.
    nonisolated var receivedData: AsyncStream<Data> {
        AsyncStream { _ in }
    }

    var isConnected: Bool {
        state == .connected
    }

    func connect() async throws {
        // Already connected — skip redundant reconnect cycle
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
