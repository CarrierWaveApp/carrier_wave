use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

// ---------------------------------------------------------------------------
// POTA API types (upstream JSON shapes)
// ---------------------------------------------------------------------------

/// Response from GET /park/stats/{ref}
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct PotaApiStats {
    pub reference: String,
    pub attempts: i32,
    pub activations: i32,
    pub contacts: i32,
}

/// Single activation from GET /park/activations/{ref}?count=all
#[derive(Debug, Deserialize)]
pub struct PotaApiActivation {
    #[serde(rename = "activeCallsign")]
    pub active_callsign: String,
    pub qso_date: String, // "YYYYMMDD"
    #[serde(rename = "totalQSOs")]
    pub total_qsos: i32,
    #[serde(rename = "qsosCW", default)]
    pub qsos_cw: i32,
    #[serde(rename = "qsosDATA", default)]
    pub qsos_data: i32,
    #[serde(rename = "qsosPHONE", default)]
    pub qsos_phone: i32,
}

/// Hunter QSO entry from leaderboard response
#[derive(Debug, Deserialize)]
pub struct PotaApiHunterQso {
    pub callsign: String,
    pub count: i32,
}

/// Response from GET /park/leaderboard/{ref}?count=all
#[derive(Debug, Deserialize)]
pub struct PotaApiLeaderboard {
    #[serde(default)]
    pub hunter_qsos: Vec<PotaApiHunterQso>,
}

/// Single row from the all_parks_ext.csv
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct PotaCsvPark {
    pub reference: String,
    pub name: String,
    #[serde(default)]
    pub active: String, // "1" or "0"
    #[serde(rename = "entityId", default)]
    pub entity_id: Option<String>,
    #[serde(rename = "locationDesc", default)]
    pub location_desc: Option<String>,
    #[serde(rename = "latitude", default)]
    pub lat: Option<f64>,
    #[serde(rename = "longitude", default)]
    pub lon: Option<f64>,
    #[serde(default)]
    pub grid: Option<String>,
}

// ---------------------------------------------------------------------------
// Database row types
// ---------------------------------------------------------------------------

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct PotaParkRow {
    pub reference: String,
    pub name: String,
    pub location_desc: Option<String>,
    pub state: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub grid: Option<String>,
    pub active: bool,
    pub total_attempts: i32,
    pub total_activations: i32,
    pub total_qsos: i32,
    pub stats_fetched_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct PotaActivationRow {
    pub id: i64,
    pub park_reference: String,
    pub callsign: String,
    pub qso_date: NaiveDate,
    pub total_qsos: i32,
    pub qsos_cw: i32,
    pub qsos_data: i32,
    pub qsos_phone: i32,
    pub state: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct PotaHunterQsoRow {
    pub id: i64,
    pub park_reference: String,
    pub callsign: String,
    pub qso_count: i32,
    pub state: Option<String>,
}

/// Ranked activator from a window-function query.
#[derive(Debug, Clone, FromRow)]
pub struct RankedActivatorRow {
    pub callsign: String,
    pub activation_count: i64,
    pub total_qsos: i64,
    pub total_cw: i64,
    pub total_data: i64,
    pub total_phone: i64,
    pub rank: i64,
    pub total_ranked: i64,
}

/// Ranked activator by a single mode.
#[derive(Debug, Clone, FromRow)]
pub struct RankedActivatorByModeRow {
    pub callsign: String,
    pub mode_qsos: i64,
    pub rank: i64,
    pub total_ranked: i64,
}

/// Ranked hunter from a window-function query.
#[derive(Debug, Clone, FromRow)]
pub struct RankedHunterRow {
    pub callsign: String,
    pub total_qsos: i64,
    pub rank: i64,
    pub total_ranked: i64,
}

/// Aggregate state-level stats.
#[derive(Debug, Clone, FromRow)]
pub struct StateAggregateRow {
    pub total_activations: i64,
    pub unique_activators: i64,
    pub total_qsos: i64,
}

/// Top entry (callsign + count) used for state/park top lists.
#[derive(Debug, Clone, FromRow)]
pub struct TopCallsignRow {
    pub callsign: String,
    pub count: i64,
}

/// Freshness info from fetch_status.
#[derive(Debug, Clone, FromRow)]
pub struct FreshnessRow {
    pub oldest_fetch: Option<DateTime<Utc>>,
    pub newest_fetch: Option<DateTime<Utc>>,
    pub parks_pending: i64,
    pub total_parks: i64,
}

/// Stalest park reference for batch fetching.
#[derive(Debug, Clone, FromRow)]
pub struct StaleParkRow {
    pub park_reference: String,
}

// ---------------------------------------------------------------------------
// Query parameter types (from HTTP query strings)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivatorStatsQuery {
    pub callsign: String,
    pub state: Option<String>,
    pub mode: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HunterStatsQuery {
    pub callsign: String,
    pub state: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RankingsQuery {
    pub state: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ---------------------------------------------------------------------------
// API response types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FreshnessInfo {
    pub oldest_fetch: Option<DateTime<Utc>>,
    pub newest_fetch: Option<DateTime<Utc>>,
    pub parks_pending: i64,
    pub total_parks: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warning: Option<String>,
}

impl From<FreshnessRow> for FreshnessInfo {
    fn from(row: FreshnessRow) -> Self {
        let warning = if row.total_parks == 0 {
            Some("Park catalog has not been synced yet. Stats are unavailable.".to_string())
        } else if row.parks_pending > 0 {
            let pct = 100 - (row.parks_pending * 100 / row.total_parks);
            Some(format!(
                "Data collection in progress ({pct}% complete, {} of {} parks fetched). Stats may be incomplete.",
                row.total_parks - row.parks_pending,
                row.total_parks,
            ))
        } else {
            None
        };

        Self {
            oldest_fetch: row.oldest_fetch,
            newest_fetch: row.newest_fetch,
            parks_pending: row.parks_pending,
            total_parks: row.total_parks,
            warning,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QsosByMode {
    pub cw: i64,
    pub data: i64,
    pub phone: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RankedCallsignResponse {
    pub callsign: String,
    pub count: i64,
}

impl From<TopCallsignRow> for RankedCallsignResponse {
    fn from(row: TopCallsignRow) -> Self {
        Self {
            callsign: row.callsign,
            count: row.count,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivatorStatsResponse {
    pub callsign: String,
    pub activation_count: i64,
    pub total_qsos: i64,
    pub qsos_by_mode: QsosByMode,
    pub rank: i64,
    pub total_ranked: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode_filter: Option<String>,
    pub freshness: FreshnessInfo,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HunterStatsResponse {
    pub callsign: String,
    pub total_qsos: i64,
    pub rank: i64,
    pub total_ranked: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    pub freshness: FreshnessInfo,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StateStatsResponse {
    pub state: String,
    pub total_activations: i64,
    pub unique_activators: i64,
    pub total_qsos: i64,
    pub top_activators: Vec<RankedCallsignResponse>,
    pub top_hunters: Vec<RankedCallsignResponse>,
    pub freshness: FreshnessInfo,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ParkStatsResponse {
    pub reference: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location_desc: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub longitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grid: Option<String>,
    pub active: bool,
    pub total_attempts: i32,
    pub total_activations: i32,
    pub total_qsos: i32,
    pub top_activators: Vec<RankedCallsignResponse>,
    pub top_hunters: Vec<RankedCallsignResponse>,
    pub freshness: FreshnessInfo,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivatorRankingEntry {
    pub callsign: String,
    pub activation_count: i64,
    pub total_qsos: i64,
    pub qsos_by_mode: QsosByMode,
    pub rank: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivatorRankingsResponse {
    pub rankings: Vec<ActivatorRankingEntry>,
    pub total_ranked: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    pub freshness: FreshnessInfo,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PotaSyncStatusResponse {
    pub total_parks: i64,
    pub parks_fetched: i64,
    pub parks_pending: i64,
    pub completion_percentage: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub oldest_fetch: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub newest_fetch: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warning: Option<String>,
}
