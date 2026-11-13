import Foundation

// MARK: - WhatsNewService

/// Decides whether a "What's New" sheet should appear on launch and records
/// the user's acknowledgement. Backed by `UserDefaults` so iOS and macOS each
/// track their own last-seen version (App Store releases ship independently).
@MainActor
@Observable
public final class WhatsNewService {
    // MARK: Lifecycle

    public init(
        platform: WhatsNewPlatform,
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        catalog: [WhatsNewEntry] = WhatsNewCatalog.entries
    ) {
        self.platform = platform
        self.bundle = bundle
        self.defaults = defaults
        self.catalog = catalog
    }

    // MARK: Public

    /// Entries the user hasn't seen for the currently-installed version.
    /// Empty on first install (we suppress notes for users with no history)
    /// and after the user dismisses the sheet.
    public var pendingEntries: [WhatsNewEntry] {
        WhatsNewCatalog.unseenEntries(
            currentVersion: currentVersion,
            lastSeenVersion: lastSeenVersion,
            platform: platform,
            catalog: catalog
        )
    }

    public var hasPendingEntries: Bool {
        !pendingEntries.isEmpty
    }

    /// Mark the current version as seen. Called when the user dismisses the
    /// sheet so re-launches don't re-present the same notes.
    public func markCurrentVersionSeen() {
        defaults.set(currentVersion, forKey: Self.lastSeenKey(for: platform))
    }

    /// Seed `lastSeenVersion` to the current version without showing notes.
    /// Call once on a fresh install so the very next update triggers the
    /// sheet but the first-ever launch does not.
    public func markFreshInstallIfNeeded() {
        guard defaults.string(forKey: Self.lastSeenKey(for: platform)) == nil else {
            return
        }
        defaults.set(currentVersion, forKey: Self.lastSeenKey(for: platform))
    }

    // MARK: Internal

    var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var lastSeenVersion: String? {
        defaults.string(forKey: Self.lastSeenKey(for: platform))
    }

    static func lastSeenKey(for platform: WhatsNewPlatform) -> String {
        "whatsNew.lastSeenVersion.\(platform.rawValue)"
    }

    // MARK: Private

    private let platform: WhatsNewPlatform
    private let bundle: Bundle
    private let defaults: UserDefaults
    private let catalog: [WhatsNewEntry]
}
