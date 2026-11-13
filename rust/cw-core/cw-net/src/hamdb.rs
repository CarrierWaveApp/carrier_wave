//! HamDB.org callbook client.
//!
//! Faithful port of the iOS `HamDBClient`: a free US callbook used as a
//! fill-nil fallback for name / grid / QTH / state / country / license-class
//! when QRZ has no answer. HamDB returns HTTP 200 with
//! `hamdb.messages.status == "NOT_FOUND"` on a miss, so a miss is detected from
//! the body, not the status code.

use serde::Deserialize;

use crate::http::{HttpClient, HttpError};

const HAMDB_BASE_URL: &str = "https://api.hamdb.org/v1";

/// The enrichment-relevant subset of a HamDB license record.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct HamdbLookup {
    pub call: String,
    /// "First Last" — whichever parts are present.
    pub name: Option<String>,
    pub grid: Option<String>,
    /// City (HamDB `city`).
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    /// Human license class ("Extra" / "General" / "Technician").
    pub license_class: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

#[derive(Deserialize)]
struct HamdbResponse {
    hamdb: HamdbData,
}

#[derive(Deserialize)]
struct HamdbData {
    callsign: HamdbLicense,
    messages: Option<HamdbMessages>,
}

#[derive(Deserialize)]
struct HamdbMessages {
    status: Option<String>,
}

#[derive(Deserialize)]
struct HamdbLicense {
    call: Option<String>,
    class: Option<String>,
    fname: Option<String>,
    name: Option<String>,
    city: Option<String>,
    state: Option<String>,
    country: Option<String>,
    grid: Option<String>,
    lat: Option<String>,
    lon: Option<String>,
}

/// HamDB callbook client. Stateless — build one per `HttpClient`.
#[derive(Debug, Clone)]
pub struct HamdbClient {
    http: HttpClient,
    base_url: String,
}

impl HamdbClient {
    pub fn new(http: HttpClient) -> Self {
        Self { http, base_url: HAMDB_BASE_URL.to_string() }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into().trim_end_matches('/').to_string();
        self
    }

    /// Look `callsign` up. `Ok(None)` for an empty input, a `NOT_FOUND` body, or
    /// a record with no usable name / grid / QTH (matching the iOS guard).
    pub async fn lookup(&self, callsign: &str) -> Result<Option<HamdbLookup>, HttpError> {
        let call = callsign.trim().to_uppercase();
        if call.is_empty() {
            return Ok(None);
        }
        let url = format!("{}/{}/json/CarrierWave", self.base_url, call);
        let resp: HamdbResponse = self.http.get_json(&url).await?;

        if resp.hamdb.messages.and_then(|msgs| msgs.status).as_deref() == Some("NOT_FOUND") {
            return Ok(None);
        }

        let lic = resp.hamdb.callsign;
        let result = HamdbLookup {
            call: nonempty(lic.call).unwrap_or(call),
            name: full_name(lic.fname, lic.name),
            grid: nonempty(lic.grid),
            qth: nonempty(lic.city),
            state: nonempty(lic.state),
            country: nonempty(lic.country),
            license_class: lic.class.as_deref().and_then(license_class),
            lat: nonempty(lic.lat).and_then(|v| v.parse::<f64>().ok()),
            lon: nonempty(lic.lon).and_then(|v| v.parse::<f64>().ok()),
        };

        if result.name.is_none() && result.grid.is_none() && result.qth.is_none() {
            return Ok(None);
        }
        Ok(Some(result))
    }
}

/// Trim, returning `None` for an empty or `NOT_FOUND` placeholder value.
fn nonempty(value: Option<String>) -> Option<String> {
    let trimmed = value?.trim().to_string();
    if trimmed.is_empty() || trimmed == "NOT_FOUND" {
        None
    } else {
        Some(trimmed)
    }
}

/// "First Last" / "First" / "Last" from the HamDB name parts.
fn full_name(fname: Option<String>, last: Option<String>) -> Option<String> {
    match (nonempty(fname), nonempty(last)) {
        (Some(first), Some(last)) => Some(format!("{first} {last}")),
        (Some(first), None) => Some(first),
        (None, Some(last)) => Some(last),
        (None, None) => None,
    }
}

/// Map the single-letter HamDB class to a human label (port of
/// `HamDBLicense.parsedLicenseClass`). `A`/`N` are grandfathered classes.
fn license_class(code: &str) -> Option<String> {
    match code.trim().to_uppercase().as_str() {
        "E" | "A" => Some("Extra".to_string()),
        "G" => Some("General".to_string()),
        "T" | "N" => Some("Technician".to_string()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(body: &str) -> Option<HamdbLookup> {
        let resp: HamdbResponse = serde_json::from_str(body).expect("valid json");
        if resp.hamdb.messages.and_then(|m| m.status).as_deref() == Some("NOT_FOUND") {
            return None;
        }
        let lic = resp.hamdb.callsign;
        let result = HamdbLookup {
            call: nonempty(lic.call).unwrap_or_default(),
            name: full_name(lic.fname, lic.name),
            grid: nonempty(lic.grid),
            qth: nonempty(lic.city),
            state: nonempty(lic.state),
            country: nonempty(lic.country),
            license_class: lic.class.as_deref().and_then(license_class),
            lat: nonempty(lic.lat).and_then(|v| v.parse::<f64>().ok()),
            lon: nonempty(lic.lon).and_then(|v| v.parse::<f64>().ok()),
        };
        if result.name.is_none() && result.grid.is_none() && result.qth.is_none() {
            return None;
        }
        Some(result)
    }

    #[test]
    fn parses_full_record() {
        let body = r#"{"hamdb":{"version":"1.0","callsign":{"call":"W1AW","class":"E",
            "fname":"Hiram","name":"Maxim","city":"Newington","state":"CT",
            "country":"United States","grid":"FN31pr","lat":"41.714775",
            "lon":"-72.727260"},"messages":{"status":"OK"}}}"#;
        let found = parse(body).expect("record");
        assert_eq!(found.call, "W1AW");
        assert_eq!(found.name.as_deref(), Some("Hiram Maxim"));
        assert_eq!(found.qth.as_deref(), Some("Newington"));
        assert_eq!(found.state.as_deref(), Some("CT"));
        assert_eq!(found.grid.as_deref(), Some("FN31pr"));
        assert_eq!(found.license_class.as_deref(), Some("Extra"));
        assert_eq!(found.lat, Some(41.714775));
        assert_eq!(found.lon, Some(-72.727260));
    }

    #[test]
    fn not_found_status_is_none() {
        let body = r#"{"hamdb":{"version":"1.0","callsign":{"call":"NOT_FOUND",
            "class":"NOT_FOUND","fname":"NOT_FOUND","name":"NOT_FOUND",
            "grid":"NOT_FOUND","lat":"NOT_FOUND","lon":"NOT_FOUND"},
            "messages":{"status":"NOT_FOUND"}}}"#;
        assert!(parse(body).is_none());
    }

    #[test]
    fn empty_record_is_none() {
        let body = r#"{"hamdb":{"callsign":{"call":"K1ABC"},"messages":{"status":"OK"}}}"#;
        assert!(parse(body).is_none(), "no name/grid/qth → not a hit");
    }
}
