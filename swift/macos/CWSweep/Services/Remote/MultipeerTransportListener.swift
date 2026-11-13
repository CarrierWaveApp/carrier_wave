import CarrierWaveCore
import Foundation
import MultipeerConnectivity
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RemoteOp.MPC")

// MARK: - MultipeerTransportListener

//
// Advertises Sweep over MultipeerConnectivity (Bluetooth + AWDL peer Wi-Fi)
// so Field can reach us with no shared LAN. Auto-accepts MPC invitations —
// auth still runs in-protocol via the existing `hello` → `pair`(6-digit
// code) → token flow over the wrapping `MultipeerTransport`.
//
// One advertiser; one `MCSession` per accepted invitation. The session is
// handed off to `MultipeerTransport`, then to `RemoteOpService.acceptTransport(_:)`,
// at which point this listener no longer touches it.

@MainActor
final class MultipeerTransportListener: NSObject {
    // MARK: Lifecycle

    init(service: RemoteOpService) {
        self.service = service
        let displayName = Host.current().localizedName ?? "CW Sweep"
        peerID = MCPeerID(displayName: String(displayName.prefix(63)))
        super.init()
    }

    // MARK: Internal

    /// Starts advertising. Idempotent — calling again is a no-op.
    func start() {
        guard advertiser == nil else {
            return
        }
        let displayName = Host.current().localizedName ?? "CW Sweep"
        let info = [RemoteOp.multipeerDisplayNameKey: displayName]
        let newAdvertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: info,
            serviceType: RemoteOp.multipeerServiceType
        )
        newAdvertiser.delegate = self
        newAdvertiser.startAdvertisingPeer()
        advertiser = newAdvertiser
        let peerName = peerID.displayName
        logger.info("MPC advertiser started as \(peerName, privacy: .public)")
    }

    /// Stops advertising and tears down any sessions still owned by this
    /// listener (sessions handed off to RemoteOpConnection are not touched —
    /// they live on under the connection actor until it cancels).
    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        logger.info("MPC advertiser stopped")
    }

    // MARK: Private

    private weak var service: RemoteOpService?
    private let peerID: MCPeerID
    private var advertiser: MCNearbyServiceAdvertiser?
}

// MARK: MCNearbyServiceAdvertiserDelegate

extension MultipeerTransportListener: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext _: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Build a session bound to the inviting peer, accept the invitation,
        // and hand the session off to a transport. Auth happens in-protocol
        // over the transport — anyone may open a connection, but they can't
        // do anything without producing the 6-digit code or a known token.
        // MCPeerID + the system-provided handler are non-Sendable but
        // effectively constant for the lifetime of this delegate call, so
        // we capture them through nonisolated(unsafe) lets before hopping.
        nonisolated(unsafe) let capturedPeer = peerID
        nonisolated(unsafe) let capturedHandler = invitationHandler
        Task { @MainActor in
            guard let service = self.service else {
                capturedHandler(false, nil)
                return
            }
            let session = MCSession(
                peer: self.peerID,
                securityIdentity: nil,
                encryptionPreference: .required
            )
            let transport = MultipeerTransport(session: session, peer: capturedPeer)
            capturedHandler(true, session)
            service.acceptTransport(transport)
            logger.info("MPC accepted invitation from \(capturedPeer.displayName, privacy: .public)")
        }
    }

    nonisolated func advertiser(
        _: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        logger.error("MPC advertise failed: \(error.localizedDescription, privacy: .public)")
    }
}
