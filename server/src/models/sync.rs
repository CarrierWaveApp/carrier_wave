//! Request/response + row types for the E2E-blind sync journal (Phase 2).
//!
//! The server stores ciphertext blobs in object storage and only ever sees
//! plaintext metadata (tenant, seq, type, op, size, hash) plus a blob pointer.
//! Sequence numbers are `i64`; tenant ids are `Uuid`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// One row of the append-only journal (`sync_entry`).
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct SyncEntryRow {
    pub tenant_id: Uuid,
    pub seq: i64,
    pub client_entry_id: Uuid,
    pub entity_type: String,
    pub op: String,
    pub blob_key: String,
    pub byte_size: i64,
    pub content_hash: String,
    pub created_at: DateTime<Utc>,
}

/// A single entry the client wants to append in a push batch.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushEntry {
    pub client_entry_id: Uuid,
    pub entity_type: String,
    pub op: String,
    pub byte_size: i64,
    pub content_hash: String,
}

/// Request body for `POST /v1/sync/push`.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushRequest {
    pub entries: Vec<PushEntry>,
}

/// Per-entry result of a push: the reserved seq + where to upload ciphertext.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PushedEntry {
    pub client_entry_id: Uuid,
    pub seq: i64,
    pub blob_key: String,
    pub upload_url: String,
}

/// Response body for `POST /v1/sync/push`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PushResponse {
    pub entries: Vec<PushedEntry>,
    pub high_water: i64,
}

/// One change returned to a pulling client, with a presigned download URL.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangeItem {
    pub seq: i64,
    pub entity_type: String,
    pub op: String,
    pub blob_key: String,
    pub byte_size: i64,
    pub content_hash: String,
    pub download_url: String,
}

/// Response body for `GET /v1/sync/changes`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangesResponse {
    pub entries: Vec<ChangeItem>,
    pub snapshot_seq: Option<i64>,
    pub snapshot_url: Option<String>,
    pub high_water: i64,
}

/// Request body for `POST /v1/sync/snapshot` (phase 1: begin a snapshot).
///
/// `byte_size` / `content_hash` describe the ciphertext the client is about to
/// upload. Both are optional; when given they are checked at commit time.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotRequest {
    pub seq: i64,
    #[serde(default)]
    pub byte_size: Option<i64>,
    #[serde(default)]
    pub content_hash: Option<String>,
}

/// Response body for `POST /v1/sync/snapshot` (phase 1).
///
/// Nothing has changed server-side yet except that a pending snapshot exists:
/// the live pointer is untouched and no journal entries were deleted. The
/// client must `PUT` the bytes to `upload_url`, then call
/// `POST /v1/sync/snapshot/commit` with `snapshot_id` before `expires_at`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotResponse {
    pub snapshot_id: Uuid,
    pub seq: i64,
    pub snapshot_blob_key: String,
    pub upload_url: String,
    pub expires_at: DateTime<Utc>,
}

/// Request body for `POST /v1/sync/snapshot/commit` (phase 2).
///
/// `byte_size` / `content_hash` may be repeated here; if given they must agree
/// with what phase 1 declared, and `byte_size` must match the stored object.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotCommitRequest {
    pub snapshot_id: Uuid,
    #[serde(default)]
    pub byte_size: Option<i64>,
    #[serde(default)]
    pub content_hash: Option<String>,
}

/// Response body for `POST /v1/sync/snapshot/commit`: the now-live pointer.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotCommitResponse {
    pub snapshot_seq: i64,
    pub snapshot_blob_key: String,
    pub high_water: i64,
}

/// One row of `sync_snapshot_pending`: a snapshot that has been presigned but
/// not yet confirmed. Never referenced by `bootstrap`/`changes`.
#[derive(Debug, Clone, FromRow)]
pub struct PendingSnapshotRow {
    pub snapshot_id: Uuid,
    pub tenant_id: Uuid,
    pub seq: i64,
    pub blob_key: String,
    pub byte_size: Option<i64>,
    pub content_hash: Option<String>,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

/// Response body for `GET /v1/sync/bootstrap`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BootstrapResponse {
    pub snapshot_url: Option<String>,
    pub snapshot_seq: Option<i64>,
    pub entries: Vec<ChangeItem>,
    pub high_water: i64,
}

/// Passphrase-escrow envelope exchanged on `PUT/GET /v1/sync/key`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyBlob {
    /// Base64-encoded AEAD-wrapped data key.
    pub wrapped_key: String,
    /// Argon2id KDF parameters (salt + costs) as opaque JSON.
    pub kdf_params: serde_json::Value,
}
