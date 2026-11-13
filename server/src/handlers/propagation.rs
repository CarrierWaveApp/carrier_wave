//! HTTP handlers that proxy HF propagation predictions to the Python sidecar.
//!
//! Both endpoints are `POST` and accept the same JSON bodies that the sidecar
//! exposes, so iOS and web clients can speak the public API without knowing
//! about the sidecar. Responses are cached in `propagation_cache` keyed by the
//! SHA-256 of the normalised request body.

use std::sync::Arc;
use std::time::Duration;

use axum::{extract::State, http::StatusCode, Extension, Json};
use reqwest::Client;
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::PgPool;

use crate::config::Config;
use crate::db::propagation_cache;
use crate::error::AppError;
use crate::models::propagation::{
    PointToPointRequest, PointToPointResponse, WheelRequest, WheelResponse,
};

/// Shared HTTP client used to talk to the sidecar. Cloning a `reqwest::Client`
/// is cheap (Arc under the hood) but we wrap it anyway for the extension layer.
#[derive(Clone)]
pub struct PropagationClient {
    pub http: Client,
    pub base_url: Arc<String>,
    pub cache_ttl_hours: i64,
}

impl PropagationClient {
    pub fn from_config(config: &Config) -> Self {
        let http = Client::builder()
            .timeout(Duration::from_secs(config.propagation_request_timeout_secs))
            .build()
            .expect("failed to build reqwest client for propagation sidecar");

        Self {
            http,
            base_url: Arc::new(config.propagation_service_url.trim_end_matches('/').to_string()),
            cache_ttl_hours: config.propagation_cache_ttl_hours,
        }
    }
}

pub async fn propagation_point_to_point(
    State(pool): State<PgPool>,
    Extension(client): Extension<PropagationClient>,
    Json(request): Json<PointToPointRequest>,
) -> Result<Json<PointToPointResponse>, AppError> {
    let raw = proxy_with_cache(&pool, &client, "p2p", &request).await?;
    let parsed: PointToPointResponse = serde_json::from_value(raw)
        .map_err(|err| AppError::Internal(format!("propagation p2p decode: {err}")))?;
    Ok(Json(parsed))
}

pub async fn propagation_wheel(
    State(pool): State<PgPool>,
    Extension(client): Extension<PropagationClient>,
    Json(request): Json<WheelRequest>,
) -> Result<Json<WheelResponse>, AppError> {
    let raw = proxy_with_cache(&pool, &client, "wheel", &request).await?;
    let parsed: WheelResponse = serde_json::from_value(raw)
        .map_err(|err| AppError::Internal(format!("propagation wheel decode: {err}")))?;
    Ok(Json(parsed))
}

/// Normalise the request to canonical JSON, look up the cache, and on miss
/// forward to the sidecar and persist the response.
async fn proxy_with_cache<T>(
    pool: &PgPool,
    client: &PropagationClient,
    endpoint: &str,
    request: &T,
) -> Result<Value, AppError>
where
    T: serde::Serialize,
{
    let body = serde_json::to_value(request)
        .map_err(|err| AppError::Internal(format!("propagation request encode: {err}")))?;
    let canonical = canonical_json(&body);
    let cache_key = hash_key(endpoint, &canonical);

    if let Some(hit) = propagation_cache::get_cached(pool, &cache_key).await? {
        return Ok(hit.response);
    }

    let url = format!("{}/{endpoint}", client.base_url);
    let response = client
        .http
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|err| AppError::Internal(format!("propagation sidecar unreachable: {err}")))?;

    let status = response.status();
    if !status.is_success() {
        let text = response.text().await.unwrap_or_default();
        // Propagate validation errors (422) as bad-request so the caller can
        // see why their inputs were rejected; everything else becomes a 500.
        if status == StatusCode::UNPROCESSABLE_ENTITY {
            return Err(AppError::Validation { message: text });
        }
        return Err(AppError::Internal(format!(
            "propagation sidecar returned {status}: {text}"
        )));
    }

    let payload: Value = response
        .json()
        .await
        .map_err(|err| AppError::Internal(format!("propagation response decode: {err}")))?;

    if let Err(err) = propagation_cache::put_cached(
        pool,
        &cache_key,
        endpoint,
        &payload,
        client.cache_ttl_hours,
    )
    .await
    {
        tracing::warn!(?err, endpoint, "failed to persist propagation cache entry");
    }

    Ok(payload)
}

fn canonical_json(value: &Value) -> String {
    // serde_json already emits deterministic output for scalars and arrays.
    // We sort object keys so the same logical request always hashes the same.
    match value {
        Value::Object(map) => {
            let mut entries: Vec<_> = map.iter().collect();
            entries.sort_by(|a, b| a.0.cmp(b.0));
            let mut out = String::from("{");
            for (idx, (key, val)) in entries.iter().enumerate() {
                if idx > 0 {
                    out.push(',');
                }
                out.push_str(&serde_json::to_string(key).unwrap_or_default());
                out.push(':');
                out.push_str(&canonical_json(val));
            }
            out.push('}');
            out
        }
        Value::Array(items) => {
            let mut out = String::from("[");
            for (idx, item) in items.iter().enumerate() {
                if idx > 0 {
                    out.push(',');
                }
                out.push_str(&canonical_json(item));
            }
            out.push(']');
            out
        }
        _ => serde_json::to_string(value).unwrap_or_else(|_| "null".to_string()),
    }
}

fn hash_key(endpoint: &str, canonical_body: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(endpoint.as_bytes());
    hasher.update(b":");
    hasher.update(canonical_body.as_bytes());
    hex::encode(hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn canonical_json_sorts_keys() {
        let a = json!({ "b": 1, "a": 2, "c": [3, 2, 1] });
        let b = json!({ "c": [3, 2, 1], "a": 2, "b": 1 });
        assert_eq!(canonical_json(&a), canonical_json(&b));
        assert_eq!(canonical_json(&a), "{\"a\":2,\"b\":1,\"c\":[3,2,1]}");
    }

    #[test]
    fn hash_key_differs_by_endpoint() {
        let body = json!({ "x": 1 });
        let key_p2p = hash_key("p2p", &canonical_json(&body));
        let key_wheel = hash_key("wheel", &canonical_json(&body));
        assert_ne!(key_p2p, key_wheel);
        // SHA-256 hex is 64 chars.
        assert_eq!(key_p2p.len(), 64);
    }
}
