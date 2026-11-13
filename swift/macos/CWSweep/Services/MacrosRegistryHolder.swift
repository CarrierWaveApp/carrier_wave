import AppKit
import CarrierWaveData
import Observation
import SwiftData

// MARK: - MacrosRegistryHolder

/// Hosts the long-lived `MacrosRegistryService` actor and the most recent
/// `MacrosRegistrySnapshot` for SwiftUI views to observe. The actor is
/// created lazily on `configure(container:)`. CW Sweep doesn't ship an
/// `ActivitiesClient` yet, so the auth token provider returns nil — the
/// list/get/versions/tombstones endpoints used by Browse + Updates are
/// public and don't require auth.
@MainActor
@Observable
final class MacrosRegistryHolder {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = MacrosRegistryHolder()

    /// Last snapshot from the actor. Views observe this directly.
    private(set) var snapshot: MacrosRegistrySnapshot = .empty

    /// Underlying client — exposed so install / browse / update views can
    /// hit the registry without each constructing their own.
    private(set) var client: MacrosRegistryClient?

    /// Wires the holder to the app's shared container. Idempotent — calling
    /// twice with the same container is a no-op.
    func configure(container: ModelContainer) {
        guard service == nil else {
            return
        }
        let client = MacrosRegistryClient(
            baseURLProvider: { Self.serverBaseURL },
            authTokenProvider: { nil }
        )
        self.client = client
        service = MacrosRegistryService(client: client, container: container)
    }

    /// Convenience for scenePhase = .active. Swallows network errors.
    func pollIfStale() async {
        guard let service else {
            return
        }
        do {
            snapshot = try await service.pollIfStale()
        } catch {
            // Non-fatal: registry sync is opportunistic.
        }
    }

    /// Force the next poll to run, ignoring the 30-minute debounce.
    func refreshNow() async {
        guard let service else {
            return
        }
        await service.invalidateDebounce()
        await pollIfStale()
    }

    // MARK: Private

    nonisolated private static var serverBaseURL: URL {
        let override = UserDefaults.standard.string(forKey: "activitiesServerURLOverride") ?? ""
        if !override.isEmpty, let url = URL(string: override) {
            return url
        }
        return URL(string: ContestDefinitions.defaultURL) ?? URL(string: "https://activities.carrierwave.app")!
    }

    private var service: MacrosRegistryService?
}
