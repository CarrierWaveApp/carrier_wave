import Foundation

// MARK: - WhatsNewCatalog

/// Bundled, per-version release notes shown in-app on first launch after an
/// update. Add a new entry at the top of `entries` for each shipped version.
/// Keep entries terse — full notes belong on the App Store / website devlog.
public enum WhatsNewCatalog {
    // MARK: Public

    /// Release notes ordered newest-first. iOS entries use the `Carrier Wave: Field`
    /// version (e.g. `"1.83.0"`); CW Sweep entries use `"0.x.y"`. Platform-mixed
    /// entries (`[.iOS, .macOS]`) describe shared work that landed in matching
    /// builds of both apps.
    public static let entries: [WhatsNewEntry] =
        recentEntries + archivedEntries + archivedOlderEntries + archivedOldestEntries + archivedSweepEntries

    /// Entries the running app hasn't shown yet, filtered to the current
    /// platform and ordered newest-first. Pass `nil` for `lastSeenVersion`
    /// to suppress notes on a fresh install — first-launch users haven't
    /// "missed" anything.
    public static func unseenEntries(
        currentVersion: String,
        lastSeenVersion: String?,
        platform: WhatsNewPlatform,
        catalog: [WhatsNewEntry] = WhatsNewCatalog.entries
    ) -> [WhatsNewEntry] {
        guard let lastSeenVersion else {
            return []
        }
        let current = WhatsNewVersion(currentVersion)
        let lastSeen = WhatsNewVersion(lastSeenVersion)
        guard current > lastSeen else {
            return []
        }
        return catalog.filter { entry in
            let entryVersion = WhatsNewVersion(entry.version)
            return entry.platforms.contains(platform)
                && entryVersion > lastSeen
                && entryVersion <= current
        }
    }

    // MARK: Private

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
