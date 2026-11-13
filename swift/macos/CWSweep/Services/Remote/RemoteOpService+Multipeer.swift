import CarrierWaveCore
import Foundation
import Network

// MARK: - RemoteOpService + Multipeer

//
// MultipeerConnectivity hook-up and transport-acceptance plumbing split off
// `RemoteOpService` to keep the main type under SwiftLint's body-length
// limit. The advertiser lives alongside the TCP listener and routes
// accepted MPC peers into the same `acceptTransport` pipeline as
// LAN-accepted `NWConnection`s.

extension RemoteOpService {
    /// Persisted preference for whether MPC advertising runs alongside the
    /// TCP listener. Defaults to enabled — letting Field connect off-LAN is
    /// the point of the feature.
    var multipeerEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.multipeerEnabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.multipeerEnabledKey)
            if listener != nil {
                if newValue {
                    startMultipeerListener()
                } else {
                    stopMultipeerListener()
                }
            }
        }
    }

    static var multipeerEnabledKey: String {
        "RemoteOp.multipeerEnabled"
    }

    /// Wraps a LAN socket in a transport and feeds it into `acceptTransport`.
    func acceptConnection(_ raw: NWConnection) {
        let transport = NWConnectionTransport(connection: raw, queue: networkQueue)
        acceptTransport(transport)
    }

    /// Bridges any transport (LAN TCP, MPC) into the per-client connection
    /// actor. The transport must be unstarted — `RemoteOpConnection.start()`
    /// drives it.
    func acceptTransport(_ transport: RemoteOpTransport) {
        let id = UUID()
        let connection = RemoteOpConnection(
            id: id,
            transport: transport,
            service: self
        )
        connections[id] = connection
        Task {
            await connection.start()
        }
    }

    func startMultipeerListener() {
        guard multipeerListener == nil else {
            return
        }
        let newListener = MultipeerTransportListener(service: self)
        newListener.start()
        multipeerListener = newListener
    }

    func stopMultipeerListener() {
        multipeerListener?.stop()
        multipeerListener = nil
    }
}
