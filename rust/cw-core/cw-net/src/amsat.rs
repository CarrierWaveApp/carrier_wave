//! AMSAT community-status client against the activities server's
//! `/v1/satellites/amsat-status` aggregate and its `/activity` histogram.
//! Port of the network half of `AmsatStatusService.swift` (`capabilityTag`/
//! `freshest` live in `cw_domain::satellite::amsat`). Unlike the Swift
//! client this one returns errors — the "enrichment, never load-bearing,
//! empty on failure" posture is applied by the caller
//! (`cw-ffi::satellite_api`).
//!
//! Reads go through our server (one poller is politer than a fleet of
//! phones); the one write — filing a status report — goes straight to
//! AMSAT's own API ([`AmsatSubmitClient`]), since it's the operator's own
//! observation under their own callsign.

use chrono::{DateTime, Utc};
use reqwest::header::USER_AGENT;
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::http::{HttpClient, HttpError};
use cw_domain::satellite::amsat::{ActivityBucket, AmsatReport, AmsatStatus, ReportKind};

/// AMSAT's status API — where a report is filed. The old
/// `www.amsat.org/status` host redirects here after 2026-11-04, but a
/// redirected POST turns into a GET, so the client must target this host.
pub const AMSAT_STATUS_API_BASE: &str = "https://status.amsat.org/api/v1";
/// Attribution AMSAT asks for wherever its report data is shown (CC BY 4.0).
pub const AMSAT_ATTRIBUTION: &str = "Satellite status data: AMSAT, https://status.amsat.org";
/// AMSAT's API guidelines ask clients to identify themselves with a name,
/// version, URL and contact — generic agents may be rate-limited or blocked.
const AMSAT_SUBMIT_USER_AGENT: &str = "CarrierWave/1.0 (+https://carrierwave.app; jaysvana@gmail.com)";
/// The verdicts `POST reports.php` accepts (`statuses.php`).
pub const AMSAT_REPORT_VALUES: [&str; 4] = ["Heard", "Telemetry Only", "Not Heard", "Crew Active"];

/// Wire row (camelCase, per `server/src/models/amsat_status.rs`).
/// `Serialize` so the cw-store blob cache can persist rows verbatim.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatStatusRow {
    pub name: String,
    #[serde(default)]
    pub norad_id: Option<i64>,
    #[serde(default)]
    pub last_heard_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub last_reported_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub last_report: Option<String>,
    #[serde(default)]
    pub last_callsign: Option<String>,
    #[serde(default)]
    pub last_grid: Option<String>,
    #[serde(default)]
    pub heard_reports_24h: i32,
    #[serde(default)]
    pub total_reports_24h: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatStatusResponse {
    #[serde(default)]
    pub satellites: Vec<AmsatStatusRow>,
    #[serde(default)]
    pub updated_at: Option<DateTime<Utc>>,
}

impl From<&AmsatStatusRow> for AmsatStatus {
    fn from(row: &AmsatStatusRow) -> AmsatStatus {
        AmsatStatus {
            name: row.name.clone(),
            norad_id: row.norad_id.and_then(|id| u32::try_from(id).ok()),
            last_heard_at: row.last_heard_at,
            last_reported_at: row.last_reported_at,
            last_report: row.last_report.clone(),
            last_callsign: row.last_callsign.clone(),
            last_grid: row.last_grid.clone(),
            heard_reports_24h: row.heard_reports_24h,
            total_reports_24h: row.total_reports_24h,
        }
    }
}

/// One hour of one satellite's community reports (wire row of
/// `/v1/satellites/amsat-status/activity`, per
/// `server/src/models/amsat_status.rs`).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AmsatActivityBucketRow {
    pub start: DateTime<Utc>,
    #[serde(default)]
    pub heard: i32,
    #[serde(default)]
    pub not_heard: i32,
    #[serde(default)]
    pub telemetry: i32,
    #[serde(default)]
    pub crew: i32,
    #[serde(default)]
    pub other: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatActivitySatelliteRow {
    pub name: String,
    #[serde(default)]
    pub norad_id: Option<i64>,
    #[serde(default)]
    pub buckets: Vec<AmsatActivityBucketRow>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatActivityResponse {
    #[serde(default = "default_bucket_seconds")]
    pub bucket_seconds: i64,
    pub window_start: DateTime<Utc>,
    pub window_end: DateTime<Utc>,
    #[serde(default)]
    pub updated_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub satellites: Vec<AmsatActivitySatelliteRow>,
}

fn default_bucket_seconds() -> i64 {
    3_600
}

impl From<&AmsatActivityBucketRow> for ActivityBucket {
    fn from(row: &AmsatActivityBucketRow) -> ActivityBucket {
        ActivityBucket {
            start: row.start,
            heard: row.heard,
            not_heard: row.not_heard,
            telemetry: row.telemetry,
            crew: row.crew,
            other: row.other,
        }
    }
}

/// Wire row of `/v1/satellites/amsat-status/reports`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AmsatReportRow {
    pub name: String,
    pub reported_at: DateTime<Utc>,
    pub callsign: String,
    pub report: String,
    #[serde(default)]
    pub grid: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatReportsResponse {
    pub window_start: DateTime<Utc>,
    pub window_end: DateTime<Utc>,
    #[serde(default)]
    pub names: Vec<String>,
    #[serde(default)]
    pub reports: Vec<AmsatReportRow>,
}

impl From<&AmsatReportRow> for AmsatReport {
    fn from(row: &AmsatReportRow) -> AmsatReport {
        AmsatReport {
            name: row.name.clone(),
            time: row.reported_at,
            callsign: row.callsign.clone(),
            kind: ReportKind::classify(&row.report),
            grid: row.grid.clone(),
        }
    }
}

pub struct AmsatStatusClient {
    http: HttpClient,
    base_url: String,
}

impl AmsatStatusClient {
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    /// `GET /v1/satellites/amsat-status`, unauthenticated.
    pub async fn fetch_status(&self) -> Result<AmsatStatusResponse, HttpError> {
        let url = format!("{}/v1/satellites/amsat-status", self.base_url);
        self.http.get_json(&url).await
    }

    /// `GET /v1/satellites/amsat-status/reports?norad=N&hours=H` — raw
    /// reports for every AMSAT row mapped to the NORAD id, newest first.
    pub async fn fetch_reports(&self, norad_id: u32, hours: u32) -> Result<AmsatReportsResponse, HttpError> {
        let url = format!(
            "{}/v1/satellites/amsat-status/reports?norad={}&hours={}",
            self.base_url,
            norad_id,
            hours.clamp(1, 168)
        );
        self.http.get_json(&url).await
    }

    /// `GET /v1/satellites/amsat-status/activity?hours=N`, unauthenticated.
    /// The server clamps `hours` to 1–168.
    pub async fn fetch_activity(&self, hours: u32) -> Result<AmsatActivityResponse, HttpError> {
        let url = format!(
            "{}/v1/satellites/amsat-status/activity?hours={}",
            self.base_url,
            hours.clamp(1, 168)
        );
        self.http.get_json(&url).await
    }
}

// MARK: - Filing a report with AMSAT

/// Body of `POST /reports.php` (snake_case, per AMSAT's OpenAPI document).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct AmsatReportSubmission {
    /// AMSAT's API name for the transmitter, e.g. `SO-50_[FM]`.
    pub name: String,
    /// One of [`AMSAT_REPORT_VALUES`].
    pub report: String,
    pub callsign: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grid_square: Option<String>,
    /// When the observation was made (not when it's filed), `…T..:..:..Z`.
    pub reported_at: String,
}

impl AmsatReportSubmission {
    pub fn new(
        name: impl Into<String>,
        report: impl Into<String>,
        callsign: impl Into<String>,
        grid_square: Option<String>,
        reported_at: DateTime<Utc>,
    ) -> Self {
        let grid_square = grid_square
            .map(|grid| grid.trim().to_string())
            .filter(|grid| !grid.is_empty());
        AmsatReportSubmission {
            name: name.into(),
            report: report.into(),
            callsign: callsign.into().trim().to_ascii_uppercase(),
            grid_square,
            reported_at: reported_at.format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        }
    }
}

/// `data` of a 201 from `POST /reports.php`.
#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct AmsatSubmitReceipt {
    pub id: i64,
    pub name: String,
    /// AMSAT's hour-quantised stamp for the report (`hh:30Z`).
    pub reported_time: DateTime<Utc>,
    pub callsign: String,
    pub report: String,
    #[serde(default)]
    pub grid_square: Option<String>,
    /// Earlier reports by the same callsign for the same satellite, hour and
    /// 15-minute period that this one replaced.
    #[serde(default)]
    pub replaced_count: u32,
}

#[derive(Debug, Deserialize)]
struct AmsatSubmitEnvelope {
    data: AmsatSubmitReceipt,
}

/// AMSAT's error envelope: `{"error":{"code","message","status"}}`.
#[derive(Debug, Deserialize)]
struct AmsatErrorEnvelope {
    error: AmsatErrorBody,
}

#[derive(Debug, Deserialize)]
struct AmsatErrorBody {
    #[serde(default)]
    code: String,
    #[serde(default)]
    message: String,
}

#[derive(Debug, Error)]
pub enum AmsatSubmitError {
    /// AMSAT refused the report (422 validation, 404 unknown satellite…);
    /// `message` is their human-readable reason.
    #[error("{message}")]
    Rejected { status: u16, code: String, message: String },
    #[error(transparent)]
    Http(#[from] HttpError),
}

impl AmsatSubmitError {
    /// Turn a non-2xx into [`Rejected`](Self::Rejected) when the body is
    /// AMSAT's error envelope; anything else stays an HTTP error.
    fn classify(err: HttpError) -> Self {
        if let HttpError::Http { status, body } = &err {
            if let Ok(envelope) = serde_json::from_str::<AmsatErrorEnvelope>(body) {
                return AmsatSubmitError::Rejected {
                    status: *status,
                    code: envelope.error.code,
                    message: envelope.error.message,
                };
            }
        }
        AmsatSubmitError::Http(err)
    }
}

/// Files status reports with AMSAT (`POST /reports.php`, no auth). Only
/// ever called from an explicit operator action — AMSAT's guidelines forbid
/// automated or background submissions.
pub struct AmsatSubmitClient {
    http: HttpClient,
    base_url: String,
}

impl AmsatSubmitClient {
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        Self { http, base_url: base_url.into().trim_end_matches('/').to_string() }
    }

    pub async fn submit_report(
        &self,
        submission: &AmsatReportSubmission,
    ) -> Result<AmsatSubmitReceipt, AmsatSubmitError> {
        let url = format!("{}/reports.php", self.base_url);
        let request = self
            .http
            .inner()
            .post(&url)
            .header(USER_AGENT, AMSAT_SUBMIT_USER_AGENT)
            .json(submission);
        let bytes = self.http.send_bytes(request).await.map_err(AmsatSubmitError::classify)?;
        let envelope: AmsatSubmitEnvelope =
            serde_json::from_slice(&bytes).map_err(HttpError::from)?;
        Ok(envelope.data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn submission_serializes_to_amsat_shape() {
        let when = DateTime::parse_from_rfc3339("2026-10-31T13:42:07.250Z")
            .unwrap()
            .with_timezone(&Utc);
        let submission = AmsatReportSubmission::new(
            "SO-50_[FM]", "Heard", " w6jy ", Some("CM87".into()), when,
        );
        let json = serde_json::to_value(&submission).unwrap();
        assert_eq!(
            json,
            serde_json::json!({
                "name": "SO-50_[FM]", "report": "Heard", "callsign": "W6JY",
                "grid_square": "CM87", "reported_at": "2026-10-31T13:42:07Z"
            })
        );
        // No grid → key omitted (AMSAT validates an empty string as a grid).
        let bare = AmsatReportSubmission::new("SO-50_[FM]", "Not Heard", "W6JY", Some("  ".into()), when);
        assert!(serde_json::to_value(&bare).unwrap().get("grid_square").is_none());
    }

    #[test]
    fn decodes_submit_receipt_and_rejection() {
        let receipt: AmsatSubmitEnvelope = serde_json::from_str(
            r#"{"data":{"id":456,"name":"AO-91_[FM]","reported_time":"2026-05-23T08:30:00Z",
                "callsign":"N0CALL","report":"Heard","grid_square":"EM48","replaced_count":1},
                "links":{"satellite_reports":"https://status.amsat.org/api/v1/reports.php?name=AO-91_%5BFM%5D"}}"#,
        )
        .unwrap();
        assert_eq!(receipt.data.id, 456);
        assert_eq!(receipt.data.replaced_count, 1);
        assert_eq!(receipt.data.reported_time.to_rfc3339(), "2026-05-23T08:30:00+00:00");

        let rejected = AmsatSubmitError::classify(HttpError::Http {
            status: 422,
            body: r#"{"error":{"code":"invalid_callsign","message":"A valid amateur radio callsign is required.","status":422}}"#.into(),
        });
        match rejected {
            AmsatSubmitError::Rejected { status, code, message } => {
                assert_eq!(status, 422);
                assert_eq!(code, "invalid_callsign");
                assert_eq!(message, "A valid amateur radio callsign is required.");
            }
            other => panic!("expected Rejected, got {other:?}"),
        }
        // A non-envelope body (gateway error page) stays an HTTP error.
        assert!(matches!(
            AmsatSubmitError::classify(HttpError::Http { status: 502, body: "<html>".into() }),
            AmsatSubmitError::Http(_)
        ));
    }

    #[test]
    fn decodes_camel_case_wire_shape() {
        // Fractional and non-fractional timestamps both decode (RFC3339).
        let json = r#"{"satellites":[
            {"name":"SO-50_[FM]","noradId":27607,
             "lastHeardAt":"2026-09-20T10:00:00.123456Z",
             "lastReportedAt":"2026-09-20T10:05:00Z",
             "lastReport":"Heard","lastCallsign":"W6JY","lastGrid":"CM87",
             "heardReports24h":5,"totalReports24h":9},
            {"name":"AO-7_[B]"}
        ],"updatedAt":"2026-09-20T11:00:00Z"}"#;
        let response: AmsatStatusResponse = serde_json::from_str(json).expect("decodes");
        assert_eq!(response.satellites.len(), 2);
        let status = AmsatStatus::from(&response.satellites[0]);
        assert_eq!(status.norad_id, Some(27_607));
        assert_eq!(status.capability_tag().as_deref(), Some("FM"));
        assert_eq!(status.heard_reports_24h, 5);
        // Sparse row: every optional absent.
        let sparse = AmsatStatus::from(&response.satellites[1]);
        assert_eq!(sparse.norad_id, None);
        assert!(sparse.last_heard_at.is_none());
    }

    #[test]
    fn decodes_reports_wire_shape() {
        let json = r#"{"windowStart":"2026-10-12T14:00:00Z","windowEnd":"2026-10-13T14:00:00Z",
            "names":["SO-50_[FM]"],
            "reports":[{"name":"SO-50_[FM]","reportedAt":"2026-10-13T13:30:00Z",
                        "callsign":"EI6FZ","report":"Heard","grid":"IO63"},
                       {"name":"SO-50_[FM]","reportedAt":"2026-10-13T12:30:00Z",
                        "callsign":"K1ABC","report":"Not Heard"}]}"#;
        let response: AmsatReportsResponse = serde_json::from_str(json).expect("decodes");
        assert_eq!(response.reports.len(), 2);
        let first = AmsatReport::from(&response.reports[0]);
        assert_eq!(first.kind, ReportKind::Heard);
        assert_eq!(first.grid.as_deref(), Some("IO63"));
        assert_eq!(AmsatReport::from(&response.reports[1]).kind, ReportKind::NotHeard);
    }

    #[test]
    fn decodes_activity_wire_shape() {
        let json = r#"{"bucketSeconds":3600,
            "windowStart":"2026-10-06T14:00:00Z","windowEnd":"2026-10-13T14:12:08.112Z",
            "updatedAt":"2026-10-13T14:05:41Z",
            "satellites":[
              {"name":"SO-50_[FM]","noradId":27607,"buckets":[
                 {"start":"2026-10-13T12:00:00Z","heard":2,"notHeard":0,"telemetry":0,"crew":0,"other":0},
                 {"start":"2026-10-13T13:00:00Z","heard":1,"notHeard":1}
              ]},
              {"name":"MYSTERY-1_[FM]","buckets":[]}
            ]}"#;
        let response: AmsatActivityResponse = serde_json::from_str(json).expect("decodes");
        assert_eq!(response.bucket_seconds, 3_600);
        assert_eq!(response.satellites.len(), 2);
        let so50 = &response.satellites[0];
        assert_eq!(so50.norad_id, Some(27_607));
        assert_eq!(so50.buckets.len(), 2);
        // Missing counters default to zero.
        let bucket = ActivityBucket::from(&so50.buckets[1]);
        assert_eq!((bucket.heard, bucket.not_heard, bucket.telemetry), (1, 1, 0));
        assert!(response.satellites[1].norad_id.is_none());
        assert!(response.satellites[1].buckets.is_empty());
    }
}
