//! Server callsign-enrichment dataset client.
//!
//! Faithful port of the dataset half of iOS
//! `ActivitiesClient+CallsignEnrichment`: an **unauthenticated**
//! `GET {base}/v1/callsign-enrichment/dataset`, ETag-conditional, whose body is
//! the dataset directly (no `{ data }` envelope). Membership rows use compact
//! single-char JSON keys (`s`/`n`/`#`/`e`/`t`).

use reqwest::header::{ETAG, IF_NONE_MATCH};
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};

use crate::http::{HttpClient, HttpError};
use crate::Conditional;

/// The full enrichment dataset (membership source catalog + per-callsign rows).
/// Round-trips via serde so the FFI can re-serialize it into its offline cache.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EnrichmentDataset {
    #[serde(default)]
    pub sources: Vec<EnrichmentSource>,
    #[serde(default)]
    pub callsigns: Vec<EnrichmentEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentSource {
    pub slug: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub emoji: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentEntry {
    #[serde(rename = "c")]
    pub callsign: String,
    #[serde(rename = "m", default)]
    pub memberships: Vec<EnrichmentMembership>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentMembership {
    #[serde(rename = "s")]
    pub source_slug: String,
    #[serde(rename = "n", default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(rename = "#", default, skip_serializing_if = "Option::is_none")]
    pub member_number: Option<String>,
    #[serde(rename = "e", default, skip_serializing_if = "Option::is_none")]
    pub emoji: Option<String>,
    #[serde(rename = "t", default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

/// Server enrichment-dataset client. Stateless beyond the base URL.
#[derive(Debug, Clone)]
pub struct EnrichmentClient {
    http: HttpClient,
    base_url: String,
}

impl EnrichmentClient {
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    /// `GET /v1/callsign-enrichment/dataset`, ETag-aware, unauthenticated.
    /// `304 Not Modified` is reported as [`Conditional::NotModified`].
    pub async fn fetch_dataset(
        &self,
        etag: Option<&str>,
    ) -> Result<Conditional<EnrichmentDataset>, HttpError> {
        let url = format!("{}/v1/callsign-enrichment/dataset", self.base_url);
        let mut request = self.http.inner().get(&url);
        if let Some(tag) = etag {
            request = request.header(IF_NONE_MATCH, tag);
        }
        let response = request.send().await?;
        let status = response.status();
        if status == StatusCode::NOT_MODIFIED {
            return Ok(Conditional::NotModified);
        }
        let new_etag = response
            .headers()
            .get(ETAG)
            .and_then(|val| val.to_str().ok())
            .map(str::to_string);
        let bytes = response.bytes().await?;
        if !status.is_success() {
            return Err(HttpError::Http {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        let dataset: EnrichmentDataset = serde_json::from_slice(&bytes)?;
        Ok(Conditional::Modified { data: dataset, etag: new_etag })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_compact_keys_and_round_trips() {
        let body = r##"{
            "sources": [{"slug":"cwops","name":"CWops","emoji":"🎹"}],
            "callsigns": [{"c":"W6JY","m":[{"s":"cwops","n":"Jay","#":"1532"}]}],
            "generated_at": "2026-06-29T00:00:00Z"
        }"##;
        let dataset: EnrichmentDataset = serde_json::from_str(body).expect("parse");
        assert_eq!(dataset.sources.len(), 1);
        assert_eq!(dataset.sources[0].emoji.as_deref(), Some("🎹"));
        let entry = &dataset.callsigns[0];
        assert_eq!(entry.callsign, "W6JY");
        assert_eq!(entry.memberships[0].source_slug, "cwops");
        assert_eq!(entry.memberships[0].member_number.as_deref(), Some("1532"));

        // Re-serialize → re-parse keeps the compact keys intact (offline cache).
        let raw = serde_json::to_string(&dataset).expect("serialize");
        let again: EnrichmentDataset = serde_json::from_str(&raw).expect("reparse");
        assert_eq!(again.callsigns[0].memberships[0].name.as_deref(), Some("Jay"));
    }
}
