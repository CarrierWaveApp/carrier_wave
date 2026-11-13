//! Mode family classification & equivalence. Port of `ModeEquivalence.swift`.

use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum ModeFamily {
    Phone,
    Cw,
    Digital,
    Other,
}

pub struct ModeEquivalence;

impl ModeEquivalence {
    pub const GENERIC_MODES: [&'static str; 2] = ["PHONE", "DATA"];
    pub const PHONE_MODES: [&'static str; 7] = ["PHONE", "SSB", "USB", "LSB", "AM", "FM", "DV"];
    pub const DIGITAL_MODES: [&'static str; 11] = [
        "DATA", "FT8", "FT4", "PSK31", "PSK", "RTTY", "JT65", "JT9", "MFSK", "OLIVIA", "JTTY",
    ];
    pub const CW_MODES: [&'static str; 1] = ["CW"];

    fn is_phone(upper: &str) -> bool {
        Self::PHONE_MODES.contains(&upper)
    }
    fn is_digital(upper: &str) -> bool {
        Self::DIGITAL_MODES.contains(&upper)
    }
    fn is_cw(upper: &str) -> bool {
        Self::CW_MODES.contains(&upper)
    }

    pub fn family(mode: &str) -> ModeFamily {
        let upper = mode.to_uppercase();
        if Self::is_phone(&upper) {
            ModeFamily::Phone
        } else if Self::is_digital(&upper) {
            ModeFamily::Digital
        } else if Self::is_cw(&upper) {
            ModeFamily::Cw
        } else {
            ModeFamily::Other
        }
    }

    pub fn are_equivalent(mode1: &str, mode2: &str) -> bool {
        let m1 = mode1.to_uppercase();
        let m2 = mode2.to_uppercase();
        if m1 == m2 {
            return true;
        }
        if Self::is_phone(&m1) && Self::is_phone(&m2) {
            return true;
        }
        if Self::is_digital(&m1) && Self::is_digital(&m2) {
            return true;
        }
        false
    }

    /// Returns the more specific of two equivalent modes (prefers the non-generic).
    pub fn more_specific(mode1: &str, mode2: &str) -> String {
        let m1 = mode1.to_uppercase();
        let m2 = mode2.to_uppercase();
        let m1_generic = Self::GENERIC_MODES.contains(&m1.as_str());
        let m2_generic = Self::GENERIC_MODES.contains(&m2.as_str());
        if m1_generic && !m2_generic {
            return mode2.to_string();
        }
        if m2_generic && !m1_generic {
            return mode1.to_string();
        }
        mode1.to_string()
    }

    pub fn is_generic(mode: &str) -> bool {
        Self::GENERIC_MODES.contains(&mode.to_uppercase().as_str())
    }

    pub fn canonical_name(mode: &str) -> String {
        if mode.to_uppercase() == "PHONE" {
            "SSB".to_string()
        } else {
            mode.to_string()
        }
    }

    pub fn canonical_name_for_dedup(mode: &str) -> String {
        let upper = mode.to_uppercase();
        if Self::is_phone(&upper) {
            "SSB".to_string()
        } else {
            upper
        }
    }

    /// ADIF parent mode + optional submode.
    pub fn adif_mode_submode(mode: &str) -> (String, Option<String>) {
        let upper = mode.to_uppercase();
        match upper.as_str() {
            "USB" | "LSB" => ("SSB".to_string(), Some(upper)),
            "FT4" => ("MFSK".to_string(), Some("FT4".to_string())),
            "PSK31" => ("PSK".to_string(), Some("PSK31".to_string())),
            _ => (upper, None),
        }
    }

    pub fn normalize_for_strict_adif(mode: &str) -> (String, Option<String>) {
        match mode.to_uppercase().as_str() {
            "PHONE" => ("SSB".to_string(), None),
            "DATA" => ("RTTY".to_string(), None),
            _ => Self::adif_mode_submode(mode),
        }
    }

    /// Dedup modes by family, preferring specific over generic. Within a family
    /// the representative is chosen; `other`-family modes are kept distinct.
    /// Output: family representatives sorted, then other modes sorted (mirrors
    /// Swift `familySeen.values.sorted() + otherModes.sorted()`).
    pub fn deduplicated_modes(modes: &[String]) -> Vec<String> {
        // BTreeMap keyed by family gives a deterministic order; Swift's
        // Dictionary order is undefined but the final `.sorted()` makes the
        // observable output deterministic regardless.
        let mut family_seen: BTreeMap<ModeFamily, String> = BTreeMap::new();
        let mut other_modes: Vec<String> = Vec::new();

        for mode in modes {
            let fam = Self::family(mode);
            if fam == ModeFamily::Other {
                let up = mode.to_uppercase();
                if !other_modes.contains(&up) {
                    other_modes.push(up);
                }
            } else if let Some(existing) = family_seen.get(&fam) {
                let merged = Self::more_specific(existing, mode);
                family_seen.insert(fam, merged);
            } else {
                family_seen.insert(fam, Self::canonical_name(mode));
            }
        }

        let mut reps: Vec<String> = family_seen.into_values().collect();
        reps.sort();
        other_modes.sort();
        reps.into_iter().chain(other_modes).collect()
    }
}

/// The PoLo activation metadata pseudo-modes. Port of `QSOMode.metadataModes`
/// (CAR-278): every "Their Call" command Ham2K PoLo stores as a QSO-shaped row —
/// WEATHER/SOLAR (conditions), NOTE/TODO (annotations), START (timer marker),
/// BREAK (rove line break). These are NOT real QSOs — never uploaded, synced,
/// or counted in stats.
pub const METADATA_MODES: [&str; 6] = ["WEATHER", "SOLAR", "NOTE", "TODO", "START", "BREAK"];

/// Whether `mode` is a PoLo metadata pseudo-mode (case-insensitive). Port of
/// `QSOMode.isMetadata(_:)` — the single source of truth shared by Swift and
/// Kotlin. A NULL/empty mode is a real QSO, so this returns `false` for it.
pub fn is_metadata_mode(mode: &str) -> bool {
    let upper = mode.to_uppercase();
    METADATA_MODES.contains(&upper.as_str())
}

/// Modes that use a 3-digit RST (readability/strength/tone) rather than the
/// 2-digit RS phone report. Port of the iOS `LoggerView.isCWMode` list — kept as
/// an explicit set (not the `ModeFamily` classification) because iOS treats
/// unrecognised `Other`-family modes like SSTV as 2-digit, and includes the
/// generic `DATA`/`DIGITAL` labels here.
pub const THREE_DIGIT_RST_MODES: [&str; 11] =
    ["CW", "RTTY", "PSK", "PSK31", "FT8", "FT4", "JT65", "JT9", "JTTY", "DATA", "DIGITAL"];

/// The default RST report string for `mode` — `"599"` for 3-digit (CW/digital)
/// modes, `"59"` for 2-digit (phone) modes. Port of `LoggerView.defaultRST`
/// (`isCWMode ? "599" : "59"`). Used for both the sent and received defaults
/// when the operator leaves an RST field blank. An empty/unknown mode falls to
/// the phone default, matching the Swift `?? "CW"`-then-list-miss path is *not*
/// how it behaves: iOS defaults `currentMode` to `"CW"` when there is no session
/// mode, so a blank mode here maps to `"599"` to stay faithful.
pub fn default_rst(mode: &str) -> String {
    let effective = if mode.trim().is_empty() { "CW" } else { mode };
    let upper = effective.to_uppercase();
    if THREE_DIGIT_RST_MODES.contains(&upper.as_str()) {
        "599".to_string()
    } else {
        "59".to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_rst_by_mode() {
        // 3-digit CW/digital modes -> "599" (case-insensitive).
        assert_eq!(default_rst("CW"), "599");
        assert_eq!(default_rst("cw"), "599");
        assert_eq!(default_rst("FT8"), "599");
        assert_eq!(default_rst("rtty"), "599");
        assert_eq!(default_rst("DIGITAL"), "599");
        // 2-digit phone modes -> "59".
        assert_eq!(default_rst("SSB"), "59");
        assert_eq!(default_rst("USB"), "59");
        assert_eq!(default_rst("FM"), "59");
        // Unrecognised Other-family modes fall to the phone default (iOS parity).
        assert_eq!(default_rst("SSTV"), "59");
        // Blank/unknown mode maps to CW's "599" (iOS `currentMode ?? "CW"`).
        assert_eq!(default_rst(""), "599");
        assert_eq!(default_rst("   "), "599");
    }

    #[test]
    fn metadata_modes_are_case_insensitive() {
        assert!(is_metadata_mode("WEATHER"));
        assert!(is_metadata_mode("weather"));
        assert!(is_metadata_mode("Solar"));
        assert!(is_metadata_mode("note"));
        assert!(is_metadata_mode("TODO"));
        assert!(is_metadata_mode("start"));
        assert!(is_metadata_mode("Break"));
        assert!(!is_metadata_mode("CW"));
        assert!(!is_metadata_mode("FT8"));
        assert!(!is_metadata_mode(""));
    }

    #[test]
    fn families() {
        assert_eq!(ModeEquivalence::family("usb"), ModeFamily::Phone);
        assert_eq!(ModeEquivalence::family("FT8"), ModeFamily::Digital);
        assert_eq!(ModeEquivalence::family("cw"), ModeFamily::Cw);
        assert_eq!(ModeEquivalence::family("SSTV"), ModeFamily::Other);
    }

    #[test]
    fn equivalence() {
        assert!(ModeEquivalence::are_equivalent("USB", "LSB"));
        assert!(ModeEquivalence::are_equivalent("FT8", "FT4"));
        assert!(!ModeEquivalence::are_equivalent("CW", "FT8"));
        assert!(ModeEquivalence::are_equivalent("cw", "CW"));
    }

    #[test]
    fn specificity_and_dedup() {
        assert_eq!(ModeEquivalence::more_specific("PHONE", "SSB"), "SSB");
        assert_eq!(ModeEquivalence::more_specific("SSB", "PHONE"), "SSB");
        let out = ModeEquivalence::deduplicated_modes(&[
            "PHONE".into(),
            "SSB".into(),
            "CW".into(),
        ]);
        assert_eq!(out, vec!["CW".to_string(), "SSB".to_string()]);
    }

    #[test]
    fn adif_split() {
        assert_eq!(
            ModeEquivalence::adif_mode_submode("USB"),
            ("SSB".to_string(), Some("USB".to_string()))
        );
        assert_eq!(
            ModeEquivalence::normalize_for_strict_adif("DATA"),
            ("RTTY".to_string(), None)
        );
    }
}
