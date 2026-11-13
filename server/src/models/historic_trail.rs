use serde::{Deserialize, Serialize};

// --- Query params ---

#[derive(Debug, Deserialize)]
pub struct TrailsQuery {
    pub refs: Option<String>,
    pub bbox: Option<String>,
    pub limit: Option<i64>,
    pub simplify: Option<f64>,
}

// --- DB row types ---

#[derive(Debug, sqlx::FromRow)]
pub struct HistoricTrailRow {
    pub trail_reference: String,
    pub trail_name: String,
    pub designation: Option<String>,
    pub managing_agency: Option<String>,
    pub length_miles: Option<f64>,
    pub state: Option<String>,
    pub match_quality: String,
    pub source: String,
    pub geometry_json: Option<String>,
}

// --- API response types ---

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrailFeature {
    #[serde(rename = "type")]
    pub feature_type: &'static str,
    pub geometry: serde_json::Value,
    pub properties: TrailProperties,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrailProperties {
    pub reference: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub designation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub managing_agency: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub length_miles: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    pub match_quality: String,
    pub source: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrailsResponse {
    #[serde(rename = "type")]
    pub collection_type: &'static str,
    pub features: Vec<TrailFeature>,
    pub meta: TrailsMeta,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrailsMeta {
    pub matched: usize,
    pub unmatched_refs: Vec<String>,
}

// --- Status response ---

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrailStatusResponse {
    pub total_catalog: i64,
    pub total_cached: i64,
    pub unfetched: i64,
    pub completion_percentage: i64,
    pub exact_matches: i64,
    pub spatial_matches: i64,
    pub manual_matches: i64,
    pub oldest_fetch: Option<String>,
    pub newest_fetch: Option<String>,
}

// --- NPS ArcGIS API types ---

#[derive(Debug, Deserialize)]
pub struct NpsTrailResponse {
    pub features: Option<Vec<NpsTrailFeature>>,
}

#[derive(Debug, Deserialize)]
pub struct NpsTrailFeature {
    #[serde(alias = "attributes")]
    pub properties: Option<NpsTrailAttributes>,
    pub geometry: Option<serde_json::Value>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct NpsTrailAttributes {
    #[serde(
        alias = "Trail_Name",
        alias = "TRAIL_NAME",
        alias = "trailname",
        alias = "name"
    )]
    pub trail_name: Option<String>,
    #[serde(
        alias = "Mang_Agency",
        alias = "MANG_AGENCY",
        alias = "mangagency",
        alias = "primarytrailmaintainer"
    )]
    pub managing_agency: Option<String>,
    #[serde(
        alias = "Designation",
        alias = "DESIGNATION",
        alias = "designation",
        alias = "nationaltraildesignation"
    )]
    pub designation: Option<String>,
    #[serde(
        alias = "Length_MI",
        alias = "LENGTH_MI",
        alias = "Shape__Length",
        alias = "lengthmiles"
    )]
    pub length_miles: Option<f64>,
    #[serde(alias = "State", alias = "STATE", alias = "state")]
    pub state: Option<String>,
}
