//! E2E escrow + HTTPS sync-transport driver, exposed over UniFFI.
//!
//! This module is the cross-language surface for Phase 6 of the sync-server
//! plan. It exposes two independent capabilities:
//!
//! 1. **Passphrase escrow** ([`create_sync_escrow`] / [`open_sync_escrow`]) —
//!    thin, fully-wired wrappers over [`cw_crypto::escrow`]. The host drives the
//!    key-setup UI, persists the wrapped blob server-side, and keeps the live
//!    32-byte data key in the platform keychain. These are deterministic, have
//!    no external dependencies, and are unit-tested below.
//!
//! 2. **One-shot sync driver** ([`sync_run_once`]) — constructs a real
//!    [`HttpSyncTransport`], pushes the dirty QSO backlog, pulls inbound
//!    journal payloads, and applies them to the [`FieldStore`] (merge on an
//!    existing row, insert when new, soft-delete on a `Delete` op). This is a
//!    synchronous export: the transport owns its own Tokio runtime and bridges
//!    `reqwest` via `block_on`, so wrapping it in `async_runtime = "tokio"`
//!    would panic with a nested-runtime error.
//!
//! ## Wire parity (Phase 7 full-field port)
//!
//! The QSO payload shape is `cw_sync::SyncQso` — now the **full** `QSOFields`
//! wire format, field-for-field byte-compatible with what the Swift journal
//! `JSONEncoder` emits (camelCase keys, `.secondsSince1970` dates, `.base64`
//! data, `String`-raw `importSource`). A Rust-driven sync and a Swift-driven
//! sync round-trip every modeled field. The handful of store columns that are
//! *not* in the Swift `QSOFields` wire struct (`contest_*`, `aoa_code`,
//! `callsign_change_note`, `original_callsign`, `dirty`) have no wire slot and
//! are preserved on an inbound merge — we only ever overwrite the modeled wire
//! fields on an existing row — mirroring the Swift `QSOJournalStore` seam.
//! Flipping this driver on as the sync authority still depends on the
//! two-device round-trip verification.
//!
//! `SyncRunResult::high_water` is the highest server sequence the transport
//! observed across the pass's push/pull responses ([`HttpSyncTransport`] tracks
//! it) — the host persists it durably and passes it back as `since_seq` on the
//! next run. Durable cursor storage is owned by the host.

use std::sync::Arc;

use base64::Engine as _;
use chrono::Utc;
use cw_domain::mode::is_metadata_mode;
use cw_store::{LoggingSession, LoggingSessionFilter, Qso, QsoFilter, Store, MAX_FETCH_LIMIT};
use cw_sync::{
    merge_logging_session, merge_qso, HttpSyncTransport, JournalEntityType, JournalOperation,
    JournalPayload, LoggingSessionPayload, SyncQso, SyncedConfigPayload, SyncTransport,
};

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FfiQso, FieldStore};

/// KV key holding this install's stable journal device id (minted on first use).
const SYNC_DEVICE_ID_KEY: &str = "sync_device_id";
/// KV key holding the monotonic per-device outbound journal sequence number.
const SYNC_SEQUENCE_KEY: &str = "sync_local_sequence";

// ---------------------------------------------------------------------------
// Escrow surface
// ---------------------------------------------------------------------------

/// Result of [`create_sync_escrow`]: the persistable escrow envelope (base64
/// wrapped key + KDF params JSON) plus the live 32-byte data key for the host
/// keychain. The server only ever stores `wrapped_key_b64` + `kdf_params_json`.
#[derive(uniffi::Record)]
pub struct SyncEscrowResult {
    pub wrapped_key_b64: String,
    pub kdf_params_json: String,
    pub data_key: Vec<u8>,
}

/// Create a fresh sync escrow from `passphrase`: mints a random data key,
/// derives an Argon2id KEK, wraps the key, and returns the envelope + the live
/// data key. Wraps [`cw_crypto::escrow::create_escrow`].
#[uniffi::export]
pub fn create_sync_escrow(passphrase: String) -> Result<SyncEscrowResult, CwError> {
    let (blob, data_key) = cw_crypto::escrow::create_escrow(&passphrase)?;
    let wrapped_key_b64 = base64::engine::general_purpose::STANDARD.encode(&blob.wrapped_key);
    let kdf_params_json = serde_json::to_string(&blob.kdf)
        .map_err(|err| CwError::Crypto { reason: format!("kdf params json: {err}") })?;
    Ok(SyncEscrowResult { wrapped_key_b64, kdf_params_json, data_key: data_key.to_vec() })
}

/// Recover the 32-byte data key from a persisted escrow envelope using
/// `passphrase`. Fails (`CwError::Crypto`) on a wrong passphrase or a malformed
/// envelope. Wraps [`cw_crypto::escrow::open_escrow`].
#[uniffi::export]
pub fn open_sync_escrow(
    passphrase: String,
    wrapped_key_b64: String,
    kdf_params_json: String,
) -> Result<Vec<u8>, CwError> {
    let wrapped_key = base64::engine::general_purpose::STANDARD
        .decode(wrapped_key_b64.as_bytes())
        .map_err(|err| CwError::Crypto { reason: format!("base64: {err}") })?;
    let kdf: cw_crypto::KdfParams = serde_json::from_str(&kdf_params_json)
        .map_err(|err| CwError::Crypto { reason: format!("kdf params json: {err}") })?;
    let blob = cw_crypto::EscrowBlob { kdf, wrapped_key };
    let data_key = cw_crypto::escrow::open_escrow(&passphrase, &blob)?;
    Ok(data_key.to_vec())
}

/// Wrap an EXISTING at-rest key (`key`, exactly 32 bytes) under `passphrase`
/// for LOCAL, offline recovery. Unlike [`create_sync_escrow`] this does not mint
/// a new key — the store's key is unchanged; the returned envelope is a
/// recoverable, passphrase-protected backup to cache on-device (App Group
/// sidecar). Recover with [`open_sync_escrow`], which returns the same 32 bytes.
/// Wraps [`cw_crypto::escrow::wrap_key_escrow`].
#[uniffi::export]
pub fn create_key_escrow(passphrase: String, key: Vec<u8>) -> Result<SyncKeyEnvelope, CwError> {
    let key_arr: [u8; 32] = key
        .as_slice()
        .try_into()
        .map_err(|_| CwError::Crypto { reason: "at-rest key must be 32 bytes".into() })?;
    let blob = cw_crypto::escrow::wrap_key_escrow(&passphrase, &key_arr)?;
    let wrapped_key_b64 = base64::engine::general_purpose::STANDARD.encode(&blob.wrapped_key);
    let kdf_params_json = serde_json::to_string(&blob.kdf)
        .map_err(|err| CwError::Crypto { reason: format!("kdf params json: {err}") })?;
    Ok(SyncKeyEnvelope { wrapped_key_b64, kdf_params_json })
}

/// The escrow envelope as stored server-side on `PUT/GET /v1/sync/key`:
/// base64 wrapped key + Argon2id KDF params JSON. Contains no usable key
/// material without the passphrase.
#[derive(uniffi::Record)]
pub struct SyncKeyEnvelope {
    pub wrapped_key_b64: String,
    pub kdf_params_json: String,
}

/// Upload the escrow envelope to the sync server (`PUT /v1/sync/key`) so other
/// devices can recover the data key from the passphrase. Idempotent upsert.
#[uniffi::export]
pub fn sync_put_key(
    base_url: String,
    bearer: String,
    envelope: SyncKeyEnvelope,
) -> Result<(), CwError> {
    cw_sync::http_transport::put_key_blob(
        &base_url,
        &bearer,
        &envelope.wrapped_key_b64,
        &envelope.kdf_params_json,
    )?;
    Ok(())
}

/// Fetch the escrow envelope from the sync server (`GET /v1/sync/key`), or
/// `None` when the account has never enrolled — the "create a fresh escrow"
/// signal for first-device setup.
#[uniffi::export]
pub fn sync_get_key(base_url: String, bearer: String) -> Result<Option<SyncKeyEnvelope>, CwError> {
    let envelope = cw_sync::http_transport::get_key_blob(&base_url, &bearer)?;
    Ok(envelope.map(|(wrapped_key_b64, kdf_params_json)| SyncKeyEnvelope {
        wrapped_key_b64,
        kdf_params_json,
    }))
}

// ---------------------------------------------------------------------------
// Sync driver surface
// ---------------------------------------------------------------------------

/// Outcome of one [`sync_run_once`] pass. `pulled`/`pushed` count journal
/// payloads moved this run; `high_water` is the highest server sequence seen
/// in the pass's responses — the cursor the host persists for the next run.
#[derive(uniffi::Record)]
pub struct SyncRunResult {
    pub pulled: u32,
    pub pushed: u32,
    pub high_water: i64,
}

/// Run one outbound-then-inbound sync pass against the E2E-blind sync server.
///
/// `data_key` is the 32-byte key recovered from the escrow (see
/// [`open_sync_escrow`]); `since_seq` is the host-held pull cursor. Network I/O
/// runs with no store lock held; store mutations take a short critical section
/// and the change notification fires after the lock is released.
#[uniffi::export]
pub fn sync_run_once(
    store: Arc<FieldStore>,
    base_url: String,
    bearer: String,
    data_key: Vec<u8>,
    since_seq: i64,
) -> Result<SyncRunResult, CwError> {
    let key = data_key_array(&data_key)?;
    let mut transport = HttpSyncTransport::new(base_url, bearer, key)?;
    // Pull THEN push: with a persisted cursor this means the pull never
    // re-downloads the entries we're about to push, and `high_water` after the
    // push is the cursor the host persists for next time.
    let pulled = run_pull(&store, &mut transport, since_seq)?;
    let pushed = run_push(&store, &mut transport)?;
    Ok(SyncRunResult { pulled, pushed, high_water: transport.high_water() })
}

/// Result of [`sync_run_push`]: QSOs pushed + the server high-water after the
/// push, which the host persists as the pull cursor.
#[derive(uniffi::Record)]
pub struct SyncPushResult {
    pub pushed: u32,
    pub high_water: i64,
}

/// Result of [`sync_run_pull`]: QSOs pulled + the server high-water observed.
#[derive(uniffi::Record)]
pub struct SyncPullResult {
    pub pulled: u32,
    pub high_water: i64,
}

/// One row the inbound half of a pass touched. Lets a host that keeps a
/// secondary replica of the store (CW Sweep's SwiftData follower, which its UI
/// still reads) refresh exactly those rows instead of diffing whole tables.
///
/// `deleted` is true only when the row no longer exists in the store (session
/// hard-deletes). A QSO delete is a soft delete (`is_hidden = true`), so it is
/// reported as an upsert: the replica re-fetches the row and sees the flag.
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SyncAppliedKey {
    pub table: FfiStoreTable,
    pub id: String,
    pub deleted: bool,
}

/// Result of [`sync_run_pull_detailed`]: [`SyncPullResult`] plus the rows the
/// pull applied, de-duplicated (last state wins) in apply order.
#[derive(uniffi::Record)]
pub struct SyncPullDetail {
    pub pulled: u32,
    pub high_water: i64,
    pub applied: Vec<SyncAppliedKey>,
}

/// [`sync_run_pull`] that also reports which rows it applied. A separate export
/// (rather than a new field on `SyncPullResult`) so the committed Android
/// bindings stay valid until they are regenerated.
#[uniffi::export]
pub fn sync_run_pull_detailed(
    store: Arc<FieldStore>,
    base_url: String,
    bearer: String,
    data_key: Vec<u8>,
    since_seq: i64,
) -> Result<SyncPullDetail, CwError> {
    let key = data_key_array(&data_key)?;
    let mut transport = HttpSyncTransport::new(base_url, bearer, key)?;
    let (pulled, applied) = run_pull_collect(&store, &mut transport, since_seq)?;
    Ok(SyncPullDetail { pulled, high_water: transport.high_water(), applied })
}

/// Outbound half of a sync pass (gather dirty → push → clear, batched). Exposed
/// separately so the host can surface an "uploading" phase distinct from the
/// "downloading" one, and persist the returned `high_water` as its cursor.
#[uniffi::export]
pub fn sync_run_push(
    store: Arc<FieldStore>,
    base_url: String,
    bearer: String,
    data_key: Vec<u8>,
) -> Result<SyncPushResult, CwError> {
    let key = data_key_array(&data_key)?;
    let mut transport = HttpSyncTransport::new(base_url, bearer, key)?;
    let pushed = run_push(&store, &mut transport)?;
    Ok(SyncPushResult { pushed, high_water: transport.high_water() })
}

/// Inbound half of a sync pass (pull → apply). `since_seq` is the host-held pull
/// cursor; pulling only entries newer than it is what stops a sync from
/// re-downloading data already applied.
#[uniffi::export]
pub fn sync_run_pull(
    store: Arc<FieldStore>,
    base_url: String,
    bearer: String,
    data_key: Vec<u8>,
    since_seq: i64,
) -> Result<SyncPullResult, CwError> {
    let key = data_key_array(&data_key)?;
    let mut transport = HttpSyncTransport::new(base_url, bearer, key)?;
    let pulled = run_pull(&store, &mut transport, since_seq)?;
    Ok(SyncPullResult { pulled, high_water: transport.high_water() })
}

/// Drain the dirty QSO backlog in bounded batches (each fetch is capped at
/// `MAX_FETCH_LIMIT`), pushing one blob per batch and clearing the pushed ids
/// (CAR-245 guard) between batches. Looping is what makes 50-100k-QSO logs
/// upload at all — a single gather only ever sees the first page. No store lock
/// is held across the network push. Returns the total QSOs pushed.
fn run_push(store: &FieldStore, transport: &mut HttpSyncTransport) -> Result<u32, CwError> {
    // Backstop against a pathological non-draining backlog (e.g. rows edited
    // faster than we sync). 1M batches ≫ any real log; converges far sooner.
    const MAX_BATCHES: usize = 1_000_000;
    let mut total_pushed: u32 = 0;
    for _ in 0..MAX_BATCHES {
        let gathered_at = Utc::now().timestamp();
        let (outbound, pushed_ids, fetched) = {
            let locked = store.inner.lock().expect("store mutex poisoned");
            gather_dirty_payload(&locked)?
        };
        if let Some(payload) = outbound {
            transport.push(std::slice::from_ref(&payload))?;
            total_pushed += pushed_ids.len() as u32;
            let locked = store.inner.lock().expect("store mutex poisoned");
            locked.clear_dirty("qso", &pushed_ids, Some(gathered_at))?;
        }
        // A batch that was all metadata (outbound None) still made progress by
        // clearing those rows inside gather, so keep going while anything was
        // fetched; stop once the backlog is fully drained.
        if fetched == 0 {
            break;
        }
    }
    // Additive second phase: drain the dirty synced_config backlog as its own
    // payloads (one entity type per payload). This is entirely separate from the
    // QSO gather loop above — the QSO wire path is unchanged.
    total_pushed += push_synced_configs(store, transport)?;
    // Additive third phase: drain the dirty logging_session backlog, likewise as
    // its own single-entity-type payloads. Gated by `SESSION_SYNC_PUSH_ENABLED`.
    total_pushed += push_logging_sessions(store, transport)?;
    Ok(total_pushed)
}

/// Master gate for pushing `synced_config` entries onto the sync wire.
///
/// OFF until a `JournalOperation`-tolerant client (one that decodes an unknown
/// `"op"` tag to `JournalOperation::Unknown` instead of aborting the pull batch)
/// is the floor version across ALL of a user's devices. The currently-released
/// client has no such tolerance, so a `UpsertSyncedConfig` op on the wire would
/// abort its entire pull — QSO ops included. Everything else stays wired up (the
/// `synced_config` table, inbound `apply_inbound` handling, brag-sheet local
/// storage) so flipping this to `true` later is the only change needed to enable
/// config sync. See the brag-sheet port design doc.
const CONFIG_SYNC_PUSH_ENABLED: bool = false;

/// Drain the dirty `synced_config` backlog, pushing one payload per gather and
/// clearing the pushed ids (CAR-245 guard) between pushes. Small in practice
/// (one row per config type), but bounded-and-looping to match the QSO drain.
/// Returns the number of config rows pushed.
///
/// No-op while [`CONFIG_SYNC_PUSH_ENABLED`] is `false`: nothing is gathered and
/// nothing is cleared, so no `UpsertSyncedConfig` payload ever reaches the wire.
fn push_synced_configs(store: &FieldStore, transport: &mut HttpSyncTransport) -> Result<u32, CwError> {
    const MAX_BATCHES: usize = 1_000_000;
    let mut total_pushed: u32 = 0;
    for _ in 0..MAX_BATCHES {
        let gathered_at = Utc::now().timestamp();
        let (outbound, pushed_ids) = {
            let locked = store.inner.lock().expect("store mutex poisoned");
            gather_outbound_synced_config_payload(&locked)?
        };
        let Some(payload) = outbound else { break };
        transport.push(std::slice::from_ref(&payload))?;
        total_pushed += pushed_ids.len() as u32;
        let locked = store.inner.lock().expect("store mutex poisoned");
        locked.clear_dirty("syncedConfig", &pushed_ids, Some(gathered_at))?;
    }
    Ok(total_pushed)
}

/// The single gate the push loop consults: returns the payload that would go on
/// the wire, or `(None, _)` when [`CONFIG_SYNC_PUSH_ENABLED`] is `false`. This is
/// the one place the gate is applied, so no `UpsertSyncedConfig` op can reach the
/// wire while gated even though `gather_dirty_synced_config_payload` (and the
/// dirty backlog it reads) stay fully functional for the local round-trip and
/// for the day the floor version supports tolerant decoding.
fn gather_outbound_synced_config_payload(
    store: &Store,
) -> Result<(Option<JournalPayload>, Vec<String>), CwError> {
    if !CONFIG_SYNC_PUSH_ENABLED {
        return Ok((None, Vec::new()));
    }
    gather_dirty_synced_config_payload(store)
}

/// Pull remote payloads since `since_seq` and apply them, notifying observers.
fn run_pull(
    store: &FieldStore,
    transport: &mut HttpSyncTransport,
    since_seq: i64,
) -> Result<u32, CwError> {
    run_pull_collect(store, transport, since_seq).map(|(pulled, _)| pulled)
}

/// Pull + apply, also returning the rows touched (see [`SyncAppliedKey`]).
fn run_pull_collect(
    store: &FieldStore,
    transport: &mut HttpSyncTransport,
    since_seq: i64,
) -> Result<(u32, Vec<SyncAppliedKey>), CwError> {
    let incoming = transport.pull(since_seq)?;
    // Count QSOs (operations), not payloads, so "downloaded" is comparable to
    // the "uploaded" QSO count the host shows.
    let pulled: u32 = incoming.iter().map(|payload| payload.operations.len() as u32).sum();
    let mut applied: Vec<SyncAppliedKey> = Vec::new();
    if !incoming.is_empty() {
        {
            let locked = store.inner.lock().expect("store mutex poisoned");
            // One transaction for the whole pull: with `synchronous = FULL` +
            // fullfsync a per-row autocommit costs two disk barriers per QSO,
            // which made a first pull of a few thousand rows take tens of
            // seconds. Upserts are idempotent, so a failed batch simply replays
            // on the next pass (the cursor only advances on success).
            locked.in_transaction_with(|| {
                for payload in &incoming {
                    apply_inbound(&locked, payload, &mut applied)?;
                }
                Ok::<(), CwError>(())
            })?;
        }
        store.notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        // If any inbound op touched synced_config, also notify that table so
        // config consumers (brag sheet) re-fetch. QSO behavior is unchanged.
        let touched_synced_config = incoming.iter().any(|payload| {
            payload
                .operations
                .iter()
                .any(|op| op.entity_type() == Some(JournalEntityType::SyncedConfig))
        });
        if touched_synced_config {
            store.notify(FfiStoreChange {
                table: FfiStoreTable::SyncedConfig,
                kind: FfiChangeKind::Upsert,
            });
        }
        // If any inbound op touched logging_session, notify that table so session
        // views (iOS/Android) re-fetch and render the synced session. QSO behavior
        // is unchanged. Covers both upserts and session deletes.
        let touched_sessions = incoming.iter().any(|payload| {
            payload
                .operations
                .iter()
                .any(|op| op.entity_type() == Some(JournalEntityType::LoggingSession))
        });
        if touched_sessions {
            store.notify(FfiStoreChange {
                table: FfiStoreTable::LoggingSession,
                kind: FfiChangeKind::Upsert,
            });
        }
    }
    Ok((pulled, dedupe_applied(applied)))
}

/// Keep one entry per (table, id), at the position of its last occurrence so a
/// later delete or upsert in the same pull wins.
fn dedupe_applied(applied: Vec<SyncAppliedKey>) -> Vec<SyncAppliedKey> {
    let mut out: Vec<SyncAppliedKey> = Vec::with_capacity(applied.len());
    for key in applied {
        if let Some(pos) = out.iter().position(|k| k.table == key.table && k.id == key.id) {
            out.remove(pos);
        }
        out.push(key);
    }
    out
}

// ---------------------------------------------------------------------------
// Driver internals (free fns over `&Store` so they're testable without HTTP)
// ---------------------------------------------------------------------------

/// Coerce a host-supplied key blob into a fixed 32-byte array.
fn data_key_array(bytes: &[u8]) -> Result<[u8; 32], CwError> {
    bytes.try_into().map_err(|_| CwError::Crypto {
        reason: format!("data key must be 32 bytes, got {}", bytes.len()),
    })
}

/// Build a single outbound [`JournalPayload`] from the dirty QSO backlog.
///
/// Returns `(payload, pushed_ids)` where `pushed_ids` are the non-metadata QSO
/// ids whose dirty flag the caller clears once the push succeeds. Metadata-mode
/// rows (WEATHER/SOLAR/NOTE) never sync, so they are cleared here immediately
/// and excluded from the payload (mirrors the Swift outbound skip). Returns
/// `(None, _)` when there is nothing to emit.
fn gather_dirty_payload(
    store: &Store,
) -> Result<(Option<JournalPayload>, Vec<String>, usize), CwError> {
    let filter = QsoFilter { dirty_only: true, ..Default::default() };
    let dirty = store.fetch_qsos(&filter, MAX_FETCH_LIMIT, 0)?;
    let fetched = dirty.len();

    let mut ops: Vec<JournalOperation> = Vec::new();
    let mut pushed_ids: Vec<String> = Vec::new();
    let mut metadata_ids: Vec<String> = Vec::new();
    for qso in dirty {
        if is_metadata_mode(qso.mode.as_deref().unwrap_or("")) {
            metadata_ids.push(qso.id.clone());
            continue;
        }
        pushed_ids.push(qso.id.clone());
        ops.push(JournalOperation::upsert_qso(qso_to_sync(&qso)));
    }

    // Metadata-mode rows never emit an op but must still be cleared so they
    // don't wedge the dirty backlog (no CAR-245 guard — they never sync).
    if !metadata_ids.is_empty() {
        store.clear_dirty("qso", &metadata_ids, None)?;
    }

    if ops.is_empty() {
        return Ok((None, pushed_ids, fetched));
    }

    // Content-address the entry id: an unchanged batch hashes to the same UUID
    // every run, so the server's `ON CONFLICT (tenant, client_entry_id) DO
    // NOTHING` dedups a re-upload instead of appending a duplicate. Falls back
    // to a random id (no dedup that run, but never panics) if serialization
    // somehow fails.
    let entry_id = match serde_json::to_vec(&ops) {
        Ok(bytes) => uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, &bytes).to_string(),
        Err(_) => uuid::Uuid::new_v4().to_string(),
    };
    let payload = JournalPayload::new(
        entry_id,
        device_id(store)?,
        Utc::now().timestamp(),
        next_sequence(store)?,
        ops,
    );
    Ok((Some(payload), pushed_ids, fetched))
}

/// Build a single outbound [`JournalPayload`] from the dirty synced_config
/// backlog (its OWN entity type — never mixed with QSO ops). Returns
/// `(payload, pushed_ids)` where `pushed_ids` are the row ids whose dirty flag
/// the caller clears after the push succeeds, or `(None, _)` when nothing is
/// dirty. The entry id is content-addressed (like the QSO gather) so an
/// unchanged batch dedups server-side instead of appending a duplicate.
fn gather_dirty_synced_config_payload(
    store: &Store,
) -> Result<(Option<JournalPayload>, Vec<String>), CwError> {
    let dirty = store.fetch_dirty_synced_configs()?;
    if dirty.is_empty() {
        return Ok((None, Vec::new()));
    }

    let mut ops: Vec<JournalOperation> = Vec::with_capacity(dirty.len());
    let mut pushed_ids: Vec<String> = Vec::with_capacity(dirty.len());
    for row in dirty {
        pushed_ids.push(row.id.clone());
        ops.push(JournalOperation::UpsertSyncedConfig(SyncedConfigPayload {
            id: row.id,
            config_type: row.config_type,
            data: row.data,
            modified_at: row.modified_at,
        }));
    }

    let entry_id = match serde_json::to_vec(&ops) {
        Ok(bytes) => uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, &bytes).to_string(),
        Err(_) => uuid::Uuid::new_v4().to_string(),
    };
    let payload = JournalPayload::new(
        entry_id,
        device_id(store)?,
        Utc::now().timestamp(),
        next_sequence(store)?,
        ops,
    );
    Ok((Some(payload), pushed_ids))
}

// ---------------------------------------------------------------------------
// LoggingSession outbound (the `render sessions cross-device` push path)
// ---------------------------------------------------------------------------

/// Master gate for pushing `logging_session` entries onto the sync wire.
///
/// OFF until a `JournalOperation`-tolerant client (one that decodes an unknown
/// `"op"` tag to `JournalOperation::Unknown` instead of aborting the pull batch)
/// is the floor version across ALL of a user's devices — the identical
/// forward-compat constraint that gates [`CONFIG_SYNC_PUSH_ENABLED`]. A released
/// client without that tolerance would abort its *entire* pull (QSO ops included)
/// on meeting an `UpsertLoggingSession` op. Everything else stays wired up
/// (gather, inbound `apply_inbound` handling, merge, notify) so flipping this to
/// `true` once the floor is met is the only change needed to publish sessions
/// from iOS/Android. Inbound apply is NOT gated — applying a session op a peer
/// already put on the wire is always safe.
const SESSION_SYNC_PUSH_ENABLED: bool = false;

/// Drain the dirty `logging_session` backlog in bounded batches (each fetch is
/// capped at `MAX_FETCH_LIMIT`), pushing one blob per batch and clearing the
/// pushed ids between batches. No store lock is held across the network push.
/// Returns the number of sessions pushed. No-op while [`SESSION_SYNC_PUSH_ENABLED`]
/// is `false` (nothing gathered, nothing cleared, nothing on the wire).
fn push_logging_sessions(store: &FieldStore, transport: &mut HttpSyncTransport) -> Result<u32, CwError> {
    const MAX_BATCHES: usize = 1_000_000;
    let mut total_pushed: u32 = 0;
    for _ in 0..MAX_BATCHES {
        let gathered_at = Utc::now().timestamp();
        let (outbound, pushed_ids) = {
            let locked = store.inner.lock().expect("store mutex poisoned");
            gather_outbound_logging_session_payload(&locked)?
        };
        let Some(payload) = outbound else { break };
        transport.push(std::slice::from_ref(&payload))?;
        total_pushed += pushed_ids.len() as u32;
        let locked = store.inner.lock().expect("store mutex poisoned");
        locked.clear_dirty("loggingSession", &pushed_ids, Some(gathered_at))?;
    }
    Ok(total_pushed)
}

/// The single gate the session push loop consults: returns the payload that would
/// go on the wire, or `(None, _)` when [`SESSION_SYNC_PUSH_ENABLED`] is `false`.
fn gather_outbound_logging_session_payload(
    store: &Store,
) -> Result<(Option<JournalPayload>, Vec<String>), CwError> {
    if !SESSION_SYNC_PUSH_ENABLED {
        return Ok((None, Vec::new()));
    }
    gather_dirty_logging_session_payload(store)
}

/// Build a single outbound [`JournalPayload`] from the dirty `logging_session`
/// backlog (its OWN entity type — never mixed with QSO/config ops). Returns
/// `(payload, pushed_ids)` where `pushed_ids` are the session ids whose dirty flag
/// the caller clears after the push succeeds, or `(None, _)` when nothing is
/// dirty. The entry id is content-addressed (like the QSO gather) so an unchanged
/// batch dedups server-side instead of appending a duplicate. Kept fully
/// functional even while the push gate is off, so the local round-trip tests and
/// the future floor-version flip both work off the same code path.
fn gather_dirty_logging_session_payload(
    store: &Store,
) -> Result<(Option<JournalPayload>, Vec<String>), CwError> {
    let filter = LoggingSessionFilter { dirty_only: Some(true), ..Default::default() };
    let dirty = store.fetch_logging_sessions(&filter, MAX_FETCH_LIMIT, 0)?;
    if dirty.is_empty() {
        return Ok((None, Vec::new()));
    }

    let mut ops: Vec<JournalOperation> = Vec::with_capacity(dirty.len());
    let mut pushed_ids: Vec<String> = Vec::with_capacity(dirty.len());
    for session in &dirty {
        pushed_ids.push(session.id.clone());
        ops.push(JournalOperation::upsert_logging_session(session_to_wire(session)));
    }

    let entry_id = match serde_json::to_vec(&ops) {
        Ok(bytes) => uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, &bytes).to_string(),
        Err(_) => uuid::Uuid::new_v4().to_string(),
    };
    let payload = JournalPayload::new(
        entry_id,
        device_id(store)?,
        Utc::now().timestamp(),
        next_sequence(store)?,
        ops,
    );
    Ok((Some(payload), pushed_ids))
}

/// Apply every operation in an inbound payload to the store.
fn apply_inbound(
    store: &Store,
    payload: &JournalPayload,
    applied: &mut Vec<SyncAppliedKey>,
) -> Result<(), CwError> {
    for op in &payload.operations {
        match op {
            JournalOperation::UpsertQso(remote) => {
                apply_qso_upsert(store, remote, payload.timestamp)?;
                applied.push(SyncAppliedKey { table: FfiStoreTable::Qso, id: remote.id.clone(), deleted: false });
            }
            JournalOperation::UpsertSyncedConfig(remote) => {
                apply_synced_config_upsert(store, remote)?;
                applied.push(SyncAppliedKey {
                    table: FfiStoreTable::SyncedConfig,
                    id: remote.config_type.clone(),
                    deleted: false,
                });
            }
            JournalOperation::UpsertLoggingSession(remote) => {
                apply_logging_session_upsert(store, remote, payload.timestamp)?;
                applied.push(SyncAppliedKey {
                    table: FfiStoreTable::LoggingSession,
                    id: remote.id.clone(),
                    deleted: false,
                });
            }
            JournalOperation::Delete { entity_type, id } => match entity_type {
                // Soft delete: the row stays (is_hidden = true), so report an upsert.
                JournalEntityType::Qso => {
                    soft_delete_qso(store, id)?;
                    applied.push(SyncAppliedKey { table: FfiStoreTable::Qso, id: id.clone(), deleted: false });
                }
                // Sessions hard-delete (they carry no `is_hidden`), mirroring the
                // Swift inbound `modelContext.delete(session)`. Idempotent.
                JournalEntityType::LoggingSession => {
                    store.delete_logging_session(id)?;
                    applied.push(SyncAppliedKey {
                        table: FfiStoreTable::LoggingSession,
                        id: id.clone(),
                        deleted: true,
                    });
                }
                // Other entity deletes are outside the modeled subset (Phase 7).
                _ => {}
            },
            JournalOperation::Unknown => {
                // Forward-compat: an `"op"` tag a newer client minted that this
                // build doesn't model. Skip it — no error, no state change — so a
                // single unknown op never aborts a whole pull batch (the known
                // ops in the same payload still apply above).
            }
        }
    }
    Ok(())
}

/// Inbound synced-config upsert: last-writer-wins on `modified_at`. When the
/// incoming row is not strictly newer than the local one, keep the local value
/// (a tie leaves local in place, so a device never clobbers its own concurrent
/// edit with an equal-timestamp remote). The applied row lands clean
/// (`mark_dirty = false`) so it doesn't re-push and cause a sync ping-pong.
fn apply_synced_config_upsert(
    store: &Store,
    remote: &cw_sync::SyncedConfigPayload,
) -> Result<(), CwError> {
    if let Some(existing) = store.fetch_synced_config_row(&remote.config_type)? {
        // LWW: only overwrite when the remote edit is strictly newer. A `None`
        // local modified_at is treated as oldest.
        let local_mod = existing.modified_at.unwrap_or(i64::MIN);
        let remote_mod = remote.modified_at.unwrap_or(i64::MIN);
        if remote_mod <= local_mod {
            return Ok(());
        }
    }
    store.upsert_synced_config(&remote.config_type, &remote.data, remote.modified_at, false)?;
    Ok(())
}

/// Inbound QSO upsert: merge against the local row if it exists (preserving the
/// non-subset `FfiQso` columns + the existing dirty flag), else insert a fresh
/// clean row. Mirrors `QSOJournalStore.applyInbound`.
fn apply_qso_upsert(store: &Store, remote: &SyncQso, remote_mod: i64) -> Result<(), CwError> {
    if let Some(existing) = store.fetch_qso(&remote.id)? {
        let local = qso_to_sync(&existing);
        let local_mod = existing.modified_at.unwrap_or(existing.imported_at);
        let merged = merge_qso(&local, remote, local_mod, remote_mod);
        let updated = apply_sync_onto(existing, &merged);
        store.upsert_qso(&updated)?;
    } else {
        store.upsert_qso(&sync_to_new_qso(remote))?;
    }
    Ok(())
}

/// Soft-delete a QSO (set `is_hidden`, never a hard delete). Missing id is a
/// no-op. Mirrors `QSOJournalStore.softDelete`.
fn soft_delete_qso(store: &Store, id: &str) -> Result<(), CwError> {
    if let Some(mut existing) = store.fetch_qso(id)? {
        existing.is_hidden = true;
        store.upsert_qso(&existing)?;
    }
    Ok(())
}

/// Inbound session upsert: merge against the local row if it exists (preserving
/// the non-wire columns + its dirty flag), else insert a fresh clean row. The LWW
/// key is the session's own `ended_at ?? started_at` (sessions carry no
/// `modified_at`); the payload timestamp seeds the completed-status fallback.
/// Mirrors the Swift `applyLoggingSessionUpsert` seam.
fn apply_logging_session_upsert(
    store: &Store,
    remote: &LoggingSessionPayload,
    remote_mod: i64,
) -> Result<(), CwError> {
    if let Some(existing) = store.fetch_logging_session(&remote.id)? {
        let local = session_to_wire(&existing);
        let local_mod = existing.ended_at.unwrap_or(existing.started_at);
        let merged = merge_logging_session(&local, remote, local_mod, remote_mod, remote_mod);
        let updated = apply_session_onto(existing, &merged);
        store.upsert_logging_session(&updated)?;
    } else {
        store.upsert_logging_session(&wire_to_new_session(remote))?;
    }
    Ok(())
}

/// Stable per-install device id, minted (and persisted) on first use.
fn device_id(store: &Store) -> Result<String, CwError> {
    if let Some(existing) = store.kv_get(SYNC_DEVICE_ID_KEY)? {
        return Ok(existing);
    }
    let id = uuid::Uuid::new_v4().to_string();
    store.kv_set(SYNC_DEVICE_ID_KEY, &id)?;
    Ok(id)
}

/// Next monotonic outbound journal sequence number for this device.
fn next_sequence(store: &Store) -> Result<i64, CwError> {
    let current =
        store.kv_get(SYNC_SEQUENCE_KEY)?.and_then(|raw| raw.parse::<i64>().ok()).unwrap_or(0);
    let next = current + 1;
    store.kv_set(SYNC_SEQUENCE_KEY, &next.to_string())?;
    Ok(next)
}

// ---------------------------------------------------------------------------
// QSO <-> SyncQso (the modeled-subset mapping; see the module note)
// ---------------------------------------------------------------------------

/// Project a stored `Qso` onto the full journal wire QSO. Frequency is kHz in
/// the store and MHz on the wire; `park_reference`/`their_park_reference` mirror
/// Swift `parkReference`/`theirParkReference`. Every `QSOFields` wire field is
/// carried — non-wire columns (`contest_*`, `aoa_code`, `callsign_change_note`,
/// `original_callsign`, `dirty`) have no wire slot and stay on the row.
fn qso_to_sync(qso: &Qso) -> SyncQso {
    SyncQso {
        id: qso.id.clone(),
        callsign: qso.callsign.clone(),
        band: qso.band.clone().unwrap_or_default(),
        mode: qso.mode.clone().unwrap_or_default(),
        frequency: qso.freq_khz.map(|khz| khz / 1_000.0),
        timestamp: qso.qso_date,
        rst_sent: qso.rst_sent.clone(),
        rst_received: qso.rst_rcvd.clone(),
        my_callsign: qso.my_callsign.clone().unwrap_or_default(),
        my_grid: qso.my_grid.clone(),
        their_grid: qso.their_grid.clone(),
        park_reference: qso.park.clone(),
        their_park_reference: qso.their_park.clone(),
        notes: qso.notes.clone(),
        import_source: qso.import_source_raw_value.clone(),
        imported_at: Some(qso.imported_at),
        modified_at: qso.modified_at,
        raw_adif: qso.raw_adif.clone(),
        name: qso.name.clone(),
        qth: qso.qth.clone(),
        state: qso.state.clone(),
        country: qso.country.clone(),
        power: qso.power,
        my_rig: qso.my_rig.clone(),
        station_profile_name: qso.station_profile_name.clone(),
        sota_ref: qso.sota_ref.clone(),
        wwff_ref: qso.wwff_ref.clone(),
        qrz_log_id: qso.qrz_log_id.clone(),
        qrz_confirmed: qso.qrz_confirmed,
        lotw_confirmed_date: qso.lotw_confirmed_date,
        lotw_confirmed: qso.lotw_confirmed,
        dxcc: qso.dxcc,
        their_license_class: qso.their_license_class.clone(),
        is_hidden: qso.is_hidden,
        is_activity_log_qso: qso.is_activity_log_qso,
        logging_session_id: qso.logging_session_id.clone(),
        station_callsign: qso.station_callsign.clone(),
        spot_comments_data: qso.spot_comments_data.clone(),
        notes_user_authored: qso.notes_user_authored,
        sat_name: qso.sat_name.clone(),
        prop_mode: qso.prop_mode.clone(),
    }
}

/// Overwrite only the wire fields on an existing row, preserving every non-wire
/// column (`contest_*`, `aoa_code`, `callsign_change_note`, `original_callsign`)
/// and the row's dirty flag. Empty band/mode/myCallsign (the wire format's
/// `None` sentinel for the store's optional columns) leave the existing value
/// untouched.
fn apply_sync_onto(mut qso: Qso, merged: &SyncQso) -> Qso {
    qso.callsign = merged.callsign.clone();
    if !merged.band.is_empty() {
        qso.band = Some(merged.band.clone());
    }
    if !merged.mode.is_empty() {
        qso.mode = Some(merged.mode.clone());
    }
    qso.freq_khz = merged.frequency.map(|mhz| mhz * 1_000.0);
    qso.qso_date = merged.timestamp;
    qso.rst_sent = merged.rst_sent.clone();
    qso.rst_rcvd = merged.rst_received.clone();
    if !merged.my_callsign.is_empty() {
        qso.my_callsign = Some(merged.my_callsign.clone());
    }
    qso.my_grid = merged.my_grid.clone();
    qso.their_grid = merged.their_grid.clone();
    qso.park = merged.park_reference.clone();
    qso.their_park = merged.their_park_reference.clone();
    qso.notes = merged.notes.clone();
    if !merged.import_source.is_empty() {
        qso.import_source_raw_value = merged.import_source.clone();
    }
    if let Some(imported_at) = merged.imported_at {
        qso.imported_at = imported_at;
    }
    qso.modified_at = merged.modified_at;
    qso.raw_adif = merged.raw_adif.clone();
    qso.name = merged.name.clone();
    qso.qth = merged.qth.clone();
    qso.state = merged.state.clone();
    qso.country = merged.country.clone();
    qso.power = merged.power;
    qso.my_rig = merged.my_rig.clone();
    qso.station_profile_name = merged.station_profile_name.clone();
    qso.sota_ref = merged.sota_ref.clone();
    qso.wwff_ref = merged.wwff_ref.clone();
    qso.qrz_log_id = merged.qrz_log_id.clone();
    qso.qrz_confirmed = merged.qrz_confirmed;
    qso.lotw_confirmed_date = merged.lotw_confirmed_date;
    qso.lotw_confirmed = merged.lotw_confirmed;
    qso.dxcc = merged.dxcc;
    qso.their_license_class = merged.their_license_class.clone();
    qso.is_hidden = merged.is_hidden;
    qso.is_activity_log_qso = merged.is_activity_log_qso;
    qso.logging_session_id = merged.logging_session_id.clone();
    qso.station_callsign = merged.station_callsign.clone();
    qso.spot_comments_data = merged.spot_comments_data.clone();
    qso.notes_user_authored = merged.notes_user_authored;
    qso.sat_name = merged.sat_name.clone();
    qso.prop_mode = merged.prop_mode.clone();
    qso
}

/// Project an inbound wire QSO onto an `FfiQso`, carrying every wire field.
/// Non-wire columns take `FfiQso` defaults; an empty `import_source` falls back
/// to the sync origin (`icloud`).
fn sync_to_ffi(remote: &SyncQso) -> FfiQso {
    FfiQso {
        id: remote.id.clone(),
        callsign: remote.callsign.clone(),
        band: (!remote.band.is_empty()).then(|| remote.band.clone()),
        mode: (!remote.mode.is_empty()).then(|| remote.mode.clone()),
        freq_khz: remote.frequency.map(|mhz| mhz * 1_000.0),
        qso_date: remote.timestamp,
        my_grid: remote.my_grid.clone(),
        their_grid: remote.their_grid.clone(),
        rst_sent: remote.rst_sent.clone(),
        rst_rcvd: remote.rst_received.clone(),
        my_callsign: (!remote.my_callsign.is_empty()).then(|| remote.my_callsign.clone()),
        park: remote.park_reference.clone(),
        their_park: remote.their_park_reference.clone(),
        notes: remote.notes.clone(),
        notes_user_authored: remote.notes_user_authored,
        spot_comments_data: remote.spot_comments_data.clone(),
        import_source_raw_value: if remote.import_source.is_empty() {
            "icloud".to_string()
        } else {
            remote.import_source.clone()
        },
        imported_at: remote.imported_at.unwrap_or(remote.timestamp),
        modified_at: remote.modified_at,
        raw_adif: remote.raw_adif.clone(),
        name: remote.name.clone(),
        qth: remote.qth.clone(),
        state: remote.state.clone(),
        country: remote.country.clone(),
        power: remote.power,
        my_rig: remote.my_rig.clone(),
        station_profile_name: remote.station_profile_name.clone(),
        sota_ref: remote.sota_ref.clone(),
        wwff_ref: remote.wwff_ref.clone(),
        qrz_log_id: remote.qrz_log_id.clone(),
        qrz_confirmed: remote.qrz_confirmed,
        lotw_confirmed_date: remote.lotw_confirmed_date,
        lotw_confirmed: remote.lotw_confirmed,
        dxcc: remote.dxcc,
        their_license_class: remote.their_license_class.clone(),
        is_hidden: remote.is_hidden,
        is_activity_log_qso: remote.is_activity_log_qso,
        station_callsign: remote.station_callsign.clone(),
        logging_session_id: remote.logging_session_id.clone(),
        sat_name: remote.sat_name.clone(),
        prop_mode: remote.prop_mode.clone(),
        ..Default::default()
    }
}

/// Build a fresh, clean store row from an inbound wire QSO. Non-wire columns
/// take `FfiQso` defaults; the import source is the sync origin.
fn sync_to_new_qso(remote: &SyncQso) -> Qso {
    sync_to_ffi(remote).into()
}

// ---------------------------------------------------------------------------
// LoggingSession <-> LoggingSessionPayload (the modeled-subset mapping)
// ---------------------------------------------------------------------------

/// Parse the store's JSON-encoded `photo_filenames` string into the wire's
/// `[String]`. A malformed/empty value yields an empty list rather than failing
/// the whole sync.
fn parse_photo_filenames(json: &str) -> Vec<String> {
    serde_json::from_str(json).unwrap_or_default()
}

/// Encode the wire's `[String]` photo filenames back to the store's JSON string.
fn encode_photo_filenames(names: &[String]) -> String {
    serde_json::to_string(names).unwrap_or_else(|_| "[]".to_string())
}

/// Default `programs_raw_value` for a session that arrives with no `programs` on
/// the wire (the wire omits it). Mirrors Swift `LoggingSession.init`, which seeds
/// `programs = [activationType.rawValue]` when none are supplied.
fn default_programs(activation_type_raw_value: &str) -> String {
    encode_photo_filenames(&[activation_type_raw_value.to_string()])
}

/// Project a stored `LoggingSession` onto the wire subset. Only the ~45 modeled
/// `LoggingSessionFields` columns are carried; every non-wire column stays on the
/// row (see [`apply_session_onto`]).
fn session_to_wire(session: &LoggingSession) -> LoggingSessionPayload {
    LoggingSessionPayload {
        id: session.id.clone(),
        my_callsign: session.my_callsign.clone(),
        started_at: session.started_at,
        ended_at: session.ended_at,
        frequency: session.frequency,
        mode: session.mode.clone(),
        activation_type_raw_value: session.activation_type_raw_value.clone(),
        status_raw_value: session.status_raw_value.clone(),
        park_reference: session.park_reference.clone(),
        sota_reference: session.sota_reference.clone(),
        wwff_reference: session.wwff_reference.clone(),
        my_grid: session.my_grid.clone(),
        power: session.power,
        my_rig: session.my_rig.clone(),
        notes: session.notes.clone(),
        qso_comment: session.qso_comment.clone(),
        custom_title: session.custom_title.clone(),
        qso_count: session.qso_count,
        is_rove: session.is_rove,
        my_antenna: session.my_antenna.clone(),
        my_key: session.my_key.clone(),
        my_mic: session.my_mic.clone(),
        extra_equipment: session.extra_equipment.clone(),
        attendees: session.attendees.clone(),
        photo_filenames: parse_photo_filenames(&session.photo_filenames),
        spot_comments_data: session.spot_comments_data.clone(),
        rove_stops_data: session.rove_stops_data.clone(),
        solar_k_index: session.solar_k_index,
        solar_flux: session.solar_flux,
        solar_sunspots: session.solar_sunspots,
        solar_propagation_rating: session.solar_propagation_rating.clone(),
        solar_a_index: session.solar_a_index,
        solar_band_conditions: session.solar_band_conditions.clone(),
        solar_timestamp: session.solar_timestamp,
        solar_conditions: session.solar_conditions.clone(),
        weather_temperature_f: session.weather_temperature_f,
        weather_temperature_c: session.weather_temperature_c,
        weather_humidity: session.weather_humidity,
        weather_wind_speed: session.weather_wind_speed,
        weather_wind_direction: session.weather_wind_direction.clone(),
        weather_description: session.weather_description.clone(),
        weather_timestamp: session.weather_timestamp,
        weather: session.weather.clone(),
        station_callsign: session.station_callsign.clone(),
        operator_callsigns_raw_value: session.operator_callsigns_raw_value.clone(),
    }
}

/// Overwrite only the wire columns on an existing session row, preserving every
/// non-wire column (`programs_raw_value`, `mission_reference`, `radio_item_id`,
/// `cloud_dirty_flag`, all `contest_*`, all TOTA / activation-geometry / track /
/// tile fields). Mirrors the Swift `applySessionFields` seam.
fn apply_session_onto(mut session: LoggingSession, merged: &LoggingSessionPayload) -> LoggingSession {
    session.my_callsign = merged.my_callsign.clone();
    session.started_at = merged.started_at;
    session.ended_at = merged.ended_at;
    session.frequency = merged.frequency;
    session.mode = merged.mode.clone();
    session.activation_type_raw_value = merged.activation_type_raw_value.clone();
    session.status_raw_value = merged.status_raw_value.clone();
    session.park_reference = merged.park_reference.clone();
    session.sota_reference = merged.sota_reference.clone();
    session.wwff_reference = merged.wwff_reference.clone();
    session.my_grid = merged.my_grid.clone();
    session.power = merged.power;
    session.my_rig = merged.my_rig.clone();
    session.notes = merged.notes.clone();
    session.qso_comment = merged.qso_comment.clone();
    session.custom_title = merged.custom_title.clone();
    session.qso_count = merged.qso_count;
    session.is_rove = merged.is_rove;
    session.my_antenna = merged.my_antenna.clone();
    session.my_key = merged.my_key.clone();
    session.my_mic = merged.my_mic.clone();
    session.extra_equipment = merged.extra_equipment.clone();
    session.attendees = merged.attendees.clone();
    session.photo_filenames = encode_photo_filenames(&merged.photo_filenames);
    session.spot_comments_data = merged.spot_comments_data.clone();
    session.rove_stops_data = merged.rove_stops_data.clone();
    session.solar_k_index = merged.solar_k_index;
    session.solar_flux = merged.solar_flux;
    session.solar_sunspots = merged.solar_sunspots;
    session.solar_propagation_rating = merged.solar_propagation_rating.clone();
    session.solar_a_index = merged.solar_a_index;
    session.solar_band_conditions = merged.solar_band_conditions.clone();
    session.solar_timestamp = merged.solar_timestamp;
    session.solar_conditions = merged.solar_conditions.clone();
    session.weather_temperature_f = merged.weather_temperature_f;
    session.weather_temperature_c = merged.weather_temperature_c;
    session.weather_humidity = merged.weather_humidity;
    session.weather_wind_speed = merged.weather_wind_speed;
    session.weather_wind_direction = merged.weather_wind_direction.clone();
    session.weather_description = merged.weather_description.clone();
    session.weather_timestamp = merged.weather_timestamp;
    session.weather = merged.weather.clone();
    session.station_callsign = merged.station_callsign.clone();
    session.operator_callsigns_raw_value = merged.operator_callsigns_raw_value.clone();
    session
}

/// Build a fresh, clean store row from an inbound wire session. The non-wire
/// columns take neutral defaults; `programs_raw_value` is seeded from the
/// activation type (Swift `fromFields` parity); the row lands clean
/// (`cloud_dirty_flag = false`) so it doesn't re-push and cause a sync ping-pong.
fn wire_to_new_session(remote: &LoggingSessionPayload) -> LoggingSession {
    LoggingSession {
        id: remote.id.clone(),
        my_callsign: remote.my_callsign.clone(),
        started_at: remote.started_at,
        ended_at: remote.ended_at,
        frequency: remote.frequency,
        mode: remote.mode.clone(),
        activation_type_raw_value: remote.activation_type_raw_value.clone(),
        programs_raw_value: default_programs(&remote.activation_type_raw_value),
        status_raw_value: remote.status_raw_value.clone(),
        park_reference: remote.park_reference.clone(),
        sota_reference: remote.sota_reference.clone(),
        mission_reference: None,
        wwff_reference: remote.wwff_reference.clone(),
        my_grid: remote.my_grid.clone(),
        power: remote.power,
        my_rig: remote.my_rig.clone(),
        notes: remote.notes.clone(),
        qso_comment: remote.qso_comment.clone(),
        custom_title: remote.custom_title.clone(),
        qso_count: remote.qso_count,
        spot_comments_data: remote.spot_comments_data.clone(),
        is_rove: remote.is_rove,
        rove_stops_data: remote.rove_stops_data.clone(),
        my_antenna: remote.my_antenna.clone(),
        my_key: remote.my_key.clone(),
        my_mic: remote.my_mic.clone(),
        extra_equipment: remote.extra_equipment.clone(),
        attendees: remote.attendees.clone(),
        photo_filenames: encode_photo_filenames(&remote.photo_filenames),
        radio_item_id: None,
        station_callsign: remote.station_callsign.clone(),
        operator_callsigns_raw_value: remote.operator_callsigns_raw_value.clone(),
        solar_k_index: remote.solar_k_index,
        solar_flux: remote.solar_flux,
        solar_sunspots: remote.solar_sunspots,
        solar_propagation_rating: remote.solar_propagation_rating.clone(),
        solar_a_index: remote.solar_a_index,
        solar_band_conditions: remote.solar_band_conditions.clone(),
        solar_timestamp: remote.solar_timestamp,
        solar_conditions: remote.solar_conditions.clone(),
        weather_temperature_f: remote.weather_temperature_f,
        weather_temperature_c: remote.weather_temperature_c,
        weather_humidity: remote.weather_humidity,
        weather_wind_speed: remote.weather_wind_speed,
        weather_wind_direction: remote.weather_wind_direction.clone(),
        weather_description: remote.weather_description.clone(),
        weather_timestamp: remote.weather_timestamp,
        weather: remote.weather.clone(),
        cloud_dirty_flag: false,
        contest_id: None,
        contest_category: None,
        contest_overlay_category: None,
        contest_power: None,
        contest_bands: None,
        contest_operator: None,
        activation_latitude: None,
        activation_longitude: None,
        activation_distance_miles: None,
        activation_elevation_gain_feet: None,
        ruck_weight_pounds: None,
        qrp_activation: false,
        with_pets: false,
        with_kids: false,
        winlink_sent: false,
        aprs_sent: false,
        varac_sent: false,
        adaptive_sport: false,
        track_points_data: None,
        tota_category_raw_value: None,
        personal_effort_factor: None,
        first_activation_of_tile_ever: false,
        winter_activation_override: None,
        tiles_activated_data: None,
        tota_t3_candidates_data: None,
        tota_t3_snapshot_at: None,
        tota_official_points: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- Escrow (the MUST-pass round trip) ----

    #[test]
    fn escrow_create_then_open_recovers_same_key() {
        let created = create_sync_escrow("correct horse".into()).unwrap();
        assert_eq!(created.data_key.len(), 32);
        let recovered = open_sync_escrow(
            "correct horse".into(),
            created.wrapped_key_b64.clone(),
            created.kdf_params_json.clone(),
        )
        .unwrap();
        assert_eq!(recovered, created.data_key);
    }

    #[test]
    fn escrow_wrong_passphrase_errors() {
        let created = create_sync_escrow("correct horse".into()).unwrap();
        let err = open_sync_escrow(
            "battery staple".into(),
            created.wrapped_key_b64,
            created.kdf_params_json,
        );
        assert!(matches!(err, Err(CwError::Crypto { .. })));
    }

    // ---- Offline local-decrypt proof --------------------------------------
    // The whole point of `create_key_escrow` + `open_sync_escrow`: the passphrase
    // + a LOCAL envelope must recover the exact at-rest key that DECRYPTS the
    // on-disk SQLCipher store — with no server. This walks the full production
    // chain that Swift's CwStoreKeyRecovery drives (wrap the existing key →
    // cache → unwrap offline → base64 → reopen the same file). Shared core, so
    // it proves the mechanism for both iOS and Android.

    #[test]
    fn offline_passphrase_recovers_key_that_decrypts_the_store() {
        use base64::Engine;

        let b64 = base64::engine::general_purpose::STANDARD;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cw-store.db").to_string_lossy().into_owned();

        // A random 32-byte at-rest key, held as a base64 string exactly like
        // CwStoreProvider.localEncryptionKey.
        let key_bytes: [u8; 32] =
            core::array::from_fn(|i| (i as u8).wrapping_mul(37).wrapping_add(11));
        let key_str = b64.encode(key_bytes);

        // Provision the encrypted store with that key and write a row.
        {
            let store = crate::FieldStore::open(path.clone(), key_str.clone()).unwrap();
            store
                .upsert_qso(FfiQso {
                    id: "q1".into(),
                    callsign: "W1AW".into(),
                    qso_date: 1000,
                    ..Default::default()
                })
                .unwrap();
            assert_eq!(store.qso_count().unwrap(), 1);
        } // dropped → file closed, key gone from memory

        // Wrap the key under a passphrase (this is the local recovery envelope).
        let passphrase = "correct horse battery staple";
        let envelope =
            create_key_escrow(passphrase.into(), key_bytes.to_vec()).expect("wrap the at-rest key");

        // OFFLINE recovery: only the passphrase + the local envelope. No server.
        let recovered_bytes = open_sync_escrow(
            passphrase.into(),
            envelope.wrapped_key_b64.clone(),
            envelope.kdf_params_json.clone(),
        )
        .expect("unwrap offline");
        let recovered_key = b64.encode(&recovered_bytes);
        assert_eq!(recovered_key, key_str, "recovered key string must match the original");

        // The recovered key must actually DECRYPT the on-disk store — a wrong
        // key makes FieldStore::open fail NOTADB on its forced keyed read — and
        // the data must be intact (proving it reopened the same file, not a new
        // empty one).
        let reopened = crate::FieldStore::open(path.clone(), recovered_key)
            .expect("recovered key decrypts the store");
        assert_eq!(reopened.qso_count().unwrap(), 1, "data intact after offline recovery");

        // Negative: a wrong passphrase cannot unwrap the key at all.
        assert!(
            open_sync_escrow("wrong".into(), envelope.wrapped_key_b64, envelope.kdf_params_json)
                .is_err(),
            "wrong passphrase must fail to recover the key"
        );
    }

    // ---- Driver internals (no network) ----

    fn store() -> Store {
        Store::open_in_memory("k").unwrap()
    }

    fn qso(id: &str, callsign: &str) -> Qso {
        FfiQso {
            id: id.into(),
            callsign: callsign.into(),
            band: Some("20m".into()),
            mode: Some("CW".into()),
            freq_khz: Some(14_050.0),
            qso_date: 1_000,
            imported_at: 1_000,
            modified_at: Some(1_000),
            ..Default::default()
        }
        .into()
    }

    fn remote_sync(id: &str, callsign: &str) -> SyncQso {
        qso_to_sync(&qso(id, callsign))
    }

    #[test]
    fn inbound_inserts_new_clean_row() {
        let store = store();
        let payload = JournalPayload::new(
            uuid::Uuid::new_v4().to_string(),
            "device-remote",
            2_000,
            1,
            vec![JournalOperation::upsert_qso(remote_sync("q1", "W1AW"))],
        );
        apply_inbound(&store, &payload, &mut Vec::new()).unwrap();

        let row = store.fetch_qso("q1").unwrap().expect("inserted");
        assert_eq!(row.callsign, "W1AW");
        assert!(!row.dirty, "inbound rows land clean (no sync ping-pong)");
        // kHz/MHz scale survived the round trip.
        assert_eq!(row.freq_khz, Some(14_050.0));
    }

    #[test]
    fn inbound_merge_prefers_newer_remote_and_preserves_dirty() {
        let store = store();
        // Local row carries a genuinely non-wire column (`contest_name`, absent
        // from the Swift `QSOFields` wire struct) + dirty flag we must keep.
        let mut local: Qso = qso("q1", "W1AW");
        local.contest_name = Some("CQ WW".into()); // non-wire column
        local.dirty = true;
        local.modified_at = Some(1_000);
        store.upsert_qso(&local).unwrap();

        // Newer remote changes the band.
        let mut remote = remote_sync("q1", "W1AW");
        remote.band = "40m".into();
        let payload = JournalPayload::new(
            uuid::Uuid::new_v4().to_string(),
            "device-remote",
            5_000, // remote_mod > local_mod (1000) → prefer remote
            1,
            vec![JournalOperation::upsert_qso(remote)],
        );
        apply_inbound(&store, &payload, &mut Vec::new()).unwrap();

        let row = store.fetch_qso("q1").unwrap().unwrap();
        assert_eq!(row.band.as_deref(), Some("40m"), "newer remote band won");
        assert_eq!(row.contest_name.as_deref(), Some("CQ WW"), "non-wire column preserved");
        assert!(row.dirty, "existing dirty flag preserved across inbound merge");
    }

    #[test]
    fn ffi_qso_round_trips_through_sync_qso_preserving_all_wire_fields() {
        // A fully-populated FfiQso, including non-wire columns. The wire fields
        // must survive FfiQso -> Qso -> SyncQso -> FfiQso with no silent drops.
        // Non-wire columns (contest_*, aoa_code, callsign_change_note,
        // original_callsign, dirty, presence) have no journal wire slot.
        // FfiQso is not Clone (uniffi::Record), so build it from a closure we
        // can call twice: once for the store row, once as the comparison baseline.
        let make = || FfiQso {
            id: "q-rt".into(),
            callsign: "W1AW".into(),
            band: Some("20m".into()),
            mode: Some("FT8".into()),
            freq_khz: Some(14_074.0),
            qso_date: 1_700_000_000,
            my_grid: Some("CM87".into()),
            their_grid: Some("FN31".into()),
            rst_sent: Some("599".into()),
            rst_rcvd: Some("579".into()),
            my_callsign: Some("W6JY".into()),
            park: Some("K-1234".into()),
            their_park: Some("K-5678".into()),
            notes: Some("great contact".into()),
            notes_user_authored: true,
            spot_comments_data: Some(vec![1, 2, 3, 4]),
            import_source_raw_value: "qrz".into(),
            imported_at: 1_699_999_000,
            modified_at: Some(1_700_000_500),
            raw_adif: Some("<call:4>W1AW<eor>".into()),
            name: Some("Hiram".into()),
            qth: Some("Newington".into()),
            state: Some("CT".into()),
            country: Some("United States".into()),
            power: Some(100),
            my_rig: Some("KX2".into()),
            station_profile_name: Some("Home".into()),
            sota_ref: Some("W1/HA-001".into()),
            wwff_ref: Some("KFF-0001".into()),
            qrz_log_id: Some("abc123".into()),
            qrz_confirmed: true,
            lotw_confirmed_date: Some(1_700_001_000),
            lotw_confirmed: true,
            dxcc: Some(291),
            their_license_class: Some("Extra".into()),
            is_hidden: false,
            is_activity_log_qso: false,
            station_callsign: Some("W6JY".into()),
            logging_session_id: Some("sess-1".into()),
            sat_name: Some("AO-91".into()),
            prop_mode: Some("SAT".into()),
            // Non-wire columns (intentionally dropped on the journal wire):
            callsign_change_note: Some("was N0CALL".into()),
            original_callsign: Some("N0CALL".into()),
            aoa_code: Some("AOA-1".into()),
            contest_name: Some("CQ WW".into()),
            contest_serial_sent: Some(1),
            contest_serial_received: Some(2),
            contest_exchange_sent: Some("ex-s".into()),
            contest_exchange_received: Some("ex-r".into()),
            ..Default::default()
        };
        let original = make();

        let store_row: Qso = make().into();
        let wire = qso_to_sync(&store_row);
        let back = sync_to_ffi(&wire);

        // Every wire field round-trips intact.
        assert_eq!(back.id, original.id);
        assert_eq!(back.callsign, original.callsign);
        assert_eq!(back.band, original.band);
        assert_eq!(back.mode, original.mode);
        assert_eq!(back.freq_khz, original.freq_khz);
        assert_eq!(back.qso_date, original.qso_date);
        assert_eq!(back.rst_sent, original.rst_sent);
        assert_eq!(back.rst_rcvd, original.rst_rcvd);
        assert_eq!(back.my_callsign, original.my_callsign);
        assert_eq!(back.my_grid, original.my_grid);
        assert_eq!(back.their_grid, original.their_grid);
        assert_eq!(back.park, original.park);
        assert_eq!(back.their_park, original.their_park);
        assert_eq!(back.notes, original.notes);
        assert_eq!(back.notes_user_authored, original.notes_user_authored);
        assert_eq!(back.spot_comments_data, original.spot_comments_data);
        assert_eq!(back.import_source_raw_value, original.import_source_raw_value);
        assert_eq!(back.imported_at, original.imported_at);
        assert_eq!(back.modified_at, original.modified_at);
        assert_eq!(back.raw_adif, original.raw_adif);
        assert_eq!(back.name, original.name);
        assert_eq!(back.qth, original.qth);
        assert_eq!(back.state, original.state);
        assert_eq!(back.country, original.country);
        assert_eq!(back.power, original.power);
        assert_eq!(back.my_rig, original.my_rig);
        assert_eq!(back.station_profile_name, original.station_profile_name);
        assert_eq!(back.sota_ref, original.sota_ref);
        assert_eq!(back.wwff_ref, original.wwff_ref);
        assert_eq!(back.qrz_log_id, original.qrz_log_id);
        assert_eq!(back.qrz_confirmed, original.qrz_confirmed);
        assert_eq!(back.lotw_confirmed_date, original.lotw_confirmed_date);
        assert_eq!(back.lotw_confirmed, original.lotw_confirmed);
        assert_eq!(back.dxcc, original.dxcc);
        assert_eq!(back.their_license_class, original.their_license_class);
        assert_eq!(back.is_hidden, original.is_hidden);
        assert_eq!(back.is_activity_log_qso, original.is_activity_log_qso);
        assert_eq!(back.station_callsign, original.station_callsign);
        assert_eq!(back.logging_session_id, original.logging_session_id);
        assert_eq!(back.sat_name, original.sat_name);
        assert_eq!(back.prop_mode, original.prop_mode);
    }

    #[test]
    fn inbound_delete_soft_hides_row() {
        let store = store();
        store.upsert_qso(&qso("q1", "W1AW")).unwrap();
        let payload = JournalPayload::new(
            uuid::Uuid::new_v4().to_string(),
            "device-remote",
            2_000,
            1,
            vec![JournalOperation::Delete {
                entity_type: JournalEntityType::Qso,
                id: "q1".into(),
            }],
        );
        apply_inbound(&store, &payload, &mut Vec::new()).unwrap();

        let row = store.fetch_qso("q1").unwrap().expect("still present (soft delete)");
        assert!(row.is_hidden, "delete soft-hides rather than hard-deletes");
    }

    #[test]
    fn gather_emits_dirty_and_skips_metadata_modes() {
        let store = store();
        // Two real dirty QSOs + one metadata-mode dirty row.
        let mut real1 = qso("q1", "W1AW");
        real1.dirty = true;
        let mut real2 = qso("q2", "K2ABC");
        real2.dirty = true;
        let mut weather = qso("q3", "N0CALL");
        weather.mode = Some("WEATHER".into());
        weather.dirty = true;
        store.upsert_qso(&real1).unwrap();
        store.upsert_qso(&real2).unwrap();
        store.upsert_qso(&weather).unwrap();

        let (payload, pushed_ids, _) = gather_dirty_payload(&store).unwrap();
        let payload = payload.expect("real dirty rows produce a payload");
        assert_eq!(payload.operations.len(), 2, "only the two real QSOs emit ops");
        assert_eq!(pushed_ids.len(), 2);
        assert!(!pushed_ids.contains(&"q3".to_string()), "metadata row excluded");
        // Metadata row was cleared in-place; the reals stay dirty until push confirms.
        let weather_row = store.fetch_qso("q3").unwrap().unwrap();
        assert!(!weather_row.dirty, "metadata-mode row cleared immediately");
        assert!(store.fetch_qso("q1").unwrap().unwrap().dirty, "real row still dirty pre-push");
    }

    #[test]
    fn gather_assigns_monotonic_sequences_and_stable_device() {
        let store = store();
        let mut row = qso("q1", "W1AW");
        row.dirty = true;
        store.upsert_qso(&row).unwrap();
        let (first, _, _) = gather_dirty_payload(&store).unwrap();
        // Re-dirty and gather again — sequence advances, device id is stable.
        let mut row2 = qso("q1", "W1AW");
        row2.dirty = true;
        store.upsert_qso(&row2).unwrap();
        let (second, _, _) = gather_dirty_payload(&store).unwrap();
        let first = first.unwrap();
        let second = second.unwrap();
        assert_eq!(first.sequence_number, 1);
        assert_eq!(second.sequence_number, 2);
        assert_eq!(first.device_id, second.device_id);
    }

    #[test]
    fn data_key_array_rejects_wrong_length() {
        assert!(data_key_array(&[0u8; 16]).is_err());
        assert!(data_key_array(&[0u8; 32]).is_ok());
    }

    // ---- synced_config gather / apply (brag config E2E sync) ----

    #[test]
    fn gather_synced_config_emits_its_own_payload_entity_type() {
        let store = store();
        store.upsert_synced_config("bragSheet", "{\"a\":1}", Some(100), true).unwrap();

        let (payload, pushed_ids) = gather_dirty_synced_config_payload(&store).unwrap();
        let payload = payload.expect("dirty config produces a payload");
        assert_eq!(payload.operations.len(), 1);
        // The payload is exclusively a syncedConfig entity — never mixed w/ QSO.
        assert_eq!(payload.operations[0].entity_type(), Some(JournalEntityType::SyncedConfig));
        assert_eq!(pushed_ids, vec![cw_store::synced_config_id("bragSheet")]);
        match &payload.operations[0] {
            JournalOperation::UpsertSyncedConfig(cfg) => {
                assert_eq!(cfg.config_type, "bragSheet");
                assert_eq!(cfg.data, "{\"a\":1}");
                assert_eq!(cfg.modified_at, Some(100));
            }
            other => panic!("expected UpsertSyncedConfig, got {other:?}"),
        }
    }

    #[test]
    fn gather_synced_config_none_when_clean() {
        let store = store();
        store.upsert_synced_config("bragSheet", "clean", Some(100), false).unwrap();
        let (payload, ids) = gather_dirty_synced_config_payload(&store).unwrap();
        assert!(payload.is_none());
        assert!(ids.is_empty());
    }

    // Regression guard for Part B of the brag-config sync-safety fix: while
    // CONFIG_SYNC_PUSH_ENABLED is false, a dirty synced_config row must NOT
    // produce any outbound payload — nothing goes on the wire — even though the
    // underlying dirty-gather is fully functional (so flipping the flag later is
    // the only change needed). The currently-released client can't tolerate an
    // UpsertSyncedConfig op on pull, so this is the safety gate.
    #[test]
    fn synced_config_push_gated_off_produces_no_outbound_payload() {
        let store = store();
        // Simulate a brag-config save: a dirty synced_config row.
        store.upsert_synced_config("bragSheet", "{\"include_map\":true}", Some(100), true).unwrap();

        // The raw dirty-gather still sees the row (kept functional)...
        let (raw, raw_ids) = gather_dirty_synced_config_payload(&store).unwrap();
        assert!(raw.is_some(), "dirty backlog stays gatherable for the future floor version");
        assert_eq!(raw_ids, vec![cw_store::synced_config_id("bragSheet")]);

        // ...but the gated outbound path — the only thing the push loop consults —
        // emits nothing, so no UpsertSyncedConfig op ever reaches the wire.
        let (outbound, out_ids) = gather_outbound_synced_config_payload(&store).unwrap();
        assert!(outbound.is_none(), "gated push must not emit any config payload");
        assert!(out_ids.is_empty());
    }

    // Brag config still round-trips locally via synced_config while the push is
    // gated off (save → load), so gating the wire doesn't break local storage.
    #[test]
    fn synced_config_round_trips_locally_while_push_gated() {
        let store = store();
        store.upsert_synced_config("bragSheet", "{\"include_map\":true}", Some(100), true).unwrap();
        assert_eq!(
            store.fetch_synced_config("bragSheet").unwrap().as_deref(),
            Some("{\"include_map\":true}")
        );
    }

    fn synced_config_payload(seq: i64, ts: i64, data: &str, modified_at: Option<i64>) -> JournalPayload {
        JournalPayload::new(
            uuid::Uuid::new_v4().to_string(),
            "device-remote",
            ts,
            seq,
            vec![JournalOperation::UpsertSyncedConfig(SyncedConfigPayload {
                id: cw_store::synced_config_id("bragSheet"),
                config_type: "bragSheet".into(),
                data: data.into(),
                modified_at,
            })],
        )
    }

    #[test]
    fn inbound_synced_config_inserts_new_clean_row() {
        let store = store();
        apply_inbound(&store, &synced_config_payload(1, 2_000, "remote-data", Some(500)), &mut Vec::new()).unwrap();

        assert_eq!(store.fetch_synced_config("bragSheet").unwrap().as_deref(), Some("remote-data"));
        // Lands clean — no re-push ping-pong.
        assert!(store.fetch_dirty_synced_configs().unwrap().is_empty());
    }

    #[test]
    fn inbound_synced_config_lww_prefers_higher_modified_at() {
        let store = store();
        // Local newer (modified_at=1000) than the inbound (500) → local kept.
        store.upsert_synced_config("bragSheet", "local-new", Some(1000), false).unwrap();
        apply_inbound(&store, &synced_config_payload(1, 2_000, "remote-old", Some(500)), &mut Vec::new()).unwrap();
        assert_eq!(store.fetch_synced_config("bragSheet").unwrap().as_deref(), Some("local-new"));

        // Now a strictly-newer inbound (modified_at=2000) wins.
        apply_inbound(&store, &synced_config_payload(2, 3_000, "remote-new", Some(2000)), &mut Vec::new()).unwrap();
        assert_eq!(store.fetch_synced_config("bragSheet").unwrap().as_deref(), Some("remote-new"));
    }

    #[test]
    fn inbound_synced_config_tie_keeps_local() {
        let store = store();
        store.upsert_synced_config("bragSheet", "local", Some(1000), false).unwrap();
        // Equal modified_at → local wins (never clobber own concurrent edit).
        apply_inbound(&store, &synced_config_payload(1, 2_000, "remote", Some(1000)), &mut Vec::new()).unwrap();
        assert_eq!(store.fetch_synced_config("bragSheet").unwrap().as_deref(), Some("local"));
    }

    // ---- logging_session gather / apply (the render-sessions-cross-device path) ----

    /// A minimal wire session with the given id/status/timestamps.
    fn session_wire(id: &str, started_at: i64, ended_at: Option<i64>, status: &str) -> LoggingSessionPayload {
        LoggingSessionPayload {
            id: id.into(),
            my_callsign: "W6JY".into(),
            started_at,
            ended_at,
            mode: "CW".into(),
            activation_type_raw_value: "pota".into(),
            status_raw_value: status.into(),
            park_reference: Some("US-1234".into()),
            operator_callsigns_raw_value: "[]".into(),
            ..Default::default()
        }
    }

    fn session_payload(seq: i64, ts: i64, wire: LoggingSessionPayload) -> JournalPayload {
        JournalPayload::new(
            uuid::Uuid::new_v4().to_string(),
            "device-remote",
            ts,
            seq,
            vec![JournalOperation::upsert_logging_session(wire)],
        )
    }

    #[test]
    fn inbound_session_inserts_new_clean_row() {
        let store = store();
        let wire = session_wire("sess-1", 1_700_000_000, Some(1_700_003_600), "completed");
        apply_inbound(&store, &session_payload(1, 2_000, wire), &mut Vec::new()).unwrap();

        let row = store.fetch_logging_session("sess-1").unwrap().expect("inserted");
        assert_eq!(row.my_callsign, "W6JY");
        assert_eq!(row.park_reference.as_deref(), Some("US-1234"));
        assert_eq!(row.status_raw_value, "completed");
        assert!(!row.cloud_dirty_flag, "inbound rows land clean (no sync ping-pong)");
        // Wire omits `programs`; a fresh row seeds it from the activation type.
        assert_eq!(row.programs_raw_value, r#"["pota"]"#);
    }

    #[test]
    fn inbound_session_merge_prefers_newer_and_preserves_nonwire() {
        let store = store();
        // Seed a local row that carries genuinely non-wire columns (contest_id,
        // activation_latitude, cloud_dirty_flag) the merge must NOT clobber.
        let mut local = wire_to_new_session(&session_wire("sess-1", 1_000, Some(2_000), "active"));
        local.contest_id = Some("cq-ww".into()); // non-wire
        local.activation_latitude = Some(37.8); // non-wire
        local.custom_title = Some("local title".into()); // wire
        local.cloud_dirty_flag = true; // pending local edit
        store.upsert_logging_session(&local).unwrap();

        // Newer remote (ended_at 5000 > local 2000) changes a wire field.
        let mut remote = session_wire("sess-1", 1_000, Some(5_000), "active");
        remote.custom_title = Some("remote title".into());
        apply_inbound(&store, &session_payload(1, 6_000, remote), &mut Vec::new()).unwrap();

        let row = store.fetch_logging_session("sess-1").unwrap().unwrap();
        assert_eq!(row.custom_title.as_deref(), Some("remote title"), "newer remote wire field won");
        assert_eq!(row.contest_id.as_deref(), Some("cq-ww"), "non-wire column preserved");
        assert_eq!(row.activation_latitude, Some(37.8), "non-wire column preserved");
        assert!(row.cloud_dirty_flag, "existing dirty flag preserved across inbound merge");
    }

    #[test]
    fn inbound_session_delete_hard_removes_row() {
        let store = store();
        store
            .upsert_logging_session(&wire_to_new_session(&session_wire("sess-1", 1_000, None, "active")))
            .unwrap();
        assert_eq!(store.logging_session_count().unwrap(), 1);

        let payload = JournalPayload::new(
            uuid::Uuid::new_v4().to_string(),
            "device-remote",
            2_000,
            1,
            vec![JournalOperation::Delete {
                entity_type: JournalEntityType::LoggingSession,
                id: "sess-1".into(),
            }],
        );
        apply_inbound(&store, &payload, &mut Vec::new()).unwrap();
        assert_eq!(store.logging_session_count().unwrap(), 0, "session delete is a hard delete");
    }

    #[test]
    fn session_to_wire_round_trips_all_wire_fields() {
        // A fully-populated wire session → store row → wire must be identical on
        // every modeled field (base64 blobs + photoFilenames array included).
        let mut original = session_wire("sess-rt", 1_700_000_000, Some(1_700_003_600), "completed");
        original.photo_filenames = vec!["a.jpg".into(), "b.jpg".into()];
        original.spot_comments_data = Some(vec![1, 2, 3, 4]);
        original.rove_stops_data = Some(vec![9, 8]);
        original.is_rove = true;
        original.qso_count = 42;
        original.solar_flux = Some(145.0);
        original.weather = Some("clear".into());
        original.operator_callsigns_raw_value = r#"["W6JY","N6ABC"]"#.into();

        let store_row = wire_to_new_session(&original);
        let back = session_to_wire(&store_row);
        assert_eq!(back, original, "every wire field survives store round-trip");
    }

    #[test]
    fn session_gather_emits_dirty_own_entity_type() {
        let store = store();
        let mut dirty = wire_to_new_session(&session_wire("sess-1", 1_000, None, "active"));
        dirty.cloud_dirty_flag = true;
        store.upsert_logging_session(&dirty).unwrap();
        store
            .upsert_logging_session(&wire_to_new_session(&session_wire("sess-clean", 2_000, None, "active")))
            .unwrap();

        let (payload, pushed_ids) = gather_dirty_logging_session_payload(&store).unwrap();
        let payload = payload.expect("dirty session produces a payload");
        assert_eq!(payload.operations.len(), 1, "only the dirty session emits an op");
        assert_eq!(pushed_ids, vec!["sess-1".to_string()]);
        assert_eq!(
            payload.operations[0].entity_type(),
            Some(JournalEntityType::LoggingSession),
            "payload is exclusively a loggingSession entity"
        );
    }

    // Regression guard for the forward-compat gate: while SESSION_SYNC_PUSH_ENABLED
    // is false, a dirty session must NOT produce any outbound payload — nothing on
    // the wire — even though the raw dirty-gather stays fully functional.
    #[test]
    fn session_push_gated_off_produces_no_outbound_payload() {
        let store = store();
        let mut dirty = wire_to_new_session(&session_wire("sess-1", 1_000, None, "active"));
        dirty.cloud_dirty_flag = true;
        store.upsert_logging_session(&dirty).unwrap();

        // Raw gather still sees the row (kept functional for the future flip)...
        let (raw, raw_ids) = gather_dirty_logging_session_payload(&store).unwrap();
        assert!(raw.is_some(), "dirty backlog stays gatherable for the future floor version");
        assert_eq!(raw_ids, vec!["sess-1".to_string()]);

        // ...but the gated outbound path — the only thing the push loop consults —
        // emits nothing, so no UpsertLoggingSession op ever reaches the wire.
        let (outbound, out_ids) = gather_outbound_logging_session_payload(&store).unwrap();
        assert!(outbound.is_none(), "gated push must not emit any session payload");
        assert!(out_ids.is_empty());
    }

    #[test]
    fn apply_inbound_reports_applied_keys_deduped() {
        let store = Store::open_in_memory("k").unwrap();
        let qso = remote_sync("11111111-1111-1111-1111-111111111111", "W6JY");
        let payload = JournalPayload {
            id: "p1".into(),
            device_id: "d".into(),
            timestamp: 1_700_000_000,
            sequence_number: 1,
            operations: vec![
                JournalOperation::upsert_qso(qso.clone()),
                JournalOperation::Delete { entity_type: JournalEntityType::Qso, id: qso.id.clone() },
                JournalOperation::Delete {
                    entity_type: JournalEntityType::LoggingSession,
                    id: "22222222-2222-2222-2222-222222222222".into(),
                },
                JournalOperation::Unknown,
            ],
        };
        let mut applied = Vec::new();
        apply_inbound(&store, &payload, &mut applied).unwrap();
        let deduped = dedupe_applied(applied);
        assert_eq!(
            deduped,
            vec![
                SyncAppliedKey { table: FfiStoreTable::Qso, id: qso.id.clone(), deleted: false },
                SyncAppliedKey {
                    table: FfiStoreTable::LoggingSession,
                    id: "22222222-2222-2222-2222-222222222222".into(),
                    deleted: true,
                },
            ]
        );
        // The soft delete landed: the row still exists, hidden.
        assert!(store.fetch_qso(&qso.id).unwrap().unwrap().is_hidden);
    }
}
