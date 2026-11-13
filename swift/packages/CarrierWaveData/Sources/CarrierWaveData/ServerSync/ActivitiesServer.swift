import Foundation

// MARK: - ActivitiesServer

/// Where the activities / sync server lives. One resolver for every client
/// (iOS `ActivitiesClient`, the shared `SyncAccountClient`, CW Sweep's catalog
/// fetchers) so a developer override applies everywhere at once.
public enum ActivitiesServer {
    public static let defaultURL = "https://activities.carrierwave.app"

    /// `UserDefaults` key for the developer override (Settings → Developer).
    public static let overrideDefaultsKey = "activitiesServerURLOverride"

    /// Resolved base URL, respecting the developer override if set. Safe from
    /// any actor (plain `UserDefaults` read).
    public static var resolvedBaseURL: String {
        let override = UserDefaults.standard.string(forKey: overrideDefaultsKey) ?? ""
        return override.isEmpty ? defaultURL : override
    }

    /// Strip trailing slashes so concatenation with `/v1/...` never yields `//`.
    public static func normalizeBase(_ base: String) -> String {
        var result = base
        while result.hasSuffix("/") {
            result = String(result.dropLast())
        }
        return result
    }
}
