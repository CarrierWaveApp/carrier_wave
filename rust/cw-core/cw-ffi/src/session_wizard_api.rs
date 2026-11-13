//! Session-start **wizard** logic — the portable kernel behind the iOS
//! `SessionStartSheet` "Start" action and its Android equivalent.
//!
//! iOS `LoggingSessionManager.startSession` is a `@MainActor` orchestrator: it
//! builds a `LoggingSession`, resolves the grid from caches/GPS, seeds rove, and
//! fires a pile of side effects (Live Activity, spotting, SDR, location). The
//! **pure assembly + normalization** — which the two platforms must agree on to
//! the byte — is what moves here:
//!
//! - **callsign construction** (`fullCallsign` / `clubStationCallsign`): the
//!   `prefix / base / suffix` join with per-part trim+uppercase, and the club
//!   override;
//! - **activation-type derivation** (`ActivationType.from(programs:)`): the fixed
//!   POTA→WWFF→SOTA→AoA→TOTA→casual priority;
//! - **program encoding**: the sorted JSON `[String]` (`programsRawValue`) and
//!   the "casual ⇒ empty" rule;
//! - **reference conditioning**: park/sota/wwff/mission are kept only when their
//!   program is selected, with the exact per-reference normalization
//!   (POTA/SOTA/WWFF uppercased, AoA trimmed-not-uppercased, POTA multi-park
//!   sanitized);
//! - **mode-gated gear**: `myKey` only for CW, `myMic` only for phone modes;
//! - **operator-callsign** normalization (uppercase+trim+dedupe, order-preserved);
//! - the **row defaults** (`status = active`, `qsoCount = 0`, `photoFilenames =
//!   "[]"`, rove first-stop seeding) and the direct TOTA field copies.
//!
//! Two entry points share one assembler:
//! - [`SessionWizardApi::assemble_session`] returns the assembled row **without
//!   persisting** — iOS calls this and copies the computed values onto its
//!   SwiftData `@Model`, keeping its manager machinery intact;
//! - [`SessionWizardApi::create_session`] assembles **and** upserts into the
//!   store (+ observer notify) — the Android path, which has no SwiftData mirror.
//!
//! Grid cache/GPS resolution, the frequency free-slot planner, and the TOTA
//! *derivations* (winter auto-detect, ruck-weight autofill, QRP-from-power) stay
//! host-side for now and land in later phases; this phase takes those as
//! already-computed inputs so iOS behavior is unchanged.

use std::sync::Arc;

use chrono::Utc;
use chrono::TimeZone;
use cw_domain::band_plan::LicenseClass;
use cw_domain::frequency_planner::{self, ActiveStation};
use cw_domain::gear_reminders::{self, ConnectorType};
use cw_domain::kiwisdr::haversine_km;
use cw_domain::location_prefix;
use cw_domain::maidenhead;
use cw_domain::tota;
use cw_store::{LoggingSession, RoveStop};
use uuid::Uuid;

use crate::entities::logging_session::FfiLoggingSession;
use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};

// ---------- kv keys (mirror the iOS `loggerDefault*` UserDefaults keys) ----------

const KV_DEFAULT_MODE: &str = "loggerDefaultMode";
const KV_DEFAULT_POWER: &str = "loggerDefaultPower";
const KV_DEFAULT_GRID: &str = "loggerDefaultGrid";
const KV_DEFAULT_RADIO: &str = "loggerDefaultRadio";
const KV_DEFAULT_ANTENNA: &str = "loggerDefaultAntenna";
const KV_DEFAULT_KEY: &str = "loggerDefaultKey";
const KV_DEFAULT_MIC: &str = "loggerDefaultMic";
const KV_DEFAULT_PROGRAMS: &str = "loggerDefaultPrograms";
const KV_DEFAULT_PARK: &str = "loggerDefaultParkReference";
const KV_DEFAULT_CONTEST: &str = "loggerDefaultContestId";
/// Deprecated single-value key migrated into [`KV_DEFAULT_PROGRAMS`] on read.
const KV_DEFAULT_ACTIVATION_TYPE: &str = "loggerDefaultActivationType";

/// Phone modes that carry a microphone (`myMic` gate in `startSession`).
const PHONE_MODES: [&str; 5] = ["SSB", "USB", "LSB", "AM", "FM"];

// ---------- DTOs ----------

/// Direct-copy TOTA fields, applied only when the derived activation type is
/// `tota` (the iOS `applyTOTAOptions` gate). The *derivations* that feed these
/// (winter auto-detect, ruck-weight autofill, QRP-from-power) stay host-side in
/// this phase, so every field here is a value the host already computed.
#[derive(uniffi::Record, Clone, Default)]
pub struct FfiWizardTotaInput {
    pub activation_latitude: Option<f64>,
    pub activation_longitude: Option<f64>,
    pub qrp_activation: bool,
    pub with_pets: bool,
    pub with_kids: bool,
    pub winlink_sent: bool,
    pub aprs_sent: bool,
    pub varac_sent: bool,
    pub adaptive_sport: bool,
    pub ruck_weight_pounds: Option<f64>,
    /// `"standard"` / `"mobile"`; `None` ⇒ standard.
    pub tota_category_raw_value: Option<String>,
    pub personal_effort_factor: Option<i64>,
    /// `0`/`1`/`None` — `None` means auto-detect (host or a later phase decides).
    pub winter_activation_override: Option<i64>,
}

/// Raw wizard ingredients for a new session. Everything here is what the user
/// entered (base callsign, prefix, resolved suffix string, program set, raw
/// references, resolved grid, parsed frequency/power); this API owns the
/// normalization so both platforms produce an identical row.
#[derive(uniffi::Record, Clone)]
pub struct FfiCreateSessionInput {
    /// Operator base callsign (the settings default). Uppercased here.
    pub base_callsign: String,
    /// Optional prefix (e.g. `"W6"`), may be empty. Trimmed+uppercased here.
    #[uniffi(default = "")]
    pub callsign_prefix: String,
    /// Resolved suffix string (`"P"`, `"M"`, `"MM"`, `"AM"`, or a custom value).
    /// The suffix *enum* stays a UI concern; the host resolves it to a string,
    /// which is then trimmed+uppercased and joined here.
    #[uniffi(default = "")]
    pub suffix: String,
    pub is_club_station: bool,
    /// Club base callsign (used only when `is_club_station`). Trimmed+uppercased.
    #[uniffi(default = "")]
    pub club_callsign_input: String,
    pub mode: String,
    /// Parsed frequency in **MHz** (host parses the text field this phase).
    pub frequency_mhz: Option<f64>,
    pub programs: Vec<String>,
    pub park_reference: Option<String>,
    pub sota_reference: Option<String>,
    pub mission_reference: Option<String>,
    pub wwff_reference: Option<String>,
    /// Grid, already resolved from caches/GPS by the host this phase. Empty ⇒
    /// `None`; otherwise uppercased.
    pub my_grid: Option<String>,
    /// Validated power in watts (host parses/validates `[1, 1500]` this phase).
    pub power: Option<i64>,
    pub my_rig: Option<String>,
    pub my_antenna: Option<String>,
    /// CW key; kept only when `mode == "CW"`.
    pub selected_key: Option<String>,
    /// Microphone; kept only when `mode` is a phone mode.
    pub selected_mic: Option<String>,
    pub extra_equipment: Option<String>,
    pub attendees: Option<String>,
    pub is_rove: bool,
    pub contest_id: Option<String>,
    pub contest_category: Option<String>,
    pub contest_overlay_category: Option<String>,
    pub contest_power: Option<String>,
    pub contest_bands: Option<String>,
    pub contest_operator: Option<String>,
    /// Additional operator callsigns (multi-op). Uppercased+trimmed+deduped.
    #[uniffi(default = [])]
    pub operator_callsigns: Vec<String>,
    /// Local FK to the selected radio `EquipmentItem` (for CAT auto-connect).
    pub radio_item_id: Option<String>,
    #[uniffi(default = None)]
    pub tota: Option<FfiWizardTotaInput>,
    /// Override the generated id (lets the host keep one id across its SwiftData
    /// mirror). `None` ⇒ a fresh lowercased UUID.
    #[uniffi(default = None)]
    pub id_override: Option<String>,
    /// Override the `started_at` timestamp (unix seconds). `None` ⇒ now.
    #[uniffi(default = None)]
    pub started_at_override: Option<i64>,
}

/// Wizard prefill defaults, mirrored to/from the store `kv` under the
/// `loggerDefault*` keys (the iOS `@AppStorage` surface). Every field is
/// optional so a fresh install returns an all-empty snapshot.
#[derive(uniffi::Record, Clone, Default, PartialEq, Debug)]
pub struct FfiWizardDefaults {
    pub mode: Option<String>,
    /// Stored as text (the raw power field), matching iOS.
    pub power: Option<String>,
    pub grid: Option<String>,
    pub radio: Option<String>,
    pub antenna: Option<String>,
    pub key: Option<String>,
    pub mic: Option<String>,
    /// Program slugs (decoded from the sorted JSON blob / migrated legacy key).
    pub programs: Vec<String>,
    pub park_reference: Option<String>,
    pub contest_id: Option<String>,
}

/// One currently-active station the host loaded from POTA/RBN/SOTA. The network
/// fetch stays host-side; this carries the merged, de-duped on-air picture into
/// the planner.
#[derive(uniffi::Record, Clone)]
pub struct FfiActiveStation {
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub frequency_mhz: f64,
    /// Unix-seconds timestamp of the spot.
    pub timestamp: i64,
}

impl From<FfiActiveStation> for ActiveStation {
    fn from(station: FfiActiveStation) -> Self {
        ActiveStation {
            callsign: station.callsign,
            band: station.band,
            mode: station.mode,
            frequency_mhz: station.frequency_mhz,
            timestamp: station.timestamp,
        }
    }
}

/// Result of the free-frequency pick: a suggested MHz (`None` when there's no
/// live activity or no clear slot) and a short human reason (e.g. `"3 kHz clear"`).
#[derive(uniffi::Record)]
pub struct FfiFrequencySuggestion {
    pub frequency_mhz: Option<f64>,
    pub reason: String,
}

/// A DXCC entity matched by location or callsign (prefix picker).
#[derive(uniffi::Record)]
pub struct FfiPrefixCountry {
    pub dxcc: u32,
    pub name: String,
    pub prefix: String,
    pub latitude: f64,
    pub longitude: f64,
}

fn prefix_country(entity: &location_prefix::PrefixCountry) -> FfiPrefixCountry {
    FfiPrefixCountry {
        dxcc: entity.id,
        name: entity.name.to_string(),
        prefix: entity.prefix.to_string(),
        latitude: entity.latitude,
        longitude: entity.longitude,
    }
}

/// A nearby park ranked for the wizard's POTA prefill.
#[derive(uniffi::Record)]
pub struct FfiParkSuggestion {
    pub reference: String,
    pub name: String,
    pub distance_km: f64,
}

/// Upper bound on the bounding-box candidate scan for [`SessionWizardApi::suggest_park`].
const PARK_BOX_CAP: i64 = 2_000;
/// Approximate km per degree of latitude — the bounding-box half-width factor.
const KM_PER_DEGREE: f64 = 111.0;

/// A pack-checklist reminder (`GearReminder`).
#[derive(uniffi::Record)]
pub struct FfiGearReminder {
    pub id: String,
    pub text: String,
    pub icon: String,
}

/// Ounces per tenth-of-a-pound — the ruck-weight autofill divisor
/// (`Double(totalOunces) / 1.6`, then rounded, then `/10`).
const OUNCES_PER_TENTH_POUND: f64 = 1.6;
/// TOTA QRP power ceiling in watts (`totaQRP`: `watts <= 10`).
const TOTA_QRP_MAX_WATTS: i64 = 10;

/// Parse a license-class string (`"Technician"`/`"General"`/`"Extra"` or the
/// `T`/`G`/`E` abbreviations, case-insensitive). Unknown ⇒ `General`, the safe
/// middle privilege the wizard defaults to.
fn parse_license(raw: &str) -> LicenseClass {
    match raw.trim().to_uppercase().as_str() {
        "TECHNICIAN" | "T" => LicenseClass::Technician,
        "EXTRA" | "E" => LicenseClass::Extra,
        _ => LicenseClass::General,
    }
}

// ---------- API object ----------

/// Session-start wizard API bound to a [`FieldStore`]. Stateless — assembly is
/// pure and persistence goes straight to the shared store.
#[derive(uniffi::Object)]
pub struct SessionWizardApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl SessionWizardApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        SessionWizardApi { store }
    }

    /// Assemble the session row from wizard input **without persisting**. iOS
    /// calls this to read the computed field values, then copies them onto its
    /// SwiftData `@Model`; Android can use it for previews.
    pub fn assemble_session(&self, input: FfiCreateSessionInput) -> FfiLoggingSession {
        FfiLoggingSession::from(assemble(input))
    }

    /// Assemble **and** persist the session (upsert + observer notify), returning
    /// the stored row. The Android session-start path.
    pub fn create_session(
        &self,
        input: FfiCreateSessionInput,
    ) -> Result<FfiLoggingSession, CwError> {
        let session = assemble(input);
        {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            store.upsert_logging_session(&session)?;
        }
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::LoggingSession,
            kind: FfiChangeKind::Upsert,
        });
        Ok(FfiLoggingSession::from(session))
    }

    /// Read the wizard prefill defaults from the store `kv`, decoding the program
    /// list and migrating the legacy single-value activation-type key.
    pub fn wizard_defaults(&self) -> Result<FfiWizardDefaults, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let get = |key: &str| -> Result<Option<String>, CwError> {
            Ok(store.kv_get(key)?.filter(|value| !value.is_empty()))
        };
        let programs = match get(KV_DEFAULT_PROGRAMS)? {
            Some(raw) => decode_programs(&raw),
            None => migrate_legacy_programs(get(KV_DEFAULT_ACTIVATION_TYPE)?.as_deref()),
        };
        Ok(FfiWizardDefaults {
            mode: get(KV_DEFAULT_MODE)?,
            power: get(KV_DEFAULT_POWER)?,
            grid: get(KV_DEFAULT_GRID)?,
            radio: get(KV_DEFAULT_RADIO)?,
            antenna: get(KV_DEFAULT_ANTENNA)?,
            key: get(KV_DEFAULT_KEY)?,
            mic: get(KV_DEFAULT_MIC)?,
            programs,
            park_reference: get(KV_DEFAULT_PARK)?,
            contest_id: get(KV_DEFAULT_CONTEST)?,
        })
    }

    /// Pick a free frequency on `band` for `mode`/`license`, nestled among the
    /// host-supplied on-air stations (`SessionStartSheet+FrequencySuggestion`:
    /// band-filter → relevant-stations → recommend). `now` is unix seconds so
    /// stale spots are ignored. Pure — no store access.
    pub fn suggest_frequency(
        &self,
        band: String,
        mode: String,
        license: String,
        stations: Vec<FfiActiveStation>,
        now: i64,
    ) -> FfiFrequencySuggestion {
        let stations: Vec<ActiveStation> = stations.into_iter().map(ActiveStation::from).collect();
        let (frequency_mhz, reason) =
            frequency_planner::plan_frequency(&band, &mode, parse_license(&license), &stations, now);
        FfiFrequencySuggestion { frequency_mhz, reason }
    }

    /// Best POTA park to prefill for a grid (`prefillParkIfNeeded` selection):
    /// nearby parks within `max_distance_km`, ranked by past-activation count
    /// (most-activated first) then distance. `history_limit` bounds the session
    /// scan (iOS uses 400). `None` when the grid is unparseable or nothing is in
    /// range. The host still applies its "only when the field is empty / differs"
    /// guards.
    pub fn suggest_park(
        &self,
        grid: String,
        limit: u32,
        max_distance_km: f64,
        history_limit: i64,
    ) -> Result<Option<FfiParkSuggestion>, CwError> {
        let Some(coord) = maidenhead::coordinate_from_grid(&grid) else {
            return Ok(None);
        };
        let lat_delta = max_distance_km / KM_PER_DEGREE;
        // Guard the longitude span near the poles where cos → 0.
        let lon_scale = coord.latitude.to_radians().cos().abs().max(0.01);
        let lon_delta = max_distance_km / (KM_PER_DEGREE * lon_scale);

        let (candidates, counts) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let candidates = store.fetch_pota_parks_in_box(
                coord.latitude - lat_delta,
                coord.latitude + lat_delta,
                coord.longitude - lon_delta,
                coord.longitude + lon_delta,
                PARK_BOX_CAP,
            )?;
            let counts = store.park_activation_counts(history_limit)?;
            (candidates, counts)
        };

        // Exact haversine radius filter + distance sort + limit (`nearbyParks`).
        let mut nearby: Vec<(String, String, f64)> = candidates
            .into_iter()
            .filter_map(|park| {
                let (lat, lon) = (park.latitude?, park.longitude?);
                let dist = haversine_km(coord.latitude, coord.longitude, lat, lon);
                (dist <= max_distance_km).then_some((park.reference, park.name, dist))
            })
            .collect();
        nearby.sort_by(|a, b| a.2.partial_cmp(&b.2).unwrap_or(std::cmp::Ordering::Equal));
        nearby.truncate(limit as usize);

        // Rank: most-activated first, then nearest (`prefillParkIfNeeded` min).
        let best = nearby.into_iter().reduce(|acc, cand| {
            let acc_count = counts.get(&acc.0.to_uppercase()).copied().unwrap_or(0);
            let cand_count = counts.get(&cand.0.to_uppercase()).copied().unwrap_or(0);
            if cand_count > acc_count || (cand_count == acc_count && cand.2 < acc.2) {
                cand
            } else {
                acc
            }
        });
        Ok(best.map(|(reference, name, distance_km)| FfiParkSuggestion { reference, name, distance_km }))
    }

    /// Build the Pack Checklist reminders for the selected gear/mode
    /// (`GearReminderEngine.generate`). Connector args are raw values
    /// (`"BNC"`/`"SO-239"`/`"SMA"`/`"N-Type"`); unknown/absent ⇒ untagged. Pure.
    pub fn pack_checklist(
        &self,
        radio_connector: Option<String>,
        antenna_connector: Option<String>,
        mode: String,
        has_antenna: bool,
        has_key: bool,
    ) -> Vec<FfiGearReminder> {
        let radio = radio_connector.as_deref().and_then(ConnectorType::from_raw);
        let antenna = antenna_connector.as_deref().and_then(ConnectorType::from_raw);
        gear_reminders::generate(radio, antenna, &mode, has_antenna, has_key)
            .into_iter()
            .map(|reminder| FfiGearReminder {
                id: reminder.id,
                text: reminder.text,
                icon: reminder.icon,
            })
            .collect()
    }

    /// TOTA QRP flag derived from wattage (`totaQRP`: `<= 10 W`; unknown ⇒ false).
    pub fn tota_qrp(&self, power: Option<i64>) -> bool {
        power.map(|watts| watts <= TOTA_QRP_MAX_WATTS).unwrap_or(false)
    }

    /// Effective TOTA winter flag: operator override, else auto-detect from the
    /// activation coordinate (`totaEffectiveWinter`). `now` is unix seconds.
    pub fn tota_effective_winter(
        &self,
        winter_override: Option<bool>,
        latitude: Option<f64>,
        now: i64,
    ) -> bool {
        winter_override.unwrap_or_else(|| {
            let date = Utc.timestamp_opt(now, 0).single().unwrap_or_else(Utc::now);
            tota::is_winter(latitude, date)
        })
    }

    /// Convert a summed gear weight in ounces to the ruck-weight pounds value the
    /// autofill writes (`recomputeTOTARuckWeightIfNeeded`: round to 0.1 lb). The
    /// host sums its inventory's `weightOunces` for the selected gear (SwiftData
    /// on iOS, `EquipmentApi` on Android) and passes the total here.
    pub fn ruck_weight_pounds_from_ounces(&self, total_ounces: i64) -> Option<f64> {
        if total_ounces <= 0 {
            return None;
        }
        Some((total_ounces as f64 / OUNCES_PER_TENTH_POUND).round() / 10.0)
    }

    /// Nearest DXCC entity to a coordinate (prefix picker GPS suggestion).
    pub fn nearest_prefix(&self, latitude: f64, longitude: f64) -> Option<FfiPrefixCountry> {
        location_prefix::nearest(latitude, longitude).map(prefix_country)
    }

    /// Nearest DXCC entity to a Maidenhead grid.
    pub fn nearest_prefix_for_grid(&self, grid: String) -> Option<FfiPrefixCountry> {
        location_prefix::nearest_for_grid(&grid).map(prefix_country)
    }

    /// Search the DXCC entity table by name/prefix (prefix picker browser).
    pub fn search_prefixes(&self, query: String) -> Vec<FfiPrefixCountry> {
        location_prefix::search(&query).into_iter().map(prefix_country).collect()
    }

    /// Persist the wizard prefill defaults to the store `kv`. Mirrors the iOS
    /// `saveDefaults()` write set: programs are stored as sorted JSON and the
    /// park reference is uppercased.
    pub fn save_wizard_defaults(&self, defaults: FfiWizardDefaults) -> Result<(), CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let put = |key: &str, value: Option<&str>| -> Result<(), CwError> {
            match value {
                Some(text) if !text.is_empty() => store.kv_set(key, text)?,
                _ => store.kv_delete(key)?,
            }
            Ok(())
        };
        put(KV_DEFAULT_MODE, defaults.mode.as_deref())?;
        put(KV_DEFAULT_POWER, defaults.power.as_deref())?;
        put(KV_DEFAULT_GRID, defaults.grid.map(|grid| grid.to_uppercase()).as_deref())?;
        put(KV_DEFAULT_RADIO, defaults.radio.as_deref())?;
        put(KV_DEFAULT_ANTENNA, defaults.antenna.as_deref())?;
        put(KV_DEFAULT_KEY, defaults.key.as_deref())?;
        put(KV_DEFAULT_MIC, defaults.mic.as_deref())?;
        put(KV_DEFAULT_PARK, defaults.park_reference.map(|park| park.to_uppercase()).as_deref())?;
        put(KV_DEFAULT_CONTEST, defaults.contest_id.as_deref())?;
        // Programs: sorted JSON, or clear the key when empty (a casual default).
        if defaults.programs.is_empty() {
            store.kv_delete(KV_DEFAULT_PROGRAMS)?;
        } else {
            store.kv_set(KV_DEFAULT_PROGRAMS, &encode_programs(&defaults.programs))?;
        }
        Ok(())
    }
}

// ---------- pure assembly ----------

/// Build the `LoggingSession` row from wizard input. Pure — no store, no clock
/// side effects beyond the `started_at` default. This is the byte-for-byte
/// parity surface both platforms share.
fn assemble(input: FfiCreateSessionInput) -> LoggingSession {
    let programs = sanitized_programs(&input.programs);
    let activation = activation_type_from_programs(&programs);
    let is_tota = activation == "tota";
    let has = |slug: &str| programs.iter().any(|program| program == slug);

    let my_callsign = if input.is_club_station {
        input.base_callsign.trim().to_uppercase()
    } else {
        join_callsign(&input.callsign_prefix, &input.base_callsign, &input.suffix)
    };
    let station_callsign = club_station_callsign(&input);

    let park_reference = if has("pota") {
        input.park_reference.as_deref().and_then(sanitize_multi_park)
    } else {
        None
    };
    let sota_reference =
        if has("sota") { normalize_upper(input.sota_reference.as_deref()) } else { None };
    let mission_reference =
        if has("aoa") { normalize_trim(input.mission_reference.as_deref()) } else { None };
    let wwff_reference =
        if has("wwff") { normalize_upper(input.wwff_reference.as_deref()) } else { None };

    let my_key = if input.mode == "CW" { input.selected_key.clone() } else { None };
    let my_mic = if is_phone_mode(&input.mode) { input.selected_mic.clone() } else { None };

    let started_at = input.started_at_override.unwrap_or_else(|| Utc::now().timestamp());
    let id = input.id_override.clone().unwrap_or_else(|| Uuid::new_v4().to_string());

    let operator_callsigns_raw_value = encode_operators(&input.operator_callsigns);
    let is_rove = input.is_rove && activation == "pota" && park_reference.is_some();
    let rove_stops_data = if is_rove {
        rove_first_stop_blob(park_reference.as_deref(), started_at, input.my_grid.as_deref())
    } else {
        None
    };

    let mut session = LoggingSession {
        id,
        my_callsign,
        started_at,
        ended_at: None,
        frequency: input.frequency_mhz,
        mode: input.mode.clone(),
        activation_type_raw_value: activation,
        programs_raw_value: encode_programs(&programs),
        status_raw_value: "active".to_string(),
        park_reference,
        sota_reference,
        mission_reference,
        wwff_reference,
        my_grid: normalize_grid(input.my_grid.as_deref()),
        power: input.power,
        my_rig: input.my_rig,
        notes: None,
        qso_comment: None,
        custom_title: None,
        qso_count: 0,
        spot_comments_data: None,
        is_rove,
        rove_stops_data,
        my_antenna: input.my_antenna,
        my_key,
        my_mic,
        extra_equipment: input.extra_equipment,
        attendees: normalize_trim(input.attendees.as_deref()),
        photo_filenames: "[]".to_string(),
        radio_item_id: input.radio_item_id,
        station_callsign,
        operator_callsigns_raw_value,
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
        contest_id: input.contest_id,
        contest_category: input.contest_category,
        contest_overlay_category: input.contest_overlay_category,
        contest_power: input.contest_power,
        contest_bands: input.contest_bands,
        contest_operator: input.contest_operator,
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

    // `if let totaOptions, activationType == .tota { applyTOTAOptions(...) }`.
    if is_tota {
        if let Some(tota) = input.tota {
            apply_tota(&mut session, &tota);
        }
    }
    session
}

/// Apply the direct-copy TOTA fields (`applyTOTAOptions`). Derivations that feed
/// these stay host-side this phase.
fn apply_tota(session: &mut LoggingSession, tota: &FfiWizardTotaInput) {
    session.activation_latitude = tota.activation_latitude;
    session.activation_longitude = tota.activation_longitude;
    session.qrp_activation = tota.qrp_activation;
    session.with_pets = tota.with_pets;
    session.with_kids = tota.with_kids;
    session.winlink_sent = tota.winlink_sent;
    session.aprs_sent = tota.aprs_sent;
    session.varac_sent = tota.varac_sent;
    session.adaptive_sport = tota.adaptive_sport;
    session.ruck_weight_pounds = tota.ruck_weight_pounds;
    session.tota_category_raw_value = tota.tota_category_raw_value.clone();
    session.personal_effort_factor = tota.personal_effort_factor;
    session.winter_activation_override = tota.winter_activation_override;
}

/// `ActivationType.from(programs:)` — fixed priority, first match wins.
fn activation_type_from_programs(programs: &[String]) -> String {
    for slug in ["pota", "wwff", "sota", "aoa", "tota"] {
        if programs.iter().any(|program| program == slug) {
            return slug.to_string();
        }
    }
    "casual".to_string()
}

/// Distinct program slugs, dropping blanks. Order is irrelevant — the row stores
/// the sorted JSON — so a stable de-dupe via sort keeps assembly deterministic.
fn sanitized_programs(programs: &[String]) -> Vec<String> {
    let mut out: Vec<String> =
        programs.iter().map(|slug| slug.trim().to_string()).filter(|slug| !slug.is_empty()).collect();
    out.sort();
    out.dedup();
    out
}

/// `selectedPrograms.sorted()` → JSON `[String]`; empty ⇒ `""` (the casual
/// sentinel `LoggingSession.programs` decodes back to "no program").
fn encode_programs(programs: &[String]) -> String {
    let sorted = sanitized_programs(programs);
    if sorted.is_empty() {
        return String::new();
    }
    serde_json::to_string(&sorted).unwrap_or_default()
}

/// Decode the stored JSON program blob into a sorted, de-duped slug list.
fn decode_programs(raw: &str) -> Vec<String> {
    serde_json::from_str::<Vec<String>>(raw).map(|slugs| sanitized_programs(&slugs)).unwrap_or_default()
}

/// Migrate the legacy `loggerDefaultActivationType` single value: a program
/// (`pota`/`sota`/…) becomes a one-element list; `casual`/absent ⇒ empty.
fn migrate_legacy_programs(activation_type: Option<&str>) -> Vec<String> {
    match activation_type {
        Some(value) if !value.is_empty() && value != "casual" => vec![value.to_string()],
        _ => Vec::new(),
    }
}

/// Join `prefix / base / suffix`, trimming+uppercasing each part and dropping the
/// empty ones (`fullCallsign`).
fn join_callsign(prefix: &str, base: &str, suffix: &str) -> String {
    [prefix.trim().to_uppercase(), base.trim().to_uppercase(), suffix.trim().to_uppercase()]
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("/")
}

/// `clubStationCallsign` — `None` unless club mode with a non-empty club base.
fn club_station_callsign(input: &FfiCreateSessionInput) -> Option<String> {
    if !input.is_club_station {
        return None;
    }
    let base = input.club_callsign_input.trim().to_uppercase();
    if base.is_empty() {
        return None;
    }
    Some(join_callsign(&input.callsign_prefix, &base, &input.suffix))
}

/// Uppercase+trim+dedupe operator callsigns, **preserving first-seen order**
/// (unlike programs, which are sorted), then JSON-encode. Empty ⇒ `"[]"`.
fn encode_operators(operators: &[String]) -> String {
    let mut seen: Vec<String> = Vec::new();
    for raw in operators {
        let call = raw.trim().to_uppercase();
        if !call.is_empty() && !seen.contains(&call) {
            seen.push(call);
        }
    }
    serde_json::to_string(&seen).unwrap_or_else(|_| "[]".to_string())
}

fn is_phone_mode(mode: &str) -> bool {
    PHONE_MODES.contains(&mode)
}

/// `myGrid.isEmpty ? nil : myGrid.uppercased()`.
fn normalize_grid(grid: Option<&str>) -> Option<String> {
    grid.map(str::trim).filter(|value| !value.is_empty()).map(str::to_uppercase)
}

/// Uppercase a reference, dropping empty/absent (`wwffReference.uppercased()`
/// gated on non-empty).
fn normalize_upper(value: Option<&str>) -> Option<String> {
    value.map(str::trim).filter(|text| !text.is_empty()).map(str::to_uppercase)
}

/// Trim a reference/attendees, dropping empty/absent — no uppercase (AoA mission,
/// attendees).
fn normalize_trim(value: Option<&str>) -> Option<String> {
    value.map(str::trim).filter(|text| !text.is_empty()).map(str::to_string)
}

/// POTA multi-park sanitize (`ParkReference.sanitizeMulti`): uppercase, split on
/// commas, keep non-empty, re-join with `,`. `None` when nothing survives.
fn sanitize_multi_park(raw: &str) -> Option<String> {
    let joined = cw_domain::park_reference::split(&raw.to_uppercase()).join(",");
    if joined.is_empty() {
        None
    } else {
        Some(joined)
    }
}

/// JSON blob for the rove first stop (`RoveStop(parkReference:startedAt:myGrid:)`
/// then JSON-encode into `rove_stops_data`).
fn rove_first_stop_blob(park: Option<&str>, started_at: i64, grid: Option<&str>) -> Option<Vec<u8>> {
    let stop = RoveStop {
        id: Uuid::new_v4().to_string(),
        logging_session_id: String::new(),
        park_reference: park.unwrap_or_default().to_string(),
        started_at,
        ended_at: None,
        my_grid: normalize_grid(grid),
        qso_count: 0,
        notes: None,
        cloud_dirty_flag: true,
    };
    serde_json::to_vec(&[stop]).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> Arc<FieldStore> {
        Arc::new(FieldStore::open_in_memory("k".into()).unwrap())
    }

    fn base_input() -> FfiCreateSessionInput {
        FfiCreateSessionInput {
            base_callsign: "w6jy".to_string(),
            callsign_prefix: String::new(),
            suffix: String::new(),
            is_club_station: false,
            club_callsign_input: String::new(),
            mode: "CW".to_string(),
            frequency_mhz: Some(14.062),
            programs: vec![],
            park_reference: None,
            sota_reference: None,
            mission_reference: None,
            wwff_reference: None,
            my_grid: Some("cm87".to_string()),
            power: Some(5),
            my_rig: Some("KX2".to_string()),
            my_antenna: Some("EFHW".to_string()),
            selected_key: Some("Palm".to_string()),
            selected_mic: Some("SM58".to_string()),
            extra_equipment: None,
            attendees: Some("  Bob, Sue  ".to_string()),
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
            id_override: Some("sess-1".to_string()),
            started_at_override: Some(1_700_000_000),
        }
    }

    #[test]
    fn casual_defaults_and_normalization() {
        let session = assemble(base_input());
        assert_eq!(session.my_callsign, "W6JY"); // uppercased
        assert_eq!(session.activation_type_raw_value, "casual");
        assert_eq!(session.programs_raw_value, ""); // casual ⇒ empty
        assert_eq!(session.status_raw_value, "active");
        assert_eq!(session.qso_count, 0);
        assert_eq!(session.photo_filenames, "[]");
        assert_eq!(session.my_grid.as_deref(), Some("CM87")); // uppercased
        assert_eq!(session.attendees.as_deref(), Some("Bob, Sue")); // trimmed
        assert_eq!(session.my_key.as_deref(), Some("Palm")); // CW keeps key
        assert!(session.my_mic.is_none()); // CW drops mic
        assert!(session.cloud_dirty_flag);
        assert!(!session.is_rove);
        assert!(session.park_reference.is_none()); // no pota program
    }

    #[test]
    fn phone_mode_gates_gear() {
        let mut input = base_input();
        input.mode = "SSB".to_string();
        let session = assemble(input);
        assert!(session.my_key.is_none()); // non-CW drops key
        assert_eq!(session.my_mic.as_deref(), Some("SM58")); // phone keeps mic
    }

    #[test]
    fn activation_type_priority_pota_over_wwff() {
        let mut input = base_input();
        input.programs = vec!["wwff".to_string(), "pota".to_string()];
        input.park_reference = Some("k-1234".to_string());
        input.wwff_reference = Some("kff-1234".to_string());
        let session = assemble(input);
        assert_eq!(session.activation_type_raw_value, "pota"); // pota wins
        assert_eq!(session.programs_raw_value, r#"["pota","wwff"]"#); // sorted JSON
        assert_eq!(session.park_reference.as_deref(), Some("K-1234")); // uppercased
        assert_eq!(session.wwff_reference.as_deref(), Some("KFF-1234"));
    }

    #[test]
    fn references_dropped_when_program_unselected() {
        let mut input = base_input();
        input.programs = vec!["sota".to_string()];
        input.sota_reference = Some("w6/ct-225".to_string());
        input.park_reference = Some("K-1234".to_string()); // pota not selected
        input.wwff_reference = Some("KFF-1".to_string());
        let session = assemble(input);
        assert_eq!(session.activation_type_raw_value, "sota");
        assert_eq!(session.sota_reference.as_deref(), Some("W6/CT-225")); // uppercased
        assert!(session.park_reference.is_none()); // dropped
        assert!(session.wwff_reference.is_none()); // dropped
    }

    #[test]
    fn aoa_mission_trimmed_not_uppercased() {
        let mut input = base_input();
        input.programs = vec!["aoa".to_string()];
        input.mission_reference = Some("  Operation Blue  ".to_string());
        let session = assemble(input);
        assert_eq!(session.activation_type_raw_value, "aoa");
        assert_eq!(session.mission_reference.as_deref(), Some("Operation Blue"));
    }

    #[test]
    fn club_station_callsign_and_operator() {
        let mut input = base_input();
        input.is_club_station = true;
        input.club_callsign_input = "  w6abc  ".to_string();
        input.callsign_prefix = "kh6".to_string();
        input.suffix = "p".to_string();
        let session = assemble(input);
        // Operator callsign is the base, unmodified by prefix/suffix in club mode.
        assert_eq!(session.my_callsign, "W6JY");
        // Club station carries the prefix/suffix.
        assert_eq!(session.station_callsign.as_deref(), Some("KH6/W6ABC/P"));
    }

    #[test]
    fn prefix_suffix_join() {
        let mut input = base_input();
        input.callsign_prefix = "  w6 ".to_string();
        input.suffix = "p".to_string();
        let session = assemble(input);
        assert_eq!(session.my_callsign, "W6/W6JY/P");
    }

    #[test]
    fn operator_callsigns_uppercased_deduped_order_preserved() {
        let mut input = base_input();
        input.operator_callsigns =
            vec![" n0call ".to_string(), "W1AW".to_string(), "n0call".to_string()];
        let session = assemble(input);
        assert_eq!(session.operator_callsigns_raw_value, r#"["N0CALL","W1AW"]"#);
    }

    #[test]
    fn rove_seeds_first_stop_only_for_pota_with_park() {
        let mut input = base_input();
        input.is_rove = true;
        input.programs = vec!["pota".to_string()];
        input.park_reference = Some("K-1234".to_string());
        let session = assemble(input);
        assert!(session.is_rove);
        let blob = session.rove_stops_data.expect("rove blob present");
        let stops: Vec<RoveStop> = serde_json::from_slice(&blob).unwrap();
        assert_eq!(stops.len(), 1);
        assert_eq!(stops[0].park_reference, "K-1234");
        assert_eq!(stops[0].started_at, 1_700_000_000);
        assert_eq!(stops[0].my_grid.as_deref(), Some("CM87"));

        // Rove without POTA is ignored.
        let mut casual = base_input();
        casual.is_rove = true;
        let casual_session = assemble(casual);
        assert!(!casual_session.is_rove);
        assert!(casual_session.rove_stops_data.is_none());
    }

    #[test]
    fn tota_fields_applied_only_for_tota() {
        let mut input = base_input();
        input.programs = vec!["tota".to_string()];
        input.tota = Some(FfiWizardTotaInput {
            activation_latitude: Some(37.5),
            activation_longitude: Some(-122.1),
            qrp_activation: true,
            personal_effort_factor: Some(7),
            tota_category_raw_value: Some("mobile".to_string()),
            winter_activation_override: Some(1),
            ..Default::default()
        });
        let session = assemble(input);
        assert_eq!(session.activation_type_raw_value, "tota");
        assert_eq!(session.activation_latitude, Some(37.5));
        assert!(session.qrp_activation);
        assert_eq!(session.personal_effort_factor, Some(7));
        assert_eq!(session.tota_category_raw_value.as_deref(), Some("mobile"));
        assert_eq!(session.winter_activation_override, Some(1));

        // Same TOTA input on a casual session is ignored (activation gate).
        let mut casual = base_input();
        casual.tota = Some(FfiWizardTotaInput { qrp_activation: true, ..Default::default() });
        assert!(!assemble(casual).qrp_activation);
    }

    #[test]
    fn create_session_persists_and_is_fetchable() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());
        let row = api.create_session(base_input()).unwrap();
        assert_eq!(row.id, "sess-1");

        let fetched = store.fetch_logging_session("sess-1".to_string()).unwrap().unwrap();
        assert_eq!(fetched.my_callsign, "W6JY");
        assert_eq!(fetched.status_raw_value, "active");
    }

    #[test]
    fn assemble_does_not_persist() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());
        let _ = api.assemble_session(base_input());
        assert_eq!(store.logging_session_count().unwrap(), 0);
    }

    #[test]
    fn wizard_defaults_roundtrip() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());

        let defaults = FfiWizardDefaults {
            mode: Some("SSB".to_string()),
            power: Some("100".to_string()),
            grid: Some("cm87".to_string()),
            radio: Some("IC-705".to_string()),
            antenna: None,
            key: None,
            mic: Some("SM58".to_string()),
            programs: vec!["sota".to_string(), "pota".to_string()],
            park_reference: Some("k-1234".to_string()),
            contest_id: None,
        };
        api.save_wizard_defaults(defaults).unwrap();

        let loaded = api.wizard_defaults().unwrap();
        assert_eq!(loaded.mode.as_deref(), Some("SSB"));
        assert_eq!(loaded.grid.as_deref(), Some("CM87")); // uppercased on save
        assert_eq!(loaded.park_reference.as_deref(), Some("K-1234"));
        assert_eq!(loaded.programs, vec!["pota".to_string(), "sota".to_string()]); // sorted
        assert!(loaded.antenna.is_none());
    }

    #[test]
    fn suggest_frequency_picks_clear_slot() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());
        let stations = vec![
            FfiActiveStation {
                callsign: "A".to_string(),
                band: "20m".to_string(),
                mode: "CW".to_string(),
                frequency_mhz: 14.030,
                timestamp: 1000,
            },
            FfiActiveStation {
                callsign: "B".to_string(),
                band: "20m".to_string(),
                mode: "CW".to_string(),
                frequency_mhz: 14.035,
                timestamp: 1000,
            },
        ];
        let suggestion =
            api.suggest_frequency("20m".to_string(), "CW".to_string(), "General".to_string(), stations, 1000);
        let freq = suggestion.frequency_mhz.expect("a clear frequency");
        assert!((14.025..14.070).contains(&freq));
        assert!(suggestion.reason.ends_with("kHz clear"));
    }

    #[test]
    fn suggest_frequency_none_without_activity() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());
        let suggestion =
            api.suggest_frequency("20m".to_string(), "CW".to_string(), "General".to_string(), vec![], 1000);
        assert!(suggestion.frequency_mhz.is_none());
    }

    #[test]
    fn suggest_park_ranks_by_activation_then_distance() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());

        // Two parks near CM87, one far away.
        {
            let inner = store.inner.lock().unwrap();
            let park = |reference: &str, lat: f64, lon: f64| cw_store::PotaPark {
                reference: reference.to_string(),
                name: format!("Park {reference}"),
                location_desc: "US-CA".to_string(),
                latitude: Some(lat),
                longitude: Some(lon),
                grid: None,
                entity_id: 291,
                is_active: true,
            };
            inner
                .upsert_pota_parks(&[
                    park("US-NEAR1", 37.5, -122.9), // closest
                    park("US-NEAR2", 37.6, -123.1),
                    park("US-FAR", 0.0, 0.0), // far away, excluded by radius
                ])
                .unwrap();
        }

        // Activate the farther-but-more-visited park twice, the closest once.
        let activate = |api: &SessionWizardApi, park: &str, id: &str| {
            let mut input = base_input();
            input.programs = vec!["pota".to_string()];
            input.park_reference = Some(park.to_string());
            input.id_override = Some(id.to_string());
            api.create_session(input).unwrap();
        };
        activate(&api, "US-NEAR2", "s1");
        activate(&api, "US-NEAR2", "s2");
        activate(&api, "US-NEAR1", "s3");

        // Most-activated wins over the strictly-closer park.
        let best = api.suggest_park("CM87".to_string(), 10, 100.0, 400).unwrap().expect("a park");
        assert_eq!(best.reference, "US-NEAR2");
        assert!(best.distance_km <= 100.0);

        // A tiny radius rules everything out.
        assert!(api.suggest_park("CM87".to_string(), 10, 0.001, 400).unwrap().is_none());
        // An unparseable grid returns None.
        assert!(api.suggest_park("".to_string(), 10, 100.0, 400).unwrap().is_none());
    }

    #[test]
    fn pack_checklist_and_tota_helpers() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());

        // Pack checklist mirrors GearReminderEngine ordering/ids.
        let reminders = api.pack_checklist(
            Some("BNC".to_string()),
            None,
            "CW".to_string(),
            true,
            true,
        );
        let ids: Vec<&str> = reminders.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids.first(), Some(&"coax-BNC"));
        assert!(ids.contains(&"key-cable"));
        assert_eq!(reminders.last().unwrap().id, "headphones");

        // TOTA QRP threshold.
        assert!(api.tota_qrp(Some(5)));
        assert!(api.tota_qrp(Some(10)));
        assert!(!api.tota_qrp(Some(11)));
        assert!(!api.tota_qrp(None));

        // Effective winter: override wins; else auto-detect.
        assert!(api.tota_effective_winter(Some(true), Some(-40.0), 0));
        // 2026-01-15 UTC in the northern hemisphere → winter.
        let jan = Utc.with_ymd_and_hms(2026, 1, 15, 12, 0, 0).unwrap().timestamp();
        assert!(api.tota_effective_winter(None, Some(45.0), jan));
        // Same date, southern hemisphere → not winter.
        assert!(!api.tota_effective_winter(None, Some(-33.0), jan));

        // Ruck weight ounces → pounds (round to 0.1 lb): 32 oz / 1.6 = 20 → 2.0 lb.
        assert_eq!(api.ruck_weight_pounds_from_ounces(32), Some(2.0));
        assert!(api.ruck_weight_pounds_from_ounces(0).is_none());
    }

    #[test]
    fn prefix_lookup_by_grid_and_search() {
        let store = store();
        let api = SessionWizardApi::new(store.clone());
        // CM87 (SF Bay) resolves to a US entity.
        let entity = api.nearest_prefix_for_grid("CM87".to_string()).expect("entity");
        assert!(!entity.prefix.is_empty());
        // Search returns matches.
        assert!(!api.search_prefixes("United States".to_string()).is_empty());
    }

    #[test]
    fn wizard_defaults_migrates_legacy_activation_type() {
        let store = store();
        {
            let inner = store.inner.lock().unwrap();
            inner.kv_set(KV_DEFAULT_ACTIVATION_TYPE, "pota").unwrap();
        }
        let api = SessionWizardApi::new(store.clone());
        let loaded = api.wizard_defaults().unwrap();
        assert_eq!(loaded.programs, vec!["pota".to_string()]);

        // Casual legacy value ⇒ no programs.
        {
            let inner = store.inner.lock().unwrap();
            inner.kv_set(KV_DEFAULT_ACTIVATION_TYPE, "casual").unwrap();
        }
        assert!(api.wizard_defaults().unwrap().programs.is_empty());
    }
}
