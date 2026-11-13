use chrono::{DateTime, Utc};
use sqlx::PgPool;

use crate::error::AppError;
use crate::models::equipment::{
    CreateEquipmentRequest, CreateSubmissionRequest, EquipmentRow, EquipmentSearchRow,
    EquipmentSubmissionRow, UpdateEquipmentRequest,
};

/// Get the catalog version (count of entries) and latest updated_at timestamp.
pub async fn get_catalog_version(pool: &PgPool) -> Result<(i64, DateTime<Utc>), AppError> {
    let row: (i64, Option<DateTime<Utc>>) = sqlx::query_as(
        r#"
        SELECT COUNT(*), MAX(updated_at)
        FROM equipment_catalog
        "#,
    )
    .fetch_one(pool)
    .await?;

    Ok((row.0, row.1.unwrap_or_else(Utc::now)))
}

/// Get all catalog entries, optionally filtered by `since` timestamp.
pub async fn get_catalog_entries(
    pool: &PgPool,
    since: Option<DateTime<Utc>>,
) -> Result<Vec<EquipmentRow>, AppError> {
    let entries = match since {
        Some(since) => {
            sqlx::query_as::<_, EquipmentRow>(
                r#"
                SELECT id, name, manufacturer, category, bands, modes,
                       max_power_watts, portability, weight_grams, description,
                       aliases, image_url, antenna_connector, power_connector,
                       key_jack, mic_jack, created_at, updated_at
                FROM equipment_catalog
                WHERE updated_at > $1
                ORDER BY name ASC
                "#,
            )
            .bind(since)
            .fetch_all(pool)
            .await?
        }
        None => {
            sqlx::query_as::<_, EquipmentRow>(
                r#"
                SELECT id, name, manufacturer, category, bands, modes,
                       max_power_watts, portability, weight_grams, description,
                       aliases, image_url, antenna_connector, power_connector,
                       key_jack, mic_jack, created_at, updated_at
                FROM equipment_catalog
                ORDER BY name ASC
                "#,
            )
            .fetch_all(pool)
            .await?
        }
    };

    Ok(entries)
}

/// Fuzzy search equipment by name, manufacturer, and aliases using pg_trgm.
pub async fn search_equipment(
    pool: &PgPool,
    query: &str,
    category: Option<&str>,
    limit: i64,
) -> Result<Vec<EquipmentSearchRow>, AppError> {
    let results = sqlx::query_as::<_, EquipmentSearchRow>(
        r#"
        SELECT id, name, manufacturer, category, bands, modes,
               max_power_watts, portability, weight_grams, description,
               aliases, image_url, antenna_connector, power_connector,
               key_jack, mic_jack, created_at, updated_at,
               GREATEST(
                   similarity(name, $1),
                   similarity(manufacturer || ' ' || name, $1),
                   similarity(array_to_string(aliases, ' '), $1)
               )::float8 AS score,
               CASE
                   WHEN similarity(name, $1) >= GREATEST(
                       similarity(manufacturer || ' ' || name, $1),
                       similarity(array_to_string(aliases, ' '), $1)
                   ) THEN 'name'
                   WHEN similarity(array_to_string(aliases, ' '), $1) >= similarity(manufacturer || ' ' || name, $1)
                   THEN 'alias'
                   ELSE 'name'
               END AS matched_field
        FROM equipment_catalog
        WHERE GREATEST(
                  similarity(name, $1),
                  similarity(manufacturer || ' ' || name, $1),
                  similarity(array_to_string(aliases, ' '), $1)
              ) > 0.15
          AND ($2::text IS NULL OR category = $2)
        ORDER BY score DESC
        LIMIT $3
        "#,
    )
    .bind(query)
    .bind(category)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(results)
}

/// Get a single equipment entry by ID.
pub async fn get_entry(pool: &PgPool, id: &str) -> Result<Option<EquipmentRow>, AppError> {
    let entry = sqlx::query_as::<_, EquipmentRow>(
        r#"
        SELECT id, name, manufacturer, category, bands, modes,
               max_power_watts, portability, weight_grams, description,
               aliases, image_url, created_at, updated_at
        FROM equipment_catalog
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(entry)
}

/// Create a new equipment entry.
pub async fn create_entry(
    pool: &PgPool,
    req: &CreateEquipmentRequest,
) -> Result<EquipmentRow, AppError> {
    let entry = sqlx::query_as::<_, EquipmentRow>(
        r#"
        INSERT INTO equipment_catalog (
            id, name, manufacturer, category, bands, modes,
            max_power_watts, portability, weight_grams, description,
            aliases, image_url, antenna_connector, power_connector,
            key_jack, mic_jack
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        RETURNING id, name, manufacturer, category, bands, modes,
                  max_power_watts, portability, weight_grams, description,
                  aliases, image_url, antenna_connector, power_connector,
                  key_jack, mic_jack, created_at, updated_at
        "#,
    )
    .bind(&req.id)
    .bind(&req.name)
    .bind(&req.manufacturer)
    .bind(&req.category)
    .bind(&req.bands)
    .bind(&req.modes)
    .bind(req.max_power_watts)
    .bind(&req.portability)
    .bind(req.weight_grams)
    .bind(&req.description)
    .bind(&req.aliases)
    .bind(&req.image_url)
    .bind(&req.antenna_connector)
    .bind(&req.power_connector)
    .bind(&req.key_jack)
    .bind(&req.mic_jack)
    .fetch_one(pool)
    .await?;

    Ok(entry)
}

/// Update an existing equipment entry (partial update).
pub async fn update_entry(
    pool: &PgPool,
    id: &str,
    req: &UpdateEquipmentRequest,
) -> Result<Option<EquipmentRow>, AppError> {
    let entry = sqlx::query_as::<_, EquipmentRow>(
        r#"
        UPDATE equipment_catalog SET
            name = COALESCE($2, name),
            manufacturer = COALESCE($3, manufacturer),
            category = COALESCE($4, category),
            bands = COALESCE($5, bands),
            modes = COALESCE($6, modes),
            max_power_watts = CASE WHEN $7 THEN $8 ELSE max_power_watts END,
            portability = COALESCE($9, portability),
            weight_grams = CASE WHEN $10 THEN $11 ELSE weight_grams END,
            description = CASE WHEN $12 THEN $13 ELSE description END,
            aliases = COALESCE($14, aliases),
            image_url = CASE WHEN $15 THEN $16 ELSE image_url END,
            antenna_connector = CASE WHEN $17 THEN $18 ELSE antenna_connector END,
            power_connector = CASE WHEN $19 THEN $20 ELSE power_connector END,
            key_jack = CASE WHEN $21 THEN $22 ELSE key_jack END,
            mic_jack = CASE WHEN $23 THEN $24 ELSE mic_jack END,
            updated_at = now()
        WHERE id = $1
        RETURNING id, name, manufacturer, category, bands, modes,
                  max_power_watts, portability, weight_grams, description,
                  aliases, image_url, antenna_connector, power_connector,
                  key_jack, mic_jack, created_at, updated_at
        "#,
    )
    .bind(id)
    .bind(&req.name)
    .bind(&req.manufacturer)
    .bind(&req.category)
    .bind(&req.bands)
    .bind(&req.modes)
    .bind(req.max_power_watts.is_some())
    .bind(req.max_power_watts.as_ref().and_then(|v| *v))
    .bind(&req.portability)
    .bind(req.weight_grams.is_some())
    .bind(req.weight_grams.as_ref().and_then(|v| *v))
    .bind(req.description.is_some())
    .bind(req.description.as_ref().and_then(|v| v.clone()))
    .bind(&req.aliases)
    .bind(req.image_url.is_some())
    .bind(req.image_url.as_ref().and_then(|v| v.clone()))
    .bind(req.antenna_connector.is_some())
    .bind(req.antenna_connector.as_ref().and_then(|v| v.clone()))
    .bind(req.power_connector.is_some())
    .bind(req.power_connector.as_ref().and_then(|v| v.clone()))
    .bind(req.key_jack.is_some())
    .bind(req.key_jack.as_ref().and_then(|v| v.clone()))
    .bind(req.mic_jack.is_some())
    .bind(req.mic_jack.as_ref().and_then(|v| v.clone()))
    .fetch_optional(pool)
    .await?;

    Ok(entry)
}

/// Delete an equipment entry by ID.
pub async fn delete_entry(pool: &PgPool, id: &str) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM equipment_catalog WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}

/// Compute a fingerprint for ETag based on count + latest update.
pub async fn get_catalog_fingerprint(pool: &PgPool) -> Result<String, AppError> {
    let (count, max_updated): (i64, Option<DateTime<Utc>>) = sqlx::query_as(
        r#"
        SELECT COUNT(*), MAX(updated_at)
        FROM equipment_catalog
        "#,
    )
    .fetch_one(pool)
    .await?;

    let ts = max_updated
        .map(|t| t.timestamp_millis().to_string())
        .unwrap_or_else(|| "0".to_string());

    Ok(format!("{}-{}", count, ts))
}

// ==================== Submissions ====================

/// Create a new equipment submission for admin review.
pub async fn create_submission(
    pool: &PgPool,
    req: &CreateSubmissionRequest,
    ip_address: Option<&str>,
    app_version: Option<&str>,
) -> Result<EquipmentSubmissionRow, AppError> {
    let submission = sqlx::query_as::<_, EquipmentSubmissionRow>(
        r#"
        INSERT INTO equipment_submissions (
            name, manufacturer, category, bands, modes,
            max_power_watts, portability, weight_grams,
            ip_address, app_version
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::inet, $10)
        RETURNING id, name, manufacturer, category, bands, modes,
                  max_power_watts, portability, weight_grams, status,
                  catalog_id, app_version, created_at, reviewed_at
        "#,
    )
    .bind(&req.name)
    .bind(&req.manufacturer)
    .bind(&req.category)
    .bind(&req.bands)
    .bind(&req.modes)
    .bind(req.max_power_watts)
    .bind(&req.portability)
    .bind(req.weight_grams)
    .bind(ip_address)
    .bind(app_version)
    .fetch_one(pool)
    .await?;

    Ok(submission)
}

/// List equipment submissions, optionally filtered by status.
pub async fn list_submissions(
    pool: &PgPool,
    status: Option<&str>,
    limit: i64,
) -> Result<Vec<EquipmentSubmissionRow>, AppError> {
    let submissions = sqlx::query_as::<_, EquipmentSubmissionRow>(
        r#"
        SELECT id, name, manufacturer, category, bands, modes,
               max_power_watts, portability, weight_grams, status,
               catalog_id, app_version, created_at, reviewed_at
        FROM equipment_submissions
        WHERE ($1::text IS NULL OR status = $1)
        ORDER BY created_at DESC
        LIMIT $2
        "#,
    )
    .bind(status)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(submissions)
}

/// Review (approve/reject) a submission.
pub async fn review_submission(
    pool: &PgPool,
    submission_id: uuid::Uuid,
    status: &str,
    catalog_id: Option<&str>,
) -> Result<Option<EquipmentSubmissionRow>, AppError> {
    let submission = sqlx::query_as::<_, EquipmentSubmissionRow>(
        r#"
        UPDATE equipment_submissions
        SET status = $2, catalog_id = $3, reviewed_at = NOW()
        WHERE id = $1
        RETURNING id, name, manufacturer, category, bands, modes,
                  max_power_watts, portability, weight_grams, status,
                  catalog_id, app_version, created_at, reviewed_at
        "#,
    )
    .bind(submission_id)
    .bind(status)
    .bind(catalog_id)
    .fetch_optional(pool)
    .await?;

    Ok(submission)
}
