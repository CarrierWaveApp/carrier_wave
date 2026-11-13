use chrono::NaiveDate;
use sqlx::PgPool;

use crate::error::AppError;
use crate::models::pota_stats::{
    FreshnessRow, PotaParkRow, RankedActivatorByModeRow, RankedActivatorRow, RankedHunterRow,
    StaleParkRow, StateAggregateRow, TopCallsignRow,
};

// ---------------------------------------------------------------------------
// Aggregator support
// ---------------------------------------------------------------------------

/// Upsert a park from the CSV catalog.
#[allow(clippy::too_many_arguments)]
pub async fn upsert_park(
    pool: &PgPool,
    reference: &str,
    name: &str,
    location_desc: Option<&str>,
    state: Option<&str>,
    latitude: Option<f64>,
    longitude: Option<f64>,
    grid: Option<&str>,
    active: bool,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO pota_parks (reference, name, location_desc, state, latitude, longitude, grid, active)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (reference) DO UPDATE SET
            name = EXCLUDED.name,
            location_desc = EXCLUDED.location_desc,
            state = EXCLUDED.state,
            latitude = EXCLUDED.latitude,
            longitude = EXCLUDED.longitude,
            grid = EXCLUDED.grid,
            active = EXCLUDED.active,
            updated_at = now()
        "#,
    )
    .bind(reference)
    .bind(name)
    .bind(location_desc)
    .bind(state)
    .bind(latitude)
    .bind(longitude)
    .bind(grid)
    .bind(active)
    .execute(pool)
    .await?;

    Ok(())
}

/// Ensure a fetch_status row exists for a park.
pub async fn ensure_fetch_status(pool: &PgPool, park_reference: &str) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO pota_fetch_status (park_reference)
        VALUES ($1)
        ON CONFLICT (park_reference) DO NOTHING
        "#,
    )
    .bind(park_reference)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get the stalest parks (oldest activations_fetched_at, NULLs first).
/// Skips parks with 3+ consecutive fetch errors.
pub async fn get_stalest_parks(
    pool: &PgPool,
    batch_size: i64,
) -> Result<Vec<StaleParkRow>, AppError> {
    let rows = sqlx::query_as::<_, StaleParkRow>(
        r#"
        SELECT park_reference
        FROM pota_fetch_status
        WHERE consecutive_errors < 3
        ORDER BY activations_fetched_at ASC NULLS FIRST
        LIMIT $1
        "#,
    )
    .bind(batch_size)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Count US parks (reference starts with "US-").
pub async fn count_parks(pool: &PgPool) -> Result<i64, AppError> {
    let count = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM pota_parks")
        .fetch_one(pool)
        .await?;

    Ok(count)
}

/// Count parks that have never been fetched.
pub async fn count_unfetched_parks(pool: &PgPool) -> Result<i64, AppError> {
    let count = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM pota_fetch_status WHERE activations_fetched_at IS NULL",
    )
    .fetch_one(pool)
    .await?;

    Ok(count)
}

/// Update park aggregate stats from /park/stats response.
pub async fn update_park_stats(
    pool: &PgPool,
    reference: &str,
    attempts: i32,
    activations: i32,
    contacts: i32,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE pota_parks
        SET total_attempts = $2,
            total_activations = $3,
            total_qsos = $4,
            stats_fetched_at = now(),
            updated_at = now()
        WHERE reference = $1
        "#,
    )
    .bind(reference)
    .bind(attempts)
    .bind(activations)
    .bind(contacts)
    .execute(pool)
    .await?;

    Ok(())
}

/// Upsert a single activation record.
#[allow(clippy::too_many_arguments)]
pub async fn upsert_activation(
    pool: &PgPool,
    park_reference: &str,
    callsign: &str,
    qso_date: NaiveDate,
    total_qsos: i32,
    qsos_cw: i32,
    qsos_data: i32,
    qsos_phone: i32,
    state: Option<&str>,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO pota_activations (park_reference, callsign, qso_date, total_qsos, qsos_cw, qsos_data, qsos_phone, state)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (park_reference, callsign, qso_date) DO UPDATE SET
            total_qsos = EXCLUDED.total_qsos,
            qsos_cw = EXCLUDED.qsos_cw,
            qsos_data = EXCLUDED.qsos_data,
            qsos_phone = EXCLUDED.qsos_phone,
            state = EXCLUDED.state
        "#,
    )
    .bind(park_reference)
    .bind(callsign)
    .bind(qso_date)
    .bind(total_qsos)
    .bind(qsos_cw)
    .bind(qsos_data)
    .bind(qsos_phone)
    .bind(state)
    .execute(pool)
    .await?;

    Ok(())
}

/// Upsert hunter QSO records from leaderboard data.
pub async fn upsert_hunter_qsos(
    pool: &PgPool,
    park_reference: &str,
    callsign: &str,
    qso_count: i32,
    state: Option<&str>,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO pota_hunter_qsos (park_reference, callsign, qso_count, state)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (park_reference, callsign) DO UPDATE SET
            qso_count = EXCLUDED.qso_count,
            state = EXCLUDED.state
        "#,
    )
    .bind(park_reference)
    .bind(callsign)
    .bind(qso_count)
    .bind(state)
    .execute(pool)
    .await?;

    Ok(())
}

/// Mark a park as successfully fetched (resets consecutive error counter).
pub async fn update_fetch_status(
    pool: &PgPool,
    park_reference: &str,
    activations_fetched: bool,
    leaderboard_fetched: bool,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE pota_fetch_status
        SET activations_fetched_at = CASE WHEN $2 THEN now() ELSE activations_fetched_at END,
            leaderboard_fetched_at = CASE WHEN $3 THEN now() ELSE leaderboard_fetched_at END,
            fetch_error = NULL,
            consecutive_errors = 0,
            updated_at = now()
        WHERE park_reference = $1
        "#,
    )
    .bind(park_reference)
    .bind(activations_fetched)
    .bind(leaderboard_fetched)
    .execute(pool)
    .await?;

    Ok(())
}

/// Record a fetch error for a park (increments consecutive error counter).
pub async fn record_fetch_error(
    pool: &PgPool,
    park_reference: &str,
    error: &str,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE pota_fetch_status
        SET fetch_error = $2,
            consecutive_errors = consecutive_errors + 1,
            updated_at = now()
        WHERE park_reference = $1
        "#,
    )
    .bind(park_reference)
    .bind(error)
    .execute(pool)
    .await?;

    Ok(())
}

/// Reset consecutive error counters for all parks (called during catalog re-sync
/// so that previously-failing parks get another chance each cycle).
pub async fn reset_consecutive_errors(pool: &PgPool) -> Result<u64, AppError> {
    let result = sqlx::query(
        "UPDATE pota_fetch_status SET consecutive_errors = 0 WHERE consecutive_errors > 0",
    )
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}

// ---------------------------------------------------------------------------
// API support
// ---------------------------------------------------------------------------

/// Get activator stats with rank, optionally filtered by state.
pub async fn get_activator_stats(
    pool: &PgPool,
    callsign: &str,
    state: Option<&str>,
) -> Result<Option<RankedActivatorRow>, AppError> {
    let row = sqlx::query_as::<_, RankedActivatorRow>(
        r#"
        WITH totals AS (
            SELECT callsign,
                   COUNT(*) AS activation_count,
                   COALESCE(SUM(total_qsos), 0) AS total_qsos,
                   COALESCE(SUM(qsos_cw), 0) AS total_cw,
                   COALESCE(SUM(qsos_data), 0) AS total_data,
                   COALESCE(SUM(qsos_phone), 0) AS total_phone
            FROM pota_activations
            WHERE ($2::text IS NULL OR state = $2)
            GROUP BY callsign
        ),
        ranked AS (
            SELECT *,
                   DENSE_RANK() OVER (ORDER BY activation_count DESC) AS rank,
                   COUNT(*) OVER () AS total_ranked
            FROM totals
        )
        SELECT callsign, activation_count, total_qsos, total_cw, total_data, total_phone, rank, total_ranked
        FROM ranked
        WHERE callsign = $1
        "#,
    )
    .bind(callsign)
    .bind(state)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Get activator stats ranked by a specific mode.
pub async fn get_activator_stats_by_mode(
    pool: &PgPool,
    callsign: &str,
    mode_column: &str, // "qsos_cw", "qsos_data", or "qsos_phone"
    state: Option<&str>,
) -> Result<Option<RankedActivatorByModeRow>, AppError> {
    // Build query dynamically based on mode column. The column name is validated
    // by the handler so this is safe from injection.
    let query = format!(
        r#"
        WITH totals AS (
            SELECT callsign, SUM({col}) AS mode_qsos
            FROM pota_activations
            WHERE {col} > 0
              AND ($2::text IS NULL OR state = $2)
            GROUP BY callsign
        ),
        ranked AS (
            SELECT *,
                   DENSE_RANK() OVER (ORDER BY mode_qsos DESC) AS rank,
                   COUNT(*) OVER () AS total_ranked
            FROM totals
        )
        SELECT callsign, mode_qsos, rank, total_ranked
        FROM ranked
        WHERE callsign = $1
        "#,
        col = mode_column
    );

    let row = sqlx::query_as::<_, RankedActivatorByModeRow>(&query)
        .bind(callsign)
        .bind(state)
        .fetch_optional(pool)
        .await?;

    Ok(row)
}

/// Get paginated activator rankings, optionally filtered by state.
pub async fn get_activator_rankings(
    pool: &PgPool,
    state: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<(Vec<RankedActivatorRow>, i64), AppError> {
    // First get total count
    let total_ranked = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(DISTINCT callsign)
        FROM pota_activations
        WHERE ($1::text IS NULL OR state = $1)
        "#,
    )
    .bind(state)
    .fetch_one(pool)
    .await?;

    let rows = sqlx::query_as::<_, RankedActivatorRow>(
        r#"
        WITH totals AS (
            SELECT callsign,
                   COUNT(*) AS activation_count,
                   COALESCE(SUM(total_qsos), 0) AS total_qsos,
                   COALESCE(SUM(qsos_cw), 0) AS total_cw,
                   COALESCE(SUM(qsos_data), 0) AS total_data,
                   COALESCE(SUM(qsos_phone), 0) AS total_phone
            FROM pota_activations
            WHERE ($1::text IS NULL OR state = $1)
            GROUP BY callsign
        ),
        ranked AS (
            SELECT *,
                   DENSE_RANK() OVER (ORDER BY activation_count DESC) AS rank,
                   COUNT(*) OVER () AS total_ranked
            FROM totals
        )
        SELECT callsign, activation_count, total_qsos, total_cw, total_data, total_phone, rank, total_ranked
        FROM ranked
        ORDER BY rank ASC, callsign ASC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(state)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok((rows, total_ranked))
}

/// Get hunter stats with rank, optionally filtered by state.
pub async fn get_hunter_stats(
    pool: &PgPool,
    callsign: &str,
    state: Option<&str>,
) -> Result<Option<RankedHunterRow>, AppError> {
    let row = sqlx::query_as::<_, RankedHunterRow>(
        r#"
        WITH totals AS (
            SELECT callsign,
                   COALESCE(SUM(qso_count), 0) AS total_qsos
            FROM pota_hunter_qsos
            WHERE ($2::text IS NULL OR state = $2)
            GROUP BY callsign
        ),
        ranked AS (
            SELECT *,
                   DENSE_RANK() OVER (ORDER BY total_qsos DESC) AS rank,
                   COUNT(*) OVER () AS total_ranked
            FROM totals
        )
        SELECT callsign, total_qsos, rank, total_ranked
        FROM ranked
        WHERE callsign = $1
        "#,
    )
    .bind(callsign)
    .bind(state)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Get aggregate state-level stats.
pub async fn get_state_stats(
    pool: &PgPool,
    state: &str,
) -> Result<Option<StateAggregateRow>, AppError> {
    let row = sqlx::query_as::<_, StateAggregateRow>(
        r#"
        SELECT COUNT(*) AS total_activations,
               COUNT(DISTINCT callsign) AS unique_activators,
               COALESCE(SUM(total_qsos), 0) AS total_qsos
        FROM pota_activations
        WHERE state = $1
        "#,
    )
    .bind(state)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Get top activators for a state (by activation count).
pub async fn get_state_top_activators(
    pool: &PgPool,
    state: &str,
    limit: i64,
) -> Result<Vec<TopCallsignRow>, AppError> {
    let rows = sqlx::query_as::<_, TopCallsignRow>(
        r#"
        SELECT callsign, COUNT(*) AS count
        FROM pota_activations
        WHERE state = $1
        GROUP BY callsign
        ORDER BY count DESC
        LIMIT $2
        "#,
    )
    .bind(state)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Get top hunters for a state (by QSO count).
pub async fn get_state_top_hunters(
    pool: &PgPool,
    state: &str,
    limit: i64,
) -> Result<Vec<TopCallsignRow>, AppError> {
    let rows = sqlx::query_as::<_, TopCallsignRow>(
        r#"
        SELECT callsign, COALESCE(SUM(qso_count), 0) AS count
        FROM pota_hunter_qsos
        WHERE state = $1
        GROUP BY callsign
        ORDER BY count DESC
        LIMIT $2
        "#,
    )
    .bind(state)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Get freshness info for a state scope.
pub async fn get_state_freshness(pool: &PgPool, state: &str) -> Result<FreshnessRow, AppError> {
    let row = sqlx::query_as::<_, FreshnessRow>(
        r#"
        SELECT
            MIN(fs.activations_fetched_at) AS oldest_fetch,
            MAX(fs.activations_fetched_at) AS newest_fetch,
            COUNT(*) FILTER (WHERE fs.activations_fetched_at IS NULL) AS parks_pending,
            COUNT(*) AS total_parks
        FROM pota_parks p
        JOIN pota_fetch_status fs ON fs.park_reference = p.reference
        WHERE p.state = $1
        "#,
    )
    .bind(state)
    .fetch_one(pool)
    .await?;

    Ok(row)
}

/// Get a single park row by reference.
pub async fn get_park_detail(
    pool: &PgPool,
    reference: &str,
) -> Result<Option<PotaParkRow>, AppError> {
    let row = sqlx::query_as::<_, PotaParkRow>(
        r#"
        SELECT reference, name, location_desc, state, latitude, longitude, grid,
               active, total_attempts, total_activations, total_qsos,
               stats_fetched_at, created_at, updated_at
        FROM pota_parks
        WHERE reference = $1
        "#,
    )
    .bind(reference)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Get top activators for a specific park.
pub async fn get_park_top_activators(
    pool: &PgPool,
    park_reference: &str,
    limit: i64,
) -> Result<Vec<TopCallsignRow>, AppError> {
    let rows = sqlx::query_as::<_, TopCallsignRow>(
        r#"
        SELECT callsign, COUNT(*) AS count
        FROM pota_activations
        WHERE park_reference = $1
        GROUP BY callsign
        ORDER BY count DESC
        LIMIT $2
        "#,
    )
    .bind(park_reference)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Get top hunters for a specific park.
pub async fn get_park_top_hunters(
    pool: &PgPool,
    park_reference: &str,
    limit: i64,
) -> Result<Vec<TopCallsignRow>, AppError> {
    let rows = sqlx::query_as::<_, TopCallsignRow>(
        r#"
        SELECT callsign, qso_count AS count
        FROM pota_hunter_qsos
        WHERE park_reference = $1
        ORDER BY count DESC
        LIMIT $2
        "#,
    )
    .bind(park_reference)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Get freshness info for a single park.
pub async fn get_park_freshness(
    pool: &PgPool,
    park_reference: &str,
) -> Result<FreshnessRow, AppError> {
    let row = sqlx::query_as::<_, FreshnessRow>(
        r#"
        SELECT
            fs.activations_fetched_at AS oldest_fetch,
            fs.activations_fetched_at AS newest_fetch,
            CASE WHEN fs.activations_fetched_at IS NULL THEN 1::bigint ELSE 0::bigint END AS parks_pending,
            1::bigint AS total_parks
        FROM pota_fetch_status fs
        WHERE fs.park_reference = $1
        "#,
    )
    .bind(park_reference)
    .fetch_optional(pool)
    .await?
    .unwrap_or(FreshnessRow {
        oldest_fetch: None,
        newest_fetch: None,
        parks_pending: 1,
        total_parks: 1,
    });

    Ok(row)
}

/// Get freshness info scoped to activator queries (optionally by state).
pub async fn get_activator_freshness(
    pool: &PgPool,
    state: Option<&str>,
) -> Result<FreshnessRow, AppError> {
    let row = sqlx::query_as::<_, FreshnessRow>(
        r#"
        SELECT
            MIN(fs.activations_fetched_at) AS oldest_fetch,
            MAX(fs.activations_fetched_at) AS newest_fetch,
            COUNT(*) FILTER (WHERE fs.activations_fetched_at IS NULL) AS parks_pending,
            COUNT(*) AS total_parks
        FROM pota_parks p
        JOIN pota_fetch_status fs ON fs.park_reference = p.reference
        WHERE ($1::text IS NULL OR p.state = $1)
        "#,
    )
    .bind(state)
    .fetch_one(pool)
    .await?;

    Ok(row)
}
