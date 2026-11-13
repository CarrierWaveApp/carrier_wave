//! Persistence for aggregated AMSAT community satellite status.

use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};

#[derive(Debug, Clone)]
pub struct AmsatStatusRow {
    pub name: String,
    pub norad_id: Option<i64>,
    pub last_heard_at: Option<DateTime<Utc>>,
    pub last_reported_at: Option<DateTime<Utc>>,
    pub last_report: Option<String>,
    pub last_callsign: Option<String>,
    pub last_grid: Option<String>,
    pub heard_reports_24h: i32,
    pub total_reports_24h: i32,
    pub updated_at: DateTime<Utc>,
}

/// Replace the whole table in one transaction — satellites dropped from the
/// AMSAT page vanish cleanly on the next cycle.
pub async fn replace_all(pool: &PgPool, rows: &[AmsatStatusRow]) -> Result<(), sqlx::Error> {
    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM amsat_status").execute(&mut *tx).await?;
    for row in rows {
        sqlx::query(
            "INSERT INTO amsat_status (name, norad_id, last_heard_at, last_reported_at,
                last_report, last_callsign, last_grid, heard_reports_24h,
                total_reports_24h, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())",
        )
        .bind(&row.name)
        .bind(row.norad_id)
        .bind(row.last_heard_at)
        .bind(row.last_reported_at)
        .bind(&row.last_report)
        .bind(&row.last_callsign)
        .bind(&row.last_grid)
        .bind(row.heard_reports_24h)
        .bind(row.total_reports_24h)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await
}

pub async fn list_all(pool: &PgPool) -> Result<Vec<AmsatStatusRow>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT name, norad_id, last_heard_at, last_reported_at, last_report,
                last_callsign, last_grid, heard_reports_24h, total_reports_24h, updated_at
         FROM amsat_status
         ORDER BY name",
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| AmsatStatusRow {
            name: r.get("name"),
            norad_id: r.get("norad_id"),
            last_heard_at: r.get("last_heard_at"),
            last_reported_at: r.get("last_reported_at"),
            last_report: r.get("last_report"),
            last_callsign: r.get("last_callsign"),
            last_grid: r.get("last_grid"),
            heard_reports_24h: r.get("heard_reports_24h"),
            total_reports_24h: r.get("total_reports_24h"),
            updated_at: r.get("updated_at"),
        })
        .collect())
}

// MARK: - Raw reports

/// One community report as AMSAT serves it, kept across cycles so the
/// history outlives one capped API page (`amsat_report`, migrations 051 +
/// 052).
#[derive(Debug, Clone, PartialEq)]
pub struct AmsatReportRow {
    pub name: String,
    pub reported_at: DateTime<Utc>,
    pub callsign: String,
    pub report: String,
    pub grid: Option<String>,
    /// AMSAT's 15-minute slot within the hour (0–3); None for rows stored
    /// before the new API exposed it.
    pub period: Option<i16>,
}

/// Insert reports we haven't seen; duplicates (same satellite, hour,
/// callsign, verdict) are dropped. A report that carries a period first
/// evicts any stored verdict the same callsign filed for the same
/// satellite, hour and period — AMSAT replaces such a report rather than
/// keeping both, so we mirror the replacement. Returns the number of new
/// rows.
pub async fn insert_reports(pool: &PgPool, rows: &[AmsatReportRow]) -> Result<u64, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let mut inserted = 0;
    for row in rows {
        if let Some(period) = row.period {
            sqlx::query(
                "DELETE FROM amsat_report
                 WHERE name = $1 AND reported_at = $2 AND callsign = $3
                   AND period = $4 AND report <> $5",
            )
            .bind(&row.name)
            .bind(row.reported_at)
            .bind(&row.callsign)
            .bind(period)
            .bind(&row.report)
            .execute(&mut *tx)
            .await?;
        }
        let result = sqlx::query(
            "INSERT INTO amsat_report (name, reported_at, callsign, report, grid, period)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (name, reported_at, callsign, report) DO NOTHING",
        )
        .bind(&row.name)
        .bind(row.reported_at)
        .bind(&row.callsign)
        .bind(&row.report)
        .bind(&row.grid)
        .bind(row.period)
        .execute(&mut *tx)
        .await?;
        inserted += result.rows_affected();
    }
    tx.commit().await?;
    Ok(inserted)
}

/// The newest `reported_at` we hold — the incremental poll's cursor.
pub async fn latest_reported_at(pool: &PgPool) -> Result<Option<DateTime<Utc>>, sqlx::Error> {
    let row = sqlx::query("SELECT MAX(reported_at) AS latest FROM amsat_report")
        .fetch_one(pool)
        .await?;
    Ok(row.get("latest"))
}

/// Every stored report for one satellite at or after `since`, newest first.
pub async fn fetch_reports_since(
    pool: &PgPool,
    name: &str,
    since: DateTime<Utc>,
) -> Result<Vec<AmsatReportRow>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT name, reported_at, callsign, report, grid, period
         FROM amsat_report
         WHERE name = $1 AND reported_at >= $2
         ORDER BY reported_at DESC",
    )
    .bind(name)
    .bind(since)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| AmsatReportRow {
            name: r.get("name"),
            reported_at: r.get("reported_at"),
            callsign: r.get("callsign"),
            report: r.get("report"),
            grid: r.get("grid"),
            period: r.get("period"),
        })
        .collect())
}

/// Drop reports older than `cutoff`. Returns the number removed.
pub async fn prune_reports_before(pool: &PgPool, cutoff: DateTime<Utc>) -> Result<u64, sqlx::Error> {
    let result = sqlx::query("DELETE FROM amsat_report WHERE reported_at < $1")
        .bind(cutoff)
        .execute(pool)
        .await?;
    Ok(result.rows_affected())
}

/// Reports per (satellite, hour, verdict) since `since` — the raw material
/// for the activity grid; the handler folds verdicts into buckets.
#[derive(Debug, Clone, PartialEq)]
pub struct AmsatActivityCount {
    pub name: String,
    pub bucket_start: DateTime<Utc>,
    pub report: String,
    pub count: i64,
}

pub async fn activity_counts(
    pool: &PgPool,
    since: DateTime<Utc>,
) -> Result<Vec<AmsatActivityCount>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT name, date_trunc('hour', reported_at) AS bucket_start, report, COUNT(*) AS count
         FROM amsat_report
         WHERE reported_at >= $1
         GROUP BY name, bucket_start, report
         ORDER BY name, bucket_start",
    )
    .bind(since)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| AmsatActivityCount {
            name: r.get("name"),
            bucket_start: r.get("bucket_start"),
            report: r.get("report"),
            count: r.get("count"),
        })
        .collect())
}

/// Every stored report for a set of satellite names at or after `since`,
/// newest first, capped at `limit` rows — the per-bird reports feed.
pub async fn fetch_reports_for_names_since(
    pool: &PgPool,
    names: &[String],
    since: DateTime<Utc>,
    limit: i64,
) -> Result<Vec<AmsatReportRow>, sqlx::Error> {
    if names.is_empty() {
        return Ok(Vec::new());
    }
    let rows = sqlx::query(
        "SELECT name, reported_at, callsign, report, grid, period
         FROM amsat_report
         WHERE name = ANY($1) AND reported_at >= $2
         ORDER BY reported_at DESC, callsign
         LIMIT $3",
    )
    .bind(names)
    .bind(since)
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| AmsatReportRow {
            name: r.get("name"),
            reported_at: r.get("reported_at"),
            callsign: r.get("callsign"),
            report: r.get("report"),
            grid: r.get("grid"),
            period: r.get("period"),
        })
        .collect())
}
