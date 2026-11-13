//! Public read endpoints for aggregated AMSAT community satellite status.
//!
//! `GET /satellites/amsat-status` — every satellite from amsat.org/status
//! with its last-heard summary, refreshed server-side by the aggregator so
//! clients never hit AMSAT directly.
//!
//! `GET /satellites/amsat-status/activity?hours=168` — the same satellites
//! with their hour-by-hour report histogram (the grid AMSAT's status page
//! draws), built from the accumulated `amsat_report` rows.
//!
//! `GET /satellites/amsat-status/reports?norad=27607|name=SO-50_[FM]&hours=24`
//! — the raw reports for one bird (callsign, grid, verdict), newest first.

use std::collections::BTreeMap;

use axum::{
    Json,
    extract::{Query, State},
};
use chrono::{DateTime, Duration, DurationRound, Utc};
use serde::Deserialize;
use sqlx::PgPool;

use crate::db::amsat_status::{self as db_amsat, AmsatActivityCount};
use crate::error::AppError;
use crate::models::amsat_status::{
    AmsatActivityBucket, AmsatActivityResponse, AmsatActivitySatellite, AmsatReportKind,
    AmsatReportWire, AmsatReportsResponse, AmsatSatelliteStatus, AmsatStatusResponse,
};

/// Longest activity window served (matches the aggregator's retention).
const MAX_ACTIVITY_HOURS: i64 = 168;
const BUCKET_SECONDS: i64 = 3_600;
/// Most raw reports returned by the reports feed.
const MAX_REPORTS: i64 = 500;

pub async fn get_amsat_status(
    State(pool): State<PgPool>,
) -> Result<Json<AmsatStatusResponse>, AppError> {
    let rows = db_amsat::list_all(&pool).await?;
    let updated_at = rows.iter().map(|r| r.updated_at).max();
    let satellites = rows
        .into_iter()
        .map(|r| AmsatSatelliteStatus {
            name: r.name,
            norad_id: r.norad_id,
            last_heard_at: r.last_heard_at,
            last_reported_at: r.last_reported_at,
            last_report: r.last_report,
            last_callsign: r.last_callsign,
            last_grid: r.last_grid,
            heard_reports_24h: r.heard_reports_24h,
            total_reports_24h: r.total_reports_24h,
        })
        .collect();

    Ok(Json(AmsatStatusResponse {
        satellites,
        updated_at,
    }))
}

#[derive(Debug, Deserialize)]
pub struct AmsatActivityQuery {
    /// Look-back window in hours (1–168, default 168).
    pub hours: Option<i64>,
}

pub async fn get_amsat_activity(
    State(pool): State<PgPool>,
    Query(query): Query<AmsatActivityQuery>,
) -> Result<Json<AmsatActivityResponse>, AppError> {
    let hours = query.hours.unwrap_or(MAX_ACTIVITY_HOURS).clamp(1, MAX_ACTIVITY_HOURS);
    let now = Utc::now();
    // Align the window to bucket edges so the oldest bucket is whole.
    let window_start = (now - Duration::hours(hours))
        .duration_trunc(Duration::seconds(BUCKET_SECONDS))
        .unwrap_or(now - Duration::hours(hours));

    let status_rows = db_amsat::list_all(&pool).await?;
    let counts = db_amsat::activity_counts(&pool, window_start).await?;
    let updated_at = status_rows.iter().map(|r| r.updated_at).max();

    let mut buckets_by_name = fold_buckets(&counts);
    // Every satellite AMSAT lists appears, even with an empty week, so the
    // client grid matches amsat.org's row set; names that only exist in the
    // report table (dropped from AMSAT's list since) are appended after.
    let mut satellites: Vec<AmsatActivitySatellite> = status_rows
        .iter()
        .map(|row| AmsatActivitySatellite {
            name: row.name.clone(),
            norad_id: row.norad_id,
            buckets: buckets_by_name.remove(&row.name).unwrap_or_default(),
        })
        .collect();
    satellites.extend(buckets_by_name.into_iter().map(|(name, buckets)| {
        AmsatActivitySatellite { name, norad_id: None, buckets }
    }));

    Ok(Json(AmsatActivityResponse {
        bucket_seconds: BUCKET_SECONDS,
        window_start,
        window_end: now,
        updated_at,
        satellites,
    }))
}

#[derive(Debug, Deserialize)]
pub struct AmsatReportsQuery {
    /// NORAD id — resolves to every AMSAT capability row mapped to it.
    pub norad: Option<i64>,
    /// Exact AMSAT internal name, e.g. `SO-50_[FM]`.
    pub name: Option<String>,
    /// Look-back window in hours (1–168, default 24).
    pub hours: Option<i64>,
}

pub async fn get_amsat_reports(
    State(pool): State<PgPool>,
    Query(query): Query<AmsatReportsQuery>,
) -> Result<Json<AmsatReportsResponse>, AppError> {
    let hours = query.hours.unwrap_or(24).clamp(1, MAX_ACTIVITY_HOURS);
    let now = Utc::now();
    let window_start = now - Duration::hours(hours);

    let mut names: Vec<String> = Vec::new();
    if let Some(name) = query.name.as_deref().map(str::trim).filter(|n| !n.is_empty()) {
        names.push(name.to_string());
    }
    if let Some(norad) = query.norad {
        names.extend(
            db_amsat::list_all(&pool)
                .await?
                .into_iter()
                .filter(|row| row.norad_id == Some(norad))
                .map(|row| row.name),
        );
    }
    names.sort();
    names.dedup();
    if names.is_empty() {
        return Err(AppError::Validation {
            message: "pass `norad` (a mapped NORAD id) or `name` (an AMSAT name)".to_string(),
        });
    }

    let reports = db_amsat::fetch_reports_for_names_since(&pool, &names, window_start, MAX_REPORTS)
        .await?
        .into_iter()
        .map(|r| AmsatReportWire {
            name: r.name,
            reported_at: r.reported_at,
            callsign: r.callsign,
            report: r.report,
            grid: r.grid,
        })
        .collect();

    Ok(Json(AmsatReportsResponse {
        window_start,
        window_end: now,
        names,
        reports,
    }))
}

/// Fold per-(name, hour, verdict) counts into one bucket per (name, hour),
/// hours ascending. Verdicts are classified by `AmsatReportKind`.
fn fold_buckets(counts: &[AmsatActivityCount]) -> BTreeMap<String, Vec<AmsatActivityBucket>> {
    let mut grouped: BTreeMap<String, BTreeMap<DateTime<Utc>, AmsatActivityBucket>> =
        BTreeMap::new();
    for count in counts {
        let bucket = grouped
            .entry(count.name.clone())
            .or_default()
            .entry(count.bucket_start)
            .or_insert_with(|| AmsatActivityBucket {
                start: count.bucket_start,
                ..AmsatActivityBucket::default()
            });
        bucket.add(
            AmsatReportKind::classify(&count.report),
            i32::try_from(count.count).unwrap_or(i32::MAX),
        );
    }
    grouped
        .into_iter()
        .map(|(name, by_hour)| (name, by_hour.into_values().collect()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn count(name: &str, hour: &str, report: &str, n: i64) -> AmsatActivityCount {
        AmsatActivityCount {
            name: name.to_string(),
            bucket_start: DateTime::parse_from_rfc3339(hour).unwrap().with_timezone(&Utc),
            report: report.to_string(),
            count: n,
        }
    }

    #[test]
    fn folds_verdicts_into_hour_buckets_in_order() {
        let counts = vec![
            count("SO-50_[FM]", "2026-10-13T12:00:00Z", "Heard", 3),
            count("SO-50_[FM]", "2026-10-13T12:00:00Z", "Not Heard", 1),
            count("SO-50_[FM]", "2026-10-13T08:00:00Z", "Telemetry Only", 2),
            count("AO-7_[U/v]", "2026-10-13T12:00:00Z", "Crew Active", 1),
        ];
        let folded = fold_buckets(&counts);
        let so50 = &folded["SO-50_[FM]"];
        assert_eq!(so50.len(), 2);
        assert_eq!(so50[0].start.to_rfc3339(), "2026-10-13T08:00:00+00:00");
        assert_eq!(so50[0].telemetry, 2);
        assert_eq!((so50[1].heard, so50[1].not_heard), (3, 1));
        assert_eq!(folded["AO-7_[U/v]"][0].crew, 1);
    }
}
