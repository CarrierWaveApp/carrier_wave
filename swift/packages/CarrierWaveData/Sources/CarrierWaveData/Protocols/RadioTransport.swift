import Foundation

// MARK: - RadioTransport

/// Transport abstraction for radio communication.
/// BLE on iOS, serial on macOS — same protocol logic above this layer.
public protocol RadioTransport: Sendable {
    var isConnected: Bool { get async }
    func send(_ data: Data) async throws
    var receivedData: AsyncStream<Data> { get }
    func connect() async throws
    func disconnect() async

    /// Recommended interval between poll commands.
    /// WiFi transports need slower polling (~1s) to avoid overwhelming the radio.
    var recommendedPollInterval: Duration { get }

    /// Send a semantic set-and-verify command via the bridge protocol.
    /// Returns the result code: 0x00=OK, 0x01=FAIL, 0x02=UNSUPPORTED.
    /// Default: returns 0x02 (unsupported) for non-bridge transports.
    func sendSetVerify(field: UInt8, value: Data) async -> UInt8
}

public extension RadioTransport {
    var recommendedPollInterval: Duration {
        .milliseconds(200)
    }

    func sendSetVerify(field: UInt8, value: Data) async -> UInt8 {
        0x02 // unsupported
    }
}
