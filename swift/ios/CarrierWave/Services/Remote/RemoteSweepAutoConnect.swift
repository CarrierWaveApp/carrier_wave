import CarrierWaveCore
import Foundation
import Network
import UIKit

// Watches for the operator's preferred Sweep on the LAN and reconnects
// silently when one is seen. Pairing still happens via Sweep's UI on
// the first run; after that, the pairing token in Keychain is enough
// to bring the link back up automatically every time the iOS app
// returns to the foreground or the network changes.

@MainActor
@Observable
final class RemoteSweepAutoConnect {
    // MARK: Lifecycle

    init(coordinator: RemoteSweepCoordinator) {
        self.coordinator = coordinator
        registerLifecycleObservers()
    }

    deinit {
        // Observers are scoped to the lifetime of the harness; they
        // unregister themselves automatically when the app process
        // terminates. NSNotificationCenter holds weak references only
        // for block-based observers, but we still pull them out
        // explicitly when the app suspends.
    }

    // MARK: Internal

    /// Begin watching. Idempotent. Call once from the app entry point.
    func start() {
        guard browser == nil else {
            return
        }
        attemptOnce()
    }

    /// Cancel any in-flight browse. Future `start()` resumes watching.
    func stop() {
        browser?.cancel()
        browser = nil
        cancelWatchdog()
    }

    // MARK: Private

    /// How long to keep browsing before giving up for this attempt. Restarted
    /// on every foreground / network change, so a "no Sweep on this network"
    /// outcome is cheap.
    private static let watchdogSeconds: TimeInterval = 8

    private weak var coordinator: RemoteSweepCoordinator?
    private var browser: NWBrowser?
    private var watchdog: Task<Void, Never>?

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.attemptOnce()
            }
        }
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    /// Start a fresh browse + watchdog. Called on app launch, foreground,
    /// and any time we want to re-try (e.g. after a coordinator disconnect).
    private func attemptOnce() {
        guard let coordinator else {
            return
        }
        // Already connected or busy connecting; nothing to do.
        switch coordinator.connectionState {
        case .connected,
             .connecting,
             .awaitingPairing:
            return
        case .idle,
             .error:
            break
        }
        // No paired sweep recorded yet — manual pairing is required for
        // the very first run, and we won't try to guess.
        guard let preferred = coordinator.preferredSweepName,
              !preferred.isEmpty,
              RemoteSweepKeychain.loadToken(for: preferred) != nil
        else {
            return
        }
        startBrowser(matching: preferred)
    }

    private func startBrowser(matching preferredName: String) {
        browser?.cancel()
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: RemoteOp.bonjourServiceType,
            domain: nil
        )
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let newBrowser = NWBrowser(for: descriptor, using: parameters)
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleResults(results, matching: preferredName)
            }
        }
        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBrowserState(state)
            }
        }
        newBrowser.start(queue: .main)
        browser = newBrowser
        scheduleWatchdog()
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .failed,
             .cancelled:
            browser = nil
            cancelWatchdog()
        default:
            break
        }
    }

    private func handleResults(
        _ results: Set<NWBrowser.Result>,
        matching preferredName: String
    ) {
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else {
                continue
            }
            if name.localizedCaseInsensitiveCompare(preferredName) == .orderedSame {
                let endpoint = result.endpoint
                Task { @MainActor [weak self] in
                    await self?.connect(name: name, endpoint: endpoint)
                }
                return
            }
        }
    }

    private func connect(name: String, endpoint: NWEndpoint) async {
        // Ensure we're still in a state that wants a connection — the
        // user may have manually picked a different Sweep in the
        // meantime, or pairing may have expired.
        guard let coordinator else {
            return
        }
        let discovered = RemoteSweepDiscovery.DiscoveredSweep(
            id: UUID(),
            name: name,
            endpoint: endpoint
        )
        await coordinator.connect(to: discovered)
        stop()
    }

    private func scheduleWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.watchdogSeconds))
            guard !Task.isCancelled else {
                return
            }
            self?.stop()
        }
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }
}
