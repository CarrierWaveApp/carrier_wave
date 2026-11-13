import CarrierWaveCore
import Network
import UIKit

// MARK: - RemoteSweepCoordinator + Multipeer

//
// Off-LAN connect path. The MultipeerConnectivity browser produces a
// connected `MCSession` once Sweep accepts the invitation; this extension
// wraps that into the same `RemoteSweepClient` plumbing the LAN path uses.

extension RemoteSweepCoordinator {
    /// Begin a connection to a Sweep advertised over MultipeerConnectivity.
    /// Reuses any token previously cached for the same display name.
    func connectMultipeer(
        to sweep: MultipeerSweepBrowser.DiscoveredSweep,
        via browser: MultipeerSweepBrowser
    ) async {
        await establish(serverName: sweep.displayName) {
            try await browser.connect(to: sweep)
        }
    }

    /// Shared connect/handshake pipeline. The closure produces the transport
    /// after whatever async setup the underlying channel requires (DNS for
    /// LAN, MPC invite + handshake for nearby).
    func establish(
        serverName: String,
        makeTransport: () async throws -> RemoteOpTransport
    ) async {
        await disconnect()
        preferredSweepName = serverName
        let token = RemoteSweepKeychain.loadToken(for: serverName)
        let coordinator = self
        let deviceName = await Self.deviceName()
        do {
            let transport = try await makeTransport()
            let client = RemoteSweepClient(
                transport: transport,
                deviceName: deviceName,
                existingToken: token
            ) { event in
                Task { @MainActor in
                    coordinator.handle(event: event, sweepName: serverName)
                }
            }
            self.client = client
            currentSweepName = serverName
            connectionState = .connecting
            lastError = nil
            await client.connect()
        } catch {
            connectionState = .error("Connection failed: \(error.localizedDescription)")
        }
    }
}
