import Darwin
import Foundation

// MARK: - PortChannel

/// A single UDP port using raw POSIX sockets.
/// NWConnection doesn't work reliably for receiving UDP from NAT'd endpoints,
/// so we use raw sockets like the working Python implementation.
final class PortChannel: @unchecked Sendable {
    // MARK: Lifecycle

    init(host: String, port: UInt16) {
        remoteHost = host
        remotePort = port

        let (strm, cont) = AsyncStream<Data>.makeStream()
        stream = strm
        streamContinuation = cont
    }

    // MARK: Internal

    var onError: ((String) -> Void)?
    /// Called for every received packet (for debugging)
    var onReceive: ((Data) -> Void)?
    var totalReceived = 0
    var recvLoopCount = 0
    var recvErrors = 0

    var totalSent = 0
    var lastSendError: Int32 = 0

    var inbound: AsyncStream<Data> {
        stream
    }

    func start() throws {
        // Resolve hostname
        guard let hostent = gethostbyname(remoteHost) else {
            throw SCULAN10Error.notConnected
        }
        let addrPtr = hostent.pointee.h_addr_list[0]!
        var inAddr = in_addr()
        memcpy(&inAddr, addrPtr, Int(hostent.pointee.h_length))
        resolvedAddr = inAddr

        // Create UDP socket
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw SCULAN10Error.notConnected
        }

        // Bind to any port
        var localAddr = sockaddr_in()
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_port = 0 // any port
        localAddr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            fd = -1
            throw SCULAN10Error.notConnected
        }

        // Set receive timeout to 100ms for the poll loop
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Start receive thread
        running = true
        receiveThread = Thread { [weak self] in
            self?.receiveLoop()
        }
        receiveThread?.qualityOfService = .userInitiated
        receiveThread?.start()
    }

    func stop() {
        running = false
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        streamContinuation.finish()
    }

    func send(_ data: Data) {
        guard fd >= 0 else {
            return
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = remotePort.bigEndian
        addr.sin_addr = resolvedAddr

        let result = data.withUnsafeBytes { rawBuf -> Int in
            let ptr = rawBuf.baseAddress!
            return withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    sendto(fd, ptr, data.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if result >= 0 {
            totalSent += 1
        } else {
            lastSendError = errno
        }
    }

    /// One-shot receive with timeout for auth handshake.
    func receive(timeout: TimeInterval) async -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let result: Data? = lock.withLock {
                if let data = buffer.first {
                    buffer.removeFirst()
                    return data
                }
                return nil
            }
            if let result {
                return result
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    /// Switch from buffered mode to streaming mode.
    func enableStreaming() {
        lock.withLock {
            let buffered = buffer
            buffer.removeAll()
            streaming = true
            for data in buffered {
                streamContinuation.yield(data)
            }
        }
    }

    // MARK: Private

    private let remoteHost: String
    private let remotePort: UInt16
    private var resolvedAddr = in_addr()
    private var fd: Int32 = -1
    private var running = false
    private var receiveThread: Thread?
    private let lock = NSLock()
    private var buffer: [Data] = []
    private var streaming = false
    private let stream: AsyncStream<Data>
    private let streamContinuation: AsyncStream<Data>.Continuation

    private func receiveLoop() {
        var recvBuf = [UInt8](repeating: 0, count: 8_192)
        while running {
            recvLoopCount += 1
            let bytesRead = recv(fd, &recvBuf, recvBuf.count, 0)
            if bytesRead > 0 {
                let data = Data(recvBuf[..<bytesRead])
                totalReceived += 1
                onReceive?(data)

                lock.withLock {
                    if streaming {
                        streamContinuation.yield(data)
                    } else {
                        buffer.append(data)
                    }
                }
            } else if bytesRead < 0, errno != EAGAIN, errno != EWOULDBLOCK {
                recvErrors += 1
                if !running {
                    break
                }
            }
        }
    }
}
