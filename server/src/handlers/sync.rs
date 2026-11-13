//! HTTP handlers for the E2E-blind sync journal (Phase 4).
//!
//! The server is a dumb per-tenant append-only log: it assigns monotonic
//! sequence numbers, stores opaque ciphertext blobs in object storage (via
//! presigned URLs — it never sees plaintext or proxies blob bytes), and serves
//! incremental changes back to clients. All routes require an account-backed
//! OAuth session (email-verified); the tenant is `auth.account_id`, never a
//! client-supplied id. Legacy `fd_` device tokens get 403 ACCOUNT_REQUIRED.
//!
//! Endpoints:
//! - `POST /v1/sync/push` — reserve seqs + presign uploads (idempotent re-push).
//! - `GET  /v1/sync/changes?since=&limit=` — incremental pull with download URLs.
//! - `POST /v1/sync/snapshot` — phase 1: validate seq, record a PENDING
//!   snapshot, presign its upload. Moves nothing, deletes nothing.
//! - `POST /v1/sync/snapshot/commit` — phase 2: verify the object exists, move
//!   the live pointer forward, then best-effort GC entries below it (CAR-334).
//! - `GET  /v1/sync/bootstrap` — snapshot pointer + post-snapshot changes.
//! - `PUT/GET /v1/sync/key` — the passphrase-escrow key blob.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::{
    extract::{Extension, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
};
use base64::Engine;
use chrono::Utc;
use serde::Deserialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::sync::{
    BootstrapResponse, ChangeItem, ChangesResponse, KeyBlob, PendingSnapshotRow, PushRequest,
    PushResponse, PushedEntry, SnapshotCommitRequest, SnapshotCommitResponse, SnapshotRequest,
    SnapshotResponse, SyncEntryRow,
};
use crate::storage::BlobStore;

/// Validity window for the presigned upload/download URLs we hand out.
const PRESIGN_TTL: Duration = Duration::from_secs(900);

/// How long a pending (phase-1) snapshot may wait for its commit. Longer than
/// [`PRESIGN_TTL`] so an upload that finishes right before the URL expires still
/// has time to be committed; after this it is purged as abandoned.
const PENDING_SNAPSHOT_TTL_SECS: i64 = 30 * 60;

/// Default page size for `/changes` and `/bootstrap` when the client omits it.
const DEFAULT_CHANGES_LIMIT: i64 = 500;

/// The tenant id for a request: the unified account id, which only exists for
/// OAuth sessions verified via a magic-link email. Legacy `fd_` device tokens
/// carry no account (and no verified email) and are rejected with 403
/// ACCOUNT_REQUIRED — sync data must always be email-recoverable. Never trust
/// a client-supplied tenant. Pre-cutover participant-tenant data is orphaned;
/// the admin orphan endpoints re-key it onto an account.
fn tenant_id(auth: &AuthContext) -> Result<Uuid, AppError> {
    auth.account_id.ok_or(AppError::AccountRequired)
}

/// Object-store key for an entry blob.
fn entry_blob_key(tenant: Uuid, seq: i64) -> String {
    format!("{tenant}/entries/{seq}.bin")
}

/// Object-store key for a snapshot blob. Unique per attempt (`snapshot_id`) so
/// a stale object left by an earlier abandoned attempt at the same seq can
/// never satisfy a later commit's existence check.
fn snapshot_blob_key(tenant: Uuid, seq: i64, snapshot_id: Uuid) -> String {
    format!("{tenant}/snapshots/{seq}-{snapshot_id}.bin")
}

/// Current high-water seq for a tenant (`0` if it has never reserved a block).
async fn high_water(pool: &PgPool, tenant: Uuid) -> Result<i64, AppError> {
    Ok(db::sync::get_cursor(pool, tenant)
        .await?
        .map(|(last, _, _)| last)
        .unwrap_or(0))
}

/// `POST /v1/sync/push`
///
/// Reserve a contiguous seq block for the entries that are not already stored,
/// record their metadata, and return a presigned upload URL per entry. A
/// re-push of an already-stored `client_entry_id` is idempotent: it keeps the
/// original seq/blob key and reserves no new seqs.
pub async fn push(
    State(pool): State<PgPool>,
    Extension(store): Extension<Arc<dyn BlobStore>>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<PushRequest>,
) -> Result<Json<PushResponse>, AppError> {
    let tenant = tenant_id(&auth)?;

    // Idempotency: look up which client_entry_ids are already stored.
    let ids: Vec<Uuid> = body.entries.iter().map(|e| e.client_entry_id).collect();
    let existing: HashMap<Uuid, SyncEntryRow> =
        db::sync::entries_for_client_ids(&pool, tenant, &ids)
            .await?
            .into_iter()
            .map(|row| (row.client_entry_id, row))
            .collect();

    // Only genuinely new entries consume seqs.
    let new_entries: Vec<&_> = body
        .entries
        .iter()
        .filter(|e| !existing.contains_key(&e.client_entry_id))
        .collect();

    // (client_entry_id, seq, blob_key) for the freshly reserved entries. Held
    // so the `&str` borrows handed to `insert_entries` stay alive.
    let mut assigned: Vec<(Uuid, i64, String)> = Vec::with_capacity(new_entries.len());
    if !new_entries.is_empty() {
        let first = db::sync::reserve_block(&pool, tenant, new_entries.len() as i64).await?;
        for (offset, entry) in new_entries.iter().enumerate() {
            let seq = first + offset as i64;
            assigned.push((entry.client_entry_id, seq, entry_blob_key(tenant, seq)));
        }

        let rows: Vec<(Uuid, i64, &str, &str, &str, &str, i64)> = new_entries
            .iter()
            .zip(assigned.iter())
            .map(|(entry, (_, seq, blob_key))| {
                (
                    entry.client_entry_id,
                    *seq,
                    blob_key.as_str(),
                    entry.entity_type.as_str(),
                    entry.op.as_str(),
                    entry.content_hash.as_str(),
                    entry.byte_size,
                )
            })
            .collect();
        db::sync::insert_entries(&pool, tenant, &rows).await?;
    }

    // CAR-335: build the response from what the DB actually persisted, not from
    // the seqs/keys we locally reserved. Under a concurrent re-push of the same
    // client_entry_id our `INSERT ... ON CONFLICT DO NOTHING` may be the loser, so
    // the authoritative row can carry a different seq/blob_key. Handing back our
    // locally-reserved key would presign a PUT to an object the journal never
    // references, silently losing the entry on the next pull. Re-read all ids.
    let persisted: HashMap<Uuid, SyncEntryRow> =
        db::sync::entries_for_client_ids(&pool, tenant, &ids)
            .await?
            .into_iter()
            .map(|row| (row.client_entry_id, row))
            .collect();

    // Build the response in request order, presigning a PUT per entry.
    let mut out = Vec::with_capacity(body.entries.len());
    for entry in &body.entries {
        let row = persisted
            .get(&entry.client_entry_id)
            .expect("every pushed entry must be persisted");
        let upload_url = store.presign_put(&row.blob_key, PRESIGN_TTL).await?;
        out.push(PushedEntry {
            client_entry_id: entry.client_entry_id,
            seq: row.seq,
            blob_key: row.blob_key.clone(),
            upload_url,
        });
    }

    let high_water = high_water(&pool, tenant).await?;
    Ok(Json(PushResponse {
        entries: out,
        high_water,
    }))
}

/// Query params for `GET /v1/sync/changes`.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangesQuery {
    /// Return entries with `seq > since`. Defaults to 0 (from the beginning).
    #[serde(default)]
    pub since: i64,
    /// Page size. Defaults to [`DEFAULT_CHANGES_LIMIT`]; clamped server-side.
    pub limit: Option<i64>,
}

/// `GET /v1/sync/changes?since=&limit=`
///
/// Incremental pull: every entry with `seq > since`, ascending, each with a
/// presigned download URL, plus the tenant's current snapshot pointer.
pub async fn changes(
    State(pool): State<PgPool>,
    Extension(store): Extension<Arc<dyn BlobStore>>,
    Extension(auth): Extension<AuthContext>,
    Query(query): Query<ChangesQuery>,
) -> Result<Json<ChangesResponse>, AppError> {
    let tenant = tenant_id(&auth)?;
    let limit = query.limit.unwrap_or(DEFAULT_CHANGES_LIMIT);

    let rows = db::sync::changes_since(&pool, tenant, query.since, limit).await?;
    let entries = presign_changes(store.as_ref(), rows).await?;

    let (high_water, snapshot_seq, snapshot_key) = match db::sync::get_cursor(&pool, tenant).await?
    {
        Some((last, snap_seq, snap_key)) => (last, snap_seq, snap_key),
        None => (0, None, None),
    };
    let snapshot_url = match snapshot_key {
        Some(key) => Some(store.presign_get(&key, PRESIGN_TTL).await?),
        None => None,
    };

    Ok(Json(ChangesResponse {
        entries,
        snapshot_seq,
        snapshot_url,
        high_water,
    }))
}

/// `POST /v1/sync/snapshot` — phase 1 of a two-phase snapshot (CAR-334).
///
/// Validate the requested seq, record a PENDING snapshot, and hand back a
/// presigned PUT. Nothing else changes: the live pointer on the cursor is not
/// moved and no journal entry is deleted until the client has uploaded the
/// bytes and called [`snapshot_commit`]. A pending snapshot that is never
/// committed is inert — `bootstrap`/`changes` only ever read the live pointer —
/// and is purged once it expires.
pub async fn snapshot(
    State(pool): State<PgPool>,
    Extension(store): Extension<Arc<dyn BlobStore>>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<SnapshotRequest>,
) -> Result<Json<SnapshotResponse>, AppError> {
    let tenant = tenant_id(&auth)?;
    let now = Utc::now();

    let (high_water, live_snapshot_seq) = match db::sync::get_cursor(&pool, tenant).await? {
        Some((last, snap_seq, _)) => (last, snap_seq),
        None => (0, None),
    };

    // Housekeeping: drop this tenant's pending snapshots that have expired or
    // that target a seq the live pointer has already reached (they can never
    // commit). Best-effort — a failure here must not block a fresh snapshot.
    purge_stale_pending(&pool, store.as_ref(), tenant, now, live_snapshot_seq).await;

    // SECURITY (CAR-306 / CAR-316 / CAR-334): `body.seq` is raw client input that
    // ultimately drives an irreversible DELETE of journal rows and their
    // ciphertext blobs. Only accept a seq inside the tenant's real, already
    // reserved history AND strictly after the current live snapshot, so the
    // pointer can only ever move forward: current_snapshot_seq < seq <= last_seq.
    let floor = live_snapshot_seq.unwrap_or(0);
    if body.seq <= floor || body.seq > high_water {
        return Err(AppError::SyncSequenceConflict);
    }
    if matches!(body.byte_size, Some(size) if size <= 0) {
        return Err(AppError::Validation {
            message: "byteSize must be a positive number of bytes".into(),
        });
    }

    let snapshot_id = Uuid::new_v4();
    let blob_key = snapshot_blob_key(tenant, body.seq, snapshot_id);
    let expires_at = now + chrono::Duration::seconds(PENDING_SNAPSHOT_TTL_SECS);

    let upload_url = store.presign_put(&blob_key, PRESIGN_TTL).await?;
    db::sync::insert_pending_snapshot(
        &pool,
        &PendingSnapshotRow {
            snapshot_id,
            tenant_id: tenant,
            seq: body.seq,
            blob_key: blob_key.clone(),
            byte_size: body.byte_size,
            content_hash: body.content_hash,
            created_at: now,
            expires_at,
        },
    )
    .await?;

    Ok(Json(SnapshotResponse {
        snapshot_id,
        seq: body.seq,
        snapshot_blob_key: blob_key,
        upload_url,
        expires_at,
    }))
}

/// `POST /v1/sync/snapshot/commit` — phase 2 of a two-phase snapshot (CAR-334).
///
/// The client calls this after its PUT succeeded. The server HEADs the object
/// to prove it exists (and, when a size was declared, that it is the declared
/// size), then promotes the pending snapshot to the live pointer with a
/// forward-only guard, and only then GCs the entries strictly below the new
/// snapshot seq. GC is best-effort and logged; orphaned blobs are harmless
/// because nothing references them.
///
/// Failure modes leave the journal untouched:
/// - unknown/expired/superseded id → 404 `SYNC_SNAPSHOT_NOT_FOUND`
/// - object not in the store → 409 `SYNC_SNAPSHOT_NOT_UPLOADED` (the pending
///   row survives so the client can retry the upload before it expires)
/// - size/hash disagree with what was declared → 409 `SYNC_SNAPSHOT_MISMATCH`
/// - pointer already at/after this seq → 409 `SYNC_SEQUENCE_CONFLICT`
pub async fn snapshot_commit(
    State(pool): State<PgPool>,
    Extension(store): Extension<Arc<dyn BlobStore>>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<SnapshotCommitRequest>,
) -> Result<Json<SnapshotCommitResponse>, AppError> {
    let tenant = tenant_id(&auth)?;
    let snapshot_id = body.snapshot_id;
    let not_found = || AppError::SyncSnapshotNotFound { snapshot_id };

    let pending = db::sync::get_pending_snapshot(&pool, tenant, snapshot_id)
        .await?
        .ok_or_else(not_found)?;

    if pending.expires_at <= Utc::now() {
        discard_pending(&pool, store.as_ref(), tenant, &pending).await;
        return Err(not_found());
    }

    // If the client repeats size/hash on commit they must agree with phase 1.
    if let (Some(declared), Some(committed)) = (pending.byte_size, body.byte_size) {
        if declared != committed {
            return Err(AppError::SyncSnapshotMismatch {
                message: format!("byteSize {committed} differs from the declared {declared}"),
            });
        }
    }
    if let (Some(declared), Some(committed)) = (&pending.content_hash, &body.content_hash) {
        if declared != committed {
            return Err(AppError::SyncSnapshotMismatch {
                message: "contentHash differs from the declared value".into(),
            });
        }
    }

    // The object must really be there before the pointer may reference it.
    let meta = store
        .head(&pending.blob_key)
        .await?
        .ok_or(AppError::SyncSnapshotNotUploaded { snapshot_id })?;
    if let Some(declared) = body.byte_size.or(pending.byte_size) {
        if meta.size != declared as u64 {
            return Err(AppError::SyncSnapshotMismatch {
                message: format!(
                    "stored object is {} bytes but {declared} were declared",
                    meta.size
                ),
            });
        }
    }

    // Promote. The guarded UPDATE refuses to move the pointer backward (or past
    // the high-water mark), so a stale or concurrent commit cannot regress it.
    let Some(previous_key) =
        db::sync::commit_snapshot(&pool, tenant, pending.seq, &pending.blob_key).await?
    else {
        discard_pending(&pool, store.as_ref(), tenant, &pending).await;
        return Err(AppError::SyncSequenceConflict);
    };

    // From here on the snapshot is live; everything below is best-effort GC.
    if let Err(err) = db::sync::delete_pending_snapshot(&pool, tenant, snapshot_id).await {
        tracing::warn!(%snapshot_id, error = %err, "sync snapshot commit: pending row cleanup failed");
    }
    match db::sync::delete_entries_below(&pool, tenant, pending.seq).await {
        Ok(keys) => delete_blobs(store.as_ref(), keys, "sync snapshot GC").await,
        Err(err) => {
            tracing::warn!(error = %err, "sync snapshot GC: entry cleanup failed");
        }
    }
    if let Some(prev) = previous_key.filter(|prev| *prev != pending.blob_key) {
        delete_blobs(
            store.as_ref(),
            vec![prev],
            "sync snapshot GC (previous snapshot)",
        )
        .await;
    }
    // Any other pending attempt at or below this seq can never commit now.
    purge_stale_pending(&pool, store.as_ref(), tenant, Utc::now(), Some(pending.seq)).await;

    let high_water = high_water(&pool, tenant).await?;
    Ok(Json(SnapshotCommitResponse {
        snapshot_seq: pending.seq,
        snapshot_blob_key: pending.blob_key,
        high_water,
    }))
}

/// Drop a pending snapshot row and (best-effort) whatever bytes were uploaded
/// for it. Used when a pending snapshot can never become live.
async fn discard_pending(
    pool: &PgPool,
    store: &dyn BlobStore,
    tenant: Uuid,
    pending: &PendingSnapshotRow,
) {
    if let Err(err) = db::sync::delete_pending_snapshot(pool, tenant, pending.snapshot_id).await {
        tracing::warn!(
            snapshot_id = %pending.snapshot_id,
            error = %err,
            "sync snapshot: pending row cleanup failed"
        );
    }
    delete_blobs(
        store,
        vec![pending.blob_key.clone()],
        "sync snapshot: discard pending",
    )
    .await;
}

/// Purge pending snapshots that have expired (or target `seq <= below_or_at`)
/// and best-effort delete their blobs. Never fails — logs instead.
async fn purge_stale_pending(
    pool: &PgPool,
    store: &dyn BlobStore,
    tenant: Uuid,
    now: chrono::DateTime<Utc>,
    below_or_at: Option<i64>,
) {
    match db::sync::purge_stale_pending_snapshots(pool, tenant, now, below_or_at).await {
        Ok(keys) => delete_blobs(store, keys, "sync snapshot: purge stale pending").await,
        Err(err) => {
            tracing::warn!(error = %err, "sync snapshot: stale pending cleanup failed");
        }
    }
}

/// Best-effort blob deletion; every failure is logged with `context`.
async fn delete_blobs(store: &dyn BlobStore, keys: Vec<String>, context: &str) {
    for key in keys {
        if let Err(err) = store.delete(&key).await {
            tracing::warn!(%key, error = %err, "{context}: blob delete failed");
        }
    }
}

/// `GET /v1/sync/bootstrap`
///
/// Initial-load shortcut: the snapshot pointer plus only the changes after it,
/// so a fresh client downloads one snapshot + the recent tail instead of the
/// whole journal.
pub async fn bootstrap(
    State(pool): State<PgPool>,
    Extension(store): Extension<Arc<dyn BlobStore>>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<BootstrapResponse>, AppError> {
    let tenant = tenant_id(&auth)?;

    let (high_water, snapshot_seq, snapshot_key) = match db::sync::get_cursor(&pool, tenant).await?
    {
        Some((last, snap_seq, snap_key)) => (last, snap_seq, snap_key),
        None => (0, None, None),
    };
    let snapshot_url = match &snapshot_key {
        Some(key) => Some(store.presign_get(key, PRESIGN_TTL).await?),
        None => None,
    };

    let rows = db::sync::changes_since(
        &pool,
        tenant,
        snapshot_seq.unwrap_or(0),
        DEFAULT_CHANGES_LIMIT,
    )
    .await?;
    let entries = presign_changes(store.as_ref(), rows).await?;

    Ok(Json(BootstrapResponse {
        snapshot_url,
        snapshot_seq,
        entries,
        high_water,
    }))
}

/// `PUT /v1/sync/key`
///
/// Store (upsert) the tenant's passphrase-escrow key blob. `wrapped_key` is
/// base64; the server keeps the raw bytes and the opaque KDF params.
pub async fn put_key(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<KeyBlob>,
) -> Result<StatusCode, AppError> {
    let tenant = tenant_id(&auth)?;
    let wrapped = base64::engine::general_purpose::STANDARD
        .decode(body.wrapped_key.as_bytes())
        .map_err(|err| AppError::Validation {
            message: format!("invalid base64 wrapped_key: {err}"),
        })?;
    db::sync::upsert_key_blob(&pool, tenant, &wrapped, body.kdf_params).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// `GET /v1/sync/key`
///
/// Return the tenant's escrow key blob (base64 `wrapped_key` + KDF params), or
/// 404 if none has been stored.
pub async fn get_key(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Response, AppError> {
    let tenant = tenant_id(&auth)?;
    match db::sync::get_key_blob(&pool, tenant).await? {
        Some((wrapped, kdf_params)) => Ok(Json(KeyBlob {
            wrapped_key: base64::engine::general_purpose::STANDARD.encode(&wrapped),
            kdf_params,
        })
        .into_response()),
        None => Ok(StatusCode::NOT_FOUND.into_response()),
    }
}

/// Turn journal rows into [`ChangeItem`]s, presigning a download URL per row.
async fn presign_changes(
    store: &dyn BlobStore,
    rows: Vec<SyncEntryRow>,
) -> Result<Vec<ChangeItem>, AppError> {
    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let download_url = store.presign_get(&row.blob_key, PRESIGN_TTL).await?;
        out.push(ChangeItem {
            seq: row.seq,
            entity_type: row.entity_type,
            op: row.op,
            blob_key: row.blob_key,
            byte_size: row.byte_size,
            content_hash: row.content_hash,
            download_url,
        });
    }
    Ok(out)
}
