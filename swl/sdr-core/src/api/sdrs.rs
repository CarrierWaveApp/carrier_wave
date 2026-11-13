use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::sdr::SdrInfo;
use crate::types::SdrId;

use super::AppState;

#[derive(Serialize)]
pub struct SdrListResponse {
    pub sdrs: Vec<SdrInfo>,
}

pub async fn list_sdrs(State(state): State<Arc<AppState>>) -> Json<SdrListResponse> {
    let sdrs = state.registry.list().await;
    Json(SdrListResponse { sdrs })
}

pub async fn get_sdr(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<SdrInfo>, StatusCode> {
    let sdr_id = SdrId::from(id.as_str());
    state
        .registry
        .get(&sdr_id)
        .await
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

#[derive(Serialize)]
pub struct ScanResponse {
    pub discovered: usize,
}

pub async fn scan_sdrs(State(state): State<Arc<AppState>>) -> Json<ScanResponse> {
    state.registry.scan().await;
    let count = state.registry.list().await.len();
    Json(ScanResponse { discovered: count })
}

#[derive(Deserialize)]
pub struct SdrSearchParams {
    pub lat: f64,
    pub lon: f64,
    #[serde(default = "default_count")]
    pub count: usize,
    #[serde(default)]
    pub available_only: bool,
}

fn default_count() -> usize {
    10
}

#[derive(Serialize)]
pub struct SdrSearchResult {
    pub sdr: SdrInfo,
    pub distance_km: f64,
    pub available_slots: Option<u32>,
}

#[derive(Serialize)]
pub struct SdrSearchResponse {
    pub results: Vec<SdrSearchResult>,
}

/// Haversine great-circle distance in km.
fn haversine_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const R: f64 = 6371.0;
    let dlat = (lat2 - lat1).to_radians();
    let dlon = (lon2 - lon1).to_radians();
    let a = (dlat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (dlon / 2.0).sin().powi(2);
    R * 2.0 * a.sqrt().asin()
}

pub async fn search_sdrs(
    State(state): State<Arc<AppState>>,
    Query(params): Query<SdrSearchParams>,
) -> Json<SdrSearchResponse> {
    let sdrs = state.registry.list().await;

    let mut results: Vec<SdrSearchResult> = sdrs
        .into_iter()
        .filter_map(|sdr| {
            let status = sdr.kiwi_status.as_ref()?;
            let lat = status.lat?;
            let lon = status.lon?;

            // Skip offline SDRs when available_only is set
            if params.available_only {
                if status.offline == Some(true) {
                    return None;
                }
                // Skip full SDRs
                if let (Some(users), Some(max)) = (status.users, status.users_max) {
                    if users >= max {
                        return None;
                    }
                }
            }

            let distance_km = haversine_km(params.lat, params.lon, lat, lon);
            let available_slots = match (status.users, status.users_max) {
                (Some(u), Some(m)) => Some(m.saturating_sub(u)),
                _ => None,
            };

            Some(SdrSearchResult {
                sdr,
                distance_km,
                available_slots,
            })
        })
        .collect();

    results.sort_by(|a, b| a.distance_km.partial_cmp(&b.distance_km).unwrap());
    results.truncate(params.count);

    Json(SdrSearchResponse { results })
}
