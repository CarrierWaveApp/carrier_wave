import CarrierWaveData
import Observation
import SwiftData
import UIKit

/// Hosts the long-lived `MacrosRegistryService` actor and the most recent
/// `MacrosRegistrySnapshot` for SwiftUI views to observe. The actor is
/// created lazily on `configure(container:)` so the App struct can wire
/// it once at startup. The snapshot is published back to the main actor
/// after every successful poll.
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
            authTokenProvider: { [weak self] in
                await self?.activitiesAuthToken()
            }
        )
        self.client = client
        service = MacrosRegistryService(client: client, container: container)
    }

    /// Convenience for scenePhase = .active. Swallows network errors —
    /// the registry is non-critical and shouldn't surface red banners on
    /// every cold start in airplane mode.
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

    /// Force the next poll to run, ignoring the 30-minute debounce. The
    /// Updates tab + pull-to-refresh use this.
    func refreshNow() async {
        guard let service else {
            return
        }
        await service.invalidateDebounce()
        await pollIfStale()
    }

    // MARK: Private

    nonisolated private static var serverBaseURL: URL {
        URL(string: ActivitiesClient.resolvedBaseURL) ?? URL(string: ActivitiesClient.defaultURL)!
    }

    private var service: MacrosRegistryService?

    private func activitiesAuthToken() async -> String? {
        await ActivitiesClient().ensureAuthToken()
    }
}
