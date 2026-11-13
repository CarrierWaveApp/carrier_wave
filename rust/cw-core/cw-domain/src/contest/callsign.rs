//! Callsign normalization + CQ WPX prefix extraction. Port of
//! `Services/Contest/ContestCallsign.swift`.

/// Portable suffixes that are stripped from the callsign before using it
/// as part of a dupe key.
pub const PORTABLE_SUFFIXES: [&str; 7] = ["P", "M", "MM", "AM", "QRP", "QRPP", "PM"];

/// Normalize: uppercase and strip trailing portable suffixes.
pub fn normalize(callsign: &str) -> String {
    let upper = callsign.to_uppercase();
    if !upper.contains('/') {
        return upper;
    }

    let parts: Vec<&str> = upper.split('/').filter(|part| !part.is_empty()).collect();
    if parts.len() < 2 {
        return upper;
    }

    // If the last part looks like a portable suffix, drop it.
    if let Some(last) = parts.last() {
        if PORTABLE_SUFFIXES.contains(last) {
            return parts[..parts.len() - 1].join("/");
        }
    }
    upper
}

/// CQ WPX contest prefix derived from a callsign:
/// - Simple call: letters/numerals up to and including the last digit
///   (`K4XL` → `K4`, `VE3XYZ` → `VE3`, `4U1UN` → `4U1`, `OE25XYZ` → `OE25`).
/// - No digit anywhere: a zero after the first two letters (`RAEM` → `RA0`).
/// - Portable host designator (letters): that designator forms the prefix
///   (`KH6/N8BJQ` → `KH6`, `PA/N8BJQ` → `PA0`, `VP2E/K4XL` → `VP2`).
/// - Single-number portable: home-call letters + that digit
///   (`N8BJQ/9` → `N9`, `WB8XYZ/4` → `WB4`).
///
/// The bare-number portable case can only be resolved exactly with a
/// country file (the official rule maps it to the operating country's
/// prefix). We approximate with the home call's leading letters, which
/// still yields a valid and distinct prefix for multiplier purposes.
pub fn wpx_prefix(callsign: &str) -> String {
    let normalized = normalize(callsign);
    match normalized.find('/') {
        None => prefix_from_designator(&normalized),
        Some(slash) => {
            let left = &normalized[..slash];
            let right = &normalized[slash + 1..];
            wpx_prefix_portable(left, right)
        }
    }
}

fn wpx_prefix_portable(left: &str, right: &str) -> String {
    if is_all_digits(left) {
        return format!("{}{left}", alpha_lead(right));
    }
    if is_all_digits(right) {
        return format!("{}{right}", alpha_lead(left));
    }
    // Both sides are alphanumeric designators/calls. The shorter side is
    // the operating prefix; ties go to the leading side (the host
    // designator by signing convention, e.g. `KH6/N8BJQ`).
    let designator = if left.chars().count() <= right.chars().count() { left } else { right };
    prefix_from_designator(designator)
}

/// Prefix from a designator that is not a bare number: letters/numerals up
/// to and including the last digit, or — when there is no digit — a zero
/// after the first two letters.
fn prefix_from_designator(designator: &str) -> String {
    if let Some((idx, ch)) = designator.char_indices().rfind(|(_, ch)| ch.is_numeric()) {
        return designator[..idx + ch.len_utf8()].to_string();
    }
    let lead: String = designator.chars().take(2).collect();
    format!("{lead}0")
}

/// Leading letters of a callsign (the part before the first digit).
fn alpha_lead(call: &str) -> String {
    let lead: String = call.chars().take_while(|ch| ch.is_alphabetic()).collect();
    if lead.is_empty() { call.to_string() } else { lead }
}

fn is_all_digits(value: &str) -> bool {
    !value.is_empty() && value.chars().all(|ch| ch.is_numeric())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_strips_portable_suffixes() {
        assert_eq!(normalize("k4xl"), "K4XL");
        assert_eq!(normalize("K4XL/QRP"), "K4XL");
        assert_eq!(normalize("G3XYZ/P"), "G3XYZ");
        assert_eq!(normalize("KH6/N8BJQ"), "KH6/N8BJQ");
        assert_eq!(normalize("W1ABC/7"), "W1ABC/7");
    }

    #[test]
    fn wpx_prefix_extraction() {
        // Mirror of `wpxPrefixExtraction`.
        assert_eq!(wpx_prefix("K4XL"), "K4");
        assert_eq!(wpx_prefix("ve3xyz"), "VE3");
        assert_eq!(wpx_prefix("4U1UN"), "4U1");
        assert_eq!(wpx_prefix("OE25XYZ"), "OE25");
        assert_eq!(wpx_prefix("RAEM"), "RA0");
        assert_eq!(wpx_prefix("K4XL/QRP"), "K4");
        assert_eq!(wpx_prefix("G3XYZ/P"), "G3");
        assert_eq!(wpx_prefix("KH6/N8BJQ"), "KH6");
        assert_eq!(wpx_prefix("PA/N8BJQ"), "PA0");
        assert_eq!(wpx_prefix("VP2E/K4XL"), "VP2");
        assert_eq!(wpx_prefix("W1/K4XL"), "W1");
        assert_eq!(wpx_prefix("N8BJQ/9"), "N9");
        assert_eq!(wpx_prefix("WB8XYZ/4"), "WB4");
    }
}
