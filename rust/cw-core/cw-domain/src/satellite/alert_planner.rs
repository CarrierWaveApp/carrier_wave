//! Pure planning core for satellite pass alerts: maps upcoming passes of
//! favorited birds onto the bounded set of local notifications worth
//! scheduling. Port of `SatellitePassAlertPlanner`
//! (`SatellitePassAlertPlanner.swift`) — thresholds, ordering, cap,
//! identifiers, and copy strings are byte-identical; the platform
//! notification scheduling stays host-side.

use chrono::{DateTime, Utc};

use super::pass_predictor::UpcomingPass;
use super::workability::{
    is_marginal, MIN_WORKABLE_PASS_ELEVATION_DEG,
};

/// iOS caps pending local notifications at 64 app-wide; Android's alarm
/// budget is softer but the same 24-slot cap keeps both hosts honest.
pub const MAX_PENDING_ALERTS: usize = 24;

/// Identifier prefix — hosts cancel/reconcile only their own.
pub const IDENTIFIER_PREFIX: &str = "satpass-";

/// One notification to schedule, plus the pass geometry the tap handler
/// needs (countdown Live Activity on iOS, deep link on Android).
#[derive(Debug, Clone, PartialEq)]
pub struct PlannedAlert {
    pub identifier: String,
    pub fire_at: DateTime<Utc>,
    pub title: String,
    pub body: String,
    pub norad_id: u32,
    pub satellite_name: String,
    pub aos: DateTime<Utc>,
    pub los: DateTime<Utc>,
    pub peak_elevation_deg: f64,
    pub aos_azimuth_deg: f64,
    pub los_azimuth_deg: f64,
    pub is_marginal: bool,
}

/// Plan alerts for the given favorite passes:
/// - drops passes below the 10° floor, and 10–20° unless `include_marginal`
/// - drops passes whose fire date (AOS − lead) is already past
/// - orders nearest-AOS-first across all satellites interleaved
/// - caps at [`MAX_PENDING_ALERTS`]
pub fn plan(
    passes: &[UpcomingPass],
    include_marginal: bool,
    lead_secs: i64,
    now: DateTime<Utc>,
) -> Vec<PlannedAlert> {
    let mut planned: Vec<PlannedAlert> = passes
        .iter()
        .filter_map(|item| {
            let peak = item.pass.peak_elevation_deg;
            if peak < MIN_WORKABLE_PASS_ELEVATION_DEG {
                return None;
            }
            let marginal = is_marginal(peak);
            if marginal && !include_marginal {
                return None;
            }
            let fire_at = item.pass.aos - chrono::Duration::seconds(lead_secs);
            if fire_at <= now {
                return None;
            }
            let lead_minutes = ((lead_secs as f64) / 60.0).round() as i64;
            Some(PlannedAlert {
                identifier: identifier(item.norad_id, item.pass.aos),
                fire_at,
                title: format!("{} pass in {} min", item.name, lead_minutes),
                body: alert_body(
                    peak,
                    item.pass.aos_azimuth_deg,
                    item.pass.los_azimuth_deg,
                    item.pass.duration_secs(),
                    marginal,
                ),
                norad_id: item.norad_id,
                satellite_name: item.name.clone(),
                aos: item.pass.aos,
                los: item.pass.los,
                peak_elevation_deg: peak,
                aos_azimuth_deg: item.pass.aos_azimuth_deg,
                los_azimuth_deg: item.pass.los_azimuth_deg,
                is_marginal: marginal,
            })
        })
        .collect();
    planned.sort_by_key(|alert| alert.aos);
    planned.truncate(MAX_PENDING_ALERTS);
    planned
}

/// Stable per-pass identifier: NORAD id + AOS rounded to the minute, so a
/// TLE refresh that moves AOS by seconds doesn't churn the pending
/// notification (±30 s drift keeps the same identifier).
pub fn identifier(norad_id: u32, aos: DateTime<Utc>) -> String {
    let rounded = ((aos.timestamp() as f64 / 60.0).round() as i64) * 60;
    format!("{IDENTIFIER_PREFIX}{norad_id}-{rounded}")
}

/// "Peaks 62° · W → E · 6 min" (+ " · marginal" for 10–20° passes).
pub fn alert_body(
    peak_elevation_deg: f64,
    aos_azimuth_deg: f64,
    los_azimuth_deg: f64,
    duration_secs: i64,
    marginal: bool,
) -> String {
    let path = format!(
        "{} → {}",
        compass_point(aos_azimuth_deg),
        compass_point(los_azimuth_deg)
    );
    let minutes = ((duration_secs as f64 / 60.0).round() as i64).max(1);
    let mut body =
        format!("Peaks {peak_elevation_deg:.0}° · {path} · {minutes} min");
    if marginal {
        body.push_str(" · marginal");
    }
    body
}

/// 8-point compass point (no degrees — notification copy stays short).
fn compass_point(degrees: f64) -> &'static str {
    const POINTS: [&str; 8] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    let index = (((degrees + 22.5) / 45.0).floor() as isize).rem_euclid(8) as usize;
    POINTS[index]
}

#[cfg(test)]
mod tests {
    //! Verbatim ports of the six Swift parity tests
    //! (`SatellitePassAlertPlannerTests.swift`), same fixed `now`.

    use super::*;
    use crate::satellite::pass_predictor::SatPass;
    use chrono::{Duration, TimeZone};

    fn now() -> DateTime<Utc> {
        Utc.timestamp_opt(1_789_999_980, 0).unwrap()
    }

    #[allow(clippy::too_many_arguments)]
    fn upcoming(
        norad: u32,
        name: &str,
        aos_minutes: i64,
        peak: f64,
        aos_azimuth: f64,
        los_azimuth: f64,
        duration_minutes: i64,
    ) -> UpcomingPass {
        let aos = now() + Duration::minutes(aos_minutes);
        let los = aos + Duration::minutes(duration_minutes);
        UpcomingPass {
            norad_id: norad,
            name: name.to_string(),
            detail_name: None,
            pass: SatPass {
                aos,
                aos_azimuth_deg: aos_azimuth,
                peak: aos + Duration::seconds(duration_minutes * 30),
                peak_azimuth_deg: 0.0,
                peak_elevation_deg: peak,
                peak_range_km: 800.0,
                los,
                los_azimuth_deg: los_azimuth,
            },
        }
    }

    fn simple(norad: u32, name: &str, aos_minutes: i64, peak: f64) -> UpcomingPass {
        upcoming(norad, name, aos_minutes, peak, 315.0, 135.0, 10)
    }

    #[test]
    fn orders_nearest_aos_first_interleaved() {
        let passes = [
            simple(1, "AO-91", 180, 60.0),
            simple(2, "SO-50", 60, 60.0),
            simple(1, "AO-91", 120, 60.0),
        ];
        let planned = plan(&passes, false, 15 * 60, now());
        let ids: Vec<u32> = planned.iter().map(|a| a.norad_id).collect();
        assert_eq!(ids, [2, 1, 1]);
        let mut sorted = planned.clone();
        sorted.sort_by_key(|a| a.aos);
        assert_eq!(planned, sorted);
    }

    #[test]
    fn caps_at_budget_keeping_soonest() {
        let passes: Vec<UpcomingPass> = (0..40)
            .map(|i| simple(i, &format!("SAT-{i}"), 60 + (i as i64) * 10, 45.0))
            .collect();
        let planned = plan(&passes, false, 15 * 60, now());
        assert_eq!(planned.len(), MAX_PENDING_ALERTS);
        assert_eq!(planned.first().map(|a| a.norad_id), Some(0));
        assert_eq!(
            planned.last().map(|a| a.norad_id),
            Some(MAX_PENDING_ALERTS as u32 - 1)
        );
    }

    #[test]
    fn marginal_boundaries() {
        let passes = [
            simple(1, "LOW", 60, 9.9),
            simple(2, "MARGINAL-FLOOR", 70, 10.0),
            simple(3, "MARGINAL-TOP", 80, 19.9),
            simple(4, "RECOMMENDED", 90, 20.0),
        ];
        let strict = plan(&passes, false, 15 * 60, now());
        assert_eq!(strict.iter().map(|a| a.norad_id).collect::<Vec<_>>(), [4]);

        let relaxed = plan(&passes, true, 15 * 60, now());
        assert_eq!(
            relaxed.iter().map(|a| a.norad_id).collect::<Vec<_>>(),
            [2, 3, 4]
        );
        assert!(relaxed[0].is_marginal);
        assert!(relaxed[1].is_marginal);
        assert!(!relaxed[2].is_marginal);
    }

    #[test]
    fn lead_time_math_and_past_drop() {
        let passes = [simple(1, "SOON", 10, 45.0), simple(2, "LATER", 60, 45.0)];
        let planned = plan(&passes, false, 15 * 60, now());
        assert_eq!(planned.iter().map(|a| a.norad_id).collect::<Vec<_>>(), [2]);
        assert_eq!(planned[0].fire_at, planned[0].aos - Duration::minutes(15));
    }

    #[test]
    fn identifier_survives_30s_drift_via_minute_rounding() {
        let aos = now() + Duration::hours(1);
        let base = identifier(43_017, aos);
        let drifted = identifier(43_017, aos + Duration::seconds(20));
        let moved = identifier(43_017, aos + Duration::seconds(45));
        assert!(base.starts_with(IDENTIFIER_PREFIX));
        assert_eq!(base, drifted);
        assert_ne!(base, moved);
    }

    #[test]
    fn copy_strings_match_ios() {
        let item = upcoming(1, "SO-50", 60, 62.0, 270.0, 90.0, 6);
        let planned = plan(&[item], false, 15 * 60, now());
        assert_eq!(planned[0].title, "SO-50 pass in 15 min");
        assert_eq!(planned[0].body, "Peaks 62° · W → E · 6 min");

        let marginal = upcoming(2, "AO-7", 60, 12.0, 0.0, 180.0, 9);
        let relaxed = plan(&[marginal], true, 15 * 60, now());
        assert_eq!(relaxed[0].body, "Peaks 12° · N → S · 9 min · marginal");
    }
}
