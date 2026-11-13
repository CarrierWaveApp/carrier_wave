//! Reference-data download clients — the network half of the iOS External
//! Data screen: POTA parks / SOTA summits / WWFF directory CSVs
//! (`ReferenceCacheDiskIO.downloadAndSaveCSV`), the equipment catalog
//! (`EquipmentCatalogService`), the FCC amateur-callsign SQLite bundle
//! (`FCCLookupService`), and SOTA activation zones (`SOTAZonesCache`).
//!
//! Parsing lives in `cw_domain::reference_csv`; persistence in `cw-store`
//! (driven by `cw-ffi`'s `ReferenceDataApi`).

use std::time::Duration;

use reqwest::header::{ETAG, IF_NONE_MATCH, ACCEPT, AUTHORIZATION, USER_AGENT};
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};

use crate::http::{HttpError, USER_AGENT_VALUE};
use crate::Conditional;

/// POTA parks directory (unauthenticated CSV).
pub const POTA_PARKS_CSV_URL: &str = "https://pota.app/all_parks_ext.csv";

/// SOTA summits list (unauthenticated CSV, ~25 MB).
pub const SOTA_SUMMITS_CSV_URL: &str = "https://www.sotadata.org.uk/summitslist.csv";

/// WWFF directory (unauthenticated CSV; the server is slow — iOS runs it
/// with 120 s request / 300 s resource timeouts).
pub const WWFF_DIRECTORY_CSV_URL: &str = "https://wwff.co/wwff-data/wwff_directory.csv";

/// FCC bundle metadata (record count + SHA-256 + schema version).
pub const FCC_METADATA_URL: &str =
    "https://github.com/jsvana/fcc-uls-etl/releases/download/latest/amateur-callsigns.json";

/// FCC amateur-callsign SQLite database, gzip-compressed.
pub const FCC_DATABASE_URL: &str =
    "https://github.com/jsvana/fcc-uls-etl/releases/download/latest/amateur-callsigns.db.gz";

/// Fetch one reference CSV: sends the same Accept/User-Agent headers as the
/// Swift `ReferenceCacheDiskIO`, rejects HTML challenge pages, and
/// normalizes line endings to `\n`. `timeout` bounds the whole transfer
/// (the CSVs run tens of MB; WWFF's server is additionally slow).
pub async fn fetch_reference_csv(url: &str, timeout: Duration) -> Result<String, HttpError> {
    let client = reqwest::Client::builder().timeout(timeout).build()?;
    let response = client
        .get(url)
        .header(ACCEPT, "text/csv, text/plain, */*")
        .header(USER_AGENT, USER_AGENT_VALUE)
        .send()
        .await?;
    let status = response.status();
    let bytes = response.bytes().await?;
    if !status.is_success() {
        return Err(HttpError::Http {
            status: status.as_u16(),
            body: String::from_utf8_lossy(&bytes).into_owned(),
        });
    }
    let body = String::from_utf8(bytes.to_vec()).map_err(|_| HttpError::NotUtf8)?;
    if cw_domain::reference_csv::looks_like_html(&body) {
        return Err(HttpError::Parse("expected CSV, got an HTML page".into()));
    }
    Ok(body.replace("\r\n", "\n").replace('\r', "\n"))
}

// ---------------------------------------------------------------------------
// Equipment catalog
// ---------------------------------------------------------------------------

/// `GET /v1/equipment/catalog` response envelope.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EquipmentCatalogWire {
    #[serde(default)]
    pub version: i64,
    #[serde(default)]
    pub entries: Vec<EquipmentEntryWire>,
}

/// One catalog entry, matching the Swift `EquipmentAPIEntry` field set.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EquipmentEntryWire {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub manufacturer: Option<String>,
    #[serde(default)]
    pub category: Option<String>,
    #[serde(default)]
    pub bands: Vec<String>,
    #[serde(default)]
    pub modes: Vec<String>,
    #[serde(default)]
    pub max_power_watts: Option<f64>,
    #[serde(default)]
    pub portability: Option<String>,
    #[serde(default)]
    pub weight_grams: Option<f64>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub aliases: Vec<String>,
    #[serde(default)]
    pub image_url: Option<String>,
    #[serde(default)]
    pub antenna_connector: Option<String>,
    #[serde(default)]
    pub power_connector: Option<String>,
    #[serde(default)]
    pub key_jack: Option<String>,
    #[serde(default)]
    pub mic_jack: Option<String>,
}

/// Equipment catalog client (activities server).
#[derive(Debug, Clone)]
pub struct EquipmentCatalogClient {
    http: crate::http::HttpClient,
    base_url: String,
}

impl EquipmentCatalogClient {
    pub fn new(http: crate::http::HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    /// `GET /v1/equipment/catalog`, ETag-aware. `bearer` is the OAuth access
    /// token (the iOS path goes through the authenticated `ActivitiesClient`).
    pub async fn fetch_catalog(
        &self,
        etag: Option<&str>,
        bearer: Option<&str>,
    ) -> Result<Conditional<EquipmentCatalogWire>, HttpError> {
        let url = format!("{}/v1/equipment/catalog", self.base_url);
        let mut request = self.http.inner().get(&url);
        if let Some(tag) = etag {
            request = request.header(IF_NONE_MATCH, tag);
        }
        if let Some(token) = bearer {
            request = request.header(AUTHORIZATION, format!("Bearer {token}"));
        }
        let response = request.send().await?;
        let status = response.status();
        if status == StatusCode::NOT_MODIFIED {
            return Ok(Conditional::NotModified);
        }
        let new_etag = response
            .headers()
            .get(ETAG)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        let bytes = response.bytes().await?;
        if !status.is_success() {
            return Err(HttpError::Http {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        let catalog: EquipmentCatalogWire = serde_json::from_slice(&bytes)?;
        Ok(Conditional::Modified { data: catalog, etag: new_etag })
    }
}

// ---------------------------------------------------------------------------
// FCC amateur-callsign database
// ---------------------------------------------------------------------------

/// FCC bundle metadata sidecar (`amateur-callsigns.json`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FccMetadataWire {
    #[serde(default)]
    pub generated_at: Option<String>,
    #[serde(default)]
    pub record_count: i64,
    #[serde(default)]
    pub db_size_bytes: i64,
    pub db_sha256: String,
    #[serde(default = "default_schema_version")]
    pub schema_version: i64,
}

fn default_schema_version() -> i64 {
    1
}

/// FCC bundle client. The database download is large (tens of MB
/// compressed), so it uses its own long-timeout client.
#[derive(Debug, Clone)]
pub struct FccClient {
    http: crate::http::HttpClient,
}

impl FccClient {
    pub fn new(http: crate::http::HttpClient) -> Self {
        Self { http }
    }

    /// Fetch the metadata sidecar.
    pub async fn fetch_metadata(&self) -> Result<FccMetadataWire, HttpError> {
        let bytes = self.http.send_bytes(self.http.inner().get(FCC_METADATA_URL)).await?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    /// Download the gzip-compressed SQLite database. Returns the compressed
    /// bytes — the caller verifies the SHA-256 (computed over the compressed
    /// payload, matching iOS) and decompresses to disk.
    pub async fn download_database(&self) -> Result<Vec<u8>, HttpError> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(900))
            .user_agent(USER_AGENT_VALUE)
            .build()?;
        let response = client.get(FCC_DATABASE_URL).send().await?;
        let status = response.status();
        let bytes = response.bytes().await?;
        if !status.is_success() {
            return Err(HttpError::Http {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        Ok(bytes.to_vec())
    }
}

// ---------------------------------------------------------------------------
// SOTA activation zones
// ---------------------------------------------------------------------------

/// One summit sent to the zones endpoint.
#[derive(Debug, Clone, Serialize)]
pub struct SotaZoneInput {
    pub code: String,
    pub lat: f64,
    pub lon: f64,
    #[serde(rename = "altitudeM")]
    pub altitude_m: i64,
}

/// One resolved zone: the summit code, its altitude, and the raw GeoJSON
/// geometry (Polygon or MultiPolygon), kept verbatim for the host renderer.
#[derive(Debug, Clone)]
pub struct SotaZoneFeature {
    pub code: String,
    pub altitude_m: i64,
    pub geometry_geojson: String,
}

#[derive(Debug, Deserialize)]
struct ZoneFeatureCollection {
    #[serde(default)]
    features: Vec<serde_json::Value>,
}

/// SOTA activation-zone client (activities server). The server computes
/// zones lazily: summits absent from a response are *pending*, not errors.
#[derive(Debug, Clone)]
pub struct SotaZonesClient {
    http: crate::http::HttpClient,
    base_url: String,
}

impl SotaZonesClient {
    /// Summits per POST — iOS `SOTAZonesCache` chunk size.
    pub const CHUNK_SIZE: usize = 500;

    pub fn new(http: crate::http::HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    /// `POST /v1/sota/zones` for one chunk of summits. Malformed features
    /// are skipped (the Swift `SafeZoneFeature` behavior).
    pub async fn fetch_zones(
        &self,
        summits: &[SotaZoneInput],
    ) -> Result<Vec<SotaZoneFeature>, HttpError> {
        let url = format!("{}/v1/sota/zones", self.base_url);
        let body = serde_json::json!({ "summits": summits });
        // `/v1/sota/zones` is a read-only compute/enqueue query (POST only to
        // carry the summit-list body), so honor the server's 429 `Retry-After`
        // backoff instead of aborting a bulk refresh on the first rate-limit.
        let bytes =
            self.http.send_bytes_retrying(self.http.inner().post(&url).json(&body)).await?;
        let collection: ZoneFeatureCollection = serde_json::from_slice(&bytes)?;
        Ok(collection.features.iter().filter_map(parse_zone_feature).collect())
    }
}

fn parse_zone_feature(feature: &serde_json::Value) -> Option<SotaZoneFeature> {
    let properties = feature.get("properties")?;
    let code = properties.get("code")?.as_str()?.to_string();
    let altitude_m = properties.get("altitudeM").and_then(serde_json::Value::as_i64).unwrap_or(0);
    let geometry = feature.get("geometry")?;
    let kind = geometry.get("type")?.as_str()?;
    if kind != "Polygon" && kind != "MultiPolygon" {
        return None;
    }
    Some(SotaZoneFeature { code, altitude_m, geometry_geojson: geometry.to_string() })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zone_features_parse_and_skip_malformed() {
        let body = serde_json::json!({
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {"code": "W4C/CM-001", "altitudeM": 2037},
                    "geometry": {"type": "Polygon", "coordinates": [[[ -82.27, 35.76 ]]]}
                },
                {"type": "Feature", "properties": {"altitudeM": 1}, "geometry": null},
                {
                    "type": "Feature",
                    "properties": {"code": "W4C/CM-002"},
                    "geometry": {"type": "Point", "coordinates": [0, 0]}
                }
            ]
        });
        let collection: ZoneFeatureCollection = serde_json::from_value(body).unwrap();
        let zones: Vec<SotaZoneFeature> =
            collection.features.iter().filter_map(parse_zone_feature).collect();
        assert_eq!(zones.len(), 1);
        assert_eq!(zones[0].code, "W4C/CM-001");
        assert_eq!(zones[0].altitude_m, 2_037);
        assert!(zones[0].geometry_geojson.contains("Polygon"));
    }

    #[test]
    fn equipment_catalog_parses_partial_entries() {
        let body = r#"{"version": 3, "entries": [
            {"id": "ic-705", "name": "IC-705", "manufacturer": "Icom",
             "category": "transceiver", "bands": ["40m"], "modes": ["SSB"],
             "max_power_watts": 10.0, "portability": "portable"},
            {"id": "unknown", "name": "Mystery Box"}
        ]}"#;
        let catalog: EquipmentCatalogWire = serde_json::from_str(body).unwrap();
        assert_eq!(catalog.version, 3);
        assert_eq!(catalog.entries.len(), 2);
        assert_eq!(catalog.entries[0].manufacturer.as_deref(), Some("Icom"));
        assert!(catalog.entries[1].bands.is_empty());
    }

    #[test]
    fn fcc_metadata_defaults_schema_version() {
        let body = r#"{"record_count": 780000, "db_size_bytes": 250000000,
                       "db_sha256": "abc123"}"#;
        let metadata: FccMetadataWire = serde_json::from_str(body).unwrap();
        assert_eq!(metadata.schema_version, 1);
        assert_eq!(metadata.record_count, 780_000);
    }
}
