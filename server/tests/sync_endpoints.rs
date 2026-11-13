//! Integration tests for the sync HTTP handlers (Phase 4, Tasks 4.1 + 4.2) and
//! the two-phase snapshot protocol (CAR-334).
//!
//! These tests require a live Postgres pointed to by `TEST_DATABASE_URL`. They
//! skip silently when the env var isn't set so `cargo test` stays green in CI
//! environments without a DB. The router is wired with the real sync handlers,
//! the Phase-3 in-memory blob store (+ its dev blob routes), and a fixed
//! `AuthContext` injected as a request extension (no real JWT auth).

#![cfg(test)]

use std::sync::Arc;

use activities_server::auth::AuthContext;
use activities_server::handlers::sync;
use activities_server::storage::{self, BlobStore, MemoryStore};
use axum::{
    http::StatusCode,
    routing::{get, post, put},
    Extension, Router,
};
use axum_test::TestServer;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

async fn pool() -> Option<PgPool> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

fn auth_ctx(tenant: Uuid) -> AuthContext {
    // account_id present → it is the tenant. participant_id is a separate id we
    // never expect to be used here.
    AuthContext {
        callsign: "W6JY".to_string(),
        participant_id: Uuid::new_v4(),
        account_id: Some(tenant),
        client_id: None,
        scopes: vec!["sync:read".to_string(), "sync:write".to_string()],
    }
}

/// Build a router wired exactly like the production `auth_routes` sync seam,
/// but with the `AuthContext` injected directly and the in-memory blob store's
/// dev routes merged so presigned URLs resolve in-process.
fn server(pool: PgPool, store: Arc<MemoryStore>, tenant: Uuid) -> TestServer {
    let blob: Arc<dyn BlobStore> = store.clone();
    let v1 = Router::new()
        .route("/v1/sync/push", post(sync::push))
        .route("/v1/sync/changes", get(sync::changes))
        .route("/v1/sync/snapshot", post(sync::snapshot))
        .route("/v1/sync/snapshot/commit", post(sync::snapshot_commit))
        .route("/v1/sync/bootstrap", get(sync::bootstrap))
        .route("/v1/sync/key", put(sync::put_key).get(sync::get_key))
        .layer(Extension(blob))
        .layer(Extension(auth_ctx(tenant)));
    let dev = storage::dev_blob_routes().layer(Extension(store));
    let app: Router = v1.merge(dev).with_state(pool);
    TestServer::new(app).expect("build test server")
}

async fn cleanup(pool: &PgPool, tenant: Uuid) {
    for table in [
        "sync_entry",
        "sync_cursor",
        "sync_key_blob",
        "sync_snapshot_pending",
    ] {
        sqlx::query(&format!("DELETE FROM {table} WHERE tenant_id = $1"))
            .bind(tenant)
            .execute(pool)
            .await
            .unwrap();
    }
}

fn push_entry(id: Uuid, hash: &str, size: i64) -> Value {
    json!({
        "clientEntryId": id,
        "entityType": "qso",
        "op": "upsert",
        "byteSize": size,
        "contentHash": hash,
    })
}

/// Push `n` fresh entries and assert the high-water mark landed on `expect_hw`.
async fn push_n(server: &TestServer, n: usize, expect_hw: i64) {
    let entries: Vec<Value> = (0..n)
        .map(|i| {
            push_entry(
                Uuid::new_v4(),
                &format!("h{}", Uuid::new_v4()),
                8 + i as i64,
            )
        })
        .collect();
    let resp = server
        .post("/v1/sync/push")
        .json(&json!({ "entries": entries }))
        .await;
    resp.assert_status_ok();
    assert_eq!(
        resp.json::<Value>()["highWater"].as_i64().unwrap(),
        expect_hw
    );
}

/// Seqs currently in the journal, ascending, via `GET /changes?since=0`.
async fn journal_seqs(server: &TestServer) -> Vec<i64> {
    let resp = server.get("/v1/sync/changes?since=0").await;
    resp.assert_status_ok();
    resp.json::<Value>()["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["seq"].as_i64().unwrap())
        .collect()
}

/// `GET /bootstrap` as JSON.
async fn bootstrap(server: &TestServer) -> Value {
    let resp = server.get("/v1/sync/bootstrap").await;
    resp.assert_status_ok();
    resp.json()
}

/// Phase 1: `POST /snapshot`, asserting 200. Returns the response body.
async fn begin_snapshot(server: &TestServer, seq: i64, byte_size: i64, hash: &str) -> Value {
    let resp = server
        .post("/v1/sync/snapshot")
        .json(&json!({ "seq": seq, "byteSize": byte_size, "contentHash": hash }))
        .await;
    resp.assert_status_ok();
    let snap: Value = resp.json();
    assert_eq!(snap["seq"].as_i64().unwrap(), seq);
    assert!(
        snap["snapshotId"].is_string(),
        "phase 1 must return a snapshotId"
    );
    assert!(
        snap["expiresAt"].is_string(),
        "phase 1 must return expiresAt"
    );
    assert!(
        snap["snapshotBlobKey"]
            .as_str()
            .unwrap()
            .contains(&format!("/snapshots/{seq}-")),
        "blob key should be per-attempt: {}",
        snap["snapshotBlobKey"]
    );
    snap
}

/// Upload `bytes` to a phase-1 response's `uploadUrl`.
async fn upload_snapshot(server: &TestServer, snap: &Value, bytes: &[u8]) {
    server
        .put(snap["uploadUrl"].as_str().unwrap())
        .bytes(bytes.to_vec().into())
        .await
        .assert_status(StatusCode::NO_CONTENT);
}

/// Phase 2: `POST /snapshot/commit` for a phase-1 response. Returns the raw
/// response so callers can assert success or a specific error code.
async fn commit_snapshot(server: &TestServer, snap: &Value) -> axum_test::TestResponse {
    server
        .post("/v1/sync/snapshot/commit")
        .json(&json!({ "snapshotId": snap["snapshotId"] }))
        .await
}

fn error_code(resp: &axum_test::TestResponse) -> String {
    resp.json::<Value>()["error"]["code"]
        .as_str()
        .unwrap()
        .to_string()
}

async fn pending_count(pool: &PgPool, tenant: Uuid) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM sync_snapshot_pending WHERE tenant_id = $1")
        .bind(tenant)
        .fetch_one(pool)
        .await
        .unwrap()
}

/// Push 2 entries → upload ciphertext to the returned upload URLs →
/// `GET /changes?since=0` returns both in seq order → download URLs round-trip
/// the bytes. A re-push of the same `client_entry_id`s allocates no new seqs.
#[tokio::test]
async fn push_upload_changes_round_trip_and_idempotency() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let store = Arc::new(MemoryStore::new());
    let server = server(pool.clone(), store, tenant);

    let id_a = Uuid::new_v4();
    let id_b = Uuid::new_v4();
    let cipher_a = b"CIPHERTEXT-A-not-plaintext".to_vec();
    let cipher_b = b"CIPHERTEXT-B-not-plaintext".to_vec();

    let body = json!({
        "entries": [
            push_entry(id_a, "hash-a", cipher_a.len() as i64),
            push_entry(id_b, "hash-b", cipher_b.len() as i64),
        ]
    });

    // --- push ---
    let resp = server.post("/v1/sync/push").json(&body).await;
    resp.assert_status_ok();
    let push: Value = resp.json();
    let entries = push["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 2);
    assert_eq!(push["highWater"].as_i64().unwrap(), 2);

    // Seqs are 1 and 2, in request order.
    let seq_a = entries
        .iter()
        .find(|e| e["clientEntryId"] == json!(id_a))
        .unwrap()["seq"]
        .as_i64()
        .unwrap();
    let seq_b = entries
        .iter()
        .find(|e| e["clientEntryId"] == json!(id_b))
        .unwrap()["seq"]
        .as_i64()
        .unwrap();
    assert_eq!(seq_a, 1);
    assert_eq!(seq_b, 2);

    // --- upload ciphertext to each presigned PUT URL ---
    for entry in entries {
        let url = entry["uploadUrl"].as_str().unwrap();
        let bytes = if entry["clientEntryId"] == json!(id_a) {
            cipher_a.clone()
        } else {
            cipher_b.clone()
        };
        server
            .put(url)
            .bytes(bytes.into())
            .await
            .assert_status(StatusCode::NO_CONTENT);
    }

    // --- changes since 0 returns both in ascending seq order ---
    let resp = server.get("/v1/sync/changes?since=0").await;
    resp.assert_status_ok();
    let changes: Value = resp.json();
    let items = changes["entries"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert!(
        items[0]["seq"].as_i64().unwrap() < items[1]["seq"].as_i64().unwrap(),
        "changes must be in ascending seq order"
    );
    assert_eq!(changes["highWater"].as_i64().unwrap(), 2);
    assert!(changes["snapshotSeq"].is_null());

    // --- download URLs round-trip the exact bytes (matched by content hash) ---
    for item in items {
        let url = item["downloadUrl"].as_str().unwrap();
        let got = server.get(url).await;
        got.assert_status_ok();
        let want = match item["contentHash"].as_str().unwrap() {
            "hash-a" => &cipher_a,
            "hash-b" => &cipher_b,
            other => panic!("unexpected content hash {other}"),
        };
        assert_eq!(got.as_bytes(), &want[..]);
    }

    // --- idempotent re-push: same client_entry_ids, no new seqs ---
    let resp = server.post("/v1/sync/push").json(&body).await;
    resp.assert_status_ok();
    let repush: Value = resp.json();
    assert_eq!(
        repush["highWater"].as_i64().unwrap(),
        2,
        "re-push must not advance the high-water mark"
    );
    let repush_entries = repush["entries"].as_array().unwrap();
    let re_seq_a = repush_entries
        .iter()
        .find(|e| e["clientEntryId"] == json!(id_a))
        .unwrap()["seq"]
        .as_i64()
        .unwrap();
    assert_eq!(re_seq_a, seq_a, "re-push must keep the original seq");

    // The journal still holds exactly the two original entries.
    let resp = server.get("/v1/sync/changes?since=0").await;
    let changes: Value = resp.json();
    assert_eq!(changes["entries"].as_array().unwrap().len(), 2);

    cleanup(&pool, tenant).await;
}

/// The happy two-phase path (CAR-334): push 5 → POST /snapshot at seq 5 →
/// upload → POST /snapshot/commit → push 2 more → `GET /bootstrap` returns the
/// snapshot pointer (whose URL resolves to the uploaded bytes) and only the 2
/// post-snapshot entries. Between phase 1 and commit nothing is live or deleted.
#[tokio::test]
async fn bootstrap_returns_snapshot_pointer_and_post_snapshot_entries() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let store = Arc::new(MemoryStore::new());
    let server = server(pool.clone(), store.clone(), tenant);

    // --- push 5 (seqs 1..=5) ---
    push_n(&server, 5, 5).await;

    // --- phase 1: begin a snapshot at seq 5 ---
    let snapshot_bytes = b"SNAPSHOT-BYTES";
    let snap = begin_snapshot(&server, 5, snapshot_bytes.len() as i64, "snap-hash").await;

    // Nothing is live and nothing was deleted yet.
    let boot = bootstrap(&server).await;
    assert!(
        boot["snapshotSeq"].is_null(),
        "pointer must not move before commit"
    );
    assert!(boot["snapshotUrl"].is_null());
    assert_eq!(journal_seqs(&server).await, vec![1, 2, 3, 4, 5]);
    assert_eq!(pending_count(&pool, tenant).await, 1);

    // --- upload, then phase 2: commit ---
    upload_snapshot(&server, &snap, snapshot_bytes).await;
    let resp = commit_snapshot(&server, &snap).await;
    resp.assert_status_ok();
    let committed: Value = resp.json();
    assert_eq!(committed["snapshotSeq"].as_i64().unwrap(), 5);
    assert_eq!(committed["snapshotBlobKey"], snap["snapshotBlobKey"]);
    assert_eq!(committed["highWater"].as_i64().unwrap(), 5);
    assert_eq!(pending_count(&pool, tenant).await, 0);

    // GC removed strictly-below entries; seq 5 itself survives.
    assert_eq!(journal_seqs(&server).await, vec![5]);

    // A second commit of the same id is not replayable.
    let resp = commit_snapshot(&server, &snap).await;
    resp.assert_status(StatusCode::NOT_FOUND);
    assert_eq!(error_code(&resp), "SYNC_SNAPSHOT_NOT_FOUND");

    // --- push 2 more (seqs 6, 7) ---
    push_n(&server, 2, 7).await;

    // --- bootstrap: snapshot pointer + only the 2 post-snapshot entries ---
    let boot = bootstrap(&server).await;
    assert_eq!(boot["snapshotSeq"].as_i64().unwrap(), 5);
    assert_eq!(boot["highWater"].as_i64().unwrap(), 7);
    let snapshot_url = boot["snapshotUrl"]
        .as_str()
        .expect("bootstrap must include a snapshot download URL");
    let got = server.get(snapshot_url).await;
    got.assert_status_ok();
    assert_eq!(got.as_bytes(), &snapshot_bytes[..]);

    let seqs: Vec<i64> = boot["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["seq"].as_i64().unwrap())
        .collect();
    assert_eq!(seqs, vec![6, 7], "only the post-snapshot entries");

    cleanup(&pool, tenant).await;
}

/// Committing before the PUT is refused and deletes nothing — the pointer stays
/// where it was and every journal entry is still served. The pending snapshot
/// survives so the client can finish the upload and commit successfully.
#[tokio::test]
async fn commit_without_upload_is_rejected_and_deletes_nothing() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let store = Arc::new(MemoryStore::new());
    let server = server(pool.clone(), store.clone(), tenant);

    push_n(&server, 3, 3).await;
    let bytes = b"SNAP-3";
    let snap = begin_snapshot(&server, 3, bytes.len() as i64, "h3").await;

    // No upload → commit refused.
    let resp = commit_snapshot(&server, &snap).await;
    resp.assert_status(StatusCode::CONFLICT);
    assert_eq!(error_code(&resp), "SYNC_SNAPSHOT_NOT_UPLOADED");

    // Journal + pointer untouched; the pending attempt is still retryable.
    assert_eq!(journal_seqs(&server).await, vec![1, 2, 3]);
    let boot = bootstrap(&server).await;
    assert!(boot["snapshotSeq"].is_null());
    assert!(boot["snapshotUrl"].is_null());
    assert_eq!(boot["entries"].as_array().unwrap().len(), 3);
    assert_eq!(pending_count(&pool, tenant).await, 1);

    // Finish the upload and the same id now commits.
    upload_snapshot(&server, &snap, bytes).await;
    commit_snapshot(&server, &snap).await.assert_status_ok();
    assert_eq!(bootstrap(&server).await["snapshotSeq"].as_i64().unwrap(), 3);
    assert_eq!(journal_seqs(&server).await, vec![3]);

    cleanup(&pool, tenant).await;
}

/// A declared size that does not match the stored object is refused at commit
/// (the server cannot see plaintext, but it can see the byte count). Hash/size
/// repeated on commit must agree with phase 1. Nothing is deleted either way.
#[tokio::test]
async fn commit_with_mismatched_size_or_hash_is_rejected() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let store = Arc::new(MemoryStore::new());
    let server = server(pool.clone(), store.clone(), tenant);

    push_n(&server, 2, 2).await;

    // Declared 64 bytes, uploaded 9.
    let snap = begin_snapshot(&server, 2, 64, "declared-hash").await;
    upload_snapshot(&server, &snap, b"too-short").await;
    let resp = commit_snapshot(&server, &snap).await;
    resp.assert_status(StatusCode::CONFLICT);
    assert_eq!(error_code(&resp), "SYNC_SNAPSHOT_MISMATCH");

    // Commit-time hash disagreeing with the phase-1 hash.
    let resp = server
        .post("/v1/sync/snapshot/commit")
        .json(&json!({ "snapshotId": snap["snapshotId"], "contentHash": "other-hash" }))
        .await;
    resp.assert_status(StatusCode::CONFLICT);
    assert_eq!(error_code(&resp), "SYNC_SNAPSHOT_MISMATCH");

    assert_eq!(journal_seqs(&server).await, vec![1, 2]);
    assert!(bootstrap(&server).await["snapshotSeq"].is_null());

    cleanup(&pool, tenant).await;
}

/// `seq` must lie in `(current_snapshot_seq, high_water]`. Anything else —
/// zero, negative, past the high-water mark, `i64::MAX`, or at/below the live
/// snapshot — is a 409 that records nothing and deletes nothing.
#[tokio::test]
async fn snapshot_seq_out_of_range_is_rejected() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let store = Arc::new(MemoryStore::new());
    let server = server(pool.clone(), store.clone(), tenant);

    // Fresh tenant: no history at all, so every seq is out of range.
    for seq in [1i64, i64::MAX] {
        let resp = server
            .post("/v1/sync/snapshot")
            .json(&json!({ "seq": seq }))
            .await;
        resp.assert_status(StatusCode::CONFLICT);
        assert_eq!(error_code(&resp), "SYNC_SEQUENCE_CONFLICT");
    }

    push_n(&server, 3, 3).await;
    for seq in [0i64, -1, 4, i64::MAX] {
        let resp = server
            .post("/v1/sync/snapshot")
            .json(&json!({ "seq": seq }))
            .await;
        resp.assert_status(StatusCode::CONFLICT);
        assert_eq!(error_code(&resp), "SYNC_SEQUENCE_CONFLICT", "seq {seq}");
    }
    assert_eq!(pending_count(&pool, tenant).await, 0);
    assert_eq!(journal_seqs(&server).await, vec![1, 2, 3]);

    // Commit a real snapshot at 2, then 1 and 2 are no longer acceptable.
    let snap = begin_snapshot(&server, 2, 4, "h").await;
    upload_snapshot(&server, &snap, b"snap").await;
    commit_snapshot(&server, &snap).await.assert_status_ok();
    for seq in [1i64, 2] {
        let resp = server
            .post("/v1/sync/snapshot")
            .json(&json!({ "seq": seq }))
            .await;
        resp.assert_status(StatusCode::CONFLICT);
        assert_eq!(error_code(&resp), "SYNC_SEQUENCE_CONFLICT", "seq {seq}");
    }
    // ...but 3 still is.
    begin_snapshot(&server, 3, 4, "h").await;
    assert_eq!(bootstrap(&server).await["snapshotSeq"].as_i64().unwrap(), 2);
    assert_eq!(journal_seqs(&server).await, vec![2, 3]);

    cleanup(&pool, tenant).await;
}

/// Two pending snapshots at seqs 2 and 4, both uploaded. Committing 4 first
/// then 2 must leave the pointer at 4: a stale commit can never move it
/// backward, and the stale attempt is discarded (row + blob).
#[tokio::test]
async fn snapshot_pointer_never_moves_backward() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let store = Arc::new(MemoryStore::new());
    let server = server(pool.clone(), store.clone(), tenant);

    push_n(&server, 4, 4).await;
    let low = begin_snapshot(&server, 2, 3, "low").await;
    let high = begin_snapshot(&server, 4, 4, "high").await;
    upload_snapshot(&server, &low, b"low").await;
    upload_snapshot(&server, &high, b"high").await;
    assert_eq!(pending_count(&pool, tenant).await, 2);

    commit_snapshot(&server, &high).await.assert_status_ok();
    assert_eq!(bootstrap(&server).await["snapshotSeq"].as_i64().unwrap(), 4);
    assert_eq!(journal_seqs(&server).await, vec![4]);

    // The lower pending attempt was purged by the higher commit, so it is gone.
    let resp = commit_snapshot(&server, &low).await;
    resp.assert_status(StatusCode::NOT_FOUND);
    assert_eq!(error_code(&resp), "SYNC_SNAPSHOT_NOT_FOUND");
    assert_eq!(pending_count(&pool, tenant).await, 0);
    let low_key = low["snapshotBlobKey"].as_str().unwrap();
    assert!(
        store.head(low_key).await.unwrap().is_none(),
        "the superseded attempt's blob should be GC'd"
    );

    // Pointer still at 4, and its bytes are the ones that were committed.
    let boot = bootstrap(&server).await;
    assert_eq!(boot["snapshotSeq"].as_i64().unwrap(), 4);
    let got = server.get(boot["snapshotUrl"].as_str().unwrap()).await;
    got.assert_status_ok();
    assert_eq!(got.as_bytes(), &b"high"[..]);

    // Even a direct forward-only guard check: the committed key must be `high`'s.
    let (live_seq, live_key): (Option<i64>, Option<String>) = sqlx::query_as(
        "SELECT snapshot_seq, snapshot_blob_key FROM sync_cursor WHERE tenant_id = $1",
    )
    .bind(tenant)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(live_seq, Some(4));
    assert_eq!(live_key.as_deref(), high["snapshotBlobKey"].as_str());

    cleanup(&pool, tenant).await;
}

/// A snapshot that is begun but never uploaded/committed (client crashed, tab
/// closed, URL expired) must be harmless: bootstrap and changes keep serving the
/// full journal, an expired id cannot be committed, and the next snapshot
/// request purges the stale row.
#[tokio::test]
async fn bootstrap_after_abandoned_snapshot_serves_full_journal() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };
    let tenant = Uuid::new_v4();
    cleanup(&pool, tenant).await;

    let store = Arc::new(MemoryStore::new());
    let server = server(pool.clone(), store.clone(), tenant);

    push_n(&server, 3, 3).await;
    let abandoned = begin_snapshot(&server, 3, 16, "abandoned").await;
    // ...and the client goes away without uploading.

    let boot = bootstrap(&server).await;
    assert!(
        boot["snapshotSeq"].is_null(),
        "an uncommitted snapshot is never live"
    );
    assert!(boot["snapshotUrl"].is_null());
    assert_eq!(boot["highWater"].as_i64().unwrap(), 3);
    assert_eq!(boot["entries"].as_array().unwrap().len(), 3);
    assert_eq!(journal_seqs(&server).await, vec![1, 2, 3]);

    // Fast-forward the clock: the pending row is now past its TTL.
    sqlx::query(
        "UPDATE sync_snapshot_pending SET expires_at = now() - interval '1 hour' \
         WHERE tenant_id = $1",
    )
    .bind(tenant)
    .execute(&pool)
    .await
    .unwrap();

    // Late commit (even after a late upload) is refused, and the row is gone.
    upload_snapshot(&server, &abandoned, b"late-upload-late").await;
    let resp = commit_snapshot(&server, &abandoned).await;
    resp.assert_status(StatusCode::NOT_FOUND);
    assert_eq!(error_code(&resp), "SYNC_SNAPSHOT_NOT_FOUND");
    assert_eq!(pending_count(&pool, tenant).await, 0);
    assert!(
        store
            .head(abandoned["snapshotBlobKey"].as_str().unwrap())
            .await
            .unwrap()
            .is_none(),
        "late-uploaded bytes for an expired attempt are GC'd"
    );
    assert_eq!(journal_seqs(&server).await, vec![1, 2, 3]);

    // A second abandoned attempt, expired, is purged by the next fresh request.
    begin_snapshot(&server, 3, 16, "abandoned-2").await;
    sqlx::query(
        "UPDATE sync_snapshot_pending SET expires_at = now() - interval '1 hour' \
         WHERE tenant_id = $1",
    )
    .bind(tenant)
    .execute(&pool)
    .await
    .unwrap();
    let fresh = begin_snapshot(&server, 3, 5, "fresh").await;
    assert_eq!(
        pending_count(&pool, tenant).await,
        1,
        "only the fresh attempt remains"
    );

    // The fresh attempt completes normally.
    upload_snapshot(&server, &fresh, b"fresh").await;
    commit_snapshot(&server, &fresh).await.assert_status_ok();
    let boot = bootstrap(&server).await;
    assert_eq!(boot["snapshotSeq"].as_i64().unwrap(), 3);
    assert_eq!(boot["entries"].as_array().unwrap().len(), 0);

    cleanup(&pool, tenant).await;
}

/// A legacy `fd_`-token request (AuthContext without an account_id) is refused
/// on every sync route with 403 ACCOUNT_REQUIRED — sync data must always live
/// under an email-verified account tenant.
#[tokio::test]
async fn legacy_token_gets_account_required_on_every_route() {
    let Some(pool) = pool().await else {
        eprintln!("skipping: TEST_DATABASE_URL not set");
        return;
    };

    let legacy = AuthContext {
        callsign: "W6JY".to_string(),
        participant_id: Uuid::new_v4(),
        account_id: None,
        client_id: None,
        scopes: Vec::new(),
    };
    let store = Arc::new(MemoryStore::new());
    let blob: Arc<dyn BlobStore> = store.clone();
    let v1 = Router::new()
        .route("/v1/sync/push", post(sync::push))
        .route("/v1/sync/changes", get(sync::changes))
        .route("/v1/sync/snapshot", post(sync::snapshot))
        .route("/v1/sync/snapshot/commit", post(sync::snapshot_commit))
        .route("/v1/sync/bootstrap", get(sync::bootstrap))
        .route("/v1/sync/key", put(sync::put_key).get(sync::get_key))
        .layer(Extension(blob))
        .layer(Extension(legacy));
    let app: Router = v1.with_state(pool);
    let server = TestServer::new(app).expect("build test server");

    let requests: Vec<(&str, _)> = vec![
        (
            "push",
            server
                .post("/v1/sync/push")
                .json(&json!({ "entries": [push_entry(Uuid::new_v4(), "h", 1)] }))
                .await,
        ),
        ("changes", server.get("/v1/sync/changes").await),
        (
            "snapshot",
            server
                .post("/v1/sync/snapshot")
                .json(&json!({ "seq": 1, "byteSize": 1, "contentHash": "h" }))
                .await,
        ),
        (
            "snapshot_commit",
            server
                .post("/v1/sync/snapshot/commit")
                .json(&json!({ "snapshotId": Uuid::new_v4() }))
                .await,
        ),
        ("bootstrap", server.get("/v1/sync/bootstrap").await),
        (
            "put_key",
            server
                .put("/v1/sync/key")
                .json(&json!({ "wrappedKey": "AAAA", "kdfParams": {} }))
                .await,
        ),
        ("get_key", server.get("/v1/sync/key").await),
    ];

    for (name, resp) in requests {
        assert_eq!(
            resp.status_code(),
            StatusCode::FORBIDDEN,
            "{name} should be forbidden for legacy tokens"
        );
        let body: Value = resp.json();
        assert_eq!(
            body["error"]["code"], "ACCOUNT_REQUIRED",
            "{name} should return ACCOUNT_REQUIRED"
        );
    }
}
