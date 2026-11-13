//! Session-wizard frequency scope logic. Port of
//! `FrequencyScope/FrequencyScopeModel.swift` (`FrequencyScopeLogic`).
//!
//! Builds the ruler rows and band-plan verdicts behind the interactive
//! frequency selector, on top of [`crate::band_plan`]. Frequencies are Hz so
//! the ruler can step at 100 Hz. Advisory phrasing keeps the wizard's markdown
//! bold (`**x**`) so the Swift side can render it; other hosts strip the marks.

use std::collections::HashMap;

use crate::band_plan::{self, LicenseClass, ViolationType};

// ---- Public model ---------------------------------------------------------

/// One on-air station rendered as a row. `tier`/`wpm` are opaque render hints
/// carried through from the host (the logic only uses `frequency_hz`/`callsign`).
#[derive(Debug, Clone)]
pub struct ScopeSpot {
    pub frequency_hz: i64,
    pub callsign: String,
    pub tier: i32,
    pub wpm: Option<i32>,
    pub age_seconds: i64,
}

/// Precomputed render data for one ruler row (frequency in Hz).
#[derive(Debug, Clone)]
pub struct ScopeRow {
    pub hz: i64,
    pub freq_text: String,
    pub spot: Option<ScopeSpot>,
    pub hatched: bool,
    pub seg_label: Option<String>,
    pub block_label: Option<String>,
    pub hole: Option<String>,
    pub pileup_count: i32,
    pub is_good: bool,
    pub advisory: String,
}

/// Advisory for a frequency — green when clear/appropriate, else orange.
#[derive(Debug, Clone)]
pub struct Verdict {
    pub is_good: bool,
    pub message: String,
}

// ---- Tables (scope-specific; the shared ones live in band_plan) ------------

const BAND_ORDER: &[&str] = &["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"];
const PHONE_MODES: &[&str] = &["SSB", "USB", "LSB", "PHONE", "AM", "FM"];

/// General-class SSB starting frequencies — inside the General phone segment.
const GENERAL_PHONE_START: &[(&str, f64)] = &[
    ("160m", 1.910), ("80m", 3.850), ("40m", 7.200), ("20m", 14.285),
    ("17m", 18.130), ("15m", 21.350), ("12m", 24.960), ("10m", 28.400), ("6m", 50.150),
];

/// General-class CW starting frequencies — just inside the General CW segment.
const GENERAL_CW_START: &[(&str, f64)] = &[
    ("160m", 1.820), ("80m", 3.550), ("40m", 7.035), ("30m", 10.120), ("20m", 14.035),
    ("17m", 18.075), ("15m", 21.035), ("12m", 24.900), ("10m", 28.050), ("6m", 50.090),
];

// ---- Public API -----------------------------------------------------------

/// Bands with a band plan, in scope order.
pub fn available_bands() -> Vec<String> {
    BAND_ORDER
        .iter()
        .filter(|b| band_plan::SEGMENTS.iter().any(|s| s.band == **b))
        .map(|b| b.to_string())
        .collect()
}

/// Full displayable Hz span of a band.
pub fn band_range_hz(band: &str) -> Option<(i64, i64)> {
    let segs: Vec<_> = band_plan::SEGMENTS.iter().filter(|s| s.band == band).collect();
    let lo = segs.iter().map(|s| (s.start_mhz * 1_000_000.0).round() as i64).min()?;
    let hi = segs.iter().map(|s| (s.end_mhz * 1_000_000.0).round() as i64).max()?;
    if lo < hi {
        Some((lo, hi))
    } else {
        None
    }
}

/// Where the scope starts for a band+mode: a reasonable General-class operating
/// frequency (FT8/FT4 use their watering holes), else band center.
pub fn default_hz(band: &str, mode: &str) -> Option<i64> {
    let table: &[(&str, f64)] = match normalize(mode).as_str() {
        "FT8" => band_plan::FT8_FREQUENCIES,
        "FT4" => band_plan::FT4_FREQUENCIES,
        "SSB" => GENERAL_PHONE_START,
        _ => GENERAL_CW_START,
    };
    if let Some(mhz) = lookup(table, band) {
        return Some((mhz * 1_000_000.0).round() as i64);
    }
    band_range_hz(band).map(|(lo, hi)| (lo + hi) / 2)
}

/// The watering-hole mode at this frequency ("FT8"/"FT4"), if any.
pub fn hole_mode(band: &str, hz: i64) -> Option<String> {
    let mhz = hz as f64 / 1_000_000.0;
    if let Some(ft8) = lookup(band_plan::FT8_FREQUENCIES, band) {
        if (mhz - ft8).abs() <= 0.0015 {
            return Some("FT8".to_string());
        }
    }
    if let Some(ft4) = lookup(band_plan::FT4_FREQUENCIES, band) {
        if (mhz - ft4).abs() <= 0.0015 {
            return Some("FT4".to_string());
        }
    }
    None
}

/// The verdict + advisory for one frequency (Hz).
pub fn evaluate(hz: i64, band: &str, mode: &str, license: LicenseClass, spots: &[ScopeSpot]) -> Verdict {
    verdict(hz, band, mode, license, spots, &facts(hz, mode, license))
}

/// Build every ruler row for a band at the current step (Hz). Band-plan facts
/// are computed once per row — never on the scroll path.
pub fn build_rows(band: &str, mode: &str, license: LicenseClass, step: i64, spots: &[ScopeSpot]) -> Vec<ScopeRow> {
    let Some((lo, hi)) = band_range_hz(band) else {
        return Vec::new();
    };
    let step = step.max(100);
    let label_mod = if step <= 100 { 1_000 } else { 5_000 };
    let clusters = cluster_spots(spots, lo, hi, step);

    let mut rows = Vec::new();
    let mut prev_hatched = false;
    let mut hz = lo;
    while hz <= hi {
        let facts = facts(hz, mode, license);
        let members = clusters.get(&hz);
        let lead = members.and_then(|m| pick_lead(m));
        let hatched = facts.hatched();
        let block = if hatched && !prev_hatched { block_label(hz, mode, &facts) } else { None };
        let freq_text = row_freq_text(hz, lead, &facts, label_mod, step);
        let verdict = verdict(hz, band, mode, license, spots, &facts);
        rows.push(ScopeRow {
            hz,
            freq_text,
            spot: lead.cloned(),
            hatched,
            seg_label: segment_start_label(hz),
            block_label: block,
            hole: facts.hole.clone(),
            pileup_count: members.map(|m| (m.len() as i32 - 1).max(0)).unwrap_or(0),
            is_good: verdict.is_good,
            advisory: verdict.message,
        });
        prev_hatched = hatched;
        hz += step;
    }
    rows
}

// ---- Internals ------------------------------------------------------------

/// Band-plan facts for a frequency, computed once and threaded through
/// hatch/label/verdict.
struct RowFacts {
    violation: Option<ViolationType>,
    cw_in_data: bool,
    hole: Option<String>,
}

impl RowFacts {
    fn hatched(&self) -> bool {
        if self.cw_in_data {
            return true;
        }
        matches!(self.violation, Some(v) if v != ViolationType::UnusualFrequency)
    }
}

fn facts(hz: i64, mode: &str, license: LicenseClass) -> RowFacts {
    let mhz = hz as f64 / 1_000_000.0;
    RowFacts {
        violation: band_plan::validate(mhz, mode, license),
        cw_in_data: is_cw_in_data_zone(hz, mode),
        hole: hole_mode_for_band(hz),
    }
}

fn hole_mode_for_band(hz: i64) -> Option<String> {
    let band = band_plan::segment_for(hz as f64 / 1_000_000.0)?.band;
    hole_mode(band, hz)
}

fn verdict(hz: i64, band: &str, mode: &str, license: LicenseClass, spots: &[ScopeSpot], facts: &RowFacts) -> Verdict {
    if let Some(violation) = facts.violation {
        if let Some(blocked) = blocking_verdict(hz, band, mode, license, violation) {
            return blocked;
        }
    }
    if facts.cw_in_data {
        return Verdict {
            is_good: false,
            message: "This is the **data** segment — CW belongs in the CW segment".to_string(),
        };
    }
    if let Some(soft) = soft_mismatch(hz, band, mode) {
        return soft;
    }
    if let Some(qrm) = qrm_verdict(hz, spots) {
        return qrm;
    }
    let des = designation(hz, band);
    if facts.hole.is_some() {
        return Verdict { is_good: true, message: format!("Clear · on the **{des}** frequency") };
    }
    Verdict {
        is_good: true,
        message: if des == "SSB" { "Clear · SSB segment" } else { "Clear · CW / data segment" }.to_string(),
    }
}

fn blocking_verdict(hz: i64, band: &str, mode: &str, license: LicenseClass, violation: ViolationType) -> Option<Verdict> {
    let mhz = hz as f64 / 1_000_000.0;
    match violation {
        ViolationType::OutOfBand => {
            Some(Verdict { is_good: false, message: "Outside the amateur bands".to_string() })
        }
        ViolationType::NoPrivileges => {
            let need = required_license(mhz, mode).display_name();
            Some(Verdict {
                is_good: false,
                message: format!("This is **{}**, and you're **{}**", need, license.display_name()),
            })
        }
        ViolationType::WrongMode => {
            let des = designation(hz, band);
            Some(Verdict {
                is_good: false,
                message: format!("This is **{des}** — {} not permitted here", display_mode(mode)),
            })
        }
        ViolationType::UnusualFrequency => None,
    }
}

/// QRM advisory: prefer the station on the exact centered frequency, else the
/// nearest within ±2 kHz.
fn qrm_verdict(hz: i64, spots: &[ScopeSpot]) -> Option<Verdict> {
    let nearby: Vec<&ScopeSpot> = spots.iter().filter(|s| (s.frequency_hz - hz).abs() <= 2_000).collect();
    let on_freq = nearby.iter().find(|s| s.frequency_hz == hz).copied();
    let qrm = on_freq.or_else(|| nearby.iter().min_by_key(|s| (s.frequency_hz - hz).abs()).copied())?;
    let delta = (qrm.frequency_hz - hz).abs();
    let position = if delta < 500 {
        "on frequency".to_string()
    } else {
        format!("{} kHz away", (delta as f64 / 1_000.0).round() as i64)
    };
    Some(Verdict { is_good: false, message: format!("QRM · **{}** {position}", qrm.callsign) })
}

fn soft_mismatch(hz: i64, band: &str, mode: &str) -> Option<Verdict> {
    let des = designation(hz, band);
    let mdes = mode_designation(mode);
    if des == mdes {
        return None;
    }
    let up = normalize(mode);
    if (up == "FT8" || up == "FT4") && hole_mode(band, hz).is_none() {
        let table = if up == "FT8" { band_plan::FT8_FREQUENCIES } else { band_plan::FT4_FREQUENCIES };
        if let Some(hole) = lookup(table, band) {
            return Some(Verdict {
                is_good: false,
                message: format!("{up} is usually on **{}**", fmt_mhz(hole)),
            });
        }
    }
    Some(Verdict { is_good: false, message: format!("This is **{des}**, you're set to **{mdes}**") })
}

fn block_label(hz: i64, mode: &str, facts: &RowFacts) -> Option<String> {
    if facts.cw_in_data {
        return Some("⚠ data segment".to_string());
    }
    let mhz = hz as f64 / 1_000_000.0;
    match facts.violation? {
        ViolationType::NoPrivileges => Some(format!("⚠ {} only", required_license(mhz, mode).display_name())),
        ViolationType::WrongMode => Some(format!("⚠ {} not permitted", display_mode(mode))),
        ViolationType::OutOfBand => Some("⚠ out of band".to_string()),
        ViolationType::UnusualFrequency => None,
    }
}

/// True when CW is tuned into a data-only usage zone (legal but doesn't belong).
fn is_cw_in_data_zone(hz: i64, mode: &str) -> bool {
    if normalize(mode) != "CW" {
        return false;
    }
    let mhz = hz as f64 / 1_000_000.0;
    let Some(band) = band_plan::segment_for(mhz).map(|s| s.band) else {
        return false;
    };
    let digital = band_plan::usage_zones_for(band, "FT8");
    let cw = band_plan::usage_zones_for(band, "CW");
    let in_digital = digital.iter().any(|z| z.contains(mhz));
    let in_cw = cw.iter().any(|z| z.contains(mhz));
    in_digital && !in_cw
}

fn segment_start_label(hz: i64) -> Option<String> {
    let mhz = hz as f64 / 1_000_000.0;
    let seg = band_plan::segment_for(mhz)?;
    if (seg.start_mhz * 1_000_000.0).round() as i64 != hz {
        return None;
    }
    Some(if is_phone_segment(seg) {
        format!("SSB · {}", if seg.minimum_license == LicenseClass::Extra { "Extra" } else { "General" })
    } else {
        "CW / data".to_string()
    })
}

fn designation(hz: i64, band: &str) -> String {
    if let Some(hole) = hole_mode(band, hz) {
        return hole;
    }
    let mhz = hz as f64 / 1_000_000.0;
    match band_plan::segment_for(mhz) {
        Some(seg) if is_phone_segment(seg) => "SSB".to_string(),
        _ => "CW".to_string(),
    }
}

fn required_license(mhz: f64, mode: &str) -> LicenseClass {
    let normalized = band_plan::normalize_mode(mode);
    band_plan::SEGMENTS
        .iter()
        .filter(|seg| seg.contains(mhz) && seg.allows_mode(&normalized))
        .min_by_key(|seg| band_plan::license_rank(seg.minimum_license))
        .map(|seg| seg.minimum_license)
        .unwrap_or(LicenseClass::Extra)
}

fn is_phone_segment(seg: &band_plan::BandSegment) -> bool {
    !seg.modes.is_empty() && seg.modes.iter().all(|m| PHONE_MODES.contains(&m.to_uppercase().as_str()))
}

/// Scope-local mode normalize — keeps FT8/FT4 distinct (unlike
/// `band_plan::normalize_mode`, which folds them into DATA).
fn normalize(mode: &str) -> String {
    match mode.to_uppercase().as_str() {
        // NOTE: the Swift original omits "SSB" here (only USB/LSB/PHONE/AM/FM),
        // which mis-classifies a literal "SSB" mode as CW. Fixed in this shared
        // port since the wizard passes "SSB" directly.
        "SSB" | "USB" | "LSB" | "PHONE" | "AM" | "FM" => "SSB",
        "RTTY" | "PSK" | "PSK31" | "DATA" => "DATA",
        "FT8" => "FT8",
        "FT4" => "FT4",
        _ => "CW",
    }
    .to_string()
}

fn mode_designation(mode: &str) -> String {
    match normalize(mode).as_str() {
        "SSB" => "SSB",
        "FT8" => "FT8",
        "FT4" => "FT4",
        _ => "CW",
    }
    .to_string()
}

fn display_mode(mode: &str) -> String {
    if PHONE_MODES.contains(&mode.to_uppercase().as_str()) {
        "SSB".to_string()
    } else {
        mode.to_uppercase()
    }
}

fn pick_lead<'a>(members: &[&'a ScopeSpot]) -> Option<&'a ScopeSpot> {
    // Highest tier, then most recent (smallest age) — matches the Swift `max`.
    members
        .iter()
        .copied()
        .max_by(|a, b| a.tier.cmp(&b.tier).then(b.age_seconds.cmp(&a.age_seconds)))
}

fn row_freq_text(hz: i64, lead: Option<&ScopeSpot>, facts: &RowFacts, label_mod: i64, step: i64) -> String {
    if let Some(lead) = lead {
        return fmt_hz(lead.frequency_hz);
    }
    if hz % label_mod == 0 || facts.hole.is_some() || step >= 10_000 {
        return fmt_hz(hz);
    }
    String::new()
}

fn cluster_spots(spots: &[ScopeSpot], lo: i64, hi: i64, step: i64) -> HashMap<i64, Vec<&ScopeSpot>> {
    let mut clusters: HashMap<i64, Vec<&ScopeSpot>> = HashMap::new();
    for spot in spots {
        let offset = (spot.frequency_hz - lo) as f64 / step as f64;
        let row_hz = lo + offset.round() as i64 * step;
        if row_hz >= lo && row_hz <= hi {
            clusters.entry(row_hz).or_default().push(spot);
        }
    }
    clusters
}

fn lookup(table: &[(&str, f64)], band: &str) -> Option<f64> {
    table.iter().find(|(b, _)| *b == band).map(|(_, f)| *f)
}

fn fmt_hz(hz: i64) -> String {
    fmt_mhz(hz as f64 / 1_000_000.0)
}

fn fmt_mhz(mhz: f64) -> String {
    format!("{mhz:.3}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clear_ssb_in_general_phone() {
        let v = evaluate(14_285_000, "20m", "SSB", LicenseClass::General, &[]);
        assert!(v.is_good, "{}", v.message);
    }

    #[test]
    fn no_privileges_for_extra_only_segment() {
        // 14.150–14.225 is Extra phone; a General op has no privileges.
        let v = evaluate(14_175_000, "20m", "SSB", LicenseClass::General, &[]);
        assert!(!v.is_good);
        assert!(v.message.contains("Extra"), "{}", v.message);
    }

    #[test]
    fn qrm_flags_a_nearby_station() {
        let spots = vec![ScopeSpot {
            frequency_hz: 14_035_000,
            callsign: "W1AW".to_string(),
            tier: 0,
            wpm: None,
            age_seconds: 30,
        }];
        let v = evaluate(14_035_000, "20m", "CW", LicenseClass::General, &spots);
        assert!(!v.is_good);
        assert!(v.message.contains("W1AW"), "{}", v.message);
    }

    #[test]
    fn build_rows_spans_the_band() {
        let rows = build_rows("20m", "CW", LicenseClass::General, 1_000, &[]);
        assert!(!rows.is_empty());
        assert_eq!(rows.first().unwrap().hz, 14_000_000);
        assert_eq!(rows.last().unwrap().hz, 14_350_000);
    }

    #[test]
    fn default_hz_uses_ft8_hole() {
        assert_eq!(default_hz("20m", "FT8"), Some(14_074_000));
    }
}
