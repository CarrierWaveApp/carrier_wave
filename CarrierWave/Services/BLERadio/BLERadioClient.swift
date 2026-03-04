import CarrierWaveData
import CoreBluetooth
import Foundation

// MARK: - BLERadioClient

/// Low-level CoreBluetooth client for BLE radio control over Nordic UART Service.
/// Supports CI-V (Icom/Xiegu) and Kenwood/Elecraft text protocols.
actor BLERadioClient {
    // MARK: Lifecycle

    init(
        protocol rigProtocol: RigProtocol = .civ,
        civAddress: UInt8 = 0xA4
    ) {
        protocolHandler = RigProtocolHandler(
            protocol: rigProtocol, civAddress: civAddress
        )
    }

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
    enum ConnectionState: Sendable, Equatable {
        case disconnected
        case scanning
        case connecting(String) // phase description
        case connected
        case error(String)
    }

    /// A discovered BLE device
    struct DiscoveredDevice: Identifiable, Sendable {
        let id: UUID
        let name: String
        let rssi: Int
        let lastSeen: Date
    }

    /// Protocol handler for encoding/decoding radio commands
    let protocolHandler: RigProtocolHandler

    /// Current connection state
    var currentState: ConnectionState {
        state
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

    /// Connect to a device by UUID
    func connect(deviceUUID: UUID) {
        state = .connecting("BLE link")
        delegate.connect(deviceUUID: deviceUUID)
    }

    /// Disconnect from the current device
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        targetDeviceUUID = nil
        delegate.disconnect()
        state = .disconnected
        receiveBuffer = []
        cancelPendingRequests()
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

    // MARK: - Radio Commands

    /// Read the current frequency from the radio (returns MHz)
    func readFrequency() async throws -> Double {
        let data = protocolHandler.encodeReadFrequency()
        let tag = protocolHandler.expectedTagForReadFrequency()
        let response = try await sendAndWaitForResponse(data, expectedTag: tag)
        guard let mhz = protocolHandler.decodeFrequency(response) else {
            throw BLERadioError.invalidResponse
        }
        return mhz
    }

    /// Read the current mode from the radio
    func readMode() async throws -> String {
        let data = protocolHandler.encodeReadMode()
        let tag = protocolHandler.expectedTagForReadMode()
        let response = try await sendAndWaitForResponse(data, expectedTag: tag)
        guard let mode = protocolHandler.decodeMode(response) else {
            throw BLERadioError.invalidResponse
        }
        return mode
    }

    /// Set the radio frequency (in MHz)
    func setFrequency(_ mhz: Double) async throws {
        let data = protocolHandler.encodeSetFrequency(mhz: mhz)
        let tag = protocolHandler.expectedTagForSetFrequency()
        let response = try await sendAndWaitForResponse(data, expectedTag: tag)
        if protocolHandler.isNak(response) {
            throw BLERadioError.commandRejected
        }
    }

    /// Set the radio mode
    func setMode(_ mode: String) async throws {
        guard let data = protocolHandler.encodeSetMode(mode) else {
            throw BLERadioError.unsupportedMode(mode)
        }
        let tag = protocolHandler.expectedTagForSetMode()
        let response = try await sendAndWaitForResponse(data, expectedTag: tag)
        if protocolHandler.isNak(response) {
            throw BLERadioError.commandRejected
        }
    }

    // MARK: - Delegate Callbacks (called from BLEDelegate)

    func handleStateChange(_ newState: ConnectionState) {
        let oldState = state
        state = newState
        stateContinuation?.yield(newState)

        // Handle disconnect with auto-reconnect
        if case .disconnected = newState,
           case .connected = oldState,
           targetDeviceUUID != nil
        {
            startAutoReconnect()
        }
    }

    func handleDiscoveredDevice(_ device: DiscoveredDevice) {
        // Update or add device
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
        stateContinuation?.yield(.connected)
    }

    func handleReceivedData(_ data: Data) {
        receiveBuffer.append(contentsOf: data)
        let (responses, consumed) = protocolHandler.extractResponses(
            from: receiveBuffer
        )
        if consumed > 0 {
            receiveBuffer.removeFirst(consumed)
        }

        for response in responses {
            resumePendingRequest(with: response)
        }
    }

    func writeData(_ data: Data) {
        delegate.writeData(data)
    }

    // MARK: Private

    private struct PendingRequest {
        let expectedTag: String
        let continuation: CheckedContinuation<RigResponse, Error>
        let timeoutTask: Task<Void, Never>
    }

    private var _delegate: BLEDelegate?
    private var discoveredDevices: [DiscoveredDevice] = []
    private var scanContinuation: AsyncStream<[DiscoveredDevice]>.Continuation?
    private var stateContinuation: AsyncStream<ConnectionState>.Continuation?
    private var receiveBuffer: [UInt8] = []
    private var targetDeviceUUID: UUID?

    /// Response matching
    private var pendingRequest: PendingRequest?

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
            _delegate = BLEDelegate(client: self)
        }
        return _delegate!
    }

    private func handleScanTermination() {
        scanContinuation = nil
    }

    private func clearStateContinuation() {
        stateContinuation = nil
    }

    private func sendAndWaitForResponse(
        _ data: [UInt8],
        expectedTag: String
    ) async throws -> RigResponse {
        guard state == .connected else {
            throw BLERadioError.notConnected
        }

        // Cancel any existing pending request
        cancelPendingRequests()

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(3))
                self.handleTimeout()
            }

            pendingRequest = PendingRequest(
                expectedTag: expectedTag,
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            delegate.writeData(Data(data))
        }
    }

    private func resumePendingRequest(with response: RigResponse) {
        guard let pending = pendingRequest else {
            return
        }

        let matches = protocolHandler.responseMatchesTag(
            response, expectedTag: pending.expectedTag
        )

        if matches {
            pending.timeoutTask.cancel()
            let continuation = pending.continuation
            pendingRequest = nil
            continuation.resume(returning: response)
        }
    }

    private func handleTimeout() {
        guard let pending = pendingRequest else {
            return
        }
        let continuation = pending.continuation
        pendingRequest = nil
        continuation.resume(throwing: BLERadioError.timeout)
    }

    private func cancelPendingRequests() {
        if let pending = pendingRequest {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: CancellationError())
            pendingRequest = nil
        }
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
            connect(deviceUUID: uuid)
        }
    }
}

// MARK: - BLERadioError

enum BLERadioError: LocalizedError {
    case notConnected
    case timeout
    case invalidResponse
    case commandRejected
    case unsupportedMode(String)
    case bluetoothOff

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to radio"
        case .timeout: "Radio did not respond"
        case .invalidResponse: "Invalid response from radio"
        case .commandRejected: "Command rejected by radio"
        case let .unsupportedMode(mode): "Mode '\(mode)' not supported"
        case .bluetoothOff: "Bluetooth is turned off"
        }
    }
}
