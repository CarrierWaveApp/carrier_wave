//! Ham2K LoFi JSON models. Ports the wire shapes from `LoFiModels.swift` and
//! `LoFiModels+QSO.swift` — the registration handshake, the accounts/totals
//! endpoint, the operations + QSOs sync responses, and the sync flags.
//!
//! Credentials, keychain, retry/backoff, and the `URLSession` dance stay in
//! Swift today — `LoFiClient.swift` keeps those. Once a `reqwest` transport
//! lands here it only needs the bearer token from the host platform.

use serde::de::Deserializer;
use serde::{Deserialize, Serialize};

// ---- Registration / link --------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoFiClientCredentials {
    pub key: String,
    pub name: String,
    pub secret: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoFiAccountRequest {
    pub call: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoFiMetaRequest {
    pub app: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoFiRegistrationRequest {
    pub client: LoFiClientCredentials,
    pub account: LoFiAccountRequest,
    pub meta: LoFiMetaRequest,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoFiLinkDeviceRequest {
    pub email: String,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiRegistrationResponse {
    pub token: String,
    pub client: LoFiClientInfo,
    pub account: LoFiAccountInfo,
    pub meta: LoFiMetaInfo,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct LoFiClientInfo {
    pub uuid: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct LoFiAccountInfo {
    pub uuid: String,
    pub call: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(rename = "cutoff_date", default)]
    pub cutoff_date: Option<String>,
    #[serde(rename = "cutoff_date_millis", default)]
    pub cutoff_date_millis: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiMetaInfo {
    pub flags: LoFiSyncFlags,
}

// ---- Sync flags -----------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoFiSyncFlags {
    #[serde(rename = "suggested_sync_batch_size")]
    pub suggested_sync_batch_size: i32,
    #[serde(rename = "suggested_sync_loop_delay")]
    pub suggested_sync_loop_delay: i32,
    #[serde(rename = "suggested_sync_check_period")]
    pub suggested_sync_check_period: i32,
}

impl LoFiSyncFlags {
    /// Same defaults the Swift client falls back to when no flags are cached.
    pub const fn defaults() -> Self {
        Self {
            suggested_sync_batch_size: 50,
            suggested_sync_loop_delay: 10_000,
            suggested_sync_check_period: 20_000,
        }
    }

    /// Recommended interval between sync checks, in seconds.
    pub fn suggested_sync_check_interval_secs(&self) -> f64 {
        self.suggested_sync_check_period as f64 / 1_000.0
    }
}

// ---- Accounts / counts ----------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct LoFiRecordCounts {
    pub total: i32,
    pub syncable: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct LoFiAccountsResponse {
    pub operations: LoFiRecordCounts,
    pub qsos: LoFiRecordCounts,
}

// ---- Operations -----------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiOperationsResponse {
    pub operations: Vec<LoFiOperation>,
    pub meta: LoFiOperationsMetaWrapper,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiOperationsMetaWrapper {
    pub operations: LoFiOperationsMeta,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiOperationsMeta {
    #[serde(rename = "total_records")]
    pub total_records: i32,
    #[serde(rename = "synced_until_millis", default)]
    pub synced_until_millis: Option<f64>,
    #[serde(rename = "synced_until", default)]
    pub synced_until: Option<String>,
    #[serde(rename = "synced_since_millis", default)]
    pub synced_since_millis: Option<f64>,
    pub limit: i32,
    #[serde(rename = "records_left")]
    pub records_left: i32,
    #[serde(rename = "next_updated_at_millis", default)]
    pub next_updated_at_millis: Option<f64>,
    #[serde(rename = "next_synced_at_millis", default)]
    pub next_synced_at_millis: Option<f64>,
    #[serde(rename = "extended_page", default)]
    pub extended_page: Option<bool>,
    #[serde(rename = "other_clients_only", default)]
    pub other_clients_only: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiOperation {
    pub uuid: String,
    #[serde(rename = "stationCall")]
    pub station_call: String,
    pub account: String,
    #[serde(rename = "createdAtMillis")]
    pub created_at_millis: f64,
    #[serde(rename = "createdOnDeviceId", default)]
    pub created_on_device_id: Option<String>,
    #[serde(rename = "updatedAtMillis", default)]
    pub updated_at_millis: Option<f64>,
    #[serde(rename = "updatedOnDeviceId", default)]
    pub updated_on_device_id: Option<String>,
    #[serde(rename = "syncedAtMillis", default)]
    pub synced_at_millis: Option<f64>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub subtitle: Option<String>,
    #[serde(default)]
    pub grid: Option<String>,
    #[serde(default)]
    pub refs: Vec<LoFiOperationRef>,
    #[serde(rename = "qsoCount")]
    pub qso_count: i32,
    #[serde(rename = "startAtMillisMin", default)]
    pub start_at_millis_min: Option<f64>,
    #[serde(rename = "startAtMillisMax", default)]
    pub start_at_millis_max: Option<f64>,
    #[serde(rename = "isNew", default)]
    pub is_new: Option<bool>,
    #[serde(default, deserialize_with = "int_or_bool_opt")]
    pub deleted: Option<i32>,
    #[serde(default, deserialize_with = "int_or_bool_opt")]
    pub synced: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct LoFiOperationRef {
    #[serde(rename = "type")]
    pub ref_type: String,
    #[serde(rename = "ref", default)]
    pub reference: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub location: Option<String>,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(rename = "short_label", default)]
    pub short_label: Option<String>,
    #[serde(default)]
    pub program: Option<String>,
}

// ---- QSOs -----------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiQsosResponse {
    pub qsos: Vec<LoFiQso>,
    pub meta: LoFiQsosMetaWrapper,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiQsosMetaWrapper {
    pub qsos: LoFiQsosMeta,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiQsosMeta {
    #[serde(rename = "total_records")]
    pub total_records: i32,
    #[serde(rename = "synced_until_millis", default)]
    pub synced_until_millis: Option<f64>,
    #[serde(rename = "synced_until", default)]
    pub synced_until: Option<String>,
    #[serde(rename = "synced_since_millis", default)]
    pub synced_since_millis: Option<f64>,
    pub limit: i32,
    #[serde(rename = "records_left")]
    pub records_left: i32,
    #[serde(rename = "next_updated_at_millis", default)]
    pub next_updated_at_millis: Option<f64>,
    #[serde(rename = "next_synced_at_millis", default)]
    pub next_synced_at_millis: Option<f64>,
    #[serde(rename = "extended_page", default)]
    pub extended_page: Option<bool>,
    #[serde(rename = "other_clients_only", default)]
    pub other_clients_only: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiQso {
    pub uuid: String,
    #[serde(default)]
    pub operation: Option<String>,
    #[serde(default)]
    pub account: Option<String>,
    #[serde(rename = "createdAtMillis", default)]
    pub created_at_millis: Option<f64>,
    #[serde(rename = "updatedAtMillis", default)]
    pub updated_at_millis: Option<f64>,
    #[serde(rename = "syncedAtMillis", default)]
    pub synced_at_millis: Option<f64>,
    #[serde(rename = "startAtMillis", default)]
    pub start_at_millis: Option<f64>,
    #[serde(default)]
    pub their: Option<LoFiTheirInfo>,
    #[serde(default)]
    pub our: Option<LoFiOurInfo>,
    #[serde(default)]
    pub band: Option<String>,
    #[serde(default)]
    pub freq: Option<f64>,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub refs: Option<Vec<LoFiQsoRef>>,
    #[serde(rename = "txPwr", default)]
    pub tx_pwr: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default, deserialize_with = "int_or_bool_opt")]
    pub deleted: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiTheirInfo {
    #[serde(default)]
    pub call: Option<String>,
    #[serde(default)]
    pub sent: Option<String>,
    #[serde(default)]
    pub guess: Option<LoFiGuessInfo>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiOurInfo {
    #[serde(default)]
    pub call: Option<String>,
    #[serde(default)]
    pub sent: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoFiGuessInfo {
    #[serde(default)]
    pub call: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub state: Option<String>,
    #[serde(default)]
    pub city: Option<String>,
    #[serde(default)]
    pub grid: Option<String>,
    #[serde(default)]
    pub country: Option<String>,
    #[serde(rename = "entity_name", default)]
    pub entity_name: Option<String>,
    #[serde(rename = "cq_zone", default)]
    pub cq_zone: Option<i32>,
    #[serde(rename = "itu_zone", default)]
    pub itu_zone: Option<i32>,
    #[serde(rename = "dxcc_code", default)]
    pub dxcc_code: Option<i32>,
    #[serde(default)]
    pub continent: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct LoFiQsoRef {
    #[serde(rename = "type", default)]
    pub ref_type: Option<String>,
    #[serde(rename = "ref", default)]
    pub reference: Option<String>,
    #[serde(default)]
    pub program: Option<String>,
    #[serde(rename = "our_number", default)]
    pub our_number: Option<String>,
}

/// LoFi sometimes returns `deleted`/`synced` as a bool, sometimes as an int.
/// The Swift custom decoder picks whichever lands; we accept both.
fn int_or_bool_opt<'de, D>(deserializer: D) -> Result<Option<i32>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde_json::Value;

    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        Some(Value::Null) | None => None,
        Some(Value::Bool(b)) => Some(if b { 1 } else { 0 }),
        Some(Value::Number(n)) => n.as_i64().map(|x| x as i32),
        Some(other) => {
            // Strings or anything else — match Swift, which falls back to nil.
            other.as_str().and_then(|s| s.parse::<i32>().ok())
        }
    })
}

// ---- Helpers on operations ------------------------------------------------

impl LoFiOperation {
    /// Refs whose program/refType identify them as POTA activations.
    pub fn pota_refs(&self) -> Vec<&LoFiOperationRef> {
        self.refs
            .iter()
            .filter(|r| {
                r.ref_type == "potaActivation"
                    || r.program.as_deref() == Some("POTA")
            })
            .collect()
    }

    /// First POTA park reference, if any.
    pub fn pota_park_reference(&self) -> Option<String> {
        let parks: Vec<&str> = self
            .pota_refs()
            .into_iter()
            .filter_map(|r| r.reference.as_deref())
            .collect();
        if parks.is_empty() {
            None
        } else {
            Some(parks.join(", "))
        }
    }

    /// First SOTA activation ref.
    pub fn sota_ref(&self) -> Option<&LoFiOperationRef> {
        self.refs.iter().find(|r| {
            r.ref_type == "sotaActivation" || r.program.as_deref() == Some("SOTA")
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registration_response_decodes() {
        let json = r#"{
            "token": "abc",
            "client": {"uuid": "c-1", "name": "CarrierWave"},
            "account": {
                "uuid": "a-1", "call": "W6JY", "name": "Jay",
                "email": null, "cutoff_date": "2026-01-01",
                "cutoff_date_millis": 1735689600000
            },
            "meta": {
                "flags": {
                    "suggested_sync_batch_size": 100,
                    "suggested_sync_loop_delay": 5000,
                    "suggested_sync_check_period": 30000
                }
            }
        }"#;
        let resp: LoFiRegistrationResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.token, "abc");
        assert_eq!(resp.account.call, "W6JY");
        assert_eq!(resp.meta.flags.suggested_sync_batch_size, 100);
        assert!((resp.meta.flags.suggested_sync_check_interval_secs() - 30.0).abs() < 1e-9);
    }

    #[test]
    fn sync_flags_defaults_match_swift() {
        let f = LoFiSyncFlags::defaults();
        assert_eq!(f.suggested_sync_batch_size, 50);
        assert_eq!(f.suggested_sync_loop_delay, 10_000);
        assert_eq!(f.suggested_sync_check_period, 20_000);
    }

    #[test]
    fn operation_accepts_bool_or_int_flags() {
        let json_bool = r#"{
            "uuid": "op-1", "stationCall": "W6JY", "account": "a-1",
            "createdAtMillis": 1.0, "qsoCount": 2,
            "deleted": true, "synced": false
        }"#;
        let op: LoFiOperation = serde_json::from_str(json_bool).unwrap();
        assert_eq!(op.deleted, Some(1));
        assert_eq!(op.synced, Some(0));

        let json_int = r#"{
            "uuid": "op-2", "stationCall": "W6JY", "account": "a-1",
            "createdAtMillis": 1.0, "qsoCount": 3,
            "deleted": 0, "synced": 1
        }"#;
        let op: LoFiOperation = serde_json::from_str(json_int).unwrap();
        assert_eq!(op.deleted, Some(0));
        assert_eq!(op.synced, Some(1));
    }

    #[test]
    fn operation_helpers_classify_refs() {
        let op: LoFiOperation = serde_json::from_str(
            r#"{
                "uuid": "op-1", "stationCall": "W6JY", "account": "a-1",
                "createdAtMillis": 1.0, "qsoCount": 0,
                "refs": [
                    {"type": "potaActivation", "ref": "K-1234"},
                    {"type": "otherActivation", "ref": "X-1", "program": "POTA"},
                    {"type": "sotaActivation", "ref": "W6/CT-001"}
                ]
            }"#,
        )
        .unwrap();

        assert_eq!(op.pota_refs().len(), 2);
        assert_eq!(op.pota_park_reference().as_deref(), Some("K-1234, X-1"));
        assert!(op.sota_ref().is_some());
    }

    #[test]
    fn qsos_response_decodes_with_nested_their() {
        let json = r#"{
            "qsos": [{
                "uuid": "q-1",
                "operation": "op-1",
                "account": "a-1",
                "their": {
                    "call": "K2ABC",
                    "guess": {
                        "call": "K2ABC", "grid": "FN20",
                        "cq_zone": 5, "itu_zone": 8, "dxcc_code": 291,
                        "continent": "NA"
                    }
                },
                "our": {"call": "W6JY"},
                "band": "20m", "freq": 14.074, "mode": "FT8",
                "deleted": false
            }],
            "meta": {"qsos": {
                "total_records": 1, "limit": 50, "records_left": 0
            }}
        }"#;
        let resp: LoFiQsosResponse = serde_json::from_str(json).unwrap();
        let q = &resp.qsos[0];
        assert_eq!(q.uuid, "q-1");
        assert_eq!(q.their.as_ref().unwrap().call.as_deref(), Some("K2ABC"));
        let guess = q.their.as_ref().unwrap().guess.as_ref().unwrap();
        assert_eq!(guess.dxcc_code, Some(291));
        assert_eq!(q.deleted, Some(0));
        assert_eq!(resp.meta.qsos.total_records, 1);
    }

    #[test]
    fn accounts_response_decodes() {
        let json = r#"{
            "operations": {"total": 10, "syncable": 8},
            "qsos": {"total": 1000, "syncable": 950}
        }"#;
        let resp: LoFiAccountsResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.operations.syncable, 8);
        assert_eq!(resp.qsos.total, 1000);
    }
}
