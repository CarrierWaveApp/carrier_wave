//! In-memory [`BlobStore`] for dev and infra-free integration tests.
//!
//! Bytes live in a process-local `HashMap`. "Presigned" URLs point back at a
//! local dev handler ([`dev_blob_routes`]) that `PUT`s/`GET`s those bytes, so
//! the full push → upload → changes → download round-trip works without S3.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::Duration;

use async_trait::async_trait;
use axum::{
    body::Bytes,
    extract::Path,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::get,
    Extension, Router,
};

use super::{BlobMeta, BlobStore};
use crate::error::AppError;

/// Process-local blob store backed by a `HashMap<key, bytes>`.
///
/// Cloning shares the same underlying map (`Arc`), so the trait object injected
/// into sync handlers and the concrete handle used by the dev blob routes see
/// the same data.
#[derive(Clone, Default)]
pub struct MemoryStore {
    blobs: Arc<RwLock<HashMap<String, Vec<u8>>>>,
}

impl MemoryStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Store `bytes` under `key`, overwriting any existing value.
    pub fn put_bytes(&self, key: &str, bytes: Vec<u8>) {
        self.blobs
            .write()
            .expect("blob store lock poisoned")
            .insert(key.to_string(), bytes);
    }

    /// Fetch the bytes stored under `key`, if any.
    pub fn get_bytes(&self, key: &str) -> Option<Vec<u8>> {
        self.blobs
            .read()
            .expect("blob store lock poisoned")
            .get(key)
            .cloned()
    }
}

#[async_trait]
impl BlobStore for MemoryStore {
    async fn presign_put(&self, key: &str, _ttl: Duration) -> Result<String, AppError> {
        Ok(blob_url(key))
    }

    async fn presign_get(&self, key: &str, _ttl: Duration) -> Result<String, AppError> {
        Ok(blob_url(key))
    }

    async fn head(&self, key: &str) -> Result<Option<BlobMeta>, AppError> {
        Ok(self
            .blobs
            .read()
            .expect("blob store lock poisoned")
            .get(key)
            .map(|bytes| BlobMeta {
                size: bytes.len() as u64,
            }))
    }

    async fn delete(&self, key: &str) -> Result<(), AppError> {
        self.blobs
            .write()
            .expect("blob store lock poisoned")
            .remove(key);
        Ok(())
    }
}

/// Build the local dev blob URL for `key`.
///
/// Keys are path-shaped (`{tenant}/entries/{seq}.bin`); the `/v1/sync/blob/*key`
/// wildcard route below captures the remainder verbatim, slashes included, so
/// we percent-encode only characters that would break the path while leaving
/// `/` as the segment separator.
fn blob_url(key: &str) -> String {
    format!("/v1/sync/blob/{}", encode_key(key))
}

/// Percent-encode a blob key for use in a URL path, preserving `/` separators.
fn encode_key(key: &str) -> String {
    let mut out = String::with_capacity(key.len());
    for byte in key.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b'/' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

/// Dev/test-only routes that back [`MemoryStore`]'s presigned URLs.
///
/// `PUT /v1/sync/blob/*key` stores the request body; `GET /v1/sync/blob/*key`
/// returns it. Mounted only when the in-memory store is active — real deploys
/// use S3 presigned URLs and never hit these. Unauthenticated: blob keys embed
/// a tenant UUID, so they are unguessable-ish, and this is a dev convenience.
///
/// The caller must attach the shared store via
/// `Extension(Arc<MemoryStore>)`.
///
/// Generic over the router state `S` so it can be merged into the main
/// `Router<PgPool>` (the handlers themselves need no state).
pub fn dev_blob_routes<S>() -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    Router::new().route("/v1/sync/blob/*key", get(get_blob).put(put_blob))
}

async fn put_blob(
    Extension(store): Extension<Arc<MemoryStore>>,
    Path(key): Path<String>,
    body: Bytes,
) -> Response {
    store.put_bytes(&key, body.to_vec());
    StatusCode::NO_CONTENT.into_response()
}

async fn get_blob(
    Extension(store): Extension<Arc<MemoryStore>>,
    Path(key): Path<String>,
) -> Response {
    match store.get_bytes(&key) {
        Some(bytes) => (StatusCode::OK, Bytes::from(bytes)).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum_test::TestServer;

    fn test_server(store: Arc<MemoryStore>) -> TestServer {
        let app: Router = dev_blob_routes().layer(Extension(store));
        TestServer::new(app).expect("build test server")
    }

    #[tokio::test]
    async fn put_get_delete_round_trip() {
        let store = Arc::new(MemoryStore::new());
        let server = test_server(store.clone());

        let key = "11111111-1111-1111-1111-111111111111/entries/1.bin";
        let payload = b"ciphertext-bytes".to_vec();

        // PUT via the presigned (local) URL.
        let put_url = store
            .presign_put(key, Duration::from_secs(60))
            .await
            .unwrap();
        assert_eq!(
            put_url,
            "/v1/sync/blob/11111111-1111-1111-1111-111111111111/entries/1.bin"
        );
        let resp = server.put(&put_url).bytes(payload.clone().into()).await;
        resp.assert_status(StatusCode::NO_CONTENT);

        // GET the bytes back, byte-for-byte.
        let get_url = store
            .presign_get(key, Duration::from_secs(60))
            .await
            .unwrap();
        let resp = server.get(&get_url).await;
        resp.assert_status_ok();
        assert_eq!(resp.as_bytes(), &payload);

        // HEAD reports the stored size.
        assert_eq!(
            store.head(key).await.unwrap(),
            Some(BlobMeta {
                size: payload.len() as u64
            })
        );

        // Delete, then confirm it is gone (404 + empty store + HEAD is None).
        store.delete(key).await.unwrap();
        assert!(store.get_bytes(key).is_none());
        assert_eq!(store.head(key).await.unwrap(), None);
        let resp = server.get(&get_url).await;
        resp.assert_status(StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn head_of_missing_key_is_none() {
        let store = MemoryStore::new();
        assert_eq!(store.head("nope/entries/1.bin").await.unwrap(), None);
    }
}
