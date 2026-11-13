//! WSJT-X → [`Qso`] mapping (CAR-280).
//!
//! WSJT-X emits two UDP messages for every QSO it logs, back-to-back: a
//! structured `QSOLogged` (type 5) and a `LoggedADIF` (type 12) carrying the
//! same QSO as one ADIF record. Both are mapped here into a complete store
//! [`Qso`]; the app-wiring ticket (CAR-282) decides which to persist.
//!
//! Crate placement: `cw-net` (the decoder) and `cw-store` must not depend on
//! each other, so the message structs are plain data in `cw_domain::wsjtx`
//! (re-exported by `cw-net`) and this module — which needs the store's `Qso`
//! — consumes those. The ADIF path is the first Rust ADIF-record → `Qso`
//! mapping ([`qso_from_adif_record`]), a port of the iOS
//! `ImportService.createQSO(from:source:myCallsign:)` kept source-agnostic so
//! a later ADIF-file import can reuse it.
//!
//! # Dedup identity
//!
//! Both paths give the same QSO the same `Qso.id`: a UUIDv5 under
//! [`WSJTX_QSO_NAMESPACE`] of the app-wide deduplication key
//! ([`cw_domain::dedup::deduplication_key`] — `CALLSIGN|BAND|MODE|ts` with the
//! timestamp in 2-minute buckets; the same key the iOS importer compares to
//! skip re-imports). `QSOLogged` and `LoggedADIF` for one QSO carry the same
//! DX call, band, mode and time-on, so they produce the same key and hence the
//! same id — `Store::upsert_qso` (`ON CONFLICT(id) DO UPDATE`) then collapses
//! the pair into one row, the later ADIF message enriching it (`raw_adif`,
//! DXCC, …). [`wsjtx_dedup_key`] exposes the key so CAR-282 can also compare
//! against QSOs that already exist under a different id.
//!
//! Known limit: the band comes from the frequency (`BandUtilities::derive_band`)
//! on the QSOLogged path and from `<band>` on the ADIF path, so on a band the
//! table doesn't know (e.g. 1.25m, 23cm) the two paths disagree on band and
//! therefore on identity.
//!
//! # Provenance
//!
//! `import_source_raw_value` is [`WSJTX_IMPORT_SOURCE`] (`"wsjtx"`), following
//! the store's `ImportSource` raw-value convention (`"logger"`, `"adifFile"`,
//! `"qrz"`, …). Swift's `ImportSource(rawValue:)` falls back to `.logger` for
//! an unknown value, so this is safe until the Swift enum gains `case wsjtx`.

use chrono::{NaiveDate, NaiveTime, TimeZone, Utc};
use cw_domain::adif::{self, AdifRecord};
use cw_domain::dedup::deduplication_key;
use cw_domain::park_reference;
use cw_domain::wsjtx::{band_from_hz, khz_from_hz, store_mode, LoggedAdif, QsoLogged};
use uuid::Uuid;

use crate::qso::Qso;

/// `import_source_raw_value` stamped on every QSO mapped from WSJT-X.
pub const WSJTX_IMPORT_SOURCE: &str = "wsjtx";

/// UUIDv5 namespace for WSJT-X QSO ids. Ids derived under it are persisted;
/// never change this value.
pub const WSJTX_QSO_NAMESPACE: Uuid = Uuid::from_u128(0x2f8c_6d1a_4b3e_5c7f_9a0d_1e2b_3c4d_5e6f);

/// What the store needs that a WSJT-X message does not carry.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WsjtxImportContext {
    /// Operator callsign used when WSJT-X's `my_call` / `STATION_CALLSIGN`
    /// (and `OPERATOR`) are blank — WSJT-X sends them empty when the user has
    /// not filled in Settings → General → My Call.
    pub station_callsign: Option<String>,
    /// Unix seconds stamped into `imported_at`. Caller-supplied so a mapping
    /// is reproducible.
    pub imported_at: i64,
    /// Session to attach the QSO to when WSJT-X runs alongside an activation.
    pub logging_session_id: Option<String>,
}

/// Why a WSJT-X message could not become a QSO.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum WsjtxImportError {
    /// `QSOLogged` carried neither a time-on nor a time-off.
    #[error("WSJT-X QSO has no time on/off")]
    MissingTimestamp,
    /// `QSOLogged` carried a blank DX call.
    #[error("WSJT-X QSO has no DX callsign")]
    MissingCallsign,
    /// `LoggedADIF` parsed to zero records (blank, or every record lacked
    /// `CALL`/`BAND`/`MODE`).
    #[error("LoggedADIF payload contained no parsable QSO record")]
    NoAdifRecords,
    /// An ADIF record had no parsable `QSO_DATE` (+ `TIME_ON`).
    #[error("ADIF record for {callsign} has no parsable QSO_DATE/TIME_ON")]
    MissingAdifTimestamp { callsign: String },
}

/// Map a type-5 `QSOLogged` message to a store QSO.
///
/// Field map: `dx_call` → `callsign`; `tx_frequency_hz` → `freq_khz` + `band`
/// (via `BandUtilities`); `mode` → `mode` (via `cw_domain::wsjtx::store_mode`);
/// `report_sent`/`report_received` → `rst_sent`/`rst_rcvd`; `date_time_on`
/// (fallback `date_time_off`) → `qso_date`; `dx_grid`/`my_grid` →
/// `their_grid`/`my_grid`; `my_call` → `station_callsign`, `operator_call`
/// (fallback `my_call`) → `my_callsign`, both falling back to the context;
/// `tx_power` → `power` (watts); `comments` → `notes`; `name` → `name`;
/// `exchange_sent`/`exchange_received` → `contest_exchange_sent`/`_received`;
/// `adif_propagation_mode` → `prop_mode`. Blank strings become `None`.
pub fn qso_from_qso_logged(
    msg: &QsoLogged,
    ctx: &WsjtxImportContext,
) -> Result<Qso, WsjtxImportError> {
    let callsign = callsign_or_none(&msg.dx_call).ok_or(WsjtxImportError::MissingCallsign)?;
    let qso_date = msg
        .date_time_on
        .or(msg.date_time_off)
        .ok_or(WsjtxImportError::MissingTimestamp)?
        .timestamp();
    let station_callsign = callsign_or_none(&msg.my_call).or_else(|| context_callsign(ctx));
    let my_callsign = callsign_or_none(&msg.operator_call).or_else(|| station_callsign.clone());

    let mut qso = Qso {
        callsign,
        band: band_from_hz(msg.tx_frequency_hz).map(str::to_string),
        mode: store_mode(&msg.mode),
        freq_khz: khz_from_hz(msg.tx_frequency_hz),
        qso_date,
        my_grid: non_empty(&msg.my_grid),
        their_grid: non_empty(&msg.dx_grid),
        rst_sent: non_empty(&msg.report_sent),
        rst_rcvd: non_empty(&msg.report_received),
        my_callsign,
        station_callsign,
        notes: non_empty(&msg.comments),
        name: non_empty(&msg.name),
        power: parse_power(&msg.tx_power),
        contest_exchange_sent: non_empty(&msg.exchange_sent),
        contest_exchange_received: non_empty(&msg.exchange_received),
        prop_mode: non_empty(&msg.adif_propagation_mode),
        ..blank_qso(ctx)
    };
    qso.id = wsjtx_qso_id(&wsjtx_dedup_key(&qso));
    Ok(qso)
}

/// Map a type-12 `LoggedADIF` message to store QSOs — one per `<eor>` record
/// (WSJT-X sends exactly one). Parses with `cw_domain::adif::parse`, then
/// [`qso_from_adif_record`] with [`WSJTX_IMPORT_SOURCE`] provenance.
pub fn qso_from_logged_adif(
    msg: &LoggedAdif,
    ctx: &WsjtxImportContext,
) -> Result<Vec<Qso>, WsjtxImportError> {
    let records = adif::parse(&msg.adif);
    if records.is_empty() {
        return Err(WsjtxImportError::NoAdifRecords);
    }
    records
        .iter()
        .map(|record| qso_from_adif_record(record, WSJTX_IMPORT_SOURCE, ctx))
        .collect()
}

/// Map one parsed ADIF record to a store QSO. Port of the iOS
/// `ImportService.createQSO(from:source:myCallsign:)`: `MY_SIG_INFO` →
/// `park` (multi-park sanitised), `SIG_INFO` → `their_park`, `MY_WWFF_REF` →
/// `wwff_ref`, `COMMENT` → `notes`, `OPERATOR ?? STATION_CALLSIGN ??
/// context` → `my_callsign`, `STATION_CALLSIGN` → `station_callsign`, `FREQ`
/// MHz → `freq_khz`, `QSO_DATE`+`TIME_ON` (`HHMM` or `HHMMSS`, missing time =
/// `0000`) → `qso_date`, the raw record kept in `raw_adif`. Beyond the Swift
/// port it also reads `TX_PWR` → `power`, `STX`/`SRX` → contest serials and
/// `STX_STRING`/`SRX_STRING` → contest exchanges. The iOS comment-park user
/// preference (`CommentParkAction`) is a UI setting and is not applied.
pub fn qso_from_adif_record(
    record: &AdifRecord,
    import_source: &str,
    ctx: &WsjtxImportContext,
) -> Result<Qso, WsjtxImportError> {
    let qso_date = adif_timestamp(record).ok_or_else(|| WsjtxImportError::MissingAdifTimestamp {
        callsign: record.callsign.clone(),
    })?;
    let raw = record.raw_adif.as_str();
    let station_callsign = record
        .station_callsign
        .as_deref()
        .and_then(callsign_or_none)
        .or_else(|| context_callsign(ctx));
    // The parser already prefers OPERATOR over STATION_CALLSIGN here.
    let my_callsign = record
        .my_callsign
        .as_deref()
        .and_then(callsign_or_none)
        .or_else(|| context_callsign(ctx));
    let field = |name: &str| adif::extract_field(name, raw).and_then(|v| non_empty(&v));

    let mut qso = Qso {
        callsign: record.callsign.trim().to_uppercase(),
        band: non_empty(&record.band),
        mode: store_mode(&record.mode),
        freq_khz: record.frequency.map(|mhz| mhz * 1_000.0),
        qso_date,
        my_grid: record.my_gridsquare.as_deref().and_then(non_empty),
        their_grid: record.gridsquare.as_deref().and_then(non_empty),
        rst_sent: record.rst_sent.as_deref().and_then(non_empty),
        rst_rcvd: record.rst_received.as_deref().and_then(non_empty),
        my_callsign,
        station_callsign,
        park: record.my_sig_info.as_deref().and_then(park_reference::sanitize_multi),
        their_park: record.sig_info.as_deref().and_then(park_reference::sanitize),
        notes: record.comment.as_deref().and_then(non_empty),
        import_source_raw_value: import_source.to_string(),
        raw_adif: Some(record.raw_adif.clone()),
        name: record.name.as_deref().and_then(non_empty),
        qth: record.qth.as_deref().and_then(non_empty),
        state: record.state.as_deref().and_then(non_empty),
        country: record.country.as_deref().and_then(non_empty),
        power: field("tx_pwr").as_deref().and_then(parse_power),
        wwff_ref: record.my_wwff_ref.as_deref().and_then(non_empty),
        dxcc: record.dxcc.map(i64::from),
        contest_serial_sent: field("stx").and_then(|v| v.parse().ok()),
        contest_serial_received: field("srx").and_then(|v| v.parse().ok()),
        contest_exchange_sent: field("stx_string"),
        contest_exchange_received: field("srx_string"),
        sat_name: record.sat_name.as_deref().and_then(non_empty),
        prop_mode: record.prop_mode.as_deref().and_then(non_empty),
        ..blank_qso(ctx)
    };
    qso.id = wsjtx_qso_id(&wsjtx_dedup_key(&qso));
    Ok(qso)
}

/// The dedup identity of a mapped QSO: `cw_domain::dedup::deduplication_key`
/// over `callsign`, `band` (blank when unknown), `mode`, `qso_date`. Equal for
/// the `QSOLogged` and `LoggedADIF` messages of one QSO, and comparable with
/// the iOS `QSO.deduplicationKey` of already-stored QSOs.
pub fn wsjtx_dedup_key(qso: &Qso) -> String {
    deduplication_key(
        &qso.callsign,
        qso.band.as_deref().unwrap_or(""),
        qso.mode.as_deref().unwrap_or(""),
        qso.qso_date,
    )
}

/// Deterministic `Qso.id` for a dedup key: UUIDv5 under
/// [`WSJTX_QSO_NAMESPACE`], hyphenated lowercase like the store's v4 ids.
pub fn wsjtx_qso_id(dedup_key: &str) -> String {
    Uuid::new_v5(&WSJTX_QSO_NAMESPACE, dedup_key.as_bytes()).to_string()
}

/// Every field WSJT-X never carries, at its "freshly imported" value. The
/// mappers overwrite the carried ones via struct-update syntax; `id` is
/// replaced with the dedup-derived id once the key fields are known.
fn blank_qso(ctx: &WsjtxImportContext) -> Qso {
    Qso {
        id: String::new(),
        callsign: String::new(),
        band: None,
        mode: None,
        freq_khz: None,
        qso_date: 0,
        my_grid: None,
        their_grid: None,
        rst_sent: None,
        rst_rcvd: None,
        my_callsign: None,
        park: None,
        their_park: None,
        notes: None,
        // Imported notes are the logger's, not typed in this app (Swift import default).
        notes_user_authored: false,
        spot_comments_data: None,
        callsign_change_note: None,
        original_callsign: None,
        import_source_raw_value: WSJTX_IMPORT_SOURCE.to_string(),
        imported_at: ctx.imported_at,
        // Null until the first local edit, like every other import.
        modified_at: None,
        raw_adif: None,
        name: None,
        qth: None,
        state: None,
        country: None,
        power: None,
        my_rig: None,
        station_profile_name: None,
        sota_ref: None,
        wwff_ref: None,
        aoa_code: None,
        qrz_log_id: None,
        qrz_confirmed: false,
        lotw_confirmed_date: None,
        lotw_confirmed: false,
        dxcc: None,
        their_license_class: None,
        contest_name: None,
        contest_serial_sent: None,
        contest_serial_received: None,
        contest_exchange_sent: None,
        contest_exchange_received: None,
        is_hidden: false,
        is_activity_log_qso: false,
        station_callsign: None,
        logging_session_id: ctx.logging_session_id.clone(),
        // A new local QSO: the sync journal must pick it up.
        dirty: true,
        sat_name: None,
        prop_mode: None,
    }
}

/// `QSO_DATE` (`YYYYMMDD`) + `TIME_ON` (`HHMMSS`, `HHMM`, or missing →
/// `0000`) → Unix seconds UTC. Mirrors `ADIFRecord.timestamp` in
/// `ADIFParser.swift`.
fn adif_timestamp(record: &AdifRecord) -> Option<i64> {
    let date = NaiveDate::parse_from_str(record.qso_date.as_deref()?.trim(), "%Y%m%d").ok()?;
    let time_str = record.time_on.as_deref().map(str::trim).unwrap_or("0000");
    let time = if time_str.len() == 6 {
        NaiveTime::parse_from_str(time_str, "%H%M%S")
    } else {
        NaiveTime::parse_from_str(time_str, "%H%M")
    }
    .ok()?;
    Some(Utc.from_utc_datetime(&date.and_time(time)).timestamp())
}

/// WSJT-X `tx_power` / ADIF `TX_PWR` are free text ("50", "50W", "5.5 W");
/// take the leading number as whole watts.
fn parse_power(raw: &str) -> Option<i64> {
    let number: String = raw
        .trim()
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let watts: f64 = number.parse().ok()?;
    Some(watts.round() as i64)
}

fn non_empty(s: &str) -> Option<String> {
    let trimmed = s.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn callsign_or_none(s: &str) -> Option<String> {
    non_empty(s).map(|c| c.to_uppercase())
}

fn context_callsign(ctx: &WsjtxImportContext) -> Option<String> {
    ctx.station_callsign.as_deref().and_then(callsign_or_none)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;
    use chrono::{DateTime, Utc};

    fn ctx() -> WsjtxImportContext {
        WsjtxImportContext {
            station_callsign: Some("w6jy".to_string()),
            imported_at: 1_800_000_000,
            logging_session_id: Some("session-1".to_string()),
        }
    }

    fn time_on() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 3, 14, 18, 30, 15).unwrap()
    }

    fn time_off() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 3, 14, 18, 31, 0).unwrap()
    }

    fn sample_qso_logged() -> QsoLogged {
        QsoLogged {
            id: "WSJT-X".to_string(),
            date_time_off: Some(time_off()),
            dx_call: "K1ABC".to_string(),
            dx_grid: "FN42".to_string(),
            tx_frequency_hz: 14_075_245,
            mode: "FT8".to_string(),
            report_sent: "-10".to_string(),
            report_received: "-05".to_string(),
            tx_power: "50".to_string(),
            comments: "Nice QSO".to_string(),
            name: "Bob".to_string(),
            date_time_on: Some(time_on()),
            operator_call: String::new(),
            my_call: "W6JY".to_string(),
            my_grid: "CM87xx".to_string(),
            exchange_sent: String::new(),
            exchange_received: String::new(),
            adif_propagation_mode: String::new(),
        }
    }

    /// The record WSJT-X writes for the QSO in `sample_qso_logged`.
    const SAMPLE_ADIF: &str = "WSJT-X ADIF Export<eoh>\n\
        <call:5>K1ABC <gridsquare:4>FN42 <mode:3>FT8 <rst_sent:3>-10 <rst_rcvd:3>-05 \
        <qso_date:8>20260314 <time_on:6>183015 <qso_date_off:8>20260314 <time_off:6>183100 \
        <band:3>20m <freq:9>14.075245 <station_callsign:4>W6JY <my_gridsquare:6>CM87xx \
        <tx_pwr:2>50 <comment:8>Nice QSO <name:3>Bob <eor>";

    fn sample_logged_adif() -> LoggedAdif {
        LoggedAdif {
            id: "WSJT-X".to_string(),
            adif: SAMPLE_ADIF.to_string(),
        }
    }

    #[test]
    fn qso_logged_maps_every_field() {
        let qso = qso_from_qso_logged(&sample_qso_logged(), &ctx()).unwrap();

        assert_eq!(qso.callsign, "K1ABC");
        assert_eq!(qso.band.as_deref(), Some("20m"));
        assert_eq!(qso.mode.as_deref(), Some("FT8"));
        assert_eq!(qso.freq_khz, Some(14_075.245));
        assert_eq!(qso.qso_date, time_on().timestamp());
        assert_eq!(qso.my_grid.as_deref(), Some("CM87xx"));
        assert_eq!(qso.their_grid.as_deref(), Some("FN42"));
        assert_eq!(qso.rst_sent.as_deref(), Some("-10"));
        assert_eq!(qso.rst_rcvd.as_deref(), Some("-05"));
        assert_eq!(qso.my_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.station_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.notes.as_deref(), Some("Nice QSO"));
        assert!(!qso.notes_user_authored);
        assert_eq!(qso.name.as_deref(), Some("Bob"));
        assert_eq!(qso.power, Some(50));
        assert_eq!(qso.contest_exchange_sent, None);
        assert_eq!(qso.contest_exchange_received, None);
        assert_eq!(qso.prop_mode, None);
        assert_eq!(qso.park, None);
        assert_eq!(qso.raw_adif, None);

        // Provenance + context-supplied fields.
        assert_eq!(qso.import_source_raw_value, WSJTX_IMPORT_SOURCE);
        assert_eq!(qso.imported_at, 1_800_000_000);
        assert_eq!(qso.modified_at, None);
        assert_eq!(qso.logging_session_id.as_deref(), Some("session-1"));
        assert!(qso.dirty);
        assert!(!qso.is_hidden);

        // Identity: the Swift-shaped dedup key (18:30:15 → 18:30:00 bucket).
        let bucket = Utc.with_ymd_and_hms(2026, 3, 14, 18, 30, 0).unwrap().timestamp();
        let key = wsjtx_dedup_key(&qso);
        assert_eq!(key, format!("K1ABC|20M|FT8|{bucket}"));
        assert_eq!(qso.id, wsjtx_qso_id(&key));
        assert_eq!(qso.id, wsjtx_qso_id(&key), "id derivation is deterministic");
        assert!(Uuid::parse_str(&qso.id).is_ok());
    }

    #[test]
    fn qso_logged_exchange_prop_mode_and_operator() {
        let msg = QsoLogged {
            operator_call: "n0call".to_string(),
            exchange_sent: "579 CA".to_string(),
            exchange_received: "599 MA".to_string(),
            adif_propagation_mode: "ES".to_string(),
            ..sample_qso_logged()
        };
        let qso = qso_from_qso_logged(&msg, &ctx()).unwrap();
        assert_eq!(qso.my_callsign.as_deref(), Some("N0CALL"));
        assert_eq!(qso.station_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.contest_exchange_sent.as_deref(), Some("579 CA"));
        assert_eq!(qso.contest_exchange_received.as_deref(), Some("599 MA"));
        assert_eq!(qso.prop_mode.as_deref(), Some("ES"));
    }

    #[test]
    fn qso_logged_falls_back_to_context_callsign_and_time_off() {
        let msg = QsoLogged {
            my_call: String::new(),
            operator_call: String::new(),
            date_time_on: None,
            tx_frequency_hz: 0,
            ..sample_qso_logged()
        };
        let qso = qso_from_qso_logged(&msg, &ctx()).unwrap();
        assert_eq!(qso.station_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.my_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.qso_date, time_off().timestamp());
        assert_eq!(qso.freq_khz, None);
        assert_eq!(qso.band, None);

        let no_ctx = WsjtxImportContext::default();
        let qso = qso_from_qso_logged(&msg, &no_ctx).unwrap();
        assert_eq!(qso.station_callsign, None);
        assert_eq!(qso.my_callsign, None);
        assert_eq!(qso.logging_session_id, None);
    }

    #[test]
    fn qso_logged_requires_callsign_and_timestamp() {
        let blank_call = QsoLogged { dx_call: "  ".to_string(), ..sample_qso_logged() };
        assert_eq!(
            qso_from_qso_logged(&blank_call, &ctx()),
            Err(WsjtxImportError::MissingCallsign)
        );
        let no_time = QsoLogged {
            date_time_on: None,
            date_time_off: None,
            ..sample_qso_logged()
        };
        assert_eq!(
            qso_from_qso_logged(&no_time, &ctx()),
            Err(WsjtxImportError::MissingTimestamp)
        );
    }

    #[test]
    fn logged_adif_maps_realistic_wsjtx_record() {
        let qsos = qso_from_logged_adif(&sample_logged_adif(), &ctx()).unwrap();
        assert_eq!(qsos.len(), 1);
        let qso = &qsos[0];

        assert_eq!(qso.callsign, "K1ABC");
        assert_eq!(qso.band.as_deref(), Some("20m"));
        assert_eq!(qso.mode.as_deref(), Some("FT8"));
        assert_eq!(qso.freq_khz, Some(14_075.245));
        assert_eq!(qso.qso_date, time_on().timestamp());
        assert_eq!(qso.my_grid.as_deref(), Some("CM87xx"));
        assert_eq!(qso.their_grid.as_deref(), Some("FN42"));
        assert_eq!(qso.rst_sent.as_deref(), Some("-10"));
        assert_eq!(qso.rst_rcvd.as_deref(), Some("-05"));
        assert_eq!(qso.my_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.station_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.notes.as_deref(), Some("Nice QSO"));
        assert_eq!(qso.name.as_deref(), Some("Bob"));
        assert_eq!(qso.power, Some(50));
        assert_eq!(qso.import_source_raw_value, WSJTX_IMPORT_SOURCE);
        assert_eq!(qso.imported_at, 1_800_000_000);
        assert_eq!(qso.logging_session_id.as_deref(), Some("session-1"));
        assert!(qso.dirty);
        // The header is stripped; the record itself is kept (in the parser's
        // `<…<eor>` re-framing, as every other imported QSO's raw_adif is).
        let raw = qso.raw_adif.as_deref().unwrap();
        assert!(raw.contains("<call:5>K1ABC <gridsquare:4>FN42"), "{raw}");
        assert!(raw.contains("<tx_pwr:2>50"), "{raw}");
        assert!(raw.ends_with("<eor>"), "{raw}");
        assert!(!raw.contains("<eoh>"), "{raw}");
    }

    #[test]
    fn adif_record_extras_parks_dxcc_contest_and_hhmm_time() {
        let adif = "<call:4>W1AW <band:3>40m <mode:4>MFSK <submode:3>FT4 <freq:8>7.047500 \
            <qso_date:8>20260314 <time_on:4>1830 <operator:5>N0CAL <station_callsign:4>W6JY \
            <my_sig_info:7>US-1234 <sig_info:7>US-0001 <my_wwff_ref:8>KFF-0001 <dxcc:3>291 \
            <state:2>CT <country:13>United States <stx:2>12 <srx:3>345 <stx_string:2>CA \
            <srx_string:2>MA <tx_pwr:6>5.5 W <eor>";
        let qsos = qso_from_logged_adif(
            &LoggedAdif { id: "WSJT-X".to_string(), adif: adif.to_string() },
            &ctx(),
        )
        .unwrap();
        let qso = &qsos[0];
        assert_eq!(qso.mode.as_deref(), Some("FT4"), "submode wins over MFSK");
        assert_eq!(qso.freq_khz, Some(7_047.5));
        assert_eq!(
            qso.qso_date,
            Utc.with_ymd_and_hms(2026, 3, 14, 18, 30, 0).unwrap().timestamp()
        );
        assert_eq!(qso.my_callsign.as_deref(), Some("N0CAL"), "OPERATOR wins");
        assert_eq!(qso.station_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.park.as_deref(), Some("US-1234"));
        assert_eq!(qso.their_park.as_deref(), Some("US-0001"));
        assert_eq!(qso.wwff_ref.as_deref(), Some("KFF-0001"));
        assert_eq!(qso.dxcc, Some(291));
        assert_eq!(qso.state.as_deref(), Some("CT"));
        assert_eq!(qso.country.as_deref(), Some("United States"));
        assert_eq!(qso.contest_serial_sent, Some(12));
        assert_eq!(qso.contest_serial_received, Some(345));
        assert_eq!(qso.contest_exchange_sent.as_deref(), Some("CA"));
        assert_eq!(qso.contest_exchange_received.as_deref(), Some("MA"));
        assert_eq!(qso.power, Some(6));
    }

    #[test]
    fn logged_adif_errors() {
        let empty = LoggedAdif { id: "WSJT-X".to_string(), adif: "WSJT-X<eoh>".to_string() };
        assert_eq!(
            qso_from_logged_adif(&empty, &ctx()),
            Err(WsjtxImportError::NoAdifRecords)
        );
        let no_date = LoggedAdif {
            id: "WSJT-X".to_string(),
            adif: "<call:5>K1ABC <band:3>20m <mode:3>FT8 <eor>".to_string(),
        };
        assert_eq!(
            qso_from_logged_adif(&no_date, &ctx()),
            Err(WsjtxImportError::MissingAdifTimestamp { callsign: "K1ABC".to_string() })
        );
    }

    #[test]
    fn both_paths_yield_the_same_identity_and_collapse_to_one_row() {
        let from_logged = qso_from_qso_logged(&sample_qso_logged(), &ctx()).unwrap();
        let from_adif = qso_from_logged_adif(&sample_logged_adif(), &ctx()).unwrap().remove(0);

        assert_eq!(wsjtx_dedup_key(&from_logged), wsjtx_dedup_key(&from_adif));
        assert_eq!(from_logged.id, from_adif.id);
        // Everything both messages carry agrees; the ADIF path adds raw_adif.
        assert_eq!(
            Qso { raw_adif: None, ..from_adif.clone() },
            from_logged,
            "the two paths disagree on a shared field"
        );

        // The pair upserts into a single row, the later message enriching it.
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&from_logged).unwrap();
        store.upsert_qso(&from_adif).unwrap();
        assert_eq!(store.qso_count().unwrap(), 1);
        let stored = store.fetch_qso(&from_logged.id).unwrap().unwrap();
        assert!(stored.raw_adif.is_some());
        assert_eq!(stored.import_source_raw_value, WSJTX_IMPORT_SOURCE);
    }

    #[test]
    fn ft4_identity_agrees_across_paths_via_submode() {
        let logged = QsoLogged {
            mode: "FT4".to_string(),
            tx_frequency_hz: 7_047_500,
            ..sample_qso_logged()
        };
        let adif = LoggedAdif {
            id: "WSJT-X".to_string(),
            adif: "<call:5>K1ABC <band:3>40m <mode:4>MFSK <submode:3>FT4 <freq:8>7.047500 \
                <qso_date:8>20260314 <time_on:6>183015 <station_callsign:4>W6JY <eor>"
                .to_string(),
        };
        let a = qso_from_qso_logged(&logged, &ctx()).unwrap();
        let b = qso_from_logged_adif(&adif, &ctx()).unwrap().remove(0);
        assert_eq!(a.mode.as_deref(), Some("FT4"));
        assert_eq!(a.id, b.id);
    }

    #[test]
    fn power_parsing_table() {
        let cases: &[(&str, Option<i64>)] = &[
            ("50", Some(50)),
            ("50W", Some(50)),
            (" 5.5 W ", Some(6)),
            ("100.0", Some(100)),
            ("", None),
            ("QRP", None),
        ];
        for (raw, expected) in cases {
            assert_eq!(parse_power(raw), *expected, "parse_power({raw:?})");
        }
    }
}
