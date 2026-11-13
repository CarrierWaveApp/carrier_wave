//! S3-backed [`BlobStore`] for production.
//!
//! Wraps `object_store`'s `AmazonS3` and issues real presigned URLs via the
//! `Signer` trait so clients upload/download ciphertext directly against the
//! bucket. Not unit-tested here — exercising it needs a live bucket; this
//! module only has to compile and stay clippy-clean.

use std::time::Duration;

use async_trait::async_trait;
use object_store::{
    aws::{AmazonS3, AmazonS3Builder},
    path::Path as ObjectPath,
    signer::Signer,
    ObjectStore,
};
use reqwest::Method;

use super::{BlobMeta, BlobStore};
use crate::config::Config;
use crate::error::AppError;

/// Production blob store backed by an S3-compatible bucket.
pub struct S3Store {
    inner: AmazonS3,
}

impl S3Store {
    /// Build the S3 store from configuration.
    ///
    /// `SYNC_S3_BUCKET` is required (the caller only reaches here when it is
    /// set); region, endpoint, and credentials are optional so that instance
    /// IAM roles / standard AWS env vars can supply them when omitted.
    pub fn from_config(config: &Config) -> Result<Self, AppError> {
        let bucket = config
            .s3_bucket
            .as_deref()
            .ok_or_else(|| AppError::Storage("SYNC_S3_BUCKET is required for S3Store".into()))?;

        let mut builder = AmazonS3Builder::from_env().with_bucket_name(bucket);

        if let Some(region) = config.s3_region.as_deref() {
            builder = builder.with_region(region);
        }
        if let Some(endpoint) = config.s3_endpoint.as_deref() {
            builder = builder.with_endpoint(endpoint);
            // Custom endpoints (e.g. MinIO) are frequently plain HTTP in dev.
            if endpoint.starts_with("http://") {
                builder = builder.with_allow_http(true);
            }
        }
        if let Some(key_id) = config.s3_access_key_id.as_deref() {
            builder = builder.with_access_key_id(key_id);
        }
        if let Some(secret) = config.s3_secret_access_key.as_deref() {
            builder = builder.with_secret_access_key(secret);
        }

        let inner = builder
            .build()
            .map_err(|e| AppError::Storage(format!("failed to build S3 client: {e}")))?;

        Ok(Self { inner })
    }

    async fn presign(&self, method: Method, key: &str, ttl: Duration) -> Result<String, AppError> {
        let path = ObjectPath::from(key);
        let url = self
            .inner
            .signed_url(method, &path, ttl)
            .await
            .map_err(|e| AppError::Storage(format!("failed to presign URL: {e}")))?;
        Ok(url.to_string())
    }
}

#[async_trait]
impl BlobStore for S3Store {
    async fn presign_put(&self, key: &str, ttl: Duration) -> Result<String, AppError> {
        self.presign(Method::PUT, key, ttl).await
    }

    async fn presign_get(&self, key: &str, ttl: Duration) -> Result<String, AppError> {
        self.presign(Method::GET, key, ttl).await
    }

    async fn head(&self, key: &str) -> Result<Option<BlobMeta>, AppError> {
        let path = ObjectPath::from(key);
        match self.inner.head(&path).await {
            Ok(meta) => Ok(Some(BlobMeta {
                size: meta.size as u64,
            })),
            Err(object_store::Error::NotFound { .. }) => Ok(None),
            Err(e) => Err(AppError::Storage(format!("failed to head blob: {e}"))),
        }
    }

    async fn delete(&self, key: &str) -> Result<(), AppError> {
        let path = ObjectPath::from(key);
        self.inner
            .delete(&path)
            .await
            .map_err(|e| AppError::Storage(format!("failed to delete blob: {e}")))?;
        Ok(())
    }
}
