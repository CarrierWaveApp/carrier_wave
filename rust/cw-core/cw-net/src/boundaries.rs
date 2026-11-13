//! Carrier Wave activities-server **GIS boundary** clients: park boundaries,
//! historic trails, and US administrative boundaries (states/counties).
//!
//! Ports the network halves of `ActivitiesClient+ParkBoundaries.swift`,
//! `ActivitiesClient+Trails.swift`, and `ActivitiesClient+AdminBoundaries.swift`.
//! Geometry is kept as raw GeoJSON (verbatim `serde_json::Value`, restringified)
//! rather than built into a full geometry object model — the downstream cache
//! stores it as-is and the map renderer decodes it. Feature decoding is
//! resilient: a malformed feature is skipped (the Swift `SafeFeature`/
//! `SafeAdminFeature` behavior), not fatal to the whole response. Unlike the
//! Swift `BoundariesResponse.toParkBoundaries()`, grouping here does NOT merge
//! intersecting rings — the server now pre-merges per reference.

use serde::Deserialize;

use crate::http::{HttpClient, HttpError};

/// A `west,south,east,north` viewport, shared by all three `by_bbox` queries
/// (matches the Swift clients' `west`/`south`/`east`/`north` parameter set).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BoundingBox {
    pub west: f64,
    pub south: f64,
    pub east: f64,
    pub north: f64,
}

impl BoundingBox {
    fn to_query_value(self) -> String {
        format!("{},{},{},{}", self.west, self.south, self.east, self.north)
    }
}

// ---------------------------------------------------------------------------
// Park boundaries
// ---------------------------------------------------------------------------

/// One park boundary feature's properties (`BoundaryProperties` in Swift).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ParkBoundaryProperties {
    reference: String,
    name: String,
    #[serde(default)]
    designation: Option<String>,
    #[serde(default)]
    manager: Option<String>,
    #[serde(default)]
    acreage: Option<f64>,
    match_quality: String,
    #[allow(dead_code)]
    #[serde(default)]
    source: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ParkBoundaryFeatureWire {
    geometry: serde_json::Value,
    properties: ParkBoundaryProperties,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ParkBoundariesMetaWire {
    matched: i64,
    #[serde(default)]
    unmatched_refs: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct ParkBoundariesResponseWire {
    #[serde(default)]
    features: Vec<serde_json::Value>,
    meta: ParkBoundariesMetaWire,
}

/// One park's polygon geometries grouped by reference, raw GeoJSON kept
/// verbatim per feature (no ring-merging — the server pre-merges).
#[derive(Debug, Clone)]
pub struct ParkBoundaryGroup {
    pub reference: String,
    pub name: String,
    pub designation: Option<String>,
    pub manager: Option<String>,
    pub acreage: Option<f64>,
    pub match_quality: String,
    /// One raw GeoJSON geometry string per feature sharing this reference.
    pub geometries_geojson: Vec<String>,
}

/// Summary metadata alongside the grouped boundaries.
#[derive(Debug, Clone)]
pub struct ParkBoundariesMeta {
    pub matched: i64,
    pub unmatched_refs: Vec<String>,
}

/// A single park boundary at full resolution (`GET /v1/parks/boundaries/{ref}`).
#[derive(Debug, Clone)]
pub struct ParkBoundaryFull {
    pub reference: String,
    pub name: String,
    pub designation: Option<String>,
    pub manager: Option<String>,
    pub acreage: Option<f64>,
    pub match_quality: String,
    pub geometry_geojson: String,
}

fn parse_park_feature(raw: &serde_json::Value) -> Option<ParkBoundaryFeatureWire> {
    serde_json::from_value(raw.clone()).ok()
}

fn group_park_features(features: &[serde_json::Value]) -> Vec<ParkBoundaryGroup> {
    let mut order: Vec<String> = Vec::new();
    let mut grouped: std::collections::HashMap<String, ParkBoundaryGroup> =
        std::collections::HashMap::new();

    for raw in features {
        let Some(feature) = parse_park_feature(raw) else {
            continue;
        };
        let reference = feature.properties.reference.clone();
        let geometry_geojson = feature.geometry.to_string();
        match grouped.get_mut(&reference) {
            Some(group) => group.geometries_geojson.push(geometry_geojson),
            None => {
                order.push(reference.clone());
                grouped.insert(
                    reference.clone(),
                    ParkBoundaryGroup {
                        reference,
                        name: feature.properties.name,
                        designation: feature.properties.designation,
                        manager: feature.properties.manager,
                        acreage: feature.properties.acreage,
                        match_quality: feature.properties.match_quality,
                        geometries_geojson: vec![geometry_geojson],
                    },
                );
            }
        }
    }

    order.into_iter().filter_map(|reference| grouped.remove(&reference)).collect()
}

/// Park boundaries client (activities server).
#[derive(Debug, Clone)]
pub struct ParkBoundariesClient {
    http: HttpClient,
    base_url: String,
}

impl ParkBoundariesClient {
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    /// `GET /v1/parks/boundaries?refs=...` — max 20 POTA references per the
    /// Swift client's doc comment; the server enforces the actual cap.
    pub async fn by_refs(
        &self,
        refs: &[String],
    ) -> Result<(Vec<ParkBoundaryGroup>, ParkBoundariesMeta), HttpError> {
        let url = format!("{}/v1/parks/boundaries", self.base_url);
        let request = self.http.inner().get(&url).query(&[("refs", refs.join(","))]);
        let bytes = self.http.send_bytes(request).await?;
        let response: ParkBoundariesResponseWire = serde_json::from_slice(&bytes)?;
        Ok((
            group_park_features(&response.features),
            ParkBoundariesMeta {
                matched: response.meta.matched,
                unmatched_refs: response.meta.unmatched_refs,
            },
        ))
    }

    /// `GET /v1/parks/boundaries?bbox=...&limit=...&simplify=...`.
    pub async fn by_bbox(
        &self,
        bbox: BoundingBox,
        limit: i64,
        simplify: Option<f64>,
    ) -> Result<(Vec<ParkBoundaryGroup>, ParkBoundariesMeta), HttpError> {
        let url = format!("{}/v1/parks/boundaries", self.base_url);
        let mut query = vec![
            ("bbox".to_string(), bbox.to_query_value()),
            ("limit".to_string(), limit.to_string()),
        ];
        if let Some(simplify) = simplify {
            query.push(("simplify".to_string(), simplify.to_string()));
        }
        let request = self.http.inner().get(&url).query(&query);
        let bytes = self.http.send_bytes(request).await?;
        let response: ParkBoundariesResponseWire = serde_json::from_slice(&bytes)?;
        Ok((
            group_park_features(&response.features),
            ParkBoundariesMeta {
                matched: response.meta.matched,
                unmatched_refs: response.meta.unmatched_refs,
            },
        ))
    }

    /// `GET /v1/parks/boundaries/{ref}` — single park, full-resolution geometry.
    pub async fn full_res(&self, reference: &str) -> Result<ParkBoundaryFull, HttpError> {
        let encoded = urlencoding_path_segment(reference);
        let url = format!("{}/v1/parks/boundaries/{}", self.base_url, encoded);
        let bytes = self.http.send_bytes(self.http.inner().get(&url)).await?;
        let feature: ParkBoundaryFeatureWire = serde_json::from_slice(&bytes)?;
        Ok(ParkBoundaryFull {
            reference: feature.properties.reference,
            name: feature.properties.name,
            designation: feature.properties.designation,
            manager: feature.properties.manager,
            acreage: feature.properties.acreage,
            match_quality: feature.properties.match_quality,
            geometry_geojson: feature.geometry.to_string(),
        })
    }
}

/// Percent-encode a single path segment the way Swift's
/// `.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` does for
/// our reference strings (letters/digits/`-`/`_`/`/`... kept simple: encode
/// anything not alphanumeric or in a small safe set).
fn urlencoding_path_segment(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char);
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Trails
// ---------------------------------------------------------------------------

/// One trail feature's properties (`TrailProperties` in Swift).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TrailProperties {
    reference: String,
    name: String,
    #[serde(default)]
    designation: Option<String>,
    #[serde(default)]
    managing_agency: Option<String>,
    #[serde(default)]
    length_miles: Option<f64>,
    #[serde(default)]
    state: Option<String>,
    match_quality: String,
    #[allow(dead_code)]
    #[serde(default)]
    source: Option<String>,
}

#[derive(Debug, Deserialize)]
struct TrailFeatureWire {
    geometry: serde_json::Value,
    properties: TrailProperties,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TrailsMetaWire {
    matched: i64,
    #[serde(default)]
    unmatched_refs: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct TrailsResponseWire {
    #[serde(default)]
    features: Vec<serde_json::Value>,
    meta: TrailsMetaWire,
}

/// One historic trail, raw GeoJSON geometry kept verbatim.
#[derive(Debug, Clone)]
pub struct TrailFeature {
    pub reference: String,
    pub name: String,
    pub designation: Option<String>,
    pub managing_agency: Option<String>,
    pub length_miles: Option<f64>,
    pub state: Option<String>,
    pub match_quality: String,
    pub geometry_geojson: String,
}

/// Summary metadata alongside the trail features.
#[derive(Debug, Clone)]
pub struct TrailsMeta {
    pub matched: i64,
    pub unmatched_refs: Vec<String>,
}

fn parse_trail_feature(raw: &serde_json::Value) -> Option<TrailFeature> {
    let feature: TrailFeatureWire = serde_json::from_value(raw.clone()).ok()?;
    Some(TrailFeature {
        reference: feature.properties.reference,
        name: feature.properties.name,
        designation: feature.properties.designation,
        managing_agency: feature.properties.managing_agency,
        length_miles: feature.properties.length_miles,
        state: feature.properties.state,
        match_quality: feature.properties.match_quality,
        geometry_geojson: feature.geometry.to_string(),
    })
}

/// Historic trails client (activities server).
#[derive(Debug, Clone)]
pub struct TrailsClient {
    http: HttpClient,
    base_url: String,
}

impl TrailsClient {
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    /// `GET /v1/trails?bbox=...&limit=...&simplify=...`. Malformed features
    /// are skipped rather than failing the whole response.
    pub async fn by_bbox(
        &self,
        bbox: BoundingBox,
        limit: i64,
        simplify: Option<f64>,
    ) -> Result<(Vec<TrailFeature>, TrailsMeta), HttpError> {
        let url = format!("{}/v1/trails", self.base_url);
        let mut query = vec![
            ("bbox".to_string(), bbox.to_query_value()),
            ("limit".to_string(), limit.to_string()),
        ];
        if let Some(simplify) = simplify {
            query.push(("simplify".to_string(), simplify.to_string()));
        }
        let request = self.http.inner().get(&url).query(&query);
        let bytes = self.http.send_bytes(request).await?;
        let response: TrailsResponseWire = serde_json::from_slice(&bytes)?;
        let features = response.features.iter().filter_map(parse_trail_feature).collect();
        Ok((
            features,
            TrailsMeta { matched: response.meta.matched, unmatched_refs: response.meta.unmatched_refs },
        ))
    }
}

// ---------------------------------------------------------------------------
// Admin boundaries (states/counties)
// ---------------------------------------------------------------------------

/// One admin boundary feature's properties (`AdminBoundaryProperties` in Swift).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AdminBoundaryProperties {
    id: String,
    kind: String,
    name: String,
    #[serde(default)]
    state_name: Option<String>,
    fips: String,
}

#[derive(Debug, Deserialize)]
struct AdminBoundaryFeatureWire {
    geometry: serde_json::Value,
    properties: AdminBoundaryProperties,
}

#[derive(Debug, Deserialize)]
struct AdminBoundariesResponseWire {
    #[serde(default)]
    features: Vec<serde_json::Value>,
}

/// `kind` filter for admin-boundary queries (`state` or `county`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdminBoundaryKind {
    State,
    County,
}

impl AdminBoundaryKind {
    fn as_query_value(self) -> &'static str {
        match self {
            AdminBoundaryKind::State => "state",
            AdminBoundaryKind::County => "county",
        }
    }
}

/// One US administrative boundary (state or county), raw GeoJSON geometry
/// kept verbatim.
#[derive(Debug, Clone)]
pub struct AdminBoundaryFeature {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub state_name: Option<String>,
    pub fips: String,
    pub geometry_geojson: String,
}

fn parse_admin_feature(raw: &serde_json::Value) -> Option<AdminBoundaryFeature> {
    let feature: AdminBoundaryFeatureWire = serde_json::from_value(raw.clone()).ok()?;
    Some(AdminBoundaryFeature {
        id: feature.properties.id,
        kind: feature.properties.kind,
        name: feature.properties.name,
        state_name: feature.properties.state_name,
        fips: feature.properties.fips,
        geometry_geojson: feature.geometry.to_string(),
    })
}

/// Admin boundaries client (activities server).
#[derive(Debug, Clone)]
pub struct AdminBoundariesClient {
    http: HttpClient,
    base_url: String,
}

impl AdminBoundariesClient {
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    /// `GET /v1/admin/boundaries?bbox=...&kind=...&limit=...&simplify=...`.
    /// `kind` of `None` returns both states and counties. Malformed features
    /// are skipped rather than failing the whole response.
    pub async fn by_bbox(
        &self,
        bbox: BoundingBox,
        kind: Option<AdminBoundaryKind>,
        limit: i64,
        simplify: Option<f64>,
    ) -> Result<Vec<AdminBoundaryFeature>, HttpError> {
        let url = format!("{}/v1/admin/boundaries", self.base_url);
        let mut query = vec![
            ("bbox".to_string(), bbox.to_query_value()),
            ("limit".to_string(), limit.to_string()),
        ];
        if let Some(kind) = kind {
            query.push(("kind".to_string(), kind.as_query_value().to_string()));
        }
        if let Some(simplify) = simplify {
            query.push(("simplify".to_string(), simplify.to_string()));
        }
        let request = self.http.inner().get(&url).query(&query);
        let bytes = self.http.send_bytes(request).await?;
        let response: AdminBoundariesResponseWire = serde_json::from_slice(&bytes)?;
        Ok(response.features.iter().filter_map(parse_admin_feature).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- Park boundaries -----------------------------------------------

    #[test]
    fn park_boundaries_group_by_reference_and_skip_malformed() {
        let body = serde_json::json!({
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {"type": "Polygon", "coordinates": [[[-82.27, 35.76], [-82.26, 35.76], [-82.26, 35.77], [-82.27, 35.76]]]},
                    "properties": {
                        "reference": "K-1234", "name": "Test Park", "designation": "State Park",
                        "manager": "State", "acreage": 100.5, "matchQuality": "exact", "source": "pota"
                    }
                },
                {
                    "type": "Feature",
                    "geometry": {"type": "Polygon", "coordinates": [[[-82.20, 35.70], [-82.19, 35.70], [-82.19, 35.71], [-82.20, 35.70]]]},
                    "properties": {
                        "reference": "K-1234", "name": "Test Park", "matchQuality": "exact"
                    }
                },
                {
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [0, 0]},
                    "properties": {"reference": "K-9999", "name": "Bad Park"}
                }
            ],
            "meta": {"matched": 1, "unmatchedRefs": []}
        });
        let response: ParkBoundariesResponseWire = serde_json::from_value(body).unwrap();
        let groups = group_park_features(&response.features);
        assert_eq!(groups.len(), 1, "malformed feature (missing matchQuality) must be skipped");
        assert_eq!(groups[0].reference, "K-1234");
        assert_eq!(groups[0].geometries_geojson.len(), 2, "same-ref features accumulate, unmerged");
        assert_eq!(groups[0].acreage, Some(100.5));
        assert_eq!(response.meta.matched, 1);
    }

    #[test]
    fn park_boundaries_empty_response() {
        let body = serde_json::json!({
            "type": "FeatureCollection",
            "features": [],
            "meta": {"matched": 0, "unmatchedRefs": ["K-0001"]}
        });
        let response: ParkBoundariesResponseWire = serde_json::from_value(body).unwrap();
        let groups = group_park_features(&response.features);
        assert!(groups.is_empty());
        assert_eq!(response.meta.unmatched_refs, vec!["K-0001".to_string()]);
    }

    #[test]
    fn park_boundary_full_res_parses_single_feature() {
        let body = serde_json::json!({
            "type": "Feature",
            "geometry": {"type": "MultiPolygon", "coordinates": [[[[-82.27, 35.76], [-82.26, 35.76], [-82.26, 35.77], [-82.27, 35.76]]]]},
            "properties": {
                "reference": "K-1234", "name": "Test Park", "matchQuality": "exact"
            }
        });
        let feature: ParkBoundaryFeatureWire = serde_json::from_value(body).unwrap();
        assert_eq!(feature.properties.reference, "K-1234");
        assert!(feature.geometry.to_string().contains("MultiPolygon"));
    }

    #[test]
    fn path_segment_percent_encodes_slash() {
        assert_eq!(urlencoding_path_segment("K-1234"), "K-1234");
        assert_eq!(urlencoding_path_segment("W4C/CM-001"), "W4C%2FCM-001");
    }

    // -- Trails -----------------------------------------------------------

    #[test]
    fn trails_parse_and_skip_malformed_feature() {
        let body = serde_json::json!({
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {"type": "LineString", "coordinates": [[-82.27, 35.76], [-82.26, 35.76]]},
                    "properties": {
                        "reference": "T-1", "name": "Test Trail", "designation": "National Historic Trail",
                        "managingAgency": "NPS", "lengthMiles": 12.5, "state": "NC",
                        "matchQuality": "exact", "source": "nps"
                    }
                },
                {
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [0, 0]},
                    "properties": {"reference": "T-2", "name": "Bad Trail"}
                }
            ],
            "meta": {"matched": 1, "unmatchedRefs": []}
        });
        let response: TrailsResponseWire = serde_json::from_value(body).unwrap();
        let features: Vec<TrailFeature> =
            response.features.iter().filter_map(parse_trail_feature).collect();
        assert_eq!(features.len(), 1);
        assert_eq!(features[0].reference, "T-1");
        assert_eq!(features[0].length_miles, Some(12.5));
        assert!(features[0].geometry_geojson.contains("LineString"));
    }

    #[test]
    fn trails_empty_response() {
        let body = serde_json::json!({
            "type": "FeatureCollection",
            "features": [],
            "meta": {"matched": 0, "unmatchedRefs": []}
        });
        let response: TrailsResponseWire = serde_json::from_value(body).unwrap();
        let features: Vec<TrailFeature> =
            response.features.iter().filter_map(parse_trail_feature).collect();
        assert!(features.is_empty());
    }

    // -- Admin boundaries ---------------------------------------------------

    #[test]
    fn admin_boundaries_parse_and_skip_malformed_feature() {
        let body = serde_json::json!({
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {"type": "Polygon", "coordinates": [[[-82.27, 35.76], [-82.26, 35.76], [-82.26, 35.77], [-82.27, 35.76]]]},
                    "properties": {
                        "id": "37", "kind": "state", "name": "North Carolina", "fips": "37"
                    }
                },
                {
                    "type": "Feature",
                    "geometry": {"type": "Polygon", "coordinates": [[[-82.20, 35.70], [-82.19, 35.70], [-82.19, 35.71], [-82.20, 35.70]]]},
                    "properties": {
                        "id": "37021", "kind": "county", "name": "Buncombe", "stateName": "North Carolina", "fips": "37021"
                    }
                },
                {
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [0, 0]},
                    "properties": {"id": "99", "kind": "state"}
                }
            ]
        });
        let response: AdminBoundariesResponseWire = serde_json::from_value(body).unwrap();
        let features: Vec<AdminBoundaryFeature> =
            response.features.iter().filter_map(parse_admin_feature).collect();
        assert_eq!(features.len(), 2, "malformed feature (missing name/fips) must be skipped");
        assert_eq!(features[0].kind, "state");
        assert_eq!(features[1].state_name.as_deref(), Some("North Carolina"));
    }

    #[test]
    fn admin_boundaries_empty_response() {
        let body = serde_json::json!({"type": "FeatureCollection", "features": []});
        let response: AdminBoundariesResponseWire = serde_json::from_value(body).unwrap();
        let features: Vec<AdminBoundaryFeature> =
            response.features.iter().filter_map(parse_admin_feature).collect();
        assert!(features.is_empty());
    }

    #[test]
    fn admin_boundary_kind_query_values() {
        assert_eq!(AdminBoundaryKind::State.as_query_value(), "state");
        assert_eq!(AdminBoundaryKind::County.as_query_value(), "county");
    }
}
