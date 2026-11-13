import CarrierWaveCore
import MultipeerConnectivity
import UIKit

// MARK: - MultipeerSweepBrowser

//
// MultipeerConnectivity browser for nearby Sweeps when there's no shared
// LAN (BT + AWDL peer Wi-Fi). Surfaces discovered peers as Identifiable
// values the pairing UI binds to. Invitation produces a connected
// `MCSession` wrapped in a `MultipeerTransport`, which the caller hands
// to `RemoteSweepClient`.

@MainActor
@Observable
final class MultipeerSweepBrowser {
    // MARK: Lifecycle

    init() {
        peerID = MCPeerID(displayName: String(UIDevice.current.name.prefix(63)))
    }

    // MARK: Internal

    struct DiscoveredSweep: Identifiable, Hashable {
        let id: UUID
        let displayName: String
        let peerID: MCPeerID

        static func == (lhs: DiscoveredSweep, rhs: DiscoveredSweep) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private(set) var discovered: [DiscoveredSweep] = []
    private(set) var isBrowsing = false
    private(set) var lastError: String?

    /// Begin scanning. Idempotent.
    func start() {
        guard browser == nil else {
            return
        }
        let newBrowser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: RemoteOp.multipeerServiceType
        )
        let bridge = BrowserDelegateBridge(owner: self)
        delegateBridge = bridge
        newBrowser.delegate = bridge
        newBrowser.startBrowsingForPeers()
        browser = newBrowser
        isBrowsing = true
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        delegateBridge = nil
        isBrowsing = false
        discovered.removeAll()
    }

    /// Invite a discovered sweep, wait for the session to reach `.connected`,
    /// and hand back a ready `RemoteOpTransport`. Throws on timeout/decline.
    func connect(to sweep: DiscoveredSweep, timeout: TimeInterval = 15) async throws -> RemoteOpTransport {
        guard let browser else {
            throw BrowserError.notBrowsing
        }
        let session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        let waiter = SessionConnectWaiter(targetPeer: sweep.peerID, session: session)
        session.delegate = waiter
        browser.invitePeer(sweep.peerID, to: session, withContext: nil, timeout: timeout)
        try await waiter.wait(timeout: timeout)
        // Hand session ownership to the transport — it re-installs itself as
        // the delegate, so the waiter no longer receives events.
        return MultipeerTransport(session: session, peer: sweep.peerID)
    }

    /// Add or replace a discovered peer. Called by the delegate bridge.
    func didFind(peer: MCPeerID, info: [String: String]?) {
        let displayName = info?[RemoteOp.multipeerDisplayNameKey] ?? peer.displayName
        var next = discovered.filter { $0.peerID != peer }
        next.append(DiscoveredSweep(id: UUID(), displayName: displayName, peerID: peer))
        discovered = next.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func didLose(peer: MCPeerID) {
        discovered.removeAll { $0.peerID == peer }
    }

    func didFail(_ error: Error) {
        lastError = error.localizedDescription
        isBrowsing = false
    }

    // MARK: Private

    private enum BrowserError: Error, LocalizedError {
        case notBrowsing
        case inviteTimeout
        case sessionDeclined

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .notBrowsing: "Not browsing for nearby Sweeps"
            case .inviteTimeout: "Sweep did not respond to the invitation"
            case .sessionDeclined: "Sweep declined the invitation"
            }
        }
    }

    private let peerID: MCPeerID
    private var browser: MCNearbyServiceBrowser?
    private var delegateBridge: BrowserDelegateBridge?
}

// MARK: - BrowserDelegateBridge

private final class BrowserDelegateBridge: NSObject, MCNearbyServiceBrowserDelegate {
    // MARK: Lifecycle

    init(owner: MultipeerSweepBrowser) {
        self.owner = owner
    }

    // MARK: Internal

    weak var owner: MultipeerSweepBrowser?

    func browser(_: MCNearbyServiceBrowser, foundPeer peer: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            owner?.didFind(peer: peer, info: info)
        }
    }

    func browser(_: MCNearbyServiceBrowser, lostPeer peer: MCPeerID) {
        Task { @MainActor in
            owner?.didLose(peer: peer)
        }
    }

    func browser(_: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            owner?.didFail(error)
        }
    }
}

// MARK: - SessionConnectWaiter

private final class SessionConnectWaiter: NSObject, MCSessionDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init(targetPeer: MCPeerID, session: MCSession) {
        self.targetPeer = targetPeer
        self.session = session
    }

    // MARK: Internal

    func wait(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.resolve(throwing: BrowserError.inviteTimeout)
            }
        }
    }

    func session(_: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
        guard peer == targetPeer else {
            return
        }
        switch state {
        case .connected:
            resolve(throwing: nil)
        case .notConnected:
            resolve(throwing: BrowserError.sessionDeclined)
        default:
            break
        }
    }

    func session(_: MCSession, didReceive _: Data, fromPeer _: MCPeerID) {}
    func session(_: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID) {}
    func session(_: MCSession, didStartReceivingResourceWithName _: String, fromPeer _: MCPeerID, with _: Progress) {}
    func session(
        _: MCSession,
        didFinishReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        at _: URL?,
        withError _: Error?
    ) {}

    // MARK: Private

    private enum BrowserError: Error, LocalizedError {
        case inviteTimeout
        case sessionDeclined

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .inviteTimeout: "Sweep did not respond to the invitation"
            case .sessionDeclined: "Sweep declined the invitation"
            }
        }
    }

    private let targetPeer: MCPeerID
    private let session: MCSession
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    private func resolve(throwing error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
