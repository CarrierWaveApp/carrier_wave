import Foundation

// MARK: - RemoteOpTransport

//
// Byte-pipe abstraction the Remote Op protocol layer sits on top of. Each
// element on `incoming()` is exactly one already-decoded JSON frame, so
// per-transport framing (newline delimiter for TCP, native message
// boundaries for MultipeerConnectivity) is hidden from
// `RemoteOpConnection` / `RemoteSweepClient`.

public protocol RemoteOpTransport: Sendable {
    /// Begin moving bytes. Idempotent. The transport may still be coming up
    /// when this returns; senders will queue until the underlying channel is
    /// ready, and `incoming()` will start emitting once frames arrive.
    func start() async

    /// Send one already-JSON-encoded frame. The transport applies whatever
    /// framing the underlying channel requires.
    func send(_ frame: Data) async throws

    /// Stream of complete inbound frames. Terminates when the transport
    /// closes (peer hang-up, cancel, or unrecoverable error).
    func incoming() async -> AsyncStream<Data>

    /// Tear down. Idempotent.
    func cancel() async
}

// MARK: - RemoteOpTransportError

public enum RemoteOpTransportError: Error, Sendable {
    case notReady
    case sendFailed(String)
    case cancelled
}
