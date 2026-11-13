use sqlx::PgPool;

use crate::models::park_boundary::ParkBoundaryRow;

/// Get boundaries by POTA references, using simplified geometry.
pub async fn get_boundaries_by_refs(
    pool: &PgPool,
    refs: &[String],
) -> Result<Vec<ParkBoundaryRow>, sqlx::Error> {
    sqlx::query_as::<_, ParkBoundaryRow>(
        r#"
        SELECT pota_reference, park_name, designation, manager, acreage,
               match_quality, source,
               ST_AsGeoJSON(geometry_simplified) as geometry_json
        FROM park_boundaries
        WHERE pota_reference = ANY($1)
          AND match_quality != 'none'
        "#,
    )
    .bind(refs)
    .fetch_all(pool)
    .await
}

/// Get a single boundary by reference with full-resolution geometry.
pub async fn get_boundary_by_ref(
    pool: &PgPool,
    reference: &str,
) -> Result<Option<ParkBoundaryRow>, sqlx::Error> {
    sqlx::query_as::<_, ParkBoundaryRow>(
        r#"
        SELECT pota_reference, park_name, designation, manager, acreage,
               match_quality, source,
               ST_AsGeoJSON(geometry) as geometry_json
        FROM park_boundaries
        WHERE pota_reference = $1
          AND match_quality != 'none'
        "#,
    )
    .bind(reference)
    .fetch_optional(pool)
    .await
}

/// Get boundaries within a bounding box, using simplified geometry.
pub async fn get_boundaries_by_bbox(
    pool: &PgPool,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
    limit: i64,
) -> Result<Vec<ParkBoundaryRow>, sqlx::Error> {
    sqlx::query_as::<_, ParkBoundaryRow>(
        r#"
        SELECT pota_reference, park_name, designation, manager, acreage,
               match_quality, source,
               ST_AsGeoJSON(geometry_simplified) as geometry_json
        FROM park_boundaries
        WHERE geometry_simplified && ST_MakeEnvelope($1, $2, $3, $4, 4326)
        ORDER BY pota_reference
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

/// Get boundaries within a bounding box with custom simplification tolerance.
pub async fn get_boundaries_by_bbox_simplified(
    pool: &PgPool,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
    limit: i64,
    simplify_tolerance: f64,
) -> Result<Vec<ParkBoundaryRow>, sqlx::Error> {
    sqlx::query_as::<_, ParkBoundaryRow>(
        r#"
        SELECT pota_reference, park_name, designation, manager, acreage,
               match_quality, source,
               ST_AsGeoJSON(ST_Simplify(geometry, $6)) as geometry_json
        FROM park_boundaries
        WHERE geometry_simplified && ST_MakeEnvelope($1, $2, $3, $4, 4326)
        ORDER BY pota_reference
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

/// Upsert a park boundary from ArcGIS data.
#[allow(clippy::too_many_arguments)]
pub async fn upsert_boundary(
    pool: &PgPool,
    pota_reference: &str,
    park_name: &str,
    designation: Option<&str>,
    manager: Option<&str>,
    acreage: Option<f64>,
    match_quality: &str,
    geojson: &str,
    source: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO park_boundaries
            (pota_reference, park_name, designation, manager, acreage,
             match_quality, geometry, geometry_simplified, source,
             fetched_at, matched_at)
        VALUES ($1, $2, $3, $4, $5, $6,
                ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($7), 3)),
                ST_Simplify(ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($7), 3)), 0.001),
                $8, NOW(), NOW())
        ON CONFLICT (pota_reference) DO UPDATE SET
            park_name = EXCLUDED.park_name,
            designation = EXCLUDED.designation,
            manager = EXCLUDED.manager,
            acreage = EXCLUDED.acreage,
            match_quality = EXCLUDED.match_quality,
            geometry = EXCLUDED.geometry,
            geometry_simplified = EXCLUDED.geometry_simplified,
            source = EXCLUDED.source,
            fetched_at = NOW()
        "#,
    )
    .bind(pota_reference)
    .bind(park_name)
    .bind(designation)
    .bind(manager)
    .bind(acreage)
    .bind(match_quality)
    .bind(geojson)
    .bind(source)
    .execute(pool)
    .await?;
    Ok(())
}

/// Record that a park was attempted but no boundary was found.
/// Inserts a row with NULL geometry and match_quality='none' so the park
/// is excluded from the unfetched queue. It will be retried during stale
/// boundary refresh cycles.
pub async fn upsert_no_match(
    pool: &PgPool,
    pota_reference: &str,
    park_name: &str,
    source: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO park_boundaries
            (pota_reference, park_name, match_quality, geometry, geometry_simplified,
             source, fetched_at, matched_at)
        VALUES ($1, $2, 'none', NULL, NULL, $3, NOW(), NOW())
        ON CONFLICT (pota_reference) DO UPDATE SET
            park_name = EXCLUDED.park_name,
            match_quality = EXCLUDED.match_quality,
            geometry = NULL,
            geometry_simplified = NULL,
            source = EXCLUDED.source,
            fetched_at = NOW()
        -- CAR-327: only overwrite a row that is ALREADY a no-match sentinel. A
        -- NoMatch is frequently transient (ArcGIS 200-with-error body, a misrouted
        -- foreign park, a WAF page), so blindly NULLing geometry here permanently
        -- destroyed boundaries that had been fetched successfully. Preserve any
        -- existing good geometry; a genuine removal will be reflected by a
        -- successful re-fetch, not by a no-match.
        WHERE park_boundaries.match_quality = 'none'
        "#,
    )
    .bind(pota_reference)
    .bind(park_name)
    .bind(source)
    .execute(pool)
    .await?;
    Ok(())
}

/// Count total cached boundaries (excludes no-match sentinel rows).
pub async fn count_boundaries(pool: &PgPool) -> Result<i64, sqlx::Error> {
    let row: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM park_boundaries WHERE match_quality != 'none'")
            .fetch_one(pool)
            .await?;
    Ok(row.0)
}

/// Get references that need fetching (no boundary row yet).
/// Includes US, UK (G-), and Italian (I-) parks.
pub async fn get_unfetched_parks(
    pool: &PgPool,
    limit: i64,
) -> Result<Vec<UnfetchedPark>, sqlx::Error> {
    sqlx::query_as::<_, UnfetchedPark>(
        r#"
        SELECT p.reference, p.name, p.location_desc, p.latitude, p.longitude
        FROM pota_parks p
        LEFT JOIN park_boundaries b ON p.reference = b.pota_reference
        WHERE b.pota_reference IS NULL
          AND (p.reference LIKE 'US-%'
               OR p.reference LIKE 'GB-%'
               OR p.reference LIKE 'IT-%')
          AND p.active = true
        ORDER BY p.reference
        LIMIT $1
        "#,
    )
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Get Polish (SP-) parks that need fetching (no boundary row yet).
pub async fn get_unfetched_polish_parks(
    pool: &PgPool,
    limit: i64,
) -> Result<Vec<UnfetchedPark>, sqlx::Error> {
    sqlx::query_as::<_, UnfetchedPark>(
        r#"
        SELECT p.reference, p.name, p.location_desc, p.latitude, p.longitude
        FROM pota_parks p
        LEFT JOIN park_boundaries b ON p.reference = b.pota_reference
        WHERE b.pota_reference IS NULL
          AND p.reference LIKE 'PL-%'
          AND p.active = true
        ORDER BY p.reference
        LIMIT $1
        "#,
    )
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Get stale boundaries (older than given days) for re-fetching.
pub async fn get_stale_boundaries(
    pool: &PgPool,
    stale_days: i64,
    limit: i64,
) -> Result<Vec<StaleBoundary>, sqlx::Error> {
    sqlx::query_as::<_, StaleBoundary>(
        r#"
        SELECT b.pota_reference as reference, p.name, p.location_desc,
               p.latitude, p.longitude
        FROM park_boundaries b
        JOIN pota_parks p ON p.reference = b.pota_reference
        WHERE b.fetched_at < NOW() - make_interval(days => $1::int)
        ORDER BY b.fetched_at ASC
        LIMIT $2
        "#,
    )
    .bind(stale_days)
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Get boundary sync status statistics.
pub async fn get_boundary_status(pool: &PgPool) -> Result<BoundaryStatusRow, sqlx::Error> {
    sqlx::query_as::<_, BoundaryStatusRow>(
        r#"
        SELECT
            (SELECT COUNT(*) FROM park_boundaries WHERE match_quality != 'none') as total_cached,
            (SELECT COUNT(*) FROM pota_parks WHERE reference LIKE 'US-%' AND active = true) as total_us_parks,
            (SELECT COUNT(*) FROM pota_parks WHERE reference LIKE 'GB-%' AND active = true) as total_uk_parks,
            (SELECT COUNT(*) FROM pota_parks WHERE reference LIKE 'IT-%' AND active = true) as total_it_parks,
            (SELECT COUNT(*) FROM pota_parks WHERE reference LIKE 'PL-%' AND active = true) as total_pl_parks,
            (SELECT COUNT(*) FROM park_boundaries WHERE match_quality = 'exact') as exact_matches,
            (SELECT COUNT(*) FROM park_boundaries WHERE match_quality = 'spatial') as spatial_matches,
            (SELECT COUNT(*) FROM park_boundaries WHERE match_quality = 'manual') as manual_matches,
            (SELECT COUNT(*) FROM park_boundaries WHERE match_quality = 'none') as no_match_count,
            (SELECT MIN(fetched_at) FROM park_boundaries WHERE match_quality != 'none') as oldest_fetch,
            (SELECT MAX(fetched_at) FROM park_boundaries WHERE match_quality != 'none') as newest_fetch
        "#,
    )
    .fetch_one(pool)
    .await
}

/// Get boundary counts grouped by source.
pub async fn get_boundary_source_counts(pool: &PgPool) -> Result<Vec<SourceCount>, sqlx::Error> {
    sqlx::query_as::<_, SourceCount>(
        r#"
        SELECT source, COUNT(*) as count
        FROM park_boundaries
        WHERE match_quality != 'none'
        GROUP BY source
        ORDER BY count DESC
        "#,
    )
    .fetch_all(pool)
    .await
}

#[derive(Debug, sqlx::FromRow)]
pub struct SourceCount {
    pub source: String,
    pub count: i64,
}

#[derive(Debug, sqlx::FromRow)]
pub struct BoundaryStatusRow {
    pub total_cached: i64,
    pub total_us_parks: i64,
    pub total_uk_parks: i64,
    pub total_it_parks: i64,
    pub total_pl_parks: i64,
    pub exact_matches: i64,
    pub spatial_matches: i64,
    pub manual_matches: i64,
    pub no_match_count: i64,
    pub oldest_fetch: Option<chrono::DateTime<chrono::Utc>>,
    pub newest_fetch: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, sqlx::FromRow)]
pub struct UnfetchedPark {
    pub reference: String,
    pub name: String,
    pub location_desc: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}

#[derive(Debug, sqlx::FromRow)]
pub struct StaleBoundary {
    pub reference: String,
    pub name: String,
    pub location_desc: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}
