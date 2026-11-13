use axum::extract::{Query, State};
use sqlx::PgPool;

use crate::db::park_boundaries as db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::park_boundary::{
    BoundariesMeta, BoundariesQuery, BoundariesResponse, BoundaryCountryStat, BoundaryCountryStats,
    BoundaryFeature, BoundaryProperties, BoundaryStatusResponse, ParkBoundaryRow,
};

use super::DataResponse;

/// GET /v1/parks/boundaries?refs=...&bbox=...&limit=...&simplify=...
pub async fn get_boundaries(
    State(pool): State<PgPool>,
    Query(params): Query<BoundariesQuery>,
) -> Result<Json<BoundariesResponse>, AppError> {
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

        let rows = db::get_boundaries_by_refs(&pool, &refs).await?;
        let matched_refs: Vec<&str> = rows.iter().map(|r| r.pota_reference.as_str()).collect();
        let unmatched_refs: Vec<String> = refs
            .iter()
            .filter(|r| !matched_refs.contains(&r.as_str()))
            .cloned()
            .collect();

        let features = rows_to_features(rows);
        let matched = features.len();

        return Ok(Json(BoundariesResponse {
            collection_type: "FeatureCollection",
            features,
            meta: BoundariesMeta {
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
            db::get_boundaries_by_bbox_simplified(&pool, west, south, east, north, limit, tolerance)
                .await?
        } else {
            db::get_boundaries_by_bbox(&pool, west, south, east, north, limit).await?
        };

        let features = rows_to_features(rows);
        let matched = features.len();

        return Ok(Json(BoundariesResponse {
            collection_type: "FeatureCollection",
            features,
            meta: BoundariesMeta {
                matched,
                unmatched_refs: vec![],
            },
        }));
    }

    unreachable!()
}

/// GET /v1/parks/boundaries/:reference
pub async fn get_boundary(
    State(pool): State<PgPool>,
    Path(reference): Path<String>,
) -> Result<Json<BoundaryFeature>, AppError> {
    let reference = reference.to_uppercase();

    let row = db::get_boundary_by_ref(&pool, &reference)
        .await?
        .ok_or_else(|| AppError::ParkNotFound {
            reference: reference.clone(),
        })?;

    let feature = row_to_feature(row).ok_or_else(|| AppError::ParkNotFound { reference })?;

    Ok(Json(feature))
}

fn rows_to_features(rows: Vec<ParkBoundaryRow>) -> Vec<BoundaryFeature> {
    rows.into_iter().filter_map(row_to_feature).collect()
}

fn row_to_feature(row: ParkBoundaryRow) -> Option<BoundaryFeature> {
    let geometry_json = row.geometry_json?;
    let geometry: serde_json::Value = serde_json::from_str(&geometry_json).ok()?;

    Some(BoundaryFeature {
        feature_type: "Feature",
        geometry,
        properties: BoundaryProperties {
            reference: row.pota_reference,
            name: row.park_name,
            designation: row.designation,
            manager: row.manager,
            acreage: row.acreage,
            match_quality: row.match_quality,
            source: row.source,
        },
    })
}

/// GET /v1/parks/boundaries/status
pub async fn get_boundary_status(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<BoundaryStatusResponse>>, AppError> {
    let status = db::get_boundary_status(&pool).await?;
    let source_counts = db::get_boundary_source_counts(&pool).await?;

    let by_source: std::collections::HashMap<String, i64> = source_counts
        .into_iter()
        .map(|sc| (sc.source, sc.count))
        .collect();

    let total_parks = status.total_us_parks
        + status.total_uk_parks
        + status.total_it_parks
        + status.total_pl_parks;
    let total_attempted = status.total_cached + status.no_match_count;
    let unfetched = total_parks - total_attempted;
    let completion_percentage = if total_parks > 0 {
        total_attempted * 100 / total_parks
    } else {
        0
    };

    Ok(Json(DataResponse {
        data: BoundaryStatusResponse {
            total_parks,
            total_cached: status.total_cached,
            unfetched,
            completion_percentage,
            by_country: BoundaryCountryStats {
                us: BoundaryCountryStat {
                    total_parks: status.total_us_parks,
                },
                uk: BoundaryCountryStat {
                    total_parks: status.total_uk_parks,
                },
                it: BoundaryCountryStat {
                    total_parks: status.total_it_parks,
                },
                pl: BoundaryCountryStat {
                    total_parks: status.total_pl_parks,
                },
            },
            by_source,
            exact_matches: status.exact_matches,
            spatial_matches: status.spatial_matches,
            manual_matches: status.manual_matches,
            no_matches: status.no_match_count,
            oldest_fetch: status.oldest_fetch.map(|t| t.to_rfc3339()),
            newest_fetch: status.newest_fetch.map(|t| t.to_rfc3339()),
        },
    }))
}
