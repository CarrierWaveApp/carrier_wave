use sqlx::PgPool;

use crate::models::sota_zone::SotaZoneRow;

/// Fetch computed ('ok') activation zones for the given summit codes.
pub async fn get_ok_zones_by_codes(
    pool: &PgPool,
    codes: &[String],
) -> Result<Vec<SotaZoneRow>, sqlx::Error> {
    sqlx::query_as::<_, SotaZoneRow>(
        r#"
        SELECT summit_code, altitude_m,
               ST_AsGeoJSON(geometry_simplified) as geometry_json
        FROM sota_activation_zones
        WHERE summit_code = ANY($1)
          AND status = 'ok'
        "#,
    )
    .bind(codes)
    .fetch_all(pool)
    .await
}

/// Return which of the given codes already have a row that should suppress
/// re-enqueue. CAR-337 / CAR-340: a 'pending' sentinel is a compute *lease*, not
/// a permanent marker — if the task that would clear it dies (process restart,
/// panic, dropped from the semaphore queue) the row would otherwise strand the
/// summit forever, since the only transitions out of 'pending' live in that task.
/// Treat a 'pending' row older than the lease window as absent so it is
/// recomputed; 'ok'/'none' and fresh-pending rows still suppress.
pub async fn existing_codes(pool: &PgPool, codes: &[String]) -> Result<Vec<String>, sqlx::Error> {
    let rows: Vec<(String,)> = sqlx::query_as(
        r#"
        SELECT summit_code FROM sota_activation_zones
        WHERE summit_code = ANY($1)
          AND NOT (status = 'pending' AND computed_at < NOW() - INTERVAL '1 hour')
        "#,
    )
    .bind(codes)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|row| row.0).collect())
}

/// Insert a 'pending' sentinel so concurrent requests don't double-enqueue. If a
/// stale-pending lease already exists (its compute task died), re-claim it by
/// refreshing `computed_at`; never disturb an 'ok'/'none' or fresh-pending row.
pub async fn insert_pending(
    pool: &PgPool,
    code: &str,
    altitude_m: Option<f64>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO sota_activation_zones (summit_code, status, altitude_m)
        VALUES ($1, 'pending', $2)
        ON CONFLICT (summit_code) DO UPDATE SET computed_at = NOW()
        WHERE sota_activation_zones.status = 'pending'
          AND sota_activation_zones.computed_at < NOW() - INTERVAL '1 hour'
        "#,
    )
    .bind(code)
    .bind(altitude_m)
    .execute(pool)
    .await?;
    Ok(())
}

/// Store a computed activation-zone polygon (GeoJSON).
pub async fn upsert_ok(
    pool: &PgPool,
    code: &str,
    altitude_m: Option<f64>,
    geojson: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO sota_activation_zones
            (summit_code, status, altitude_m, geometry, geometry_simplified, computed_at)
        VALUES ($1, 'ok', $2,
                ST_GeomFromGeoJSON($3),
                ST_SimplifyPreserveTopology(ST_GeomFromGeoJSON($3), 0.0003),
                NOW())
        ON CONFLICT (summit_code) DO UPDATE SET
            status = 'ok',
            altitude_m = EXCLUDED.altitude_m,
            geometry = EXCLUDED.geometry,
            geometry_simplified = EXCLUDED.geometry_simplified,
            computed_at = NOW()
        "#,
    )
    .bind(code)
    .bind(altitude_m)
    .bind(geojson)
    .execute(pool)
    .await?;
    Ok(())
}

/// Mark a summit as having no usable zone (DEM void / runaway fill).
pub async fn mark_none(pool: &PgPool, code: &str) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE sota_activation_zones
        SET status = 'none', geometry = NULL, geometry_simplified = NULL, computed_at = NOW()
        WHERE summit_code = $1
        "#,
    )
    .bind(code)
    .execute(pool)
    .await?;
    Ok(())
}

/// Remove a row so it can be retried (used after transient compute errors).
pub async fn delete_zone(pool: &PgPool, code: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM sota_activation_zones WHERE summit_code = $1")
        .bind(code)
        .execute(pool)
        .await?;
    Ok(())
}
