//! Admin endpoints for orphaned sync tenants.
//!
//! When `/v1/sync/*` started requiring an account-backed (email-verified)
//! tenant, data synced under legacy `fd_` device tokens — keyed by
//! `participants.id` — became unreachable by clients. These superuser routes
//! (behind the admin bearer token) surface those orphans and re-key one onto
//! the account that now owns the same callsign.
//!
//! - `GET  /v1/admin/sync/orphans` — list orphaned participant tenants.
//! - `POST /v1/admin/sync/orphans/:participant_id/adopt` — move an orphan's
//!   journal/cursor/key blob onto the callsign's account tenant. Refuses with
//!   409 when the account tenant already has sync data (no automatic merges).

use axum::extract::{Path, State};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::extractors::Json;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OrphanTenantDto {
    pub participant_id: Uuid,
    pub callsign: String,
    pub entry_count: i64,
    pub total_bytes: i64,
    pub has_key_blob: bool,
    pub last_seq: i64,
    pub last_activity: Option<chrono::DateTime<chrono::Utc>>,
    /// The account that now owns this callsign (the adoption target), if the
    /// user has signed in since the cutover.
    pub account_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OrphanListResponse {
    pub orphans: Vec<OrphanTenantDto>,
}

/// `GET /v1/admin/sync/orphans`
pub async fn list_sync_orphans(
    State(pool): State<PgPool>,
) -> Result<Json<OrphanListResponse>, AppError> {
    let orphans = db::sync::list_orphan_tenants(&pool)
        .await?
        .into_iter()
        .map(|o| OrphanTenantDto {
            participant_id: o.participant_id,
            callsign: o.callsign,
            entry_count: o.entry_count,
            total_bytes: o.total_bytes,
            has_key_blob: o.has_key_blob,
            last_seq: o.last_seq,
            last_activity: o.last_activity,
            account_id: o.account_id,
        })
        .collect();
    Ok(Json(OrphanListResponse { orphans }))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdoptResponse {
    pub participant_id: Uuid,
    pub account_id: Uuid,
    pub entries_moved: i64,
}

/// `POST /v1/admin/sync/orphans/:participant_id/adopt`
///
/// Re-keys the orphan's `sync_entry` / `sync_cursor` / `sync_key_blob` rows
/// onto the account that owns the participant's callsign. The account tenant
/// must be completely empty (409 SYNC_ADOPT_CONFLICT otherwise) and the
/// callsign must already have an account (422 SYNC_ADOPT_NO_ACCOUNT).
pub async fn adopt_sync_orphan(
    State(pool): State<PgPool>,
    Path(participant_id): Path<Uuid>,
) -> Result<Json<AdoptResponse>, AppError> {
    let callsign: Option<String> =
        sqlx::query_scalar("SELECT callsign FROM participants WHERE id = $1")
            .bind(participant_id)
            .fetch_optional(&pool)
            .await?;
    let callsign = callsign.ok_or(AppError::UserNotFound {
        user_id: participant_id,
    })?;

    let account = db::auth::find_account_for_callsign(&pool, &callsign)
        .await?
        .ok_or(AppError::SyncAdoptNoAccount {
            callsign: callsign.clone(),
        })?;

    let usage = db::sync::tenant_usage(&pool, account.account_id).await?;
    if usage.entry_count > 0 || usage.has_cursor || usage.has_key_blob {
        return Err(AppError::SyncAdoptConflict {
            entry_count: usage.entry_count,
            has_cursor: usage.has_cursor,
            has_key_blob: usage.has_key_blob,
        });
    }

    let entries_moved =
        db::sync::adopt_orphan_tenant(&pool, participant_id, account.account_id).await?;

    tracing::info!(
        %participant_id,
        account_id = %account.account_id,
        callsign,
        entries_moved,
        "admin adopted orphan sync tenant"
    );

    Ok(Json(AdoptResponse {
        participant_id,
        account_id: account.account_id,
        entries_moved,
    }))
}
