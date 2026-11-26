//! BKG log type — FFI surface over `cw_domain::bkg`.
//!
//! Store-less helpers the logger form calls on every keystroke
//! ([`bkg_rules`], [`bkg_check_grid`], [`bkg_build_qso`],
//! [`bkg_corner_grids`]) plus the store-backed [`BkgApi`]: the session's
//! 4-grid corner, the pre-upload check, and the ADIF export that adds
//! `BAND_RX`/`SAT_MODE` to satellite contacts and `MY_VUCC_GRIDS` to a corner
//! session.
//!
//! A BKG session is an ordinary `LoggingSession` whose `programs_raw_value`
//! holds `"bkg"` (the wizard forces CW on 2 m — `session_wizard_api`). A BKG
//! contact is an ordinary `qso` row: the grids ride in `my_grid`/`their_grid`,
//! the "sent in CW" switches in `contest_exchange_sent`/`_received`
//! (`STX_STRING`/`SRX_STRING`), a satellite contact in `sat_name`/`prop_mode`.
//! Hosts log through `SessionApi::log_qso` with the values
//! [`bkg_build_qso`] returns, so no schema change is involved. The corner
//! grids are per-session and live in the store `kv` (local to the device; not
//! synced yet).

use std::sync::Arc;

use chrono::Utc;
use cw_domain::adif_writer::{write_session_adif, AdifSessionHeaderOpts, AdifSessionRecord};
use cw_domain::bkg::{self, GridError, InputError, QsoInput, StoredQso};
use cw_domain::is_metadata_mode;
use cw_store::{LoggingSession, Qso, MAX_FETCH_LIMIT};

use crate::adif_api::{format_utc, non_blank, row_to_write_record};
use crate::entities::logging_session::FfiLoggingSession;
use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};

/// `kv` key prefix for a session's 4-grid corner (value: `"CM87,CM88,…"`).
const KV_CORNER_PREFIX: &str = "bkg.cornerGrids.";
/// `kv` key prefix for a session's "follow GPS live" flag (value: `"1"`).
const KV_LIVE_GPS_PREFIX: &str = "bkg.liveGps.";

// ---------- DTOs ----------

/// The fixed BKG rules, so hosts label and lock their controls from one place.
#[derive(uniffi::Record, Debug, Clone, PartialEq)]
pub struct FfiBkgRules {
    pub program_slug: String,
    /// On-screen name of the log type ("BKG Turf Wars").
    pub display_name: String,
    /// How close (metres) a GPS fix must be to a 4-grid corner to count.
    pub corner_radius_m: f64,
    pub mode: String,
    pub band: String,
    pub band_low_mhz: f64,
    pub band_high_mhz: f64,
    pub default_frequency_mhz: f64,
    pub sat_prop_mode: String,
    pub sat_band_rx: String,
    pub sat_mode: String,
}

/// Where a GPS fix puts the station: its 6-character grid and the nearest
/// 4-grid corner.
#[derive(uniffi::Record, Debug, Clone, PartialEq)]
pub struct FfiBkgPosition {
    pub grid: String,
    /// The four grids at the nearest corner, sorted; empty near a pole.
    pub nearest_corner_grids: Vec<String>,
    pub corner_distance_m: f64,
    /// Within `FfiBkgRules::corner_radius_m` of that corner.
    pub at_corner: bool,
}

/// Result of checking one grid field.
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct FfiBkgGridCheck {
    /// Canonical upper-case grid when valid.
    pub grid: Option<String>,
    /// What is wrong, when it is not.
    pub problem: Option<String>,
}

/// The logger's BKG form state for one contact.
#[derive(uniffi::Record, Debug, Clone)]
pub struct FfiBkgQsoInput {
    pub my_grid: String,
    pub their_grid: String,
    /// "I sent my grid in CW".
    pub sent_my_grid: bool,
    /// "They sent theirs".
    pub received_their_grid: bool,
    /// Worked through a linear V/U satellite.
    #[uniffi(default = false)]
    pub via_satellite: bool,
    #[uniffi(default = None)]
    pub sat_name: Option<String>,
}

/// QSO field values for a BKG contact. `exchange_sent`/`exchange_received`,
/// `sat_name` and `prop_mode` go straight into the matching
/// `FfiSessionLogInput` fields; `band_rx`/`sat_mode` are shown for
/// confirmation and re-derived at export.
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct FfiBkgQsoFields {
    pub mode: String,
    pub band: String,
    pub my_grid: String,
    pub their_grid: String,
    pub exchange_sent: Option<String>,
    pub exchange_received: Option<String>,
    pub prop_mode: Option<String>,
    pub sat_name: Option<String>,
    pub band_rx: Option<String>,
    pub sat_mode: Option<String>,
}

/// [`bkg_build_qso`] outcome: the fields, or why the contact can't be logged.
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct FfiBkgQsoDraft {
    pub fields: Option<FfiBkgQsoFields>,
    pub problem: Option<String>,
}

/// One stored QSO the BKG rules would not accept, with the reasons.
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct FfiBkgQsoCheck {
    pub qso_id: String,
    pub callsign: String,
    /// Unix seconds, UTC.
    pub qso_date: i64,
    pub issues: Vec<String>,
}

/// A BKG session rendered to ADIF.
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct FfiBkgExport {
    pub adif: String,
    pub qso_count: u32,
    /// Unix seconds (UTC) of the earliest exported QSO; `None` when empty.
    pub first_qso_date: Option<i64>,
    /// The session's 4-grid corner, empty when it has none.
    pub corner_grids: Vec<String>,
    /// Exported QSOs that fail the app's own rule check. They are still in the
    /// file; the BKG server decides.
    pub flagged: Vec<FfiBkgQsoCheck>,
}

// ---------- store-less helpers ----------

fn grid_problem(label: &str, error: GridError) -> String {
    match error {
        GridError::Missing => format!("{label} grid is required"),
        GridError::NotSixCharacters => format!("{label} grid must be 6 characters"),
        GridError::Invalid => format!("{label} grid is not a valid grid"),
    }
}

/// The fixed BKG rules.
#[uniffi::export]
pub fn bkg_rules() -> FfiBkgRules {
    FfiBkgRules {
        program_slug: bkg::PROGRAM_SLUG.to_string(),
        display_name: bkg::DISPLAY_NAME.to_string(),
        corner_radius_m: bkg::CORNER_RADIUS_M,
        mode: bkg::MODE.to_string(),
        band: bkg::BAND.to_string(),
        band_low_mhz: bkg::BAND_LOW_MHZ,
        band_high_mhz: bkg::BAND_HIGH_MHZ,
        default_frequency_mhz: bkg::DEFAULT_FREQUENCY_MHZ,
        sat_prop_mode: bkg::PROP_MODE_SAT.to_string(),
        sat_band_rx: bkg::SAT_BAND_RX.to_string(),
        sat_mode: bkg::SAT_MODE.to_string(),
    }
}

/// Check one grid field (a BKG exchange needs all six characters).
#[uniffi::export]
pub fn bkg_check_grid(grid: String) -> FfiBkgGridCheck {
    match bkg::normalize_grid6(&grid) {
        Ok(grid) => FfiBkgGridCheck { grid: Some(grid), problem: None },
        Err(error) => FfiBkgGridCheck { grid: None, problem: Some(grid_problem("The", error)) },
    }
}

/// Turn the form state into QSO field values, or say why it can't be logged.
#[uniffi::export]
pub fn bkg_build_qso(input: FfiBkgQsoInput) -> FfiBkgQsoDraft {
    let built = bkg::build_qso_fields(&QsoInput {
        my_grid: input.my_grid,
        their_grid: input.their_grid,
        sent_my_grid: input.sent_my_grid,
        received_their_grid: input.received_their_grid,
        via_satellite: input.via_satellite,
        sat_name: input.sat_name,
    });
    match built {
        Ok(fields) => FfiBkgQsoDraft {
            fields: Some(FfiBkgQsoFields {
                mode: fields.mode,
                band: fields.band,
                my_grid: fields.my_grid,
                their_grid: fields.their_grid,
                exchange_sent: fields.exchange_sent,
                exchange_received: fields.exchange_received,
                prop_mode: fields.prop_mode,
                sat_name: fields.sat_name,
                band_rx: fields.band_rx,
                sat_mode: fields.sat_mode,
            }),
            problem: None,
        },
        Err(InputError::MyGrid(error)) => {
            FfiBkgQsoDraft { fields: None, problem: Some(grid_problem("My", error)) }
        }
        Err(InputError::TheirGrid(error)) => {
            FfiBkgQsoDraft { fields: None, problem: Some(grid_problem("Their", error)) }
        }
    }
}

/// The four grids meeting at the corner nearest a 6-character grid, sorted.
/// Empty when the grid is invalid or has no four-grid corner.
#[uniffi::export]
pub fn bkg_corner_grids(grid: String) -> Vec<String> {
    bkg::corner_grids_near(&grid).unwrap_or_default()
}

/// Grid and nearest 4-grid corner for a GPS fix. `None` for a coordinate
/// off the globe.
#[uniffi::export]
pub fn bkg_position(latitude: f64, longitude: f64) -> Option<FfiBkgPosition> {
    bkg::position_from_coordinate(latitude, longitude).map(|position| FfiBkgPosition {
        grid: position.grid,
        nearest_corner_grids: position.nearest_corner_grids,
        corner_distance_m: if position.corner_distance_m.is_finite() { position.corner_distance_m } else { -1.0 },
        at_corner: position.at_corner,
    })
}

// ---------- store-backed API ----------

/// Store-backed BKG session operations. Stateless — every call reads the
/// store, like [`crate::adif_api::AdifApi`].
#[derive(uniffi::Object)]
pub struct BkgApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl BkgApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        BkgApi { store }
    }

    /// Mark a session as operated from a 4-grid corner. `grids` must be four
    /// 4-character grids forming a 2×2 block (any order, any case); an empty
    /// list clears the corner. Returns the stored, sorted grids.
    pub fn set_corner_grids(&self, session_id: String, grids: Vec<String>) -> Result<Vec<String>, CwError> {
        let key = corner_key(&session_id);
        let store = self.store.inner.lock().expect("store mutex poisoned");
        if grids.is_empty() {
            store.kv_delete(&key)?;
            return Ok(Vec::new());
        }
        let corner = bkg::normalize_corner_grids(&grids).ok_or_else(|| CwError::Store {
            reason: "a 4-grid corner needs four adjacent 4-character grids".to_string(),
        })?;
        store.kv_set(&key, &corner.join(","))?;
        Ok(corner)
    }

    /// The session's 4-grid corner, empty when it has none.
    pub fn corner_grids(&self, session_id: String) -> Result<Vec<String>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        Ok(read_corner(store.kv_get(&corner_key(&session_id))?))
    }

    /// Set the session's own grid (from GPS or typed). It must be a valid
    /// 6-character grid; it is stored upper case. `None` when no session has
    /// that id. Hosts with their own session model (iOS SwiftData) write it
    /// there instead.
    pub fn set_session_grid(
        &self,
        session_id: String,
        grid: String,
    ) -> Result<Option<FfiLoggingSession>, CwError> {
        let grid = bkg::normalize_grid6(&grid)
            .map_err(|error| CwError::Store { reason: grid_problem("The", error) })?;
        let session = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut session) = store.fetch_logging_session(&session_id)? else {
                return Ok(None);
            };
            if session.my_grid.as_deref() != Some(grid.as_str()) {
                session.my_grid = Some(grid);
                session.cloud_dirty_flag = true;
                store.upsert_logging_session(&session)?;
            }
            session
        };
        self.store.notify(FfiStoreChange { table: FfiStoreTable::LoggingSession, kind: FfiChangeKind::Upsert });
        Ok(Some(FfiLoggingSession::from(session)))
    }

    /// Turn "follow GPS live" on or off for a session (a rove). Off — the
    /// default — keeps the grid and corner the session started with.
    pub fn set_live_gps(&self, session_id: String, on: bool) -> Result<(), CwError> {
        let key = live_gps_key(&session_id);
        let store = self.store.inner.lock().expect("store mutex poisoned");
        if on {
            store.kv_set(&key, "1")?;
        } else {
            store.kv_delete(&key)?;
        }
        Ok(())
    }

    /// Whether the session follows GPS live.
    pub fn live_gps(&self, session_id: String) -> Result<bool, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        Ok(store.kv_get(&live_gps_key(&session_id))?.as_deref() == Some("1"))
    }

    /// Pre-upload check: the session's QSOs that break a BKG rule, oldest
    /// first. Empty ⇒ every contact is ready.
    pub fn check_session(&self, session_id: String) -> Result<Vec<FfiBkgQsoCheck>, CwError> {
        let rows = self.session_rows(&session_id)?;
        Ok(flag_rows(&rows))
    }

    /// Export a BKG session to ADIF. On top of the standard session export
    /// every satellite contact (`PROP_MODE` = `SAT`) carries `BAND_RX` 70cm and
    /// `SAT_MODE` VU, and a corner session carries `MY_VUCC_GRIDS` on every
    /// record. `STX_STRING`/`SRX_STRING` come from the stored exchange. No
    /// POTA block is written. `None` when no session has that id.
    pub fn export_session(
        &self,
        session_id: String,
        program_version: String,
    ) -> Result<Option<FfiBkgExport>, CwError> {
        let (session, corner) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(session) = store.fetch_logging_session(&session_id)? else {
                return Ok(None);
            };
            let corner = read_corner(store.kv_get(&corner_key(&session_id))?);
            (session, corner)
        };
        let rows = self.session_rows(&session_id)?;
        let vucc_grids = bkg::vucc_grids_field(&corner);
        let first_qso_date = rows.first().map(|row| row.qso_date);

        let header = AdifSessionHeaderOpts {
            activator_callsign: session
                .station_callsign
                .as_deref()
                .and_then(non_blank)
                .unwrap_or_else(|| session.my_callsign.clone()),
            park_reference: None,
            park_name: None,
            sota_reference: None,
            first_qso_date: first_qso_date
                .map(|date| format_utc(date, "%Y-%m-%d"))
                .unwrap_or_else(|| "unknown".to_string()),
            program_version,
            created_timestamp: format_utc(Utc::now().timestamp(), "%Y%m%d %H%M%S"),
        };
        let records: Vec<AdifSessionRecord> = rows
            .iter()
            .map(|row| {
                let mut record = row_to_write_record(row);
                if let Some((band_rx, sat_mode)) = bkg::satellite_export_fields(row.prop_mode.as_deref()) {
                    record.band_rx = Some(band_rx.to_string());
                    record.sat_mode = Some(sat_mode.to_string());
                }
                record.my_vucc_grids = vucc_grids.clone();
                AdifSessionRecord { record, park_reference: None }
            })
            .collect();

        Ok(Some(FfiBkgExport {
            adif: write_session_adif(&records, &header),
            qso_count: records.len() as u32,
            first_qso_date,
            corner_grids: corner,
            flagged: flag_rows(&rows),
        }))
    }
}

impl BkgApi {
    /// The session's visible, non-metadata QSOs, oldest first.
    fn session_rows(&self, session_id: &str) -> Result<Vec<Qso>, CwError> {
        let mut rows = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            store.fetch_qsos_for_session(session_id, None, MAX_FETCH_LIMIT)?
        };
        rows.retain(|qso| !qso.mode.as_deref().map(is_metadata_mode).unwrap_or(false));
        rows.sort_by_key(|qso| qso.qso_date);
        Ok(rows)
    }
}

/// Whether a session is a BKG log: `"bkg"` is in its stored program list.
pub(crate) fn is_bkg_session(session: &LoggingSession) -> bool {
    serde_json::from_str::<Vec<String>>(&session.programs_raw_value)
        .map(|slugs| slugs.iter().any(|slug| slug == bkg::PROGRAM_SLUG))
        .unwrap_or(false)
}

fn corner_key(session_id: &str) -> String {
    format!("{KV_CORNER_PREFIX}{session_id}")
}

fn live_gps_key(session_id: &str) -> String {
    format!("{KV_LIVE_GPS_PREFIX}{session_id}")
}

fn read_corner(raw: Option<String>) -> Vec<String> {
    let grids: Vec<String> =
        raw.unwrap_or_default().split(',').map(str::to_string).filter(|grid| !grid.is_empty()).collect();
    bkg::normalize_corner_grids(&grids).unwrap_or_default()
}

fn flag_rows(rows: &[Qso]) -> Vec<FfiBkgQsoCheck> {
    rows.iter()
        .filter_map(|row| {
            let issues = bkg::check_qso(&StoredQso {
                mode: row.mode.as_deref(),
                band: row.band.as_deref(),
                my_grid: row.my_grid.as_deref(),
                their_grid: row.their_grid.as_deref(),
                exchange_sent: row.contest_exchange_sent.as_deref(),
                exchange_received: row.contest_exchange_received.as_deref(),
            });
            (!issues.is_empty()).then(|| FfiBkgQsoCheck {
                qso_id: row.id.clone(),
                callsign: row.callsign.clone(),
                qso_date: row.qso_date,
                issues: issues.iter().map(|issue| issue.message().to_string()).collect(),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session_api::{FfiSessionLogInput, SessionApi};
    use crate::session_wizard_api::{FfiCreateSessionInput, SessionWizardApi};

    fn store() -> Arc<FieldStore> {
        Arc::new(FieldStore::open_in_memory("k".into()).unwrap())
    }

    /// Start a BKG session through the real wizard (SSB on 20 m in, CW on 2 m out).
    fn start_session(store: &Arc<FieldStore>, my_grid: &str) -> String {
        let wizard = SessionWizardApi::new(store.clone());
        let session = wizard
            .create_session(FfiCreateSessionInput {
                base_callsign: "w6jy".to_string(),
                callsign_prefix: String::new(),
                suffix: String::new(),
                is_club_station: false,
                club_callsign_input: String::new(),
                mode: "SSB".to_string(),
                frequency_mhz: Some(14.062),
                programs: vec!["bkg".to_string()],
                park_reference: None,
                sota_reference: None,
                mission_reference: None,
                wwff_reference: None,
                my_grid: Some(my_grid.to_string()),
                power: Some(50),
                my_rig: Some("IC-9700".to_string()),
                my_antenna: None,
                selected_key: None,
                selected_mic: None,
                extra_equipment: None,
                attendees: None,
                is_rove: false,
                contest_id: None,
                contest_category: None,
                contest_overlay_category: None,
                contest_power: None,
                contest_bands: None,
                contest_operator: None,
                operator_callsigns: vec![],
                radio_item_id: None,
                tota: None,
                id_override: Some("bkg-1".to_string()),
                started_at_override: Some(1_768_487_000),
            })
            .unwrap();
        session.id
    }

    /// Log one contact the way a host does: form → `bkg_build_qso` → `log_qso`.
    fn log(store: &Arc<FieldStore>, session_id: &str, call: &str, form: FfiBkgQsoInput, at: i64) {
        let fields = bkg_build_qso(form).fields.expect("form should be loggable");
        let logged = SessionApi::new(store.clone()).log_qso(log_input(session_id, call, fields, at)).unwrap();
        assert!(logged.is_some());
    }

    fn log_input(session_id: &str, call: &str, fields: FfiBkgQsoFields, at: i64) -> FfiSessionLogInput {
        FfiSessionLogInput {
                session_id: session_id.to_string(),
                callsign: call.to_string(),
                rst_sent: "599".to_string(),
                rst_received: "579".to_string(),
                their_grid: Some(fields.their_grid),
                their_park: None,
                notes: None,
                name: None,
                qth: None,
                state: None,
                country: None,
                their_license_class: None,
                aoa_code: None,
                callsign_change_note: None,
                frequency_override_mhz: None,
                mode_override: None,
                timestamp_override: Some(at),
                contest_name: None,
                contest_serial_sent: None,
                contest_serial_received: None,
                contest_exchange_sent: fields.exchange_sent,
                contest_exchange_received: fields.exchange_received,
                sat_name: fields.sat_name,
                prop_mode: fields.prop_mode,
                upload_qrz: false,
                upload_pota: false,
                upload_lofi: false,
                upload_clublog: false,
        }
    }

    fn form(their_grid: &str) -> FfiBkgQsoInput {
        FfiBkgQsoInput {
            my_grid: "CM87xx".to_string(),
            their_grid: their_grid.to_string(),
            sent_my_grid: true,
            received_their_grid: true,
            via_satellite: false,
            sat_name: None,
        }
    }

    #[test]
    fn rules_are_cw_on_two_meters() {
        let rules = bkg_rules();
        assert_eq!(rules.program_slug, "bkg");
        assert_eq!(rules.mode, "CW");
        assert_eq!(rules.band, "2m");
        assert_eq!(rules.sat_band_rx, "70cm");
        assert_eq!(rules.sat_mode, "VU");
        assert_eq!(rules.display_name, "BKG Turf Wars");
        assert_eq!(rules.corner_radius_m, 500.0);
    }

    #[test]
    fn position_reports_grid_and_corner() {
        let at = bkg_position(34.002, -86.003).unwrap();
        assert_eq!(at.grid, "EM64XA");
        assert!(at.at_corner);
        assert_eq!(at.nearest_corner_grids, vec!["EM63", "EM64", "EM73", "EM74"]);
        assert_eq!(bkg_position(89.9, 0.0).unwrap().corner_distance_m, -1.0);
        assert_eq!(bkg_position(100.0, 0.0), None);
    }

    #[test]
    fn session_grid_must_be_six_characters() {
        let store = store();
        let id = start_session(&store, "EM64");
        let api = BkgApi::new(store);
        assert!(api.set_session_grid(id.clone(), "EM64".to_string()).is_err());
        let session = api.set_session_grid(id.clone(), " em64xa ".to_string()).unwrap().unwrap();
        assert_eq!(session.my_grid.as_deref(), Some("EM64XA"));
        assert!(api.set_session_grid("nope".to_string(), "EM64XA".to_string()).unwrap().is_none());
    }

    #[test]
    fn live_gps_is_off_until_turned_on() {
        let store = store();
        let id = start_session(&store, "EM64XA");
        let api = BkgApi::new(store);
        assert!(!api.live_gps(id.clone()).unwrap());
        api.set_live_gps(id.clone(), true).unwrap();
        assert!(api.live_gps(id.clone()).unwrap());
        api.set_live_gps(id.clone(), false).unwrap();
        assert!(!api.live_gps(id).unwrap());
    }

    #[test]
    fn grid_check_explains_a_short_grid() {
        assert_eq!(bkg_check_grid("cm87xk".into()).grid.as_deref(), Some("CM87XK"));
        let short = bkg_check_grid("CM87".into());
        assert_eq!(short.grid, None);
        assert_eq!(short.problem.as_deref(), Some("The grid must be 6 characters"));
    }

    #[test]
    fn draft_names_the_bad_grid() {
        let draft = bkg_build_qso(form("CM97"));
        assert_eq!(draft.fields, None);
        assert_eq!(draft.problem.as_deref(), Some("Their grid must be 6 characters"));
    }

    #[test]
    fn terrestrial_session_exports_grids_as_exchange() {
        let store = store();
        let session_id = start_session(&store, "cm87xx");
        log(&store, &session_id, "K6ABC", form("cm97ab"), 1_768_487_400);

        let api = BkgApi::new(store.clone());
        let export = api.export_session(session_id.clone(), "1.0".into()).unwrap().unwrap();
        assert_eq!(export.qso_count, 1);
        assert!(export.flagged.is_empty());
        assert!(export.corner_grids.is_empty());

        let adif = &export.adif;
        assert!(adif.contains("<CALL:5>K6ABC<BAND:2>2m<MODE:2>CW<FREQ:10>144.100000"));
        assert!(adif.contains("<GRIDSQUARE:6>CM97AB<MY_GRIDSQUARE:6>CM87XX"));
        assert!(adif.contains("<STX_STRING:6>CM87XX<SRX_STRING:6>CM97AB"));
        for absent in ["BAND_RX", "SAT_MODE", "PROP_MODE", "MY_VUCC_GRIDS", "MY_SIG", "QSLMSG"] {
            assert!(!adif.contains(absent), "{absent} should not be written");
        }
        assert!(api.check_session(session_id).unwrap().is_empty());
    }

    #[test]
    fn satellite_contact_exports_band_rx_and_sat_mode() {
        let store = store();
        let session_id = start_session(&store, "CM87xx");
        let mut sat = form("DM04bb");
        sat.via_satellite = true;
        sat.sat_name = Some("rs-44".to_string());
        log(&store, &session_id, "N7XYZ", sat, 1_768_487_400);
        log(&store, &session_id, "K6ABC", form("CM97ab"), 1_768_487_500);

        let export = BkgApi::new(store).export_session(session_id, "1.0".into()).unwrap().unwrap();
        let records: Vec<&str> = export.adif.split("<EOR>").collect();
        assert!(records[0].contains("<CALL:5>N7XYZ<BAND:2>2m"));
        assert!(records[0].contains("<SAT_NAME:5>RS-44<PROP_MODE:3>SAT<BAND_RX:4>70cm<SAT_MODE:2>VU"));
        // The terrestrial contact in the same session stays plain.
        assert!(records[1].contains("<CALL:5>K6ABC"));
        assert!(!records[1].contains("BAND_RX"));
        assert!(!records[1].contains("SAT_MODE"));
    }

    #[test]
    fn corner_session_writes_my_vucc_grids_on_every_record() {
        let store = store();
        let session_id = start_session(&store, "CM87xx");
        log(&store, &session_id, "K6ABC", form("CM97ab"), 1_768_487_400);
        log(&store, &session_id, "K6DEF", form("CM98cd"), 1_768_487_500);

        let api = BkgApi::new(store);
        let corner = api.set_corner_grids(session_id.clone(), bkg_corner_grids("CM87xx".into())).unwrap();
        assert_eq!(corner, vec!["CM87", "CM88", "CM97", "CM98"]);
        assert_eq!(api.corner_grids(session_id.clone()).unwrap(), corner);

        let export = api.export_session(session_id.clone(), "1.0".into()).unwrap().unwrap();
        assert_eq!(export.corner_grids, corner);
        assert_eq!(export.adif.matches("<MY_VUCC_GRIDS:19>CM87,CM88,CM97,CM98").count(), 2);

        // Clearing the corner removes the field.
        assert!(api.set_corner_grids(session_id.clone(), vec![]).unwrap().is_empty());
        let export = api.export_session(session_id, "1.0".into()).unwrap().unwrap();
        assert!(!export.adif.contains("MY_VUCC_GRIDS"));
    }

    #[test]
    fn corner_must_be_four_adjacent_grids() {
        let store = store();
        let session_id = start_session(&store, "CM87xx");
        let api = BkgApi::new(store);
        let not_a_corner = ["CM87", "CM88", "CM97", "DM04"].map(String::from).to_vec();
        assert!(api.set_corner_grids(session_id.clone(), not_a_corner).is_err());
        assert!(api.corner_grids(session_id).unwrap().is_empty());
    }

    #[test]
    fn switched_off_exchange_is_flagged_and_left_out() {
        let store = store();
        let session_id = start_session(&store, "CM87xx");
        let mut no_copy = form("CM97ab");
        no_copy.received_their_grid = false;
        log(&store, &session_id, "K6ABC", no_copy, 1_768_487_400);

        let export = BkgApi::new(store).export_session(session_id, "1.0".into()).unwrap().unwrap();
        assert!(export.adif.contains("<STX_STRING:6>CM87XX"));
        assert!(!export.adif.contains("SRX_STRING"));
        assert_eq!(export.flagged.len(), 1);
        assert_eq!(export.flagged[0].callsign, "K6ABC");
        assert_eq!(export.flagged[0].issues, vec!["Their grid was not received in CW"]);
    }

    #[test]
    fn four_character_session_grid_is_flagged() {
        let store = store();
        let session_id = start_session(&store, "CM87");
        // The form's own my-grid is fine, but the session (and so the stored
        // QSO) only has four characters.
        log(&store, &session_id, "K6ABC", form("CM97ab"), 1_768_487_400);
        let flagged = BkgApi::new(store).check_session(session_id).unwrap();
        assert_eq!(flagged.len(), 1);
        assert!(flagged[0].issues.contains(&"My grid is not a 6-character grid".to_string()));
        assert!(!flagged[0].issues.contains(&"Exchange does not match the logged grid".to_string()));
    }

    #[test]
    fn per_contact_overrides_cannot_leave_cw_on_two_meters() {
        let store = store();
        let session_id = start_session(&store, "CM87xx");
        let fields = bkg_build_qso(form("CM97ab")).fields.unwrap();
        let mut input = log_input(&session_id, "K6ABC", fields, 1_768_487_400);
        // A quick-entry line like "14.062 SSB" must not move a BKG contact.
        input.frequency_override_mhz = Some(14.062);
        input.mode_override = Some("SSB".to_string());
        SessionApi::new(store.clone()).log_qso(input).unwrap().unwrap();
        // An in-band override (a different 2 m frequency) is kept.
        let fields = bkg_build_qso(form("CM97ab")).fields.unwrap();
        let mut input = log_input(&session_id, "K6DEF", fields, 1_768_487_500);
        input.frequency_override_mhz = Some(145.9);
        SessionApi::new(store.clone()).log_qso(input).unwrap().unwrap();

        let api = BkgApi::new(store);
        assert!(api.check_session(session_id.clone()).unwrap().is_empty());
        let adif = api.export_session(session_id, "1.0".into()).unwrap().unwrap().adif;
        assert!(adif.contains("<CALL:5>K6ABC<BAND:2>2m<MODE:2>CW<FREQ:10>144.100000"));
        assert!(adif.contains("<CALL:5>K6DEF<BAND:2>2m<MODE:2>CW<FREQ:10>145.900000"));
    }

    #[test]
    fn frequency_and_mode_commands_are_refused_outside_the_lock() {
        use crate::logger_command::FfiLoggerCommand;
        use crate::logger_command_handler::{FfiCommandContext, FfiCommandOutcome, LoggerCommandApi};

        let store = store();
        let session_id = start_session(&store, "CM87xx");
        let api = LoggerCommandApi::new(store.clone());
        let run = |command: FfiLoggerCommand| {
            let context = FfiCommandContext { pota_qsy_spot_enabled: false, pota_auto_spot_enabled: false };
            api.handle(session_id.clone(), command, context).unwrap()
        };

        assert!(matches!(run(FfiLoggerCommand::Mode { mode: "SSB".into() }), FfiCommandOutcome::Message { .. }));
        assert!(matches!(run(FfiLoggerCommand::Frequency { mhz: 14.062 }), FfiCommandOutcome::Message { .. }));
        assert!(matches!(
            run(FfiLoggerCommand::Frequency { mhz: 145.9 }),
            FfiCommandOutcome::SessionUpdated { .. }
        ));
        assert!(matches!(run(FfiLoggerCommand::Mode { mode: "CW".into() }), FfiCommandOutcome::SessionUpdated { .. }));

        let session = store.inner.lock().unwrap().fetch_logging_session(&session_id).unwrap().unwrap();
        assert_eq!(session.mode, "CW");
        assert_eq!(session.frequency, Some(145.9));
    }

    #[test]
    fn unknown_session_exports_nothing() {
        let api = BkgApi::new(store());
        assert!(api.export_session("nope".into(), "1.0".into()).unwrap().is_none());
        assert!(api.check_session("nope".into()).unwrap().is_empty());
    }
}
