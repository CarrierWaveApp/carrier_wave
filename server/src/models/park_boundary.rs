use serde::{Deserialize, Serialize};

// --- Query params ---

#[derive(Debug, Deserialize)]
pub struct BoundariesQuery {
    pub refs: Option<String>,
    pub bbox: Option<String>,
    pub limit: Option<i64>,
    pub simplify: Option<f64>,
}

// --- DB row types ---

#[derive(Debug, sqlx::FromRow)]
pub struct ParkBoundaryRow {
    pub pota_reference: String,
    pub park_name: String,
    pub designation: Option<String>,
    pub manager: Option<String>,
    pub acreage: Option<f64>,
    pub match_quality: String,
    pub source: String,
    pub geometry_json: Option<String>,
}

// --- API response types ---

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundaryFeature {
    #[serde(rename = "type")]
    pub feature_type: &'static str,
    pub geometry: serde_json::Value,
    pub properties: BoundaryProperties,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundaryProperties {
    pub reference: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub designation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manager: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub acreage: Option<f64>,
    pub match_quality: String,
    pub source: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundariesResponse {
    #[serde(rename = "type")]
    pub collection_type: &'static str,
    pub features: Vec<BoundaryFeature>,
    pub meta: BoundariesMeta,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundariesMeta {
    pub matched: usize,
    pub unmatched_refs: Vec<String>,
}

// --- Status response ---

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundaryStatusResponse {
    pub total_parks: i64,
    pub total_cached: i64,
    pub unfetched: i64,
    pub completion_percentage: i64,
    pub by_country: BoundaryCountryStats,
    pub by_source: std::collections::HashMap<String, i64>,
    pub exact_matches: i64,
    pub spatial_matches: i64,
    pub manual_matches: i64,
    pub no_matches: i64,
    pub oldest_fetch: Option<String>,
    pub newest_fetch: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundaryCountryStats {
    pub us: BoundaryCountryStat,
    pub uk: BoundaryCountryStat,
    pub it: BoundaryCountryStat,
    pub pl: BoundaryCountryStat,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundaryCountryStat {
    pub total_parks: i64,
}

// --- WFS API types (GDOŚ Poland) ---

#[derive(Debug, Deserialize)]
pub struct WfsFeatureCollection {
    pub features: Option<Vec<WfsFeature>>,
}

#[derive(Debug, Deserialize)]
pub struct WfsFeature {
    pub properties: Option<WfsProperties>,
    pub geometry: Option<serde_json::Value>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct WfsProperties {
    /// Name of the protected area
    #[serde(alias = "nazwa")]
    pub nazwa: Option<String>,
    /// Area in hectares
    #[serde(alias = "powierzchnia", alias = "pow_ha")]
    pub area_ha: Option<f64>,
    /// INSPIRE ID or local identifier
    #[serde(alias = "inspireid", alias = "id_iip")]
    pub inspire_id: Option<String>,
}

// --- ArcGIS API types ---

#[derive(Debug, Deserialize)]
pub struct ArcGisResponse {
    pub features: Option<Vec<ArcGisFeature>>,
}

#[derive(Debug, Deserialize)]
pub struct ArcGisFeature {
    #[serde(alias = "attributes")]
    pub properties: Option<ArcGisAttributes>,
    pub geometry: Option<serde_json::Value>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ArcGisAttributes {
    // PAD-US fields
    #[serde(alias = "Loc_Nm")]
    pub loc_nm: Option<String>,
    #[serde(alias = "Unit_Nm")]
    pub unit_nm: Option<String>,
    #[serde(alias = "Mang_Name")]
    pub mang_name: Option<String>,
    #[serde(alias = "Des_Tp")]
    pub des_tp: Option<String>,
    #[serde(alias = "GIS_Acres")]
    pub gis_acres: Option<f64>,
    #[serde(alias = "FeatClass")]
    pub feat_class: Option<String>,

    // Natural England fields
    #[serde(alias = "NAME")]
    pub name: Option<String>,
    #[serde(alias = "AREA_HA")]
    pub area_ha: Option<f64>,

    // WDPA fields
    #[serde(alias = "DESIG_ENG")]
    pub desig_eng: Option<String>,
    #[serde(alias = "DESIG")]
    pub desig: Option<String>,
    #[serde(alias = "IUCN_CAT")]
    pub iucn_cat: Option<String>,
    #[serde(alias = "REP_AREA")]
    pub rep_area: Option<f64>,
    #[serde(alias = "ISO3")]
    pub iso3: Option<String>,
}
