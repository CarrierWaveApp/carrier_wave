import CarrierWaveCore
import Network
import OSLog
import UIKit

// MARK: - RemoteSweepDiscovery

//
// Bonjour browser for CW Sweep remote servers on the LAN. Publishes a list of
// `DiscoveredSweep` values that the pairing UI binds to. Names are taken from
// each Sweep's NWService and become "<host> on <network>".

@MainActor
@Observable
final class RemoteSweepDiscovery {
    // MARK: Internal

    struct DiscoveredSweep: Identifiable, Hashable {
        let id: UUID
        let name: String
        let endpoint: NWEndpoint

        static func == (lhs: DiscoveredSweep, rhs: DiscoveredSweep) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private(set) var discovered: [DiscoveredSweep] = []
    private(set) var isBrowsing: Bool = false
    private(set) var lastError: String?
    /// Rolling on-screen diagnostics for the discovery flow (newest last).
    private(set) var debugLog: [String] = []

    func start() {
        guard browser == nil else {
            return
        }
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: RemoteOp.bonjourServiceType,
            domain: nil
        )
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleState(state)
            }
        }
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.applyResults(results)
            }
        }
        newBrowser.start(queue: .main)
        browser = newBrowser
        isBrowsing = true
        Self.logger.info("browse started for \(RemoteOp.bonjourServiceType, privacy: .public)")
        note("browse started: \(RemoteOp.bonjourServiceType)")
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discovered.removeAll()
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "com.jsvana.FullDuplex",
        category: "RemoteDiscovery"
    )

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var browser: NWBrowser?

    private func handleState(_ state: NWBrowser.State) {
        Self.logger.info("browser state: \(String(describing: state), privacy: .public)")
        note("state: \(String(describing: state))")
        switch state {
        case .ready:
            lastError = nil
        case let .failed(error):
            Self.logger.error("browser failed: \(String(describing: error), privacy: .public)")
            lastError = error.localizedDescription
            isBrowsing = false
        case let .waiting(error):
            // Permission-denied and interface trouble surface here, not in
            // .failed — without logging this the UI just looks empty.
            Self.logger.error("browser waiting: \(String(describing: error), privacy: .public)")
            lastError = "Waiting: \(error.localizedDescription)"
        case .cancelled:
            isBrowsing = false
        default:
            break
        }
    }

    private func applyResults(_ results: Set<NWBrowser.Result>) {
        var next: [DiscoveredSweep] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else {
                continue
            }
            next.append(DiscoveredSweep(
                id: UUID(),
                name: name,
                endpoint: result.endpoint
            ))
        }
        discovered = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let names = discovered.map(\.name).joined(separator: ", ")
        let usableCount = discovered.count
        Self.logger.info(
            "browse results: \(results.count) raw, \(usableCount) services: \(names, privacy: .public)"
        )
        note("results: \(results.count) raw / \(usableCount) usable [\(names)]")
    }

    private func note(_ message: String) {
        let stamp = Self.stampFormatter.string(from: Date())
        debugLog.append("\(stamp) \(message)")
        if debugLog.count > 50 {
            debugLog.removeFirst(debugLog.count - 50)
        }
    }
}
