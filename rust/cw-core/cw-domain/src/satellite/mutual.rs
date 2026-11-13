//! Joint-visibility search over two observer sites: scans min(elA, elB)
//! with the same coarse-scan + bisection approach as the single-station
//! predictor. Port of `MutualPassPlanner` (`MutualPassPlanner.swift`).
//! Per-satellite here; the cross-satellite sweep fans out in cw-ffi.

use chrono::{DateTime, Duration, Utc};

use super::catalog::HamSatellite;
use super::propagator::SatPropagator;
use super::Observer;

pub const LOOK_AHEAD_HOURS: f64 = 24.0;
pub const MAX_PASSES: usize = 3;

const COARSE_STEP_SECS: i64 = 60;
const PEAK_SAMPLE_SECS: i64 = 10;
const SAMPLE_STEP_SECS: i64 = 15;
const MAX_PAD_SECS: i64 = 900;

/// A window during which a satellite is above the horizon at BOTH stations.
#[derive(Debug, Clone, PartialEq)]
pub struct MutualPass {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    /// Moment the limiting (lower) elevation peaks — the best of the window.
    pub peak_date: DateTime<Utc>,
    pub peak_min_elevation_deg: f64,
    pub peak_elevation_a_deg: f64,
    pub peak_elevation_b_deg: f64,
    /// Window geometry from STATION A's sky (start/peak/end azimuths, °
    /// clockwise from north) — the "which way do I point" and
    /// horizon-mask inputs; station B has its own sky.
    pub start_azimuth_a_deg: f64,
    pub peak_azimuth_a_deg: f64,
    pub end_azimuth_a_deg: f64,
}

/// One time-step of a pass for the profile visualization.
#[derive(Debug, Clone, PartialEq)]
pub struct MutualSample {
    pub date: DateTime<Utc>,
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub alt_km: f64,
    pub elevation_a_deg: f64,
    pub elevation_b_deg: f64,
}

impl MutualSample {
    pub fn either_visible(&self) -> bool {
        self.elevation_a_deg > 0.0 || self.elevation_b_deg > 0.0
    }
}

/// Mutual windows for one satellite.
pub fn mutual_passes(
    sat: &HamSatellite,
    site_a: Observer,
    site_b: Observer,
    start: DateTime<Utc>,
    hours: f64,
    max_passes: usize,
) -> Vec<MutualPass> {
    let propagator = &sat.propagator;
    let end = start + Duration::seconds((hours * 3_600.0) as i64);
    let mut passes = Vec::new();
    let mut scan = start;
    let mut was_up = joint_elevation(propagator, start, site_a, site_b) > 0.0;
    let mut pending_start = if was_up { Some(start) } else { None };
    while scan < end && passes.len() < max_passes {
        let next = scan + Duration::seconds(COARSE_STEP_SECS);
        let is_up = joint_elevation(propagator, next, site_a, site_b) > 0.0;
        if is_up && !was_up {
            pending_start = Some(refine_crossing(propagator, site_a, site_b, scan, next));
        } else if !is_up && was_up {
            if let Some(window_start) = pending_start {
                let window_end = refine_crossing(propagator, site_a, site_b, scan, next);
                if let Some(pass) = build_pass(sat, site_a, site_b, window_start, window_end) {
                    passes.push(pass);
                }
            }
            pending_start = None;
        }
        was_up = is_up;
        scan = next;
    }
    passes
}

/// Samples for the profile view: the mutual window padded outward while the
/// satellite remains visible from either station, stepped finely.
pub fn profile_samples(
    sat: &SatPropagator,
    window_start: DateTime<Utc>,
    window_end: DateTime<Utc>,
    site_a: Observer,
    site_b: Observer,
) -> Vec<MutualSample> {
    let mut start = window_start;
    let mut end = window_end;
    while (window_start - start).num_seconds() < MAX_PAD_SECS {
        let probe = start - Duration::seconds(SAMPLE_STEP_SECS);
        match sample(sat, probe, site_a, site_b) {
            Some(sample) if sample.either_visible() => start = probe,
            _ => break,
        }
    }
    while (end - window_end).num_seconds() < MAX_PAD_SECS {
        let probe = end + Duration::seconds(SAMPLE_STEP_SECS);
        match sample(sat, probe, site_a, site_b) {
            Some(sample) if sample.either_visible() => end = probe,
            _ => break,
        }
    }
    let mut samples = Vec::new();
    let mut date = start;
    while date <= end {
        if let Some(sample) = sample(sat, date, site_a, site_b) {
            samples.push(sample);
        }
        date += Duration::seconds(SAMPLE_STEP_SECS);
    }
    samples
}

fn joint_elevation(
    sat: &SatPropagator,
    at: DateTime<Utc>,
    site_a: Observer,
    site_b: Observer,
) -> f64 {
    sat.elevation_deg(at, site_a).min(sat.elevation_deg(at, site_b))
}

fn refine_crossing(
    sat: &SatPropagator,
    site_a: Observer,
    site_b: Observer,
    low: DateTime<Utc>,
    high: DateTime<Utc>,
) -> DateTime<Utc> {
    let mut low = low;
    let mut high = high;
    let low_up = joint_elevation(sat, low, site_a, site_b) > 0.0;
    while (high - low).num_seconds() > 1 {
        let mid = low + Duration::seconds((high - low).num_seconds() / 2);
        if (joint_elevation(sat, mid, site_a, site_b) > 0.0) == low_up {
            low = mid;
        } else {
            high = mid;
        }
    }
    high
}

fn build_pass(
    sat: &HamSatellite,
    site_a: Observer,
    site_b: Observer,
    window_start: DateTime<Utc>,
    window_end: DateTime<Utc>,
) -> Option<MutualPass> {
    if window_end <= window_start {
        return None;
    }
    let propagator = &sat.propagator;
    let mut peak_date = window_start;
    let mut peak_min = -90.0;
    let mut date = window_start;
    while date <= window_end {
        let joint = joint_elevation(propagator, date, site_a, site_b);
        if joint > peak_min {
            peak_min = joint;
            peak_date = date;
        }
        date += Duration::seconds(PEAK_SAMPLE_SECS);
    }
    let azimuth_a = |at: DateTime<Utc>| {
        propagator.look(at, site_a).map_or(0.0, |look| look.azimuth_deg)
    };
    Some(MutualPass {
        norad_id: sat.norad_id,
        name: sat.name.clone(),
        detail_name: sat.detail_name.clone(),
        start: window_start,
        end: window_end,
        peak_date,
        peak_min_elevation_deg: peak_min,
        peak_elevation_a_deg: propagator.elevation_deg(peak_date, site_a),
        peak_elevation_b_deg: propagator.elevation_deg(peak_date, site_b),
        start_azimuth_a_deg: azimuth_a(window_start),
        peak_azimuth_a_deg: azimuth_a(peak_date),
        end_azimuth_a_deg: azimuth_a(window_end),
    })
}

fn sample(
    sat: &SatPropagator,
    at: DateTime<Utc>,
    site_a: Observer,
    site_b: Observer,
) -> Option<MutualSample> {
    let geo = sat.geo_position(at)?;
    if !geo.lat_deg.is_finite() || !geo.lon_deg.is_finite() || geo.alt_km <= 0.0 {
        return None;
    }
    Some(MutualSample {
        date: at,
        lat_deg: geo.lat_deg,
        lon_deg: geo.lon_deg,
        alt_km: geo.alt_km,
        elevation_a_deg: sat.elevation_deg(at, site_a),
        elevation_b_deg: sat.elevation_deg(at, site_b),
    })
}
