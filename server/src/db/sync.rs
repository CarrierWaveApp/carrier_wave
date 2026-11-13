//! Database queries for the E2E-blind sync journal (Phase 2).
//!
//! `reserve_block` is the atomic per-tenant sequence allocator: it bumps
//! `sync_cursor.last_seq` by N in a single statement and returns the first seq
//! of the reserved contiguous block, so concurrent pushers never overlap and
//! the per-tenant log stays gap-free + monotonic.

use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::sync::{PendingSnapshotRow, SyncEntryRow};

/// Atomically reserve an N-wide contiguous block of sequence numbers for a
/// tenant and return the FIRST seq of that block.
///
/// The first insert seeds `last_seq = n`; subsequent calls bump it by `n`. The
/// single `INSERT ... ON CONFLICT DO UPDATE ... RETURNING` is atomic, so two
/// concurrent reservations always get disjoint blocks.
pub async fn reserve_block(pool: &PgPool, tenant: Uuid, n: i64) -> Result<i64, AppError> {
    let last_seq: i64 = sqlx::query_scalar(
        r#"
        INSERT INTO sync_cursor (tenant_id, last_seq) VALUES ($1, $2)
        ON CONFLICT (tenant_id) DO UPDATE SET last_seq = sync_cursor.last_seq + $2,
                                              updated_at = now()
        RETURNING last_seq
        "#,
    )
    .bind(tenant)
    .bind(n)
    .fetch_one(pool)
    .await?;

    Ok(last_seq - n + 1)
}

/// Bulk-insert journal entries. Idempotent: a re-push of the same
/// `(tenant_id, client_entry_id)` is ignored (no new seq is consumed because
/// the seq was reserved by the caller).
///
/// Each row is `(client_entry_id, seq, blob_key, entity_type, op, content_hash, byte_size)`.
pub async fn insert_entries(
    pool: &PgPool,
    tenant: Uuid,
    rows: &[(Uuid, i64, &str, &str, &str, &str, i64)],
) -> Result<(), AppError> {
    if rows.is_empty() {
        return Ok(());
    }

    let mut builder = sqlx::QueryBuilder::new(
        "INSERT INTO sync_entry \
         (tenant_id, seq, client_entry_id, entity_type, op, blob_key, content_hash, byte_size) ",
    );
    builder.push_values(
        rows,
        |mut b, (client_entry_id, seq, blob_key, entity_type, op, content_hash, byte_size)| {
            b.push_bind(tenant)
                .push_bind(seq)
                .push_bind(client_entry_id)
                .push_bind(*entity_type)
                .push_bind(*op)
                .push_bind(*blob_key)
                .push_bind(*content_hash)
                .push_bind(byte_size);
        },
    );
    builder.push(" ON CONFLICT (tenant_id, client_entry_id) DO NOTHING");

    builder.build().execute(pool).await?;
    Ok(())
}

/// Fetch already-stored rows for a set of `client_entry_id`s.
///
/// A push handler uses this to make re-pushes idempotent: ids that are already
/// present keep their original seq + blob key instead of consuming a new block.
pub async fn entries_for_client_ids(
    pool: &PgPool,
    tenant: Uuid,
    ids: &[Uuid],
) -> Result<Vec<SyncEntryRow>, AppError> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }

    let rows = sqlx::query_as::<_, SyncEntryRow>(
        r#"
        SELECT tenant_id, seq, client_entry_id, entity_type, op, blob_key,
               byte_size, content_hash, created_at
        FROM sync_entry
        WHERE tenant_id = $1 AND client_entry_id = ANY($2)
        "#,
    )
    .bind(tenant)
    .bind(ids)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Return entries with `seq > since`, in ascending seq order, capped at `limit`.
pub async fn changes_since(
    pool: &PgPool,
    tenant: Uuid,
    since: i64,
    limit: i64,
) -> Result<Vec<SyncEntryRow>, AppError> {
    let limit = limit.clamp(1, 1000);
    let rows = sqlx::query_as::<_, SyncEntryRow>(
        r#"
        SELECT tenant_id, seq, client_entry_id, entity_type, op, blob_key,
               byte_size, content_hash, created_at
        FROM sync_entry
        WHERE tenant_id = $1 AND seq > $2
        ORDER BY seq ASC
        LIMIT $3
        "#,
    )
    .bind(tenant)
    .bind(since)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Delete journal entries with `seq < below` for a tenant, returning the blob
/// keys that were removed so the caller can best-effort GC the matching object
/// store blobs. Used during snapshot compaction (v1 = immediate best-effort).
pub async fn delete_entries_below(
    pool: &PgPool,
    tenant: Uuid,
    below: i64,
) -> Result<Vec<String>, AppError> {
    let keys: Vec<(String,)> = sqlx::query_as(
        r#"
        DELETE FROM sync_entry
        WHERE tenant_id = $1 AND seq < $2
        RETURNING blob_key
        "#,
    )
    .bind(tenant)
    .bind(below)
    .fetch_all(pool)
    .await?;

    Ok(keys.into_iter().map(|(k,)| k).collect())
}

/// Fetch the tenant's cursor: `(last_seq, snapshot_seq, snapshot_blob_key)`.
/// Returns `None` if the tenant has never reserved a block.
pub async fn get_cursor(
    pool: &PgPool,
    tenant: Uuid,
) -> Result<Option<(i64, Option<i64>, Option<String>)>, AppError> {
    let row: Option<(i64, Option<i64>, Option<String>)> = sqlx::query_as(
        r#"
        SELECT last_seq, snapshot_seq, snapshot_blob_key
        FROM sync_cursor
        WHERE tenant_id = $1
        "#,
    )
    .bind(tenant)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

// ---- Two-phase snapshots (CAR-334) ------------------------------------------
//
// A snapshot is first recorded as PENDING (`sync_snapshot_pending`) when the
// upload is presigned, and only promoted to the live pointer on `sync_cursor`
// once the client has confirmed the upload and the server has verified the
// object exists. The live pointer is the only thing bootstrap/changes read.

/// Record a pending snapshot: the client has been handed a presigned PUT for
/// `blob_key` but nothing is live yet.
pub async fn insert_pending_snapshot(
    pool: &PgPool,
    row: &PendingSnapshotRow,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO sync_snapshot_pending
            (snapshot_id, tenant_id, seq, blob_key, byte_size, content_hash, created_at, expires_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
    )
    .bind(row.snapshot_id)
    .bind(row.tenant_id)
    .bind(row.seq)
    .bind(&row.blob_key)
    .bind(row.byte_size)
    .bind(&row.content_hash)
    .bind(row.created_at)
    .bind(row.expires_at)
    .execute(pool)
    .await?;

    Ok(())
}

/// Fetch a pending snapshot by id, scoped to the tenant so one account can
/// never commit (or learn about) another account's pending snapshot.
pub async fn get_pending_snapshot(
    pool: &PgPool,
    tenant: Uuid,
    snapshot_id: Uuid,
) -> Result<Option<PendingSnapshotRow>, AppError> {
    let row = sqlx::query_as::<_, PendingSnapshotRow>(
        r#"
        SELECT snapshot_id, tenant_id, seq, blob_key, byte_size, content_hash,
               created_at, expires_at
        FROM sync_snapshot_pending
        WHERE tenant_id = $1 AND snapshot_id = $2
        "#,
    )
    .bind(tenant)
    .bind(snapshot_id)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

/// Remove one pending snapshot (committed, abandoned, or rejected). Returns
/// whether a row was deleted.
pub async fn delete_pending_snapshot(
    pool: &PgPool,
    tenant: Uuid,
    snapshot_id: Uuid,
) -> Result<bool, AppError> {
    let result =
        sqlx::query("DELETE FROM sync_snapshot_pending WHERE tenant_id = $1 AND snapshot_id = $2")
            .bind(tenant)
            .bind(snapshot_id)
            .execute(pool)
            .await?;

    Ok(result.rows_affected() > 0)
}

/// Purge a tenant's pending snapshots that are past `expires_at` (or, when
/// `below_or_at` is given, that target a seq the live pointer has already
/// reached, since they can never commit). Returns the blob keys so the caller
/// can best-effort delete any bytes that were uploaded but never committed.
pub async fn purge_stale_pending_snapshots(
    pool: &PgPool,
    tenant: Uuid,
    now: chrono::DateTime<chrono::Utc>,
    below_or_at: Option<i64>,
) -> Result<Vec<String>, AppError> {
    let keys: Vec<(String,)> = sqlx::query_as(
        r#"
        DELETE FROM sync_snapshot_pending
        WHERE tenant_id = $1
          AND (expires_at <= $2 OR ($3::BIGINT IS NOT NULL AND seq <= $3))
        RETURNING blob_key
        "#,
    )
    .bind(tenant)
    .bind(now)
    .bind(below_or_at)
    .fetch_all(pool)
    .await?;

    Ok(keys.into_iter().map(|(k,)| k).collect())
}

/// Promote a verified snapshot to the live pointer — forward only.
///
/// The `UPDATE` is guarded so the pointer can never move backward or past the
/// high-water mark, even under a concurrent commit: it only fires when
/// `seq > COALESCE(snapshot_seq, 0)` and `seq <= last_seq`. Returns
/// `Some(previous_snapshot_blob_key)` (which may be `None` inside if there was
/// no earlier snapshot) when the pointer moved, or `None` when the guard
/// rejected the move. Never inserts a cursor row: a tenant with no reserved
/// seqs has nothing to snapshot.
pub async fn commit_snapshot(
    pool: &PgPool,
    tenant: Uuid,
    seq: i64,
    blob_key: &str,
) -> Result<Option<Option<String>>, AppError> {
    let row: Option<(Option<String>,)> = sqlx::query_as(
        r#"
        WITH prev AS (
            SELECT snapshot_blob_key FROM sync_cursor WHERE tenant_id = $1
        ),
        moved AS (
            UPDATE sync_cursor
            SET snapshot_seq = $2, snapshot_blob_key = $3, updated_at = now()
            WHERE tenant_id = $1
              AND $2 > COALESCE(snapshot_seq, 0)
              AND $2 <= last_seq
            RETURNING tenant_id
        )
        SELECT prev.snapshot_blob_key FROM moved JOIN prev ON TRUE
        "#,
    )
    .bind(tenant)
    .bind(seq)
    .bind(blob_key)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|(prev,)| prev))
}

/// Upsert the tenant's passphrase-escrow key blob.
pub async fn upsert_key_blob(
    pool: &PgPool,
    tenant: Uuid,
    wrapped: &[u8],
    kdf: serde_json::Value,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO sync_key_blob (tenant_id, wrapped_key, kdf_params)
        VALUES ($1, $2, $3)
        ON CONFLICT (tenant_id) DO UPDATE SET wrapped_key = $2,
                                              kdf_params = $3,
                                              updated_at = now()
        "#,
    )
    .bind(tenant)
    .bind(wrapped)
    .bind(kdf)
    .execute(pool)
    .await?;

    Ok(())
}

/// Fetch the tenant's escrow key blob: `(wrapped_key, kdf_params)`.
pub async fn get_key_blob(
    pool: &PgPool,
    tenant: Uuid,
) -> Result<Option<(Vec<u8>, serde_json::Value)>, AppError> {
    let row: Option<(Vec<u8>, serde_json::Value)> = sqlx::query_as(
        r#"
        SELECT wrapped_key, kdf_params
        FROM sync_key_blob
        WHERE tenant_id = $1
        "#,
    )
    .bind(tenant)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

// ---- Admin: orphaned participant-tenant data --------------------------------
//
// Before sync required an account (email-verified) tenant, legacy `fd_` device
// tokens synced under `participants.id`. Those datasets are now unreachable by
// clients ("orphans"). The queries below let a superuser inspect them and
// re-key one onto the account that owns the same callsign.

/// One orphaned participant-tenant sync dataset.
#[derive(Debug, sqlx::FromRow)]
pub struct OrphanTenant {
    pub participant_id: Uuid,
    pub callsign: String,
    pub entry_count: i64,
    pub total_bytes: i64,
    pub has_key_blob: bool,
    pub last_seq: i64,
    pub last_activity: Option<chrono::DateTime<chrono::Utc>>,
    /// The account that now owns this callsign, if one exists — the natural
    /// adoption target.
    pub account_id: Option<Uuid>,
}

/// Every sync tenant that is a `participants.id` (i.e. legacy, account-less),
/// with enough context for an admin to decide what to do with it.
pub async fn list_orphan_tenants(pool: &PgPool) -> Result<Vec<OrphanTenant>, AppError> {
    let rows = sqlx::query_as::<_, OrphanTenant>(
        r#"
        WITH sync_tenants AS (
            SELECT tenant_id FROM sync_cursor
            UNION
            SELECT tenant_id FROM sync_key_blob
            UNION
            SELECT DISTINCT tenant_id FROM sync_entry
        )
        SELECT p.id                                   AS participant_id,
               p.callsign                             AS callsign,
               COALESCE(e.entry_count, 0)             AS entry_count,
               COALESCE(e.total_bytes, 0)             AS total_bytes,
               (kb.tenant_id IS NOT NULL)             AS has_key_blob,
               COALESCE(c.last_seq, 0)                AS last_seq,
               GREATEST(c.updated_at, kb.updated_at, e.last_created) AS last_activity,
               ac.account_id                          AS account_id
        FROM sync_tenants st
        JOIN participants p ON p.id = st.tenant_id
        LEFT JOIN sync_cursor c ON c.tenant_id = st.tenant_id
        LEFT JOIN sync_key_blob kb ON kb.tenant_id = st.tenant_id
        LEFT JOIN LATERAL (
            SELECT COUNT(*)                       AS entry_count,
                   COALESCE(SUM(byte_size), 0)::BIGINT AS total_bytes,
                   MAX(created_at)                AS last_created
            FROM sync_entry WHERE tenant_id = st.tenant_id
        ) e ON TRUE
        LEFT JOIN account_callsigns ac ON UPPER(ac.callsign) = UPPER(p.callsign)
        ORDER BY p.callsign
        "#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// What already lives under a would-be adoption target tenant. Adoption only
/// proceeds when all three are empty — merging two journals would need seq
/// rewriting and is left to manual surgery.
#[derive(Debug, sqlx::FromRow)]
pub struct TenantUsage {
    pub entry_count: i64,
    pub has_cursor: bool,
    pub has_key_blob: bool,
}

pub async fn tenant_usage(pool: &PgPool, tenant: Uuid) -> Result<TenantUsage, AppError> {
    let usage = sqlx::query_as::<_, TenantUsage>(
        r#"
        SELECT (SELECT COUNT(*) FROM sync_entry WHERE tenant_id = $1)              AS entry_count,
               EXISTS(SELECT 1 FROM sync_cursor WHERE tenant_id = $1)              AS has_cursor,
               EXISTS(SELECT 1 FROM sync_key_blob WHERE tenant_id = $1)            AS has_key_blob
        "#,
    )
    .bind(tenant)
    .fetch_one(pool)
    .await?;

    Ok(usage)
}

/// Re-key an orphan participant tenant's sync rows onto an account tenant, in
/// one transaction. Blob keys are NOT rewritten: they are opaque object-store
/// pointers that still resolve (existing rows keep their `{participant}/...`
/// paths; new writes use `{account}/...`). Returns the number of journal
/// entries moved.
pub async fn adopt_orphan_tenant(
    pool: &PgPool,
    participant: Uuid,
    account: Uuid,
) -> Result<i64, AppError> {
    let mut tx = pool.begin().await?;

    let moved = sqlx::query("UPDATE sync_entry SET tenant_id = $2 WHERE tenant_id = $1")
        .bind(participant)
        .bind(account)
        .execute(&mut *tx)
        .await?
        .rows_affected();
    sqlx::query("UPDATE sync_cursor SET tenant_id = $2 WHERE tenant_id = $1")
        .bind(participant)
        .bind(account)
        .execute(&mut *tx)
        .await?;
    sqlx::query("UPDATE sync_key_blob SET tenant_id = $2 WHERE tenant_id = $1")
        .bind(participant)
        .bind(account)
        .execute(&mut *tx)
        .await?;
    // A pending (uncommitted) snapshot can only be committed by its tenant, so
    // it has to travel with the rest of the dataset.
    sqlx::query("UPDATE sync_snapshot_pending SET tenant_id = $2 WHERE tenant_id = $1")
        .bind(participant)
        .bind(account)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(moved as i64)
}
