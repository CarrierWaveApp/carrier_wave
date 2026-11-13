import CarrierWaveCore
import Foundation

// MARK: - ContestCallsign

/// Callsign normalization used for dupe-keying and condition matching, plus
/// CQ WPX prefix extraction. Facade over `cw_domain::contest::callsign`.
public enum ContestCallsign {
    /// Normalize: uppercase and strip trailing portable suffixes
    /// (`/QRP`, `/M`, `/P`, `/MM`, `/AM`, …).
    public static func normalize(_ callsign: String) -> String {
        contestNormalizeCallsign(callsign: callsign)
    }

    /// CQ WPX contest prefix derived from a callsign
    /// (`K4XL` → `K4`, `KH6/N8BJQ` → `KH6`, `N8BJQ/9` → `N9`, `RAEM` → `RA0`).
    public static func wpxPrefix(_ callsign: String) -> String {
        contestWpxPrefix(callsign: callsign)
    }
}
