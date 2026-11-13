use chrono::{DateTime, Duration, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::spot::{AggregatedSpot, SpotRow, SpotSource};

/// Query parameters for listing spots (pre-validated by handler).
pub struct ListSpotsParams {
    pub program: Option<String>,
    pub callsign: Option<String>,
    pub source: Option<SpotSource>,
    pub mode: Option<String>,
    pub state: Option<String>,
    pub max_age_minutes: i64,
    pub limit: i64,
    pub cursor: Option<DateTime<Utc>>,
}

/// List active spots with filters and cursor pagination.
/// Returns up to `limit + 1` rows so the caller can determine `has_more`.
pub async fn list_spots(pool: &PgPool, params: &ListSpotsParams) -> Result<Vec<SpotRow>, AppError> {
    let cutoff = Utc::now() - Duration::minutes(params.max_age_minutes);

    // Reference coordinates: POTA parks from the catalog; SOTA summits
    // best-effort from cached activation-zone centroids (no summit catalog
    // server-side). Joined on program_slug so self-spots resolve too.
    let rows = sqlx::query_as::<_, SpotRow>(
        r#"
        SELECT s.id, s.callsign, s.program_slug, s.source, s.external_id,
               s.frequency_khz, s.mode, s.reference, s.reference_name,
               s.spotter, s.spotter_grid, s.location_desc, s.country_code, s.state_abbr,
               s.comments, s.snr, s.wpm, s.submitted_by,
               s.spotted_at, s.expires_at, s.created_at, s.updated_at,
               COALESCE(p.latitude, ST_Y(ST_Centroid(z.geometry_simplified))) AS ref_latitude,
               COALESCE(p.longitude, ST_X(ST_Centroid(z.geometry_simplified))) AS ref_longitude
        FROM spots s
        LEFT JOIN pota_parks p
               ON s.program_slug = 'pota' AND s.reference = p.reference
        LEFT JOIN sota_activation_zones z
               ON s.program_slug = 'sota' AND s.reference = z.summit_code AND z.status = 'ok'
        WHERE s.expires_at > now()
          AND s.spotted_at >= $1
          AND ($2::text IS NULL OR s.program_slug = $2)
          AND ($3::text IS NULL OR s.callsign = $3)
          AND ($4::spot_source IS NULL OR s.source = $4)
          AND ($5::text IS NULL OR s.mode = $5)
          AND ($6::text IS NULL OR s.state_abbr = $6)
          AND ($7::timestamptz IS NULL OR s.spotted_at < $7)
        ORDER BY s.spotted_at DESC
        LIMIT $8
        "#,
    )
    .bind(cutoff)
    .bind(&params.program)
    .bind(&params.callsign)
    .bind(&params.source)
    .bind(&params.mode)
    .bind(&params.state)
    .bind(params.cursor)
    .bind(params.limit + 1)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Parameters for creating a self-spot.
pub struct InsertSelfSpotParams<'a> {
    pub participant_id: Uuid,
    pub callsign: &'a str,
    pub program_slug: &'a str,
    pub frequency_khz: f64,
    pub mode: &'a str,
    pub reference: Option<&'a str>,
    pub comments: Option<&'a str>,
}

/// Insert a self-spot. Enforces one unexpired self-spot per user+program.
pub async fn insert_self_spot(
    pool: &PgPool,
    params: &InsertSelfSpotParams<'_>,
) -> Result<SpotRow, AppError> {
    // Check for existing unexpired self-spot
    let existing = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM spots
        WHERE submitted_by = $1
          AND program_slug = $2
          AND source = 'self'
          AND expires_at > now()
        "#,
    )
    .bind(params.participant_id)
    .bind(params.program_slug)
    .fetch_one(pool)
    .await?;

    if existing > 0 {
        return Err(AppError::SelfSpotExists);
    }

    let expires_at = Utc::now() + Duration::minutes(30);

    let row = sqlx::query_as::<_, SpotRow>(
        r#"
        INSERT INTO spots (
            callsign, program_slug, source, frequency_khz, mode,
            reference, comments, submitted_by, spotted_at, expires_at
        )
        VALUES ($1, $2, 'self', $3, $4, $5, $6, $7, now(), $8)
        RETURNING id, callsign, program_slug, source, external_id,
                  frequency_khz, mode, reference, reference_name,
                  spotter, spotter_grid, location_desc, country_code, state_abbr,
                  comments, snr, wpm, submitted_by,
                  spotted_at, expires_at, created_at, updated_at
        "#,
    )
    .bind(params.callsign)
    .bind(params.program_slug)
    .bind(params.frequency_khz)
    .bind(params.mode)
    .bind(params.reference)
    .bind(params.comments)
    .bind(params.participant_id)
    .bind(expires_at)
    .fetch_one(pool)
    .await?;

    Ok(row)
}

/// Get a single spot by ID.
#[allow(dead_code)]
pub async fn get_spot(pool: &PgPool, spot_id: Uuid) -> Result<Option<SpotRow>, AppError> {
    let row = sqlx::query_as::<_, SpotRow>(
        r#"
        SELECT id, callsign, program_slug, source, external_id,
               frequency_khz, mode, reference, reference_name,
               spotter, spotter_grid, location_desc, country_code, state_abbr,
               comments, snr, wpm, submitted_by,
               spotted_at, expires_at, created_at, updated_at
        FROM spots
        WHERE id = $1
        "#,
    )
    .bind(spot_id)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Delete a spot by ID, verifying ownership (submitted_by must match).
pub async fn delete_own_spot(
    pool: &PgPool,
    spot_id: Uuid,
    participant_id: Uuid,
) -> Result<bool, AppError> {
    let result = sqlx::query(
        r#"
        DELETE FROM spots
        WHERE id = $1 AND submitted_by = $2
        "#,
    )
    .bind(spot_id)
    .bind(participant_id)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}

/// Admin delete: remove any spot by ID.
pub async fn admin_delete_spot(pool: &PgPool, spot_id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM spots WHERE id = $1")
        .bind(spot_id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}

/// Delete all expired spots. Returns count of deleted rows.
pub async fn delete_expired_spots(pool: &PgPool) -> Result<u64, AppError> {
    let result = sqlx::query("DELETE FROM spots WHERE expires_at < now()")
        .execute(pool)
        .await?;

    Ok(result.rows_affected())
}

/// Upsert an aggregated spot from an external source.
/// Uses (source, external_id) for conflict resolution.
pub async fn upsert_aggregated_spot(
    pool: &PgPool,
    spot: &AggregatedSpot,
) -> Result<SpotRow, AppError> {
    let row = sqlx::query_as::<_, SpotRow>(
        r#"
        INSERT INTO spots (
            callsign, program_slug, source, external_id,
            frequency_khz, mode, reference, reference_name,
            spotter, spotter_grid, location_desc, country_code, state_abbr,
            comments, snr, wpm,
            spotted_at, expires_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
        ON CONFLICT (source, external_id) WHERE external_id IS NOT NULL
        DO UPDATE SET
            frequency_khz = EXCLUDED.frequency_khz,
            mode = EXCLUDED.mode,
            reference = EXCLUDED.reference,
            reference_name = EXCLUDED.reference_name,
            comments = EXCLUDED.comments,
            updated_at = now()
        RETURNING id, callsign, program_slug, source, external_id,
                  frequency_khz, mode, reference, reference_name,
                  spotter, spotter_grid, location_desc, country_code, state_abbr,
                  comments, snr, wpm, submitted_by,
                  spotted_at, expires_at, created_at, updated_at
        "#,
    )
    .bind(&spot.callsign)
    .bind(&spot.program_slug)
    .bind(&spot.source)
    .bind(&spot.external_id)
    .bind(spot.frequency_khz)
    .bind(&spot.mode)
    .bind(&spot.reference)
    .bind(&spot.reference_name)
    .bind(&spot.spotter)
    .bind(&spot.spotter_grid)
    .bind(&spot.location_desc)
    .bind(&spot.country_code)
    .bind(&spot.state_abbr)
    .bind(&spot.comments)
    .bind(spot.snr)
    .bind(spot.wpm)
    .bind(spot.spotted_at)
    .bind(spot.expires_at)
    .fetch_one(pool)
    .await?;

    Ok(row)
}
