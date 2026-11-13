//! Persistence layer for the propagation prediction cache.
//!
//! Cache keys are the hex-encoded SHA-256 of the canonical JSON body sent to
//! the sidecar. Entries are read past their `expires_at` only to let a reader
//! check staleness; the handler treats expired rows as misses.

use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::PgPool;

#[derive(Debug, Clone)]
pub struct CachedPrediction {
    pub response: Value,
    #[allow(dead_code)] // exposed for diagnostics / future stale-while-revalidate
    pub expires_at: DateTime<Utc>,
}

pub async fn get_cached(
    pool: &PgPool,
    cache_key: &str,
) -> Result<Option<CachedPrediction>, sqlx::Error> {
    let row = sqlx::query_as::<_, (Value, DateTime<Utc>)>(
        "SELECT response, expires_at
         FROM propagation_cache
         WHERE cache_key = $1 AND expires_at > now()
         LIMIT 1",
    )
    .bind(cache_key)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|(response, expires_at)| CachedPrediction {
        response,
        expires_at,
    }))
}

pub async fn put_cached(
    pool: &PgPool,
    cache_key: &str,
    endpoint: &str,
    response: &Value,
    ttl_hours: i64,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        // CAR-333: `make_interval(hours => ...)` takes int4, but sqlx binds i64 as
        // int8 and int8->int4 is only an *assignment* cast, so `hours => $4` failed
        // Parse ("function make_interval(hours => bigint) does not exist") on every
        // call — the whole Postgres cache was silently dead. Cast to int explicitly,
        // matching historic_trails.rs / park_boundaries.rs.
        "INSERT INTO propagation_cache (cache_key, endpoint, response, expires_at)
         VALUES ($1, $2, $3, now() + make_interval(hours => $4::int))
         ON CONFLICT (cache_key) DO UPDATE
           SET response = EXCLUDED.response,
               expires_at = EXCLUDED.expires_at,
               endpoint = EXCLUDED.endpoint,
               created_at = now()",
    )
    .bind(cache_key)
    .bind(endpoint)
    .bind(response)
    .bind(ttl_hours)
    .execute(pool)
    .await?;
    Ok(())
}

/// Remove cache entries whose `expires_at` is in the past. Not wired to any
/// scheduler yet — callers invoke opportunistically or rely on hit-path
/// filtering via `get_cached`'s `expires_at > now()` predicate.
#[allow(dead_code)]
pub async fn purge_expired(pool: &PgPool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query("DELETE FROM propagation_cache WHERE expires_at <= now()")
        .execute(pool)
        .await?;
    Ok(result.rows_affected())
}
