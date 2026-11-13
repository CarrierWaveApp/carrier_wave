import Foundation
import Network

// MARK: - NWConnectionTransport

//
// Wraps one `NWConnection` as a `RemoteOpTransport`. Owns the newline-
// delimited buffering that's intrinsic to the TCP wire format — frames go
// out terminated by `\n`, and inbound bytes are split on `\n` before
// being handed up. Used for both server-accepted sockets (Sweep) and
// client-initiated sockets (Field).

public actor NWConnectionTransport: RemoteOpTransport {
    // MARK: Lifecycle

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    // MARK: Public

    public func start() async {
        guard !started else {
            return
        }
        started = true
        if incomingContinuation == nil {
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            incomingStream = stream
            incomingContinuation = continuation
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }
            Task { await self.handleState(state) }
        }
        connection.start(queue: queue)
        Task { await self.receiveLoop() }
    }

    public func send(_ frame: Data) async throws {
        var payload = frame
        payload.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: RemoteOpTransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func incoming() async -> AsyncStream<Data> {
        if let incomingStream {
            return incomingStream
        }
        // Caller invoked incoming() before start(); set up a stream and
        // remember it so the receive loop can publish into it once running.
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        incomingStream = stream
        incomingContinuation = continuation
        return stream
    }

    public func cancel() async {
        guard !cancelled else {
            return
        }
        cancelled = true
        connection.cancel()
        incomingContinuation?.finish()
        incomingContinuation = nil
    }

    // MARK: Private

    private let connection: NWConnection
    private let queue: DispatchQueue

    private var started = false
    private var cancelled = false
    private var receiveBuffer = Data()
    private var incomingStream: AsyncStream<Data>?
    private var incomingContinuation: AsyncStream<Data>.Continuation?

    private func handleState(_ state: NWConnection.State) async {
        switch state {
        case .failed,
             .cancelled:
            incomingContinuation?.finish()
            incomingContinuation = nil
        default:
            break
        }
    }

    private func receiveLoop() async {
        while !cancelled {
            let chunk = await receiveOnce()
            guard let data = chunk else {
                break
            }
            receiveBuffer.append(data)
            drainBuffer()
        }
        incomingContinuation?.finish()
        incomingContinuation = nil
    }

    private func receiveOnce() async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { data, _, isComplete, error in
                if error != nil || isComplete {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func drainBuffer() {
        while let newlineRange = receiveBuffer.range(of: Data([0x0A])) {
            let frame = receiveBuffer.subdata(in: 0 ..< newlineRange.lowerBound)
            receiveBuffer.removeSubrange(0 ..< newlineRange.upperBound)
            if frame.isEmpty {
                continue
            }
            incomingContinuation?.yield(frame)
        }
    }
}
