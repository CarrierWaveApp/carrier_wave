import Foundation

// MARK: - BKGLog

/// The BKG log type: 2 m CW contacts (direct or through a linear V/U
/// satellite) that exchange 6-character grids on the key. The rules, grid
/// checks, exchange mapping and ADIF export live in the Rust core
/// (`cw_domain::bkg`, surfaced as `bkgRules()` / `bkgBuildQso(input:)` /
/// `BkgApi`); this holds only the program slug hosts match sessions on.
public enum BKGLog {
    /// Slug stored in `LoggingSession.programs`. Matches `bkgRules().programSlug`.
    public static let programSlug = "bkg"
    /// On-screen name of the log type. Matches `bkgRules().displayName`.
    public static let displayName = "BKG Turf Wars"
}
