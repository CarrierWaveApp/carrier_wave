use std::sync::OnceLock;

use axum::extract::State;
use sqlx::PgPool;
use tokio::sync::Semaphore;

use crate::db::sota_zones as db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::sota_zone::{
    SotaSummitInput, SotaZoneFeature, SotaZoneProperties, SotaZoneRow, SotaZonesMeta,
    SotaZonesRequest, SotaZonesResponse,
};
use crate::sota_az;

/// Max summits accepted per request (matches a generously-zoomed viewport).
const MAX_SUMMITS: usize = 400;
/// Max new summits to enqueue for compute per request (protects the DEM source).
const MAX_ENQUEUE: usize = 8;
/// Global cap on concurrent zone computations.
const MAX_CONCURRENT_COMPUTES: usize = 4;

/// POST /v1/sota/zones
/// Body: `{ "summits": [{ "code", "lat", "lon", "altitudeM"? }, ...] }`
/// Returns cached activation-zone polygons and enqueues background compute for
/// summits we haven't seen yet (reported in `meta.pending`).
pub async fn post_sota_zones(
    State(pool): State<PgPool>,
    Json(request): Json<SotaZonesRequest>,
) -> Result<Json<SotaZonesResponse>, AppError> {
    // SECURITY (CAR-312): this anonymous endpoint lets the request body define
    // both the cache key (summit code) and the geometry computed from it, into a
    // permanently-cached table every client trusts. Drop entries that can't be a
    // real submission — non-finite / out-of-range coordinates, or codes that
    // don't match the SOTA reference grammar — so junk can't seed poisoned or
    // permanent-`none` rows. NOTE: input validation alone does not stop a caller
    // forging plausible in-range coordinates for a valid code; closing that fully
    // needs authentication + multi-submitter corroboration and a recompute TTL
    // (tracked on CAR-312).
    let summits: Vec<SotaSummitInput> = request
        .summits
        .into_iter()
        .filter(is_valid_summit)
        .take(MAX_SUMMITS)
        .collect();
    let codes: Vec<String> = summits.iter().map(|summit| summit.code.clone()).collect();

    let rows = db::get_ok_zones_by_codes(&pool, &codes).await?;
    let features = rows_to_features(rows);
    let matched = features.len();

    let mut pending = Vec::new();
    if compute_enabled() {
        let existing: std::collections::HashSet<String> =
            db::existing_codes(&pool, &codes).await?.into_iter().collect();
        for summit in summits.iter().filter(|s| !existing.contains(&s.code)).take(MAX_ENQUEUE) {
            // Insert sentinel first so a concurrent request won't re-enqueue.
            db::insert_pending(&pool, &summit.code, summit.altitude_m).await?;
            spawn_compute(pool.clone(), summit.code.clone(), summit.lat, summit.lon, summit.altitude_m);
            pending.push(summit.code.clone());
        }
    }

    Ok(Json(SotaZonesResponse {
        collection_type: "FeatureCollection",
        features,
        meta: SotaZonesMeta { matched, pending },
    }))
}

/// Reject summit submissions that can't be genuine before they key or seed the
/// shared zone cache (CAR-312): coordinates must be finite and in range, and the
/// code must match the SOTA reference grammar `PREFIX/REGION-NUMBER`.
fn is_valid_summit(s: &SotaSummitInput) -> bool {
    (-90.0..=90.0).contains(&s.lat) && (-180.0..=180.0).contains(&s.lon) && is_valid_sota_code(&s.code)
}

fn is_valid_sota_code(code: &str) -> bool {
    if code.is_empty() || code.len() > 16 {
        return false;
    }
    let (Some(slash), Some(dash)) = (code.find('/'), code.rfind('-')) else {
        return false;
    };
    if slash >= dash {
        return false;
    }
    let prefix = &code[..slash];
    let region = &code[slash + 1..dash];
    let number = &code[dash + 1..];
    !prefix.is_empty()
        && !region.is_empty()
        && !number.is_empty()
        && prefix.chars().all(|c| c.is_ascii_alphanumeric())
        && region.chars().all(|c| c.is_ascii_alphanumeric())
        && number.chars().all(|c| c.is_ascii_digit())
}

fn rows_to_features(rows: Vec<SotaZoneRow>) -> Vec<SotaZoneFeature> {
    rows.into_iter().filter_map(row_to_feature).collect()
}

fn row_to_feature(row: SotaZoneRow) -> Option<SotaZoneFeature> {
    let geometry_json = row.geometry_json?;
    let geometry: serde_json::Value = serde_json::from_str(&geometry_json).ok()?;
    Some(SotaZoneFeature {
        feature_type: "Feature",
        geometry,
        properties: SotaZoneProperties {
            code: row.summit_code,
            altitude_m: row.altitude_m,
        },
    })
}

/// Spawn a bounded background task to compute and cache one summit's zone.
fn spawn_compute(pool: PgPool, code: String, lat: f64, lon: f64, altitude_m: Option<f64>) {
    tokio::spawn(async move {
        let _permit = compute_semaphore().acquire().await;
        let client = reqwest::Client::new();
        match sota_az::compute_activation_zone(&client, lat, lon, &tile_url()).await {
            Ok(Some(rings)) => {
                let geojson = sota_az::rings_to_geojson(&rings).to_string();
                if let Err(err) = db::upsert_ok(&pool, &code, altitude_m, &geojson).await {
                    tracing::warn!("SOTA AZ store failed for {}: {}", code, err);
                }
            }
            Ok(None) => {
                let _ = db::mark_none(&pool, &code).await;
            }
            Err(err) => {
                // Transient (network) failure — drop the sentinel so it retries.
                tracing::warn!("SOTA AZ compute failed for {}: {}", code, err);
                let _ = db::delete_zone(&pool, &code).await;
            }
        }
    });
}

fn compute_semaphore() -> &'static Semaphore {
    static SEM: OnceLock<Semaphore> = OnceLock::new();
    SEM.get_or_init(|| Semaphore::new(MAX_CONCURRENT_COMPUTES))
}

fn tile_url() -> String {
    std::env::var("SOTA_AZ_TILE_URL").unwrap_or_else(|_| sota_az::DEFAULT_TILE_URL.to_string())
}

fn compute_enabled() -> bool {
    std::env::var("SOTA_AZ_COMPUTE_ENABLED")
        .map(|value| value != "false" && value != "0")
        .unwrap_or(true)
}
