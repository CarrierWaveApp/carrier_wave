import UIKit

// MARK: - NeedsPreferences

/// Centralized reads for Smart Spot tracking toggles with locale-aware
/// defaults. The `@AppStorage` defaults in `NeedsSettingsView` can only
/// be compile-time constants, so we layer on top: if the user has never
/// toggled the switch, we derive an appropriate default from their home
/// country. Once the user makes a choice, the stored value wins.
///
/// Today only `trackWAS` has a locale-specific default (USA-only), but
/// the same pattern will apply to JCC/VUCC/etc. when those ship.
enum NeedsPreferences {
    // MARK: Internal

    /// Whether "Worked All States" tracking should be active. Defaults
    /// to the user's explicit setting, else true for USA operators, else
    /// false. Non-US users therefore don't see WAS nags on first launch.
    static var trackWAS: Bool {
        read("needsTrackWAS", default: UserRegionProfile.isUSAOperator ?? false)
    }

    /// Whether DXCC tracking is on — always defaults to true; relevant
    /// to every DXCC-licensed operator.
    static var trackDXCC: Bool {
        read("needsTrackDXCC", default: true)
    }

    /// Whether POTA hunter-park tracking is on.
    static var trackPOTAHunter: Bool {
        read("needsTrackPOTAHunter", default: true)
    }

    /// Whether WWFF hunter-reference tracking is on.
    static var trackWWFFHunter: Bool {
        read("needsTrackWWFFHunter", default: true)
    }

    // MARK: Private

    private static func read(_ key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return defaultValue
    }
}
