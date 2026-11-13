use sqlx::{PgPool, Postgres, QueryBuilder};

use crate::models::admin_boundary::AdminBoundaryRow;

/// Get US administrative boundaries (states and/or counties) intersecting a
/// bounding box, returning simplified geometry. An optional `kind` filter
/// ("state" or "county") and an optional extra `simplify` tolerance are applied
/// dynamically.
pub async fn get_by_bbox(
    pool: &PgPool,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
    kind: Option<&str>,
    limit: i64,
    simplify: Option<f64>,
) -> Result<Vec<AdminBoundaryRow>, sqlx::Error> {
    let mut qb: QueryBuilder<Postgres> =
        QueryBuilder::new("SELECT id, kind, name, state_name, fips, ");

    if let Some(tolerance) = simplify {
        qb.push("ST_AsGeoJSON(ST_Simplify(geometry_simplified, ");
        qb.push_bind(tolerance);
        qb.push(")) as geometry_json");
    } else {
        qb.push("ST_AsGeoJSON(geometry_simplified) as geometry_json");
    }

    qb.push(" FROM admin_boundaries WHERE geometry_simplified && ST_MakeEnvelope(");
    qb.push_bind(west)
        .push(", ")
        .push_bind(south)
        .push(", ")
        .push_bind(east)
        .push(", ")
        .push_bind(north)
        .push(", 4326)");

    if let Some(kind) = kind {
        qb.push(" AND kind = ").push_bind(kind.to_string());
    }

    qb.push(" ORDER BY kind, fips LIMIT ").push_bind(limit);

    qb.build_query_as::<AdminBoundaryRow>().fetch_all(pool).await
}
