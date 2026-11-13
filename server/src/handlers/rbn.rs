use axum::{extract::Query, Extension, Json};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::AppError;
use crate::rbn::store::{SpotFilter, SpotStore};
use crate::rbn::RbnSpot;

#[derive(Deserialize)]
pub struct SpotsQuery {
    pub call: Option<String>,
    pub spotter: Option<String>,
    pub mode: Option<String>,
    pub band: Option<String>,
    pub min_freq: Option<f64>,
    pub max_freq: Option<f64>,
    pub since: Option<DateTime<Utc>>,
    pub limit: Option<u32>,
}

#[derive(Serialize)]
pub struct SpotsResponse {
    pub total: usize,
    pub spots: Vec<RbnSpot>,
}

pub async fn rbn_spots(
    Extension(store): Extension<SpotStore>,
    Query(q): Query<SpotsQuery>,
) -> Result<Json<SpotsResponse>, AppError> {
    let modes = q
        .mode
        .as_ref()
        .map(|m| m.split(',').map(|s| s.trim().to_string()).collect());

    let filter = SpotFilter {
        call: q.call,
        spotter: q.spotter,
        modes,
        band: q.band,
        min_freq: q.min_freq,
        max_freq: q.max_freq,
        since: q.since,
        limit: q.limit,
    };

    let (total, spots) = store.query(&filter);

    Ok(Json(SpotsResponse { total, spots }))
}

#[derive(Deserialize)]
pub struct StatsQuery {
    pub minutes: Option<u32>,
}

pub async fn rbn_stats(
    Extension(store): Extension<SpotStore>,
    Query(q): Query<StatsQuery>,
) -> Result<Json<crate::rbn::store::StatsResult>, AppError> {
    let minutes = q.minutes.unwrap_or(60).clamp(1, 60);
    Ok(Json(store.stats(minutes)))
}

#[derive(Deserialize)]
pub struct SkimmersQuery {
    pub minutes: Option<u32>,
    pub limit: Option<u32>,
}

pub async fn rbn_skimmers(
    Extension(store): Extension<SpotStore>,
    Query(q): Query<SkimmersQuery>,
) -> Result<Json<crate::rbn::store::SkimmersResult>, AppError> {
    let minutes = q.minutes.unwrap_or(60).clamp(1, 60);
    let limit = q.limit.unwrap_or(100);
    Ok(Json(store.skimmers(minutes, limit)))
}
