//! Carrier Wave activities-server **contest definitions** API.
//!
//! Mirrors `server/src/handlers/contests.rs` and the iOS
//! `ActivitiesClient+ContestDefinitions.swift` DTOs (camelCase JSON, every
//! endpoint wrapped in a `{ "data": … }` envelope). Both endpoints are
//! public — no bearer token.
//!
//! The full v0.3 contest body under `definition` is carried through as raw
//! JSON: the store caches it verbatim and `cw_domain::contest` owns parsing.

use chrono::{DateTime, Utc};
use serde::Deserialize;

use crate::http::{HttpClient, HttpError};

/// The `{ "data": … }` envelope every activities endpoint returns.
#[derive(Debug, Deserialize)]
struct DataResponse<T> {
    data: T,
}

/// One list entry from `GET /v1/contests` (`ContestDefinitionSummary`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContestSummaryWire {
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub sponsor_name: Option<String>,
    pub format_version: String,
    pub is_active: bool,
    pub updated_at: DateTime<Utc>,
}

/// The `GET /v1/contests/:id` wrapper: metadata alongside the full contest
/// body under `definition` (kept opaque here).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContestEnvelopeWire {
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub sponsor_name: Option<String>,
    pub sponsor_url: Option<String>,
    pub format_version: String,
    pub is_active: bool,
    pub updated_at: DateTime<Utc>,
    pub definition: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct ContestsListWire {
    contests: Vec<ContestSummaryWire>,
}

/// Async client for the activities-server contest-definition endpoints.
#[derive(Debug, Clone)]
pub struct ContestsClient {
    http: HttpClient,
    base_url: String,
}

impl ContestsClient {
    /// Build a client against `base_url`. A trailing slash is trimmed.
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        let base_url = base_url.into().trim_end_matches('/').to_string();
        Self { http, base_url }
    }

    /// `GET /v1/contests` — list all active contest definitions.
    pub async fn list_contests(&self) -> Result<Vec<ContestSummaryWire>, HttpError> {
        let url = format!("{}/v1/contests", self.base_url);
        let response: DataResponse<ContestsListWire> = self.http.get_json(&url).await?;
        Ok(response.data.contests)
    }

    /// `GET /v1/contests/:id` — fetch the full contest definition body.
    pub async fn get_contest(&self, id: &str) -> Result<ContestEnvelopeWire, HttpError> {
        let url = format!("{}/v1/contests/{id}", self.base_url);
        let response: DataResponse<ContestEnvelopeWire> = self.http.get_json(&url).await?;
        Ok(response.data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summary_decodes_from_server_shape() {
        let json = r#"
        { "data": { "contests": [
            { "id": "cwops-cwt", "name": "CWops Mini-CWT Test", "shortName": "CWT",
              "sponsorName": "CW Operators' Club", "formatVersion": "0.3.0",
              "isActive": true, "updatedAt": "2026-04-23T01:08:55.371358Z" }
        ] } }
        "#;
        let decoded: DataResponse<ContestsListWire> = serde_json::from_str(json).expect("decode");
        let contests = decoded.data.contests;
        assert_eq!(contests.len(), 1);
        assert_eq!(contests[0].id, "cwops-cwt");
        assert_eq!(contests[0].short_name.as_deref(), Some("CWT"));
        assert!(contests[0].is_active);
    }

    #[test]
    fn envelope_keeps_definition_opaque() {
        let json = r#"
        { "data": {
            "id": "cwops-cwt", "name": "CWops Mini-CWT Test", "shortName": "CWT",
            "sponsorName": "CW Operators' Club", "sponsorUrl": "https://cwops.org",
            "formatVersion": "0.3.0", "isActive": true,
            "updatedAt": "2026-04-23T01:08:55.371358Z",
            "definition": { "id": "cwops-cwt", "bands": ["40m"] }
        } }
        "#;
        let decoded: DataResponse<ContestEnvelopeWire> = serde_json::from_str(json).expect("decode");
        let envelope = decoded.data;
        assert_eq!(envelope.sponsor_url.as_deref(), Some("https://cwops.org"));
        assert_eq!(envelope.definition["bands"][0], "40m");
    }
}
