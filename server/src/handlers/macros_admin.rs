//! Admin-side macros endpoints (CAR-271 T7).
//!
//! Wired under the `require_admin` middleware in `main.rs`. Every write
//! runs through the same verifier the Swift app uses, plus the slug/tag/
//! band-plan validators, so bad uploads are rejected with HTTP 422 and a
//! structured `issues` list rather than silently accepted.

use axum::extract::State;
use axum::http::StatusCode;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::macros as macros_db;
use crate::db::macros::{ListFilter, MacroRow, MacroUpsert};
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::macros::band_plan;
use crate::macros::slug as slug_v;
use crate::macros::spec::{ArgType, RadioMacroArg, RadioMacroSpec};
use crate::macros::tag_vocabulary;
use crate::macros::verifier;
use crate::macros::verifier::{Severity, VerifierIssue};
use crate::macros::verifier_generated::{CapabilityBits, RadioMacroStep};

// ---------------------------------------------------------------------------
// Request shapes
// ---------------------------------------------------------------------------

/// Body accepted by `POST /v1/admin/macros` and `PUT /v1/admin/macros/:slug`.
/// This is the full RadioMacroDocument minus server-managed fields.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AdminMacroPayload {
    pub slug: String,
    pub name: String,
    pub icon: Option<String>,
    pub description: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default, rename = "appliesTo")]
    pub applies_to: Vec<String>,
    #[serde(default)]
    pub capabilities: CapabilityBits,
    #[serde(default)]
    pub args: Vec<RadioMacroArg>,
    pub steps: Vec<RadioMacroStep>,
    #[serde(default = "default_format")]
    pub format: i32,
    pub author_callsign: Option<String>,
    pub author_user_id: Option<Uuid>,
    #[serde(default = "default_status")]
    pub status: String,
    /// Optional pre-allocated spec id; otherwise the verifier uses Uuid::nil().
    pub id: Option<Uuid>,
}

fn default_format() -> i32 {
    2
}
fn default_status() -> String {
    "approved".to_string()
}

#[derive(Debug, Deserialize)]
pub struct AdminPatchPayload {
    pub status: Option<String>,
    pub moderator_notes: Option<String>,
}

// ---------------------------------------------------------------------------
// Response shapes
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct AdminMacroResponse {
    pub slug: String,
    pub status: String,
    pub version: i32,
    pub published_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

impl From<MacroRow> for AdminMacroResponse {
    fn from(row: MacroRow) -> Self {
        Self {
            slug: row.slug,
            status: row.status,
            version: row.version,
            published_at: row.published_at,
            updated_at: row.updated_at,
            created_at: row.created_at,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct AdminListResponse {
    pub entries: Vec<AdminListEntry>,
}

#[derive(Debug, Serialize)]
pub struct AdminListEntry {
    pub slug: String,
    pub name: String,
    pub status: String,
    pub format: i32,
    pub version: i32,
    pub author_callsign: Option<String>,
    pub updated_at: DateTime<Utc>,
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
struct ValidationDetails {
    issues: Vec<VerifierIssue>,
}

fn build_spec(payload: &AdminMacroPayload) -> RadioMacroSpec {
    RadioMacroSpec {
        id: payload.id.unwrap_or_else(Uuid::nil),
        name: payload.name.clone(),
        applies_to: payload.applies_to.clone(),
        capabilities: payload.capabilities.clone(),
        args: payload.args.clone(),
        steps: payload.steps.clone(),
    }
}

/// Runs slug/tag/band-plan/verifier checks. Mutates `payload.tags` to the
/// normalised form (so the DB write picks up NFKC+lowercase).
fn validate(payload: &mut AdminMacroPayload) -> Result<(), AppError> {
    slug_v::validate(
        &payload.slug,
        payload.author_callsign.as_deref(),
        /* allow_reserved_prefix */ true,
    )
    .map_err(|e| AppError::Validation { message: e.to_string() })?;

    payload.tags = tag_vocabulary::validate_set(&payload.tags)
        .map_err(|e| AppError::Validation { message: e.to_string() })?;

    // Band-plan plausibility on top of the verifier's presence check.
    band_plan::validate(&payload.args)
        .map_err(|e| AppError::Validation { message: e.to_string() })?;

    let spec = build_spec(payload);
    let issues = verifier::verify(&spec);
    let errors: Vec<_> = issues
        .iter()
        .filter(|i| i.severity == Severity::Error)
        .cloned()
        .collect();
    if !errors.is_empty() {
        let details = serde_json::to_value(ValidationDetails { issues: errors })
            .unwrap_or_else(|_| serde_json::json!({}));
        return Err(AppError::Validation {
            message: format!("verifier rejected macro `{}`: {details}", payload.slug),
        });
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// GET /v1/admin/macros — list every macro regardless of status.
pub async fn list_macros(
    State(pool): State<PgPool>,
    axum::extract::Query(q): axum::extract::Query<AdminListQuery>,
) -> Result<Json<AdminListResponse>, AppError> {
    let filter = ListFilter {
        status: q.status,
        limit: q.limit.unwrap_or(200),
        offset: q.offset.unwrap_or(0),
        ..Default::default()
    };
    let rows = macros_db::list_macros(&pool, &filter).await?;
    Ok(Json(AdminListResponse {
        entries: rows
            .into_iter()
            .map(|r| AdminListEntry {
                slug: r.slug,
                name: r.name,
                status: r.status,
                format: r.format,
                version: r.version,
                author_callsign: r.author_callsign,
                updated_at: r.updated_at,
            })
            .collect(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct AdminListQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// POST /v1/admin/macros — create-or-bump a macro.
///
/// Idempotent: re-POSTing the same slug bumps version. Prefer PUT for
/// clarity; we accept both because the `cwa macros sync` CLI doesn't know
/// ahead of time whether a slug exists.
pub async fn create_macro(
    State(pool): State<PgPool>,
    Json(payload): Json<AdminMacroPayload>,
) -> Result<(StatusCode, Json<AdminMacroResponse>), AppError> {
    upsert(&pool, payload).await.map(|row| {
        let status = if row.version == 1 {
            StatusCode::CREATED
        } else {
            StatusCode::OK
        };
        (status, Json(row.into()))
    })
}

/// PUT /v1/admin/macros/:slug — replace the spec for an existing slug
/// (or create it if absent). Payload slug must match path slug.
pub async fn update_macro(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
    Json(mut payload): Json<AdminMacroPayload>,
) -> Result<Json<AdminMacroResponse>, AppError> {
    if payload.slug != slug {
        return Err(AppError::Validation {
            message: format!("path slug `{slug}` does not match body slug `{}`", payload.slug),
        });
    }
    payload.slug = slug;
    let row = upsert(&pool, payload).await?;
    Ok(Json(row.into()))
}

/// PATCH /v1/admin/macros/:slug — status-only changes (e.g. withdraw).
pub async fn patch_macro(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
    Json(patch): Json<AdminPatchPayload>,
) -> Result<Json<AdminMacroResponse>, AppError> {
    let Some(new_status) = patch.status else {
        return Err(AppError::Validation {
            message: "PATCH body must include `status`".to_string(),
        });
    };
    let row = macros_db::set_status(&pool, &slug, &new_status, patch.moderator_notes.as_deref())
        .await?;
    Ok(Json(row.into()))
}

/// DELETE /v1/admin/macros/:slug — hard delete. Prefer PATCH withdrawn.
pub async fn delete_macro(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
) -> Result<StatusCode, AppError> {
    let deleted = macros_db::delete_macro(&pool, &slug).await?;
    if !deleted {
        return Err(AppError::Validation {
            message: format!("macro not found: {slug}"),
        });
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn upsert(pool: &PgPool, mut payload: AdminMacroPayload) -> Result<MacroRow, AppError> {
    // Default an integer arg's `type` to `string` when the field is absent
    // in the JSON. Done implicitly by ArgType's Deserialize; nothing extra
    // needed here. We still want to surface mis-typed args though.
    let _ = ArgType::String; // silence unused-import lint in some build modes

    validate(&mut payload)?;
    let upsert = MacroUpsert {
        slug: payload.slug.clone(),
        author_user_id: payload.author_user_id,
        author_callsign: payload.author_callsign.clone(),
        name: payload.name.clone(),
        icon: payload.icon.clone(),
        description: payload.description.clone(),
        tags: payload.tags.clone(),
        applies_to: payload.applies_to.clone(),
        capabilities: serde_json::to_value(&payload.capabilities).unwrap_or_default(),
        args: serde_json::to_value(&payload.args).unwrap_or_default(),
        steps: serde_json::to_value(&payload.steps).unwrap_or_default(),
        format: payload.format,
        spec: serde_json::to_value(&payload).unwrap_or_default(),
    };
    let status = payload.status.clone();
    macros_db::upsert_macro(pool, &upsert, &status).await
}
