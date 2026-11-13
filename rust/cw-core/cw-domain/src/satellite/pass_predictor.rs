//! Horizon-to-horizon pass search: 60 s coarse elevation scan, ~1 s
//! bisection refinement of the crossings, 10 s in-pass peak sampling.
//! Port of `SatellitePassPredictor` (`SatellitePassPredictor.swift`).
//! Sequential per satellite here (pure crate); the cross-satellite fan-out
//! lives in `cw-ffi::satellite_api`.

use chrono::{DateTime, Duration, Utc};

use super::propagator::{normalize_azimuth, SatPropagator};
use super::Observer;

/// Search window and result cap for the pass list UI.
pub const LOOK_AHEAD_HOURS: f64 = 48.0;
pub const MAX_PASSES: usize = 12;

const COARSE_STEP_SECS: i64 = 60;
const PEAK_SAMPLE_SECS: i64 = 10;

/// One pass with the geometry an operator needs to work it. Port of the
/// Swift `SatellitePass`.
#[derive(Debug, Clone, PartialEq)]
pub struct SatPass {
    pub aos: DateTime<Utc>,
    pub aos_azimuth_deg: f64,
    pub peak: DateTime<Utc>,
    pub peak_azimuth_deg: f64,
    pub peak_elevation_deg: f64,
    pub peak_range_km: f64,
    pub los: DateTime<Utc>,
    pub los_azimuth_deg: f64,
}

impl SatPass {
    pub fn duration_secs(&self) -> i64 {
        (self.los - self.aos).num_seconds()
    }

    pub fn is_in_progress(&self, at: DateTime<Utc>) -> bool {
        at >= self.aos && at <= self.los
    }
}

/// Result of a pass search over a fixed look-ahead window.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct PassForecast {
    pub passes: Vec<SatPass>,
    /// True when the satellite never dropped below the horizon during the
    /// whole window (e.g. a geostationary bird in view of the QTH).
    pub is_always_visible: bool,
}

/// One pass in the cross-satellite "what's next" schedule. Port of the
/// Swift `UpcomingSatellitePass`.
#[derive(Debug, Clone, PartialEq)]
pub struct UpcomingPass {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
    pub pass: SatPass,
}

pub fn forecast(
    sat: &SatPropagator,
    observer: Observer,
    start: DateTime<Utc>,
    hours: f64,
    max_passes: usize,
) -> PassForecast {
    let end = start + Duration::seconds((hours * 3_600.0) as i64);
    let mut passes = Vec::new();
    let mut scan = start;
    let mut was_up = sat.elevation_deg(start, observer) > 0.0;
    let mut ever_down = !was_up;
    let mut pending_aos = if was_up { Some(start) } else { None };
    while scan < end && passes.len() < max_passes {
        let next = scan + Duration::seconds(COARSE_STEP_SECS);
        let is_up = sat.elevation_deg(next, observer) > 0.0;
        if is_up && !was_up {
            pending_aos = Some(refine_crossing(sat, observer, scan, next));
        } else if !is_up && was_up {
            ever_down = true;
            if let Some(aos) = pending_aos {
                let los = refine_crossing(sat, observer, scan, next);
                if let Some(pass) = build_pass(sat, observer, aos, los) {
                    passes.push(pass);
                }
            }
            pending_aos = None;
        }
        was_up = is_up;
        scan = next;
    }
    let is_always_visible = passes.is_empty() && !ever_down && was_up;
    PassForecast { passes, is_always_visible }
}

/// Bisect a horizon crossing bracketed by `low`/`high` down to ~1 s.
fn refine_crossing(
    sat: &SatPropagator,
    observer: Observer,
    low: DateTime<Utc>,
    high: DateTime<Utc>,
) -> DateTime<Utc> {
    let mut low = low;
    let mut high = high;
    let low_up = sat.elevation_deg(low, observer) > 0.0;
    while (high - low).num_seconds() > 1 {
        let mid = low + Duration::seconds((high - low).num_seconds() / 2);
        if (sat.elevation_deg(mid, observer) > 0.0) == low_up {
            low = mid;
        } else {
            high = mid;
        }
    }
    high
}

/// Sample the pass for its peak and capture rise/set azimuths.
fn build_pass(
    sat: &SatPropagator,
    observer: Observer,
    aos: DateTime<Utc>,
    los: DateTime<Utc>,
) -> Option<SatPass> {
    if los <= aos {
        return None;
    }
    let aos_look = sat.look(aos, observer)?;
    let los_look = sat.look(los, observer)?;
    let mut peak_date = aos;
    let mut peak_look = aos_look;
    let mut sample = aos;
    while sample <= los {
        if let Some(look) = sat.look(sample, observer) {
            if look.elevation_deg > peak_look.elevation_deg {
                peak_look = look;
                peak_date = sample;
            }
        }
        sample += Duration::seconds(PEAK_SAMPLE_SECS);
    }
    Some(SatPass {
        aos,
        aos_azimuth_deg: normalize_azimuth(aos_look.azimuth_deg),
        peak: peak_date,
        peak_azimuth_deg: normalize_azimuth(peak_look.azimuth_deg),
        peak_elevation_deg: peak_look.elevation_deg,
        peak_range_km: peak_look.range_km,
        los,
        los_azimuth_deg: normalize_azimuth(los_look.azimuth_deg),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::satellite::propagator::iss_propagator;
    use chrono::TimeZone;

    /// SatelliteKit-generated pass fixtures (see the provenance note on
    /// `propagator::tests::matches_satellitekit_fixtures`): same ISS TLE,
    /// same observer, 48 h window from 2026-09-19T12:00:00Z, the iOS
    /// SatellitePassPredictor algorithm run against SatelliteKit. Gates:
    /// AOS/LOS ±10 s, peak elevation ±0.5°. AOS/LOS azimuths inherit the
    /// crossing-time sensitivity (~0.2°/s at the horizon), so ±3°.
    #[test]
    fn matches_satellitekit_pass_fixtures() {
        let sat = iss_propagator();
        let observer = crate::satellite::Observer::new(37.7749, -122.4194);
        let start = Utc.with_ymd_and_hms(2026, 9, 19, 12, 0, 0).unwrap();
        let result = forecast(&sat, observer, start, LOOK_AHEAD_HOURS, MAX_PASSES);
        assert!(!result.is_always_visible);
        // (aos, aos_az, peak, peak_el, los, los_az)
        let fixtures: [(i64, f64, i64, f64, i64, f64); 6] = [
            (1_789_852_798, 150.8179, 1_789_852_958, 2.6832, 1_789_853_122, 92.6238),
            (1_789_858_388, 214.1279, 1_789_858_718, 43.5288, 1_789_859_054, 56.0886),
            (1_789_864_213, 260.0186, 1_789_864_533, 24.7435, 1_789_864_857, 42.9516),
            (1_789_870_134, 298.3684, 1_789_870_404, 9.7792, 1_789_870_672, 43.9477),
            (1_789_876_017, 317.5183, 1_789_876_297, 10.6807, 1_789_876_568, 66.8663),
            (1_789_881_825, 315.8645, 1_789_882_155, 31.1511, 1_789_882_480, 106.9297),
        ];
        assert!(result.passes.len() >= fixtures.len(), "passes {}", result.passes.len());
        for (index, (aos, aos_az, peak, peak_el, los, los_az)) in fixtures.iter().enumerate() {
            let pass = &result.passes[index];
            assert!((pass.aos.timestamp() - aos).abs() <= 10, "pass {index} aos {}", pass.aos);
            assert!((pass.los.timestamp() - los).abs() <= 10, "pass {index} los {}", pass.los);
            assert!(
                (pass.peak.timestamp() - peak).abs() <= 20,
                "pass {index} peak {}",
                pass.peak
            );
            assert!(
                (pass.peak_elevation_deg - peak_el).abs() < 0.5,
                "pass {index} peakEl {}",
                pass.peak_elevation_deg
            );
            assert!(
                (pass.aos_azimuth_deg - aos_az).abs() < 3.0,
                "pass {index} aosAz {}",
                pass.aos_azimuth_deg
            );
            assert!(
                (pass.los_azimuth_deg - los_az).abs() < 3.0,
                "pass {index} losAz {}",
                pass.los_azimuth_deg
            );
        }
    }

    /// A geostationary bird in view of the observer never sets: no discrete
    /// passes, `is_always_visible`. Synthetic GEO TLE (QO-100-like orbit at
    /// ~26°E, valid checksums); observer in Germany sits in its footprint.
    #[test]
    fn geostationary_in_footprint_is_always_visible() {
        let tle = crate::satellite::SatTle {
            name: "QO-100".to_string(),
            norad_id: 43_700,
            line1: "1 43700U 18090A   26262.50000000  .00000140  00000-0  00000+0 0  9999"
                .to_string(),
            line2: "2 43700   0.0140 271.4700 0001300 210.0000 100.0000  1.00270000 21003"
                .to_string(),
        };
        let sat = crate::satellite::propagator::SatPropagator::from_tle(&tle).expect("tle");
        let start = Utc.with_ymd_and_hms(2026, 9, 19, 12, 0, 0).unwrap();
        // Locate the bird's actual longitude at start, then park the
        // observer under it so the test doesn't depend on the synthetic
        // TLE's phasing.
        let geo = sat.geo_position(start).expect("geo");
        assert!(geo.alt_km > 35_000.0, "not GEO: alt {}", geo.alt_km);
        let observer = crate::satellite::Observer::new(geo.lat_deg + 10.0, geo.lon_deg);
        let result = forecast(&sat, observer, start, LOOK_AHEAD_HOURS, MAX_PASSES);
        assert!(result.is_always_visible);
        assert!(result.passes.is_empty());
    }

    #[test]
    fn respects_max_passes_cap() {
        let sat = iss_propagator();
        let observer = crate::satellite::Observer::new(37.7749, -122.4194);
        let start = Utc.with_ymd_and_hms(2026, 9, 19, 12, 0, 0).unwrap();
        let result = forecast(&sat, observer, start, LOOK_AHEAD_HOURS, 2);
        assert_eq!(result.passes.len(), 2);
    }
}
