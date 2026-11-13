//! Satellite display identity: the short OSCAR designator operators say
//! ("SO-50") first, long mission name as a de-emphasized detail. Port of
//! `SatelliteDisplayName` (`SatelliteDisplayName.swift`). Sources in order:
//! 1. AMSAT status name (`SO-50_[FM]`) — authoritative designator.
//! 2. Parenthesized designator inside the catalog name ("SAUDISAT 1C (SO-50)").
//! 3. "OSCAR n" catalog names → AO-n.

use regex::Regex;
use std::sync::OnceLock;

/// `short` renders prominently; `long` (when present) is the mission name.
pub fn split(name: &str, amsat_name: Option<&str>) -> (String, Option<String>) {
    let trimmed = name.trim();
    if let Some(amsat_name) = amsat_name {
        let base = amsat_name.split("_[").next().unwrap_or("").trim();
        if !base.is_empty() {
            let same = base.eq_ignore_ascii_case(trimmed);
            return (
                base.to_string(),
                if same { None } else { Some(trimmed.to_string()) },
            );
        }
    }
    if let Some(captures) = designator_regex().captures(trimmed) {
        let designator = captures.get(1).map(|m| m.as_str().to_uppercase()).unwrap_or_default();
        let full = captures.get(0).map(|m| m.range()).unwrap_or(0..0);
        let mut long = String::new();
        long.push_str(&trimmed[..full.start]);
        long.push_str(&trimmed[full.end..]);
        let cleaned = long.replace("  ", " ").trim().to_string();
        return (
            designator,
            if cleaned.is_empty() { None } else { Some(cleaned) },
        );
    }
    if let Some(captures) = oscar_regex().captures(trimmed) {
        // Swift uses wholeMatch — the whole name must be "OSCAR n".
        if captures.get(0).map(|m| m.as_str().len()) == Some(trimmed.len()) {
            let number = captures.get(1).map(|m| m.as_str()).unwrap_or("");
            return (format!("AO-{number}"), Some(trimmed.to_string()));
        }
    }
    (trimmed.to_string(), None)
}

/// Strip the TLE `"0 "` line-zero marker some catalogs prefix names with.
/// Port of `SatNOGSTLE.displayName`.
pub fn from_tle0(tle0: &str) -> String {
    let trimmed = tle0.trim();
    trimmed.strip_prefix("0 ").unwrap_or(trimmed).trim().to_string()
}

/// Best base name for the catalog before [`split`] runs: the SatNOGS
/// satellite-catalog name beats the TLE line-zero name (which is often a
/// launch placeholder like "OBJECT C"), and an OSCAR-style designator among
/// the catalog aliases ("FO-29" for the satellite named "JAS-2") is appended
/// in parentheses so [`split`]'s designator extraction promotes it.
pub fn catalog_base_name(
    satnogs_name: Option<&str>,
    satnogs_aliases: Option<&str>,
    tle_name: &str,
) -> String {
    let base = satnogs_name
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .unwrap_or(tle_name.trim());
    let designator = satnogs_aliases
        .unwrap_or("")
        .split(|c: char| c.is_whitespace() || c == ',')
        .find(|token| alias_designator_regex().is_match(token));
    match designator {
        Some(designator)
            if !base.to_uppercase().contains(&designator.to_uppercase()) =>
        {
            format!("{base} ({designator})")
        }
        _ => base.to_string(),
    }
}

fn alias_designator_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^[A-Za-z]{1,3}-\d{1,3}$").expect("static regex"))
}

fn designator_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"\(([A-Za-z]{1,3}-\d{1,3})\)").expect("static regex"))
}

fn oscar_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(?i)^OSCAR[ -](\d{1,3})$").expect("static regex"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn amsat_base_name_wins() {
        let (short, long) = split("SAUDISAT 1C (SO-50)", Some("SO-50_[FM]"));
        assert_eq!(short, "SO-50");
        assert_eq!(long.as_deref(), Some("SAUDISAT 1C (SO-50)"));
        // Same name → no detail line.
        let (short, long) = split("SO-50", Some("SO-50_[FM]"));
        assert_eq!(short, "SO-50");
        assert_eq!(long, None);
    }

    #[test]
    fn parenthesized_designator_extracted() {
        let (short, long) = split("SAUDISAT 1C (SO-50)", None);
        assert_eq!(short, "SO-50");
        assert_eq!(long.as_deref(), Some("SAUDISAT 1C"));
        let (short, long) = split("FOX-1B (AO-91)", None);
        assert_eq!(short, "AO-91");
        assert_eq!(long.as_deref(), Some("FOX-1B"));
    }

    #[test]
    fn oscar_number_maps_to_ao() {
        let (short, long) = split("OSCAR 7", None);
        assert_eq!(short, "AO-7");
        assert_eq!(long.as_deref(), Some("OSCAR 7"));
        // Not a whole-name match → passthrough.
        let (short, long) = split("OSCAR 7 DEB", None);
        assert_eq!(short, "OSCAR 7 DEB");
        assert_eq!(long, None);
    }

    #[test]
    fn catalog_base_name_prefers_satnogs_and_promotes_alias_designators() {
        // OBJECT placeholder replaced by the catalog name; its parenthesized
        // designator then splits normally.
        assert_eq!(
            catalog_base_name(Some("CAS-6 (TO-108)"), Some("2019-093C"), "OBJECT C"),
            "CAS-6 (TO-108)"
        );
        let (short, long) = split("CAS-6 (TO-108)", None);
        assert_eq!(short, "TO-108");
        assert_eq!(long.as_deref(), Some("CAS-6"));
        // Alias designator appended so split() promotes it.
        assert_eq!(catalog_base_name(Some("JAS-2"), Some("FO-29"), "JAS 2"), "JAS-2 (FO-29)");
        let (short, long) = split("JAS-2 (FO-29)", None);
        assert_eq!(short, "FO-29");
        assert_eq!(long.as_deref(), Some("JAS-2"));
        // Alias already inside the name → no duplicate parens.
        assert_eq!(
            catalog_base_name(Some("FOX-1B (AO-91)"), Some("AO-91"), "FOX-1B"),
            "FOX-1B (AO-91)"
        );
        // Non-designator aliases (launch ids) are ignored.
        assert_eq!(catalog_base_name(Some("CroCube"), Some("2024-247A"), "X"), "CroCube");
        // No catalog row → TLE name unchanged.
        assert_eq!(catalog_base_name(None, None, "ISS (ZARYA)"), "ISS (ZARYA)");
        // Empty catalog name falls back to the TLE name.
        assert_eq!(catalog_base_name(Some("  "), None, "ISS (ZARYA)"), "ISS (ZARYA)");
    }

    #[test]
    fn passthrough_and_tle0_marker() {
        let (short, long) = split("ISS (ZARYA)", None);
        // "(ZARYA)" doesn't match the designator shape (no digits-dash).
        assert_eq!(short, "ISS (ZARYA)");
        assert_eq!(long, None);
        assert_eq!(from_tle0("0 ISS (ZARYA)"), "ISS (ZARYA)");
        assert_eq!(from_tle0("ISS (ZARYA)"), "ISS (ZARYA)");
    }
}
