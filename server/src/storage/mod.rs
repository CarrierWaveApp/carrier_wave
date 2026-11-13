//! Pluggable object-storage abstraction for the sync server.
//!
//! The sync journal stores opaque ciphertext blobs in object storage and only
//! ever hands clients *presigned* URLs to upload/download them directly — the
//! server never proxies blob bytes in production. [`BlobStore`] captures that
//! surface. Two implementations exist:
//!
//! - [`memory::MemoryStore`] — a `HashMap`-backed store whose "presigned" URLs
//!   point back at a local dev handler (see [`memory::dev_blob_routes`]). Needs
//!   no external service, so integration tests run infra-free.
//! - [`s3::S3Store`] — wraps `object_store`'s `AmazonS3` and issues real S3
//!   presigned URLs. Used in production; not unit-tested here (needs a bucket).
//!
//! The active store is chosen by [`from_config`] based on whether the S3 config
//! is present, constructed in `main.rs`, and injected as
//! `Extension<Arc<dyn BlobStore>>`.

use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;

use crate::config::Config;
use crate::error::AppError;

pub mod memory;
pub mod s3;

pub use memory::{dev_blob_routes, MemoryStore};
pub use s3::S3Store;

/// What the store knows about a blob without reading it (a `HEAD`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BlobMeta {
    /// Stored object size in bytes.
    pub size: u64,
}

/// Object storage for opaque sync blobs.
///
/// Implementations hand out time-limited presigned URLs so clients upload and
/// download ciphertext directly against the backing store, and delete blobs
/// during snapshot garbage collection.
#[async_trait]
pub trait BlobStore: Send + Sync {
    /// Presigned URL a client can `PUT` `key`'s bytes to, valid for `ttl`.
    async fn presign_put(&self, key: &str, ttl: Duration) -> Result<String, AppError>;

    /// Presigned URL a client can `GET` `key`'s bytes from, valid for `ttl`.
    async fn presign_get(&self, key: &str, ttl: Duration) -> Result<String, AppError>;

    /// Metadata for the blob at `key`, or `None` if no such object exists.
    ///
    /// The server never sees blob bytes, so this is the only way it can confirm
    /// a client really uploaded what it said it would (CAR-334: the snapshot
    /// pointer must never reference an object that is not there).
    async fn head(&self, key: &str) -> Result<Option<BlobMeta>, AppError>;

    /// Delete the blob at `key`. Succeeds (idempotently) if it is absent.
    async fn delete(&self, key: &str) -> Result<(), AppError>;
}

/// The active blob store plus, when in-memory, a concrete handle for the dev
/// blob routes. See [`from_config`].
pub type BlobStoreHandles = (Arc<dyn BlobStore>, Option<Arc<MemoryStore>>);

/// Construct the blob store selected by configuration.
///
/// Returns the trait object for injection plus, when the in-memory store is
/// selected, a concrete handle the dev blob routes use to read/write bytes.
/// When `SYNC_S3_BUCKET` is set the S3 store is used and the second element is
/// `None` (real deploys use S3 presigned URLs, not the local dev handler).
pub fn from_config(config: &Config) -> Result<BlobStoreHandles, AppError> {
    match config.s3_bucket.as_deref() {
        Some(bucket) if !bucket.is_empty() => {
            let store = S3Store::from_config(config)?;
            Ok((Arc::new(store), None))
        }
        _ => {
            let store = Arc::new(MemoryStore::new());
            Ok((store.clone() as Arc<dyn BlobStore>, Some(store)))
        }
    }
}
