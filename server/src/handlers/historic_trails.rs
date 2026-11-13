use axum::extract::{Query, State};
use sqlx::PgPool;

use crate::db::historic_trails as db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::historic_trail::{
    HistoricTrailRow, TrailFeature, TrailProperties, TrailStatusResponse, TrailsMeta, TrailsQuery,
    TrailsResponse,
};

use super::DataResponse;

/// GET /v1/trails?refs=...&bbox=...&limit=...&simplify=...
pub async fn get_trails(
    State(pool): State<PgPool>,
    Query(params): Query<TrailsQuery>,
) -> Result<Json<TrailsResponse>, AppError> {
    let limit = params.limit.unwrap_or(50).clamp(1, 100);

    if params.refs.is_none() && params.bbox.is_none() {
        return Err(AppError::Validation {
            message: "Either 'refs' or 'bbox' parameter is required".to_string(),
        });
    }

    // refs query takes priority
    if let Some(ref refs_str) = params.refs {
        let refs: Vec<String> = refs_str
            .split(',')
            .map(|s| s.trim().to_uppercase())
            .filter(|s| !s.is_empty())
            .collect();

        if refs.len() > 20 {
            return Err(AppError::Validation {
                message: "Maximum 20 refs per request".to_string(),
            });
        }

        let rows = db::get_trails_by_refs(&pool, &refs).await?;
        let matched_refs: Vec<&str> = rows.iter().map(|r| r.trail_reference.as_str()).collect();
        let unmatched_refs: Vec<String> = refs
            .iter()
            .filter(|r| !matched_refs.contains(&r.as_str()))
            .cloned()
            .collect();

        let features = rows_to_features(rows);
        let matched = features.len();

        return Ok(Json(TrailsResponse {
            collection_type: "FeatureCollection",
            features,
            meta: TrailsMeta {
                matched,
                unmatched_refs,
            },
        }));
    }

    // bbox query
    if let Some(ref bbox_str) = params.bbox {
        let coords: Vec<f64> = bbox_str
            .split(',')
            .filter_map(|s| s.trim().parse().ok())
            .collect();

        if coords.len() != 4 {
            return Err(AppError::Validation {
                message: "bbox must be 'west,south,east,north' (4 numbers)".to_string(),
            });
        }

        let (west, south, east, north) = (coords[0], coords[1], coords[2], coords[3]);

        let rows = if let Some(tolerance) = params.simplify {
            db::get_trails_by_bbox_simplified(&pool, west, south, east, north, limit, tolerance)
                .await?
        } else {
            db::get_trails_by_bbox(&pool, west, south, east, north, limit).await?
        };

        let features = rows_to_features(rows);
        let matched = features.len();

        return Ok(Json(TrailsResponse {
            collection_type: "FeatureCollection",
            features,
            meta: TrailsMeta {
                matched,
                unmatched_refs: vec![],
            },
        }));
    }

    unreachable!()
}

/// GET /v1/trails/:reference
pub async fn get_trail(
    State(pool): State<PgPool>,
    Path(reference): Path<String>,
) -> Result<Json<TrailFeature>, AppError> {
    let reference = reference.to_uppercase();

    let row = db::get_trail_by_ref(&pool, &reference)
        .await?
        .ok_or_else(|| AppError::TrailNotFound {
            reference: reference.clone(),
        })?;

    let feature = row_to_feature(row).ok_or_else(|| AppError::TrailNotFound { reference })?;

    Ok(Json(feature))
}

/// GET /v1/trails/status
pub async fn get_trail_status(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<TrailStatusResponse>>, AppError> {
    let status = db::get_trail_status(&pool).await?;

    let unfetched = status.total_catalog - status.total_cached;
    let completion_percentage = if status.total_catalog > 0 {
        status.total_cached * 100 / status.total_catalog
    } else {
        0
    };

    Ok(Json(DataResponse {
        data: TrailStatusResponse {
            total_catalog: status.total_catalog,
            total_cached: status.total_cached,
            unfetched,
            completion_percentage,
            exact_matches: status.exact_matches,
            spatial_matches: status.spatial_matches,
            manual_matches: status.manual_matches,
            oldest_fetch: status.oldest_fetch.map(|t| t.to_rfc3339()),
            newest_fetch: status.newest_fetch.map(|t| t.to_rfc3339()),
        },
    }))
}

fn rows_to_features(rows: Vec<HistoricTrailRow>) -> Vec<TrailFeature> {
    rows.into_iter().filter_map(row_to_feature).collect()
}

fn row_to_feature(row: HistoricTrailRow) -> Option<TrailFeature> {
    let geometry_json = row.geometry_json?;
    let geometry: serde_json::Value = serde_json::from_str(&geometry_json).ok()?;

    Some(TrailFeature {
        feature_type: "Feature",
        geometry,
        properties: TrailProperties {
            reference: row.trail_reference,
            name: row.trail_name,
            designation: row.designation,
            managing_agency: row.managing_agency,
            length_miles: row.length_miles,
            state: row.state,
            match_quality: row.match_quality,
            source: row.source,
        },
    })
}
