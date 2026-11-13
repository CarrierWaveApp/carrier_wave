use sqlx::PgPool;

use crate::contest::types::ContestDefinition;
use crate::error::AppError;
use crate::models::contest_definition::ContestDefinitionRow;

/// List all contest definitions.
pub async fn list(
    pool: &PgPool,
    include_inactive: bool,
) -> Result<Vec<ContestDefinitionRow>, AppError> {
    let rows = if include_inactive {
        sqlx::query_as::<_, ContestDefinitionRow>(
            r#"
            SELECT id, name, short_name, sponsor_name, sponsor_url,
                   format_version, definition, is_active, created_at, updated_at
            FROM contest_definitions
            ORDER BY name ASC
            "#,
        )
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, ContestDefinitionRow>(
            r#"
            SELECT id, name, short_name, sponsor_name, sponsor_url,
                   format_version, definition, is_active, created_at, updated_at
            FROM contest_definitions
            WHERE is_active = TRUE
            ORDER BY name ASC
            "#,
        )
        .fetch_all(pool)
        .await?
    };
    Ok(rows)
}

/// Fetch a single contest definition by its id.
pub async fn get(pool: &PgPool, id: &str) -> Result<Option<ContestDefinitionRow>, AppError> {
    let row = sqlx::query_as::<_, ContestDefinitionRow>(
        r#"
        SELECT id, name, short_name, sponsor_name, sponsor_url,
               format_version, definition, is_active, created_at, updated_at
        FROM contest_definitions
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Upsert all contests within a [`ContestDefinition`] file.
///
/// Each contest in the file becomes a separate row keyed by its id.
/// Returns the list of upserted rows in the same order as the input.
pub async fn upsert_all(
    pool: &PgPool,
    def: &ContestDefinition,
) -> Result<Vec<ContestDefinitionRow>, AppError> {
    let mut tx = pool.begin().await?;
    let mut out = Vec::with_capacity(def.contests.len());

    for contest in &def.contests {
        let definition_value = serde_json::to_value(contest)
            .map_err(|e| AppError::Internal(format!("failed to serialize contest: {e}")))?;

        let row = sqlx::query_as::<_, ContestDefinitionRow>(
            r#"
            INSERT INTO contest_definitions (
                id, name, short_name, sponsor_name, sponsor_url,
                format_version, definition, is_active, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, TRUE, NOW())
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                short_name = EXCLUDED.short_name,
                sponsor_name = EXCLUDED.sponsor_name,
                sponsor_url = EXCLUDED.sponsor_url,
                format_version = EXCLUDED.format_version,
                definition = EXCLUDED.definition,
                updated_at = NOW()
            RETURNING id, name, short_name, sponsor_name, sponsor_url,
                      format_version, definition, is_active, created_at, updated_at
            "#,
        )
        .bind(&contest.id)
        .bind(&contest.name)
        .bind(contest.short_name.as_deref())
        .bind(contest.sponsor.as_ref().and_then(|s| s.name.as_deref()))
        .bind(contest.sponsor.as_ref().and_then(|s| s.url.as_deref()))
        .bind(&def.version)
        .bind(&definition_value)
        .fetch_one(&mut *tx)
        .await?;

        out.push(row);
    }

    tx.commit().await?;
    Ok(out)
}

/// Hard-delete a contest definition. Used by the admin DELETE endpoint.
pub async fn delete(pool: &PgPool, id: &str) -> Result<bool, AppError> {
    let result = sqlx::query(
        r#"
        DELETE FROM contest_definitions WHERE id = $1
        "#,
    )
    .bind(id)
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}
