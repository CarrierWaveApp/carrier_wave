//! ADIF 3.1.7 field validation. Port of `ADIFFieldValidator.swift` (uses
//! `adif_catalog` for band/mode/submode lookups). Each per-field check returns
//! `Option<Violation>` so the caller can compose a list. `validate_for_upload`
//! is the composite the QSO upload pipeline calls.

use crate::adif_catalog::{band_for_code, mode_for_code, parent_mode_for_submode};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdifField {
    Call,
    Band,
    Mode,
    Submode,
    Freq,
    Date,
    Time,
    Grid,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Violation {
    pub field: AdifField,
    pub value: String,
    pub reason: String,
}

pub fn validate_callsign(call: &str) -> Option<Violation> {
    if call.trim().is_empty() {
        return Some(Violation {
            field: AdifField::Call,
            value: call.to_string(),
            reason: "Callsign is empty".to_string(),
        });
    }
    None
}

pub fn validate_band(band: &str) -> Option<Violation> {
    if band_for_code(band).is_none() {
        return Some(Violation {
            field: AdifField::Band,
            value: band.to_string(),
            reason: format!("'{}' is not a recognized ADIF band", band),
        });
    }
    None
}

pub fn validate_mode(mode: &str) -> Option<Violation> {
    if mode_for_code(mode).is_none() {
        return Some(Violation {
            field: AdifField::Mode,
            value: mode.to_string(),
            reason: format!("'{}' is not a recognized ADIF mode", mode),
        });
    }
    None
}

pub fn validate_submode(submode: &str, parent_mode: &str) -> Option<Violation> {
    let upper = submode.trim().to_uppercase();
    if upper.is_empty() {
        return None;
    }
    let Some(expected_parent) = parent_mode_for_submode(&upper) else {
        return Some(Violation {
            field: AdifField::Submode,
            value: submode.to_string(),
            reason: format!("'{}' is not a recognized ADIF submode", submode),
        });
    };
    let parent_upper = parent_mode.trim().to_uppercase();
    if expected_parent != parent_upper {
        return Some(Violation {
            field: AdifField::Submode,
            value: submode.to_string(),
            reason: format!(
                "Submode '{}' requires parent '{}', not '{}'",
                submode, expected_parent, parent_mode
            ),
        });
    }
    None
}

pub fn validate_band_freq_consistency(band: &str, freq_mhz: f64) -> Option<Violation> {
    let band_def = band_for_code(band)?;
    if freq_mhz < band_def.min_mhz || freq_mhz > band_def.max_mhz {
        return Some(Violation {
            field: AdifField::Freq,
            value: format!("{:.6}", freq_mhz),
            reason: format!(
                "{} MHz is outside {} range ({}–{} MHz)",
                freq_mhz, band, band_def.min_mhz, band_def.max_mhz
            ),
        });
    }
    None
}

pub fn validate_date(date_str: &str) -> Option<Violation> {
    let trimmed = date_str.trim();
    if trimmed.len() != 8 || !trimmed.chars().all(|c| c.is_ascii_digit()) {
        return Some(Violation {
            field: AdifField::Date,
            value: date_str.to_string(),
            reason: "Date must be 8 digits (YYYYMMDD)".to_string(),
        });
    }
    validate_date_components(trimmed, date_str)
}

pub fn validate_time(time_str: &str) -> Option<Violation> {
    let trimmed = time_str.trim();
    let len = trimmed.len();
    if !(len == 4 || len == 6) || !trimmed.chars().all(|c| c.is_ascii_digit()) {
        return Some(Violation {
            field: AdifField::Time,
            value: time_str.to_string(),
            reason: "Time must be HHMM or HHMMSS".to_string(),
        });
    }
    validate_time_components(trimmed, time_str)
}

pub fn validate_grid_square(grid: &str) -> Option<Violation> {
    let trimmed = grid.trim();
    if trimmed.is_empty() {
        return None;
    }
    let len = trimmed.chars().count();
    if ![2usize, 4, 6, 8].contains(&len) {
        return Some(Violation {
            field: AdifField::Grid,
            value: grid.to_string(),
            reason: "Grid must be 2, 4, 6, or 8 characters".to_string(),
        });
    }
    validate_grid_characters(trimmed, grid)
}

/// Composite validator the upload pipeline calls. Each `Some(field)` arg is
/// only checked if non-empty (mirrors Swift's behavior).
#[allow(clippy::too_many_arguments)]
pub fn validate_for_upload(
    callsign: &str,
    band: &str,
    mode: &str,
    submode: Option<&str>,
    freq_mhz: Option<f64>,
    date_str: Option<&str>,
    time_str: Option<&str>,
    grid: Option<&str>,
) -> Vec<Violation> {
    let mut violations = Vec::new();
    if let Some(v) = validate_callsign(callsign) {
        violations.push(v);
    }
    if let Some(v) = validate_band(band) {
        violations.push(v);
    }
    if let Some(v) = validate_mode(mode) {
        violations.push(v);
    }
    if let Some(sub) = submode {
        if !sub.is_empty() {
            if let Some(v) = validate_submode(sub, mode) {
                violations.push(v);
            }
        }
    }
    if let Some(freq) = freq_mhz {
        if let Some(v) = validate_band_freq_consistency(band, freq) {
            violations.push(v);
        }
    }
    if let Some(date) = date_str {
        if !date.is_empty() {
            if let Some(v) = validate_date(date) {
                violations.push(v);
            }
        }
    }
    if let Some(time) = time_str {
        if !time.is_empty() {
            if let Some(v) = validate_time(time) {
                violations.push(v);
            }
        }
    }
    if let Some(g) = grid {
        if !g.is_empty() {
            if let Some(v) = validate_grid_square(g) {
                violations.push(v);
            }
        }
    }
    violations
}

// ---------- private helpers ----------

fn validate_date_components(trimmed: &str, original: &str) -> Option<Violation> {
    let year: i32 = trimmed[..4].parse().ok()?;
    let month: u32 = trimmed[4..6].parse().ok()?;
    let day: u32 = trimmed[6..8].parse().ok()?;

    if year < 1930 {
        return Some(Violation {
            field: AdifField::Date,
            value: original.to_string(),
            reason: "Year must be >= 1930".to_string(),
        });
    }
    if !(1..=12).contains(&month) {
        return Some(Violation {
            field: AdifField::Date,
            value: original.to_string(),
            reason: format!("Month {} is out of range (1-12)", month),
        });
    }
    let days = days_in_month(month, year);
    if !(1..=days).contains(&day) {
        return Some(Violation {
            field: AdifField::Date,
            value: original.to_string(),
            reason: format!("Day {} is invalid for month {}", day, month),
        });
    }
    None
}

fn days_in_month(month: u32, year: i32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            let is_leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
            if is_leap { 29 } else { 28 }
        }
        _ => 0,
    }
}

fn validate_time_components(trimmed: &str, original: &str) -> Option<Violation> {
    let hour: u32 = trimmed[..2].parse().ok()?;
    let minute: u32 = trimmed[2..4].parse().ok()?;
    if hour > 23 {
        return Some(Violation {
            field: AdifField::Time,
            value: original.to_string(),
            reason: format!("Hour {} is out of range (0-23)", hour),
        });
    }
    if minute > 59 {
        return Some(Violation {
            field: AdifField::Time,
            value: original.to_string(),
            reason: format!("Minute {} is out of range (0-59)", minute),
        });
    }
    if trimmed.len() == 6 {
        let sec: u32 = trimmed[4..6].parse().ok()?;
        if sec > 59 {
            return Some(Violation {
                field: AdifField::Time,
                value: original.to_string(),
                reason: "Second is out of range (0-59)".to_string(),
            });
        }
    }
    None
}

fn validate_grid_characters(trimmed: &str, original: &str) -> Option<Violation> {
    let upper: Vec<char> = trimmed.to_uppercase().chars().collect();
    // Positions 1-2: field A-R
    for ch in upper.iter().take(2.min(upper.len())) {
        if !('A'..='R').contains(ch) {
            return Some(Violation {
                field: AdifField::Grid,
                value: original.to_string(),
                reason: format!("Field character '{}' must be A-R", ch),
            });
        }
    }
    // Positions 3-4: square 0-9
    if upper.len() >= 4 {
        for ch in &upper[2..4] {
            if !ch.is_ascii_digit() {
                return Some(Violation {
                    field: AdifField::Grid,
                    value: original.to_string(),
                    reason: format!("Square digit '{}' must be 0-9", ch),
                });
            }
        }
    }
    // Positions 5-6: subsquare A-X
    if upper.len() >= 6 {
        for ch in &upper[4..6] {
            if !('A'..='X').contains(ch) {
                return Some(Violation {
                    field: AdifField::Grid,
                    value: original.to_string(),
                    reason: format!("Subsquare character '{}' must be A-X", ch),
                });
            }
        }
    }
    // Positions 7-8: extended digit 0-9
    if upper.len() >= 8 {
        for ch in &upper[6..8] {
            if !ch.is_ascii_digit() {
                return Some(Violation {
                    field: AdifField::Grid,
                    value: original.to_string(),
                    reason: format!("Extended digit '{}' must be 0-9", ch),
                });
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn callsign_must_not_be_empty() {
        assert!(validate_callsign("W1AW").is_none());
        assert!(validate_callsign("").is_some());
        assert!(validate_callsign("   ").is_some());
    }

    #[test]
    fn band_must_be_recognized() {
        assert!(validate_band("20m").is_none());
        assert!(validate_band("20M").is_none()); // case-insensitive
        assert!(validate_band("nope").is_some());
    }

    #[test]
    fn mode_must_be_recognized() {
        assert!(validate_mode("FT8").is_none());
        assert!(validate_mode("ft8").is_none());
        assert!(validate_mode("BOGUS").is_some());
    }

    #[test]
    fn submode_must_match_parent() {
        assert!(validate_submode("USB", "SSB").is_none());
        assert!(validate_submode("USB", "FT8").is_some()); // wrong parent
        assert!(validate_submode("BOGUS", "SSB").is_some()); // unrecognized submode
        assert!(validate_submode("", "SSB").is_none()); // empty submode is OK
    }

    #[test]
    fn freq_must_match_band() {
        assert!(validate_band_freq_consistency("20m", 14.074).is_none());
        assert!(validate_band_freq_consistency("20m", 14.400).is_some()); // above
        assert!(validate_band_freq_consistency("20m", 13.9).is_some());   // below
    }

    #[test]
    fn date_must_be_yyyymmdd() {
        assert!(validate_date("20260613").is_none());
        assert!(validate_date("19290101").is_some()); // year < 1930
        assert!(validate_date("20261301").is_some()); // invalid month
        assert!(validate_date("20260230").is_some()); // invalid feb day
        assert!(validate_date("ABCDEFGH").is_some());
        // Leap year
        assert!(validate_date("20240229").is_none());
        assert!(validate_date("20230229").is_some());
    }

    #[test]
    fn time_must_be_hhmm_or_hhmmss() {
        assert!(validate_time("1230").is_none());
        assert!(validate_time("123059").is_none());
        assert!(validate_time("2459").is_some()); // hour 24
        assert!(validate_time("2360").is_some()); // minute 60
        assert!(validate_time("235960").is_some()); // sec 60
        assert!(validate_time("12345").is_some()); // wrong length
    }

    #[test]
    fn grid_must_be_2_4_6_or_8_chars() {
        assert!(validate_grid_square("FN").is_none());
        assert!(validate_grid_square("FN31").is_none());
        assert!(validate_grid_square("FN31pr").is_none());
        assert!(validate_grid_square("FN31pr12").is_none());
        assert!(validate_grid_square("FN3").is_some()); // wrong length
        assert!(validate_grid_square("ZZ31").is_some()); // field char > R
        assert!(validate_grid_square("FN31zz").is_some()); // subsquare char > X
    }

    #[test]
    fn composite_collects_all_violations() {
        let violations = validate_for_upload(
            "", // empty callsign
            "20m",
            "FT8",
            Some("USB"), // wrong submode for FT8
            Some(14.074),
            Some("20260613"),
            Some("1230"),
            None,
        );
        // Should fire: callsign + submode wrong parent.
        assert_eq!(violations.len(), 2);
        let fields: Vec<AdifField> = violations.iter().map(|v| v.field).collect();
        assert!(fields.contains(&AdifField::Call));
        assert!(fields.contains(&AdifField::Submode));
    }

    #[test]
    fn composite_clean_qso_has_no_violations() {
        let violations = validate_for_upload(
            "W1AW",
            "20m",
            "SSB",
            Some("USB"),
            Some(14.250),
            Some("20260613"),
            Some("1230"),
            Some("FN31pr"),
        );
        assert!(violations.is_empty());
    }
}
