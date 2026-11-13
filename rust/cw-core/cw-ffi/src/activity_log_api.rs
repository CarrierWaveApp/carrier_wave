//! Hunter-log lifecycle + QSO logging — port of the iOS `ActivityLogManager`.
//!
//! `ActivityLogManager` (the "hunter" / chaser workflow) is an `@MainActor`
//! `@Observable` that wraps SwiftData with a handful of load-bearing *rules*:
//!
//! - **single active log** — creating or activating a log deactivates whichever
//!   log was previously active;
//! - **`log_qso` enrichment** — uppercase the callsign, stamp `my_callsign` /
//!   `my_grid` from the log, copy the station-profile fields, set
//!   `is_activity_log_qso` + link the QSO to the log via `logging_session_id`,
//!   and tag user-authored notes (CAR-243);
//! - **upload routing** — mark for QRZ (and the no-op LoFi/ClubLog calls,
//!   faithfully preserved — `ServiceType::supports_upload` gates them out), but
//!   **never POTA** (a hunter QSO has no operator park) and never for a metadata
//!   pseudo-mode (`WEATHER`/`SOLAR`/`NOTE`);
//! - **today stats** — count + worked bands/modes over the UTC start-of-day
//!   window, with one-shot daily-goal detection at exact equality.
//!
//! The SwiftData/Keychain/UserDefaults/CoreLocation plumbing stays in the host;
//! the *active log* is the store's `is_active = 1` row (the source of truth that
//! the iOS `activeActivityLogId` UserDefaults key merely cached). Profile fields
//! (`power`/`my_rig`/`station_profile_name`) and the "is this service
//! configured" booleans are host inputs — they come from `StationProfileStorage`
//! and the Keychain, which are not in the store.

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

use chrono::{TimeZone, Utc};
use cw_domain::hunter_log::band_mode_park_keys;
use cw_domain::is_metadata_mode;
use cw_domain::service_type::ServiceType;
use cw_store::{ActivityLog, ActivityLogFilter, Qso, Store};
use uuid::Uuid;

use crate::entities::activity_log::FfiActivityLog;
use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::upload::mark_needs_upload;
use crate::{CwError, FfiQso, FieldStore};

/// Upper bound for the "how many logs are active" sweep. There should only ever
/// be one, but the invariant is enforced defensively (any stragglers from an
/// interrupted write are cleaned up on the next create/activate).
const ACTIVE_SWEEP_LIMIT: i64 = 1_000;

/// Bound on the today-stats window fetch — mirrors the iOS
/// `BoundedDescriptor<QSO>(limit: 500)` in `refreshTodayStats`.
const TODAY_STATS_LIMIT: i64 = 500;

// ---------- DTOs ----------

/// Everything `log_qso` needs that the store + the active log don't already
/// carry: the contact fields, the host-resolved station-profile fields, and the
/// per-service "is configured" flags. Mirrors the `ActivityLogManager.logQSO`
/// parameter list plus the cached service configuration.
#[derive(uniffi::Record)]
pub struct FfiLogQsoInput {
    /// The active log to log into. A hunter QSO is linked to it via
    /// `logging_session_id` and flagged `is_activity_log_qso`.
    pub log_id: String,
    pub callsign: String,
    pub band: String,
    pub mode: String,
    /// Frequency in **MHz** (matches `QSO.frequency`); persisted as `freq_khz`.
    pub frequency_mhz: Option<f64>,
    /// RST sent — defaults to `"599"` in the iOS form.
    pub rst_sent: String,
    /// RST received — defaults to `"599"` in the iOS form.
    pub rst_received: String,
    pub their_grid: Option<String>,
    pub their_park: Option<String>,
    pub sota_ref: Option<String>,
    pub notes: Option<String>,
    pub name: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    /// Station-profile power (watts), resolved host-side from `StationProfile`.
    pub power: Option<i64>,
    /// Station-profile rig, resolved host-side.
    pub my_rig: Option<String>,
    /// Station-profile name, resolved host-side.
    pub station_profile_name: Option<String>,
    /// Whether QRZ upload is configured (Keychain check, host-side).
    pub upload_qrz: bool,
    /// Whether LoFi is device-linked (host-side). Preserved for parity; LoFi does
    /// not use `ServicePresence` (`supports_upload == false`), so this is a no-op.
    pub upload_lofi: bool,
    /// Whether ClubLog credentials exist (host-side). Same no-op caveat as LoFi.
    pub upload_clublog: bool,
    /// Daily QSO goal (0 = disabled). Drives one-shot `daily_goal_reached`.
    pub daily_goal: i64,
}

/// Today's running statistics for an active log (UTC start-of-day window).
#[derive(uniffi::Record, Default, PartialEq, Debug)]
pub struct FfiTodayStats {
    pub qso_count: i64,
    /// Distinct worked bands today, sorted for a deterministic surface.
    pub bands: Vec<String>,
    /// Distinct used modes today, sorted for a deterministic surface.
    pub modes: Vec<String>,
}

/// The result of logging a hunter QSO: the persisted row, the refreshed today
/// stats, and whether this QSO is the one that *exactly* hit the daily goal.
#[derive(uniffi::Record)]
pub struct FfiLogQsoResult {
    pub qso: FfiQso,
    pub today: FfiTodayStats,
    /// `true` only on the QSO whose logging makes the count equal the daily goal
    /// (fires once, mirroring `dailyGoalReached`). Always `false` when the goal
    /// is disabled (0).
    pub daily_goal_reached: bool,
}

// ---------- API object ----------

/// Hunter-log API bound to a [`FieldStore`]. Holds no state of its own — the
/// active log and today stats are always derived from the store, so two API
/// instances (or an instance shared with the iOS manager) never drift.
#[derive(uniffi::Object)]
pub struct ActivityLogApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl ActivityLogApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        ActivityLogApi { store }
    }

    /// The currently active log, or `None`. Replaces the iOS `loadActiveLog`
    /// (UserDefaults id + fetch) — the `is_active = 1` row is the source of truth.
    pub fn active_log(&self) -> Result<Option<FfiActivityLog>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        Ok(active_logs(&store)?.into_iter().next().map(FfiActivityLog::from))
    }

    /// All logs, newest first (mirrors `getAllLogs`, ordered by `created_at`).
    pub fn all_logs(&self) -> Result<Vec<FfiActivityLog>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let mut rows = store.fetch_activity_logs(&ActivityLogFilter::default(), ACTIVE_SWEEP_LIMIT, 0)?;
        rows.sort_by_key(|log| std::cmp::Reverse(log.created_at));
        Ok(rows.into_iter().map(FfiActivityLog::from).collect())
    }

    /// Create and activate a new log, deactivating any previously active one
    /// (`createLog`). `grid` is the host's choice: the profile grid for a fixed
    /// station, or `None` when the profile tracks current location.
    pub fn create_log(
        &self,
        name: String,
        my_callsign: String,
        station_profile_id: Option<String>,
        grid: Option<String>,
    ) -> Result<FfiActivityLog, CwError> {
        let log = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            deactivate_active(&store, None)?;
            let log = ActivityLog {
                id: Uuid::new_v4().to_string(),
                name,
                my_callsign,
                created_at: now_ts(),
                station_profile_id,
                current_grid: grid,
                location_label: None,
                is_active: true,
                cloud_dirty_flag: true,
            };
            store.upsert_activity_log(&log)?;
            log
        };
        self.notify_activity_log();
        Ok(FfiActivityLog::from(log))
    }

    /// Activate an existing log (deactivating the previously active one). Returns
    /// `None` if `id` does not exist.
    pub fn activate_log(&self, id: String) -> Result<Option<FfiActivityLog>, CwError> {
        let log = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut log) = store.fetch_activity_log(&id)? else {
                return Ok(None);
            };
            deactivate_active(&store, Some(&id))?;
            log.is_active = true;
            log.cloud_dirty_flag = true;
            store.upsert_activity_log(&log)?;
            log
        };
        self.notify_activity_log();
        Ok(Some(FfiActivityLog::from(log)))
    }

    /// Deactivate the active log without deleting it (`deactivateLog`). No-op if
    /// nothing is active.
    pub fn deactivate_active_log(&self) -> Result<(), CwError> {
        {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            deactivate_active(&store, None)?;
        }
        self.notify_activity_log();
        Ok(())
    }

    /// Delete a log. The QSOs it linked remain (only the log record is removed),
    /// mirroring `deleteLog`.
    pub fn delete_log(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            store.delete_activity_log(&id)?;
        }
        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::ActivityLog, kind: FfiChangeKind::Delete });
        Ok(())
    }

    /// Switch the station profile for a log (`switchProfile`). `grid` follows the
    /// same host rule as `create_log`: pass the profile grid for a fixed station,
    /// `None` to leave the grid untouched (location-tracking profiles).
    pub fn switch_profile(
        &self,
        id: String,
        station_profile_id: String,
        grid: Option<String>,
    ) -> Result<Option<FfiActivityLog>, CwError> {
        self.mutate_log(&id, |log| {
            log.station_profile_id = Some(station_profile_id.clone());
            if let Some(grid) = grid.clone() {
                log.current_grid = Some(grid);
            }
        })
    }

    /// Update the current grid square (`updateGrid`).
    pub fn update_grid(&self, id: String, grid: String) -> Result<Option<FfiActivityLog>, CwError> {
        self.mutate_log(&id, |log| log.current_grid = Some(grid.clone()))
    }

    /// Update the free-text location label (`updateLocationLabel`).
    pub fn update_location_label(
        &self,
        id: String,
        label: Option<String>,
    ) -> Result<Option<FfiActivityLog>, CwError> {
        self.mutate_log(&id, |log| log.location_label = label.clone())
    }

    /// Log a hunter QSO into the active log (`logQSO`). Returns `None` if `log_id`
    /// does not resolve (the iOS `guard let log = activeLog` path).
    pub fn log_qso(&self, input: FfiLogQsoInput) -> Result<Option<FfiLogQsoResult>, CwError> {
        let (qso, today, presence_written) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(log) = store.fetch_activity_log(&input.log_id)? else {
                return Ok(None);
            };

            let qso = build_qso(&log, &input);
            store.upsert_qso(&qso)?;
            let presence_written = mark_for_upload(&store, &qso, &input)?;
            let today = today_stats(&store, &log.id)?;
            (qso, today, presence_written)
        };

        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        if presence_written {
            self.store.notify(FfiStoreChange {
                table: FfiStoreTable::ServicePresence,
                kind: FfiChangeKind::Upsert,
            });
        }

        let daily_goal_reached = input.daily_goal > 0 && today.qso_count == input.daily_goal;
        Ok(Some(FfiLogQsoResult { qso: FfiQso::from(qso), today, daily_goal_reached }))
    }

    /// Today's stats for a log (`refreshTodayStats`). Empty when `log_id` has no
    /// QSOs in today's UTC window.
    pub fn today_stats(&self, log_id: String) -> Result<FfiTodayStats, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        today_stats(&store, &log_id)
    }

    /// Today's recent QSOs for a log, newest first (`fetchRecentQSOs`).
    pub fn recent_qsos(&self, log_id: String, limit: i64) -> Result<Vec<FfiQso>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_qsos_for_session(&log_id, Some(utc_start_of_today()), limit)?;
        Ok(rows.into_iter().map(FfiQso::from).collect())
    }

    /// The worked-before dedup cache for today: uppercased callsign → the set of
    /// `band|MODE-FAMILY|park` keys worked today across *all* hunter logs. Port
    /// of `WorkedBeforeCache.loadToday`; a spot is a dupe when this map's entry
    /// for its callsign contains `hunter_band_mode_park_key(band, mode, park)`.
    pub fn worked_today(&self) -> Result<HashMap<String, Vec<String>>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_activity_log_qsos_since(utc_start_of_today(), TODAY_STATS_LIMIT)?;
        let mut map: HashMap<String, BTreeSet<String>> = HashMap::new();
        for qso in &rows {
            let band = qso.band.clone().unwrap_or_default();
            let mode = qso.mode.clone().unwrap_or_default();
            // A multi-park n-fer contributes one key per credited park so each
            // park's spot row crosses out independently; single-park QSOs yield
            // exactly one key, unchanged.
            let entry = map.entry(qso.callsign.to_uppercase()).or_default();
            for key in band_mode_park_keys(&band, &mode, qso.their_park.as_deref()) {
                entry.insert(key);
            }
        }
        Ok(map.into_iter().map(|(call, keys)| (call, keys.into_iter().collect())).collect())
    }
}

impl ActivityLogApi {
    /// Fetch → mutate → upsert → notify a single log. Returns `None` if absent.
    fn mutate_log(
        &self,
        id: &str,
        mutate: impl FnOnce(&mut ActivityLog),
    ) -> Result<Option<FfiActivityLog>, CwError> {
        let log = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut log) = store.fetch_activity_log(id)? else {
                return Ok(None);
            };
            mutate(&mut log);
            log.cloud_dirty_flag = true;
            store.upsert_activity_log(&log)?;
            log
        };
        self.notify_activity_log();
        Ok(Some(FfiActivityLog::from(log)))
    }

    fn notify_activity_log(&self) {
        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::ActivityLog, kind: FfiChangeKind::Upsert });
    }
}

// ---------- pure helpers ----------

fn now_ts() -> i64 {
    Utc::now().timestamp()
}

/// Unix-seconds timestamp of the start of *today* in UTC — the `refreshTodayStats`
/// window lower bound (`Calendar(UTC).startOfDay(for: Date())`).
fn utc_start_of_today() -> i64 {
    let today = Utc::now().date_naive();
    let start = today.and_hms_opt(0, 0, 0).expect("midnight is a valid time");
    Utc.from_utc_datetime(&start).timestamp()
}

/// The active logs (`is_active = 1`). At most one in normal operation.
fn active_logs(store: &Store) -> Result<Vec<ActivityLog>, CwError> {
    let filter = ActivityLogFilter { is_active: Some(true), ..Default::default() };
    Ok(store.fetch_activity_logs(&filter, ACTIVE_SWEEP_LIMIT, 0)?)
}

/// Deactivate every active log except `except`, persisting each. The
/// single-active-log invariant behind `createLog` / `activateLog`.
fn deactivate_active(store: &Store, except: Option<&str>) -> Result<(), CwError> {
    for mut log in active_logs(store)? {
        if Some(log.id.as_str()) == except {
            continue;
        }
        log.is_active = false;
        log.cloud_dirty_flag = true;
        store.upsert_activity_log(&log)?;
    }
    Ok(())
}

/// Build the QSO `logQSO` persists: uppercase callsign, log-stamped my-fields,
/// profile-stamped station fields, `is_activity_log_qso` + the session link.
fn build_qso(log: &ActivityLog, input: &FfiLogQsoInput) -> Qso {
    let now = now_ts();
    Qso {
        id: Uuid::new_v4().to_string(),
        callsign: input.callsign.to_uppercase(),
        band: Some(input.band.clone()),
        mode: Some(input.mode.clone()),
        freq_khz: input.frequency_mhz.map(|mhz| mhz * 1000.0),
        qso_date: now,
        my_grid: log.current_grid.clone(),
        their_grid: input.their_grid.clone(),
        rst_sent: Some(input.rst_sent.clone()),
        rst_rcvd: Some(input.rst_received.clone()),
        my_callsign: Some(log.my_callsign.clone()),
        park: None,
        their_park: input.their_park.clone(),
        notes: input.notes.clone(),
        // Notes came from the user's quick-entry form — tag as user-authored (CAR-243).
        notes_user_authored: input.notes.as_deref().map(|n| !n.is_empty()).unwrap_or(false),
        spot_comments_data: None,
        callsign_change_note: None,
        original_callsign: None,
        import_source_raw_value: "logger".to_string(),
        imported_at: now,
        modified_at: Some(now),
        raw_adif: None,
        name: input.name.clone(),
        qth: None,
        state: input.state.clone(),
        country: input.country.clone(),
        power: input.power,
        my_rig: input.my_rig.clone(),
        station_profile_name: input.station_profile_name.clone(),
        sota_ref: input.sota_ref.clone(),
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
        is_activity_log_qso: true,
        station_callsign: None,
        logging_session_id: Some(log.id.clone()),
        dirty: true,
        sat_name: None,
        prop_mode: None,
    }
}

/// Route a freshly-logged hunter QSO to its upload destinations. Mirrors
/// `markForUpload`: skip metadata pseudo-modes entirely; mark QRZ when
/// configured; **never** POTA; and attempt the configured LoFi/ClubLog marks
/// (which `mark_needs_upload`'s `supports_upload` guard turns into no-ops, as in
/// iOS). Returns whether any `ServicePresence` row was written.
fn mark_for_upload(store: &Store, qso: &Qso, input: &FfiLogQsoInput) -> Result<bool, CwError> {
    if qso.mode.as_deref().map(is_metadata_mode).unwrap_or(false) {
        return Ok(false);
    }
    let mut wrote = false;
    if input.upload_qrz {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Qrz)?;
    }
    // Activity-log QSOs never go to POTA (no operator park reference).
    if input.upload_lofi {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Lofi)?;
    }
    if input.upload_clublog {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Clublog)?;
    }
    Ok(wrote)
}

/// Fold today's visible QSOs for a log into `(count, bands, modes)`.
fn today_stats(store: &Store, log_id: &str) -> Result<FfiTodayStats, CwError> {
    let rows = store.fetch_qsos_for_session(log_id, Some(utc_start_of_today()), TODAY_STATS_LIMIT)?;
    let mut bands: BTreeSet<String> = BTreeSet::new();
    let mut modes: BTreeSet<String> = BTreeSet::new();
    for qso in &rows {
        if let Some(band) = &qso.band {
            bands.insert(band.clone());
        }
        if let Some(mode) = &qso.mode {
            modes.insert(mode.clone());
        }
    }
    Ok(FfiTodayStats {
        qso_count: rows.len() as i64,
        bands: bands.into_iter().collect(),
        modes: modes.into_iter().collect(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use cw_store::ServicePresenceFilter;

    fn api() -> ActivityLogApi {
        ActivityLogApi::new(Arc::new(FieldStore::open_in_memory("k".into()).unwrap()))
    }

    fn base_input(log_id: &str) -> FfiLogQsoInput {
        FfiLogQsoInput {
            log_id: log_id.to_string(),
            callsign: "w1aw".to_string(),
            band: "20m".to_string(),
            mode: "CW".to_string(),
            frequency_mhz: Some(14.074),
            rst_sent: "599".to_string(),
            rst_received: "599".to_string(),
            their_grid: None,
            their_park: None,
            sota_ref: None,
            notes: None,
            name: None,
            state: None,
            country: None,
            power: None,
            my_rig: None,
            station_profile_name: None,
            upload_qrz: false,
            upload_lofi: false,
            upload_clublog: false,
            daily_goal: 0,
        }
    }

    #[test]
    fn create_log_enforces_single_active() {
        let api = api();
        let first = api.create_log("A".into(), "W6JY".into(), None, Some("CM87".into())).unwrap();
        assert!(first.is_active);
        assert_eq!(api.active_log().unwrap().unwrap().id, first.id);

        let second = api.create_log("B".into(), "W6JY".into(), None, None).unwrap();
        assert!(second.is_active);
        // Only the newest is active.
        assert_eq!(api.active_log().unwrap().unwrap().id, second.id);
        assert_eq!(api.all_logs().unwrap().len(), 2);
    }

    #[test]
    fn activate_log_deactivates_previous_and_missing_is_none() {
        let api = api();
        let first = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        let second = api.create_log("B".into(), "W6JY".into(), None, None).unwrap();
        let reactivated = api.activate_log(first.id.clone()).unwrap().unwrap();
        assert!(reactivated.is_active);
        assert_eq!(api.active_log().unwrap().unwrap().id, first.id);
        // The other log is now inactive.
        let logs = api.all_logs().unwrap();
        let second_row = logs.iter().find(|log| log.id == second.id).unwrap();
        assert!(!second_row.is_active);

        assert!(api.activate_log("no-such-id".into()).unwrap().is_none());
    }

    #[test]
    fn log_qso_enriches_links_and_uppercases() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, Some("CM87".into())).unwrap();

        let mut input = base_input(&log.id);
        input.notes = Some("nice sig".into());
        let result = api.log_qso(input).unwrap().unwrap();
        let qso = result.qso;

        assert_eq!(qso.callsign, "W1AW"); // uppercased
        assert_eq!(qso.my_callsign.as_deref(), Some("W6JY")); // stamped from log
        assert_eq!(qso.my_grid.as_deref(), Some("CM87")); // stamped from log grid
        assert_eq!(qso.logging_session_id.as_deref(), Some(log.id.as_str())); // linked
        assert!(qso.is_activity_log_qso);
        assert!(qso.dirty);
        assert!(qso.notes_user_authored); // non-empty notes
        assert_eq!(qso.freq_khz, Some(14_074.0)); // MHz -> kHz
        assert_eq!(qso.import_source_raw_value, "logger");

        // Today stats reflect the one QSO.
        assert_eq!(result.today.qso_count, 1);
        assert_eq!(result.today.bands, vec!["20m".to_string()]);
        assert_eq!(result.today.modes, vec!["CW".to_string()]);
    }

    #[test]
    fn log_qso_missing_log_returns_none() {
        let api = api();
        assert!(api.log_qso(base_input("no-such-log")).unwrap().is_none());
    }

    #[test]
    fn empty_notes_are_not_user_authored() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        let mut input = base_input(&log.id);
        input.notes = Some(String::new());
        let qso = api.log_qso(input).unwrap().unwrap().qso;
        assert!(!qso.notes_user_authored);
    }

    #[test]
    fn upload_routing_marks_qrz_only_never_pota_lofi_clublog() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        let mut input = base_input(&log.id);
        input.upload_qrz = true;
        input.upload_lofi = true; // no-op (supports_upload == false)
        input.upload_clublog = true; // no-op
        let result = api.log_qso(input).unwrap().unwrap();

        let store = api.store.inner.lock().unwrap();
        let presences = store
            .fetch_service_presences(
                &ServicePresenceFilter { qso_id: Some(result.qso.id.clone()), ..Default::default() },
                100,
                0,
            )
            .unwrap();
        // Exactly one presence: QRZ, needs upload. No POTA / LoFi / ClubLog.
        assert_eq!(presences.len(), 1);
        assert_eq!(presences[0].service_type_raw_value, "qrz");
        assert!(presences[0].needs_upload);
    }

    #[test]
    fn metadata_mode_qso_skips_upload() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        let mut input = base_input(&log.id);
        input.mode = "WEATHER".into();
        input.upload_qrz = true;
        let result = api.log_qso(input).unwrap().unwrap();

        let store = api.store.inner.lock().unwrap();
        let count = store
            .fetch_service_presences(
                &ServicePresenceFilter { qso_id: Some(result.qso.id.clone()), ..Default::default() },
                100,
                0,
            )
            .unwrap()
            .len();
        assert_eq!(count, 0);
    }

    #[test]
    fn daily_goal_fires_once_at_exact_equality() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();

        let mut first = base_input(&log.id);
        first.daily_goal = 2;
        assert!(!api.log_qso(first).unwrap().unwrap().daily_goal_reached); // count 1 != 2

        let mut second = base_input(&log.id);
        second.daily_goal = 2;
        assert!(api.log_qso(second).unwrap().unwrap().daily_goal_reached); // count 2 == 2

        let mut third = base_input(&log.id);
        third.daily_goal = 2;
        assert!(!api.log_qso(third).unwrap().unwrap().daily_goal_reached); // count 3 != 2
    }

    #[test]
    fn recent_qsos_returns_today_newest_first() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        for call in ["k1aa", "k2bb", "k3cc"] {
            let mut input = base_input(&log.id);
            input.callsign = call.into();
            api.log_qso(input).unwrap();
        }
        let recent = api.recent_qsos(log.id.clone(), 2).unwrap();
        assert_eq!(recent.len(), 2);
        // All three share a timestamp second; assert the window/limit, not order.
        assert!(recent.iter().all(|qso| qso.logging_session_id.as_deref() == Some(log.id.as_str())));
    }

    #[test]
    fn worked_today_maps_callsign_to_dedup_keys() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        // Two contacts, one a same-band/mode dupe of the first.
        for (call, band, mode) in [("k1aa", "20m", "CW"), ("k1aa", "40m", "SSB"), ("k2bb", "20m", "CW")] {
            let mut input = base_input(&log.id);
            input.callsign = call.into();
            input.band = band.into();
            input.mode = mode.into();
            api.log_qso(input).unwrap();
        }
        let map = api.worked_today().unwrap();
        let k1 = map.get("K1AA").unwrap();
        assert!(k1.contains(&"20m|CW|".to_string()));
        assert!(k1.contains(&"40m|PHONE|".to_string()));
        assert_eq!(map.get("K2BB").unwrap(), &vec!["20m|CW|".to_string()]);
    }

    #[test]
    fn worked_today_explodes_nfer_into_per_park_keys() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        // One QSO crediting a 2-fer.
        let mut input = base_input(&log.id);
        input.callsign = "k1aa".into();
        input.band = "20m".into();
        input.mode = "CW".into();
        input.their_park = Some("US-1044, US-3791".into());
        api.log_qso(input).unwrap();

        let map = api.worked_today().unwrap();
        let k1 = map.get("K1AA").unwrap();
        // Both parks deduplicate independently — each single-park spot row's key
        // is present, so both rows cross out from the single logged contact.
        assert!(k1.contains(&"20m|CW|US-1044".to_string()));
        assert!(k1.contains(&"20m|CW|US-3791".to_string()));
        // The atomic comma-joined key is NOT stored (that was the old defect).
        assert!(!k1.contains(&"20m|CW|US-1044, US-3791".to_string()));
    }

    #[test]
    fn delete_log_keeps_linked_qsos() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        api.log_qso(base_input(&log.id)).unwrap();
        api.delete_log(log.id.clone()).unwrap();
        assert!(api.active_log().unwrap().is_none());
        // The QSO survives the log deletion.
        let store = api.store.inner.lock().unwrap();
        assert_eq!(store.qso_count().unwrap(), 1);
    }

    #[test]
    fn switch_profile_and_grid_updates() {
        let api = api();
        let log = api.create_log("A".into(), "W6JY".into(), None, None).unwrap();
        let switched = api
            .switch_profile(log.id.clone(), "profile-2".into(), Some("DM79".into()))
            .unwrap()
            .unwrap();
        assert_eq!(switched.station_profile_id.as_deref(), Some("profile-2"));
        assert_eq!(switched.current_grid.as_deref(), Some("DM79"));

        let regridded = api.update_grid(log.id.clone(), "EN50".into()).unwrap().unwrap();
        assert_eq!(regridded.current_grid.as_deref(), Some("EN50"));
    }
}
