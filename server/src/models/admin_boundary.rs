use serde::{Deserialize, Serialize};

// --- Query params ---

#[derive(Debug, Deserialize)]
pub struct AdminBoundariesQuery {
    /// Required: "west,south,east,north".
    pub bbox: Option<String>,
    /// Optional filter: "state" or "county". Omitted returns both.
    pub kind: Option<String>,
    pub limit: Option<i64>,
    /// Optional Douglas-Peucker tolerance (degrees) for extra simplification.
    pub simplify: Option<f64>,
}

// --- DB row types ---

#[derive(Debug, sqlx::FromRow)]
pub struct AdminBoundaryRow {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub state_name: Option<String>,
    pub fips: String,
    pub geometry_json: Option<String>,
}

// --- API response types ---

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminBoundaryFeature {
    #[serde(rename = "type")]
    pub feature_type: &'static str,
    pub geometry: serde_json::Value,
    pub properties: AdminBoundaryProperties,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminBoundaryProperties {
    pub id: String,
    pub kind: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state_name: Option<String>,
    pub fips: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminBoundariesResponse {
    #[serde(rename = "type")]
    pub collection_type: &'static str,
    pub features: Vec<AdminBoundaryFeature>,
    pub meta: AdminBoundariesMeta,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminBoundariesMeta {
    pub matched: usize,
}
