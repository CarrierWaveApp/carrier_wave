//! Phase 1 public macros endpoints (CAR-271 T5).
//!
//! All reads filter on `status='approved'` server-side; withdrawn slugs
//! propagate via `GET /v1/macros/tombstones?since=`. Versions endpoint
//! returns both `version` and `format` so a v2 client can ignore v3-only
//! macros up front (see design spec "Update propagation").

use axum::extract::{Query, State};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::collections::HashMap;

use crate::db::macros as macros_db;
use crate::db::macros::{ListFilter, MacroRow, TombstoneRow, VersionHistoryRow, VersionInfo};
use crate::error::AppError;
use crate::extractors::{Json, Path};

// ---------------------------------------------------------------------------
// GET /v1/macros — filtered list (public, approved-only)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct ListQuery {
    pub tag: Option<String>,
    pub applies_to: Option<String>,
    pub search: Option<String>,
    pub max_format: Option<i32>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct ListResponse {
    pub entries: Vec<MacroSummary>,
}

#[derive(Debug, Serialize)]
pub struct MacroSummary {
    pub slug: String,
    pub name: String,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub applies_to: Vec<String>,
    pub capabilities: serde_json::Value,
    pub format: i32,
    pub version: i32,
    pub author_callsign: Option<String>,
    pub published_at: DateTime<Utc>,
}

impl From<&MacroRow> for MacroSummary {
    fn from(row: &MacroRow) -> Self {
        Self {
            slug: row.slug.clone(),
            name: row.name.clone(),
            icon: row.icon.clone(),
            description: row.description.clone(),
            tags: row.tags.clone(),
            applies_to: row.applies_to.clone(),
            capabilities: row.capabilities.clone(),
            format: row.format,
            version: row.version,
            author_callsign: row.author_callsign.clone(),
            published_at: row.published_at,
        }
    }
}

pub async fn list_macros(
    State(pool): State<PgPool>,
    Query(query): Query<ListQuery>,
) -> Result<Json<ListResponse>, AppError> {
    let filter = ListFilter {
        tag: query.tag,
        applies_to: query.applies_to,
        search: query.search,
        max_format: query.max_format,
        limit: query.limit.unwrap_or(50),
        offset: query.offset.unwrap_or(0),
        status: Some("approved".to_string()),
    };
    let rows = macros_db::list_macros(&pool, &filter).await?;
    let entries = rows.iter().map(MacroSummary::from).collect();
    Ok(Json(ListResponse { entries }))
}

// ---------------------------------------------------------------------------
// GET /v1/macros/:slug — full RadioMacroDocument
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct MacroDocumentResponse {
    pub slug: String,
    pub spec: MacroSpecResponse,
    pub format: i32,
    pub version: i32,
    pub published_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub author_callsign: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MacroSpecResponse {
    pub name: String,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub applies_to: Vec<String>,
    pub capabilities: serde_json::Value,
    pub args: serde_json::Value,
    pub steps: serde_json::Value,
}

pub async fn get_macro(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
) -> Result<Json<MacroDocumentResponse>, AppError> {
    let Some(row) = macros_db::get_by_slug(&pool, &slug).await? else {
        return Err(AppError::Validation {
            message: format!("macro not found: {slug}"),
        });
    };
    Ok(Json(MacroDocumentResponse {
        slug: row.slug,
        spec: MacroSpecResponse {
            name: row.name,
            icon: row.icon,
            description: row.description,
            tags: row.tags,
            applies_to: row.applies_to,
            capabilities: row.capabilities,
            args: row.args,
            steps: row.steps,
        },
        format: row.format,
        version: row.version,
        published_at: row.published_at,
        updated_at: row.updated_at,
        author_callsign: row.author_callsign,
    }))
}

// ---------------------------------------------------------------------------
// GET /v1/macros/:slug/versions — per-slug version audit trail
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct VersionsResponse {
    pub versions: Vec<VersionHistoryRow>,
}

pub async fn list_macro_versions(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
) -> Result<Json<VersionsResponse>, AppError> {
    // Only surface history if the macro is currently approved.
    if macros_db::get_by_slug(&pool, &slug).await?.is_none() {
        return Err(AppError::Validation {
            message: format!("macro not found: {slug}"),
        });
    }
    let versions = macros_db::version_history(&pool, &slug).await?;
    Ok(Json(VersionsResponse { versions }))
}

// ---------------------------------------------------------------------------
// GET /v1/macros/versions?slugs=a,b,c — bulk version check
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct VersionsQuery {
    pub slugs: String,
}

pub async fn versions_for_slugs(
    State(pool): State<PgPool>,
    Query(query): Query<VersionsQuery>,
) -> Result<Json<HashMap<String, VersionInfo>>, AppError> {
    let slugs: Vec<String> = query
        .slugs
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if slugs.len() > 200 {
        return Err(AppError::Validation {
            message: "max 200 slugs per request".to_string(),
        });
    }
    let map = macros_db::versions_for_slugs(&pool, &slugs).await?;
    Ok(Json(map))
}

// ---------------------------------------------------------------------------
// GET /v1/macros/tombstones?since=<ts>
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct TombstonesQuery {
    pub since: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
pub struct TombstonesResponse {
    pub entries: Vec<TombstoneRow>,
}

pub async fn tombstones(
    State(pool): State<PgPool>,
    Query(query): Query<TombstonesQuery>,
) -> Result<Json<TombstonesResponse>, AppError> {
    let entries = macros_db::tombstones_since(&pool, query.since).await?;
    Ok(Json(TombstonesResponse { entries }))
}
