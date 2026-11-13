//! Sync journal types. Port of `CloudSyncJournalEntry.swift`.
//!
//! Transport-agnostic: the same payloads that were serialized into a CloudKit
//! `ChangeJournal` record now serialize to JSON for the HTTPS sync endpoint.

use crate::conflict::{LoggingSessionPayload, SyncQso};
use serde::{Deserialize, Serialize};

/// Entity types tracked in journal entries.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum JournalEntityType {
    Qso,
    ServicePresence,
    LoggingSession,
    ActivationMetadata,
    SessionSpot,
    ActivityLog,
    RadioMacro,
    Club,
    ClubMember,
    SyncedConfig,
}

/// Wire payload for a synced configuration blob (the `syncedConfig` entity).
/// One logical config per `config_type`; `data` is an opaque JSON string the
/// consumer decodes. LWW converges on `modified_at`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncedConfigPayload {
    pub id: String,
    pub config_type: String,
    pub data: String,
    /// Unix seconds of the last local edit (the LWW key).
    pub modified_at: Option<i64>,
}

/// A single change operation. (Only QSO upsert is fully modelled this phase;
/// the other upserts follow the same tagged-enum shape.)
///
/// Forward-compatibility: the server returns *every* journal entry on pull,
/// regardless of entity type, so a client may meet an `"op"` tag minted by a
/// newer client. `#[serde(other)] Unknown` makes such an entry decode to a
/// skip-able variant instead of failing the whole payload — without it, one
/// unknown op would abort an entire pull batch (QSO ops included). Applying an
/// `Unknown` op is a no-op; see `apply_inbound` in cw-ffi's `sync_transport`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op")]
pub enum JournalOperation {
    // Boxed: the QSO payload is far larger than the `Delete` variant.
    UpsertQso(Box<SyncQso>),
    UpsertSyncedConfig(SyncedConfigPayload),
    // Boxed: the session payload is the largest variant (~45 wire fields).
    UpsertLoggingSession(Box<LoggingSessionPayload>),
    Delete { entity_type: JournalEntityType, id: String },
    /// An `"op"` tag this build does not recognise (minted by a newer client).
    /// Decoded tolerantly so it never aborts a pull batch; skipped on apply.
    /// Never constructed locally, so it is never serialized onto the wire.
    #[serde(other)]
    Unknown,
}

impl JournalOperation {
    /// Convenience constructor that boxes the QSO payload.
    pub fn upsert_qso(qso: SyncQso) -> Self {
        JournalOperation::UpsertQso(Box::new(qso))
    }

    /// Convenience constructor that boxes the session payload.
    pub fn upsert_logging_session(session: LoggingSessionPayload) -> Self {
        JournalOperation::UpsertLoggingSession(Box::new(session))
    }

    /// The entity type this op touches, or `None` for an `Unknown` (unrecognised)
    /// op that carries no locally-known entity.
    pub fn entity_type(&self) -> Option<JournalEntityType> {
        match self {
            JournalOperation::UpsertQso(_) => Some(JournalEntityType::Qso),
            JournalOperation::UpsertSyncedConfig(_) => Some(JournalEntityType::SyncedConfig),
            JournalOperation::UpsertLoggingSession(_) => Some(JournalEntityType::LoggingSession),
            JournalOperation::Delete { entity_type, .. } => Some(*entity_type),
            JournalOperation::Unknown => None,
        }
    }

    pub fn entity_id(&self) -> Option<String> {
        match self {
            JournalOperation::UpsertQso(fields) => Some(fields.id.clone()),
            JournalOperation::UpsertSyncedConfig(cfg) => Some(cfg.id.clone()),
            JournalOperation::UpsertLoggingSession(session) => Some(session.id.clone()),
            JournalOperation::Delete { id, .. } => Some(id.clone()),
            JournalOperation::Unknown => None,
        }
    }
}

/// A batch of operations from one device, ordered by `sequence_number`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct JournalPayload {
    pub id: String,
    pub device_id: String,
    /// Unix seconds.
    pub timestamp: i64,
    pub sequence_number: i64,
    pub operations: Vec<JournalOperation>,
}

impl JournalPayload {
    pub const RECORD_TYPE: &'static str = "ChangeJournal";
    pub const MAX_OPERATIONS_PER_ENTRY: usize = 100;

    pub fn new(
        id: impl Into<String>,
        device_id: impl Into<String>,
        timestamp: i64,
        sequence_number: i64,
        operations: Vec<JournalOperation>,
    ) -> Self {
        JournalPayload {
            id: id.into(),
            device_id: device_id.into(),
            timestamp,
            sequence_number,
            operations,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conflict::{LoggingSessionPayload, SyncQso};

    fn qso(id: &str) -> SyncQso {
        SyncQso {
            id: id.into(),
            callsign: "W1AW".into(),
            band: "20m".into(),
            mode: "FT8".into(),
            frequency: Some(14_074.0),
            timestamp: 1000,
            my_grid: None,
            their_grid: None,
            park_reference: None,
            notes: None,
            imported_at: None,
            modified_at: Some(1000),
            qrz_confirmed: false,
            lotw_confirmed: false,
            is_hidden: false,
            ..Default::default()
        }
    }

    // Guards the wire contract the browser logbook's delete writer depends on
    // (server/logbook-web/src/sync/writeClient.ts). That client hand-builds this
    // exact JSON — snake_case `device_id`/`sequence_number` (JournalPayload has
    // no rename_all) and a snake_case tagged Delete op. If this struct ever
    // gains `rename_all` or renames a field, web-initiated deletes would fail to
    // deserialize here on pull; this test breaks first.
    #[test]
    fn browser_delete_wire_json_deserializes() {
        let wire = r#"{"id":"e1","device_id":"web-abc","timestamp":42,"sequence_number":7,"operations":[{"op":"Delete","entity_type":"qso","id":"q1"}]}"#;
        let payload: JournalPayload = serde_json::from_str(wire).unwrap();
        assert_eq!(payload.device_id, "web-abc");
        assert_eq!(payload.sequence_number, 7);
        assert_eq!(payload.operations.len(), 1);
        assert_eq!(payload.operations[0].entity_type(), Some(JournalEntityType::Qso));
        assert_eq!(payload.operations[0].entity_id().as_deref(), Some("q1"));
    }

    #[test]
    fn payload_json_round_trip() {
        let payload = JournalPayload::new(
            "Journal-1",
            "device-abc",
            1700,
            42,
            vec![
                JournalOperation::upsert_qso(qso("q1")),
                JournalOperation::Delete { entity_type: JournalEntityType::Qso, id: "q2".into() },
            ],
        );
        let json = serde_json::to_string(&payload).unwrap();
        let back: JournalPayload = serde_json::from_str(&json).unwrap();
        assert_eq!(payload, back);
        assert_eq!(back.operations[0].entity_type(), Some(JournalEntityType::Qso));
        assert_eq!(back.operations[1].entity_id().as_deref(), Some("q2"));
    }

    #[test]
    fn synced_config_op_round_trip() {
        let payload = JournalPayload::new(
            "Journal-cfg",
            "device-abc",
            1700,
            43,
            vec![JournalOperation::UpsertSyncedConfig(SyncedConfigPayload {
                id: "synced-config:bragSheet".into(),
                config_type: "bragSheet".into(),
                data: "{\"include_map\":true}".into(),
                modified_at: Some(1700),
            })],
        );
        let json = serde_json::to_string(&payload).unwrap();
        let back: JournalPayload = serde_json::from_str(&json).unwrap();
        assert_eq!(payload, back);
        assert_eq!(back.operations[0].entity_type(), Some(JournalEntityType::SyncedConfig));
        assert_eq!(back.operations[0].entity_id().as_deref(), Some("synced-config:bragSheet"));
    }

    #[test]
    fn logging_session_op_round_trip() {
        let payload = JournalPayload::new(
            "Journal-sess",
            "device-abc",
            1700,
            44,
            vec![JournalOperation::upsert_logging_session(LoggingSessionPayload {
                id: "sess-1".into(),
                my_callsign: "W6JY".into(),
                started_at: 1700,
                mode: "CW".into(),
                activation_type_raw_value: "pota".into(),
                status_raw_value: "active".into(),
                park_reference: Some("US-1234".into()),
                photo_filenames: vec!["a.jpg".into()],
                operator_callsigns_raw_value: "[]".into(),
                ..Default::default()
            })],
        );
        let json = serde_json::to_string(&payload).unwrap();
        let back: JournalPayload = serde_json::from_str(&json).unwrap();
        assert_eq!(payload, back);
        assert_eq!(back.operations[0].entity_type(), Some(JournalEntityType::LoggingSession));
        assert_eq!(back.operations[0].entity_id().as_deref(), Some("sess-1"));
    }

    #[test]
    fn logging_session_entity_type_serializes_camel_case() {
        // The dirty-flag resolver + server key off this string; it must be the
        // camelCase `loggingSession` that matches the cw-store registry arm.
        let json = serde_json::to_string(&JournalEntityType::LoggingSession).unwrap();
        assert_eq!(json, "\"loggingSession\"");
    }

    #[test]
    fn synced_config_entity_type_serializes_camel_case() {
        // The server keys the payload's entity_type off this string; it must be
        // the camelCase `syncedConfig` that matches the cw-store registry arm.
        let json = serde_json::to_string(&JournalEntityType::SyncedConfig).unwrap();
        assert_eq!(json, "\"syncedConfig\"");
    }

    /// Regression guard for the Critical forward-compat finding: the pull path
    /// decodes every entry regardless of entity type, so an old client MUST NOT
    /// abort a whole batch when it meets an `"op"` tag it doesn't know. A mix of
    /// known + unknown ops must deserialize, mapping the unknown op to `Unknown`
    /// while keeping the known ops intact and in order.
    #[test]
    fn unknown_op_decodes_to_unknown_variant_and_preserves_known_ops() {
        // Build a real payload (a known UpsertQso + a known Delete), serialize
        // it, then splice a made-up future op into the middle of the JSON so the
        // known ops carry their exact wire shape and only the unknown tag is
        // synthetic — the realistic "newer client added an op" scenario.
        let base = JournalPayload::new(
            "e1",
            "dev-1",
            42,
            7,
            vec![
                JournalOperation::upsert_qso(qso("q1")),
                JournalOperation::Delete { entity_type: JournalEntityType::Qso, id: "q2".into() },
            ],
        );
        let mut value: serde_json::Value = serde_json::to_value(&base).unwrap();
        let ops = value["operations"].as_array_mut().unwrap();
        ops.insert(
            1,
            serde_json::json!({
                "op": "SomeFutureOpTheClientDoesNotKnow",
                "whatever": { "nested": true },
                "extra": 123
            }),
        );
        let wire = serde_json::to_string(&value).unwrap();

        let payload: JournalPayload =
            serde_json::from_str(&wire).expect("unknown op must not abort the payload decode");
        assert_eq!(payload.operations.len(), 3);
        // Known ops survive, in order.
        assert_eq!(payload.operations[0].entity_type(), Some(JournalEntityType::Qso));
        assert_eq!(payload.operations[0].entity_id().as_deref(), Some("q1"));
        // Unknown op maps to the skip-able variant (no entity id, no known type).
        assert!(matches!(payload.operations[1], JournalOperation::Unknown));
        assert_eq!(payload.operations[1].entity_id(), None);
        // The trailing known op still decodes.
        assert_eq!(payload.operations[2].entity_type(), Some(JournalEntityType::Qso));
        assert_eq!(payload.operations[2].entity_id().as_deref(), Some("q2"));
    }
}
