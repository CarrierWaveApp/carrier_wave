use axum::extract::{Query, State};
use sqlx::PgPool;

use crate::db::admin_boundaries as db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::admin_boundary::{
    AdminBoundariesMeta, AdminBoundariesQuery, AdminBoundariesResponse, AdminBoundaryFeature,
    AdminBoundaryProperties, AdminBoundaryRow,
};

/// GET /v1/admin/boundaries?bbox=west,south,east,north&kind=state|county&limit=&simplify=
pub async fn get_admin_boundaries(
    State(pool): State<PgPool>,
    Query(params): Query<AdminBoundariesQuery>,
) -> Result<Json<AdminBoundariesResponse>, AppError> {
    let limit = params.limit.unwrap_or(500).clamp(1, 4000);

    let bbox_str = params.bbox.as_ref().ok_or_else(|| AppError::Validation {
        message: "'bbox' parameter is required".to_string(),
    })?;

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

    let kind = match params.kind.as_deref().map(str::trim) {
        None | Some("") => None,
        Some(value @ ("state" | "county")) => Some(value),
        Some(_) => {
            return Err(AppError::Validation {
                message: "kind must be 'state' or 'county'".to_string(),
            })
        }
    };

    let rows = db::get_by_bbox(&pool, west, south, east, north, kind, limit, params.simplify).await?;

    let features = rows_to_features(rows);
    let matched = features.len();

    Ok(Json(AdminBoundariesResponse {
        collection_type: "FeatureCollection",
        features,
        meta: AdminBoundariesMeta { matched },
    }))
}

fn rows_to_features(rows: Vec<AdminBoundaryRow>) -> Vec<AdminBoundaryFeature> {
    rows.into_iter().filter_map(row_to_feature).collect()
}

fn row_to_feature(row: AdminBoundaryRow) -> Option<AdminBoundaryFeature> {
    let geometry_json = row.geometry_json?;
    let geometry: serde_json::Value = serde_json::from_str(&geometry_json).ok()?;

    Some(AdminBoundaryFeature {
        feature_type: "Feature",
        geometry,
        properties: AdminBoundaryProperties {
            id: row.id,
            kind: row.kind,
            name: row.name,
            state_name: row.state_name,
            fips: row.fips,
        },
    })
}
