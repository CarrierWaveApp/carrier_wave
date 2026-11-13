//! Tiles on the Air (TOTA) scoring + helpers. Ports:
//! - `TOTAScoringEngine.swift`
//! - `TOTAT3Correlator.swift`
//! - `TOTATileDetector.swift`
//! - `TOTAWinterDetector.swift`
//!
//! The Swift engine is intentionally pure: inputs in, ledger out. The Rust
//! port keeps the same value-struct shape — the iOS shim is responsible for
//! gathering QSO/track/spot data and converting it into the input structs.

use std::collections::{HashMap, HashSet};

use chrono::{DateTime, Datelike, Utc};

use crate::maidenhead::{self, Coordinate, Precision};

// ---- Scoring engine -------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TotaCategoryKind {
    Standard,
    Mobile,
}

impl TotaCategoryKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::Mobile => "mobile",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct TotaScoringQso {
    pub id: String,
    pub mode: String,
    pub callsign: String,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TotaScoringInputs {
    pub category: TotaCategoryKind,
    pub qsos: Vec<TotaScoringQso>,
    /// Map of uppercased chaser callsign → 6-char tile, derived from the
    /// spots feed. Presence of a key means the QSO earns the T3 boost.
    pub t3_callsign_to_tile: HashMap<String, String>,
    pub distance_miles: Option<f64>,
    pub elevation_gain_feet: Option<f64>,
    pub ruck_weight_pounds: Option<f64>,
    pub personal_effort_factor: Option<i32>,
    pub qrp_activation: bool,
    pub is_winter: bool,
    pub with_pets: bool,
    pub with_kids: bool,
    pub winlink_sent: bool,
    pub aprs_sent: bool,
    pub varac_sent: bool,
    pub first_activation_of_tile_ever: bool,
    pub tile_count: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TotaConfirmedTier {
    pub effective_qsos: f64,
    pub distance_miles: f64,
    pub base: f64,
    pub qrp_multiplier_applied: bool,
    pub qso_subtotal: f64,
    pub winter_bonus: f64,
    pub ruck_bonus: f64,
    pub elevation_bonus: f64,
    pub pets_bonus: f64,
    pub kids_bonus: f64,
    pub winlink_flat: f64,
    pub aprs_flat: f64,
    pub varac_flat: f64,
    pub subtotal: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TotaScoringResult {
    pub confirmed: TotaConfirmedTier,
    pub estimated_t3_boost: f64,
    pub asserted_first_ever: f64,
    pub pending_max_points: f64,
    /// Pre-upload pessimistic total — excludes `pending_max_points`.
    pub total: f64,
}

/// Score the inputs into a four-tier ledger. Pure & deterministic.
pub fn score(inputs: &TotaScoringInputs) -> TotaScoringResult {
    let filtered = filtered_qsos(inputs);
    let effective = effective_qsos(&filtered, &inputs.t3_callsign_to_tile);
    let t3_boost = t3_boost_points(&filtered, &inputs.t3_callsign_to_tile);
    let pending_max = (inputs.tile_count.max(1) as f64) * 10.0;
    let asserted = if inputs.first_activation_of_tile_ever { 10.0 } else { 0.0 };

    match inputs.category {
        TotaCategoryKind::Mobile => {
            score_mobile(inputs, effective, t3_boost, pending_max, asserted)
        }
        TotaCategoryKind::Standard => {
            score_standard(inputs, effective, t3_boost, pending_max, asserted)
        }
    }
}

/// Per-mode weight. FT8/FT4 = 0.2; everything else = 1.0.
pub fn mode_weight(mode: &str) -> f64 {
    let upper = mode.to_uppercase();
    if upper == "FT8" || upper == "FT4" {
        0.2
    } else {
        1.0
    }
}

/// Drop QSOs whose mode matches a flat-bonus session flag, so flats and the
/// implicit QSO don't double-count.
pub fn filtered_qsos(inputs: &TotaScoringInputs) -> Vec<TotaScoringQso> {
    inputs
        .qsos
        .iter()
        .filter(|q| {
            let upper = q.mode.to_uppercase();
            if inputs.winlink_sent && upper == "WINLINK" {
                return false;
            }
            if inputs.aprs_sent && upper == "APRS" {
                return false;
            }
            if inputs.varac_sent && upper == "VARAC" {
                return false;
            }
            true
        })
        .cloned()
        .collect()
}

pub fn effective_qsos(qsos: &[TotaScoringQso], t3: &HashMap<String, String>) -> f64 {
    qsos.iter().fold(0.0, |acc, qso| {
        let weight = mode_weight(&qso.mode);
        let is_t3 = t3.contains_key(&qso.callsign.to_uppercase());
        let factor = if is_t3 { weight * 2.0 } else { weight };
        acc + factor
    })
}

pub fn t3_boost_points(qsos: &[TotaScoringQso], t3: &HashMap<String, String>) -> f64 {
    qsos.iter().fold(0.0, |acc, qso| {
        if t3.contains_key(&qso.callsign.to_uppercase()) {
            acc + mode_weight(&qso.mode)
        } else {
            acc
        }
    })
}

pub fn flat_bonuses(inputs: &TotaScoringInputs) -> f64 {
    let mut total = 0.0;
    if inputs.winlink_sent { total += 5.0; }
    if inputs.aprs_sent { total += 5.0; }
    if inputs.varac_sent { total += 5.0; }
    total
}

/// Distance with PEF scaling and 0.25-mi floor (only when distance > 0).
pub fn scaled_distance(inputs: &TotaScoringInputs) -> f64 {
    let raw = match inputs.distance_miles {
        Some(d) if d > 0.0 => d,
        _ => return 0.0,
    };
    let floored = raw.max(0.25);
    let pef = inputs.personal_effort_factor.map(f64::from).unwrap_or(1.0);
    floored * pef
}

fn score_standard(
    inputs: &TotaScoringInputs,
    effective: f64,
    t3_boost: f64,
    pending_max: f64,
    asserted: f64,
) -> TotaScoringResult {
    let distance = scaled_distance(inputs);
    let base = effective * distance;
    let qrp_multiplier = if inputs.qrp_activation { 2.0 } else { 1.0 };
    let qso_subtotal = base * qrp_multiplier;

    let winter_pct = if inputs.is_winter { 0.20 } else { 0.0 };
    let ruck_steps = (inputs.ruck_weight_pounds.unwrap_or(0.0) / 5.0).floor();
    let ruck_pct = ruck_steps * 0.05;
    let elev_steps = (inputs.elevation_gain_feet.unwrap_or(0.0) / 200.0).floor();
    let elev_pct = elev_steps * 0.02;
    let pets_pct = if inputs.with_pets { 0.15 } else { 0.0 };
    let kids_pct = if inputs.with_kids { 0.20 } else { 0.0 };

    let winter_bonus = qso_subtotal * winter_pct;
    let ruck_bonus = qso_subtotal * ruck_pct;
    let elev_bonus = qso_subtotal * elev_pct;
    let pets_bonus = qso_subtotal * pets_pct;
    let kids_bonus = qso_subtotal * kids_pct;

    let winlink_flat = if inputs.winlink_sent { 5.0 } else { 0.0 };
    let aprs_flat = if inputs.aprs_sent { 5.0 } else { 0.0 };
    let varac_flat = if inputs.varac_sent { 5.0 } else { 0.0 };

    let confirmed_subtotal = qso_subtotal
        + winter_bonus
        + ruck_bonus
        + elev_bonus
        + pets_bonus
        + kids_bonus
        + winlink_flat
        + aprs_flat
        + varac_flat;

    let confirmed = TotaConfirmedTier {
        effective_qsos: effective,
        distance_miles: distance,
        base,
        qrp_multiplier_applied: inputs.qrp_activation,
        qso_subtotal,
        winter_bonus,
        ruck_bonus,
        elevation_bonus: elev_bonus,
        pets_bonus,
        kids_bonus,
        winlink_flat,
        aprs_flat,
        varac_flat,
        subtotal: confirmed_subtotal,
    };

    let percentage_multiplier = winter_pct + ruck_pct + elev_pct + pets_pct + kids_pct;
    let t3_points = t3_boost * distance * qrp_multiplier * (1.0 + percentage_multiplier);
    let total = confirmed_subtotal + t3_points + asserted;
    TotaScoringResult {
        confirmed,
        estimated_t3_boost: t3_points,
        asserted_first_ever: asserted,
        pending_max_points: pending_max,
        total,
    }
}

fn score_mobile(
    inputs: &TotaScoringInputs,
    effective: f64,
    t3_boost: f64,
    pending_max: f64,
    asserted: f64,
) -> TotaScoringResult {
    let qrp_multiplier = if inputs.qrp_activation { 2.0 } else { 1.0 };
    let qso_subtotal = effective * qrp_multiplier;
    let winlink_flat = if inputs.winlink_sent { 5.0 } else { 0.0 };
    let aprs_flat = if inputs.aprs_sent { 5.0 } else { 0.0 };
    let varac_flat = if inputs.varac_sent { 5.0 } else { 0.0 };
    let confirmed_subtotal = qso_subtotal + winlink_flat + aprs_flat + varac_flat;

    let confirmed = TotaConfirmedTier {
        effective_qsos: effective,
        distance_miles: 0.0,
        base: qso_subtotal,
        qrp_multiplier_applied: inputs.qrp_activation,
        qso_subtotal,
        winter_bonus: 0.0,
        ruck_bonus: 0.0,
        elevation_bonus: 0.0,
        pets_bonus: 0.0,
        kids_bonus: 0.0,
        winlink_flat,
        aprs_flat,
        varac_flat,
        subtotal: confirmed_subtotal,
    };
    let t3_points = t3_boost * qrp_multiplier;
    let total = confirmed_subtotal + t3_points + asserted;
    TotaScoringResult {
        confirmed,
        estimated_t3_boost: t3_points,
        asserted_first_ever: asserted,
        pending_max_points: pending_max,
        total,
    }
}

// ---- T3 Correlator --------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct T3SpotRecord {
    pub callsign: String,
    pub maidenhead_tile: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct T3CorrelatedQso {
    pub qso_id: String,
    pub callsign: String,
    pub their_tile: String,
    pub spot_created_at: DateTime<Utc>,
}

/// Default match window for T3: spots within 6 hours preceding the QSO.
pub const DEFAULT_T3_WINDOW: chrono::Duration = chrono::Duration::seconds(6 * 60 * 60);

pub fn correlate_t3(
    spots: &[T3SpotRecord],
    qsos: &[TotaScoringQso],
    window: chrono::Duration,
) -> Vec<T3CorrelatedQso> {
    let mut by_callsign: HashMap<String, Vec<&T3SpotRecord>> = HashMap::new();
    for spot in spots {
        by_callsign
            .entry(spot.callsign.to_uppercase())
            .or_default()
            .push(spot);
    }

    let mut out = Vec::new();
    for qso in qsos {
        let Some(candidates) = by_callsign.get(&qso.callsign.to_uppercase()) else {
            continue;
        };
        let lower = qso.timestamp - window;
        let best = candidates
            .iter()
            .filter(|s| {
                s.maidenhead_tile.is_some() && s.created_at >= lower && s.created_at <= qso.timestamp
            })
            .max_by_key(|s| s.created_at);
        let Some(best) = best else { continue };
        let Some(tile) = best.maidenhead_tile.clone() else { continue };
        out.push(T3CorrelatedQso {
            qso_id: qso.id.clone(),
            callsign: qso.callsign.clone(),
            their_tile: tile,
            spot_created_at: best.created_at,
        });
    }
    out
}

// ---- Tile Detector --------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct TilePathSample {
    pub timestamp: DateTime<Utc>,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TileDetectionResult {
    pub activated: Vec<String>,
    pub candidates: Vec<String>,
}

pub fn detect_tiles(
    track: &[TilePathSample],
    qso_timestamps: &[DateTime<Utc>],
    activation_coord: Option<(f64, f64)>,
) -> TileDetectionResult {
    let mut activated: HashSet<String> = HashSet::new();
    if let Some((lat, lon)) = activation_coord {
        let tile = maidenhead::grid_from_coordinate(
            Coordinate {
                latitude: lat,
                longitude: lon,
            },
            Precision::Six,
        );
        activated.insert(tile);
    }

    let mut sorted_track = track.to_vec();
    sorted_track.sort_by_key(|s| s.timestamp);

    for ts in qso_timestamps {
        if let Some(sample) = interpolated_sample(&sorted_track, *ts) {
            let tile = maidenhead::grid_from_coordinate(
                Coordinate {
                    latitude: sample.latitude,
                    longitude: sample.longitude,
                },
                Precision::Six,
            );
            activated.insert(tile);
        }
    }

    let mut touched: HashSet<String> = HashSet::new();
    for sample in &sorted_track {
        let tile = maidenhead::grid_from_coordinate(
            Coordinate {
                latitude: sample.latitude,
                longitude: sample.longitude,
            },
            Precision::Six,
        );
        touched.insert(tile);
    }

    let candidates: HashSet<String> = touched.difference(&activated).cloned().collect();
    let mut activated: Vec<String> = activated.into_iter().collect();
    let mut candidates: Vec<String> = candidates.into_iter().collect();
    activated.sort();
    candidates.sort();
    TileDetectionResult { activated, candidates }
}

fn interpolated_sample(
    sorted_track: &[TilePathSample],
    timestamp: DateTime<Utc>,
) -> Option<TilePathSample> {
    if sorted_track.is_empty() {
        return None;
    }
    let first = &sorted_track[0];
    let last = sorted_track.last()?;
    if timestamp < first.timestamp || timestamp > last.timestamp {
        return None;
    }
    let mut before = first.clone();
    let mut after = last.clone();
    for sample in sorted_track {
        if sample.timestamp <= timestamp {
            before = sample.clone();
        } else {
            after = sample.clone();
            break;
        }
    }
    let span = (after.timestamp - before.timestamp).num_milliseconds() as f64;
    if span <= 0.0 {
        return Some(before);
    }
    let frac = (timestamp - before.timestamp).num_milliseconds() as f64 / span;
    let lat = before.latitude + (after.latitude - before.latitude) * frac;
    let lon = before.longitude + (after.longitude - before.longitude) * frac;
    Some(TilePathSample {
        timestamp,
        latitude: lat,
        longitude: lon,
    })
}

// ---- Winter Detector ------------------------------------------------------

/// True when `date` falls in the hemisphere's winter window. `latitude` in
/// decimal degrees; `None` ⇒ assume northern. Equator-adjacent (|lat| < 5°)
/// has no winter regardless of date.
pub fn is_winter(latitude: Option<f64>, date: DateTime<Utc>) -> bool {
    let month = date.month();
    let Some(lat) = latitude else {
        return month == 12 || month == 1 || month == 2;
    };
    if lat.abs() < 5.0 {
        return false;
    }
    if lat >= 0.0 {
        month == 12 || month == 1 || month == 2
    } else {
        (6..=8).contains(&month)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn ts(year: i32, month: u32, day: u32, hour: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(year, month, day, hour, 0, 0).unwrap()
    }

    fn qso(id: &str, mode: &str, callsign: &str, t: DateTime<Utc>) -> TotaScoringQso {
        TotaScoringQso {
            id: id.into(),
            mode: mode.into(),
            callsign: callsign.into(),
            timestamp: t,
        }
    }

    fn inputs() -> TotaScoringInputs {
        TotaScoringInputs {
            category: TotaCategoryKind::Standard,
            qsos: vec![],
            t3_callsign_to_tile: HashMap::new(),
            distance_miles: None,
            elevation_gain_feet: None,
            ruck_weight_pounds: None,
            personal_effort_factor: None,
            qrp_activation: false,
            is_winter: false,
            with_pets: false,
            with_kids: false,
            winlink_sent: false,
            aprs_sent: false,
            varac_sent: false,
            first_activation_of_tile_ever: false,
            tile_count: 1,
        }
    }

    // ---- Scoring engine ---------------------------------------------------

    #[test]
    fn mode_weight_ft8_quarter_pointer() {
        assert!((mode_weight("FT8") - 0.2).abs() < 1e-9);
        assert!((mode_weight("ft4") - 0.2).abs() < 1e-9);
        assert!((mode_weight("CW") - 1.0).abs() < 1e-9);
    }

    #[test]
    fn effective_qsos_doubles_t3_chasers() {
        let qsos = vec![
            qso("a", "CW", "K2ABC", ts(2026, 6, 13, 12)),
            qso("b", "CW", "W3T3X", ts(2026, 6, 13, 12)),
        ];
        let mut t3 = HashMap::new();
        t3.insert("W3T3X".into(), "FN20aa".into());
        assert!((effective_qsos(&qsos, &t3) - 3.0).abs() < 1e-9);
    }

    #[test]
    fn standard_score_with_distance_and_qrp() {
        let mut i = inputs();
        i.qsos = vec![qso("a", "CW", "K2ABC", ts(2026, 6, 13, 12))];
        i.distance_miles = Some(2.0);
        i.qrp_activation = true;
        let r = score(&i);
        // base = 1 effective × 2 miles = 2; QRP doubles to 4
        assert!((r.confirmed.qso_subtotal - 4.0).abs() < 1e-9);
        assert!((r.total - 4.0).abs() < 1e-9);
    }

    #[test]
    fn mobile_score_skips_distance_and_bonuses() {
        let mut i = inputs();
        i.category = TotaCategoryKind::Mobile;
        i.qsos = vec![
            qso("a", "CW", "K2ABC", ts(2026, 6, 13, 12)),
            qso("b", "FT8", "K3FT", ts(2026, 6, 13, 12)),
        ];
        i.aprs_sent = true;
        let r = score(&i);
        // effective = 1 + 0.2 = 1.2, qso_subtotal = 1.2; +5 APRS flat
        assert!((r.confirmed.qso_subtotal - 1.2).abs() < 1e-9);
        assert!((r.confirmed.subtotal - 6.2).abs() < 1e-9);
    }

    #[test]
    fn pending_max_uses_tile_count() {
        let mut i = inputs();
        i.tile_count = 3;
        let r = score(&i);
        assert_eq!(r.pending_max_points, 30.0);
    }

    #[test]
    fn filtered_qsos_drops_implicit_winlink() {
        let mut i = inputs();
        i.qsos = vec![
            qso("a", "WINLINK", "K2ABC", ts(2026, 6, 13, 12)),
            qso("b", "CW", "K3XYZ", ts(2026, 6, 13, 12)),
        ];
        i.winlink_sent = true;
        let kept = filtered_qsos(&i);
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].id, "b");
    }

    // ---- T3 correlator ----------------------------------------------------

    #[test]
    fn correlator_picks_latest_preceding_spot() {
        let spots = vec![
            T3SpotRecord {
                callsign: "K2ABC".into(),
                maidenhead_tile: Some("FN20aa".into()),
                created_at: ts(2026, 6, 13, 10),
            },
            T3SpotRecord {
                callsign: "K2ABC".into(),
                maidenhead_tile: Some("FN20ab".into()),
                created_at: ts(2026, 6, 13, 11),
            },
            // Outside the 6h window (too early)
            T3SpotRecord {
                callsign: "K2ABC".into(),
                maidenhead_tile: Some("FN20ac".into()),
                created_at: ts(2026, 6, 13, 5),
            },
        ];
        let qsos = vec![qso("q", "CW", "K2ABC", ts(2026, 6, 13, 12))];
        let result = correlate_t3(&spots, &qsos, DEFAULT_T3_WINDOW);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].their_tile, "FN20ab");
    }

    #[test]
    fn correlator_skips_spots_with_no_tile() {
        let spots = vec![T3SpotRecord {
            callsign: "K2ABC".into(),
            maidenhead_tile: None,
            created_at: ts(2026, 6, 13, 11),
        }];
        let qsos = vec![qso("q", "CW", "K2ABC", ts(2026, 6, 13, 12))];
        let result = correlate_t3(&spots, &qsos, DEFAULT_T3_WINDOW);
        assert!(result.is_empty());
    }

    // ---- Tile detector ----------------------------------------------------

    #[test]
    fn detect_tiles_always_includes_declared() {
        let result = detect_tiles(&[], &[], Some((37.0, -122.0)));
        assert_eq!(result.activated.len(), 1);
        assert!(result.candidates.is_empty());
    }

    #[test]
    fn detect_tiles_interpolates_qso_timestamps() {
        let t0 = ts(2026, 6, 13, 10);
        let t1 = ts(2026, 6, 13, 12);
        let track = vec![
            TilePathSample {
                timestamp: t0,
                latitude: 37.0,
                longitude: -122.0,
            },
            TilePathSample {
                timestamp: t1,
                latitude: 37.05,
                longitude: -122.05,
            },
        ];
        let qso_at = ts(2026, 6, 13, 11);
        let result = detect_tiles(&track, &[qso_at], None);
        // At least one activated tile from QSO interpolation
        assert!(!result.activated.is_empty());
    }

    // ---- Winter detector --------------------------------------------------

    #[test]
    fn northern_winter_in_dec_jan_feb() {
        for month in [1, 2, 12] {
            let d = Utc.with_ymd_and_hms(2026, month, 15, 0, 0, 0).unwrap();
            assert!(is_winter(Some(45.0), d));
        }
    }

    #[test]
    fn southern_winter_in_jun_jul_aug() {
        for month in [6, 7, 8] {
            let d = Utc.with_ymd_and_hms(2026, month, 15, 0, 0, 0).unwrap();
            assert!(is_winter(Some(-45.0), d));
        }
    }

    #[test]
    fn equator_adjacent_never_winter() {
        let d = ts(2026, 1, 15, 0);
        assert!(!is_winter(Some(0.0), d));
        assert!(!is_winter(Some(4.5), d));
    }

    #[test]
    fn missing_latitude_assumes_north() {
        let dec = ts(2026, 12, 15, 0);
        assert!(is_winter(None, dec));
        let jul = ts(2026, 7, 15, 0);
        assert!(!is_winter(None, jul));
    }
}
