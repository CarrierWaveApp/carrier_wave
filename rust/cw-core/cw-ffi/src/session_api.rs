//! Activation-session lifecycle + QSO logging — port of the iOS
//! `LoggingSessionManager` (the activation-centric counterpart to the hunter
//! `ActivityLogManager`).
//!
//! The iOS manager is a 19-file `@MainActor` orchestrator wrapping timers, Live
//! Activity, spotting, radio, and continuity around a SwiftData store. This API
//! ports the **portable kernel** the migration needs cross-platform:
//!
//! - **lifecycle transitions** — `pause`/`resume`/`end`/`reopen`, including
//!   resume's "pause whatever session was active" rule and end's
//!   `endedAt = now, status = completed`;
//! - **`log_qso` association** — derive the band from the effective frequency,
//!   stamp the session's my-fields / park / WWFF ref onto the QSO, combine the
//!   session `qsoComment` with the user notes, **leave `sotaRef` nil** (the
//!   operator's summit lives on the session as `MY_SOTA_REF`, not on each
//!   contact), increment the session QSO count, and route uploads
//!   (QRZ + POTA-when-this-is-a-POTA-activation; LoFi/ClubLog stay no-ops);
//! - **`merge_sessions`** — reassign QSOs / spots / recordings, expand the
//!   target's time bounds, fold the QSO counts, concat photo filenames, delete
//!   the source shell;
//! - **`delete_session`** — hide the linked QSOs (dropping their pending upload
//!   markers) and remove the session.
//!
//! End-of-session follow-ons ported here (each mirrors a `LoggingSessionManager`
//! extension): the NOAA conditions fill-only-if-nil merge (`+Conditions`,
//! `record_conditions`) and the end-of-session WPM averaging into
//! `ActivationMetadata` (`saveAverageWPM`, `save_average_wpm`). The **network
//! fetch** for conditions and the **WPM parse** from spot-comment text stay
//! host-side (Swift keeps the `NOAAClient` + the `\d+ WPM` regex); this API owns
//! the fill-if-nil merge, the `(primary_park, UTC-day)` keying, and the
//! find-or-create upsert so both platforms agree. The POTA UTC-midnight split
//! (`+POTASplit`, `split_at_utc_midnight`) is ported too — it reads/rewrites the
//! structured `rove_stop` table (the portable replacement for the Swift-encoded
//! `rove_stops_data` blob), so the day-boundary cloning + QSO/recording/rove-stop
//! reassignment is shared. The *live* UTC-rollover timer + service restarts stay
//! host-side (`+UTCDayBoundary`).
//! Session *creation* stays a host concern (a large profile-driven form) — it
//! lands via the existing `FieldStore.upsert_logging_session`; this API drives
//! the row from there. Contest sessions ride the same path: `log_qso` stamps
//! the optional contest fields (`isContest` exchange-copy branch) and the
//! scoring engine lives in `contest_api` (2026-07-04 contest port).

use std::collections::BTreeSet;
use std::sync::Arc;

use chrono::{TimeZone, Utc};
use cw_domain::band::BandUtilities;
use cw_domain::prefix_suggest::{self, SuggestionQso};
use cw_domain::{default_rst, is_metadata_mode};
use cw_domain::service_type::ServiceType;
use cw_store::{
    ActivationMetadata, LoggingSession, Qso, QsoFilter, RoveStop, Store, WebSDRRecordingFilter,
};
use uuid::Uuid;

use crate::entities::activation_metadata::FfiActivationMetadata;
use crate::entities::logging_session::FfiLoggingSession;
use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::upload::mark_needs_upload;
use crate::{CwError, FfiQso, FieldStore};

/// Upper bound for the "pause any other active session" sweep.
const ACTIVE_SWEEP_LIMIT: i64 = 1_000;

// ---------- DTOs ----------

/// Per-contact inputs to `log_qso`. Everything the session itself supplies
/// (frequency/mode/park/WWFF/power/rig/callsign/grid/qsoComment/stationCallsign)
/// is read from the stored session; this carries the contact fields, the
/// optional per-QSO overrides, and the "is this service configured" booleans.
#[derive(uniffi::Record)]
pub struct FfiSessionLogInput {
    pub session_id: String,
    pub callsign: String,
    pub rst_sent: String,
    pub rst_received: String,
    pub their_grid: Option<String>,
    pub their_park: Option<String>,
    pub notes: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub their_license_class: Option<String>,
    pub aoa_code: Option<String>,
    pub callsign_change_note: Option<String>,
    /// Quick-entry frequency override in **MHz**; falls back to the session.
    pub frequency_override_mhz: Option<f64>,
    /// Quick-entry mode override; falls back to the session mode.
    pub mode_override: Option<String>,
    /// Unix-seconds timestamp override; defaults to now.
    pub timestamp_override: Option<i64>,
    /// Contest fields (the `isContest` branch of `logQSO`): stamped verbatim
    /// onto the QSO when the session is a contest. All default `None` so
    /// non-contest callers are unchanged.
    #[uniffi(default = None)]
    pub contest_name: Option<String>,
    #[uniffi(default = None)]
    pub contest_serial_sent: Option<i64>,
    #[uniffi(default = None)]
    pub contest_serial_received: Option<i64>,
    /// Space-joined sent exchange tokens.
    #[uniffi(default = None)]
    pub contest_exchange_sent: Option<String>,
    /// Space-joined received exchange tokens.
    #[uniffi(default = None)]
    pub contest_exchange_received: Option<String>,
    /// ADIF SAT_NAME — satellite short name (e.g. "AO-91"). Set by the satellite
    /// quick-log flow; `None` for terrestrial QSOs.
    #[uniffi(default = None)]
    pub sat_name: Option<String>,
    /// ADIF PROP_MODE — always "SAT" when `sat_name` is set.
    #[uniffi(default = None)]
    pub prop_mode: Option<String>,
    pub upload_qrz: bool,
    /// Whether POTA upload is configured. Only routed when the session is a POTA
    /// activation.
    pub upload_pota: bool,
    pub upload_lofi: bool,
    pub upload_clublog: bool,
}

/// Result of logging a session QSO: the persisted row + the session's new count.
#[derive(uniffi::Record)]
pub struct FfiSessionLogResult {
    pub qso: FfiQso,
    pub qso_count: i64,
}

/// The per-session configuration a logger form renders from — the shared shape
/// so iOS and Android draw the same fields/defaults from one source instead of
/// each re-deriving them (iOS previously computed `defaultRST`, band, and the
/// POTA/contest field-visibility in `LoggerView`). Read via
/// [`SessionApi::logger_form_config`].
#[derive(uniffi::Record)]
pub struct FfiLoggerFormConfig {
    /// Effective session mode (e.g. `CW`, `SSB`, `FT8`).
    pub mode: String,
    /// Band derived from the session frequency (e.g. `20m`), `None` if unknown.
    pub band: Option<String>,
    /// Session operating frequency in MHz, `None` if the session has none.
    pub frequency_mhz: Option<f64>,
    /// Default RST to prefill the Sent field when the operator leaves it blank.
    pub default_rst_sent: String,
    /// Default RST to prefill the Received field when left blank.
    pub default_rst_received: String,
    /// Whether this is a POTA activation (surfaces the park-to-park field).
    pub is_pota: bool,
    /// Whether this is a WWFF activation.
    pub is_wwff: bool,
    /// Whether this is a contest session (surfaces the exchange fields).
    pub is_contest: bool,
    /// Whether to show a their-park (park-to-park) input — POTA activations.
    pub show_their_park: bool,
    /// Whether to show contest-exchange inputs — contest sessions.
    pub show_contest_exchange: bool,
}

/// Conditions payload for `record_conditions` — the solar/weather values the
/// host fetched (from `NOAAClient`). Every field is optional; the merge fills
/// only where the target is empty. Mirrors the `SolarConditions` +
/// `WeatherConditions` fields `LoggingSessionManager+Conditions` stores.
#[derive(uniffi::Record)]
pub struct FfiConditionsInput {
    /// Free-text solar description (`solarConditions`).
    pub solar_conditions: Option<String>,
    /// Free-text weather description (`weather`).
    pub weather: Option<String>,
    pub solar_k_index: Option<f64>,
    pub solar_flux: Option<f64>,
    pub solar_sunspots: Option<i64>,
    pub solar_propagation_rating: Option<String>,
    pub solar_a_index: Option<i64>,
    pub solar_band_conditions: Option<String>,
    pub solar_timestamp: Option<i64>,
    pub weather_temperature_f: Option<f64>,
    pub weather_temperature_c: Option<f64>,
    pub weather_humidity: Option<i64>,
    pub weather_wind_speed: Option<f64>,
    pub weather_wind_direction: Option<String>,
    pub weather_description: Option<String>,
    pub weather_timestamp: Option<i64>,
}

/// Result of `record_conditions`: the updated session, plus the touched
/// `ActivationMetadata` row when the session is a POTA activation (`None`
/// otherwise, matching the iOS "metadata is POTA-only" rule).
#[derive(uniffi::Record)]
pub struct FfiConditionsResult {
    pub session: FfiLoggingSession,
    pub metadata: Option<FfiActivationMetadata>,
}

// ---------- API object ----------

/// Activation-session API bound to a [`FieldStore`]. Stateless — every operation
/// reads the session row from the store, so it never drifts from the iOS
/// manager sharing the same store.
#[derive(uniffi::Object)]
pub struct SessionApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl SessionApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        SessionApi { store }
    }

    /// Pause a session (`pause`: `status = paused`). `None` if `id` is absent.
    pub fn pause_session(&self, id: String) -> Result<Option<FfiLoggingSession>, CwError> {
        self.transition(&id, |s| s.status_raw_value = "paused".to_string())
    }

    /// Resume a session (`resume`: `status = active`), first pausing whatever
    /// other session was active (the iOS `resumeSession(_:)` rule).
    pub fn resume_session(&self, id: String) -> Result<Option<FfiLoggingSession>, CwError> {
        let session = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut session) = store.fetch_logging_session(&id)? else {
                return Ok(None);
            };
            pause_other_active(&store, &id)?;
            session.status_raw_value = "active".to_string();
            session.cloud_dirty_flag = true;
            store.upsert_logging_session(&session)?;
            session
        };
        self.notify_session();
        Ok(Some(FfiLoggingSession::from(session)))
    }

    /// End a session (`end`: `endedAt = now, status = completed`).
    pub fn end_session(&self, id: String) -> Result<Option<FfiLoggingSession>, CwError> {
        self.transition(&id, |s| {
            s.ended_at = Some(now_ts());
            s.status_raw_value = "completed".to_string();
        })
    }

    /// Reopen a completed session for more QSOs (`reopenSession`: clear `endedAt`,
    /// then resume — pausing any other active session).
    pub fn reopen_session(&self, id: String) -> Result<Option<FfiLoggingSession>, CwError> {
        {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut session) = store.fetch_logging_session(&id)? else {
                return Ok(None);
            };
            session.ended_at = None;
            session.cloud_dirty_flag = true;
            store.upsert_logging_session(&session)?;
        }
        self.resume_session(id)
    }

    /// Delete a session, hiding its linked QSOs (and dropping their pending
    /// upload markers) — `deleteSession`. Returns whether the session existed.
    pub fn delete_session(&self, id: String) -> Result<bool, CwError> {
        let existed = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            if store.fetch_logging_session(&id)?.is_none() {
                return Ok(false);
            }
            store.hide_qsos_in_session(&id)?;
            store.delete_logging_session(&id)?;
            true
        };
        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::LoggingSession,
            kind: FfiChangeKind::Delete,
        });
        Ok(existed)
    }

    /// Log a QSO into a session (`logQSO` + `insertAndFinalize`). `None` if the
    /// session is absent.
    pub fn log_qso(
        &self,
        input: FfiSessionLogInput,
    ) -> Result<Option<FfiSessionLogResult>, CwError> {
        let (qso, qso_count, presence_written) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut session) = store.fetch_logging_session(&input.session_id)? else {
                return Ok(None);
            };

            let qso = build_session_qso(&session, &input);
            store.upsert_qso(&qso)?;

            // session.incrementQSOCount()
            session.qso_count += 1;
            session.cloud_dirty_flag = true;
            store.upsert_logging_session(&session)?;

            let presence_written = mark_for_upload(&store, &qso, &session, &input)?;
            (qso, session.qso_count, presence_written)
        };

        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        self.notify_session();
        if presence_written {
            self.store.notify(FfiStoreChange {
                table: FfiStoreTable::ServicePresence,
                kind: FfiChangeKind::Upsert,
            });
        }

        Ok(Some(FfiSessionLogResult { qso: FfiQso::from(qso), qso_count }))
    }

    /// Visible QSOs in a session, newest first (`getSessionQSOs`).
    pub fn session_qsos(&self, session_id: String, limit: i64) -> Result<Vec<FfiQso>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_qsos_for_session(&session_id, None, limit)?;
        Ok(rows.into_iter().map(FfiQso::from).collect())
    }

    /// The single in-progress session (`status = active`, not yet ended), or
    /// `None` when idle. Rust is canonical for "which session is active": the
    /// host reads this on launch and after starting/ending a session to decide
    /// whether to show the logger, instead of keeping its own active-session
    /// pointer. Replaces the iOS `LoggingSessionManager.activeSession` +
    /// UserDefaults `activeLoggingSessionId` restoration.
    pub fn current_session(&self) -> Result<Option<FfiLoggingSession>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_current_session()?.map(FfiLoggingSession::from))
    }

    /// Position-local prefix hot-key suggestions for the logger keyboard
    /// accessory (CAR-290). `current_grid` is the operator's current
    /// maidenhead grid at any precision; pass `None` to anchor on the most
    /// recently logged operating position instead. Suggestions come only
    /// from QSOs logged near the anchor (widening once), with a
    /// country-level prefix as the cold-start fallback — never from the
    /// operator's home entity or far-away logbook history. `limit = 0`
    /// applies the default (8).
    pub fn suggested_prefixes(
        &self,
        current_grid: Option<String>,
        limit: u32,
    ) -> Result<Vec<String>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_qsos(&QsoFilter::default(), 1000, 0)?;
        let entries: Vec<SuggestionQso> = rows
            .into_iter()
            .filter(|q| !q.is_hidden)
            .map(|q| SuggestionQso {
                callsign: q.callsign,
                my_grid: q.my_grid,
                qso_date: q.qso_date,
            })
            .collect();
        Ok(prefix_suggest::suggested_prefixes(
            &entries,
            current_grid.as_deref(),
            limit as usize,
        ))
    }

    /// The logger-form configuration for a session — effective mode/band/frequency,
    /// the RST defaults, and the POTA/WWFF/contest field-visibility flags. Both
    /// platforms render from this so the form shape stays identical. `None` if the
    /// session is absent.
    pub fn logger_form_config(
        &self,
        session_id: String,
    ) -> Result<Option<FfiLoggerFormConfig>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(session) = store.fetch_logging_session(&session_id)? else {
            return Ok(None);
        };
        let mode = session.mode.clone();
        let band = session
            .frequency
            .map(|mhz| mhz * 1000.0)
            .and_then(|khz| BandUtilities::derive_band(Some(khz)))
            .map(str::to_string);
        let default = default_rst(&mode);
        let is_pota = is_pota(&session);
        let is_wwff = is_wwff(&session);
        let is_contest = session.contest_id.as_deref().is_some_and(|id| !id.is_empty());
        Ok(Some(FfiLoggerFormConfig {
            mode,
            band,
            frequency_mhz: session.frequency,
            default_rst_sent: default.clone(),
            default_rst_received: default,
            is_pota,
            is_wwff,
            is_contest,
            show_their_park: is_pota,
            show_contest_exchange: is_contest,
        }))
    }

    /// Merge `source_id` into `target_id` (`mergeSessions`): reassign QSOs / spots
    /// / recordings, expand the target's time bounds, fold the QSO counts, concat
    /// photo filenames, then delete the source. Returns whether both existed.
    pub fn merge_sessions(
        &self,
        source_id: String,
        target_id: String,
    ) -> Result<bool, CwError> {
        let merged = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let (Some(source), Some(mut target)) =
                (store.fetch_logging_session(&source_id)?, store.fetch_logging_session(&target_id)?)
            else {
                return Ok(false);
            };

            store.reassign_qsos_to_session(&source_id, &target_id)?;
            store.reassign_session_spots_to_session(&source_id, &target_id)?;
            store.reassign_websdr_recordings_to_session(&source_id, &target_id)?;

            // Expand target time bounds to cover source.
            if source.started_at < target.started_at {
                target.started_at = source.started_at;
            }
            if let (Some(src_end), Some(tgt_end)) = (source.ended_at, target.ended_at) {
                if src_end > tgt_end {
                    target.ended_at = Some(src_end);
                }
            }
            // Recalculate target QSO count + concat photo filenames.
            target.qso_count += source.qso_count;
            target.photo_filenames =
                concat_photo_filenames(&target.photo_filenames, &source.photo_filenames);
            target.cloud_dirty_flag = true;

            store.upsert_logging_session(&target)?;
            store.delete_logging_session(&source_id)?;
            true
        };

        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::SessionSpot, kind: FfiChangeKind::Upsert });
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::LoggingSession,
            kind: FfiChangeKind::Upsert,
        });
        Ok(merged)
    }

    /// Fill the session's conditions where empty and, for a POTA activation, the
    /// matching `ActivationMetadata` row (`recordConditions` → `storeConditionsOnSession`
    /// + `storeConditionsMetadata`). Text fields fill only when the target is
    /// empty (nil for the session; nil-**or-empty-string** for the metadata,
    /// matching the stricter Swift check); the structured solar / weather blocks
    /// fill only when the target has no data of that kind. `None` if the session
    /// is absent.
    pub fn record_conditions(
        &self,
        session_id: String,
        conditions: FfiConditionsInput,
    ) -> Result<Option<FfiConditionsResult>, CwError> {
        let (session, metadata) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut session) = store.fetch_logging_session(&session_id)? else {
                return Ok(None);
            };
            if apply_conditions_to_session(&mut session, &conditions) {
                session.cloud_dirty_flag = true;
                store.upsert_logging_session(&session)?;
            }

            // Metadata is written only for POTA activations with a park ref.
            let park = session.park_reference.as_deref().filter(|p| !p.is_empty());
            let metadata = match (is_pota(&session), park) {
                (true, Some(park)) => {
                    let primary = primary_park(park);
                    let date = utc_start_of_day(session.started_at);
                    let existing = store.fetch_activation_metadata(&primary, date)?;
                    let is_new = existing.is_none();
                    let mut meta = existing.unwrap_or_else(|| blank_metadata(&primary, date));
                    let changed = apply_conditions_to_metadata(&mut meta, &conditions);
                    if is_new || changed {
                        meta.cloud_dirty_flag = true;
                        store.upsert_activation_metadata(&meta)?;
                    }
                    Some(meta)
                }
                _ => None,
            };
            (session, metadata)
        };

        self.notify_session();
        if metadata.is_some() {
            self.store.notify(FfiStoreChange {
                table: FfiStoreTable::ActivationMetadata,
                kind: FfiChangeKind::Upsert,
            });
        }
        Ok(Some(FfiConditionsResult {
            session: FfiLoggingSession::from(session),
            metadata: metadata.map(FfiActivationMetadata::from),
        }))
    }

    /// Average the supplied per-spot WPM values and store the result on the
    /// session's `ActivationMetadata` (`saveAverageWPM`). The host pre-parses the
    /// WPM integers from spot-comment text (the `\d+ WPM` regex stays Swift); this
    /// owns the **integer-truncating** average, the `(primary_park, UTC-day-of-
    /// startedAt)` key, and the find-or-create upsert. Unlike the conditions
    /// merge, `average_wpm` **always overwrites**. `None` when there are no WPM
    /// values, the session is absent, or it has no park reference.
    pub fn save_average_wpm(
        &self,
        session_id: String,
        wpm_values: Vec<i32>,
    ) -> Result<Option<FfiActivationMetadata>, CwError> {
        if wpm_values.is_empty() {
            return Ok(None);
        }
        let metadata = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(session) = store.fetch_logging_session(&session_id)? else {
                return Ok(None);
            };
            let Some(park) = session.park_reference.as_deref().filter(|p| !p.is_empty()) else {
                return Ok(None);
            };
            let primary = primary_park(park);
            let date = utc_start_of_day(session.started_at);
            let sum: i64 = wpm_values.iter().map(|&wpm| i64::from(wpm)).sum();
            // Integer division truncates — matches Swift's `wpms.reduce(0,+) / wpms.count`.
            let average = sum / wpm_values.len() as i64;

            let mut meta = store
                .fetch_activation_metadata(&primary, date)?
                .unwrap_or_else(|| blank_metadata(&primary, date));
            meta.average_wpm = Some(average);
            meta.cloud_dirty_flag = true;
            store.upsert_activation_metadata(&meta)?;
            meta
        };
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::ActivationMetadata,
            kind: FfiChangeKind::Upsert,
        });
        Ok(Some(FfiActivationMetadata::from(metadata)))
    }

    /// Split a completed multi-day session at UTC midnight (`splitPOTAAtUTCMidnight`):
    /// group the session's QSOs by UTC day, keep the original for the first day,
    /// clone a completed session per subsequent day, and reassign that day's QSOs +
    /// WebSDR recordings + rove stops. Rove stops come from the structured
    /// `rove_stop` table (not the Swift blob) and each split session's stops are
    /// rewritten there. Returns every session after the split — the mutated
    /// original first, then the new ones — or an **empty vec** when no split was
    /// needed (session absent, no QSOs, or all on one UTC day). The caller reflects
    /// the returned sessions + re-reads each one's QSOs / recordings / rove stops.
    pub fn split_at_utc_midnight(
        &self,
        session_id: String,
    ) -> Result<Vec<FfiLoggingSession>, CwError> {
        let sessions = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut original) = store.fetch_logging_session(&session_id)? else {
                return Ok(Vec::new());
            };
            let all_qsos = store.fetch_all_qsos_for_session(&session_id, MAX_SPLIT_QSOS)?;
            if all_qsos.is_empty() {
                return Ok(Vec::new());
            }

            // Distinct UTC days, ascending (BTreeSet is sorted).
            let qso_dates: Vec<i64> = all_qsos.iter().map(|qso| qso.qso_date).collect();
            let sorted_days: Vec<i64> =
                qso_dates.iter().map(|&ts| utc_start_of_day(ts)).collect::<BTreeSet<_>>().into_iter().collect();
            if sorted_days.len() <= 1 {
                return Ok(Vec::new());
            }

            let original_ended_at = original.ended_at;
            let stops = store.fetch_rove_stops(&session_id)?;
            let first_day = sorted_days[0];
            let second_midnight = sorted_days[1];

            // First UTC day keeps the original session (bounds + count + clipped stops).
            original.ended_at = Some(second_midnight);
            original.qso_count =
                qso_dates.iter().filter(|&&ts| utc_start_of_day(ts) == first_day).count() as i64;
            original.cloud_dirty_flag = true;
            store.upsert_logging_session(&original)?;
            store.replace_rove_stops(
                &original.id,
                &split_stops(&stops, first_day, second_midnight, &qso_dates),
            )?;

            // A new completed session per subsequent UTC day.
            let mut session_by_day: Vec<(i64, String)> = vec![(first_day, original.id.clone())];
            let mut result = vec![FfiLoggingSession::from(original.clone())];
            for index in 1..sorted_days.len() {
                let day = sorted_days[index];
                let next_midnight = if index + 1 < sorted_days.len() {
                    sorted_days[index + 1]
                } else {
                    original_ended_at.unwrap_or(day + SECONDS_PER_DAY)
                };
                let day_count =
                    qso_dates.iter().filter(|&&ts| utc_start_of_day(ts) == day).count() as i64;
                let park = park_active_at(day, &stops).or_else(|| original.park_reference.clone());
                let new_session =
                    clone_split_session(&original, park, day, next_midnight, day_count);
                store.upsert_logging_session(&new_session)?;
                store.replace_rove_stops(
                    &new_session.id,
                    &split_stops(&stops, day, next_midnight, &qso_dates),
                )?;
                session_by_day.push((day, new_session.id.clone()));
                result.push(FfiLoggingSession::from(new_session));
            }

            // Reassign each QSO to the session that owns its UTC day (first-day QSOs
            // already belong to the original).
            for mut qso in all_qsos {
                let day = utc_start_of_day(qso.qso_date);
                if day == first_day {
                    continue;
                }
                if let Some((_, target)) = session_by_day.iter().find(|(dday, _)| *dday == day) {
                    qso.logging_session_id = Some(target.clone());
                    qso.dirty = true;
                    store.upsert_qso(&qso)?;
                }
            }

            // Reassign WebSDR recordings by their start day.
            let filter = WebSDRRecordingFilter {
                logging_session_id: Some(session_id.clone()),
                ..Default::default()
            };
            for mut rec in store.fetch_websdr_recordings(&filter, MAX_SPLIT_QSOS, 0)? {
                let day = utc_start_of_day(rec.started_at);
                if let Some((_, target)) = session_by_day.iter().find(|(dday, _)| *dday == day) {
                    if rec.logging_session_id != *target {
                        rec.logging_session_id = target.clone();
                        store.upsert_websdr_recording(&rec)?;
                    }
                }
            }

            result
        };

        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::LoggingSession, kind: FfiChangeKind::Upsert });
        self.store.notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::RoveStop, kind: FfiChangeKind::Upsert });
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::WebSdrRecording,
            kind: FfiChangeKind::Upsert,
        });
        Ok(sessions)
    }
}

impl SessionApi {
    /// Fetch → mutate → upsert → notify a single session. `None` if absent.
    fn transition(
        &self,
        id: &str,
        mutate: impl FnOnce(&mut LoggingSession),
    ) -> Result<Option<FfiLoggingSession>, CwError> {
        let session = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let Some(mut session) = store.fetch_logging_session(id)? else {
                return Ok(None);
            };
            mutate(&mut session);
            session.cloud_dirty_flag = true;
            store.upsert_logging_session(&session)?;
            session
        };
        self.notify_session();
        Ok(Some(FfiLoggingSession::from(session)))
    }

    fn notify_session(&self) {
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::LoggingSession,
            kind: FfiChangeKind::Upsert,
        });
    }
}

// ---------- pure helpers ----------

fn now_ts() -> i64 {
    Utc::now().timestamp()
}

/// Pause every *other* session currently `active` (the resume invariant).
fn pause_other_active(store: &Store, except: &str) -> Result<(), CwError> {
    for mut session in store.fetch_logging_sessions_by_status("active", ACTIVE_SWEEP_LIMIT)? {
        if session.id == except {
            continue;
        }
        session.status_raw_value = "paused".to_string();
        session.cloud_dirty_flag = true;
        store.upsert_logging_session(&session)?;
    }
    Ok(())
}

/// The session's program slugs — port of `LoggingSession.programs`: decode the
/// JSON `programsRawValue`, else fall back to the `activationType` (unless it is
/// `casual`/empty, which means no program).
fn session_programs(session: &LoggingSession) -> BTreeSet<String> {
    if !session.programs_raw_value.is_empty() {
        if let Ok(slugs) = serde_json::from_str::<Vec<String>>(&session.programs_raw_value) {
            return slugs.into_iter().collect();
        }
    }
    let activation = session.activation_type_raw_value.as_str();
    if activation == "casual" || activation.is_empty() {
        BTreeSet::new()
    } else {
        BTreeSet::from([activation.to_string()])
    }
}

fn is_pota(session: &LoggingSession) -> bool {
    session_programs(session).contains("pota")
}

fn is_wwff(session: &LoggingSession) -> bool {
    session_programs(session).contains("wwff")
}

/// Fill a blank RST with the mode default (`rstSent.nonEmpty ?? defaultRST`).
/// A non-blank value is passed through verbatim (trimmed of surrounding space).
fn fill_rst(value: &str, mode: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        default_rst(mode)
    } else {
        trimmed.to_string()
    }
}

/// Combine the session-level `qsoComment` with the per-QSO notes (`combineNotes`):
/// non-empty parts joined by `" | "`, or `None` when both are empty.
fn combine_notes(qso_comment: Option<&str>, notes: Option<&str>) -> Option<String> {
    let mut parts: Vec<&str> = Vec::new();
    if let Some(comment) = qso_comment {
        if !comment.is_empty() {
            parts.push(comment);
        }
    }
    if let Some(user_notes) = notes {
        if !user_notes.is_empty() {
            parts.push(user_notes);
        }
    }
    if parts.is_empty() {
        None
    } else {
        Some(parts.join(" | "))
    }
}

/// Concatenate two JSON `[String]` photo-filename blobs (target first), used by
/// `mergeSessions`. Non-array / invalid inputs are treated as empty.
fn concat_photo_filenames(target: &str, source: &str) -> String {
    let parse = |raw: &str| serde_json::from_str::<Vec<String>>(raw).unwrap_or_default();
    let mut merged = parse(target);
    merged.extend(parse(source));
    serde_json::to_string(&merged).unwrap_or_else(|_| "[]".to_string())
}

/// Build the activation QSO `logQSO` persists.
fn build_session_qso(session: &LoggingSession, input: &FfiSessionLogInput) -> Qso {
    let now = now_ts();
    // effectiveFrequency = override ?? session.frequency (MHz); band derived from it.
    let effective_freq_mhz = input.frequency_override_mhz.or(session.frequency);
    let freq_khz = effective_freq_mhz.map(|mhz| mhz * 1000.0);
    let band = freq_khz
        .and_then(|khz| BandUtilities::derive_band(Some(khz)))
        .map(str::to_string)
        .unwrap_or_else(|| "Unknown".to_string());
    let effective_mode = input.mode_override.clone().unwrap_or_else(|| session.mode.clone());
    let notes = combine_notes(session.qso_comment.as_deref(), input.notes.as_deref());
    // RST defaults are owned here (port of `rstSent.nonEmpty ?? defaultRST`): a
    // blank field falls back to the mode's default report so both platforms —
    // and any caller that sends "" — agree.
    let rst_sent = fill_rst(&input.rst_sent, &effective_mode);
    let rst_received = fill_rst(&input.rst_received, &effective_mode);

    Qso {
        id: Uuid::new_v4().to_string(),
        callsign: input.callsign.trim().to_uppercase(),
        band: Some(band),
        mode: Some(effective_mode),
        freq_khz,
        qso_date: input.timestamp_override.unwrap_or(now),
        my_grid: session.my_grid.clone(),
        their_grid: input.their_grid.clone(),
        rst_sent: Some(rst_sent),
        rst_rcvd: Some(rst_received),
        my_callsign: Some(session.my_callsign.clone()),
        // Operator's own park reference stamps every QSO in the activation.
        park: session.park_reference.clone(),
        their_park: input.their_park.clone(),
        notes: notes.clone(),
        // User/session-comment notes — tag user-authored so QRZ may push COMMENT (CAR-243).
        notes_user_authored: notes.as_deref().map(|n| !n.is_empty()).unwrap_or(false),
        spot_comments_data: None,
        callsign_change_note: input.callsign_change_note.clone(),
        original_callsign: None,
        import_source_raw_value: "logger".to_string(),
        imported_at: now,
        modified_at: Some(now),
        raw_adif: None,
        name: input.name.clone(),
        qth: input.qth.clone(),
        state: input.state.clone(),
        country: input.country.clone(),
        power: session.power,
        my_rig: session.my_rig.clone(),
        station_profile_name: None,
        // `sotaRef` is the CONTACTED station's summit; the operator's own summit
        // is on the session (exported as MY_SOTA_REF). Leave nil here.
        sota_ref: None,
        wwff_ref: if is_wwff(session) { session.wwff_reference.clone() } else { None },
        aoa_code: input.aoa_code.clone(),
        qrz_log_id: None,
        qrz_confirmed: false,
        lotw_confirmed_date: None,
        lotw_confirmed: false,
        dxcc: None,
        their_license_class: input.their_license_class.clone(),
        contest_name: input.contest_name.clone(),
        contest_serial_sent: input.contest_serial_sent,
        contest_serial_received: input.contest_serial_received,
        contest_exchange_sent: input.contest_exchange_sent.clone(),
        contest_exchange_received: input.contest_exchange_received.clone(),
        is_hidden: false,
        is_activity_log_qso: false,
        station_callsign: session.station_callsign.clone(),
        logging_session_id: Some(session.id.clone()),
        dirty: true,
        sat_name: input.sat_name.clone(),
        prop_mode: input.prop_mode.clone(),
    }
}

/// Route an activation QSO to its upload destinations (`markForUpload`): skip
/// metadata modes; QRZ when configured; POTA when this is a POTA activation and
/// POTA is configured; LoFi/ClubLog attempted but no-ops (`supports_upload`).
fn mark_for_upload(
    store: &Store,
    qso: &Qso,
    session: &LoggingSession,
    input: &FfiSessionLogInput,
) -> Result<bool, CwError> {
    if qso.mode.as_deref().map(is_metadata_mode).unwrap_or(false) {
        return Ok(false);
    }
    let mut wrote = false;
    if input.upload_qrz {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Qrz)?;
    }
    if input.upload_pota && is_pota(session) {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Pota)?;
    }
    if input.upload_lofi {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Lofi)?;
    }
    if input.upload_clublog {
        wrote |= mark_needs_upload(store, &qso.id, ServiceType::Clublog)?;
    }
    Ok(wrote)
}

/// Unix-seconds timestamp of UTC midnight for the day containing `ts`. Mirrors
/// the `utcCalendar.startOfDay(for:)` normalisation used by the conditions +
/// WPM metadata keys.
fn utc_start_of_day(ts: i64) -> i64 {
    let dt = Utc
        .timestamp_opt(ts, 0)
        .single()
        .unwrap_or_else(|| Utc.timestamp_opt(0, 0).single().expect("epoch is valid"));
    let start = dt.date_naive().and_hms_opt(0, 0, 0).expect("midnight is a valid time");
    Utc.from_utc_datetime(&start).timestamp()
}

/// The primary park of a possibly-multi reference (`ParkReference.split(_).first`),
/// falling back to the whole ref when it doesn't split.
fn primary_park(park_ref: &str) -> String {
    cw_domain::park_reference::split(park_ref)
        .into_iter()
        .next()
        .unwrap_or_else(|| park_ref.to_string())
}

/// A bare `ActivationMetadata` for `(park, date)` with every optional field nil —
/// the find-or-create seed for the conditions / WPM merges.
fn blank_metadata(park: &str, date: i64) -> ActivationMetadata {
    ActivationMetadata {
        park_reference: park.to_string(),
        date,
        title: None,
        watts: None,
        weather: None,
        solar_conditions: None,
        average_wpm: None,
        solar_k_index: None,
        solar_flux: None,
        solar_sunspots: None,
        solar_propagation_rating: None,
        solar_a_index: None,
        solar_band_conditions: None,
        solar_timestamp: None,
        weather_temperature_f: None,
        weather_temperature_c: None,
        weather_humidity: None,
        weather_wind_speed: None,
        weather_wind_direction: None,
        weather_description: None,
        weather_timestamp: None,
        cloud_dirty_flag: false,
    }
}

/// `None`/empty-string test used by the metadata text-field fill.
fn is_blank(value: &Option<String>) -> bool {
    value.as_deref().map(str::is_empty).unwrap_or(true)
}

/// Incoming conditions carry structured solar data (`hasSolarData` shape:
/// kIndex OR flux OR sunspots).
fn input_has_solar(conditions: &FfiConditionsInput) -> bool {
    conditions.solar_k_index.is_some()
        || conditions.solar_flux.is_some()
        || conditions.solar_sunspots.is_some()
}

/// Incoming conditions carry structured weather data (`hasWeatherData` shape:
/// temperatureF non-nil).
fn input_has_weather(conditions: &FfiConditionsInput) -> bool {
    conditions.weather_temperature_f.is_some()
}

/// `LoggingSession.hasSolarData` — any of kIndex / flux / sunspots present.
fn session_has_solar(session: &LoggingSession) -> bool {
    session.solar_k_index.is_some()
        || session.solar_flux.is_some()
        || session.solar_sunspots.is_some()
}

/// `LoggingSession.hasWeatherData` — temperatureF present.
fn session_has_weather(session: &LoggingSession) -> bool {
    session.weather_temperature_f.is_some()
}

/// `ActivationMetadata.hasSolarData` — any of kIndex / flux / sunspots present.
fn metadata_has_solar(meta: &ActivationMetadata) -> bool {
    meta.solar_k_index.is_some() || meta.solar_flux.is_some() || meta.solar_sunspots.is_some()
}

/// `ActivationMetadata.hasWeatherData` — temperatureF present.
fn metadata_has_weather(meta: &ActivationMetadata) -> bool {
    meta.weather_temperature_f.is_some()
}

/// `storeConditionsOnSession`: fill the session's conditions where empty. Text
/// fields fill only when nil; the structured solar / weather blocks fill only
/// when the session has no data of that kind and the input carries some. Returns
/// whether anything changed.
fn apply_conditions_to_session(session: &mut LoggingSession, conditions: &FfiConditionsInput) -> bool {
    let mut changed = false;
    if session.solar_conditions.is_none() && conditions.solar_conditions.is_some() {
        session.solar_conditions = conditions.solar_conditions.clone();
        changed = true;
    }
    if session.weather.is_none() && conditions.weather.is_some() {
        session.weather = conditions.weather.clone();
        changed = true;
    }
    if !session_has_solar(session) && input_has_solar(conditions) {
        session.solar_k_index = conditions.solar_k_index;
        session.solar_flux = conditions.solar_flux;
        session.solar_sunspots = conditions.solar_sunspots;
        session.solar_propagation_rating = conditions.solar_propagation_rating.clone();
        session.solar_a_index = conditions.solar_a_index;
        session.solar_band_conditions = conditions.solar_band_conditions.clone();
        session.solar_timestamp = conditions.solar_timestamp;
        changed = true;
    }
    if !session_has_weather(session) && input_has_weather(conditions) {
        session.weather_temperature_f = conditions.weather_temperature_f;
        session.weather_temperature_c = conditions.weather_temperature_c;
        session.weather_humidity = conditions.weather_humidity;
        session.weather_wind_speed = conditions.weather_wind_speed;
        session.weather_wind_direction = conditions.weather_wind_direction.clone();
        session.weather_description = conditions.weather_description.clone();
        session.weather_timestamp = conditions.weather_timestamp;
        changed = true;
    }
    changed
}

/// `storeConditionsMetadata`: like [`apply_conditions_to_session`] but the text
/// fields fill on nil-**or-empty-string** (the stricter Swift metadata check).
fn apply_conditions_to_metadata(meta: &mut ActivationMetadata, conditions: &FfiConditionsInput) -> bool {
    let mut changed = false;
    if is_blank(&meta.solar_conditions) && conditions.solar_conditions.is_some() {
        meta.solar_conditions = conditions.solar_conditions.clone();
        changed = true;
    }
    if is_blank(&meta.weather) && conditions.weather.is_some() {
        meta.weather = conditions.weather.clone();
        changed = true;
    }
    if !metadata_has_solar(meta) && input_has_solar(conditions) {
        meta.solar_k_index = conditions.solar_k_index;
        meta.solar_flux = conditions.solar_flux;
        meta.solar_sunspots = conditions.solar_sunspots;
        meta.solar_propagation_rating = conditions.solar_propagation_rating.clone();
        meta.solar_a_index = conditions.solar_a_index;
        meta.solar_band_conditions = conditions.solar_band_conditions.clone();
        meta.solar_timestamp = conditions.solar_timestamp;
        changed = true;
    }
    if !metadata_has_weather(meta) && input_has_weather(conditions) {
        meta.weather_temperature_f = conditions.weather_temperature_f;
        meta.weather_temperature_c = conditions.weather_temperature_c;
        meta.weather_humidity = conditions.weather_humidity;
        meta.weather_wind_speed = conditions.weather_wind_speed;
        meta.weather_wind_direction = conditions.weather_wind_direction.clone();
        meta.weather_description = conditions.weather_description.clone();
        meta.weather_timestamp = conditions.weather_timestamp;
        changed = true;
    }
    changed
}

/// Bound on the split's QSO/recording scans (mirrors the iOS `BoundedDescriptor`
/// cap used by `fetchSessionQSOs`).
const MAX_SPLIT_QSOS: i64 = 1_000;

/// Seconds in a UTC day — the last-day `endedAt` fallback (`date + 1 day`).
const SECONDS_PER_DAY: i64 = 86_400;

/// The park active at a UTC-midnight boundary (`parkActiveAt`): the stop whose
/// `[startedAt, endedAt)` window contains `date`, else the last stop that had
/// started by then. Stops are ascending by `started_at`.
fn park_active_at(date: i64, stops: &[RoveStop]) -> Option<String> {
    for stop in stops {
        let stop_end = stop.ended_at.unwrap_or(i64::MAX);
        if stop.started_at <= date && stop_end > date {
            return Some(stop.park_reference.clone());
        }
    }
    stops.iter().rfind(|stop| stop.started_at <= date).map(|stop| stop.park_reference.clone())
}

/// Clip the rove stops overlapping a `[day_start, midnight)` UTC day, splitting
/// any that span the boundary (`splitStops` / `splitSingleStop`). Each emitted
/// stop is a **new** row (new id); `qso_count` is the number of `qso_dates` on
/// that day within the clamped window. The `logging_session_id` is a placeholder —
/// `replace_rove_stops` rebinds it to the target session.
fn split_stops(stops: &[RoveStop], day_start: i64, midnight: i64, qso_dates: &[i64]) -> Vec<RoveStop> {
    stops
        .iter()
        .filter_map(|stop| split_single_stop(stop, day_start, midnight, qso_dates))
        .collect()
}

fn split_single_stop(
    stop: &RoveStop,
    day_start: i64,
    midnight: i64,
    qso_dates: &[i64],
) -> Option<RoveStop> {
    let stop_end = stop.ended_at.unwrap_or(midnight);
    // Stop entirely outside this day.
    if !(stop_end > day_start && stop.started_at < midnight) {
        return None;
    }
    let clamped_start = stop.started_at.max(day_start);
    let clamped_end = stop_end.min(midnight);
    let stop_day_start = utc_start_of_day(stop.started_at);
    if !(clamped_start < clamped_end || stop_day_start == day_start) {
        return None;
    }
    let slice_count = qso_dates
        .iter()
        .filter(|&&ts| utc_start_of_day(ts) == day_start && ts >= clamped_start && ts < clamped_end)
        .count() as i64;
    Some(RoveStop {
        id: Uuid::new_v4().to_string(),
        logging_session_id: String::new(), // rebound by replace_rove_stops
        park_reference: stop.park_reference.clone(),
        started_at: clamped_start,
        ended_at: Some(clamped_end),
        my_grid: stop.my_grid.clone(),
        qso_count: slice_count,
        notes: stop.notes.clone(),
        cloud_dirty_flag: true,
    })
}

/// Clone a session for a split UTC day (`createSplitSession`). Copies only the
/// subset the Swift init carries over (callsign/frequency/mode/activation type/
/// grid/power/rig/antenna/key/mic/extraEquipment/attendees/isRove); derives
/// `programs` from the activation type alone (dropping any extra programs +
/// sotaRef/wwffRef/stationCallsign/contest/conditions, exactly as the Swift init
/// does); sets status=completed, the day bounds, and the QSO count. Rove stops go
/// to the `rove_stop` table, so `rove_stops_data` stays nil.
fn clone_split_session(
    original: &LoggingSession,
    park: Option<String>,
    start: i64,
    end: i64,
    qso_count: i64,
) -> LoggingSession {
    let activation = original.activation_type_raw_value.clone();
    let programs_raw_value = if activation != "casual" && !activation.is_empty() {
        serde_json::to_string(std::slice::from_ref(&activation)).unwrap_or_else(|_| "[]".to_string())
    } else {
        String::new()
    };
    LoggingSession {
        id: Uuid::new_v4().to_string(),
        my_callsign: original.my_callsign.clone(),
        started_at: start,
        ended_at: Some(end),
        frequency: original.frequency,
        mode: original.mode.clone(),
        activation_type_raw_value: activation,
        programs_raw_value,
        status_raw_value: "completed".to_string(),
        park_reference: park,
        sota_reference: None,
        mission_reference: None,
        wwff_reference: None,
        my_grid: original.my_grid.clone(),
        power: original.power,
        my_rig: original.my_rig.clone(),
        notes: None,
        qso_comment: None,
        custom_title: None,
        qso_count,
        spot_comments_data: None,
        is_rove: original.is_rove,
        rove_stops_data: None,
        my_antenna: original.my_antenna.clone(),
        my_key: original.my_key.clone(),
        my_mic: original.my_mic.clone(),
        extra_equipment: original.extra_equipment.clone(),
        attendees: original.attendees.clone(),
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
        cloud_dirty_flag: true,
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

#[cfg(test)]
mod tests {
    use super::*;
    use cw_store::ServicePresenceFilter;

    fn store() -> Arc<FieldStore> {
        Arc::new(FieldStore::open_in_memory("k".into()).unwrap())
    }

    /// A minimal session row, inserted directly (creation is a host concern).
    fn insert_session(store: &FieldStore, id: &str, programs: &str) -> LoggingSession {
        let session = LoggingSession {
            id: id.to_string(),
            my_callsign: "W6JY".to_string(),
            started_at: 1_000,
            ended_at: None,
            frequency: Some(14.074),
            mode: "FT8".to_string(),
            activation_type_raw_value: "casual".to_string(),
            programs_raw_value: programs.to_string(),
            status_raw_value: "active".to_string(),
            park_reference: Some("US-1234".to_string()),
            sota_reference: None,
            mission_reference: None,
            wwff_reference: Some("KFF-1234".to_string()),
            my_grid: Some("CM87".to_string()),
            power: Some(5),
            my_rig: Some("KX2".to_string()),
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
            station_callsign: Some("W6JY".to_string()),
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
        };
        let inner = store.inner.lock().unwrap();
        inner.upsert_logging_session(&session).unwrap();
        session
    }

    fn base_input(session_id: &str) -> FfiSessionLogInput {
        FfiSessionLogInput {
            session_id: session_id.to_string(),
            callsign: " w1aw ".to_string(),
            rst_sent: "599".to_string(),
            rst_received: "599".to_string(),
            their_grid: None,
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
            timestamp_override: None,
            contest_name: None,
            contest_serial_sent: None,
            contest_serial_received: None,
            contest_exchange_sent: None,
            contest_exchange_received: None,
            sat_name: None,
            prop_mode: None,
            upload_qrz: false,
            upload_pota: false,
            upload_lofi: false,
            upload_clublog: false,
        }
    }

    #[test]
    fn log_qso_stamps_session_fields_and_derives_band() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());

        let result = api.log_qso(base_input("s1")).unwrap().unwrap();
        let qso = result.qso;
        assert_eq!(qso.callsign, "W1AW"); // trimmed + uppercased
        assert_eq!(qso.band.as_deref(), Some("20m")); // 14.074 MHz -> 20m
        assert_eq!(qso.mode.as_deref(), Some("FT8")); // from session
        assert_eq!(qso.freq_khz, Some(14_074.0));
        assert_eq!(qso.my_callsign.as_deref(), Some("W6JY"));
        assert_eq!(qso.my_grid.as_deref(), Some("CM87"));
        assert_eq!(qso.park.as_deref(), Some("US-1234")); // operator park stamped
        assert_eq!(qso.power, Some(5));
        assert_eq!(qso.my_rig.as_deref(), Some("KX2"));
        assert_eq!(qso.logging_session_id.as_deref(), Some("s1"));
        assert!(qso.sota_ref.is_none()); // contacted-station summit left nil
        assert!(!qso.is_activity_log_qso); // an activation, not a hunter QSO
        assert_eq!(result.qso_count, 1); // session count incremented
    }

    #[test]
    fn log_qso_stamps_contest_fields_when_provided() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());

        let mut input = base_input("s1");
        input.contest_name = Some("cwops-cwt".to_string());
        input.contest_serial_sent = Some(12);
        input.contest_serial_received = Some(34);
        input.contest_exchange_sent = Some("JAY 3573".to_string());
        input.contest_exchange_received = Some("TIM OR".to_string());

        let qso = api.log_qso(input).unwrap().unwrap().qso;
        assert_eq!(qso.contest_name.as_deref(), Some("cwops-cwt"));
        assert_eq!(qso.contest_serial_sent, Some(12));
        assert_eq!(qso.contest_serial_received, Some(34));
        assert_eq!(qso.contest_exchange_sent.as_deref(), Some("JAY 3573"));
        assert_eq!(qso.contest_exchange_received.as_deref(), Some("TIM OR"));

        // Non-contest input leaves the fields nil.
        let plain = api.log_qso(base_input("s1")).unwrap().unwrap().qso;
        assert!(plain.contest_name.is_none());
    }

    #[test]
    fn log_qso_stamps_satellite_fields_when_provided() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());

        let mut input = base_input("s1");
        input.sat_name = Some("AO-91".to_string());
        input.prop_mode = Some("SAT".to_string());

        let qso = api.log_qso(input).unwrap().unwrap().qso;
        assert_eq!(qso.sat_name.as_deref(), Some("AO-91"));
        assert_eq!(qso.prop_mode.as_deref(), Some("SAT"));

        // Terrestrial input leaves the fields nil.
        let plain = api.log_qso(base_input("s1")).unwrap().unwrap().qso;
        assert!(plain.sat_name.is_none());
        assert!(plain.prop_mode.is_none());
    }

    #[test]
    fn log_qso_wwff_ref_only_for_wwff_session() {
        let store = store();
        insert_session(&store, "pota", r#"["pota"]"#);
        insert_session(&store, "wwff", r#"["wwff"]"#);
        let api = SessionApi::new(store.clone());

        let pota_qso = api.log_qso(base_input("pota")).unwrap().unwrap().qso;
        assert!(pota_qso.wwff_ref.is_none());
        let wwff_qso = api.log_qso(base_input("wwff")).unwrap().unwrap().qso;
        assert_eq!(wwff_qso.wwff_ref.as_deref(), Some("KFF-1234"));
    }

    #[test]
    fn log_qso_fills_blank_rst_with_mode_default() {
        let store = store();
        // FT8 session (from insert_session) -> 3-digit default "599".
        insert_session(&store, "ft8", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());

        let mut input = base_input("ft8");
        input.rst_sent = String::new();
        input.rst_received = "   ".to_string();
        let qso = api.log_qso(input).unwrap().unwrap().qso;
        assert_eq!(qso.rst_sent.as_deref(), Some("599"));
        assert_eq!(qso.rst_rcvd.as_deref(), Some("599"));

        // A mode override to a phone mode changes the default to "59".
        let mut phone = base_input("ft8");
        phone.mode_override = Some("SSB".to_string());
        phone.rst_sent = String::new();
        phone.rst_received = String::new();
        let phone_qso = api.log_qso(phone).unwrap().unwrap().qso;
        assert_eq!(phone_qso.rst_sent.as_deref(), Some("59"));

        // Provided values pass through (trimmed).
        let mut given = base_input("ft8");
        given.rst_sent = " 579 ".to_string();
        let given_qso = api.log_qso(given).unwrap().unwrap().qso;
        assert_eq!(given_qso.rst_sent.as_deref(), Some("579"));
    }

    #[test]
    fn current_session_returns_single_active_non_ended() {
        let store = store();
        let api = SessionApi::new(store.clone());
        assert!(api.current_session().unwrap().is_none()); // idle

        insert_session(&store, "s1", "[]"); // status active, ended_at None
        let current = api.current_session().unwrap().expect("active session");
        assert_eq!(current.id, "s1");

        // Ending it clears the current session.
        api.end_session("s1".to_string()).unwrap();
        assert!(api.current_session().unwrap().is_none());
    }

    #[test]
    fn suggested_prefixes_are_position_local() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#); // my_grid CM87
        let api = SessionApi::new(store.clone());
        for call in ["W6AAA", "W6BBB", "K6CCC"] {
            let mut input = base_input("s1");
            input.callsign = call.to_string();
            api.log_qso(input).unwrap();
        }

        // Anchored near the logged position: ranked local prefixes.
        let near = api.suggested_prefixes(Some("CM97".to_string()), 0).unwrap();
        assert_eq!(near, vec!["W6".to_string(), "K6".to_string()]);

        // Anchored on another continent: the country-level fallback,
        // never the California history.
        let far = api.suggested_prefixes(Some("QF44".to_string()), 0).unwrap();
        assert!(!far.contains(&"W6".to_string()), "got {far:?}");
    }

    #[test]
    fn logger_form_config_reports_defaults_and_flags() {
        let store = store();
        insert_session(&store, "pota", r#"["pota"]"#); // FT8, 14.074 MHz, POTA
        let api = SessionApi::new(store.clone());

        let cfg = api.logger_form_config("pota".to_string()).unwrap().expect("config");
        assert_eq!(cfg.mode, "FT8");
        assert_eq!(cfg.band.as_deref(), Some("20m"));
        assert_eq!(cfg.frequency_mhz, Some(14.074));
        assert_eq!(cfg.default_rst_sent, "599");
        assert_eq!(cfg.default_rst_received, "599");
        assert!(cfg.is_pota);
        assert!(cfg.show_their_park);
        assert!(!cfg.is_contest);
        assert!(!cfg.show_contest_exchange);

        assert!(api.logger_form_config("missing".to_string()).unwrap().is_none());
    }

    #[test]
    fn log_qso_overrides_and_combined_notes() {
        let store = store();
        let mut session = insert_session(&store, "s1", "[]");
        session.qso_comment = Some("SOTA chaser".to_string());
        store.inner.lock().unwrap().upsert_logging_session(&session).unwrap();
        let api = SessionApi::new(store.clone());

        let mut input = base_input("s1");
        input.frequency_override_mhz = Some(7.040);
        input.mode_override = Some("CW".into());
        input.notes = Some("nice sig".into());
        let qso = api.log_qso(input).unwrap().unwrap().qso;
        assert_eq!(qso.band.as_deref(), Some("40m"));
        assert_eq!(qso.mode.as_deref(), Some("CW"));
        // session qsoComment combined with user notes
        assert_eq!(qso.notes.as_deref(), Some("SOTA chaser | nice sig"));
        assert!(qso.notes_user_authored);
    }

    #[test]
    fn upload_routing_pota_only_for_pota_session() {
        let store = store();
        insert_session(&store, "pota", r#"["pota"]"#);
        insert_session(&store, "casual", "[]");
        let api = SessionApi::new(store.clone());

        let mut pota_in = base_input("pota");
        pota_in.upload_qrz = true;
        pota_in.upload_pota = true;
        let pota_qso = api.log_qso(pota_in).unwrap().unwrap().qso;

        let mut casual_in = base_input("casual");
        casual_in.upload_qrz = true;
        casual_in.upload_pota = true; // configured, but not a POTA session
        let casual_qso = api.log_qso(casual_in).unwrap().unwrap().qso;

        let inner = store.inner.lock().unwrap();
        let pota_services: Vec<String> = inner
            .fetch_service_presences(
                &ServicePresenceFilter { qso_id: Some(pota_qso.id.clone()), ..Default::default() },
                100,
                0,
            )
            .unwrap()
            .into_iter()
            .map(|p| p.service_type_raw_value)
            .collect();
        assert!(pota_services.contains(&"qrz".to_string()));
        assert!(pota_services.contains(&"pota".to_string()));

        let casual_services: Vec<String> = inner
            .fetch_service_presences(
                &ServicePresenceFilter { qso_id: Some(casual_qso.id.clone()), ..Default::default() },
                100,
                0,
            )
            .unwrap()
            .into_iter()
            .map(|p| p.service_type_raw_value)
            .collect();
        assert_eq!(casual_services, vec!["qrz".to_string()]); // no POTA on a casual session
    }

    #[test]
    fn lifecycle_transitions() {
        let store = store();
        insert_session(&store, "s1", "[]");
        let api = SessionApi::new(store.clone());

        assert_eq!(api.pause_session("s1".into()).unwrap().unwrap().status_raw_value, "paused");
        assert_eq!(api.resume_session("s1".into()).unwrap().unwrap().status_raw_value, "active");
        let ended = api.end_session("s1".into()).unwrap().unwrap();
        assert_eq!(ended.status_raw_value, "completed");
        assert!(ended.ended_at.is_some());
        let reopened = api.reopen_session("s1".into()).unwrap().unwrap();
        assert_eq!(reopened.status_raw_value, "active");
        assert!(reopened.ended_at.is_none()); // reopen clears endedAt

        assert!(api.pause_session("missing".into()).unwrap().is_none());
    }

    #[test]
    fn resume_pauses_other_active_session() {
        let store = store();
        insert_session(&store, "a", "[]");
        insert_session(&store, "b", "[]");
        let api = SessionApi::new(store.clone());
        // Both start "active"; resuming "a" should pause "b".
        api.resume_session("a".into()).unwrap();
        let inner = store.inner.lock().unwrap();
        assert_eq!(inner.fetch_logging_session("a").unwrap().unwrap().status_raw_value, "active");
        assert_eq!(inner.fetch_logging_session("b").unwrap().unwrap().status_raw_value, "paused");
    }

    #[test]
    fn merge_reassigns_qsos_expands_bounds_and_folds_count() {
        let store = store();
        let mut source = insert_session(&store, "src", "[]");
        source.started_at = 500; // earlier than target
        source.ended_at = Some(3_000); // later than target
        source.qso_count = 2;
        source.photo_filenames = r#"["b.jpg"]"#.to_string();
        let mut target = insert_session(&store, "tgt", "[]");
        target.started_at = 1_000;
        target.ended_at = Some(2_000);
        target.qso_count = 3;
        target.photo_filenames = r#"["a.jpg"]"#.to_string();
        {
            let inner = store.inner.lock().unwrap();
            inner.upsert_logging_session(&source).unwrap();
            inner.upsert_logging_session(&target).unwrap();
        }
        let api = SessionApi::new(store.clone());
        // Log a QSO into the source so we can prove it moves.
        api.log_qso(base_input("src")).unwrap();

        assert!(api.merge_sessions("src".into(), "tgt".into()).unwrap());
        // A merge with a missing source is a no-op (call API before holding the lock).
        assert!(!api.merge_sessions("missing".into(), "tgt".into()).unwrap());

        let inner = store.inner.lock().unwrap();
        // Source shell deleted.
        assert!(inner.fetch_logging_session("src").unwrap().is_none());
        let merged = inner.fetch_logging_session("tgt").unwrap().unwrap();
        assert_eq!(merged.started_at, 500); // expanded earlier
        assert_eq!(merged.ended_at, Some(3_000)); // expanded later
        // Counts are folded from the stored fields (like Swift, no recount):
        // target 3 + source (2 seeded + 1 logged below = 3) = 6.
        assert_eq!(merged.qso_count, 6);
        assert_eq!(merged.photo_filenames, r#"["a.jpg","b.jpg"]"#); // concatenated
        // The source QSO now belongs to the target.
        let moved = inner.fetch_qsos_for_session("tgt", None, 100).unwrap();
        assert_eq!(moved.len(), 1);
    }

    #[test]
    fn delete_session_hides_qsos_and_clears_upload() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());
        let mut input = base_input("s1");
        input.upload_qrz = true;
        let qso = api.log_qso(input).unwrap().unwrap().qso;

        assert!(api.delete_session("s1".into()).unwrap());
        // Already gone — idempotent (call API before holding the lock).
        assert!(!api.delete_session("s1".into()).unwrap());

        let inner = store.inner.lock().unwrap();
        assert!(inner.fetch_logging_session("s1").unwrap().is_none()); // session gone
        // The QSO survives but is hidden, and its pending upload was cleared.
        let presences = inner
            .fetch_service_presences(
                &ServicePresenceFilter { qso_id: Some(qso.id.clone()), ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert!(presences.iter().all(|p| !p.needs_upload));
        // is_hidden true => excluded from the visible session fetch.
        assert!(inner.fetch_qsos_for_session("s1", None, 100).unwrap().is_empty());
    }

    // ---------- conditions + WPM (end-of-session follow-ons) ----------

    fn conditions_input() -> FfiConditionsInput {
        FfiConditionsInput {
            solar_conditions: Some("Good".to_string()),
            weather: Some("Sunny".to_string()),
            solar_k_index: Some(2.0),
            solar_flux: Some(120.0),
            solar_sunspots: Some(45),
            solar_propagation_rating: Some("Good".to_string()),
            solar_a_index: Some(5),
            solar_band_conditions: Some(r#"{"20m":"Good"}"#.to_string()),
            solar_timestamp: Some(1_000),
            weather_temperature_f: Some(72.0),
            weather_temperature_c: Some(22.0),
            weather_humidity: Some(50),
            weather_wind_speed: Some(5.0),
            weather_wind_direction: Some("NW".to_string()),
            weather_description: Some("Clear".to_string()),
            weather_timestamp: Some(1_000),
        }
    }

    #[test]
    fn save_average_wpm_truncates_and_keys_by_primary_park_and_utc_day() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#); // park US-1234, started_at 1000
        let api = SessionApi::new(store.clone());

        // (20 + 22 + 25) / 3 = 67 / 3 = 22 with integer truncation.
        let meta = api.save_average_wpm("s1".into(), vec![20, 22, 25]).unwrap().unwrap();
        assert_eq!(meta.average_wpm, Some(22));
        assert_eq!(meta.park_reference, "US-1234");
        assert_eq!(meta.date, 0); // utc_start_of_day(1000) = 1970-01-01T00:00:00Z
        assert!(meta.cloud_dirty_flag);

        // Persisted under the (primary_park, utc-day) key.
        let inner = store.inner.lock().unwrap();
        assert_eq!(
            inner.fetch_activation_metadata("US-1234", 0).unwrap().unwrap().average_wpm,
            Some(22)
        );
    }

    #[test]
    fn save_average_wpm_none_cases() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());
        // No WPM values → None.
        assert!(api.save_average_wpm("s1".into(), vec![]).unwrap().is_none());
        // Missing session → None.
        assert!(api.save_average_wpm("missing".into(), vec![20]).unwrap().is_none());
    }

    #[test]
    fn save_average_wpm_always_overwrites_existing() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        // Seed a metadata row with a stale WPM under the same key.
        {
            let inner = store.inner.lock().unwrap();
            let mut seed = blank_metadata("US-1234", 0);
            seed.average_wpm = Some(99);
            inner.upsert_activation_metadata(&seed).unwrap();
        }
        let api = SessionApi::new(store.clone());
        let meta = api.save_average_wpm("s1".into(), vec![10, 10]).unwrap().unwrap();
        assert_eq!(meta.average_wpm, Some(10)); // overwritten, not preserved
    }

    #[test]
    fn save_average_wpm_uses_primary_of_multi_park() {
        let store = store();
        let mut session = insert_session(&store, "s1", r#"["pota"]"#);
        session.park_reference = Some("US-1234, US-5678".to_string());
        store.inner.lock().unwrap().upsert_logging_session(&session).unwrap();
        let api = SessionApi::new(store.clone());

        let meta = api.save_average_wpm("s1".into(), vec![18]).unwrap().unwrap();
        assert_eq!(meta.park_reference, "US-1234"); // primary park only
    }

    #[test]
    fn save_average_wpm_none_without_park() {
        let store = store();
        let mut session = insert_session(&store, "s1", "[]");
        session.park_reference = None;
        store.inner.lock().unwrap().upsert_logging_session(&session).unwrap();
        let api = SessionApi::new(store.clone());
        assert!(api.save_average_wpm("s1".into(), vec![20]).unwrap().is_none());
    }

    #[test]
    fn record_conditions_fills_session_and_pota_metadata() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());

        let result = api.record_conditions("s1".into(), conditions_input()).unwrap().unwrap();
        // Session filled.
        assert_eq!(result.session.solar_conditions.as_deref(), Some("Good"));
        assert_eq!(result.session.weather.as_deref(), Some("Sunny"));
        assert_eq!(result.session.solar_k_index, Some(2.0));
        assert_eq!(result.session.weather_temperature_f, Some(72.0));
        // POTA → metadata written under (US-1234, utc-day 0), filled too.
        let meta = result.metadata.expect("POTA session writes metadata");
        assert_eq!(meta.park_reference, "US-1234");
        assert_eq!(meta.date, 0);
        assert_eq!(meta.solar_conditions.as_deref(), Some("Good"));
        assert_eq!(meta.weather_temperature_f, Some(72.0));
        assert!(meta.cloud_dirty_flag);
    }

    #[test]
    fn record_conditions_preserves_existing_session_data() {
        let store = store();
        let mut session = insert_session(&store, "s1", r#"["pota"]"#);
        // Pre-existing solar (hasSolarData) + text — must NOT be overwritten.
        session.solar_k_index = Some(9.9);
        session.solar_conditions = Some("Stormy".to_string());
        store.inner.lock().unwrap().upsert_logging_session(&session).unwrap();
        let api = SessionApi::new(store.clone());

        let result = api.record_conditions("s1".into(), conditions_input()).unwrap().unwrap();
        assert_eq!(result.session.solar_k_index, Some(9.9)); // block skipped (had data)
        assert_eq!(result.session.solar_conditions.as_deref(), Some("Stormy")); // nil-only, kept
        // Weather had no prior data, so it fills.
        assert_eq!(result.session.weather_temperature_f, Some(72.0));
    }

    #[test]
    fn record_conditions_non_pota_writes_no_metadata() {
        let store = store();
        insert_session(&store, "s1", "[]"); // casual, not POTA
        let api = SessionApi::new(store.clone());
        let result = api.record_conditions("s1".into(), conditions_input()).unwrap().unwrap();
        assert!(result.metadata.is_none());
        assert_eq!(store.inner.lock().unwrap().activation_metadata_count().unwrap(), 0);
    }

    #[test]
    fn record_conditions_metadata_fills_empty_string_text() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        // Seed a metadata row whose text fields are empty strings (the stricter
        // nil-or-empty fill target).
        {
            let inner = store.inner.lock().unwrap();
            let mut seed = blank_metadata("US-1234", 0);
            seed.solar_conditions = Some(String::new());
            seed.weather = Some(String::new());
            inner.upsert_activation_metadata(&seed).unwrap();
        }
        let api = SessionApi::new(store.clone());
        let meta = api.record_conditions("s1".into(), conditions_input()).unwrap().unwrap().metadata.unwrap();
        assert_eq!(meta.solar_conditions.as_deref(), Some("Good")); // empty string → filled
        assert_eq!(meta.weather.as_deref(), Some("Sunny"));
    }

    #[test]
    fn record_conditions_missing_session_is_none() {
        let store = store();
        let api = SessionApi::new(store);
        assert!(api.record_conditions("missing".into(), conditions_input()).unwrap().is_none());
    }

    // ---------- POTA UTC-midnight split ----------

    /// Log a QSO into a session at a specific UTC timestamp (seconds).
    fn log_at(api: &SessionApi, session_id: &str, ts: i64) {
        let mut input = base_input(session_id);
        input.timestamp_override = Some(ts);
        api.log_qso(input).unwrap().unwrap();
    }

    /// Set a session's `ended_at` (making it a completed session to split).
    fn set_ended_at(store: &FieldStore, session_id: &str, ended_at: i64) {
        let inner = store.inner.lock().unwrap();
        let mut session = inner.fetch_logging_session(session_id).unwrap().unwrap();
        session.ended_at = Some(ended_at);
        inner.upsert_logging_session(&session).unwrap();
    }

    fn rove_stop_row(id: &str, session: &str, park: &str, start: i64, end: i64) -> RoveStop {
        RoveStop {
            id: id.to_string(),
            logging_session_id: session.to_string(),
            park_reference: park.to_string(),
            started_at: start,
            ended_at: Some(end),
            my_grid: None,
            qso_count: 0,
            notes: None,
            cloud_dirty_flag: false,
        }
    }

    #[test]
    fn split_noop_when_single_day_or_absent_or_empty() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());
        // No QSOs → no-op.
        assert!(api.split_at_utc_midnight("s1".into()).unwrap().is_empty());
        // All QSOs on one UTC day → no-op.
        log_at(&api, "s1", 100);
        log_at(&api, "s1", 200);
        assert!(api.split_at_utc_midnight("s1".into()).unwrap().is_empty());
        // Missing session → no-op.
        assert!(api.split_at_utc_midnight("missing".into()).unwrap().is_empty());
    }

    #[test]
    fn split_two_days_reassigns_qsos_and_bounds() {
        let store = store();
        insert_session(&store, "s1", r#"["pota"]"#);
        let api = SessionApi::new(store.clone());
        // Two QSOs on UTC day 0, one on day 1.
        log_at(&api, "s1", 100);
        log_at(&api, "s1", 200);
        log_at(&api, "s1", 90_000); // day 1 (>= 86_400)
        set_ended_at(&store, "s1", 170_000);

        let sessions = api.split_at_utc_midnight("s1".into()).unwrap();
        assert_eq!(sessions.len(), 2); // original + one new
        let original = &sessions[0];
        let new_session = &sessions[1];
        assert_eq!(original.id, "s1");
        assert_eq!(original.ended_at, Some(86_400)); // clipped to second UTC midnight
        assert_eq!(original.qso_count, 2);
        assert_eq!(new_session.started_at, 86_400);
        assert_eq!(new_session.ended_at, Some(170_000)); // original endedAt for the last day
        assert_eq!(new_session.qso_count, 1);
        assert_eq!(new_session.status_raw_value, "completed");
        assert_eq!(new_session.park_reference.as_deref(), Some("US-1234")); // fallback park
        assert_eq!(new_session.programs_raw_value, ""); // activationType "casual" → no programs

        let inner = store.inner.lock().unwrap();
        // Day-0 QSOs stay on the original; the day-1 QSO moved to the new session.
        assert_eq!(inner.fetch_all_qsos_for_session("s1", 100).unwrap().len(), 2);
        assert_eq!(inner.fetch_all_qsos_for_session(&new_session.id, 100).unwrap().len(), 1);
    }

    #[test]
    fn split_derives_programs_from_activation_type() {
        let store = store();
        // A real POTA session carries activationType "pota" (not just the programs blob).
        let mut session = insert_session(&store, "s1", r#"["pota"]"#);
        session.activation_type_raw_value = "pota".to_string();
        store.inner.lock().unwrap().upsert_logging_session(&session).unwrap();
        let api = SessionApi::new(store.clone());
        log_at(&api, "s1", 100);
        log_at(&api, "s1", 90_000);
        set_ended_at(&store, "s1", 170_000);

        let sessions = api.split_at_utc_midnight("s1".into()).unwrap();
        assert_eq!(sessions[1].activation_type_raw_value, "pota");
        assert_eq!(sessions[1].programs_raw_value, r#"["pota"]"#); // derived from activationType
    }

    #[test]
    fn split_clips_rove_stops_and_picks_park_at_midnight() {
        let store = store();
        let mut session = insert_session(&store, "r1", r#"["pota"]"#);
        session.is_rove = true;
        store.inner.lock().unwrap().upsert_logging_session(&session).unwrap();
        // Two rove stops: US-1111 covers day 0, US-2222 covers day 1.
        {
            let inner = store.inner.lock().unwrap();
            inner.upsert_rove_stop(&rove_stop_row("a", "r1", "US-1111", 0, 86_400)).unwrap();
            inner.upsert_rove_stop(&rove_stop_row("b", "r1", "US-2222", 86_400, 170_000)).unwrap();
        }
        let api = SessionApi::new(store.clone());
        log_at(&api, "r1", 100); // day 0
        log_at(&api, "r1", 90_000); // day 1
        set_ended_at(&store, "r1", 170_000);

        let sessions = api.split_at_utc_midnight("r1".into()).unwrap();
        let new_session = &sessions[1];
        // The park active at the second UTC midnight is US-2222.
        assert_eq!(new_session.park_reference.as_deref(), Some("US-2222"));

        let inner = store.inner.lock().unwrap();
        // Original keeps only the day-0 stop; the new session gets the day-1 stop.
        let orig_stops = inner.fetch_rove_stops("r1").unwrap();
        assert_eq!(orig_stops.len(), 1);
        assert_eq!(orig_stops[0].park_reference, "US-1111");
        let new_stops = inner.fetch_rove_stops(&new_session.id).unwrap();
        assert_eq!(new_stops.len(), 1);
        assert_eq!(new_stops[0].park_reference, "US-2222");
        // The split-off stop is a fresh row bound to the new session.
        assert_eq!(new_stops[0].logging_session_id, new_session.id);
    }
}
