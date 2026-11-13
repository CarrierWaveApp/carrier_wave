//! Bulk propagation + ground tracks. Port of the `nonisolated static`
//! propagation math in `SatelliteTrackerModel.swift` (`propagate`,
//! `position(of:)`, `applyLook`, `groundTrack`).

use chrono::{DateTime, Duration, Utc};

use super::catalog::HamSatellite;
use super::propagator::{footprint_radius_m, normalize_longitude};
use super::Observer;

/// A satellite's geodetic position at a moment, plus ground velocity and
/// (when an observer is known) look angles with finite-difference rates.
/// Port of the Swift `SatellitePosition`.
#[derive(Debug, Clone, PartialEq)]
pub struct SatPosition {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub alt_km: f64,
    pub lat_rate_deg_per_sec: f64,
    pub lon_rate_deg_per_sec: f64,
    pub azimuth_deg: Option<f64>,
    pub elevation_deg: Option<f64>,
    pub range_km: Option<f64>,
    pub az_rate_deg_per_sec: f64,
    pub el_rate_deg_per_sec: f64,
    /// Slant-range rate (km/s, positive = receding) for Doppler correction.
    pub range_rate_km_per_sec: f64,
}

impl SatPosition {
    pub fn footprint_radius_m(&self) -> f64 {
        footprint_radius_m(self.alt_km)
    }
}

/// Finite-difference step, seconds — matches the Swift `velocityStep`/`step`.
const RATE_STEP_SECS: f64 = 10.0;

/// Propagate every satellite to `at`, observer-relative fields filled when a
/// site is given. Port of `SatelliteTrackerModel.propagate`.
pub fn propagate_all(
    sats: &[HamSatellite],
    at: DateTime<Utc>,
    observer: Option<Observer>,
) -> Vec<SatPosition> {
    let mut out = Vec::with_capacity(sats.len());
    for sat in sats {
        let Some(mut pos) = position_of(sat, at, true) else {
            continue;
        };
        if let Some(site) = observer {
            apply_look(&mut pos, sat, at, site);
        }
        out.push(pos);
    }
    out
}

/// Ground track running one orbital period FORWARD from `around`, 30-second
/// samples, span capped at 1440 minutes for deep-space orbits. Port of
/// `SatelliteTrackerModel.groundTrack` (see its comment for why the track is
/// anchored at the satellite rather than centered).
pub fn ground_track(
    sat: &HamSatellite,
    around: DateTime<Utc>,
    observer: Option<Observer>,
) -> Vec<SatPosition> {
    let span_minutes = sat.propagator.period_minutes().min(1_440.0);
    let mut track = Vec::new();
    let mut offset_minutes = 0.0;
    while offset_minutes <= span_minutes {
        let sample = around + Duration::milliseconds((offset_minutes * 60_000.0) as i64);
        if let Some(mut pos) = position_of(sat, sample, false) {
            if let Some(site) = observer {
                apply_look(&mut pos, sat, sample, site);
            }
            track.push(pos);
        }
        offset_minutes += 0.5;
    }
    track
}

/// Geodetic position + optional ground velocity, with the same sanity gate
/// as the Swift `position(of:)`: `0 < alt < 500_000 km`, finite lat/lon.
fn position_of(sat: &HamSatellite, at: DateTime<Utc>, with_velocity: bool) -> Option<SatPosition> {
    let geo = sat.propagator.geo_position(at)?;
    let sane = geo.alt_km > 0.0
        && geo.alt_km < 500_000.0
        && geo.lat_deg.is_finite()
        && geo.lon_deg.is_finite();
    if !sane {
        return None;
    }
    let mut pos = SatPosition {
        norad_id: sat.norad_id,
        name: sat.name.clone(),
        detail_name: sat.detail_name.clone(),
        lat_deg: geo.lat_deg,
        lon_deg: normalize_longitude(geo.lon_deg),
        alt_km: geo.alt_km,
        lat_rate_deg_per_sec: 0.0,
        lon_rate_deg_per_sec: 0.0,
        azimuth_deg: None,
        elevation_deg: None,
        range_km: None,
        az_rate_deg_per_sec: 0.0,
        el_rate_deg_per_sec: 0.0,
        range_rate_km_per_sec: 0.0,
    };
    if with_velocity {
        let ahead_at = at + Duration::seconds(RATE_STEP_SECS as i64);
        if let Some(ahead) = sat.propagator.geo_position(ahead_at) {
            if ahead.lat_deg.is_finite() && ahead.lon_deg.is_finite() {
                let mut lon_delta = normalize_longitude(ahead.lon_deg) - pos.lon_deg;
                if lon_delta > 180.0 {
                    lon_delta -= 360.0;
                }
                if lon_delta < -180.0 {
                    lon_delta += 360.0;
                }
                pos.lat_rate_deg_per_sec = (ahead.lat_deg - pos.lat_deg) / RATE_STEP_SECS;
                pos.lon_rate_deg_per_sec = lon_delta / RATE_STEP_SECS;
            }
        }
    }
    Some(pos)
}

/// Fill observer-relative az/el/range plus finite-difference rates. Port of
/// `SatelliteTrackerModel.applyLook`.
fn apply_look(pos: &mut SatPosition, sat: &HamSatellite, at: DateTime<Utc>, site: Observer) {
    let Some(look) = sat.propagator.look(at, site) else {
        return;
    };
    pos.azimuth_deg = Some(look.azimuth_deg);
    pos.elevation_deg = Some(look.elevation_deg);
    pos.range_km = Some(look.range_km);
    let ahead_at = at + Duration::seconds(RATE_STEP_SECS as i64);
    let Some(ahead) = sat.propagator.look(ahead_at, site) else {
        return;
    };
    let mut az_delta = ahead.azimuth_deg - look.azimuth_deg;
    if az_delta > 180.0 {
        az_delta -= 360.0;
    }
    if az_delta < -180.0 {
        az_delta += 360.0;
    }
    pos.az_rate_deg_per_sec = az_delta / RATE_STEP_SECS;
    pos.el_rate_deg_per_sec = (ahead.elevation_deg - look.elevation_deg) / RATE_STEP_SECS;
    pos.range_rate_km_per_sec = (ahead.range_km - look.range_km) / RATE_STEP_SECS;
}
