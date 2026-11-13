use sqlx::PgPool;

use crate::error::AppError;
use crate::models::spot_marker::SpotMarkerRow;

/// Generate a short alphanumeric marker code.
pub fn generate_marker() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let chars: Vec<char> = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars().collect();
    (0..6).map(|_| chars[rng.gen_range(0..chars.len())]).collect()
}

/// Create a new spot marker for a participant. Replaces any existing marker for the callsign.
pub async fn create_spot_marker(
    pool: &PgPool,
    callsign: &str,
    participant_id: uuid::Uuid,
) -> Result<SpotMarkerRow, AppError> {
    // Delete any existing markers for this callsign
    sqlx::query("DELETE FROM spot_markers WHERE callsign = $1")
        .bind(callsign)
        .execute(pool)
        .await?;

    let marker = generate_marker();

    let row = sqlx::query_as::<_, SpotMarkerRow>(
        r#"
        INSERT INTO spot_markers (marker, callsign, participant_id)
        VALUES ($1, $2, $3)
        RETURNING id, marker, callsign, participant_id, created_at
        "#,
    )
    .bind(&marker)
    .bind(callsign)
    .bind(participant_id)
    .fetch_one(pool)
    .await?;

    Ok(row)
}

/// Look up a spot marker by its code.
pub async fn get_spot_marker(
    pool: &PgPool,
    marker: &str,
) -> Result<Option<SpotMarkerRow>, AppError> {
    let row = sqlx::query_as::<_, SpotMarkerRow>(
        "SELECT id, marker, callsign, participant_id, created_at FROM spot_markers WHERE marker = $1",
    )
    .bind(marker)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}
