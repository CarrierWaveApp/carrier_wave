import CarrierWaveData
import Foundation

// MARK: - AchievementSignalID

/// Stable IDs for ecosystem-usage signals the client can emit. Must match
/// the server's `award_method = 'signal'` rows in the `achievements` table.
public enum AchievementSignalID: String, CaseIterable, Sendable {
    case sweepUser = "sweep-user"
    case watchOperator = "watch-operator"
    case homeScreen = "home-screen"
    case pebblePioneer = "pebble-pioneer"
    case swl
    case rbnSpotter = "rbn-spotter"
}

// MARK: - AchievementSignalService

/// Fire-and-forget service that posts ecosystem-usage signals to the
/// activities server. Idempotent on the client: each signal ID is only
/// reported once per device install (tracked via UserDefaults). Failures
/// are swallowed — never blocks any user surface.
@MainActor
final class AchievementSignalService {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Internal

    static let shared = AchievementSignalService()

    /// Report a signal. Returns immediately; the network call runs in the
    /// background. Re-reporting a previously-sent signal is a no-op.
    func reportSignal(_ id: AchievementSignalID) {
        guard !alreadyReported(id) else {
            return
        }
        Task.detached(priority: .background) { [weak self] in
            await self?.send(id)
        }
    }

    /// Reset the local "already reported" cache. Useful after callsign
    /// change — signals belong to the new callsign.
    func resetReportedCache() {
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let storageKey = "AchievementSignals.reportedIDs.v1"

    private func alreadyReported(_ id: AchievementSignalID) -> Bool {
        let reported = defaults.array(forKey: storageKey) as? [String] ?? []
        return reported.contains(id.rawValue)
    }

    private func markReported(_ id: AchievementSignalID) {
        var reported = defaults.array(forKey: storageKey) as? [String] ?? []
        guard !reported.contains(id.rawValue) else {
            return
        }
        reported.append(id.rawValue)
        defaults.set(reported, forKey: storageKey)
    }

    private func send(_ id: AchievementSignalID) async {
        let client = ActivitiesClient()
        guard let token = await client.ensureAuthToken() else {
            return
        }
        do {
            try await client.reportAchievementSignal(
                id: id.rawValue,
                authToken: token,
                sourceURL: ActivitiesClient.resolvedBaseURL
            )
            markReported(id)
        } catch {
            // Best-effort — leave un-marked so we'll retry next launch.
        }
    }
}
