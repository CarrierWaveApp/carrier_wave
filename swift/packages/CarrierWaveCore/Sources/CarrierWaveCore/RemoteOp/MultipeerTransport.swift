#if canImport(MultipeerConnectivity)

    import Foundation
    import MultipeerConnectivity

    // MARK: - RemoteOp Multipeer constants

    public extension RemoteOp {
        /// MultipeerConnectivity service type used for the off-LAN transport
        /// (Bluetooth + AWDL peer Wi-Fi). Must be ≤ 15 chars, `[a-z0-9-]`.
        /// Also registered in `NSBonjourServices` for both apps so iOS allows
        /// the local-network access MPC requires under the hood.
        static let multipeerServiceType = "cw-remote"

        /// Key used inside MPC `discoveryInfo` so Field can render a human
        /// name for each advertising Sweep.
        static let multipeerDisplayNameKey = "sweep"
    }

    // MARK: - MultipeerTransport

//
    // Wraps one `MCSession` carrying traffic to a single remote peer as a
    // `RemoteOpTransport`. MPC already gives us message boundaries, so each
    // `session(_:didReceive:fromPeer:)` payload is one complete JSON frame —
    // no newline framing required. Sends use `.reliable` (TCP-equivalent
    // ordering and delivery).
//
    // The owning app code (Sweep listener / Field browser) is responsible for
    // constructing the session, accepting/invitating the peer, and handing
    // the session to this transport once the peer is connected.

    public final class MultipeerTransport: NSObject, RemoteOpTransport, MCSessionDelegate, @unchecked Sendable {
        // MARK: Lifecycle

        public init(session: MCSession, peer: MCPeerID) {
            self.session = session
            self.peer = peer
            super.init()
            session.delegate = self
        }

        // MARK: Public

        public func start() async {
            lock.lock()
            defer { lock.unlock() }
            guard !started else {
                return
            }
            started = true
            if incomingContinuation == nil {
                let (stream, continuation) = AsyncStream<Data>.makeStream()
                incomingStream = stream
                incomingContinuation = continuation
            }
        }

        public func send(_ frame: Data) async throws {
            do {
                try session.send(frame, toPeers: [peer], with: .reliable)
            } catch {
                throw RemoteOpTransportError.sendFailed(error.localizedDescription)
            }
        }

        public func incoming() async -> AsyncStream<Data> {
            lock.lock()
            defer { lock.unlock() }
            if let incomingStream {
                return incomingStream
            }
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            incomingStream = stream
            incomingContinuation = continuation
            return stream
        }

        public func cancel() async {
            lock.lock()
            let continuation = incomingContinuation
            incomingContinuation = nil
            cancelled = true
            lock.unlock()
            session.disconnect()
            continuation?.finish()
        }

        // MARK: - MCSessionDelegate

        public func session(_: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
            guard peer == self.peer else {
                return
            }
            if state == .notConnected {
                lock.lock()
                let continuation = incomingContinuation
                incomingContinuation = nil
                lock.unlock()
                continuation?.finish()
            }
        }

        public func session(_: MCSession, didReceive data: Data, fromPeer peer: MCPeerID) {
            guard peer == self.peer else {
                return
            }
            lock.lock()
            let continuation = incomingContinuation
            lock.unlock()
            continuation?.yield(data)
        }

        public func session(_: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID) {
            // Streams unused — protocol is message-oriented.
        }

        public func session(
            _: MCSession,
            didStartReceivingResourceWithName _: String,
            fromPeer _: MCPeerID,
            with _: Progress
        ) {
            // Resources unused.
        }

        public func session(
            _: MCSession,
            didFinishReceivingResourceWithName _: String,
            fromPeer _: MCPeerID,
            at _: URL?,
            withError _: Error?
        ) {
            // Resources unused.
        }

        // MARK: Private

        private let session: MCSession
        private let peer: MCPeerID
        private let lock = NSLock()

        private var started = false
        private var cancelled = false
        private var incomingStream: AsyncStream<Data>?
        private var incomingContinuation: AsyncStream<Data>.Continuation?
    }

#endif
