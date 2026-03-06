import Foundation

/// Transport abstraction for radio communication.
/// BLE on iOS, serial on macOS — same protocol logic above this layer.
public protocol RadioTransport: Sendable {
    var isConnected: Bool { get async }
    func send(_ data: Data) async throws
    var receivedData: AsyncStream<Data> { get }
    func connect() async throws
    func disconnect() async
}
