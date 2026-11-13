//! Database queries for the radio-macros registry (CAR-271).
//!
//! Schema lives in `migrations/041_macros_registry.sql`. Public reads filter
//! to `status='approved'`. Admin upserts bump `version` on slug-conflict and
//! always write a `macro_versions` row. Withdraw writes a `macro_tombstones`
//! row so clients can propagate removals on next sync.

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use std::collections::HashMap;
use uuid::Uuid;

use crate::error::AppError;

/// One row from `macros`. JSON columns surface as `serde_json::Value` so
/// handlers can pass through the body verbatim without re-encoding.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize)]
pub struct MacroRow {
    pub id: Uuid,
    pub slug: String,
    pub author_user_id: Option<Uuid>,
    pub author_callsign: Option<String>,
    pub name: String,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub applies_to: Vec<String>,
    pub capabilities: serde_json::Value,
    pub args: serde_json::Value,
    pub steps: serde_json::Value,
    pub format: i32,
    pub status: String,
    pub version: i32,
    pub moderator_notes: Option<String>,
    pub published_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

const MACRO_COLUMNS: &str = "id, slug, author_user_id, author_callsign, name, icon, description, \
                             tags, applies_to, capabilities, args, steps, format, status, \
                             version, moderator_notes, published_at, updated_at, created_at";

#[derive(Debug, Default, Clone)]
pub struct ListFilter {
    pub tag: Option<String>,
    pub applies_to: Option<String>,
    pub search: Option<String>,
    pub max_format: Option<i32>,
    pub limit: i64,
    pub offset: i64,
    /// Defaults to `"approved"` for public endpoints; admin endpoints may pass
    /// `None` to see every status.
    pub status: Option<String>,
}

impl ListFilter {
    pub fn approved_default() -> Self {
        Self {
            limit: 50,
            offset: 0,
            status: Some("approved".to_string()),
            ..Self::default()
        }
    }
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct VersionInfo {
    pub version: i32,
    pub format: i32,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize)]
pub struct TombstoneRow {
    pub slug: String,
    pub reason: String,
    pub tombstoned_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize)]
pub struct VersionHistoryRow {
    pub version: i32,
    pub published_at: DateTime<Utc>,
}

/// Inputs an admin sends when upserting a macro. `spec` is the full
/// `RadioMacroDocument`-shaped JSON; we project specific fields out for
/// indexed columns but also store the full doc in `macro_versions.spec`.
#[derive(Debug, Clone, serde::Deserialize)]
pub struct MacroUpsert {
    pub slug: String,
    pub author_user_id: Option<Uuid>,
    pub author_callsign: Option<String>,
    pub name: String,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub applies_to: Vec<String>,
    pub capabilities: serde_json::Value,
    pub args: serde_json::Value,
    pub steps: serde_json::Value,
    pub format: i32,
    /// Full `RadioMacroDocument` JSON; stored verbatim in `macro_versions`.
    pub spec: serde_json::Value,
}

/// Public list: filters status, applies optional tag/applies_to/search/max_format.
pub async fn list_macros(pool: &PgPool, filter: &ListFilter) -> Result<Vec<MacroRow>, AppError> {
    let limit = filter.limit.clamp(1, 200);
    let offset = filter.offset.max(0);
    let sql = format!(
        "SELECT {cols} \
         FROM macros \
         WHERE ($1::text IS NULL OR status = $1) \
           AND ($2::text IS NULL OR $2 = ANY(tags)) \
           AND ($3::text IS NULL OR $3 = ANY(applies_to)) \
           AND ($4::text IS NULL OR name ILIKE '%' || $4 || '%' OR slug ILIKE '%' || $4 || '%' OR description ILIKE '%' || $4 || '%') \
           AND ($5::int IS NULL OR format <= $5) \
         ORDER BY published_at DESC \
         LIMIT $6 OFFSET $7",
        cols = MACRO_COLUMNS
    );
    let rows = sqlx::query_as::<_, MacroRow>(&sql)
        .bind(filter.status.as_deref())
        .bind(filter.tag.as_deref())
        .bind(filter.applies_to.as_deref())
        .bind(filter.search.as_deref())
        .bind(filter.max_format)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?;
    Ok(rows)
}

/// Fetch a single approved macro by slug.
pub async fn get_by_slug(pool: &PgPool, slug: &str) -> Result<Option<MacroRow>, AppError> {
    let sql = format!(
        "SELECT {cols} FROM macros WHERE slug = $1 AND status = 'approved'",
        cols = MACRO_COLUMNS
    );
    let row = sqlx::query_as::<_, MacroRow>(&sql)
        .bind(slug)
        .fetch_optional(pool)
        .await?;
    Ok(row)
}

/// Admin-side single fetch — returns the row regardless of status.
pub async fn get_by_slug_admin(pool: &PgPool, slug: &str) -> Result<Option<MacroRow>, AppError> {
    let sql = format!(
        "SELECT {cols} FROM macros WHERE slug = $1",
        cols = MACRO_COLUMNS
    );
    let row = sqlx::query_as::<_, MacroRow>(&sql)
        .bind(slug)
        .fetch_optional(pool)
        .await?;
    Ok(row)
}

/// Bulk version check for the client's installed slugs.
/// Includes only approved rows — withdrawn slugs route via `tombstones_since`.
pub async fn versions_for_slugs(
    pool: &PgPool,
    slugs: &[String],
) -> Result<HashMap<String, VersionInfo>, AppError> {
    if slugs.is_empty() {
        return Ok(HashMap::new());
    }
    let rows: Vec<(String, i32, i32)> = sqlx::query_as(
        "SELECT slug, version, format FROM macros WHERE slug = ANY($1) AND status = 'approved'",
    )
    .bind(slugs)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(slug, version, format)| (slug, VersionInfo { version, format }))
        .collect())
}

/// Per-slug version history for `GET /v1/macros/:slug/versions`.
pub async fn version_history(
    pool: &PgPool,
    slug: &str,
) -> Result<Vec<VersionHistoryRow>, AppError> {
    let rows = sqlx::query_as::<_, VersionHistoryRow>(
        "SELECT mv.version, mv.published_at \
         FROM macro_versions mv \
         JOIN macros m ON m.id = mv.macro_id \
         WHERE m.slug = $1 \
         ORDER BY mv.version DESC",
    )
    .bind(slug)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Tombstones since the given timestamp. `since=None` returns all.
pub async fn tombstones_since(
    pool: &PgPool,
    since: Option<DateTime<Utc>>,
) -> Result<Vec<TombstoneRow>, AppError> {
    let rows = sqlx::query_as::<_, TombstoneRow>(
        "SELECT slug, reason, tombstoned_at \
         FROM macro_tombstones \
         WHERE $1::timestamptz IS NULL OR tombstoned_at > $1 \
         ORDER BY tombstoned_at ASC",
    )
    .bind(since)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Insert (status='pending' or 'approved' depending on caller) or bump version
/// on slug-conflict. Writes a `macro_versions` row for every write.
///
/// Returns the resulting `MacroRow`. Slug is permanent — once a row exists,
/// subsequent calls only update mutable fields and increment `version`.
pub async fn upsert_macro(
    pool: &PgPool,
    upsert: &MacroUpsert,
    status: &str,
) -> Result<MacroRow, AppError> {
    let mut tx = pool.begin().await?;

    let existing: Option<(Uuid, i32)> =
        sqlx::query_as("SELECT id, version FROM macros WHERE slug = $1 FOR UPDATE")
            .bind(&upsert.slug)
            .fetch_optional(&mut *tx)
            .await?;

    let (id, version) = match existing {
        Some((id, current_version)) => {
            let next_version = current_version + 1;
            let sql = format!(
                "UPDATE macros SET \
                    author_user_id = $2, author_callsign = $3, name = $4, icon = $5, \
                    description = $6, tags = $7, applies_to = $8, capabilities = $9, \
                    args = $10, steps = $11, format = $12, status = $13, version = $14, \
                    updated_at = NOW(), published_at = NOW() \
                 WHERE id = $1 RETURNING {cols}",
                cols = MACRO_COLUMNS
            );
            sqlx::query_as::<_, MacroRow>(&sql)
                .bind(id)
                .bind(upsert.author_user_id)
                .bind(&upsert.author_callsign)
                .bind(&upsert.name)
                .bind(&upsert.icon)
                .bind(&upsert.description)
                .bind(&upsert.tags)
                .bind(&upsert.applies_to)
                .bind(&upsert.capabilities)
                .bind(&upsert.args)
                .bind(&upsert.steps)
                .bind(upsert.format)
                .bind(status)
                .bind(next_version)
                .fetch_one(&mut *tx)
                .await?;
            (id, next_version)
        }
        None => {
            let new_id = Uuid::new_v4();
            let sql = format!(
                "INSERT INTO macros (id, slug, author_user_id, author_callsign, name, icon, \
                                     description, tags, applies_to, capabilities, args, steps, \
                                     format, status, version) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, 1) \
                 RETURNING {cols}",
                cols = MACRO_COLUMNS
            );
            sqlx::query_as::<_, MacroRow>(&sql)
                .bind(new_id)
                .bind(&upsert.slug)
                .bind(upsert.author_user_id)
                .bind(&upsert.author_callsign)
                .bind(&upsert.name)
                .bind(&upsert.icon)
                .bind(&upsert.description)
                .bind(&upsert.tags)
                .bind(&upsert.applies_to)
                .bind(&upsert.capabilities)
                .bind(&upsert.args)
                .bind(&upsert.steps)
                .bind(upsert.format)
                .bind(status)
                .fetch_one(&mut *tx)
                .await?;
            (new_id, 1)
        }
    };

    sqlx::query(
        "INSERT INTO macro_versions (macro_id, version, spec) VALUES ($1, $2, $3)",
    )
    .bind(id)
    .bind(version)
    .bind(&upsert.spec)
    .execute(&mut *tx)
    .await?;

    let sql = format!(
        "SELECT {cols} FROM macros WHERE id = $1",
        cols = MACRO_COLUMNS
    );
    let row = sqlx::query_as::<_, MacroRow>(&sql)
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(row)
}

/// Update status (typically to `withdrawn` or `rejected`). When the new
/// status is `withdrawn` or `tombstoned` we insert a `macro_tombstones` row
/// so clients can propagate the removal on next sync.
pub async fn set_status(
    pool: &PgPool,
    slug: &str,
    new_status: &str,
    moderator_notes: Option<&str>,
) -> Result<MacroRow, AppError> {
    let mut tx = pool.begin().await?;

    let sql = format!(
        "UPDATE macros SET status = $2, moderator_notes = COALESCE($3, moderator_notes), \
                          updated_at = NOW() \
         WHERE slug = $1 RETURNING {cols}",
        cols = MACRO_COLUMNS
    );
    let row = sqlx::query_as::<_, MacroRow>(&sql)
        .bind(slug)
        .bind(new_status)
        .bind(moderator_notes)
        .fetch_optional(&mut *tx)
        .await?;
    let Some(row) = row else {
        tx.rollback().await.ok();
        return Err(AppError::Validation {
            message: format!("macro not found: {slug}"),
        });
    };

    if matches!(new_status, "withdrawn" | "tombstoned" | "author_deleted") {
        let reason = match new_status {
            "author_deleted" => "author_deleted",
            "tombstoned" => "admin_removed",
            _ => "withdrawn",
        };
        sqlx::query(
            "INSERT INTO macro_tombstones (slug, reason) VALUES ($1, $2) \
             ON CONFLICT (slug) DO UPDATE SET reason = EXCLUDED.reason, tombstoned_at = NOW()",
        )
        .bind(slug)
        .bind(reason)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;
    Ok(row)
}

/// Hard-delete (only used by admin DELETE). Cascades via FKs to versions,
/// run_events, tombstones, etc. Prefer `set_status("withdrawn")` so the
/// slug stays reserved.
pub async fn delete_macro(pool: &PgPool, slug: &str) -> Result<bool, AppError> {
    let res = sqlx::query("DELETE FROM macros WHERE slug = $1")
        .bind(slug)
        .execute(pool)
        .await?;
    Ok(res.rows_affected() > 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_upsert(slug: &str) -> MacroUpsert {
        MacroUpsert {
            slug: slug.to_string(),
            author_user_id: None,
            author_callsign: Some("W6JY".to_string()),
            name: "Test Macro".to_string(),
            icon: Some("waveform".to_string()),
            description: Some("test".to_string()),
            tags: vec!["test".to_string()],
            applies_to: vec!["icom-civ".to_string()],
            capabilities: serde_json::json!({ "transmits": false }),
            args: serde_json::json!([]),
            steps: serde_json::json!([{ "kind": "delay", "durationMs": 100 }]),
            format: 2,
            spec: serde_json::json!({ "slug": slug }),
        }
    }

    async fn pool_for_test() -> Option<PgPool> {
        let url = std::env::var("TEST_DATABASE_URL").ok()?;
        Some(PgPool::connect(&url).await.ok()?)
    }

    macro_rules! db_test {
        ($pool:ident => $body:block) => {{
            let Some($pool) = pool_for_test().await else {
                eprintln!("TEST_DATABASE_URL not set; skipping");
                return;
            };
            $body
        }};
    }

    #[tokio::test]
    async fn upsert_then_get_roundtrip() {
        db_test!(pool => {
            let slug = format!("test-roundtrip-{}", Uuid::new_v4());
            let upsert = sample_upsert(&slug);
            let row = upsert_macro(&pool, &upsert, "approved").await.unwrap();
            assert_eq!(row.version, 1);
            let fetched = get_by_slug(&pool, &slug).await.unwrap().unwrap();
            assert_eq!(fetched.slug, slug);
            assert_eq!(fetched.version, 1);

            // Second upsert bumps version.
            let bumped = upsert_macro(&pool, &upsert, "approved").await.unwrap();
            assert_eq!(bumped.version, 2);

            // Cleanup.
            delete_macro(&pool, &slug).await.unwrap();
        });
    }

    #[tokio::test]
    async fn pending_status_hidden_from_public() {
        db_test!(pool => {
            let slug = format!("test-pending-{}", Uuid::new_v4());
            let upsert = sample_upsert(&slug);
            upsert_macro(&pool, &upsert, "pending").await.unwrap();
            assert!(get_by_slug(&pool, &slug).await.unwrap().is_none());
            assert!(get_by_slug_admin(&pool, &slug).await.unwrap().is_some());
            delete_macro(&pool, &slug).await.unwrap();
        });
    }

    #[tokio::test]
    async fn withdraw_creates_tombstone() {
        db_test!(pool => {
            let slug = format!("test-withdraw-{}", Uuid::new_v4());
            let upsert = sample_upsert(&slug);
            upsert_macro(&pool, &upsert, "approved").await.unwrap();
            let row = set_status(&pool, &slug, "withdrawn", Some("dangerous"))
                .await
                .unwrap();
            assert_eq!(row.status, "withdrawn");
            let ts = tombstones_since(&pool, None).await.unwrap();
            assert!(ts.iter().any(|t| t.slug == slug && t.reason == "withdrawn"));
            delete_macro(&pool, &slug).await.unwrap();
        });
    }

    #[tokio::test]
    async fn versions_for_slugs_filters_to_approved() {
        db_test!(pool => {
            let slug_a = format!("test-vfs-a-{}", Uuid::new_v4());
            let slug_b = format!("test-vfs-b-{}", Uuid::new_v4());
            upsert_macro(&pool, &sample_upsert(&slug_a), "approved").await.unwrap();
            upsert_macro(&pool, &sample_upsert(&slug_b), "pending").await.unwrap();
            let map = versions_for_slugs(&pool, &[slug_a.clone(), slug_b.clone()]).await.unwrap();
            assert!(map.contains_key(&slug_a));
            assert!(!map.contains_key(&slug_b));
            delete_macro(&pool, &slug_a).await.unwrap();
            delete_macro(&pool, &slug_b).await.unwrap();
        });
    }

    #[tokio::test]
    async fn list_filters_by_tag_and_max_format() {
        db_test!(pool => {
            let slug = format!("test-list-{}", Uuid::new_v4());
            let mut upsert = sample_upsert(&slug);
            upsert.tags = vec!["unique-tag-list-test".to_string()];
            upsert.format = 2;
            upsert_macro(&pool, &upsert, "approved").await.unwrap();
            let mut filter = ListFilter::approved_default();
            filter.tag = Some("unique-tag-list-test".to_string());
            let rows = list_macros(&pool, &filter).await.unwrap();
            assert_eq!(rows.len(), 1);
            assert_eq!(rows[0].slug, slug);

            // max_format=1 excludes our format=2 macro.
            filter.max_format = Some(1);
            let rows = list_macros(&pool, &filter).await.unwrap();
            assert!(rows.is_empty());
            delete_macro(&pool, &slug).await.unwrap();
        });
    }
}
