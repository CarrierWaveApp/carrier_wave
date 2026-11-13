//! LoggingSession — mirrors LoggingSession.swift

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// A logging session (activation). Plain value type — the FFI exposes this,
/// not a live row. Field names and types are a faithful port of the SwiftData
/// `@Model` stored properties in `LoggingSession.swift`; computed properties
/// and methods are omitted.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LoggingSession {
    /// Primary key. UUID stringified (lowercase hyphenated).
    pub id: String,
    pub my_callsign: String,
    /// Unix seconds, UTC.
    pub started_at: i64,
    /// Unix seconds, UTC. Nil until the session is ended.
    pub ended_at: Option<i64>,
    pub frequency: Option<f64>,
    pub mode: String,
    /// Raw value of `ActivationType` enum (e.g. `"pota"`, `"casual"`).
    pub activation_type_raw_value: String,
    /// JSON-encoded `[String]` of program slugs (e.g. `["pota","wwff"]`).
    pub programs_raw_value: String,
    /// Raw value of `LoggingSessionStatus` enum (`"active"`, `"paused"`, `"completed"`).
    pub status_raw_value: String,
    pub park_reference: Option<String>,
    pub sota_reference: Option<String>,
    pub mission_reference: Option<String>,
    pub wwff_reference: Option<String>,
    pub my_grid: Option<String>,
    pub power: Option<i64>,
    pub my_rig: Option<String>,
    pub notes: Option<String>,
    /// Prepended to every QSO's notes.
    pub qso_comment: Option<String>,
    pub custom_title: Option<String>,
    pub qso_count: i64,
    /// JSON-encoded `[POTASpotComment]` blob.
    pub spot_comments_data: Option<Vec<u8>>,
    pub is_rove: bool,
    /// JSON-encoded `[RoveStop]` blob.
    pub rove_stops_data: Option<Vec<u8>>,
    pub my_antenna: Option<String>,
    pub my_key: Option<String>,
    pub my_mic: Option<String>,
    pub extra_equipment: Option<String>,
    pub attendees: Option<String>,
    /// JSON-encoded `[String]` of photo filenames.
    pub photo_filenames: String,
    /// UUID stringified — local FK to `EquipmentItem`.
    pub radio_item_id: Option<String>,
    pub station_callsign: Option<String>,
    /// JSON-encoded `[String]` of additional operator callsigns.
    pub operator_callsigns_raw_value: String,
    // --- Solar / propagation conditions ---
    pub solar_k_index: Option<f64>,
    pub solar_flux: Option<f64>,
    pub solar_sunspots: Option<i64>,
    pub solar_propagation_rating: Option<String>,
    pub solar_a_index: Option<i64>,
    pub solar_band_conditions: Option<String>,
    /// Unix seconds, UTC.
    pub solar_timestamp: Option<i64>,
    pub solar_conditions: Option<String>,
    // --- Weather conditions ---
    pub weather_temperature_f: Option<f64>,
    pub weather_temperature_c: Option<f64>,
    pub weather_humidity: Option<i64>,
    pub weather_wind_speed: Option<f64>,
    pub weather_wind_direction: Option<String>,
    pub weather_description: Option<String>,
    /// Unix seconds, UTC.
    pub weather_timestamp: Option<i64>,
    pub weather: Option<String>,
    /// Sync-journal dirty flag (mirrors `cloudDirtyFlag`).
    pub cloud_dirty_flag: bool,
    // --- Contest fields ---
    /// Matches `ContestDefinition.id`.
    pub contest_id: Option<String>,
    /// Primary category (e.g. `"SOAB-HP"`).
    pub contest_category: Option<String>,
    /// Overlay category (e.g. `"YL"`, `"ROOKIE"`).
    pub contest_overlay_category: Option<String>,
    /// `"HIGH"`, `"LOW"`, `"QRP"`, or custom.
    pub contest_power: Option<String>,
    /// `"ALL"` or single band.
    pub contest_bands: Option<String>,
    /// Callsign override for multi-op.
    pub contest_operator: Option<String>,
    // --- TOTA / activation geometry ---
    /// Activation site latitude (decimal degrees).
    pub activation_latitude: Option<f64>,
    /// Activation site longitude (decimal degrees).
    pub activation_longitude: Option<f64>,
    /// Distance travelled to/at the site, miles.
    pub activation_distance_miles: Option<f64>,
    /// Elevation gain in feet.
    pub activation_elevation_gain_feet: Option<f64>,
    /// Pack weight in pounds (TOTA ruck bonus).
    pub ruck_weight_pounds: Option<f64>,
    /// Operator stayed at ≤ 10 W for the entire session (TOTA QRP 2× multiplier).
    pub qrp_activation: bool,
    pub with_pets: bool,
    pub with_kids: bool,
    pub winlink_sent: bool,
    pub aprs_sent: bool,
    /// VarAC VMail / email sent over RF (TOTA flat +5 pts).
    pub varac_sent: bool,
    /// TOTA "adaptive sport" descriptor (display only).
    pub adaptive_sport: bool,
    /// JSON-encoded `[TrackPoint]` blob.
    pub track_points_data: Option<Vec<u8>>,
    /// Raw value of `TOTACategory` enum (`"standard"`, `"mobile"`). Nil = standard.
    pub tota_category_raw_value: Option<String>,
    pub personal_effort_factor: Option<i64>,
    /// Operator-asserted first activation of the tile ever.
    pub first_activation_of_tile_ever: bool,
    /// Operator override of auto-detected winter flag. None = auto-detect.
    /// Stored as INTEGER (0/1/NULL).
    pub winter_activation_override: Option<i64>,
    /// JSON-encoded `[String]` of 6-char Maidenhead tiles activated this session.
    pub tiles_activated_data: Option<Vec<u8>>,
    /// JSON-encoded `[T3Candidate]` blob from TOTA spots correlation.
    pub tota_t3_candidates_data: Option<Vec<u8>>,
    /// Unix seconds, UTC. When `tota_t3_candidates_data` was last refreshed.
    pub tota_t3_snapshot_at: Option<i64>,
    /// Server-returned official TOTA points after upload. None pre-upload.
    pub tota_official_points: Option<f64>,
}

/// DDL for `logging_session` and its supporting indexes. Registered by the
/// migration runner; exposed here so it stays co-located with the struct it
/// describes.
pub(crate) const LOGGING_SESSION_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS logging_session (
    id                           TEXT    PRIMARY KEY NOT NULL,
    my_callsign                  TEXT    NOT NULL,
    started_at                   INTEGER NOT NULL,   -- unix seconds, UTC
    ended_at                     INTEGER,            -- unix seconds, UTC
    frequency                    REAL,
    mode                         TEXT    NOT NULL,
    activation_type_raw_value    TEXT    NOT NULL,
    programs_raw_value           TEXT    NOT NULL,
    status_raw_value             TEXT    NOT NULL,
    park_reference               TEXT,
    sota_reference               TEXT,
    mission_reference            TEXT,
    wwff_reference               TEXT,
    my_grid                      TEXT,
    power                        INTEGER,
    my_rig                       TEXT,
    notes                        TEXT,
    qso_comment                  TEXT,
    custom_title                 TEXT,
    qso_count                    INTEGER NOT NULL DEFAULT 0,
    spot_comments_data           BLOB,
    is_rove                      INTEGER NOT NULL DEFAULT 0,
    rove_stops_data              BLOB,
    my_antenna                   TEXT,
    my_key                       TEXT,
    my_mic                       TEXT,
    extra_equipment              TEXT,
    attendees                    TEXT,
    photo_filenames              TEXT    NOT NULL DEFAULT '[]',  -- JSON [String]
    radio_item_id                TEXT,
    station_callsign             TEXT,
    operator_callsigns_raw_value TEXT    NOT NULL DEFAULT '[]', -- JSON [String]
    solar_k_index                REAL,
    solar_flux                   REAL,
    solar_sunspots               INTEGER,
    solar_propagation_rating     TEXT,
    solar_a_index                INTEGER,
    solar_band_conditions        TEXT,
    solar_timestamp              INTEGER,            -- unix seconds, UTC
    solar_conditions             TEXT,
    weather_temperature_f        REAL,
    weather_temperature_c        REAL,
    weather_humidity             INTEGER,
    weather_wind_speed           REAL,
    weather_wind_direction       TEXT,
    weather_description          TEXT,
    weather_timestamp            INTEGER,            -- unix seconds, UTC
    weather                      TEXT,
    cloud_dirty_flag             INTEGER NOT NULL DEFAULT 0,
    contest_id                   TEXT,
    contest_category             TEXT,
    contest_overlay_category     TEXT,
    contest_power                TEXT,
    contest_bands                TEXT,
    contest_operator             TEXT,
    activation_latitude          REAL,
    activation_longitude         REAL,
    activation_distance_miles    REAL,
    activation_elevation_gain_feet REAL,
    ruck_weight_pounds           REAL,
    qrp_activation               INTEGER NOT NULL DEFAULT 0,
    with_pets                    INTEGER NOT NULL DEFAULT 0,
    with_kids                    INTEGER NOT NULL DEFAULT 0,
    winlink_sent                 INTEGER NOT NULL DEFAULT 0,
    aprs_sent                    INTEGER NOT NULL DEFAULT 0,
    varac_sent                   INTEGER NOT NULL DEFAULT 0,
    adaptive_sport               INTEGER NOT NULL DEFAULT 0,
    track_points_data            BLOB,
    tota_category_raw_value      TEXT,
    personal_effort_factor       INTEGER,
    first_activation_of_tile_ever INTEGER NOT NULL DEFAULT 0,
    winter_activation_override   INTEGER,            -- 0/1/NULL
    tiles_activated_data         BLOB,
    tota_t3_candidates_data      BLOB,
    tota_t3_snapshot_at          INTEGER,            -- unix seconds, UTC
    tota_official_points         REAL
);

CREATE INDEX IF NOT EXISTS idx_ls_my_callsign    ON logging_session(my_callsign);
CREATE INDEX IF NOT EXISTS idx_ls_started_at     ON logging_session(started_at);
CREATE INDEX IF NOT EXISTS idx_ls_park_reference ON logging_session(park_reference);
CREATE INDEX IF NOT EXISTS idx_ls_cloud_dirty    ON logging_session(cloud_dirty_flag);
"#;

/// Bounded query parameters for `fetch_logging_sessions`.
#[derive(Debug, Clone, Default)]
pub struct LoggingSessionFilter {
    pub my_callsign: Option<String>,
    /// Only sessions whose `started_at` is at or after this unix-seconds timestamp.
    pub since: Option<i64>,
    /// When `true`, only sessions where `cloud_dirty_flag = 1`.
    pub dirty_only: Option<bool>,
}

impl Store {
    /// Insert or replace a `LoggingSession` row.
    pub fn upsert_logging_session(&self, s: &LoggingSession) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO logging_session (
                id, my_callsign, started_at, ended_at, frequency, mode,
                activation_type_raw_value, programs_raw_value, status_raw_value,
                park_reference, sota_reference, mission_reference, wwff_reference,
                my_grid, power, my_rig, notes, qso_comment, custom_title, qso_count,
                spot_comments_data, is_rove, rove_stops_data, my_antenna, my_key,
                my_mic, extra_equipment, attendees, photo_filenames, radio_item_id,
                station_callsign, operator_callsigns_raw_value,
                solar_k_index, solar_flux, solar_sunspots, solar_propagation_rating,
                solar_a_index, solar_band_conditions, solar_timestamp, solar_conditions,
                weather_temperature_f, weather_temperature_c, weather_humidity,
                weather_wind_speed, weather_wind_direction, weather_description,
                weather_timestamp, weather, cloud_dirty_flag,
                contest_id, contest_category, contest_overlay_category, contest_power,
                contest_bands, contest_operator,
                activation_latitude, activation_longitude, activation_distance_miles,
                activation_elevation_gain_feet, ruck_weight_pounds,
                qrp_activation, with_pets, with_kids, winlink_sent, aprs_sent,
                varac_sent, adaptive_sport, track_points_data, tota_category_raw_value,
                personal_effort_factor, first_activation_of_tile_ever,
                winter_activation_override, tiles_activated_data,
                tota_t3_candidates_data, tota_t3_snapshot_at, tota_official_points
            ) VALUES (
                ?1,  ?2,  ?3,  ?4,  ?5,  ?6,  ?7,  ?8,  ?9,  ?10,
                ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20,
                ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30,
                ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40,
                ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50,
                ?51, ?52, ?53, ?54, ?55, ?56, ?57, ?58, ?59, ?60,
                ?61, ?62, ?63, ?64, ?65, ?66, ?67, ?68, ?69, ?70,
                ?71, ?72, ?73, ?74, ?75, ?76
            )
            ON CONFLICT(id) DO UPDATE SET
                my_callsign                  = excluded.my_callsign,
                started_at                   = excluded.started_at,
                ended_at                     = excluded.ended_at,
                frequency                    = excluded.frequency,
                mode                         = excluded.mode,
                activation_type_raw_value    = excluded.activation_type_raw_value,
                programs_raw_value           = excluded.programs_raw_value,
                status_raw_value             = excluded.status_raw_value,
                park_reference               = excluded.park_reference,
                sota_reference               = excluded.sota_reference,
                mission_reference            = excluded.mission_reference,
                wwff_reference               = excluded.wwff_reference,
                my_grid                      = excluded.my_grid,
                power                        = excluded.power,
                my_rig                       = excluded.my_rig,
                notes                        = excluded.notes,
                qso_comment                  = excluded.qso_comment,
                custom_title                 = excluded.custom_title,
                qso_count                    = excluded.qso_count,
                spot_comments_data           = excluded.spot_comments_data,
                is_rove                      = excluded.is_rove,
                rove_stops_data              = excluded.rove_stops_data,
                my_antenna                   = excluded.my_antenna,
                my_key                       = excluded.my_key,
                my_mic                       = excluded.my_mic,
                extra_equipment              = excluded.extra_equipment,
                attendees                    = excluded.attendees,
                photo_filenames              = excluded.photo_filenames,
                radio_item_id                = excluded.radio_item_id,
                station_callsign             = excluded.station_callsign,
                operator_callsigns_raw_value = excluded.operator_callsigns_raw_value,
                solar_k_index                = excluded.solar_k_index,
                solar_flux                   = excluded.solar_flux,
                solar_sunspots               = excluded.solar_sunspots,
                solar_propagation_rating     = excluded.solar_propagation_rating,
                solar_a_index                = excluded.solar_a_index,
                solar_band_conditions        = excluded.solar_band_conditions,
                solar_timestamp              = excluded.solar_timestamp,
                solar_conditions             = excluded.solar_conditions,
                weather_temperature_f        = excluded.weather_temperature_f,
                weather_temperature_c        = excluded.weather_temperature_c,
                weather_humidity             = excluded.weather_humidity,
                weather_wind_speed           = excluded.weather_wind_speed,
                weather_wind_direction       = excluded.weather_wind_direction,
                weather_description          = excluded.weather_description,
                weather_timestamp            = excluded.weather_timestamp,
                weather                      = excluded.weather,
                cloud_dirty_flag             = excluded.cloud_dirty_flag,
                contest_id                   = excluded.contest_id,
                contest_category             = excluded.contest_category,
                contest_overlay_category     = excluded.contest_overlay_category,
                contest_power                = excluded.contest_power,
                contest_bands                = excluded.contest_bands,
                contest_operator             = excluded.contest_operator,
                activation_latitude          = excluded.activation_latitude,
                activation_longitude         = excluded.activation_longitude,
                activation_distance_miles    = excluded.activation_distance_miles,
                activation_elevation_gain_feet = excluded.activation_elevation_gain_feet,
                ruck_weight_pounds           = excluded.ruck_weight_pounds,
                qrp_activation               = excluded.qrp_activation,
                with_pets                    = excluded.with_pets,
                with_kids                    = excluded.with_kids,
                winlink_sent                 = excluded.winlink_sent,
                aprs_sent                    = excluded.aprs_sent,
                varac_sent                   = excluded.varac_sent,
                adaptive_sport               = excluded.adaptive_sport,
                track_points_data            = excluded.track_points_data,
                tota_category_raw_value      = excluded.tota_category_raw_value,
                personal_effort_factor       = excluded.personal_effort_factor,
                first_activation_of_tile_ever = excluded.first_activation_of_tile_ever,
                winter_activation_override   = excluded.winter_activation_override,
                tiles_activated_data         = excluded.tiles_activated_data,
                tota_t3_candidates_data      = excluded.tota_t3_candidates_data,
                tota_t3_snapshot_at          = excluded.tota_t3_snapshot_at,
                tota_official_points         = excluded.tota_official_points
            "#,
            params![
                /* ?1  */ s.id,
                /* ?2  */ s.my_callsign,
                /* ?3  */ s.started_at,
                /* ?4  */ s.ended_at,
                /* ?5  */ s.frequency,
                /* ?6  */ s.mode,
                /* ?7  */ s.activation_type_raw_value,
                /* ?8  */ s.programs_raw_value,
                /* ?9  */ s.status_raw_value,
                /* ?10 */ s.park_reference,
                /* ?11 */ s.sota_reference,
                /* ?12 */ s.mission_reference,
                /* ?13 */ s.wwff_reference,
                /* ?14 */ s.my_grid,
                /* ?15 */ s.power,
                /* ?16 */ s.my_rig,
                /* ?17 */ s.notes,
                /* ?18 */ s.qso_comment,
                /* ?19 */ s.custom_title,
                /* ?20 */ s.qso_count,
                /* ?21 */ s.spot_comments_data,
                /* ?22 */ s.is_rove as i64,
                /* ?23 */ s.rove_stops_data,
                /* ?24 */ s.my_antenna,
                /* ?25 */ s.my_key,
                /* ?26 */ s.my_mic,
                /* ?27 */ s.extra_equipment,
                /* ?28 */ s.attendees,
                /* ?29 */ s.photo_filenames,
                /* ?30 */ s.radio_item_id,
                /* ?31 */ s.station_callsign,
                /* ?32 */ s.operator_callsigns_raw_value,
                /* ?33 */ s.solar_k_index,
                /* ?34 */ s.solar_flux,
                /* ?35 */ s.solar_sunspots,
                /* ?36 */ s.solar_propagation_rating,
                /* ?37 */ s.solar_a_index,
                /* ?38 */ s.solar_band_conditions,
                /* ?39 */ s.solar_timestamp,
                /* ?40 */ s.solar_conditions,
                /* ?41 */ s.weather_temperature_f,
                /* ?42 */ s.weather_temperature_c,
                /* ?43 */ s.weather_humidity,
                /* ?44 */ s.weather_wind_speed,
                /* ?45 */ s.weather_wind_direction,
                /* ?46 */ s.weather_description,
                /* ?47 */ s.weather_timestamp,
                /* ?48 */ s.weather,
                /* ?49 */ s.cloud_dirty_flag as i64,
                /* ?50 */ s.contest_id,
                /* ?51 */ s.contest_category,
                /* ?52 */ s.contest_overlay_category,
                /* ?53 */ s.contest_power,
                /* ?54 */ s.contest_bands,
                /* ?55 */ s.contest_operator,
                /* ?56 */ s.activation_latitude,
                /* ?57 */ s.activation_longitude,
                /* ?58 */ s.activation_distance_miles,
                /* ?59 */ s.activation_elevation_gain_feet,
                /* ?60 */ s.ruck_weight_pounds,
                /* ?61 */ s.qrp_activation as i64,
                /* ?62 */ s.with_pets as i64,
                /* ?63 */ s.with_kids as i64,
                /* ?64 */ s.winlink_sent as i64,
                /* ?65 */ s.aprs_sent as i64,
                /* ?66 */ s.varac_sent as i64,
                /* ?67 */ s.adaptive_sport as i64,
                /* ?68 */ s.track_points_data,
                /* ?69 */ s.tota_category_raw_value,
                /* ?70 */ s.personal_effort_factor,
                /* ?71 */ s.first_activation_of_tile_ever as i64,
                /* ?72 */ s.winter_activation_override,
                /* ?73 */ s.tiles_activated_data,
                /* ?74 */ s.tota_t3_candidates_data,
                /* ?75 */ s.tota_t3_snapshot_at,
                /* ?76 */ s.tota_official_points,
            ],
        )?;
        Ok(())
    }

    /// Per-park activation counts over the most recent `history_limit` sessions
    /// that have a park reference (`pastParkActivationCounts`). Multi-park refs
    /// ("US-1,US-2") are split on commas and each part counted; keys are trimmed
    /// and uppercased. Ordered newest-first before the limit, matching the Swift
    /// `FetchDescriptor` (`startedAt` desc, `fetchLimit`).
    pub fn park_activation_counts(
        &self,
        history_limit: i64,
    ) -> Result<std::collections::HashMap<String, i64>> {
        let mut stmt = self.conn.prepare(
            "SELECT park_reference FROM logging_session \
             WHERE park_reference IS NOT NULL \
             ORDER BY started_at DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map(params![history_limit], |row| row.get::<_, String>(0))?;
        let mut counts: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
        for refs in rows {
            for part in refs?.split(',') {
                let key = part.trim().to_uppercase();
                if !key.is_empty() {
                    *counts.entry(key).or_insert(0) += 1;
                }
            }
        }
        Ok(counts)
    }

    /// Total session count. Intended to run off the UI thread.
    pub fn logging_session_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM logging_session", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch. `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_logging_sessions(
        &self,
        filter: &LoggingSessionFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<LoggingSession>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT \
                id, my_callsign, started_at, ended_at, frequency, mode, \
                activation_type_raw_value, programs_raw_value, status_raw_value, \
                park_reference, sota_reference, mission_reference, wwff_reference, \
                my_grid, power, my_rig, notes, qso_comment, custom_title, qso_count, \
                spot_comments_data, is_rove, rove_stops_data, my_antenna, my_key, \
                my_mic, extra_equipment, attendees, photo_filenames, radio_item_id, \
                station_callsign, operator_callsigns_raw_value, \
                solar_k_index, solar_flux, solar_sunspots, solar_propagation_rating, \
                solar_a_index, solar_band_conditions, solar_timestamp, solar_conditions, \
                weather_temperature_f, weather_temperature_c, weather_humidity, \
                weather_wind_speed, weather_wind_direction, weather_description, \
                weather_timestamp, weather, cloud_dirty_flag, \
                contest_id, contest_category, contest_overlay_category, contest_power, \
                contest_bands, contest_operator, \
                activation_latitude, activation_longitude, activation_distance_miles, \
                activation_elevation_gain_feet, ruck_weight_pounds, \
                qrp_activation, with_pets, with_kids, winlink_sent, aprs_sent, \
                varac_sent, adaptive_sport, track_points_data, tota_category_raw_value, \
                personal_effort_factor, first_activation_of_tile_ever, \
                winter_activation_override, tiles_activated_data, \
                tota_t3_candidates_data, tota_t3_snapshot_at, tota_official_points \
            FROM logging_session WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(callsign) = &filter.my_callsign {
            sql.push_str(" AND my_callsign = ?");
            args.push(Box::new(callsign.clone()));
        }
        if let Some(since) = filter.since {
            sql.push_str(" AND started_at >= ?");
            args.push(Box::new(since));
        }
        if let Some(true) = filter.dirty_only {
            sql.push_str(" AND cloud_dirty_flag = 1");
        }
        sql.push_str(" ORDER BY started_at DESC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_logging_session)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Sessions in a given lifecycle status (`active`/`paused`/`completed`),
    /// newest first. Backs the "pause any other active session" rule when
    /// resuming a session (`fetchActiveSessions` is the paused+active variant).
    pub fn fetch_logging_sessions_by_status(
        &self,
        status: &str,
        limit: i64,
    ) -> Result<Vec<LoggingSession>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let filter = LoggingSessionFilter::default();
        // Reuse the full SELECT, then filter by status in SQL via a wrapping CTE
        // would over-complicate; status is low-cardinality, so fetch + filter the
        // bounded page in Rust keeps one column list.
        let rows = self.fetch_logging_sessions(&filter, limit, 0)?;
        Ok(rows.into_iter().filter(|s| s.status_raw_value == status).collect())
    }

    /// The single in-progress session (`status = active`, not yet ended), newest
    /// first. Rust is canonical for "which session is active" — both platforms
    /// read this instead of holding their own active-session pointer (iOS
    /// previously kept it in `LoggingSessionManager.activeSession` + a UserDefaults
    /// UUID). The single-active invariant is enforced by the resume/create
    /// "pause any other active session" sweep, so `.find` on the newest-first list
    /// is the current session. `None` when idle.
    pub fn fetch_current_session(&self) -> Result<Option<LoggingSession>> {
        let active = self.fetch_logging_sessions_by_status("active", MAX_FETCH_LIMIT)?;
        Ok(active.into_iter().find(|s| s.ended_at.is_none()))
    }

    /// Reassign every QSO linked to `from_session` over to `to_session`. Returns
    /// the number of rows moved. The QSO→session link is the merge primitive
    /// (`reassignQSOs`).
    pub fn reassign_qsos_to_session(&self, from_session: &str, to_session: &str) -> Result<i64> {
        let n = self.conn.execute(
            "UPDATE qso SET logging_session_id = ?1, dirty = 1 WHERE logging_session_id = ?2",
            params![to_session, from_session],
        )?;
        Ok(n as i64)
    }

    /// Reassign session spots from one session to another (`reassignSessionData`).
    pub fn reassign_session_spots_to_session(
        &self,
        from_session: &str,
        to_session: &str,
    ) -> Result<i64> {
        let n = self.conn.execute(
            "UPDATE session_spot SET logging_session_id = ?1 WHERE logging_session_id = ?2",
            params![to_session, from_session],
        )?;
        Ok(n as i64)
    }

    /// Reassign WebSDR recordings from one session to another (`reassignSessionData`).
    pub fn reassign_websdr_recordings_to_session(
        &self,
        from_session: &str,
        to_session: &str,
    ) -> Result<i64> {
        let n = self.conn.execute(
            "UPDATE websdr_recording SET logging_session_id = ?1 WHERE logging_session_id = ?2",
            params![to_session, from_session],
        )?;
        Ok(n as i64)
    }

    /// Soft-delete (hide) every QSO in a session and clear any pending upload
    /// markers on them. Mirrors `deleteSession`'s `hideQSOs(inSession:)` +
    /// `hideQSO`'s "drop needs-upload presences" rule. Returns rows hidden.
    pub fn hide_qsos_in_session(&self, session_id: &str) -> Result<i64> {
        self.conn.execute(
            "UPDATE service_presence SET needs_upload = 0, cloud_dirty_flag = 1 \
             WHERE needs_upload = 1 AND qso_id IN \
             (SELECT id FROM qso WHERE logging_session_id = ?1)",
            params![session_id],
        )?;
        let n = self.conn.execute(
            "UPDATE qso SET is_hidden = 1, dirty = 1 WHERE logging_session_id = ?1 AND is_hidden = 0",
            params![session_id],
        )?;
        Ok(n as i64)
    }

    /// Fetch a single session by primary key. Returns `None` if not found.
    /// Delete a `logging_session` row by id. Idempotent — a missing id succeeds.
    pub fn delete_logging_session(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM logging_session WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn fetch_logging_session(&self, id: &str) -> Result<Option<LoggingSession>> {
        let mut stmt = self.conn.prepare(
            "SELECT \
                id, my_callsign, started_at, ended_at, frequency, mode, \
                activation_type_raw_value, programs_raw_value, status_raw_value, \
                park_reference, sota_reference, mission_reference, wwff_reference, \
                my_grid, power, my_rig, notes, qso_comment, custom_title, qso_count, \
                spot_comments_data, is_rove, rove_stops_data, my_antenna, my_key, \
                my_mic, extra_equipment, attendees, photo_filenames, radio_item_id, \
                station_callsign, operator_callsigns_raw_value, \
                solar_k_index, solar_flux, solar_sunspots, solar_propagation_rating, \
                solar_a_index, solar_band_conditions, solar_timestamp, solar_conditions, \
                weather_temperature_f, weather_temperature_c, weather_humidity, \
                weather_wind_speed, weather_wind_direction, weather_description, \
                weather_timestamp, weather, cloud_dirty_flag, \
                contest_id, contest_category, contest_overlay_category, contest_power, \
                contest_bands, contest_operator, \
                activation_latitude, activation_longitude, activation_distance_miles, \
                activation_elevation_gain_feet, ruck_weight_pounds, \
                qrp_activation, with_pets, with_kids, winlink_sent, aprs_sent, \
                varac_sent, adaptive_sport, track_points_data, tota_category_raw_value, \
                personal_effort_factor, first_activation_of_tile_ever, \
                winter_activation_override, tiles_activated_data, \
                tota_t3_candidates_data, tota_t3_snapshot_at, tota_official_points \
            FROM logging_session WHERE id = ?1",
        )?;
        Ok(stmt.query_row(params![id], Self::row_to_logging_session).optional()?)
    }

    #[allow(clippy::too_many_lines)]
    fn row_to_logging_session(row: &rusqlite::Row<'_>) -> rusqlite::Result<LoggingSession> {
        Ok(LoggingSession {
            id:                            row.get(0)?,
            my_callsign:                   row.get(1)?,
            started_at:                    row.get(2)?,
            ended_at:                      row.get(3)?,
            frequency:                     row.get(4)?,
            mode:                          row.get(5)?,
            activation_type_raw_value:     row.get(6)?,
            programs_raw_value:            row.get(7)?,
            status_raw_value:              row.get(8)?,
            park_reference:                row.get(9)?,
            sota_reference:                row.get(10)?,
            mission_reference:             row.get(11)?,
            wwff_reference:                row.get(12)?,
            my_grid:                       row.get(13)?,
            power:                         row.get(14)?,
            my_rig:                        row.get(15)?,
            notes:                         row.get(16)?,
            qso_comment:                   row.get(17)?,
            custom_title:                  row.get(18)?,
            qso_count:                     row.get(19)?,
            spot_comments_data:            row.get(20)?,
            is_rove:                       row.get::<_, i64>(21)? != 0,
            rove_stops_data:               row.get(22)?,
            my_antenna:                    row.get(23)?,
            my_key:                        row.get(24)?,
            my_mic:                        row.get(25)?,
            extra_equipment:               row.get(26)?,
            attendees:                     row.get(27)?,
            photo_filenames:               row.get(28)?,
            radio_item_id:                 row.get(29)?,
            station_callsign:              row.get(30)?,
            operator_callsigns_raw_value:  row.get(31)?,
            solar_k_index:                 row.get(32)?,
            solar_flux:                    row.get(33)?,
            solar_sunspots:                row.get(34)?,
            solar_propagation_rating:      row.get(35)?,
            solar_a_index:                 row.get(36)?,
            solar_band_conditions:         row.get(37)?,
            solar_timestamp:               row.get(38)?,
            solar_conditions:              row.get(39)?,
            weather_temperature_f:         row.get(40)?,
            weather_temperature_c:         row.get(41)?,
            weather_humidity:              row.get(42)?,
            weather_wind_speed:            row.get(43)?,
            weather_wind_direction:        row.get(44)?,
            weather_description:           row.get(45)?,
            weather_timestamp:             row.get(46)?,
            weather:                       row.get(47)?,
            cloud_dirty_flag:              row.get::<_, i64>(48)? != 0,
            contest_id:                    row.get(49)?,
            contest_category:              row.get(50)?,
            contest_overlay_category:      row.get(51)?,
            contest_power:                 row.get(52)?,
            contest_bands:                 row.get(53)?,
            contest_operator:              row.get(54)?,
            activation_latitude:           row.get(55)?,
            activation_longitude:          row.get(56)?,
            activation_distance_miles:     row.get(57)?,
            activation_elevation_gain_feet: row.get(58)?,
            ruck_weight_pounds:            row.get(59)?,
            qrp_activation:               row.get::<_, i64>(60)? != 0,
            with_pets:                     row.get::<_, i64>(61)? != 0,
            with_kids:                     row.get::<_, i64>(62)? != 0,
            winlink_sent:                  row.get::<_, i64>(63)? != 0,
            aprs_sent:                     row.get::<_, i64>(64)? != 0,
            varac_sent:                    row.get::<_, i64>(65)? != 0,
            adaptive_sport:                row.get::<_, i64>(66)? != 0,
            track_points_data:             row.get(67)?,
            tota_category_raw_value:       row.get(68)?,
            personal_effort_factor:        row.get(69)?,
            first_activation_of_tile_ever: row.get::<_, i64>(70)? != 0,
            winter_activation_override:    row.get(71)?,
            tiles_activated_data:          row.get(72)?,
            tota_t3_candidates_data:       row.get(73)?,
            tota_t3_snapshot_at:           row.get(74)?,
            tota_official_points:          row.get(75)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample_session(id: &str, callsign: &str, started_at: i64) -> LoggingSession {
        LoggingSession {
            id: id.to_string(),
            my_callsign: callsign.to_string(),
            started_at,
            ended_at: None,
            frequency: Some(14_025.0),
            mode: "CW".to_string(),
            activation_type_raw_value: "pota".to_string(),
            programs_raw_value: r#"["pota"]"#.to_string(),
            status_raw_value: "active".to_string(),
            park_reference: Some("K-1234".to_string()),
            sota_reference: None,
            mission_reference: None,
            wwff_reference: None,
            my_grid: Some("CM87".to_string()),
            power: Some(100),
            my_rig: Some("IC-7300".to_string()),
            notes: None,
            qso_comment: None,
            custom_title: None,
            qso_count: 0,
            spot_comments_data: None,
            is_rove: false,
            rove_stops_data: None,
            my_antenna: Some("EFHW".to_string()),
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
            activation_latitude: Some(37.8044),
            activation_longitude: Some(-122.2712),
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

    #[test]
    fn delete_removes_row() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_logging_session(&sample_session("sess-del", "W6JY", 1000))
            .unwrap();
        assert_eq!(store.logging_session_count().unwrap(), 1);
        store.delete_logging_session("sess-del").unwrap();
        assert_eq!(store.logging_session_count().unwrap(), 0);
        // Idempotent: deleting a missing id succeeds.
        store.delete_logging_session("nope").unwrap();
    }

    #[test]
    fn upsert_and_fetch_roundtrip() {
        let store = Store::open_in_memory("k").unwrap();

        let mut session = sample_session("sess-1", "W6JY", 1_700_000_000);
        // Set a blob field and verify it survives the round-trip.
        session.track_points_data = Some(vec![1, 2, 3]);
        session.cloud_dirty_flag = true;

        store.upsert_logging_session(&session).unwrap();

        let fetched = store.fetch_logging_session("sess-1").unwrap().expect("session should exist");
        assert_eq!(fetched.id, "sess-1");
        assert_eq!(fetched.my_callsign, "W6JY");
        assert_eq!(fetched.park_reference.as_deref(), Some("K-1234"));
        assert_eq!(fetched.track_points_data, Some(vec![1, 2, 3]));
        assert!(fetched.cloud_dirty_flag);
        assert_eq!(fetched.activation_latitude, Some(37.8044));
    }

    #[test]
    fn count_is_accurate() {
        let store = Store::open_in_memory("k").unwrap();
        assert_eq!(store.logging_session_count().unwrap(), 0);
        store.upsert_logging_session(&sample_session("a", "W6JY", 1000)).unwrap();
        store.upsert_logging_session(&sample_session("b", "W6JY", 2000)).unwrap();
        assert_eq!(store.logging_session_count().unwrap(), 2);
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_logging_session(&sample_session("s1", "W6JY", 1000)).unwrap();

        let mut updated = sample_session("s1", "W6JY", 1000);
        updated.notes = Some("edited".to_string());
        updated.qso_count = 42;
        store.upsert_logging_session(&updated).unwrap();

        assert_eq!(store.logging_session_count().unwrap(), 1);
        let rows = store
            .fetch_logging_sessions(&LoggingSessionFilter::default(), 10, 0)
            .unwrap();
        assert_eq!(rows[0].notes.as_deref(), Some("edited"));
        assert_eq!(rows[0].qso_count, 42);
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_logging_sessions(&LoggingSessionFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn filter_by_dirty() {
        let store = Store::open_in_memory("k").unwrap();
        let mut dirty = sample_session("d", "W6JY", 1000);
        dirty.cloud_dirty_flag = true;
        store.upsert_logging_session(&dirty).unwrap();
        store.upsert_logging_session(&sample_session("c", "W6JY", 2000)).unwrap();

        let only_dirty = store
            .fetch_logging_sessions(
                &LoggingSessionFilter { dirty_only: Some(true), ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert_eq!(only_dirty.len(), 1);
        assert_eq!(only_dirty[0].id, "d");
    }

    #[test]
    fn filter_by_callsign_and_since() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_logging_session(&sample_session("1", "W6JY", 1000)).unwrap();
        store.upsert_logging_session(&sample_session("2", "W6JY", 3000)).unwrap();
        store.upsert_logging_session(&sample_session("3", "N6ABC", 2000)).unwrap();

        let results = store
            .fetch_logging_sessions(
                &LoggingSessionFilter {
                    my_callsign: Some("W6JY".to_string()),
                    since: Some(2000),
                    ..Default::default()
                },
                100,
                0,
            )
            .unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "2");
    }
}
