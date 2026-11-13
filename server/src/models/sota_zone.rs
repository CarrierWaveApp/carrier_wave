use serde::{Deserialize, Serialize};

// --- Request ---

#[derive(Debug, Deserialize)]
pub struct SotaZonesRequest {
    pub summits: Vec<SotaSummitInput>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SotaSummitInput {
    pub code: String,
    pub lat: f64,
    pub lon: f64,
    #[serde(default)]
    pub altitude_m: Option<f64>,
}

// --- DB row ---

#[derive(Debug, sqlx::FromRow)]
pub struct SotaZoneRow {
    pub summit_code: String,
    pub altitude_m: Option<f64>,
    pub geometry_json: Option<String>,
}

// --- Response (GeoJSON FeatureCollection) ---

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SotaZonesResponse {
    #[serde(rename = "type")]
    pub collection_type: &'static str,
    pub features: Vec<SotaZoneFeature>,
    pub meta: SotaZonesMeta,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SotaZoneFeature {
    #[serde(rename = "type")]
    pub feature_type: &'static str,
    pub geometry: serde_json::Value,
    pub properties: SotaZoneProperties,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SotaZoneProperties {
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub altitude_m: Option<f64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SotaZonesMeta {
    pub matched: usize,
    /// Codes whose zones are being computed now — re-request shortly.
    pub pending: Vec<String>,
}
