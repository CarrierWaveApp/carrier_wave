use axum::extract::{Query, State};
use sqlx::PgPool;

use crate::db::pota_stats as db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::pota_stats::{
    ActivatorRankingEntry, ActivatorRankingsResponse, ActivatorStatsQuery, ActivatorStatsResponse,
    FreshnessInfo, HunterStatsQuery, HunterStatsResponse, ParkStatsResponse,
    PotaSyncStatusResponse, QsosByMode, RankedCallsignResponse, RankingsQuery, StateStatsResponse,
};

use super::DataResponse;

/// GET /v1/pota/stats/activator?callsign=...&state=...&mode=...
pub async fn get_activator_stats(
    State(pool): State<PgPool>,
    Query(params): Query<ActivatorStatsQuery>,
) -> Result<Json<DataResponse<ActivatorStatsResponse>>, AppError> {
    let callsign = params.callsign.to_uppercase();

    let freshness: FreshnessInfo = db::get_activator_freshness(&pool, params.state.as_deref())
        .await?
        .into();

    // If mode filter is specified, rank by that mode
    if let Some(ref mode) = params.mode {
        let mode_column = match mode.to_lowercase().as_str() {
            "cw" => "qsos_cw",
            "data" => "qsos_data",
            "phone" => "qsos_phone",
            other => {
                return Err(AppError::Validation {
                    message: format!("Invalid mode '{}'. Must be cw, data, or phone.", other),
                });
            }
        };

        let row =
            db::get_activator_stats_by_mode(&pool, &callsign, mode_column, params.state.as_deref())
                .await?;

        match row {
            Some(r) => Ok(Json(DataResponse {
                data: ActivatorStatsResponse {
                    callsign: r.callsign,
                    activation_count: 0,
                    total_qsos: r.mode_qsos,
                    qsos_by_mode: QsosByMode {
                        cw: if mode_column == "qsos_cw" {
                            r.mode_qsos
                        } else {
                            0
                        },
                        data: if mode_column == "qsos_data" {
                            r.mode_qsos
                        } else {
                            0
                        },
                        phone: if mode_column == "qsos_phone" {
                            r.mode_qsos
                        } else {
                            0
                        },
                    },
                    rank: r.rank,
                    total_ranked: r.total_ranked,
                    state: params.state,
                    mode_filter: Some(mode.clone()),
                    freshness,
                },
            })),
            None => Ok(Json(DataResponse {
                data: ActivatorStatsResponse {
                    callsign,
                    activation_count: 0,
                    total_qsos: 0,
                    qsos_by_mode: QsosByMode {
                        cw: 0,
                        data: 0,
                        phone: 0,
                    },
                    rank: 0,
                    total_ranked: 0,
                    state: params.state,
                    mode_filter: Some(mode.clone()),
                    freshness,
                },
            })),
        }
    } else {
        let row = db::get_activator_stats(&pool, &callsign, params.state.as_deref()).await?;

        match row {
            Some(r) => Ok(Json(DataResponse {
                data: ActivatorStatsResponse {
                    callsign: r.callsign,
                    activation_count: r.activation_count,
                    total_qsos: r.total_qsos,
                    qsos_by_mode: QsosByMode {
                        cw: r.total_cw,
                        data: r.total_data,
                        phone: r.total_phone,
                    },
                    rank: r.rank,
                    total_ranked: r.total_ranked,
                    state: params.state,
                    mode_filter: None,
                    freshness,
                },
            })),
            None => Ok(Json(DataResponse {
                data: ActivatorStatsResponse {
                    callsign,
                    activation_count: 0,
                    total_qsos: 0,
                    qsos_by_mode: QsosByMode {
                        cw: 0,
                        data: 0,
                        phone: 0,
                    },
                    rank: 0,
                    total_ranked: 0,
                    state: params.state,
                    mode_filter: None,
                    freshness,
                },
            })),
        }
    }
}

/// GET /v1/pota/stats/hunter?callsign=...&state=...
pub async fn get_hunter_stats(
    State(pool): State<PgPool>,
    Query(params): Query<HunterStatsQuery>,
) -> Result<Json<DataResponse<HunterStatsResponse>>, AppError> {
    let callsign = params.callsign.to_uppercase();

    let freshness: FreshnessInfo = db::get_activator_freshness(&pool, params.state.as_deref())
        .await?
        .into();

    let row = db::get_hunter_stats(&pool, &callsign, params.state.as_deref()).await?;

    match row {
        Some(r) => Ok(Json(DataResponse {
            data: HunterStatsResponse {
                callsign: r.callsign,
                total_qsos: r.total_qsos,
                rank: r.rank,
                total_ranked: r.total_ranked,
                state: params.state,
                freshness,
            },
        })),
        None => Ok(Json(DataResponse {
            data: HunterStatsResponse {
                callsign,
                total_qsos: 0,
                rank: 0,
                total_ranked: 0,
                state: params.state,
                freshness,
            },
        })),
    }
}

/// GET /v1/pota/stats/state/:state
pub async fn get_state_stats(
    State(pool): State<PgPool>,
    Path(state): Path<String>,
) -> Result<Json<DataResponse<StateStatsResponse>>, AppError> {
    let state = state.to_uppercase();

    let freshness: FreshnessInfo = db::get_state_freshness(&pool, &state).await?.into();

    let stats = db::get_state_stats(&pool, &state).await?;

    let (total_activations, unique_activators, total_qsos) = match stats {
        Some(s) => (s.total_activations, s.unique_activators, s.total_qsos),
        None => (0, 0, 0),
    };

    let top_activators: Vec<RankedCallsignResponse> =
        db::get_state_top_activators(&pool, &state, 10)
            .await?
            .into_iter()
            .map(Into::into)
            .collect();

    let top_hunters: Vec<RankedCallsignResponse> = db::get_state_top_hunters(&pool, &state, 10)
        .await?
        .into_iter()
        .map(Into::into)
        .collect();

    Ok(Json(DataResponse {
        data: StateStatsResponse {
            state,
            total_activations,
            unique_activators,
            total_qsos,
            top_activators,
            top_hunters,
            freshness,
        },
    }))
}

/// GET /v1/pota/stats/park/:reference
pub async fn get_park_stats(
    State(pool): State<PgPool>,
    Path(reference): Path<String>,
) -> Result<Json<DataResponse<ParkStatsResponse>>, AppError> {
    let reference = reference.to_uppercase();

    let park = db::get_park_detail(&pool, &reference)
        .await?
        .ok_or_else(|| AppError::ParkNotFound {
            reference: reference.clone(),
        })?;

    let freshness: FreshnessInfo = db::get_park_freshness(&pool, &reference).await?.into();

    let top_activators: Vec<RankedCallsignResponse> =
        db::get_park_top_activators(&pool, &reference, 10)
            .await?
            .into_iter()
            .map(Into::into)
            .collect();

    let top_hunters: Vec<RankedCallsignResponse> = db::get_park_top_hunters(&pool, &reference, 10)
        .await?
        .into_iter()
        .map(Into::into)
        .collect();

    Ok(Json(DataResponse {
        data: ParkStatsResponse {
            reference: park.reference,
            name: park.name,
            location_desc: park.location_desc,
            state: park.state,
            latitude: park.latitude,
            longitude: park.longitude,
            grid: park.grid,
            active: park.active,
            total_attempts: park.total_attempts,
            total_activations: park.total_activations,
            total_qsos: park.total_qsos,
            top_activators,
            top_hunters,
            freshness,
        },
    }))
}

/// GET /v1/pota/stats/rankings/activators?state=...&limit=...&offset=...
pub async fn get_activator_rankings(
    State(pool): State<PgPool>,
    Query(params): Query<RankingsQuery>,
) -> Result<Json<DataResponse<ActivatorRankingsResponse>>, AppError> {
    let limit = params.limit.unwrap_or(25).clamp(1, 100);
    let offset = params.offset.unwrap_or(0).max(0);

    let freshness: FreshnessInfo = db::get_activator_freshness(&pool, params.state.as_deref())
        .await?
        .into();

    let (rows, total_ranked) =
        db::get_activator_rankings(&pool, params.state.as_deref(), limit, offset).await?;

    let rankings: Vec<ActivatorRankingEntry> = rows
        .into_iter()
        .map(|r| ActivatorRankingEntry {
            callsign: r.callsign,
            activation_count: r.activation_count,
            total_qsos: r.total_qsos,
            qsos_by_mode: QsosByMode {
                cw: r.total_cw,
                data: r.total_data,
                phone: r.total_phone,
            },
            rank: r.rank,
        })
        .collect();

    Ok(Json(DataResponse {
        data: ActivatorRankingsResponse {
            rankings,
            total_ranked,
            state: params.state,
            freshness,
        },
    }))
}

/// GET /v1/pota/stats/status
pub async fn get_sync_status(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<PotaSyncStatusResponse>>, AppError> {
    let freshness: FreshnessInfo = db::get_activator_freshness(&pool, None).await?.into();

    let parks_fetched = freshness.total_parks - freshness.parks_pending;
    let completion_percentage = if freshness.total_parks > 0 {
        parks_fetched * 100 / freshness.total_parks
    } else {
        0
    };

    Ok(Json(DataResponse {
        data: PotaSyncStatusResponse {
            total_parks: freshness.total_parks,
            parks_fetched,
            parks_pending: freshness.parks_pending,
            completion_percentage,
            oldest_fetch: freshness.oldest_fetch,
            newest_fetch: freshness.newest_fetch,
            warning: freshness.warning,
        },
    }))
}
