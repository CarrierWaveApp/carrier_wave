//! Store-backed ADIF export surface (`AdifApi`). Mirrors the iOS POTA
//! single-activation export path: `ADIFExportSheet` →
//! `ADIFExportService.generateADIF` (`swift/ios/CarrierWave/Views/
//! POTAActivations/ADIFExportSheet.swift` + `Services/ADIFExportService.swift`),
//! with the writer itself living in [`cw_domain::adif_writer`] (ported in Task
//! 3). This object only does the store side: resolve the activation's QSO rows,
//! map each `qso` row onto an [`AdifWriteRecord`], and hand the pre-sorted list
//! to [`write_adif`].
//!
//! ## The bound option set (from `ADIFExportSheet` / `generateADIF`)
//!
//! The sheet exports exactly ONE POTA activation, identified — like
//! `POTAActivation.groupQSOs` (`Models/POTAActivation.swift:237-275`) — by
//! `(parkReference, callsign, UTC date)`. `generateADIF`'s parameters are
//! `parkReference`, `parkName?`, and `activatorCallsign`; the QSOs are the
//! activation's own (`activation.qsos`). There are no date-RANGE or per-field
//! toggles in this sheet — the only "filters" are the activation identity
//! itself. [`AdifApi::export_activation`] binds those exactly:
//!
//! - `park_reference` → `parkReference` (also the `activatorCallsign`'s scope).
//! - `callsign` → `activatorCallsign` + the `my_callsign` scope column.
//! - `date` (`yyyy-MM-dd`, UTC) → the activation's `utcDate`; expanded to the
//!   half-open `[startOfDay, startOfDay+24h)` UTC window the grouping uses.
//! - `park_name` → `parkName?` (header comment only).
//! - `program_version` → `CFBundleShortVersionString` (`generateADIF` reads
//!   `Bundle.main`; off-Apple callers supply the marketing version).
//!
//! The `<EOH>` header's `first_qso_date` and the `CREATED_TIMESTAMP` are
//! derived here in UTC (chrono) to the exact formats `write_adif` documents —
//! see the field-mapping notes on [`row_to_write_record`].

use std::sync::Arc;

use chrono::{DateTime, NaiveDate, TimeZone, Utc};
use uuid::Uuid;

use cw_domain::adif;
use cw_domain::adif_writer::{
    write_adif, write_bulk_adif, write_session_adif, AdifBulkActivation, AdifHeaderOpts, AdifSessionHeaderOpts,
    AdifSessionRecord, AdifWriteRecord,
};
use cw_domain::dedup::deduplication_key;
use cw_domain::mode::is_metadata_mode;
use cw_domain::service_type::ServiceType;
use cw_store::{
    filter_for_multi_op, qso_from_adif_record, Qso, WsjtxImportContext, ADIF_FILE_IMPORT_SOURCE, MAX_FETCH_LIMIT,
};

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::upload::mark_needs_upload;
use crate::{CwError, FieldStore};

/// Host-supplied context for [`AdifApi::import_adif`] — the pieces of the iOS
/// `ADIFImportModifier` → `ImportService.importADIF` flow that come from app
/// state rather than the file.
#[derive(uniffi::Record)]
pub struct FfiAdifImportOptions {
    /// The operator's own callsign (`CallsignAliasService.getCurrentCallsign()`
    /// on iOS). Drives the multi-op filter, fills `my_callsign` for records
    /// without `OPERATOR`/`STATION_CALLSIGN`, and gates upload markers to the
    /// primary callsign's QSOs. May be empty.
    pub my_callsign: String,
    /// Mark imported QSOs as needing a QRZ upload (iOS: QRZ is in
    /// `ServiceConfiguration.configuredUploadServices()`).
    pub upload_qrz: bool,
    /// Mark imported QSOs that carry a `MY_SIG_INFO` park as needing a POTA
    /// upload (iOS: POTA configured + `parkReference` non-empty).
    pub upload_pota: bool,
}

/// Outcome of one [`AdifApi::import_adif`] call. Mirrors
/// `ImportService.ImportResult`: `errors` includes records the multi-op
/// filter dropped, as the Swift `errors + skipped` does.
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct FfiAdifImportResult {
    /// Records parsed from the file (every `<EOR>` with `CALL`/`BAND`/`MODE`).
    pub total_records: u32,
    /// Records inserted as new QSOs.
    pub imported: u32,
    /// Records skipped because their dedup key was already in the store or
    /// earlier in the same file.
    pub duplicates: u32,
    /// Records that could not become a QSO (no parsable `QSO_DATE`) plus
    /// records the multi-op filter dropped.
    pub errors: u32,
}

/// One activation to include in an [`AdifApi::export_bulk`] call. Same
/// activation identity tuple `export_activation` takes — `(park_reference,
/// callsign, date)` — plus the optional `park_name` header comment.
#[derive(uniffi::Record)]
pub struct FfiAdifBulkActivationRef {
    pub park_reference: String,
    pub park_name: Option<String>,
    pub callsign: String,
    /// `yyyy-MM-dd`, UTC.
    pub date: String,
}

/// One logging session rendered to ADIF by [`AdifApi::export_session`], plus
/// the facts a host needs to name and describe the file without re-reading
/// the store.
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct FfiAdifSessionExport {
    /// The rendered file (header + `<EOH>` + one record per QSO).
    pub adif: String,
    /// Records written — the session's visible, non-metadata QSOs.
    pub qso_count: u32,
    /// Unix seconds (UTC) of the earliest exported QSO; `None` when empty.
    pub first_qso_date: Option<i64>,
}

/// Store-backed ADIF export API bound to a [`FieldStore`]. Stateless — every
/// call reads straight from the store, mirroring [`crate::map_api::MapApi`] /
/// [`crate::session_api::SessionApi`].
#[derive(uniffi::Object)]
pub struct AdifApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl AdifApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        AdifApi { store }
    }

    /// Export one POTA activation to ADIF text. Resolves the activation's QSO
    /// rows — `(park_reference, callsign, date)` scoped, non-metadata, visible,
    /// pre-sorted chronologically by the store — maps them to writer records,
    /// and renders via [`write_adif`].
    ///
    /// `date` is `yyyy-MM-dd` UTC (the `POTAActivation.utcDateString`).
    /// `program_version` is the app's marketing version
    /// (`CFBundleShortVersionString`). An empty activation still produces a
    /// valid header + `<EOH>` with `first_qso_date = "unknown"`
    /// (`buildHeader`:351).
    pub fn export_activation(
        &self,
        park_reference: String,
        park_name: Option<String>,
        callsign: String,
        date: String,
        program_version: String,
    ) -> Result<String, CwError> {
        let (day_start, day_end) = utc_day_window(&date)
            .ok_or_else(|| CwError::Store { reason: format!("invalid activation date: {date}") })?;

        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_activation_qsos(&park_reference, &callsign, day_start, day_end)?;
        drop(store);

        // Rows arrive `qso_date ASC` from the store, matching Swift's
        // `sorted { $0.timestamp < $1.timestamp }`. `first_qso_date` is the
        // first (earliest) row's date; "unknown" when the activation is empty.
        let first_qso_date = rows
            .first()
            .map(|r| format_utc(r.qso_date, "%Y-%m-%d"))
            .unwrap_or_else(|| "unknown".to_string());

        let header = AdifHeaderOpts {
            park_reference: park_reference.clone(),
            park_name,
            activator_callsign: callsign,
            first_qso_date,
            program_version,
            created_timestamp: format_utc(Utc::now().timestamp(), "%Y%m%d %H%M%S"),
        };

        let records: Vec<AdifWriteRecord> = rows.iter().map(row_to_write_record).collect();
        Ok(write_adif(&records, &header))
    }

    /// Export every QSO of one logging session to ADIF text. Scoped by
    /// `logging_session_id` — NOT by the `(park, callsign, UTC day)` tuple
    /// [`Self::export_activation`] uses — so a merged session that spans UTC
    /// midnight or two parks, a rove, or casual QSOs merged into a park
    /// session all land in one file. Visible, non-metadata rows only,
    /// `qso_date` ASC, bounded by the store's `MAX_FETCH_LIMIT`.
    ///
    /// Each record's POTA block uses the QSO's own park when it has one and
    /// otherwise the session's `park_reference`; a record with neither gets no
    /// `MY_SIG`/`MY_POTA_REF` block (park-to-park fields still go out). The
    /// session's `sota_reference` is written as `MY_SOTA_REF` on every record.
    /// The activator callsign is the session's `station_callsign`, falling
    /// back to `my_callsign` (the iOS `SessionADIFExportSheet` rule). `None`
    /// when no session has that id.
    pub fn export_session(
        &self,
        session_id: String,
        park_name: Option<String>,
        program_version: String,
    ) -> Result<Option<FfiAdifSessionExport>, CwError> {
        let (session, mut rows) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(session) = store.fetch_logging_session(&session_id)? else {
                return Ok(None);
            };
            let rows = store.fetch_qsos_for_session(&session_id, None, MAX_FETCH_LIMIT)?;
            (session, rows)
        };
        rows.retain(|qso| !qso.mode.as_deref().map(is_metadata_mode).unwrap_or(false));
        // The store hands the session back newest-first; the file is chronological.
        rows.sort_by_key(|qso| qso.qso_date);

        let session_park = session.park_reference.as_deref().and_then(non_blank);
        let activator_callsign = session
            .station_callsign
            .as_deref()
            .and_then(non_blank)
            .unwrap_or_else(|| session.my_callsign.clone());
        let first_qso_date = rows.first().map(|row| row.qso_date);

        let header = AdifSessionHeaderOpts {
            activator_callsign,
            park_reference: session_park.clone(),
            park_name,
            sota_reference: session.sota_reference.as_deref().and_then(non_blank),
            first_qso_date: first_qso_date
                .map(|date| format_utc(date, "%Y-%m-%d"))
                .unwrap_or_else(|| "unknown".to_string()),
            program_version,
            created_timestamp: format_utc(Utc::now().timestamp(), "%Y%m%d %H%M%S"),
        };
        let records: Vec<AdifSessionRecord> = rows
            .iter()
            .map(|row| AdifSessionRecord {
                record: row_to_write_record(row),
                park_reference: row.park.as_deref().and_then(non_blank).or_else(|| session_park.clone()),
            })
            .collect();

        Ok(Some(FfiAdifSessionExport {
            adif: write_session_adif(&records, &header),
            qso_count: records.len() as u32,
            first_qso_date,
        }))
    }

    /// Export multiple POTA activations to one combined ADIF file. Port of
    /// `ADIFExportService.generateBulkADIF`'s "combined" mode — each
    /// activation's QSOs are resolved with the same `(park_reference,
    /// callsign, date)` scoping [`Self::export_activation`] uses, mapped to
    /// writer records, and handed to [`write_bulk_adif`] together with a
    /// single shared `CREATED_TIMESTAMP`.
    ///
    /// Swift's "split" bulk mode (one ADIF file per park, produced client-side
    /// by re-slicing the combined export) is intentionally NOT bound here —
    /// left as a Task 11 follow-up if Android needs per-park files.
    pub fn export_bulk(
        &self,
        activations: Vec<FfiAdifBulkActivationRef>,
        program_version: String,
    ) -> Result<String, CwError> {
        let created_timestamp = format_utc(Utc::now().timestamp(), "%Y%m%d %H%M%S");

        let store = self.store.inner.lock().expect("store mutex poisoned");
        let mut bulk_activations = Vec::with_capacity(activations.len());
        for activation in &activations {
            let (day_start, day_end) = utc_day_window(&activation.date).ok_or_else(|| CwError::Store {
                reason: format!("invalid activation date: {}", activation.date),
            })?;
            let rows = store.fetch_activation_qsos(
                &activation.park_reference,
                &activation.callsign,
                day_start,
                day_end,
            )?;
            let records: Vec<AdifWriteRecord> = rows.iter().map(row_to_write_record).collect();
            bulk_activations.push(AdifBulkActivation {
                records,
                park_reference: activation.park_reference.clone(),
                park_name: activation.park_name.clone(),
            });
        }
        drop(store);

        Ok(write_bulk_adif(&bulk_activations, &program_version, &created_timestamp))
    }

    /// Resolve one activation's QSO rows for the UI (timeline + header stats) —
    /// the same `(park_reference, callsign, UTC-day)` scope
    /// [`Self::export_activation`] uses, but returning the QSO records instead of
    /// rendered ADIF. Backs the Android activation-detail screen, which lacks a
    /// session id and so can't use `SessionApi`.
    ///
    /// Unlike a bare `park:… date:…` DSL query, this scopes on the operator's own
    /// callsign too (matching iOS's `POTAActivation` grouping key), so two of the
    /// user's own callsigns activating the same park on the same day stay
    /// separate. Non-metadata, visible (`is_hidden = 0`) rows only, `qso_date` ASC,
    /// bounded by the store's `MAX_FETCH_LIMIT`. `date` is `yyyy-MM-dd` UTC.
    pub fn fetch_activation_qsos(
        &self,
        park_reference: String,
        callsign: String,
        date: String,
    ) -> Result<Vec<crate::FfiQso>, CwError> {
        let (day_start, day_end) = utc_day_window(&date)
            .ok_or_else(|| CwError::Store { reason: format!("invalid activation date: {date}") })?;

        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_activation_qsos(&park_reference, &callsign, day_start, day_end)?;
        Ok(rows.into_iter().map(crate::FfiQso::from).collect())
    }

    /// Import an ADIF file's text into the logbook. Port of the iOS
    /// `ImportService.importADIF(content:source:myCallsign:)` with
    /// `source = .adifFile`, so Swift and Kotlin share one importer:
    ///
    /// 1. `cw_domain::adif::parse` — one record per `<EOR>` that has
    ///    `CALL`/`BAND`/`MODE`.
    /// 2. [`filter_for_multi_op`] — in a multi-operator log keep only this
    ///    operator's (and unattributed) records; dropped ones count as errors.
    /// 3. [`qso_from_adif_record`] — the shared record→`Qso` mapping, with
    ///    `my_callsign` as the station fallback; a record with no parsable
    ///    `QSO_DATE` is an error. Each new row gets a fresh v4 id (not the
    ///    WSJT-X key-derived id) so re-imports are *reported* as duplicates
    ///    rather than silently upserting.
    /// 4. Dedup — a record whose [`deduplication_key`] is already in the store
    ///    (`Store::deduplication_keys`, hidden rows included) or earlier in
    ///    this file is skipped and counted.
    /// 5. Insert every surviving row in one transaction; mark QRZ/POTA upload
    ///    presences per `options` (primary-callsign, non-metadata QSOs only;
    ///    POTA only with a park), then notify observers once per table.
    ///
    /// Reads the whole file into memory; hosts should run this off the main
    /// thread (it holds the store lock for the duration of the insert).
    pub fn import_adif(
        &self,
        content: String,
        options: FfiAdifImportOptions,
    ) -> Result<FfiAdifImportResult, CwError> {
        let records = adif::parse(&content);
        let total_records = records.len();
        let kept = filter_for_multi_op(&records, &options.my_callsign);
        let skipped = total_records - kept.len();

        let ctx = WsjtxImportContext {
            station_callsign: non_blank(&options.my_callsign),
            imported_at: Utc::now().timestamp(),
            logging_session_id: None,
        };

        let mut errors = skipped;
        let mut duplicates = 0usize;
        let mut wrote_presence = false;
        let imported;
        {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let mut seen = store.deduplication_keys()?;
            let mut to_insert: Vec<Qso> = Vec::new();
            for record in kept {
                let mut qso = match qso_from_adif_record(record, ADIF_FILE_IMPORT_SOURCE, &ctx) {
                    Ok(qso) => qso,
                    Err(_) => {
                        errors += 1;
                        continue;
                    }
                };
                let key = deduplication_key(
                    &qso.callsign,
                    qso.band.as_deref().unwrap_or(""),
                    qso.mode.as_deref().unwrap_or(""),
                    qso.qso_date,
                );
                if !seen.insert(key) {
                    duplicates += 1;
                    continue;
                }
                qso.id = Uuid::new_v4().to_string();
                to_insert.push(qso);
            }
            imported = to_insert.len();

            store.in_transaction_with(|| -> Result<(), CwError> {
                for qso in &to_insert {
                    store.upsert_qso(qso)?;
                    wrote_presence |= mark_import_for_upload(&store, qso, &options)?;
                }
                Ok(())
            })?;
        }

        if imported > 0 {
            self.store.notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        }
        if wrote_presence {
            self.store.notify(FfiStoreChange {
                table: FfiStoreTable::ServicePresence,
                kind: FfiChangeKind::Upsert,
            });
        }

        Ok(FfiAdifImportResult {
            total_records: total_records as u32,
            imported: imported as u32,
            duplicates: duplicates as u32,
            errors: errors as u32,
        })
    }
}

/// `ImportService.createServicePresenceRecords(for:importedFrom: nil)` for a
/// file import: needs-upload markers only for the services the host says are
/// configured, only for non-metadata QSOs whose `my_callsign` is blank or
/// equals the primary callsign, and POTA only when the QSO has a park.
fn mark_import_for_upload(
    store: &cw_store::Store,
    qso: &Qso,
    options: &FfiAdifImportOptions,
) -> Result<bool, CwError> {
    if !(options.upload_qrz || options.upload_pota) {
        return Ok(false);
    }
    if qso.mode.as_deref().map(is_metadata_mode).unwrap_or(false) {
        return Ok(false);
    }
    let primary = options.my_callsign.trim().to_uppercase();
    let matches_primary = match qso.my_callsign.as_deref().map(str::trim) {
        None | Some("") => true,
        Some(mine) => primary.is_empty() || mine.to_uppercase() == primary,
    };
    if !matches_primary {
        return Ok(false);
    }
    let mut wrote = false;
    if options.upload_qrz {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Qrz)?;
    }
    if options.upload_pota && qso.park.as_deref().is_some_and(|p| !p.is_empty()) {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Pota)?;
    }
    Ok(wrote)
}

fn non_blank(s: &str) -> Option<String> {
    let trimmed = s.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

/// Format a UTC unix-seconds timestamp with a chrono strftime pattern. Matches
/// the Swift `DateFormatter` + `TimeZone(identifier: "UTC")` the export uses
/// for every date/time field (`ADIFExportService.swift:241-246,296-309`, plus
/// `buildHeader` and `generateBulkADIF`). Callers pass the exact format
/// `write_adif` documents for each field.
fn format_utc(unix_seconds: i64, fmt: &str) -> String {
    DateTime::<Utc>::from_timestamp(unix_seconds, 0)
        .unwrap_or_else(Utc::now)
        .format(fmt)
        .to_string()
}

/// Expand a `yyyy-MM-dd` UTC date into the half-open `[start, start+24h)`
/// unix-seconds window. `None` when the string isn't a valid date. Uses a flat
/// 86_400s day — the activation grouping is a calendar-day bucket and the
/// store timestamps are UTC unix seconds, so no DST math applies (UTC has no
/// DST).
fn utc_day_window(date: &str) -> Option<(i64, i64)> {
    let day = NaiveDate::parse_from_str(date, "%Y-%m-%d").ok()?;
    let start = Utc.from_utc_datetime(&day.and_hms_opt(0, 0, 0)?).timestamp();
    Some((start, start + 86_400))
}

/// Map a store `qso` row onto an [`AdifWriteRecord`]. Field-by-field mirror of
/// `QSOExportSnapshot(from:)` (`ADIFExportService.swift:16-48`) plus the format
/// conversions the Swift writer applied downstream:
///
/// - `band`/`mode`/`my_callsign` are `Option` in the store but non-optional
///   (`""`-defaulted) on the `@Model` — unwrapped to `""` so the writer's
///   `!isEmpty` guards behave identically.
/// - `freq_khz` (kHz) → `frequency` (MHz): `/ 1000.0`, matching the SwiftData
///   `frequency` accessor (`QSOFields+FieldStore.swift:106`,
///   `FfiReflector.swift:94`). The writer prints `%.6f` MHz.
/// - `qso_date` → `qso_date` `yyyyMMdd` UTC, `time_on` `HHmmss` UTC — the exact
///   formats `appendCoreFields` used (`:241-246`).
/// - `lotw_confirmed_date` (unix seconds) → `yyyyMMdd` UTC
///   (`appendConfirmationFields`:305). `None` → `None` (writer skips
///   `LOTW_QSLRDATE`).
/// - `power` (`i64`) → `i32`; `dxcc` (`i64`) → `i32` — plain truncating `as`
///   casts (not saturating); safe because real values (watts, DXCC entity
///   numbers, contest serials) are always far below `i32::MAX`.
/// - `park` (the operator's own POTA ref) is the header/`MY_SIG_INFO` park, so
///   it is NOT copied onto the record; `their_park` → `their_park_reference`.
fn row_to_write_record(qso: &Qso) -> AdifWriteRecord {
    AdifWriteRecord {
        callsign: qso.callsign.clone(),
        band: qso.band.clone().unwrap_or_default(),
        mode: qso.mode.clone().unwrap_or_default(),
        frequency: qso.freq_khz.map(|khz| khz / 1000.0),
        qso_date: format_utc(qso.qso_date, "%Y%m%d"),
        time_on: format_utc(qso.qso_date, "%H%M%S"),
        rst_sent: qso.rst_sent.clone(),
        rst_received: qso.rst_rcvd.clone(),
        my_callsign: qso.my_callsign.clone().unwrap_or_default(),
        my_grid: qso.my_grid.clone(),
        their_grid: qso.their_grid.clone(),
        their_park_reference: qso.their_park.clone(),
        notes: qso.notes.clone(),
        name: qso.name.clone(),
        qth: qso.qth.clone(),
        state: qso.state.clone(),
        country: qso.country.clone(),
        power: qso.power.map(|p| p as i32),
        my_rig: qso.my_rig.clone(),
        sota_ref: qso.sota_ref.clone(),
        dxcc: qso.dxcc.map(|d| d as i32),
        qrz_confirmed: qso.qrz_confirmed,
        lotw_confirmed: qso.lotw_confirmed,
        lotw_confirmed_date: qso.lotw_confirmed_date.map(|ts| format_utc(ts, "%Y%m%d")),
        station_callsign: qso.station_callsign.clone(),
        contest_name: qso.contest_name.clone(),
        contest_serial_sent: qso.contest_serial_sent.map(|s| s as i32),
        contest_serial_received: qso.contest_serial_received.map(|s| s as i32),
        contest_exchange_sent: qso.contest_exchange_sent.clone(),
        contest_exchange_received: qso.contest_exchange_received.clone(),
        sat_name: qso.sat_name.clone(),
        prop_mode: qso.prop_mode.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cw_domain::adif_writer::{write_adif, AdifHeaderOpts};

    // A store-backed AdifApi over an in-memory store. Mirrors the harness used
    // by the other store-backed API tests (`map_api`, `session_api`).
    fn api_with_store() -> (AdifApi, Arc<FieldStore>) {
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        (AdifApi::new(store.clone()), store)
    }

    // Build a Qso row with the fields the export reads; defaults elsewhere.
    fn qso_row(id: &str, park: &str, my_call: &str, qso_date: i64) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: "K1JT".to_string(),
            band: Some("20m".to_string()),
            mode: Some("FT8".to_string()),
            freq_khz: Some(14_074.0),
            qso_date,
            my_grid: Some("cm87".to_string()),
            their_grid: Some("fn31".to_string()),
            rst_sent: Some("-05".to_string()),
            rst_rcvd: Some("-12".to_string()),
            my_callsign: Some(my_call.to_string()),
            park: Some(park.to_string()),
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: String::new(),
            imported_at: qso_date,
            modified_at: None,
            raw_adif: None,
            name: None,
            qth: None,
            state: None,
            country: None,
            power: Some(5),
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
            logging_session_id: None,
            dirty: false,
            sat_name: None,
            prop_mode: None,
        }
    }

    // 2026-01-15 14:30:00 UTC and 15:00:00 UTC.
    const TS_1430: i64 = 1_768_487_400;
    const TS_1500: i64 = 1_768_489_200;

    fn insert(store: &Arc<FieldStore>, qso: &Qso) {
        let s = store.inner.lock().unwrap();
        s.upsert_qso(qso).expect("insert qso");
    }

    #[test]
    fn export_matches_task3_writer_byte_for_byte() {
        let (api, store) = api_with_store();
        // Two QSOs in the same activation, inserted out of chronological order
        // to prove the store's ASC sort feeds the writer in QSO order.
        let later = qso_row("id-2", "US-0001", "W6JY", TS_1500);
        let earlier = qso_row("id-1", "US-0001", "W6JY", TS_1430);
        insert(&store, &later);
        insert(&store, &earlier);

        let actual = api
            .export_activation(
                "US-0001".to_string(),
                Some("Golden Gate NRA".to_string()),
                "W6JY".to_string(),
                "2026-01-15".to_string(),
                "2.3.0".to_string(),
            )
            .unwrap();

        // Re-derive the expected bytes straight from the Task 3 writer over the
        // same two records, chronological (earlier first). The header's
        // created_timestamp is "now", so pull it back out of `actual` to build
        // an identical header — everything else must match exactly.
        let expected_records = vec![row_to_write_record(&earlier), row_to_write_record(&later)];
        let created = extract_created_timestamp(&actual);
        let header = AdifHeaderOpts {
            park_reference: "US-0001".to_string(),
            park_name: Some("Golden Gate NRA".to_string()),
            activator_callsign: "W6JY".to_string(),
            first_qso_date: "2026-01-15".to_string(),
            program_version: "2.3.0".to_string(),
            created_timestamp: created,
        };
        let expected = write_adif(&expected_records, &header);

        assert_eq!(actual, expected);
        // Spot-check the ordering + formats surfaced end-to-end.
        assert!(actual.contains("<QSO_DATE:8>20260115<TIME_ON:6>143000"));
        let first = actual.find("143000").unwrap();
        let second = actual.find("150000").unwrap();
        assert!(first < second, "earlier QSO must be written first");
        assert!(actual.contains("<FREQ:9>14.074000"), "kHz→MHz conversion");
    }

    #[test]
    fn empty_activation_yields_unknown_first_qso_date() {
        let (api, _store) = api_with_store();
        let out = api
            .export_activation(
                "US-9999".to_string(),
                None,
                "W6JY".to_string(),
                "2026-01-15".to_string(),
                "2.3.0".to_string(),
            )
            .unwrap();
        assert!(out.contains("on unknown"), "{out}");
        assert!(out.contains("<EOH>"));
        // No QSO records.
        assert!(!out.contains("<EOR>"));
    }

    #[test]
    fn scopes_by_park_callsign_and_utc_day() {
        let (api, store) = api_with_store();
        // In-scope.
        insert(&store, &qso_row("in", "US-0001", "W6JY", TS_1430));
        // Wrong park.
        insert(&store, &qso_row("park", "US-0002", "W6JY", TS_1430));
        // Wrong callsign.
        insert(&store, &qso_row("call", "US-0001", "N0CALL", TS_1430));
        // Next day (2026-01-16 00:30 UTC).
        insert(&store, &qso_row("day", "US-0001", "W6JY", TS_1430 + 86_400 + 3_600));

        let out = api
            .export_activation(
                "US-0001".to_string(),
                None,
                "W6JY".to_string(),
                "2026-01-15".to_string(),
                "2.3.0".to_string(),
            )
            .unwrap();
        // Exactly one QSO record (the in-scope one).
        assert_eq!(out.matches("<EOR>").count(), 1, "{out}");
    }

    #[test]
    fn fetch_activation_qsos_scopes_by_park_callsign_and_utc_day() {
        let (api, store) = api_with_store();
        insert(&store, &qso_row("in-1", "US-0001", "W6JY", TS_1500)); // in scope (later)
        insert(&store, &qso_row("in-2", "US-0001", "W6JY", TS_1430)); // in scope (earlier)
        insert(&store, &qso_row("park", "US-0002", "W6JY", TS_1430)); // wrong park
        insert(&store, &qso_row("call", "US-0001", "N0CALL", TS_1430)); // other own-callsign
        insert(&store, &qso_row("day", "US-0001", "W6JY", TS_1430 + 86_400 + 3_600)); // next day
        let mut hidden = qso_row("hid", "US-0001", "W6JY", TS_1500);
        hidden.is_hidden = true;
        insert(&store, &hidden); // hidden — excluded

        let rows = api
            .fetch_activation_qsos("US-0001".to_string(), "W6JY".to_string(), "2026-01-15".to_string())
            .unwrap();
        let ids: Vec<String> = rows.iter().map(|q| q.id.clone()).collect();
        // Only the two in-scope, visible rows, chronological (ASC) as the store returns them.
        assert_eq!(ids, vec!["in-2".to_string(), "in-1".to_string()]);
    }

    #[test]
    fn fetch_activation_qsos_invalid_date_errors() {
        let (api, _store) = api_with_store();
        let err = api.fetch_activation_qsos("US-0001".to_string(), "W6JY".to_string(), "nope".to_string());
        assert!(err.is_err());
    }

    #[test]
    fn metadata_and_hidden_qsos_excluded() {
        let (api, store) = api_with_store();
        insert(&store, &qso_row("real", "US-0001", "W6JY", TS_1430));
        let mut weather = qso_row("wx", "US-0001", "W6JY", TS_1500);
        weather.mode = Some("WEATHER".to_string());
        insert(&store, &weather);
        let mut hidden = qso_row("hid", "US-0001", "W6JY", TS_1500);
        hidden.is_hidden = true;
        insert(&store, &hidden);

        let out = api
            .export_activation(
                "US-0001".to_string(),
                None,
                "W6JY".to_string(),
                "2026-01-15".to_string(),
                "2.3.0".to_string(),
            )
            .unwrap();
        assert_eq!(out.matches("<EOR>").count(), 1, "{out}");
    }

    #[test]
    fn invalid_date_errors() {
        let (api, _store) = api_with_store();
        let err = api.export_activation(
            "US-0001".to_string(),
            None,
            "W6JY".to_string(),
            "not-a-date".to_string(),
            "2.3.0".to_string(),
        );
        assert!(err.is_err());
    }

    /// Pull the `CREATED_TIMESTAMP` value out of a rendered export so a test can
    /// rebuild an identical header for byte comparison.
    fn extract_created_timestamp(adif: &str) -> String {
        let marker = "<CREATED_TIMESTAMP:15>";
        let start = adif.find(marker).expect("has created timestamp") + marker.len();
        adif[start..start + 15].to_string()
    }

    #[test]
    fn export_bulk_matches_write_bulk_adif_byte_for_byte() {
        let (api, store) = api_with_store();
        // Two activations, two different parks/dates, each with one QSO.
        let qso_a = qso_row("id-a", "US-0001", "W6JY", TS_1430);
        let qso_b_ts = TS_1430 + 86_400; // 2026-01-16
        let qso_b = qso_row("id-b", "US-0002", "W6JY", qso_b_ts);
        insert(&store, &qso_a);
        insert(&store, &qso_b);

        let activations = vec![
            FfiAdifBulkActivationRef {
                park_reference: "US-0001".to_string(),
                park_name: Some("Golden Gate NRA".to_string()),
                callsign: "W6JY".to_string(),
                date: "2026-01-15".to_string(),
            },
            FfiAdifBulkActivationRef {
                park_reference: "US-0002".to_string(),
                park_name: None,
                callsign: "W6JY".to_string(),
                date: "2026-01-16".to_string(),
            },
        ];

        let actual = api.export_bulk(activations, "2.3.0".to_string()).unwrap();

        // Re-derive the expected bytes straight from the Task 3 bulk writer,
        // fed with independently-assembled records — mirrors the
        // non-circular pattern used for `export_activation` above.
        let created = extract_created_timestamp(&actual);
        let expected_activations = vec![
            AdifBulkActivation {
                records: vec![row_to_write_record(&qso_a)],
                park_reference: "US-0001".to_string(),
                park_name: Some("Golden Gate NRA".to_string()),
            },
            AdifBulkActivation {
                records: vec![row_to_write_record(&qso_b)],
                park_reference: "US-0002".to_string(),
                park_name: None,
            },
        ];
        let expected = write_bulk_adif(&expected_activations, "2.3.0", &created);

        assert_eq!(actual, expected);
        assert!(actual.contains("ADIF export for 2 activations: US-0001, US-0002"));
        assert!(actual.contains("// Activation: US-0001"));
        assert!(actual.contains("// Park: Golden Gate NRA"));
        assert!(actual.contains("// Activation: US-0002"));
        assert_eq!(actual.matches("<EOR>").count(), 2, "{actual}");
    }

    #[test]
    fn export_bulk_invalid_date_errors() {
        let (api, _store) = api_with_store();
        let activations = vec![FfiAdifBulkActivationRef {
            park_reference: "US-0001".to_string(),
            park_name: None,
            callsign: "W6JY".to_string(),
            date: "not-a-date".to_string(),
        }];
        let err = api.export_bulk(activations, "2.3.0".to_string());
        assert!(err.is_err());
    }

    // ── import_adif ─────────────────────────────────────────────────────

    use std::sync::atomic::{AtomicUsize, Ordering};
    use crate::observation::StoreObserver;
    use cw_store::{QsoFilter, ServicePresenceFilter};

    // A completed session row with only the fields the session export reads set.
    fn session_row(id: &str, park: Option<&str>, sota: Option<&str>) -> cw_store::LoggingSession {
        cw_store::LoggingSession {
            id: id.to_string(),
            my_callsign: "W6JY".to_string(),
            started_at: TS_1430,
            ended_at: Some(TS_1500),
            frequency: None,
            mode: "CW".to_string(),
            activation_type_raw_value: if park.is_some() { "pota" } else { "casual" }.to_string(),
            programs_raw_value: String::new(),
            status_raw_value: "completed".to_string(),
            park_reference: park.map(str::to_string),
            sota_reference: sota.map(str::to_string),
            mission_reference: None,
            wwff_reference: None,
            my_grid: None,
            power: None,
            my_rig: None,
            notes: None,
            qso_comment: None,
            custom_title: None,
            qso_count: 0,
            spot_comments_data: None,
            is_rove: false,
            rove_stops_data: None,
            my_antenna: None,
            my_key: None,
            my_mic: None,
            extra_equipment: None,
            attendees: None,
            photo_filenames: "[]".to_string(),
            radio_item_id: None,
            station_callsign: None,
            operator_callsigns_raw_value: "[]".to_string(),
            solar_k_index: None,
            solar_flux: None,
            solar_sunspots: None,
            solar_propagation_rating: None,
            solar_a_index: None,
            solar_band_conditions: None,
            solar_timestamp: None,
            solar_conditions: None,
            weather_temperature_f: None,
            weather_temperature_c: None,
            weather_humidity: None,
            weather_wind_speed: None,
            weather_wind_direction: None,
            weather_description: None,
            weather_timestamp: None,
            weather: None,
            cloud_dirty_flag: false,
            contest_id: None,
            contest_category: None,
            contest_overlay_category: None,
            contest_power: None,
            contest_bands: None,
            contest_operator: None,
            activation_latitude: None,
            activation_longitude: None,
            activation_distance_miles: None,
            activation_elevation_gain_feet: None,
            ruck_weight_pounds: None,
            qrp_activation: false,
            with_pets: false,
            with_kids: false,
            winlink_sent: false,
            aprs_sent: false,
            varac_sent: false,
            adaptive_sport: false,
            track_points_data: None,
            tota_category_raw_value: None,
            personal_effort_factor: None,
            first_activation_of_tile_ever: false,
            winter_activation_override: None,
            tiles_activated_data: None,
            tota_t3_candidates_data: None,
            tota_t3_snapshot_at: None,
            tota_official_points: None,
        }
    }

    fn insert_session(store: &Arc<FieldStore>, session: &cw_store::LoggingSession) {
        let s = store.inner.lock().unwrap();
        s.upsert_logging_session(session).expect("insert session");
    }

    // A QSO linked to `session`; `park` None models a casual-session QSO.
    fn session_qso(id: &str, park: Option<&str>, session: &str, qso_date: i64) -> Qso {
        let mut qso = qso_row(id, park.unwrap_or(""), "W6JY", qso_date);
        qso.park = park.map(str::to_string);
        qso.logging_session_id = Some(session.to_string());
        qso
    }

    #[test]
    fn export_session_scopes_by_session_and_falls_back_to_session_park() {
        let (api, store) = api_with_store();
        insert_session(&store, &session_row("s1", Some("US-0001"), None));
        insert_session(&store, &session_row("s2", Some("US-0001"), None));
        // Same park, same day — the plain case.
        insert(&store, &session_qso("same", Some("US-0001"), "s1", TS_1430));
        // Worked from another park (merged rove / second park).
        insert(&store, &session_qso("own-park", Some("US-0002"), "s1", TS_1500));
        // Casual QSO merged in: no park of its own, next UTC day.
        insert(&store, &session_qso("no-park", None, "s1", TS_1430 + 86_400));
        // Same park + day but a different session — must not leak in.
        insert(&store, &session_qso("other-session", Some("US-0001"), "s2", TS_1430));
        let mut hidden = session_qso("hidden", Some("US-0001"), "s1", TS_1430);
        hidden.is_hidden = true;
        insert(&store, &hidden);
        let mut note = session_qso("note", Some("US-0001"), "s1", TS_1430);
        note.mode = Some("NOTE".to_string());
        insert(&store, &note);

        let out = api
            .export_session("s1".to_string(), Some("Park".to_string()), "2.3.0".to_string())
            .unwrap()
            .expect("session exists");

        assert_eq!(out.qso_count, 3, "{}", out.adif);
        assert_eq!(out.first_qso_date, Some(TS_1430));
        assert_eq!(out.adif.matches("<EOR>").count(), 3);
        assert!(
            out.adif.starts_with("ADIF export for W6JY: POTA US-0001 (Park) on 2026-01-15\n"),
            "{}",
            out.adif
        );
        // `same` carries its own park; `no-park` inherits the session's.
        assert_eq!(out.adif.matches("<MY_SIG_INFO:7>US-0001").count(), 2, "{}", out.adif);
        assert_eq!(out.adif.matches("<MY_SIG_INFO:7>US-0002").count(), 1, "{}", out.adif);
        // Chronological regardless of the store's newest-first order.
        let same = out.adif.find("<TIME_ON:6>143000").unwrap();
        let own_park = out.adif.find("<TIME_ON:6>150000").unwrap();
        let next_day = out.adif.find("<QSO_DATE:8>20260116").unwrap();
        assert!(same < own_park && own_park < next_day, "{}", out.adif);
    }

    #[test]
    fn export_session_unknown_id_is_none() {
        let (api, _store) = api_with_store();
        let out = api.export_session("nope".to_string(), None, "2.3.0".to_string()).unwrap();
        assert!(out.is_none());
    }

    #[test]
    fn export_session_uses_station_callsign_and_summit_without_park() {
        let (api, store) = api_with_store();
        let mut session = session_row("s1", None, Some("W6/NC-001"));
        session.station_callsign = Some("W6JY/P".to_string());
        insert_session(&store, &session);
        insert(&store, &session_qso("q", None, "s1", TS_1430));

        let out = api
            .export_session("s1".to_string(), None, "2.3.0".to_string())
            .unwrap()
            .expect("session exists");

        assert_eq!(out.qso_count, 1);
        assert!(
            out.adif.starts_with("ADIF export for W6JY/P: SOTA W6/NC-001 on 2026-01-15\n"),
            "{}",
            out.adif
        );
        assert!(out.adif.contains("<MY_SOTA_REF:9>W6/NC-001"), "{}", out.adif);
        assert!(!out.adif.contains("<MY_SIG:"), "{}", out.adif);
    }

    #[test]
    fn export_session_empty_session_has_unknown_date_and_no_records() {
        let (api, store) = api_with_store();
        insert_session(&store, &session_row("s1", Some("US-0001"), None));
        let out = api
            .export_session("s1".to_string(), None, "2.3.0".to_string())
            .unwrap()
            .expect("session exists");
        assert_eq!(out.qso_count, 0);
        assert_eq!(out.first_qso_date, None);
        assert!(out.adif.contains(" on unknown\n"), "{}", out.adif);
        assert!(out.adif.ends_with("<EOH>\n"), "{:?}", out.adif);
    }

    fn options(my_callsign: &str) -> FfiAdifImportOptions {
        FfiAdifImportOptions { my_callsign: my_callsign.to_string(), upload_qrz: false, upload_pota: false }
    }

    /// One ADIF record with the given call/time plus any extra fields, e.g.
    /// `rec("K1JT", "143000", "<OPERATOR:5>W6JY")`.
    fn rec(call: &str, time_on: &str, extra: &str) -> String {
        format!(
            "<CALL:{}>{call}<BAND:3>20m<MODE:3>FT8<QSO_DATE:8>20260115<TIME_ON:6>{time_on}{extra}<EOR>\n",
            call.len()
        )
    }

    fn all_qsos(store: &Arc<FieldStore>) -> Vec<Qso> {
        let s = store.inner.lock().unwrap();
        s.fetch_qsos(&QsoFilter::default(), 1_000, 0).unwrap()
    }

    #[test]
    fn import_skips_stored_and_in_file_duplicates() {
        let (api, store) = api_with_store();
        // Already in the logbook: K1JT 20m FT8 at 14:30:00 UTC.
        insert(&store, &qso_row("existing", "US-0001", "W6JY", TS_1430));

        let content = format!(
            "Generated by test<EOH>\n{}{}{}{}",
            rec("K1JT", "143059", ""),   // same 2-minute bucket as the stored row → dup
            rec("W1AW", "150000", ""),   // new
            rec("w1aw ", "150100", ""),  // same bucket as the previous record → dup
            rec("N0CALL", "160000", ""), // new
        );
        let result = api.import_adif(content, options("W6JY")).unwrap();
        assert_eq!(
            result,
            FfiAdifImportResult { total_records: 4, imported: 2, duplicates: 2, errors: 0 }
        );
        let rows = all_qsos(&store);
        assert_eq!(rows.len(), 3);
        let mut calls: Vec<&str> = rows.iter().map(|q| q.callsign.as_str()).collect();
        calls.sort_unstable();
        assert_eq!(calls, vec!["K1JT", "N0CALL", "W1AW"]);
    }

    #[test]
    fn reimporting_the_same_file_imports_nothing() {
        let (api, store) = api_with_store();
        let content = format!("<EOH>\n{}{}", rec("K1JT", "143000", ""), rec("W1AW", "150000", ""));
        let first = api.import_adif(content.clone(), options("W6JY")).unwrap();
        assert_eq!(first.imported, 2);
        let second = api.import_adif(content, options("W6JY")).unwrap();
        assert_eq!(
            second,
            FfiAdifImportResult { total_records: 2, imported: 0, duplicates: 2, errors: 0 }
        );
        assert_eq!(all_qsos(&store).len(), 2);
    }

    #[test]
    fn import_stamps_provenance_fresh_ids_and_callsign_fallback() {
        let (api, store) = api_with_store();
        let content = format!(
            "<EOH>\n{}{}",
            rec("K1JT", "143000", "<MY_SIG_INFO:7>US-0001<COMMENT:5>hello"),
            rec("W1AW", "150000", "<STATION_CALLSIGN:6>W6JY/P"),
        );
        api.import_adif(content, options("w6jy")).unwrap();
        let rows = all_qsos(&store);
        assert_eq!(rows.len(), 2);
        for qso in &rows {
            assert_eq!(qso.import_source_raw_value, "adifFile");
            assert!(qso.dirty, "imports must enter the sync journal");
            assert!(qso.raw_adif.as_deref().is_some_and(|r| r.contains("<CALL:")));
            // A random v4 id, not the WSJT-X key-derived one.
            assert_ne!(qso.id, cw_store::wsjtx_qso_id(&cw_store::wsjtx_dedup_key(qso)));
            assert_eq!(Uuid::parse_str(&qso.id).unwrap().get_version_num(), 4);
        }
        let k1jt = rows.iter().find(|q| q.callsign == "K1JT").unwrap();
        assert_eq!(k1jt.my_callsign.as_deref(), Some("W6JY"), "options callsign (uppercased) fills a blank OPERATOR");
        assert_eq!(k1jt.park.as_deref(), Some("US-0001"));
        assert_eq!(k1jt.notes.as_deref(), Some("hello"));
        let w1aw = rows.iter().find(|q| q.callsign == "W1AW").unwrap();
        assert_eq!(w1aw.my_callsign.as_deref(), Some("W6JY/P"), "STATION_CALLSIGN wins over the fallback");
        assert_eq!(w1aw.station_callsign.as_deref(), Some("W6JY/P"));
    }

    #[test]
    fn import_multi_op_drops_other_operators_as_errors() {
        let (api, store) = api_with_store();
        let content = format!(
            "<EOH>\n{}{}{}",
            rec("K1JT", "143000", "<OPERATOR:4>W6JY"),
            rec("W1AW", "150000", "<OPERATOR:6>N0CALL"),
            rec("K9ABC", "160000", ""),
        );
        let result = api.import_adif(content, options("W6JY")).unwrap();
        assert_eq!(
            result,
            FfiAdifImportResult { total_records: 3, imported: 2, duplicates: 0, errors: 1 }
        );
        let rows = all_qsos(&store);
        assert!(rows.iter().all(|q| q.callsign != "W1AW"));
    }

    #[test]
    fn import_counts_unparseable_dates_as_errors() {
        let (api, store) = api_with_store();
        let content = "<EOH>\n<CALL:4>K1JT<BAND:3>20m<MODE:3>FT8<QSO_DATE:4>2026<TIME_ON:4>1430<EOR>\n\
                       <CALL:4>W1AW<BAND:3>20m<MODE:3>FT8<EOR>\n\
                       <CALL:6>N0CALL<BAND:3>20m<MODE:3>FT8<QSO_DATE:8>20260115<EOR>\n"
            .to_string();
        let result = api.import_adif(content, options("W6JY")).unwrap();
        // The third record has a date but no TIME_ON → midnight, still imports.
        assert_eq!(
            result,
            FfiAdifImportResult { total_records: 3, imported: 1, duplicates: 0, errors: 2 }
        );
        assert_eq!(all_qsos(&store).len(), 1);
    }

    #[test]
    fn import_empty_or_recordless_content_is_a_noop() {
        let (api, store) = api_with_store();
        let result = api.import_adif(String::new(), options("W6JY")).unwrap();
        assert_eq!(result, FfiAdifImportResult { total_records: 0, imported: 0, duplicates: 0, errors: 0 });
        let result = api.import_adif("just a header<EOH>\n".to_string(), options("")).unwrap();
        assert_eq!(result.total_records, 0);
        assert!(all_qsos(&store).is_empty());
    }

    fn presences_for(store: &Arc<FieldStore>, qso_id: &str) -> Vec<String> {
        let s = store.inner.lock().unwrap();
        let mut services: Vec<String> = s
            .fetch_service_presences(
                &ServicePresenceFilter { qso_id: Some(qso_id.to_string()), ..Default::default() },
                10,
                0,
            )
            .unwrap()
            .into_iter()
            .filter(|p| p.needs_upload)
            .map(|p| p.service_type_raw_value)
            .collect();
        services.sort();
        services
    }

    #[test]
    fn import_marks_configured_uploads_for_primary_callsign_only() {
        let (api, store) = api_with_store();
        let content = format!(
            "<EOH>\n{}{}{}{}",
            rec("K1JT", "143000", "<MY_SIG_INFO:7>US-0001"),              // park → QRZ + POTA
            rec("W1AW", "150000", ""),                                      // no park → QRZ only
            rec("N0CALL", "160000", "<STATION_CALLSIGN:5>K9XYZ<OPERATOR:4>W6JY"), // station differs, operator mine → my_callsign W6JY → QRZ
            "<CALL:5>WX1WX<BAND:3>20m<MODE:7>WEATHER<QSO_DATE:8>20260115<TIME_ON:6>170000<EOR>\n", // metadata → none
        );
        let opts = FfiAdifImportOptions { my_callsign: "W6JY".to_string(), upload_qrz: true, upload_pota: true };
        let result = api.import_adif(content, opts).unwrap();
        assert_eq!(result.imported, 4, "{result:?}");

        let rows = all_qsos(&store);
        let by_call = |call: &str| rows.iter().find(|q| q.callsign == call).unwrap().id.clone();
        assert_eq!(presences_for(&store, &by_call("K1JT")), vec!["pota".to_string(), "qrz".to_string()]);
        assert_eq!(presences_for(&store, &by_call("W1AW")), vec!["qrz".to_string()]);
        assert_eq!(presences_for(&store, &by_call("N0CALL")), vec!["qrz".to_string()]);
        assert!(presences_for(&store, &by_call("WX1WX")).is_empty());
    }

    #[test]
    fn import_with_uploads_off_writes_no_presences() {
        let (api, store) = api_with_store();
        let content = format!("<EOH>\n{}", rec("K1JT", "143000", "<MY_SIG_INFO:7>US-0001"));
        api.import_adif(content, options("W6JY")).unwrap();
        let s = store.inner.lock().unwrap();
        assert_eq!(s.service_presence_count().unwrap(), 0);
    }

    struct TableCounter {
        qso: AtomicUsize,
        presence: AtomicUsize,
    }

    impl StoreObserver for TableCounter {
        fn on_change(&self, change: FfiStoreChange) {
            match change.table {
                FfiStoreTable::Qso => self.qso.fetch_add(1, Ordering::SeqCst),
                FfiStoreTable::ServicePresence => self.presence.fetch_add(1, Ordering::SeqCst),
                _ => 0,
            };
        }
    }

    #[test]
    fn import_notifies_observers_once_per_touched_table() {
        let (api, store) = api_with_store();
        let counter = Arc::new(TableCounter { qso: AtomicUsize::new(0), presence: AtomicUsize::new(0) });
        store.add_observer(counter.clone());

        let content = format!("<EOH>\n{}{}", rec("K1JT", "143000", ""), rec("W1AW", "150000", ""));
        api.import_adif(content.clone(), options("W6JY")).unwrap();
        assert_eq!(counter.qso.load(Ordering::SeqCst), 1, "one QSO notification for the batch");
        assert_eq!(counter.presence.load(Ordering::SeqCst), 0);

        // All duplicates → nothing written → no notification.
        api.import_adif(content, options("W6JY")).unwrap();
        assert_eq!(counter.qso.load(Ordering::SeqCst), 1);

        let opts = FfiAdifImportOptions { my_callsign: "W6JY".to_string(), upload_qrz: true, upload_pota: false };
        api.import_adif(format!("<EOH>\n{}", rec("N0CALL", "160000", "")), opts).unwrap();
        assert_eq!(counter.qso.load(Ordering::SeqCst), 2);
        assert_eq!(counter.presence.load(Ordering::SeqCst), 1);
    }
}
