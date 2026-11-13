//! Conflict resolution. Port of `CloudSyncConflictResolver.swift`.
//!
//! The transport-agnostic merge logic: field-level merge for QSOs (prefer the
//! newer side per differing field), union/OR merge for booleans, last-writer-
//! wins for simpler entities, and the notes-merge that dedupes `---`-separated
//! blocks. These primitives are identical regardless of CloudKit vs. server.

/// Pick between two required values: equal → either; else the preferred side.
pub fn pick_value<T: Clone + PartialEq>(local: &T, remote: &T, prefer_remote: bool) -> T {
    if local == remote {
        local.clone()
    } else if prefer_remote {
        remote.clone()
    } else {
        local.clone()
    }
}

/// Pick between two optionals: equal → either; one `None` → the other; else the
/// preferred side. Mirrors Swift `pickOptional`.
pub fn pick_optional<T: Clone + PartialEq>(
    local: &Option<T>,
    remote: &Option<T>,
    prefer_remote: bool,
) -> Option<T> {
    if local == remote {
        return local.clone();
    }
    if local.is_none() {
        return remote.clone();
    }
    if remote.is_none() {
        return local.clone();
    }
    if prefer_remote {
        remote.clone()
    } else {
        local.clone()
    }
}

/// The newer of two optional unix timestamps. Mirrors `newerOptionalDate`.
pub fn newer_optional_date(lhs: Option<i64>, rhs: Option<i64>) -> Option<i64> {
    match (lhs, rhs) {
        (Some(a), Some(b)) => Some(a.max(b)),
        (Some(_), None) => lhs,
        (None, Some(_)) => rhs,
        (None, None) => None,
    }
}

/// Merge notes, deduping `\n---\n`-separated blocks. Port of `mergeNotes`.
pub fn merge_notes(local: Option<&str>, remote: Option<&str>) -> Option<String> {
    match (local, remote) {
        (a, b) if a == b => a.map(str::to_string),
        (None, b) => b.map(str::to_string),
        (a, None) => a.map(str::to_string),
        (Some(local_str), Some(remote_str)) => {
            if local_str.contains(remote_str) {
                return Some(local_str.to_string());
            }
            if remote_str.contains(local_str) {
                return Some(remote_str.to_string());
            }
            let separator = "\n---\n";
            let mut seen: Vec<String> = Vec::new();
            let mut merged: Vec<String> = Vec::new();
            for block in local_str.split(separator).chain(remote_str.split(separator)) {
                let trimmed = block.trim().to_string();
                if trimmed.is_empty() || seen.contains(&trimmed) {
                    continue;
                }
                seen.push(trimmed.clone());
                merged.push(trimmed);
            }
            let result = merged.join(separator);
            // Match Swift's `prefix(10_000)` which counts Characters.
            if result.chars().count() > 10_000 {
                Some(result.chars().take(10_000).collect())
            } else {
                Some(result)
            }
        }
    }
}

/// Base64 (de)serialization for the optional `spotCommentsData` blob, matching
/// Swift's default `JSONEncoder` `dataEncodingStrategy == .base64` (standard
/// alphabet, padded). Nil is omitted on the wire (`encodeIfPresent`), so the
/// field also carries `skip_serializing_if`.
mod b64_opt {
    use base64::Engine as _;
    use serde::{Deserialize as _, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(value: &Option<Vec<u8>>, ser: S) -> Result<S::Ok, S::Error> {
        match value {
            Some(bytes) => {
                ser.serialize_str(&base64::engine::general_purpose::STANDARD.encode(bytes))
            }
            None => ser.serialize_none(),
        }
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(de: D) -> Result<Option<Vec<u8>>, D::Error> {
        match Option::<String>::deserialize(de)? {
            Some(text) => base64::engine::general_purpose::STANDARD
                .decode(text.as_bytes())
                .map(Some)
                .map_err(serde::de::Error::custom),
            None => Ok(None),
        }
    }
}

/// The full `QSOFields` wire QSO. Field-for-field parity with the Swift journal
/// struct (`CKRecordMapper+Fields.swift`, `struct QSOFields`): every JSON key,
/// type, and optionality matches what the Swift `JSONEncoder` emits for a
/// journal operation, so a Rust-driven and a Swift-driven sync are byte
/// compatible. Keys are camelCase (`rename_all`); `rawADIF` / `isActivityLogQSO`
/// keep their capitalized acronyms via explicit renames; dates are Unix seconds
/// (Swift `.secondsSince1970`, which emits whole seconds as bare integers);
/// `spotCommentsData` is base64 (Swift `.base64`). Optionals are omitted when
/// nil to mirror Swift's `encodeIfPresent`.
///
/// Non-wire `FfiQso`/store columns (`contest_*`, `aoaCode`, `callsignChangeNote`,
/// `originalCallsign`, `dirty`) are intentionally absent — they are not in the
/// Swift `QSOFields` wire struct and are preserved across an inbound merge by
/// writing only the modeled fields onto the existing row (see
/// `cw-ffi/sync_transport.rs::apply_sync_onto`), mirroring `QSOJournalStore`.
#[derive(Debug, Clone, PartialEq, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncQso {
    pub id: String,
    pub callsign: String,
    pub band: String,
    pub mode: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frequency: Option<f64>,
    pub timestamp: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rst_sent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rst_received: Option<String>,
    pub my_callsign: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_grid: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub their_grid: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub park_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub their_park_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    /// QSOFields `importSource` (a `String` raw enum). Always picked from local.
    pub import_source: String,
    /// Unix seconds; `QSOFields.importedAt` is non-optional, so it always serializes.
    pub imported_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub modified_at: Option<i64>,
    #[serde(rename = "rawADIF", default, skip_serializing_if = "Option::is_none")]
    pub raw_adif: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub qth: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub power: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_rig: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub station_profile_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sota_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wwff_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub qrz_log_id: Option<String>,
    pub qrz_confirmed: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lotw_confirmed_date: Option<i64>,
    pub lotw_confirmed: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dxcc: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub their_license_class: Option<String>,
    pub is_hidden: bool,
    #[serde(rename = "isActivityLogQSO")]
    pub is_activity_log_qso: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub logging_session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub station_callsign: Option<String>,
    #[serde(with = "b64_opt", default, skip_serializing_if = "Option::is_none")]
    pub spot_comments_data: Option<Vec<u8>>,
    pub notes_user_authored: bool,
    /// ADIF SAT_NAME (satellite short name, e.g. "AO-91").
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sat_name: Option<String>,
    /// ADIF PROP_MODE ("SAT" for satellite QSOs).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prop_mode: Option<String>,
}

/// The `LoggingSessionFields` wire session. Field-for-field parity with the
/// Swift journal struct (`LoggingSessionFields.swift`): every JSON key, type, and
/// optionality matches what the Swift `JSONEncoder` emits for a
/// `.upsertLoggingSession` operation, so a Rust-driven and a Swift-driven sync
/// are byte compatible. Keys are camelCase (`rename_all`); dates are Unix seconds
/// (Swift `.secondsSince1970`, bare integers); `spotCommentsData` / `roveStopsData`
/// are base64 (Swift `.base64`); `photoFilenames` is a JSON array of strings (the
/// store keeps it as a JSON-encoded string). Optionals are omitted when nil to
/// mirror Swift's synthesized `encodeIfPresent`.
///
/// This is a strict SUBSET of the full `cw_store::LoggingSession` (~45 of 76
/// columns). The non-wire store columns (`programs_raw_value`,
/// `mission_reference`, `radio_item_id`, `cloud_dirty_flag`, all `contest_*`, all
/// TOTA / activation-geometry / track / tile fields) have no wire slot and are
/// preserved across an inbound merge by writing only the modeled fields onto the
/// existing row (see `cw-ffi/sync_transport.rs::apply_session_onto`), mirroring
/// the Swift `applySessionFields` seam.
#[derive(Debug, Clone, PartialEq, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoggingSessionPayload {
    pub id: String,
    pub my_callsign: String,
    pub started_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ended_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frequency: Option<f64>,
    pub mode: String,
    pub activation_type_raw_value: String,
    pub status_raw_value: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub park_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sota_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wwff_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_grid: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub power: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_rig: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub qso_comment: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom_title: Option<String>,
    pub qso_count: i64,
    pub is_rove: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_antenna: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_mic: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extra_equipment: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attendees: Option<String>,
    /// Swift `[String]` — a JSON array on the wire (the store keeps a JSON string).
    #[serde(default)]
    pub photo_filenames: Vec<String>,
    #[serde(with = "b64_opt", default, skip_serializing_if = "Option::is_none")]
    pub spot_comments_data: Option<Vec<u8>>,
    #[serde(with = "b64_opt", default, skip_serializing_if = "Option::is_none")]
    pub rove_stops_data: Option<Vec<u8>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_k_index: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_flux: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_sunspots: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_propagation_rating: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_a_index: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_band_conditions: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_timestamp: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub solar_conditions: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_temperature_f: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_temperature_c: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_humidity: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_wind_speed: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_wind_direction: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_timestamp: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub station_callsign: Option<String>,
    pub operator_callsigns_raw_value: String,
}

/// Session status raw value marking a terminated session. Mirrors
/// `LoggingSessionStatus.completed.rawValue`.
const SESSION_STATUS_COMPLETED: &str = "completed";

/// Resolve the merged `(status, ended_at)` for two session sides. Port of
/// `CloudSyncConflictResolver.mergeSessionStatus`: "completed" is terminal — once
/// either device has ended a session it stays ended, keeping the newer `ended_at`.
/// Otherwise the winner's status/ended_at ride through.
///
/// Swift falls back to `Date()` for the (pathological) both-`nil` completed case;
/// we use the deterministic `completed_fallback` the caller threads in (the
/// inbound payload timestamp) so the merge stays pure and reproducible.
fn merge_session_status(
    local: &LoggingSessionPayload,
    remote: &LoggingSessionPayload,
    winner: &LoggingSessionPayload,
    completed_fallback: i64,
) -> (String, Option<i64>) {
    let either_completed = local.status_raw_value == SESSION_STATUS_COMPLETED
        || remote.status_raw_value == SESSION_STATUS_COMPLETED;
    if either_completed {
        let ended = newer_optional_date(local.ended_at, remote.ended_at).or(Some(completed_fallback));
        return (SESSION_STATUS_COMPLETED.to_string(), ended);
    }
    (winner.status_raw_value.clone(), winner.ended_at)
}

/// Last-writer-wins session merge with `qso_count` max + completed-wins status.
/// Port of `CloudSyncConflictResolver.mergeLoggingSession`. The LWW key is the
/// session's own `ended_at ?? started_at` (see the inbound caller), not a generic
/// `modified_at` (sessions have none). `completed_fallback` seeds the terminal
/// `ended_at` for the both-`nil` completed edge (the payload timestamp).
pub fn merge_logging_session(
    local: &LoggingSessionPayload,
    remote: &LoggingSessionPayload,
    local_mod: i64,
    remote_mod: i64,
    completed_fallback: i64,
) -> LoggingSessionPayload {
    let prefer_remote = remote_mod > local_mod;
    let winner = if prefer_remote { remote } else { local };
    let (status_raw_value, ended_at) =
        merge_session_status(local, remote, winner, completed_fallback);

    LoggingSessionPayload {
        id: local.id.clone(),
        my_callsign: winner.my_callsign.clone(),
        started_at: winner.started_at,
        ended_at,
        frequency: winner.frequency,
        mode: winner.mode.clone(),
        activation_type_raw_value: winner.activation_type_raw_value.clone(),
        status_raw_value,
        park_reference: winner.park_reference.clone(),
        sota_reference: winner.sota_reference.clone(),
        wwff_reference: winner.wwff_reference.clone(),
        my_grid: winner.my_grid.clone(),
        power: winner.power,
        my_rig: winner.my_rig.clone(),
        notes: winner.notes.clone(),
        qso_comment: winner.qso_comment.clone(),
        custom_title: winner.custom_title.clone(),
        // Never lose logged contacts to a stale count — take the higher side.
        qso_count: local.qso_count.max(remote.qso_count),
        is_rove: winner.is_rove,
        my_antenna: winner.my_antenna.clone(),
        my_key: winner.my_key.clone(),
        my_mic: winner.my_mic.clone(),
        extra_equipment: winner.extra_equipment.clone(),
        attendees: winner.attendees.clone(),
        photo_filenames: winner.photo_filenames.clone(),
        spot_comments_data: winner.spot_comments_data.clone(),
        rove_stops_data: winner.rove_stops_data.clone(),
        solar_k_index: winner.solar_k_index,
        solar_flux: winner.solar_flux,
        solar_sunspots: winner.solar_sunspots,
        solar_propagation_rating: winner.solar_propagation_rating.clone(),
        solar_a_index: winner.solar_a_index,
        solar_band_conditions: winner.solar_band_conditions.clone(),
        solar_timestamp: winner.solar_timestamp,
        solar_conditions: winner.solar_conditions.clone(),
        weather_temperature_f: winner.weather_temperature_f,
        weather_temperature_c: winner.weather_temperature_c,
        weather_humidity: winner.weather_humidity,
        weather_wind_speed: winner.weather_wind_speed,
        weather_wind_direction: winner.weather_wind_direction.clone(),
        weather_description: winner.weather_description.clone(),
        weather_timestamp: winner.weather_timestamp,
        weather: winner.weather.clone(),
        station_callsign: winner.station_callsign.clone(),
        operator_callsigns_raw_value: winner.operator_callsigns_raw_value.clone(),
    }
}

/// Field-level QSO merge. Port of `CloudSyncConflictResolver.mergeQSO`.
pub fn merge_qso(local: &SyncQso, remote: &SyncQso, local_mod: i64, remote_mod: i64) -> SyncQso {
    let prefer_remote = remote_mod > local_mod;
    SyncQso {
        id: local.id.clone(),
        callsign: pick_value(&local.callsign, &remote.callsign, prefer_remote),
        band: pick_value(&local.band, &remote.band, prefer_remote),
        mode: pick_value(&local.mode, &remote.mode, prefer_remote),
        frequency: pick_optional(&local.frequency, &remote.frequency, prefer_remote),
        timestamp: pick_value(&local.timestamp, &remote.timestamp, prefer_remote),
        rst_sent: pick_optional(&local.rst_sent, &remote.rst_sent, prefer_remote),
        rst_received: pick_optional(&local.rst_received, &remote.rst_received, prefer_remote),
        my_callsign: pick_value(&local.my_callsign, &remote.my_callsign, prefer_remote),
        my_grid: pick_optional(&local.my_grid, &remote.my_grid, prefer_remote),
        their_grid: pick_optional(&local.their_grid, &remote.their_grid, prefer_remote),
        park_reference: pick_optional(&local.park_reference, &remote.park_reference, prefer_remote),
        their_park_reference: pick_optional(
            &local.their_park_reference,
            &remote.their_park_reference,
            prefer_remote,
        ),
        notes: merge_notes(local.notes.as_deref(), remote.notes.as_deref()),
        // Swift keeps `local.importSource` unconditionally.
        import_source: local.import_source.clone(),
        imported_at: min_optional(local.imported_at, remote.imported_at),
        modified_at: pick_optional(&local.modified_at, &remote.modified_at, prefer_remote),
        // Swift: `rawADIF: local.rawADIF ?? remote.rawADIF` — local first non-nil.
        raw_adif: local.raw_adif.clone().or_else(|| remote.raw_adif.clone()),
        name: pick_optional(&local.name, &remote.name, prefer_remote),
        qth: pick_optional(&local.qth, &remote.qth, prefer_remote),
        state: pick_optional(&local.state, &remote.state, prefer_remote),
        country: pick_optional(&local.country, &remote.country, prefer_remote),
        power: pick_optional(&local.power, &remote.power, prefer_remote),
        my_rig: pick_optional(&local.my_rig, &remote.my_rig, prefer_remote),
        station_profile_name: pick_optional(
            &local.station_profile_name,
            &remote.station_profile_name,
            prefer_remote,
        ),
        sota_ref: pick_optional(&local.sota_ref, &remote.sota_ref, prefer_remote),
        wwff_ref: pick_optional(&local.wwff_ref, &remote.wwff_ref, prefer_remote),
        qrz_log_id: pick_optional(&local.qrz_log_id, &remote.qrz_log_id, prefer_remote),
        // Confirmation/visibility flags are sticky: once true anywhere, true.
        qrz_confirmed: local.qrz_confirmed || remote.qrz_confirmed,
        lotw_confirmed_date: pick_optional(
            &local.lotw_confirmed_date,
            &remote.lotw_confirmed_date,
            prefer_remote,
        ),
        lotw_confirmed: local.lotw_confirmed || remote.lotw_confirmed,
        dxcc: pick_optional(&local.dxcc, &remote.dxcc, prefer_remote),
        their_license_class: pick_optional(
            &local.their_license_class,
            &remote.their_license_class,
            prefer_remote,
        ),
        is_hidden: local.is_hidden || remote.is_hidden,
        is_activity_log_qso: local.is_activity_log_qso || remote.is_activity_log_qso,
        logging_session_id: pick_optional(
            &local.logging_session_id,
            &remote.logging_session_id,
            prefer_remote,
        ),
        station_callsign: pick_optional(
            &local.station_callsign,
            &remote.station_callsign,
            prefer_remote,
        ),
        spot_comments_data: pick_optional(
            &local.spot_comments_data,
            &remote.spot_comments_data,
            prefer_remote,
        ),
        notes_user_authored: local.notes_user_authored || remote.notes_user_authored,
        sat_name: pick_optional(&local.sat_name, &remote.sat_name, prefer_remote),
        prop_mode: pick_optional(&local.prop_mode, &remote.prop_mode, prefer_remote),
    }
}

/// Last-writer-wins by modification date. Port of the LWW entity mergers
/// (ActivationMetadata / ActivityLog).
pub fn last_writer_wins<T: Clone>(local: &T, remote: &T, local_mod: i64, remote_mod: i64) -> T {
    if remote_mod > local_mod {
        remote.clone()
    } else {
        local.clone()
    }
}

fn min_optional(a: Option<i64>, b: Option<i64>) -> Option<i64> {
    match (a, b) {
        (Some(x), Some(y)) => Some(x.min(y)),
        (Some(_), None) => a,
        (None, Some(_)) => b,
        (None, None) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pick_optional_rules() {
        assert_eq!(pick_optional(&Some(1), &None, true), Some(1));
        assert_eq!(pick_optional(&None, &Some(2), false), Some(2));
        assert_eq!(pick_optional(&Some(1), &Some(2), true), Some(2));
        assert_eq!(pick_optional(&Some(1), &Some(2), false), Some(1));
        assert_eq!(pick_optional(&Some(5), &Some(5), true), Some(5));
    }

    #[test]
    fn newer_date_rules() {
        assert_eq!(newer_optional_date(Some(10), Some(20)), Some(20));
        assert_eq!(newer_optional_date(Some(10), None), Some(10));
        assert_eq!(newer_optional_date(None, Some(7)), Some(7));
        assert_eq!(newer_optional_date(None, None), None);
    }

    #[test]
    fn notes_subset_and_dedupe() {
        // One contains the other → the superset.
        assert_eq!(
            merge_notes(Some("hello world"), Some("hello")).as_deref(),
            Some("hello world")
        );
        // Distinct blocks → deduped union joined by separator.
        let merged = merge_notes(Some("a"), Some("b")).unwrap();
        assert_eq!(merged, "a\n---\nb");
        // Identical blocks collapse.
        let merged = merge_notes(Some("a\n---\nb"), Some("b\n---\nc")).unwrap();
        assert_eq!(merged, "a\n---\nb\n---\nc");
    }

    #[test]
    fn qso_field_level_merge_prefers_newer() {
        let local = SyncQso {
            id: "1".into(),
            callsign: "W1AW".into(),
            band: "20m".into(),
            mode: "FT8".into(),
            frequency: Some(14_074.0),
            timestamp: 1000,
            my_grid: Some("FN31".into()),
            notes: Some("local note".into()),
            imported_at: Some(500),
            modified_at: Some(1000),
            qrz_confirmed: false,
            lotw_confirmed: true,
            ..Default::default()
        };
        let mut remote = local.clone();
        remote.band = "40m".into();
        remote.their_grid = Some("EM12".into());
        remote.notes = Some("remote note".into());
        remote.imported_at = Some(400);
        remote.qrz_confirmed = true;
        remote.lotw_confirmed = false;

        // Remote is newer.
        let merged = merge_qso(&local, &remote, 1000, 2000);
        assert_eq!(merged.band, "40m"); // prefer remote on differing field
        assert_eq!(merged.their_grid.as_deref(), Some("EM12")); // remote fills None
        assert_eq!(merged.imported_at, Some(400)); // min of the two
        assert!(merged.qrz_confirmed); // OR
        assert!(merged.lotw_confirmed); // OR
        assert_eq!(merged.notes.as_deref(), Some("local note\n---\nremote note"));

        // Local is newer → keep local band.
        let merged_local = merge_qso(&local, &remote, 3000, 2000);
        assert_eq!(merged_local.band, "20m");
    }

    /// JSON fixture for a fully-populated QSO, derived field-for-field from the
    /// Swift wire struct `QSOFields` in `CKRecordMapper+Fields.swift` (camelCase
    /// CodingKeys; `JSONEncoder` with `.secondsSince1970` dates as bare integers,
    /// `.base64` data, `String`-raw `importSource`). Every one of the 41 keys is
    /// present. Round-tripping through `SyncQso` must keep the exact key set —
    /// no dropped, renamed, or invented fields.
    const FULL_QSO_JSON: &str = r#"{
        "id": "8E1D7F2A-0000-4000-8000-000000000001",
        "callsign": "W1AW",
        "band": "20m",
        "mode": "FT8",
        "frequency": 14.074,
        "timestamp": 1700000000,
        "rstSent": "599",
        "rstReceived": "579",
        "myCallsign": "W6JY",
        "myGrid": "CM87",
        "theirGrid": "FN31",
        "parkReference": "K-1234",
        "theirParkReference": "K-5678",
        "notes": "great contact",
        "importSource": "icloud",
        "importedAt": 1699999000,
        "modifiedAt": 1700000500,
        "rawADIF": "<call:4>W1AW<eor>",
        "name": "Hiram",
        "qth": "Newington",
        "state": "CT",
        "country": "United States",
        "power": 100,
        "myRig": "KX2",
        "stationProfileName": "Home",
        "sotaRef": "W1/HA-001",
        "wwffRef": "KFF-0001",
        "qrzLogId": "abc123",
        "qrzConfirmed": true,
        "lotwConfirmedDate": 1700001000,
        "lotwConfirmed": true,
        "dxcc": 291,
        "theirLicenseClass": "Extra",
        "isHidden": false,
        "isActivityLogQSO": false,
        "loggingSessionId": "8E1D7F2A-0000-4000-8000-000000000002",
        "stationCallsign": "W6JY",
        "spotCommentsData": "AQIDBA==",
        "notesUserAuthored": true,
        "satName": "AO-91",
        "propMode": "SAT"
    }"#;

    #[test]
    fn full_qso_json_round_trips_with_identical_key_set() {
        use std::collections::BTreeSet;

        let parsed: SyncQso = serde_json::from_str(FULL_QSO_JSON).expect("decodes Swift wire JSON");

        // A few representative typed assertions (parse fidelity).
        assert_eq!(parsed.frequency, Some(14.074));
        assert_eq!(parsed.timestamp, 1_700_000_000);
        assert_eq!(parsed.import_source, "icloud");
        assert_eq!(parsed.raw_adif.as_deref(), Some("<call:4>W1AW<eor>"));
        assert!(!parsed.is_activity_log_qso);
        assert_eq!(parsed.spot_comments_data.as_deref(), Some(&[1u8, 2, 3, 4][..]));

        // Re-encode and assert the key set is byte-for-byte the same as Swift's.
        let expected: serde_json::Value = serde_json::from_str(FULL_QSO_JSON).unwrap();
        let actual = serde_json::to_value(&parsed).unwrap();
        let expected_keys: BTreeSet<&String> =
            expected.as_object().unwrap().keys().collect();
        let actual_keys: BTreeSet<&String> = actual.as_object().unwrap().keys().collect();
        assert_eq!(actual_keys, expected_keys, "no dropped/renamed/invented keys");

        // And every value matches (full value-level parity, not just keys).
        assert_eq!(actual, expected, "value-level wire parity");
    }

    #[test]
    fn satellite_fields_merge_like_other_optionals() {
        // Remote fills a local None regardless of dates.
        let local = SyncQso::default();
        let remote = SyncQso {
            sat_name: Some("AO-91".into()),
            prop_mode: Some("SAT".into()),
            ..Default::default()
        };
        let merged = merge_qso(&local, &remote, 999, 1);
        assert_eq!(merged.sat_name.as_deref(), Some("AO-91"));
        assert_eq!(merged.prop_mode.as_deref(), Some("SAT"));

        // Both set + local newer → local wins.
        let local = SyncQso { sat_name: Some("SO-50".into()), ..Default::default() };
        let merged = merge_qso(&local, &remote, 200, 100);
        assert_eq!(merged.sat_name.as_deref(), Some("SO-50"));
    }

    #[test]
    fn confirmation_booleans_or_together() {
        let local = SyncQso {
            qrz_confirmed: true,
            lotw_confirmed: false,
            notes_user_authored: true,
            ..Default::default()
        };
        let remote = SyncQso {
            lotw_confirmed: true,
            is_activity_log_qso: true,
            ..Default::default()
        };

        // Tie on mod date → prefer local, but booleans still OR regardless.
        let merged = merge_qso(&local, &remote, 10, 10);
        assert!(merged.qrz_confirmed);
        assert!(merged.lotw_confirmed);
        assert!(merged.is_activity_log_qso);
        assert!(merged.notes_user_authored);
    }

    #[test]
    fn newer_rst_sent_wins_by_modified_at() {
        let local = SyncQso { rst_sent: Some("559".into()), ..Default::default() };
        let remote = SyncQso { rst_sent: Some("599".into()), ..Default::default() };

        // Remote newer → its differing rstSent wins.
        let merged = merge_qso(&local, &remote, 100, 200);
        assert_eq!(merged.rst_sent.as_deref(), Some("599"));

        // Local newer → local rstSent wins.
        let merged_local = merge_qso(&local, &remote, 200, 100);
        assert_eq!(merged_local.rst_sent.as_deref(), Some("559"));
    }

    #[test]
    fn raw_adif_prefers_local_then_remote() {
        // Swift uses `??`: local first non-nil, else remote, independent of dates.
        let local = SyncQso { raw_adif: Some("LOCAL".into()), ..Default::default() };
        let remote = SyncQso { raw_adif: Some("REMOTE".into()), ..Default::default() };
        assert_eq!(merge_qso(&local, &remote, 1, 999).raw_adif.as_deref(), Some("LOCAL"));

        let local_none = SyncQso::default();
        assert_eq!(merge_qso(&local_none, &remote, 1, 999).raw_adif.as_deref(), Some("REMOTE"));
    }

    #[test]
    fn notes_merge_in_full_qso() {
        let local = SyncQso { notes: Some("alpha".into()), ..Default::default() };
        let remote = SyncQso { notes: Some("beta".into()), ..Default::default() };
        let merged = merge_qso(&local, &remote, 1, 2);
        assert_eq!(merged.notes.as_deref(), Some("alpha\n---\nbeta"));
    }

    #[test]
    fn lww() {
        assert_eq!(last_writer_wins(&"a", &"b", 1, 2), "b");
        assert_eq!(last_writer_wins(&"a", &"b", 2, 1), "a");
        assert_eq!(last_writer_wins(&"a", &"b", 2, 2), "a"); // tie → local
    }

    // ---- LoggingSession wire + merge (port of mergeLoggingSession) ----

    /// JSON fixture for a fully-populated session, derived field-for-field from
    /// the Swift wire struct `LoggingSessionFields` (camelCase CodingKeys;
    /// `.secondsSince1970` dates as bare integers, `.base64` data,
    /// `[String]` photoFilenames as a JSON array). Every wire key is present.
    const FULL_SESSION_JSON: &str = r#"{
        "id": "8E1D7F2A-0000-4000-8000-000000000010",
        "myCallsign": "W6JY",
        "startedAt": 1700000000,
        "endedAt": 1700003600,
        "frequency": 14.062,
        "mode": "CW",
        "activationTypeRawValue": "pota",
        "statusRawValue": "completed",
        "parkReference": "US-1234",
        "sotaReference": "W6/NC-001",
        "wwffReference": "KFF-0001",
        "myGrid": "CM87",
        "power": 10,
        "myRig": "KX2",
        "notes": "windy",
        "qsoComment": "POTA de W6JY",
        "customTitle": "Sunday activation",
        "qsoCount": 42,
        "isRove": false,
        "myAntenna": "EFHW",
        "myKey": "N0SA",
        "myMic": "hand",
        "extraEquipment": "tuner",
        "attendees": "K6ABC",
        "photoFilenames": ["a.jpg", "b.jpg"],
        "spotCommentsData": "AQIDBA==",
        "roveStopsData": "BQYH",
        "solarKIndex": 2.0,
        "solarFlux": 145.0,
        "solarSunspots": 90,
        "solarPropagationRating": "good",
        "solarAIndex": 7,
        "solarBandConditions": "20m open",
        "solarTimestamp": 1699999000,
        "solarConditions": "quiet",
        "weatherTemperatureF": 72.0,
        "weatherTemperatureC": 22.0,
        "weatherHumidity": 40,
        "weatherWindSpeed": 8.5,
        "weatherWindDirection": "NW",
        "weatherDescription": "clear",
        "weatherTimestamp": 1699999500,
        "weather": "clear",
        "stationCallsign": "W6JY/P",
        "operatorCallsignsRawValue": "[\"W6JY\"]"
    }"#;

    #[test]
    fn full_session_json_round_trips_with_identical_key_set() {
        use std::collections::BTreeSet;

        let parsed: LoggingSessionPayload =
            serde_json::from_str(FULL_SESSION_JSON).expect("decodes Swift wire JSON");

        // Representative parse-fidelity assertions.
        assert_eq!(parsed.started_at, 1_700_000_000);
        assert_eq!(parsed.ended_at, Some(1_700_003_600));
        assert_eq!(parsed.frequency, Some(14.062));
        assert_eq!(parsed.qso_count, 42);
        assert_eq!(parsed.photo_filenames, vec!["a.jpg", "b.jpg"]);
        assert_eq!(parsed.spot_comments_data.as_deref(), Some(&[1u8, 2, 3, 4][..]));
        assert_eq!(parsed.rove_stops_data.as_deref(), Some(&[5u8, 6, 7][..]));
        assert_eq!(parsed.operator_callsigns_raw_value, r#"["W6JY"]"#);

        // Re-encode: the key set must be byte-for-byte what Swift emits.
        let expected: serde_json::Value = serde_json::from_str(FULL_SESSION_JSON).unwrap();
        let actual = serde_json::to_value(&parsed).unwrap();
        let expected_keys: BTreeSet<&String> = expected.as_object().unwrap().keys().collect();
        let actual_keys: BTreeSet<&String> = actual.as_object().unwrap().keys().collect();
        assert_eq!(actual_keys, expected_keys, "no dropped/renamed/invented keys");
        assert_eq!(actual, expected, "value-level wire parity");
    }

    #[test]
    fn session_nil_optionals_are_omitted_on_the_wire() {
        // A minimal session leaves every optional nil → Swift `encodeIfPresent`
        // omits them, so the encoded object carries only the required keys.
        let minimal = LoggingSessionPayload {
            id: "s1".into(),
            my_callsign: "W6JY".into(),
            started_at: 1000,
            mode: "SSB".into(),
            activation_type_raw_value: "casual".into(),
            status_raw_value: "active".into(),
            operator_callsigns_raw_value: "[]".into(),
            ..Default::default()
        };
        let value = serde_json::to_value(&minimal).unwrap();
        let obj = value.as_object().unwrap();
        assert!(!obj.contains_key("endedAt"), "nil endedAt omitted");
        assert!(!obj.contains_key("parkReference"), "nil parkReference omitted");
        assert!(!obj.contains_key("spotCommentsData"), "nil data omitted");
        // Required keys always present (incl. the empty photoFilenames array).
        assert!(obj.contains_key("startedAt"));
        assert!(obj.contains_key("qsoCount"));
        assert_eq!(obj.get("photoFilenames").unwrap(), &serde_json::json!([]));
    }

    fn session(id: &str, started_at: i64, ended_at: Option<i64>, status: &str) -> LoggingSessionPayload {
        LoggingSessionPayload {
            id: id.into(),
            my_callsign: "W6JY".into(),
            started_at,
            ended_at,
            mode: "CW".into(),
            activation_type_raw_value: "pota".into(),
            status_raw_value: status.into(),
            operator_callsigns_raw_value: "[]".into(),
            ..Default::default()
        }
    }

    #[test]
    fn session_merge_prefers_newer_by_ended_or_started() {
        // local mod = ended_at (2000); remote mod = ended_at (3000) → remote wins.
        let mut local = session("s1", 1000, Some(2000), "active");
        local.custom_title = Some("local".into());
        local.qso_count = 5;
        let mut remote = session("s1", 1000, Some(3000), "active");
        remote.custom_title = Some("remote".into());
        remote.qso_count = 3;

        let merged = merge_logging_session(&local, &remote, 2000, 3000, 9999);
        assert_eq!(merged.custom_title.as_deref(), Some("remote"), "newer remote wins fields");
        assert_eq!(merged.qso_count, 5, "qso_count takes the max regardless of winner");

        // Local newer → local fields win, count still max.
        let merged_local = merge_logging_session(&local, &remote, 3000, 2000, 9999);
        assert_eq!(merged_local.custom_title.as_deref(), Some("local"));
        assert_eq!(merged_local.qso_count, 5);
    }

    #[test]
    fn session_merge_completed_is_terminal() {
        // Remote is completed but OLDER; completed must still win the status and
        // keep the newer ended_at across both sides.
        let local = session("s1", 1000, Some(5000), "active");
        let remote = session("s1", 1000, Some(2000), "completed");
        let merged = merge_logging_session(&local, &remote, 5000, 2000, 9999);
        assert_eq!(merged.status_raw_value, "completed", "completed is sticky");
        assert_eq!(merged.ended_at, Some(5000), "keeps the newer ended_at");
    }

    #[test]
    fn session_merge_completed_both_nil_uses_fallback() {
        let local = session("s1", 1000, None, "completed");
        let remote = session("s1", 1000, None, "active");
        let merged = merge_logging_session(&local, &remote, 1000, 1000, 7777);
        assert_eq!(merged.status_raw_value, "completed");
        assert_eq!(merged.ended_at, Some(7777), "fallback seeds the terminal ended_at");
    }
}
