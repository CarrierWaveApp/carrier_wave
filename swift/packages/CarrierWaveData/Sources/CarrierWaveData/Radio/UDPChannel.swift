import Darwin
import Foundation

// MARK: - IcomWiFiError

/// Errors for Icom WiFi transport operations.
public enum IcomWiFiError: LocalizedError {
    case dnsResolutionFailed(String)
    case socketCreationFailed
    case socketBindFailed
    case authenticationFailed(stage: String)
    case notConnected
    case connectionTimeout

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .dnsResolutionFailed(host):
            "DNS resolution failed for \(host)"
        case .socketCreationFailed:
            "Failed to create UDP socket"
        case .socketBindFailed:
            "Failed to bind UDP socket"
        case let .authenticationFailed(stage):
            "Auth failed: \(stage)"
        case .notConnected:
            "Not connected to radio"
        case .connectionTimeout:
            "Connection timed out"
        }
    }
}

// MARK: - UDPChannel

/// POSIX UDP socket wrapper for Icom RS-BA1 protocol communication.
/// Uses raw Darwin sockets with a thread-based receive loop.
final class UDPChannel: @unchecked Sendable {
    // MARK: Lifecycle

    init(host: String, port: UInt16) {
        remoteHost = host
        remotePort = port

        let (strm, cont) = AsyncStream<Data>.makeStream()
        stream = strm
        streamContinuation = cont
    }

    // MARK: Internal

    private(set) var localPort: UInt16 = 0

    var inbound: AsyncStream<Data> {
        stream
    }

    /// Start the channel: resolve hostname, create socket, bind, start receive loop.
    func start() throws {
        guard let hostent = gethostbyname(remoteHost) else {
            throw IcomWiFiError.dnsResolutionFailed(remoteHost)
        }
        guard let addrPtr = hostent.pointee.h_addr_list[0] else {
            throw IcomWiFiError.dnsResolutionFailed(remoteHost)
        }
        var inAddr = in_addr()
        memcpy(&inAddr, addrPtr, Int(hostent.pointee.h_length))
        resolvedAddr = inAddr

        fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw IcomWiFiError.socketCreationFailed
        }

        try bindSocket()

        // 100ms receive timeout for poll loop
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        running = true
        receiveThread = Thread { [weak self] in
            self?.receiveLoop()
        }
        receiveThread?.qualityOfService = .userInitiated
        receiveThread?.start()
    }

    /// Stop the channel: close socket, finish stream.
    func stop() {
        running = false
        lock.withLock {
            if let cont = waitingContinuation {
                waitingContinuation = nil
                cont.resume(returning: nil)
            }
        }
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        streamContinuation.finish()
    }

    /// Send a UDP packet to the remote host.
    func send(_ data: Data) {
        guard fd >= 0 else {
            return
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = remotePort.bigEndian
        addr.sin_addr = resolvedAddr

        data.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress else {
                return
            }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    _ = sendto(fd, ptr, data.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    /// One-shot receive with timeout for handshake sequences.
    /// Uses a continuation resumed by the receive thread for minimal latency,
    /// matching the diag tool's poll()-based responsiveness.
    func receive(timeout: TimeInterval) async -> Data? {
        // Fast path: check buffer immediately
        let immediate: Data? = lock.withLock {
            if let data = buffer.first {
                buffer.removeFirst()
                return data
            }
            return nil
        }
        if let immediate {
            return immediate
        }

        guard timeout > 0 else {
            return nil
        }

        // Slow path: park until the receive thread delivers data or timeout
        return await withUnsafeContinuation { continuation in
            let alreadyResumed: Bool = self.lock.withLock {
                if let data = self.buffer.first {
                    self.buffer.removeFirst()
                    continuation.resume(returning: data)
                    return true
                }
                self.waitingContinuation = continuation
                return false
            }

            if !alreadyResumed {
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + timeout
                ) { [weak self] in
                    guard let self else {
                        return
                    }
                    lock.withLock {
                        if let cont = self.waitingContinuation {
                            self.waitingContinuation = nil
                            cont.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }

    /// Switch from buffered mode to streaming mode, flushing any buffered packets.
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
    private var waitingContinuation: UnsafeContinuation<Data?, Never>?
    private let stream: AsyncStream<Data>
    private let streamContinuation: AsyncStream<Data>.Continuation

    /// Bind to matching remote port (RS-BA1 convention), falling back to random.
    /// Records the assigned local port for session ID derivation.
    private func bindSocket() throws {
        var localAddr = sockaddr_in()
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_addr.s_addr = INADDR_ANY

        // kappanhang: bind local port = remote port for RS-BA1 compatibility.
        // The IC-705 routes CI-V data only to connections from matching ports.
        localAddr.sin_port = remotePort.bigEndian
        var bindResult = withUnsafePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            localAddr.sin_port = 0
            bindResult = withUnsafePointer(to: &localAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            fd = -1
            throw IcomWiFiError.socketBindFailed
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &addrLen)
            }
        }
        localPort = UInt16(bigEndian: boundAddr.sin_port)
    }

    private func receiveLoop() {
        var recvBuf = [UInt8](repeating: 0, count: 8_192)
        while running {
            let bytesRead = recv(fd, &recvBuf, recvBuf.count, 0)
            if bytesRead > 0 {
                let data = Data(recvBuf[..<bytesRead])
                lock.withLock {
                    if streaming {
                        streamContinuation.yield(data)
                    } else if let cont = waitingContinuation {
                        waitingContinuation = nil
                        cont.resume(returning: data)
                    } else {
                        buffer.append(data)
                    }
                }
                continue
            }

            // bytesRead == 0 is a zero-length UDP datagram — rare but valid.
            if bytesRead == 0 {
                continue
            }

            // bytesRead < 0
            let err = errno
            if err == EAGAIN || err == EWOULDBLOCK || err == EINTR {
                // Timeout (SO_RCVTIMEO already paced us 100ms) or
                // signal interrupt — loop immediately.
                continue
            }
            if !running {
                break
            }
            // Persistent error (e.g. ECONNREFUSED from ICMP port-unreachable
            // when the radio isn't on the network, EBADF mid-close, etc.).
            // recv returned without blocking, so sleep briefly to avoid a
            // 100% CPU spin until either the channel is stopped or the
            // keepalive timeout tears the transport down.
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}
