use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// Maps to the `spot_source` postgres enum.
#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "spot_source", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum SpotSource {
    Pota,
    Rbn,
    Sota,
    #[serde(rename = "self")]
    #[sqlx(rename = "self")]
    SelfSpot,
    Other,
}

/// Database row for the spots table.
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct SpotRow {
    pub id: Uuid,
    pub callsign: String,
    pub program_slug: Option<String>,
    pub source: SpotSource,
    pub external_id: Option<String>,
    pub frequency_khz: f64,
    pub mode: String,
    pub reference: Option<String>,
    pub reference_name: Option<String>,
    pub spotter: Option<String>,
    pub spotter_grid: Option<String>,
    pub location_desc: Option<String>,
    pub country_code: Option<String>,
    pub state_abbr: Option<String>,
    pub comments: Option<String>,
    pub snr: Option<i16>,
    pub wpm: Option<i16>,
    pub submitted_by: Option<Uuid>,
    pub spotted_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    /// Coordinates of the spotted station's reference (POTA park catalog /
    /// SOTA zone centroid), joined in by `list_spots` only — `#[sqlx(default)]`
    /// keeps the insert/upsert RETURNING queries decodable without them.
    #[sqlx(default)]
    pub ref_latitude: Option<f64>,
    #[sqlx(default)]
    pub ref_longitude: Option<f64>,
}

/// API response for a single spot.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotResponse {
    pub id: Uuid,
    pub callsign: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub program_slug: Option<String>,
    pub source: SpotSource,
    pub frequency_khz: f64,
    pub mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reference: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reference_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spotter: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spotter_grid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location_desc: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state_abbr: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub comments: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub snr: Option<i16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wpm: Option<i16>,
    /// Reference (park/summit) coordinates when the catalog knows them.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub longitude: Option<f64>,
    pub spotted_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

/// API response for GET /v1/spots.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotsListResponse {
    pub spots: Vec<SpotResponse>,
    pub pagination: SpotsPagination,
}

/// Pagination metadata for spots list.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotsPagination {
    pub has_more: bool,
    pub next_cursor: Option<String>,
}

/// Request body for POST /v1/spots (self-spot).
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateSelfSpotRequest {
    pub program_slug: String,
    pub frequency_khz: f64,
    pub mode: String,
    pub reference: Option<String>,
    pub comments: Option<String>,
}

/// Data structure for aggregator upserts.
#[derive(Debug)]
pub struct AggregatedSpot {
    pub callsign: String,
    pub program_slug: Option<String>,
    pub source: SpotSource,
    pub external_id: String,
    pub frequency_khz: f64,
    pub mode: String,
    pub reference: Option<String>,
    pub reference_name: Option<String>,
    pub spotter: Option<String>,
    pub spotter_grid: Option<String>,
    pub location_desc: Option<String>,
    pub country_code: Option<String>,
    pub state_abbr: Option<String>,
    pub comments: Option<String>,
    pub snr: Option<i16>,
    pub wpm: Option<i16>,
    pub spotted_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

impl From<SpotRow> for SpotResponse {
    fn from(row: SpotRow) -> Self {
        Self {
            id: row.id,
            callsign: row.callsign,
            program_slug: row.program_slug,
            source: row.source,
            frequency_khz: row.frequency_khz,
            mode: row.mode,
            reference: row.reference,
            reference_name: row.reference_name,
            spotter: row.spotter,
            spotter_grid: row.spotter_grid,
            location_desc: row.location_desc,
            country_code: row.country_code,
            state_abbr: row.state_abbr,
            comments: row.comments,
            snr: row.snr,
            wpm: row.wpm,
            latitude: row.ref_latitude,
            longitude: row.ref_longitude,
            spotted_at: row.spotted_at,
            expires_at: row.expires_at,
        }
    }
}
