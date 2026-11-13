//! Persistence layer for the callsign enrichment subsystem.

use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};

#[derive(Debug, Clone)]
pub struct EnrichmentSource {
    pub slug: String,
    pub name: String,
    pub url: String,
    pub format: String,
    pub emoji: Option<String>,
    pub enabled: bool,
    pub last_etag: Option<String>,
    pub last_fetched_at: Option<DateTime<Utc>>,
    pub consecutive_errors: i32,
}

#[derive(Debug, Clone)]
pub struct EnrichmentRow {
    pub callsign: String,
    pub source_slug: String,
    pub source_name: String,
    pub source_emoji: Option<String>,
    pub name: Option<String>,
    pub member_number: Option<String>,
    pub emoji: Option<String>,
    pub note: Option<String>,
}

/// A parsed (callsign, name, member_number, emoji, note) tuple ready for upsert.
#[derive(Debug, Clone)]
pub struct ParsedEntry {
    pub callsign: String,
    pub name: Option<String>,
    pub member_number: Option<String>,
    pub emoji: Option<String>,
    pub note: Option<String>,
}

pub async fn list_enabled_sources(pool: &PgPool) -> Result<Vec<EnrichmentSource>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT slug, name, url, format, emoji, enabled, last_etag, last_fetched_at,
                consecutive_errors
         FROM callsign_enrichment_sources
         WHERE enabled = TRUE
         ORDER BY slug",
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| EnrichmentSource {
            slug: r.get("slug"),
            name: r.get("name"),
            url: r.get("url"),
            format: r.get("format"),
            emoji: r.get("emoji"),
            enabled: r.get("enabled"),
            last_etag: r.get("last_etag"),
            last_fetched_at: r.get("last_fetched_at"),
            consecutive_errors: r.get("consecutive_errors"),
        })
        .collect())
}

pub async fn list_all_sources_for_dataset(
    pool: &PgPool,
) -> Result<Vec<(String, String, Option<String>, Option<DateTime<Utc>>)>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT slug, name, emoji, last_fetched_at
         FROM callsign_enrichment_sources
         WHERE enabled = TRUE
         ORDER BY slug",
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| {
            (
                r.get::<String, _>("slug"),
                r.get::<String, _>("name"),
                r.get::<Option<String>, _>("emoji"),
                r.get::<Option<DateTime<Utc>>, _>("last_fetched_at"),
            )
        })
        .collect())
}

/// Replace all rows for one source in a single transaction. Old rows are
/// deleted, new rows inserted; this is simpler than diffing and the lists
/// are O(few thousand) so the cost is negligible.
pub async fn replace_source_rows(
    pool: &PgPool,
    source_slug: &str,
    entries: &[ParsedEntry],
) -> Result<(), sqlx::Error> {
    let mut tx = pool.begin().await?;

    sqlx::query("DELETE FROM callsign_enrichment WHERE source_slug = $1")
        .bind(source_slug)
        .execute(&mut *tx)
        .await?;

    for entry in entries {
        sqlx::query(
            "INSERT INTO callsign_enrichment
                 (callsign, source_slug, name, member_number, emoji, note, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, now())",
        )
        .bind(&entry.callsign)
        .bind(source_slug)
        .bind(&entry.name)
        .bind(&entry.member_number)
        .bind(&entry.emoji)
        .bind(&entry.note)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await
}

pub async fn record_source_success(
    pool: &PgPool,
    source_slug: &str,
    etag: Option<&str>,
    status: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE callsign_enrichment_sources
         SET last_fetched_at = now(),
             last_etag = $2,
             last_status = $3,
             last_error = NULL,
             consecutive_errors = 0,
             updated_at = now()
         WHERE slug = $1",
    )
    .bind(source_slug)
    .bind(etag)
    .bind(status)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn record_source_failure(
    pool: &PgPool,
    source_slug: &str,
    err: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE callsign_enrichment_sources
         SET last_status = 'error',
             last_error = $2,
             consecutive_errors = consecutive_errors + 1,
             updated_at = now()
         WHERE slug = $1",
    )
    .bind(source_slug)
    .bind(err)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn lookup_callsign(
    pool: &PgPool,
    callsign: &str,
) -> Result<Vec<EnrichmentRow>, sqlx::Error> {
    let upper = callsign.to_uppercase();
    let rows = sqlx::query(
        "SELECT e.callsign, e.source_slug, s.name AS source_name, s.emoji AS source_emoji,
                e.name, e.member_number, e.emoji, e.note
         FROM callsign_enrichment e
         JOIN callsign_enrichment_sources s ON s.slug = e.source_slug
         WHERE e.callsign = $1 AND s.enabled = TRUE
         ORDER BY e.source_slug",
    )
    .bind(&upper)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| EnrichmentRow {
            callsign: r.get("callsign"),
            source_slug: r.get("source_slug"),
            source_name: r.get("source_name"),
            source_emoji: r.get("source_emoji"),
            name: r.get("name"),
            member_number: r.get("member_number"),
            emoji: r.get("emoji"),
            note: r.get("note"),
        })
        .collect())
}

/// Stream every row across every enabled source for the dataset endpoint.
/// Ordered by callsign so the handler can group them in a single pass.
pub async fn fetch_full_dataset(pool: &PgPool) -> Result<Vec<EnrichmentRow>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT e.callsign, e.source_slug, s.name AS source_name, s.emoji AS source_emoji,
                e.name, e.member_number, e.emoji, e.note
         FROM callsign_enrichment e
         JOIN callsign_enrichment_sources s ON s.slug = e.source_slug
         WHERE s.enabled = TRUE
         ORDER BY e.callsign, e.source_slug",
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| EnrichmentRow {
            callsign: r.get("callsign"),
            source_slug: r.get("source_slug"),
            source_name: r.get("source_name"),
            source_emoji: r.get("source_emoji"),
            name: r.get("name"),
            member_number: r.get("member_number"),
            emoji: r.get("emoji"),
            note: r.get("note"),
        })
        .collect())
}

/// Most recent successful fetch across all enabled sources — used as the
/// dataset's `generated_at` and as a weak ETag input.
pub async fn most_recent_fetch(pool: &PgPool) -> Result<Option<DateTime<Utc>>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT MAX(last_fetched_at) AS ts
         FROM callsign_enrichment_sources
         WHERE enabled = TRUE",
    )
    .fetch_one(pool)
    .await?;
    Ok(row.get::<Option<DateTime<Utc>>, _>("ts"))
}
