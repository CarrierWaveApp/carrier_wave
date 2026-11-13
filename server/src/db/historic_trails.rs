use sqlx::PgPool;

use crate::models::historic_trail::HistoricTrailRow;

/// Get trails by references, using simplified geometry.
pub async fn get_trails_by_refs(
    pool: &PgPool,
    refs: &[String],
) -> Result<Vec<HistoricTrailRow>, sqlx::Error> {
    sqlx::query_as::<_, HistoricTrailRow>(
        r#"
        SELECT trail_reference, trail_name, designation, managing_agency,
               length_miles, state, match_quality, source,
               ST_AsGeoJSON(geometry_simplified) as geometry_json
        FROM historic_trails
        WHERE trail_reference = ANY($1)
        "#,
    )
    .bind(refs)
    .fetch_all(pool)
    .await
}

/// Get a single trail by reference with full-resolution geometry.
pub async fn get_trail_by_ref(
    pool: &PgPool,
    reference: &str,
) -> Result<Option<HistoricTrailRow>, sqlx::Error> {
    sqlx::query_as::<_, HistoricTrailRow>(
        r#"
        SELECT trail_reference, trail_name, designation, managing_agency,
               length_miles, state, match_quality, source,
               ST_AsGeoJSON(geometry) as geometry_json
        FROM historic_trails
        WHERE trail_reference = $1
        "#,
    )
    .bind(reference)
    .fetch_optional(pool)
    .await
}

/// Get trails within a bounding box, using simplified geometry.
pub async fn get_trails_by_bbox(
    pool: &PgPool,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
    limit: i64,
) -> Result<Vec<HistoricTrailRow>, sqlx::Error> {
    sqlx::query_as::<_, HistoricTrailRow>(
        r#"
        SELECT trail_reference, trail_name, designation, managing_agency,
               length_miles, state, match_quality, source,
               ST_AsGeoJSON(geometry_simplified) as geometry_json
        FROM historic_trails
        WHERE geometry_simplified && ST_MakeEnvelope($1, $2, $3, $4, 4326)
        ORDER BY trail_reference
        LIMIT $5
        "#,
    )
    .bind(west)
    .bind(south)
    .bind(east)
    .bind(north)
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Get trails within a bounding box with custom simplification tolerance.
pub async fn get_trails_by_bbox_simplified(
    pool: &PgPool,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
    limit: i64,
    simplify_tolerance: f64,
) -> Result<Vec<HistoricTrailRow>, sqlx::Error> {
    sqlx::query_as::<_, HistoricTrailRow>(
        r#"
        SELECT trail_reference, trail_name, designation, managing_agency,
               length_miles, state, match_quality, source,
               ST_AsGeoJSON(ST_Simplify(geometry, $6)) as geometry_json
        FROM historic_trails
        WHERE geometry_simplified && ST_MakeEnvelope($1, $2, $3, $4, 4326)
        ORDER BY trail_reference
        LIMIT $5
        "#,
    )
    .bind(west)
    .bind(south)
    .bind(east)
    .bind(north)
    .bind(limit)
    .bind(simplify_tolerance)
    .fetch_all(pool)
    .await
}

/// Upsert a historic trail from NPS data.
#[allow(clippy::too_many_arguments)]
pub async fn upsert_trail(
    pool: &PgPool,
    trail_reference: &str,
    trail_name: &str,
    designation: Option<&str>,
    managing_agency: Option<&str>,
    length_miles: Option<f64>,
    state: Option<&str>,
    match_quality: &str,
    geojson: &str,
    source: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO historic_trails
            (trail_reference, trail_name, designation, managing_agency,
             length_miles, state, match_quality,
             geometry, geometry_simplified, source,
             fetched_at, matched_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7,
                ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($8), 2)),
                ST_Simplify(ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($8), 2)), 0.005),
                $9, NOW(), NOW())
        ON CONFLICT (trail_reference) DO UPDATE SET
            trail_name = EXCLUDED.trail_name,
            designation = EXCLUDED.designation,
            managing_agency = EXCLUDED.managing_agency,
            length_miles = EXCLUDED.length_miles,
            state = EXCLUDED.state,
            match_quality = EXCLUDED.match_quality,
            geometry = EXCLUDED.geometry,
            geometry_simplified = EXCLUDED.geometry_simplified,
            source = EXCLUDED.source,
            fetched_at = NOW()
        "#,
    )
    .bind(trail_reference)
    .bind(trail_name)
    .bind(designation)
    .bind(managing_agency)
    .bind(length_miles)
    .bind(state)
    .bind(match_quality)
    .bind(geojson)
    .bind(source)
    .execute(pool)
    .await?;
    Ok(())
}

/// Count total cached trail geometries.
pub async fn count_trails(pool: &PgPool) -> Result<i64, sqlx::Error> {
    let row: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM historic_trails")
        .fetch_one(pool)
        .await?;
    Ok(row.0)
}

/// Get catalog trails that don't have cached geometry yet.
pub async fn get_unfetched_trails(
    pool: &PgPool,
    limit: i64,
) -> Result<Vec<UnfetchedTrail>, sqlx::Error> {
    sqlx::query_as::<_, UnfetchedTrail>(
        r#"
        SELECT c.trail_reference as reference, c.trail_name as name,
               c.states as location_desc, c.managing_agency, c.ntir_service
        FROM historic_trail_catalog c
        LEFT JOIN historic_trails t ON c.trail_reference = t.trail_reference
        WHERE t.trail_reference IS NULL
          AND c.consecutive_errors < 3
        ORDER BY c.trail_reference
        LIMIT $1
        "#,
    )
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Get stale trail boundaries for re-fetching.
pub async fn get_stale_trails(
    pool: &PgPool,
    stale_days: i64,
    limit: i64,
) -> Result<Vec<StaleTrail>, sqlx::Error> {
    sqlx::query_as::<_, StaleTrail>(
        r#"
        SELECT t.trail_reference as reference, c.trail_name as name,
               c.states as location_desc, c.managing_agency, c.ntir_service
        FROM historic_trails t
        JOIN historic_trail_catalog c ON c.trail_reference = t.trail_reference
        WHERE t.fetched_at < NOW() - make_interval(days => $1::int)
        ORDER BY t.fetched_at ASC
        LIMIT $2
        "#,
    )
    .bind(stale_days)
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Get trail sync status statistics.
pub async fn get_trail_status(pool: &PgPool) -> Result<TrailStatusRow, sqlx::Error> {
    sqlx::query_as::<_, TrailStatusRow>(
        r#"
        SELECT
            (SELECT COUNT(*) FROM historic_trails) as total_cached,
            (SELECT COUNT(*) FROM historic_trail_catalog) as total_catalog,
            (SELECT COUNT(*) FROM historic_trails WHERE match_quality = 'exact') as exact_matches,
            (SELECT COUNT(*) FROM historic_trails WHERE match_quality = 'spatial') as spatial_matches,
            (SELECT COUNT(*) FROM historic_trails WHERE match_quality = 'manual') as manual_matches,
            (SELECT MIN(fetched_at) FROM historic_trails) as oldest_fetch,
            (SELECT MAX(fetched_at) FROM historic_trails) as newest_fetch
        "#,
    )
    .fetch_one(pool)
    .await
}

/// Increment consecutive error counter for a trail that failed to fetch.
pub async fn increment_trail_errors(
    pool: &PgPool,
    trail_reference: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE historic_trail_catalog
        SET consecutive_errors = consecutive_errors + 1
        WHERE trail_reference = $1
        "#,
    )
    .bind(trail_reference)
    .execute(pool)
    .await?;
    Ok(())
}

/// Reset consecutive error counters for all trails (called at the start of
/// each cycle so previously-failing trails get another chance periodically).
pub async fn reset_trail_consecutive_errors(pool: &PgPool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        "UPDATE historic_trail_catalog SET consecutive_errors = 0 WHERE consecutive_errors > 0",
    )
    .execute(pool)
    .await?;
    Ok(result.rows_affected())
}

#[derive(Debug, sqlx::FromRow)]
pub struct TrailStatusRow {
    pub total_cached: i64,
    pub total_catalog: i64,
    pub exact_matches: i64,
    pub spatial_matches: i64,
    pub manual_matches: i64,
    pub oldest_fetch: Option<chrono::DateTime<chrono::Utc>>,
    pub newest_fetch: Option<chrono::DateTime<chrono::Utc>>,
}

#[allow(dead_code)]
#[derive(Debug, sqlx::FromRow)]
pub struct UnfetchedTrail {
    pub reference: String,
    pub name: String,
    pub location_desc: Option<String>,
    pub managing_agency: Option<String>,
    pub ntir_service: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, sqlx::FromRow)]
pub struct StaleTrail {
    pub reference: String,
    pub name: String,
    pub location_desc: Option<String>,
    pub managing_agency: Option<String>,
    pub ntir_service: Option<String>,
}
