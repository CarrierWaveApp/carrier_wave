//! Live S3-compatible object-store smoke test (Cloudflare R2, MinIO, AWS S3).
//!
//! Runs ONLY when `SYNC_S3_BUCKET` is set; otherwise it self-skips so CI and
//! local runs without a bucket stay green. It exercises the exact presigned-URL
//! round trip a sync client performs against production storage:
//!
//!   presign PUT -> upload -> presign GET -> download -> compare -> delete -> confirm gone
//!
//! This is the end-to-end proof that `S3Store::from_config` actually works
//! against the configured bucket — including presigned-URL addressing, which is
//! the one thing that can silently differ between providers.
//!
//! Run against Cloudflare R2:
//!
//! ```sh
//! SYNC_S3_BUCKET=cwlogs \
//! SYNC_S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com \
//! SYNC_S3_REGION=auto \
//! SYNC_S3_ACCESS_KEY_ID=<r2 access key id> \
//! SYNC_S3_SECRET_ACCESS_KEY=<r2 secret> \
//! cargo test --test sync_s3_smoke -- --nocapture
//! ```

use std::env;
use std::time::Duration;

use activities_server::config::Config;
use activities_server::storage::{BlobStore, S3Store};

/// Build the configured `S3Store`, or `None` (skip) when no bucket is set.
fn configured_store() -> Option<S3Store> {
    if env::var("SYNC_S3_BUCKET").is_err() {
        eprintln!("SYNC_S3_BUCKET unset — skipping live S3/R2 smoke test");
        return None;
    }
    // `S3Store` ignores these, but `Config::from_env()` requires them. Supply
    // placeholders when absent so the smoke test needs only `SYNC_S3_*` set.
    if env::var("DATABASE_URL").is_err() {
        env::set_var("DATABASE_URL", "postgres://unused/smoke");
    }
    if env::var("ADMIN_TOKEN").is_err() {
        env::set_var("ADMIN_TOKEN", "unused-smoke-token");
    }
    let config = Config::from_env().expect("Config::from_env");
    Some(S3Store::from_config(&config).expect("S3Store::from_config"))
}

#[tokio::test]
async fn s3_presigned_round_trip() {
    let Some(store) = configured_store() else {
        return;
    };

    let key = format!("_smoke/{}.bin", uuid::Uuid::new_v4());
    let body = b"carrier-wave object-store smoke test".to_vec();
    let ttl = Duration::from_secs(300);
    let http = reqwest::Client::new();

    // 1. presign PUT + upload the (opaque) bytes, exactly as a client would.
    let put_url = store.presign_put(&key, ttl).await.expect("presign_put");
    let put = http
        .put(&put_url)
        .body(body.clone())
        .send()
        .await
        .expect("PUT failed to send");
    assert!(
        put.status().is_success(),
        "PUT to presigned URL failed: {} — {}",
        put.status(),
        put.text().await.unwrap_or_default()
    );

    // 2. presign GET + download, confirm bytes round-trip unchanged.
    let get_url = store.presign_get(&key, ttl).await.expect("presign_get");
    let got = http.get(&get_url).send().await.expect("GET failed to send");
    assert!(
        got.status().is_success(),
        "GET from presigned URL failed: {}",
        got.status()
    );
    let downloaded = got.bytes().await.expect("reading GET body").to_vec();
    assert_eq!(downloaded, body, "downloaded bytes differ from uploaded");

    // 3. delete via the store, then confirm the object is actually gone.
    store.delete(&key).await.expect("delete");
    let after = http
        .get(&get_url)
        .send()
        .await
        .expect("GET-after-delete failed to send");
    assert!(
        !after.status().is_success(),
        "object still readable after delete: {}",
        after.status()
    );

    eprintln!("live S3/R2 smoke test passed for key {key}");
}
