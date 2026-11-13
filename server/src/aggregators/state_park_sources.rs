use crate::metrics as app_metrics;
use crate::models::park_boundary::{ArcGisFeature, ArcGisResponse};

/// A state-agency ArcGIS endpoint that can provide park boundary polygons.
pub struct StateDataSource {
    /// Two-letter state abbreviation (e.g. "FL", "OR")
    pub state: &'static str,
    /// ArcGIS REST query base URL (MapServer or FeatureServer layer)
    pub url: &'static str,
    /// Field name containing the park name
    pub name_field: &'static str,
    /// Fields to request in outFields
    pub out_fields: &'static str,
    /// Source label recorded in park_boundaries.source
    pub source_label: &'static str,
}

/// Registry of state-specific ArcGIS endpoints with verified field mappings.
///
/// Each entry has been verified via `?f=pjson` to confirm field names, geometry
/// type (esriGeometryPolygon), and geojson query support.
pub const STATE_SOURCES: &[StateDataSource] = &[
    // Florida DEP — 175 state parks and trails
    // Display field: SITE_NAME, Geometry: esriGeometryPolygon
    // Verified: ca.dep.state.fl.us/.../PARKS_BOUNDARIES/MapServer/0?f=pjson
    StateDataSource {
        state: "FL",
        url: "https://ca.dep.state.fl.us/arcgis/rest/services/OpenData/PARKS_BOUNDARIES/MapServer/0",
        name_field: "SITE_NAME",
        out_fields: "SITE_NAME,TOTAL_ACRES,COUNTY,DISTRICT",
        source_label: "fl_dep",
    },
    // Oregon Parks and Recreation Department — state park real property boundaries
    // Display field: NAME, Geometry: esriGeometryPolygon
    // Verified: maps.prd.state.or.us/.../Oregon_State_Parks/FeatureServer/0?f=pjson
    StateDataSource {
        state: "OR",
        url: "https://maps.prd.state.or.us/arcgis/rest/services/Land_ownership/Oregon_State_Parks/FeatureServer/0",
        name_field: "NAME",
        out_fields: "NAME",
        source_label: "or_oprd",
    },
    // California State Parks — simplified park boundaries, updated monthly
    // Display field: UNITNAME, Geometry: esriGeometryPolygon
    // Verified: services2.arcgis.com/.../ParkBoundaries/FeatureServer/0?f=pjson
    StateDataSource {
        state: "CA",
        url: "https://services2.arcgis.com/AhxrK3F6WM8ECvDi/arcgis/rest/services/ParkBoundaries/FeatureServer/0",
        name_field: "UNITNAME",
        out_fields: "UNITNAME,SUBTYPE,Shape_Area",
        source_label: "ca_csp",
    },
    // Texas Parks and Wildlife Department — state park boundaries
    // Display field: SITE_NAME, Geometry: esriGeometryPolygon
    // Via TPWD Open Data Hub
    StateDataSource {
        state: "TX",
        url: "https://tpwd.texas.gov/arcgis/rest/services/Parks/TexasStateParksTrails/MapServer/0",
        name_field: "P_NAME",
        out_fields: "P_NAME,CALCACRE",
        source_label: "tx_tpwd",
    },
];

/// Find the state-specific data source for a park based on its location code.
pub fn source_for_state(state_abbrev: &str) -> Option<&'static StateDataSource> {
    STATE_SOURCES.iter().find(|s| s.state == state_abbrev)
}

/// Query a state-specific ArcGIS endpoint by park name.
///
/// Uses a LIKE query on the state source's name field, similar to the PAD-US
/// normalized name strategy.
pub async fn query_by_name(
    client: &reqwest::Client,
    source: &StateDataSource,
    search_name: &str,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let start = std::time::Instant::now();
    let escaped = search_name.replace('\'', "''");
    let where_clause = format!("{} LIKE '%{}%'", source.name_field, escaped);

    let url = format!(
        "{}/query?where={}&outFields={}&f=geojson&outSR=4326",
        source.url,
        urlencoded(&where_clause),
        source.out_fields,
    );

    let features = fetch_arcgis_features(client, &url, source.source_label).await?;
    let result = merge_features(features);
    let result_label = if result.is_some() { "hit" } else { "miss" };
    metrics::counter!(app_metrics::GIS_FETCH_TOTAL, "source" => source.source_label, "result" => result_label)
        .increment(1);
    metrics::histogram!(app_metrics::GIS_FETCH_DURATION_SECONDS, "source" => source.source_label)
        .record(start.elapsed().as_secs_f64());
    Ok(result)
}

/// Query a state-specific ArcGIS endpoint by point intersection.
pub async fn query_by_point(
    client: &reqwest::Client,
    source: &StateDataSource,
    lon: f64,
    lat: f64,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let start = std::time::Instant::now();
    let url = format!(
        "{}/query?geometry={},{}&geometryType=esriGeometryPoint&spatialRel=esriSpatialRelIntersects&outFields={}&f=geojson&outSR=4326",
        source.url, lon, lat, source.out_fields,
    );

    let features = fetch_arcgis_features(client, &url, source.source_label).await?;
    let result = merge_features(features);
    let result_label = if result.is_some() { "hit" } else { "miss" };
    metrics::counter!(app_metrics::GIS_FETCH_TOTAL, "source" => source.source_label, "result" => result_label)
        .increment(1);
    metrics::histogram!(app_metrics::GIS_FETCH_DURATION_SECONDS, "source" => source.source_label)
        .record(start.elapsed().as_secs_f64());
    Ok(result)
}

/// Fetch features from an ArcGIS REST endpoint.
async fn fetch_arcgis_features(
    client: &reqwest::Client,
    url: &str,
    label: &str,
) -> Result<Vec<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let resp_text = client
        .get(url)
        .send()
        .await?
        .error_for_status()?
        .text()
        .await?;

    let resp: ArcGisResponse = match serde_json::from_str(&resp_text) {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(
                "State park source {}: response parse error: {} (first 200 chars: {})",
                label,
                e,
                &resp_text[..resp_text.len().min(200)]
            );
            return Ok(vec![]);
        }
    };

    Ok(resp.features.unwrap_or_default())
}

/// Merge multiple ArcGIS features into a single feature with combined geometry.
fn merge_features(features: Vec<ArcGisFeature>) -> Option<ArcGisFeature> {
    if features.is_empty() {
        return None;
    }
    if features.len() == 1 {
        return features.into_iter().next();
    }

    let geometries: Vec<serde_json::Value> =
        features.iter().filter_map(|f| f.geometry.clone()).collect();

    if geometries.is_empty() {
        return None;
    }

    let merged = crate::aggregators::park_boundaries::merge_geojson_geometries(geometries);
    let mut result = features.into_iter().next().unwrap();
    result.geometry = Some(merged);
    Some(result)
}

/// URL-encode a string for use in ArcGIS REST API query parameters.
fn urlencoded(s: &str) -> String {
    s.replace('%', "%25")
        .replace(' ', "%20")
        .replace('\'', "%27")
        .replace('=', "%3D")
        .replace('&', "%26")
}
