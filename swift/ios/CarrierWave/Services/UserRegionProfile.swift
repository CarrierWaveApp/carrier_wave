import CarrierWaveCore
import UIKit

// MARK: - UserRegionProfile

/// Resolves the operator's home country / IARU region from their stored
/// callsign and (as a fallback) their grid square. Used to localize
/// defaults — band plan region, WAS tracking, dashboard ordering — so
/// the app stops assuming every user is in the USA.
///
/// Reads are cheap (UserDefaults + prefix lookup); callers can invoke on
/// the main thread without worrying about performance.
enum UserRegionProfile {
    // MARK: Internal

    /// Whether the operator's home DXCC is the United States (48 states,
    /// Alaska, Hawaii, territories). Returns nil when the callsign
    /// cannot be resolved — callers should fall back to the system
    /// locale or a neutral default.
    static var isUSAOperator: Bool? {
        guard let entity = homeEntity() else {
            return nil
        }
        let name = entity.name.lowercased()
        return name.contains("united states")
            || name == "alaska"
            || name == "hawaii"
    }

    /// IARU region, honoring (in order): explicit user override from
    /// onboarding/settings, callsign-derived guess, grid-derived guess.
    /// Returns nil when none of those are known.
    static var primaryIARURegion: IARURegion? {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "userIARURegionOverride") != nil {
            let raw = defaults.integer(forKey: "userIARURegionOverride")
            if let region = IARURegion(rawValue: raw) {
                return region
            }
        }
        let callsign = storedCallsign()
        if !callsign.isEmpty,
           let region = IARURegion.from(callsign: callsign)
        {
            return region
        }
        let grid = storedGrid()
        if !grid.isEmpty {
            return IARURegion.from(grid: grid)
        }
        return nil
    }

    /// Best-guess amateur license scheme for the stored callsign. Falls
    /// back to `.generic` (no US-privilege filtering) when the callsign
    /// cannot be resolved, which is safer than assuming FCC tiers.
    static var licenseScheme: AmateurLicenseScheme {
        AmateurLicenseScheme.inferred(fromEntityName: homeEntity()?.name)
    }

    /// The operator's home DXCC entity, resolved from their callsign.
    /// Returns nil when the callsign is empty or the prefix can't be matched.
    static func homeEntity() -> PrefixCountry? {
        let callsign = storedCallsign()
        guard !callsign.isEmpty else {
            return nil
        }
        return LocationPrefixLookup.entity(forCallsign: callsign)
    }

    // MARK: Private

    private static func storedCallsign() -> String {
        UserDefaults.standard.string(forKey: "loggerDefaultCallsign")?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func storedGrid() -> String {
        UserDefaults.standard.string(forKey: "loggerDefaultGrid")?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
