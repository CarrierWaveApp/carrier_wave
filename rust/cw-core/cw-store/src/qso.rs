//! The QSO entity + its bounded query API.
//!
//! Faithful mirror of `CarrierWaveData`'s `QSO` `@Model` (every persisted field
//! is represented, so the SwiftData→cw-store importer loses nothing). The
//! `@Model` splits location into `myGrid`/`theirGrid` and uses
//! `importedAt`/`modifiedAt` timestamps — mirrored here as `my_grid`/`their_grid`
//! and `imported_at`/`modified_at`. `dirty` is the sync-journal flag, mapped from
//! the `@Model`'s `cloudDirtyFlag`.

use crate::error::{Result, StoreError};
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// A logged contact. Plain value type — the FFI exposes this, not a live row.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Qso {
    pub id: String,
    pub callsign: String,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub freq_khz: Option<f64>,
    /// Unix seconds, UTC (`@Model` `timestamp`).
    pub qso_date: i64,
    pub my_grid: Option<String>,
    pub their_grid: Option<String>,
    pub rst_sent: Option<String>,
    pub rst_rcvd: Option<String>,
    pub my_callsign: Option<String>,
    pub park: Option<String>,
    pub their_park: Option<String>,
    pub notes: Option<String>,
    pub notes_user_authored: bool,
    /// JSON blob of POTA spot comments, stored verbatim.
    pub spot_comments_data: Option<Vec<u8>>,
    pub callsign_change_note: Option<String>,
    pub original_callsign: Option<String>,
    pub import_source_raw_value: String,
    /// Unix seconds (`@Model` `importedAt`).
    pub imported_at: i64,
    /// Unix seconds (`@Model` `modifiedAt`), null until first local edit.
    pub modified_at: Option<i64>,
    pub raw_adif: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub power: Option<i64>,
    pub my_rig: Option<String>,
    pub station_profile_name: Option<String>,
    pub sota_ref: Option<String>,
    pub wwff_ref: Option<String>,
    pub aoa_code: Option<String>,
    pub qrz_log_id: Option<String>,
    pub qrz_confirmed: bool,
    pub lotw_confirmed_date: Option<i64>,
    pub lotw_confirmed: bool,
    pub dxcc: Option<i64>,
    pub their_license_class: Option<String>,
    pub contest_name: Option<String>,
    pub contest_serial_sent: Option<i64>,
    pub contest_serial_received: Option<i64>,
    pub contest_exchange_sent: Option<String>,
    pub contest_exchange_received: Option<String>,
    pub is_hidden: bool,
    pub is_activity_log_qso: bool,
    pub station_callsign: Option<String>,
    pub logging_session_id: Option<String>,
    /// Sync-journal flag (`@Model` `cloudDirtyFlag`).
    pub dirty: bool,
    /// ADIF SAT_NAME — satellite short name (e.g. "AO-91"); set by the
    /// satellite quick-log flow, `None` for terrestrial QSOs.
    pub sat_name: Option<String>,
    /// ADIF PROP_MODE, stored as raw text per repo convention; always "SAT"
    /// when `sat_name` is set from the satellite feature.
    pub prop_mode: Option<String>,
}

/// Bounded query parameters. Mirrors the indexed filters the analyzer favours.
#[derive(Debug, Clone, Default)]
pub struct QsoFilter {
    pub callsign_prefix: Option<String>,
    pub band: Option<String>,
    pub mode: Option<String>,
    /// Only QSOs at/after this unix-seconds timestamp.
    pub since: Option<i64>,
    /// When `true`, restrict to rows with the sync-journal `dirty` flag set —
    /// the outbound sync pass's "records with un-synced local changes" set.
    pub dirty_only: bool,
}

/// Hard cap on a single fetch — enforces the project's "max 1,000 objects
/// loaded at a time" performance rule at the store boundary, not just the UI.
pub const MAX_FETCH_LIMIT: i64 = 1_000;

/// One dupe-status candidate row: `(band, mode, their_park)`.
pub type DupeCandidate = (Option<String>, Option<String>, Option<String>);

/// `CREATE TABLE` + indexes for `qso`. Owned here (next to the struct) like every
/// other entity's `*_DDL`; assembled by `migrations`.
pub(crate) const QSO_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS qso (
    id                        TEXT PRIMARY KEY NOT NULL,
    callsign                  TEXT NOT NULL,
    band                      TEXT,
    mode                      TEXT,
    freq_khz                  REAL,
    qso_date                  INTEGER NOT NULL,   -- unix seconds, UTC
    my_grid                   TEXT,
    their_grid                TEXT,
    rst_sent                  TEXT,
    rst_rcvd                  TEXT,
    my_callsign               TEXT,
    park                      TEXT,
    their_park                TEXT,
    notes                     TEXT,
    notes_user_authored       INTEGER NOT NULL DEFAULT 0,
    spot_comments_data        BLOB,
    callsign_change_note      TEXT,
    original_callsign         TEXT,
    import_source_raw_value   TEXT NOT NULL DEFAULT '',
    imported_at               INTEGER NOT NULL,
    modified_at               INTEGER,
    raw_adif                  TEXT,
    name                      TEXT,
    qth                       TEXT,
    state                     TEXT,
    country                   TEXT,
    power                     INTEGER,
    my_rig                    TEXT,
    station_profile_name      TEXT,
    sota_ref                  TEXT,
    wwff_ref                  TEXT,
    aoa_code                  TEXT,
    qrz_log_id                TEXT,
    qrz_confirmed             INTEGER NOT NULL DEFAULT 0,
    lotw_confirmed_date       INTEGER,
    lotw_confirmed            INTEGER NOT NULL DEFAULT 0,
    dxcc                      INTEGER,
    their_license_class       TEXT,
    contest_name              TEXT,
    contest_serial_sent       INTEGER,
    contest_serial_received   INTEGER,
    contest_exchange_sent     TEXT,
    contest_exchange_received TEXT,
    is_hidden                 INTEGER NOT NULL DEFAULT 0,
    is_activity_log_qso       INTEGER NOT NULL DEFAULT 0,
    station_callsign          TEXT,
    logging_session_id        TEXT,
    dirty                     INTEGER NOT NULL DEFAULT 1, -- sync journal flag
    sat_name                  TEXT,                       -- ADIF SAT_NAME
    prop_mode                 TEXT                        -- ADIF PROP_MODE
);

-- Indexes back the `isIndexed` fields the query analyzer reasons about.
CREATE INDEX IF NOT EXISTS idx_qso_callsign ON qso(callsign);
CREATE INDEX IF NOT EXISTS idx_qso_band     ON qso(band);
CREATE INDEX IF NOT EXISTS idx_qso_mode     ON qso(mode);
CREATE INDEX IF NOT EXISTS idx_qso_date     ON qso(qso_date);
CREATE INDEX IF NOT EXISTS idx_qso_dirty    ON qso(dirty);
"#;

/// The full column list, in struct order, shared by INSERT and SELECT.
const QSO_COLUMNS: &str = "id, callsign, band, mode, freq_khz, qso_date, my_grid, their_grid, \
    rst_sent, rst_rcvd, my_callsign, park, their_park, notes, notes_user_authored, \
    spot_comments_data, callsign_change_note, original_callsign, import_source_raw_value, \
    imported_at, modified_at, raw_adif, name, qth, state, country, power, my_rig, \
    station_profile_name, sota_ref, wwff_ref, aoa_code, qrz_log_id, qrz_confirmed, \
    lotw_confirmed_date, lotw_confirmed, dxcc, their_license_class, contest_name, \
    contest_serial_sent, contest_serial_received, contest_exchange_sent, \
    contest_exchange_received, is_hidden, is_activity_log_qso, station_callsign, \
    logging_session_id, dirty, sat_name, prop_mode";

impl Store {
    /// Insert or replace a QSO.
    pub fn upsert_qso(&self, qso: &Qso) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO qso (id, callsign, band, mode, freq_khz, qso_date, my_grid, their_grid,
                             rst_sent, rst_rcvd, my_callsign, park, their_park, notes,
                             notes_user_authored, spot_comments_data, callsign_change_note,
                             original_callsign, import_source_raw_value, imported_at, modified_at,
                             raw_adif, name, qth, state, country, power, my_rig,
                             station_profile_name, sota_ref, wwff_ref, aoa_code, qrz_log_id,
                             qrz_confirmed, lotw_confirmed_date, lotw_confirmed, dxcc,
                             their_license_class, contest_name, contest_serial_sent,
                             contest_serial_received, contest_exchange_sent,
                             contest_exchange_received, is_hidden, is_activity_log_qso,
                             station_callsign, logging_session_id, dirty, sat_name, prop_mode)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17,
                    ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32,
                    ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48,
                    ?49, ?50)
            ON CONFLICT(id) DO UPDATE SET
                callsign=excluded.callsign, band=excluded.band, mode=excluded.mode,
                freq_khz=excluded.freq_khz, qso_date=excluded.qso_date, my_grid=excluded.my_grid,
                their_grid=excluded.their_grid, rst_sent=excluded.rst_sent,
                rst_rcvd=excluded.rst_rcvd, my_callsign=excluded.my_callsign, park=excluded.park,
                their_park=excluded.their_park, notes=excluded.notes,
                notes_user_authored=excluded.notes_user_authored,
                spot_comments_data=excluded.spot_comments_data,
                callsign_change_note=excluded.callsign_change_note,
                original_callsign=excluded.original_callsign,
                import_source_raw_value=excluded.import_source_raw_value,
                imported_at=excluded.imported_at, modified_at=excluded.modified_at,
                raw_adif=excluded.raw_adif, name=excluded.name, qth=excluded.qth,
                state=excluded.state, country=excluded.country, power=excluded.power,
                my_rig=excluded.my_rig, station_profile_name=excluded.station_profile_name,
                sota_ref=excluded.sota_ref, wwff_ref=excluded.wwff_ref, aoa_code=excluded.aoa_code,
                qrz_log_id=excluded.qrz_log_id, qrz_confirmed=excluded.qrz_confirmed,
                lotw_confirmed_date=excluded.lotw_confirmed_date,
                lotw_confirmed=excluded.lotw_confirmed, dxcc=excluded.dxcc,
                their_license_class=excluded.their_license_class,
                contest_name=excluded.contest_name,
                contest_serial_sent=excluded.contest_serial_sent,
                contest_serial_received=excluded.contest_serial_received,
                contest_exchange_sent=excluded.contest_exchange_sent,
                contest_exchange_received=excluded.contest_exchange_received,
                is_hidden=excluded.is_hidden, is_activity_log_qso=excluded.is_activity_log_qso,
                station_callsign=excluded.station_callsign,
                logging_session_id=excluded.logging_session_id, dirty=excluded.dirty,
                sat_name=excluded.sat_name, prop_mode=excluded.prop_mode
            "#,
            params![
                qso.id, qso.callsign, qso.band, qso.mode, qso.freq_khz, qso.qso_date, qso.my_grid,
                qso.their_grid, qso.rst_sent, qso.rst_rcvd, qso.my_callsign, qso.park,
                qso.their_park, qso.notes, qso.notes_user_authored as i64, qso.spot_comments_data,
                qso.callsign_change_note, qso.original_callsign, qso.import_source_raw_value,
                qso.imported_at, qso.modified_at, qso.raw_adif, qso.name, qso.qth, qso.state,
                qso.country, qso.power, qso.my_rig, qso.station_profile_name, qso.sota_ref,
                qso.wwff_ref, qso.aoa_code, qso.qrz_log_id, qso.qrz_confirmed as i64,
                qso.lotw_confirmed_date, qso.lotw_confirmed as i64, qso.dxcc,
                qso.their_license_class, qso.contest_name, qso.contest_serial_sent,
                qso.contest_serial_received, qso.contest_exchange_sent,
                qso.contest_exchange_received, qso.is_hidden as i64, qso.is_activity_log_qso as i64,
                qso.station_callsign, qso.logging_session_id, qso.dirty as i64, qso.sat_name,
                qso.prop_mode,
            ],
        )?;
        Ok(())
    }

    /// Total QSO count (O(1) on the main thread is the caller's concern; this is
    /// a fast COUNT, intended to run off the UI thread).
    pub fn qso_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM qso", [], |row| row.get(0))?)
    }

    /// Count of QSOs with the sync-journal `dirty` flag set — the outbound sync
    /// backlog. Backs the CloudKit sync panel's dirty-QSO count once QSO authority
    /// moves to the store (the Swift journal otherwise reads it off SwiftData).
    pub fn dirty_qso_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM qso WHERE dirty = 1", [], |row| row.get(0))?)
    }

    /// All-time count of visible, real QSOs with this exact callsign — the
    /// "previously worked" badge. Mirrors iOS `fetchPreviousQSOCount`
    /// (`LoggerView+Data`): exact callsign (uppercased), `is_hidden = 0`, and the
    /// WEATHER/SOLAR/NOTE metadata pseudo-modes excluded. Not day/band/mode
    /// scoped (that is the separate dupe-status check).
    pub fn worked_before_count(&self, callsign: &str) -> Result<i64> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*) FROM qso \
             WHERE callsign = ?1 AND is_hidden = 0 \
             AND (mode IS NULL OR mode NOT IN ('WEATHER', 'SOLAR', 'NOTE'))",
            params![callsign.to_uppercase()],
            |row| row.get(0),
        )?)
    }

    /// QSOs logged through each satellite since `since` (unix seconds),
    /// keyed by upper-cased ADIF `SAT_NAME` — the "you worked it" column of
    /// the community-activity grid. Hidden QSOs and metadata pseudo-modes
    /// are excluded; QSOs without a `sat_name` never appear.
    pub fn satellite_qso_counts_since(&self, since: i64) -> Result<Vec<(String, i64)>> {
        let mut stmt = self.conn.prepare(
            "SELECT UPPER(TRIM(sat_name)) AS sat, COUNT(*) FROM qso \
             WHERE sat_name IS NOT NULL AND TRIM(sat_name) <> '' \
             AND qso_date >= ?1 AND is_hidden = 0 \
             AND (mode IS NULL OR mode NOT IN ('WEATHER', 'SOLAR', 'NOTE')) \
             GROUP BY sat ORDER BY sat",
        )?;
        let rows = stmt.query_map(params![since], |row| Ok((row.get(0)?, row.get(1)?)))?;
        rows.collect::<std::result::Result<Vec<_>, _>>().map_err(Into::into)
    }

    /// Bounded, paginated fetch. `limit` must be ≤ [`MAX_FETCH_LIMIT`]; passing
    /// a larger value is a programmer error and returns `FetchLimitExceeded`
    /// rather than silently loading an unbounded result set.
    pub fn fetch_qsos(&self, filter: &QsoFilter, limit: i64, offset: i64) -> Result<Vec<Qso>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = format!("SELECT {QSO_COLUMNS} FROM qso WHERE 1=1");
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(prefix) = &filter.callsign_prefix {
            sql.push_str(" AND callsign LIKE ?");
            args.push(Box::new(format!("{}%", prefix.to_uppercase())));
        }
        if let Some(band) = &filter.band {
            sql.push_str(" AND band = ?");
            args.push(Box::new(band.clone()));
        }
        if let Some(mode) = &filter.mode {
            sql.push_str(" AND mode = ?");
            args.push(Box::new(mode.clone()));
        }
        if let Some(since) = filter.since {
            sql.push_str(" AND qso_date >= ?");
            args.push(Box::new(since));
        }
        if filter.dirty_only {
            sql.push_str(" AND dirty = 1");
        }
        sql.push_str(" ORDER BY qso_date DESC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_qso)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// `(band, mode, their_park)` for this exact callsign's visible QSOs at/after
    /// `day_start` — the candidate set the **hunter** dupe classifier folds, park-
    /// scoped by the *contacted* station's park (`their_park`). This is the chaser
    /// question "have I worked this activator at that park today?". Bounded by
    /// [`MAX_FETCH_LIMIT`].
    pub fn dupe_candidates(&self, callsign: &str, day_start: i64) -> Result<Vec<DupeCandidate>> {
        self.dupe_candidates_scoped(callsign, day_start, "their_park")
    }

    /// `(band, mode, park)` for this callsign's visible QSOs at/after `day_start`,
    /// carrying the **operator's own** park (`park`) as the scope column — the
    /// **activation** dupe question "have I worked this station at *my* park today?".
    /// The same classifier folds it, so activation and hunter dedup share one code
    /// path; only which park column scopes the match differs (mirrors iOS
    /// `LoggerView+Data.filterMatchingQSOs`, which scopes by `qso.parkReference`).
    /// Bounded by [`MAX_FETCH_LIMIT`].
    pub fn dupe_candidates_for_activation(
        &self,
        callsign: &str,
        day_start: i64,
    ) -> Result<Vec<DupeCandidate>> {
        self.dupe_candidates_scoped(callsign, day_start, "park")
    }

    /// Shared candidate fetch for the dupe classifier: `(band, mode, <park_column>)`
    /// for the callsign's visible QSOs within the day. `park_column` is one of the
    /// two hard-coded park columns (`their_park` for hunter, `park` for activation)
    /// — never caller input, so the interpolation is injection-safe.
    fn dupe_candidates_scoped(
        &self,
        callsign: &str,
        day_start: i64,
        park_column: &str,
    ) -> Result<Vec<DupeCandidate>> {
        let sql = format!(
            "SELECT band, mode, {park_column} FROM qso \
             WHERE callsign = ?1 AND is_hidden = 0 AND qso_date >= ?2 \
             LIMIT ?3",
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(
            params![callsign.to_uppercase(), day_start, MAX_FETCH_LIMIT],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Visible QSOs linked to one logging session / activity log, newest first.
    ///
    /// Mirrors `ActivityLogManager.refreshTodayStats` / `fetchRecentQSOs` (and the
    /// activation equivalents): `logging_session_id = ? AND is_hidden = 0`, with an
    /// optional `qso_date >= since` lower bound (the UTC start-of-day window for
    /// "today" stats; `None` fetches the whole session). Bounded by `limit`.
    pub fn fetch_qsos_for_session(
        &self,
        logging_session_id: &str,
        since: Option<i64>,
        limit: i64,
    ) -> Result<Vec<Qso>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = format!(
            "SELECT {QSO_COLUMNS} FROM qso WHERE logging_session_id = ? AND is_hidden = 0"
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        args.push(Box::new(logging_session_id.to_string()));
        if let Some(since) = since {
            sql.push_str(" AND qso_date >= ?");
            args.push(Box::new(since));
        }
        sql.push_str(" ORDER BY qso_date DESC LIMIT ?");
        args.push(Box::new(limit));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_qso)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Every QSO linked to a session **including hidden ones**, oldest first. The
    /// POTA UTC-midnight split reassigns hidden QSOs too — the Swift
    /// `fetchSessionQSOs` predicate is `loggingSessionId == id` with no
    /// `is_hidden` filter — and groups by day, so ascending `qso_date` keeps the
    /// grouping stable.
    pub fn fetch_all_qsos_for_session(
        &self,
        logging_session_id: &str,
        limit: i64,
    ) -> Result<Vec<Qso>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let sql = format!(
            "SELECT {QSO_COLUMNS} FROM qso WHERE logging_session_id = ? ORDER BY qso_date ASC LIMIT ?"
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params![logging_session_id, limit], Self::row_to_qso)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Visible activity-log (hunter) QSOs at/after `since`, newest first. Unlike
    /// [`fetch_qsos_for_session`] this spans *all* logs — it backs the
    /// worked-before dedup cache (`WorkedBeforeCache.loadToday`:
    /// `is_activity_log_qso = 1 AND is_hidden = 0 AND qso_date >= since`).
    pub fn fetch_activity_log_qsos_since(&self, since: i64, limit: i64) -> Result<Vec<Qso>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let sql = format!(
            "SELECT {QSO_COLUMNS} FROM qso \
             WHERE is_activity_log_qso = 1 AND is_hidden = 0 AND qso_date >= ? \
             ORDER BY qso_date DESC LIMIT ?"
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params![since, limit], Self::row_to_qso)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Visible QSOs belonging to one POTA activation — the `(park, callsign,
    /// UTC day)` grouping the iOS `POTAActivation.groupQSOs`
    /// (`Models/POTAActivation.swift:237-275`) produces, restricted to the
    /// half-open UTC-day window `[day_start, day_end)`. Mirrors the group
    /// predicate: `parkReference == park` (exact, uppercased — multi-park refs
    /// are NOT split), `myCallsign == callsign` (uppercased), non-metadata
    /// mode (`WEATHER`/`SOLAR`/`NOTE` excluded), that same UTC day. `is_hidden`
    /// rows are excluded (the activation list is built from visible QSOs).
    /// Ordered by `qso_date` ASC so the ADIF export is already chronological
    /// (matches Swift's `sorted { $0.timestamp < $1.timestamp }`). Bounded by
    /// [`MAX_FETCH_LIMIT`].
    pub fn fetch_activation_qsos(
        &self,
        park: &str,
        callsign: &str,
        day_start: i64,
        day_end: i64,
    ) -> Result<Vec<Qso>> {
        let sql = format!(
            "SELECT {QSO_COLUMNS} FROM qso \
             WHERE UPPER(park) = ?1 AND UPPER(my_callsign) = ?2 \
             AND qso_date >= ?3 AND qso_date < ?4 AND is_hidden = 0 \
             AND (mode IS NULL OR UPPER(mode) NOT IN ('WEATHER', 'SOLAR', 'NOTE')) \
             ORDER BY qso_date ASC LIMIT ?5"
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(
            params![park.to_uppercase(), callsign.to_uppercase(), day_start, day_end, MAX_FETCH_LIMIT],
            Self::row_to_qso,
        )?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_qso(row: &rusqlite::Row<'_>) -> rusqlite::Result<Qso> {
        Ok(Qso {
            id: row.get(0)?,
            callsign: row.get(1)?,
            band: row.get(2)?,
            mode: row.get(3)?,
            freq_khz: row.get(4)?,
            qso_date: row.get(5)?,
            my_grid: row.get(6)?,
            their_grid: row.get(7)?,
            rst_sent: row.get(8)?,
            rst_rcvd: row.get(9)?,
            my_callsign: row.get(10)?,
            park: row.get(11)?,
            their_park: row.get(12)?,
            notes: row.get(13)?,
            notes_user_authored: row.get::<_, i64>(14)? != 0,
            spot_comments_data: row.get(15)?,
            callsign_change_note: row.get(16)?,
            original_callsign: row.get(17)?,
            import_source_raw_value: row.get(18)?,
            imported_at: row.get(19)?,
            modified_at: row.get(20)?,
            raw_adif: row.get(21)?,
            name: row.get(22)?,
            qth: row.get(23)?,
            state: row.get(24)?,
            country: row.get(25)?,
            power: row.get(26)?,
            my_rig: row.get(27)?,
            station_profile_name: row.get(28)?,
            sota_ref: row.get(29)?,
            wwff_ref: row.get(30)?,
            aoa_code: row.get(31)?,
            qrz_log_id: row.get(32)?,
            qrz_confirmed: row.get::<_, i64>(33)? != 0,
            lotw_confirmed_date: row.get(34)?,
            lotw_confirmed: row.get::<_, i64>(35)? != 0,
            dxcc: row.get(36)?,
            their_license_class: row.get(37)?,
            contest_name: row.get(38)?,
            contest_serial_sent: row.get(39)?,
            contest_serial_received: row.get(40)?,
            contest_exchange_sent: row.get(41)?,
            contest_exchange_received: row.get(42)?,
            is_hidden: row.get::<_, i64>(43)? != 0,
            is_activity_log_qso: row.get::<_, i64>(44)? != 0,
            station_callsign: row.get(45)?,
            logging_session_id: row.get(46)?,
            dirty: row.get::<_, i64>(47)? != 0,
            sat_name: row.get(48)?,
            prop_mode: row.get(49)?,
        })
    }

    /// Fetch a single QSO by id (including hidden rows), or `None` if absent.
    /// The sync journal's inbound merge needs by-id access to the live row —
    /// including soft-deleted (`is_hidden`) ones — so it is intentionally not
    /// filtered like the bounded query paths.
    pub fn fetch_qso(&self, id: &str) -> Result<Option<Qso>> {
        let sql = format!("SELECT {QSO_COLUMNS} FROM qso WHERE id = ?1");
        Ok(self.conn.query_row(&sql, params![id], Self::row_to_qso).optional()?)
    }

    /// Delete a QSO by id. Missing id is a no-op (idempotent).
    pub fn delete_qso(&self, id: &str) -> Result<()> {
        self.conn.execute("DELETE FROM qso WHERE id = ?1", params![id])?;
        Ok(())
    }

    /// Full-DSL query fetch. Applies the Logbook base predicate (`is_hidden = 0`),
    /// date-desc ordering, and the bounded limit, then the compiled WHERE clause.
    pub fn fetch_qsos_query(
        &self,
        query: &cw_domain::query::ParsedQuery,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Qso>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let (where_sql, values) = crate::query::compile_where(query);
        let sql = format!(
            "SELECT {QSO_COLUMNS} FROM qso WHERE is_hidden = 0 AND ({where_sql}) \
             ORDER BY qso_date DESC LIMIT ? OFFSET ?"
        );
        let mut boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        boxed.push(Box::new(limit));
        boxed.push(Box::new(offset));
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), Self::row_to_qso)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Count for a full-DSL query (same WHERE as `fetch_qsos_query`, no limit/offset).
    pub fn count_query(&self, query: &cw_domain::query::ParsedQuery) -> Result<i64> {
        let (where_sql, values) = crate::query::compile_where(query);
        let sql = format!("SELECT COUNT(*) FROM qso WHERE is_hidden = 0 AND ({where_sql})");
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        Ok(self.conn.query_row(&sql, refs.as_slice(), |r| r.get(0))?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample_qso_full(id: &str, callsign: &str, band: Option<&str>, mode: Option<&str>) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: callsign.to_string(),
            band: band.map(|s| s.to_string()),
            mode: mode.map(|s| s.to_string()),
            freq_khz: Some(14_074.0),
            qso_date: 1000,
            my_grid: Some("FN31".to_string()),
            their_grid: Some("EM12".to_string()),
            rst_sent: Some("-10".to_string()),
            rst_rcvd: Some("-12".to_string()),
            my_callsign: Some("W6JY".to_string()),
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: 1000,
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
            logging_session_id: None,
            dirty: true,
            sat_name: None,
            prop_mode: None,
        }
    }

    fn sample_qso(id: &str) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: "W1AW".to_string(),
            band: Some("20m".to_string()),
            mode: Some("FT8".to_string()),
            freq_khz: Some(14_074.0),
            qso_date: 1000,
            my_grid: Some("FN31".to_string()),
            their_grid: Some("EM12".to_string()),
            rst_sent: Some("-10".to_string()),
            rst_rcvd: Some("-12".to_string()),
            my_callsign: Some("W6JY".to_string()),
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: 1000,
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
            logging_session_id: None,
            dirty: true,
            sat_name: None,
            prop_mode: None,
        }
    }

    #[test]
    fn upsert_round_trips_satellite_fields() {
        let store = Store::open_in_memory("k").unwrap();
        let mut qso = sample_qso("11111111-1111-1111-1111-111111111111");
        qso.sat_name = Some("AO-91".to_string());
        qso.prop_mode = Some("SAT".to_string());
        store.upsert_qso(&qso).unwrap();

        let fetched = store.fetch_qso(&qso.id).unwrap().unwrap();
        assert_eq!(fetched.sat_name.as_deref(), Some("AO-91"));
        assert_eq!(fetched.prop_mode.as_deref(), Some("SAT"));

        // Upsert-update clears them like any other column.
        qso.sat_name = None;
        qso.prop_mode = None;
        store.upsert_qso(&qso).unwrap();
        let cleared = store.fetch_qso(&qso.id).unwrap().unwrap();
        assert!(cleared.sat_name.is_none());
        assert!(cleared.prop_mode.is_none());
    }

    /// Regression test for the v16 migration (`qso.sat_name`/`qso.prop_mode`):
    /// simulate a v15 DB by dropping the columns and rewinding `user_version`,
    /// then re-run the migration and confirm the columns are rebuilt and usable.
    #[test]
    fn migration_adds_satellite_columns_when_upgrading_from_v15() {
        let store = Store::open_in_memory("k").unwrap();

        store
            .conn
            .execute_batch(
                "ALTER TABLE qso DROP COLUMN sat_name; ALTER TABLE qso DROP COLUMN prop_mode;",
            )
            .unwrap();
        store.conn.pragma_update(None, "user_version", 15_i64).unwrap();

        crate::migrations::migrate(&store.conn).unwrap();

        let version: i64 =
            store.conn.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
        assert_eq!(version, crate::migrations::SCHEMA_VERSION);

        let mut qso = sample_qso("22222222-2222-2222-2222-222222222222");
        qso.sat_name = Some("SO-50".to_string());
        qso.prop_mode = Some("SAT".to_string());
        store.upsert_qso(&qso).unwrap();
        let fetched = store.fetch_qso(&qso.id).unwrap().unwrap();
        assert_eq!(fetched.sat_name.as_deref(), Some("SO-50"));
        assert_eq!(fetched.prop_mode.as_deref(), Some("SAT"));
    }

    /// Regression test for the guarded-ALTER design: a fresh DB gets the
    /// satellite columns from `QSO_DDL`, so re-running the v16 step (rewound
    /// `user_version`, columns still present) must be a no-op, not a
    /// "duplicate column name" error.
    #[test]
    fn migration_is_idempotent_when_columns_already_exist() {
        let store = Store::open_in_memory("k").unwrap();
        store.conn.pragma_update(None, "user_version", 15_i64).unwrap();

        crate::migrations::migrate(&store.conn).unwrap();

        let version: i64 =
            store.conn.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
        assert_eq!(version, crate::migrations::SCHEMA_VERSION);
    }

    #[test]
    fn delete_qso_removes_row_and_is_idempotent() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&sample_qso("11111111-1111-1111-1111-111111111111")).unwrap();
        assert_eq!(store.qso_count().unwrap(), 1);

        store.delete_qso("11111111-1111-1111-1111-111111111111").unwrap();
        assert_eq!(store.qso_count().unwrap(), 0);

        // Deleting a missing id is a no-op, not an error.
        store.delete_qso("no-such-id").unwrap();
        assert_eq!(store.qso_count().unwrap(), 0);
    }

    #[test]
    fn worked_before_count_excludes_hidden_and_metadata_modes() {
        let store = Store::open_in_memory("k").unwrap();
        let mk = |id: &str, call: &str, mode: Option<&str>, hidden: bool| {
            let mut qso = sample_qso_full(id, call, Some("20m"), mode);
            qso.is_hidden = hidden;
            store.upsert_qso(&qso).unwrap();
        };
        mk("a", "W1AW", Some("CW"), false); // counts
        mk("b", "W1AW", Some("SSB"), false); // counts
        mk("c", "W1AW", Some("NOTE"), false); // metadata — excluded
        mk("d", "W1AW", Some("WEATHER"), false); // metadata — excluded
        mk("e", "W1AW", Some("CW"), true); // hidden — excluded
        mk("f", "K2XX", Some("CW"), false); // other callsign

        assert_eq!(store.worked_before_count("W1AW").unwrap(), 2);
        // Case-insensitive on the lookup side.
        assert_eq!(store.worked_before_count("w1aw").unwrap(), 2);
        assert_eq!(store.worked_before_count("K2XX").unwrap(), 1);
        assert_eq!(store.worked_before_count("NEVER").unwrap(), 0);
    }

    #[test]
    fn satellite_qso_counts_group_by_upper_sat_name_since() {
        let store = Store::open_in_memory("k").unwrap();
        let mk = |id: &str, sat: Option<&str>, date: i64, hidden: bool| {
            let mut qso = sample_qso_full(id, "W1AW", Some("2m"), Some("FM"));
            qso.sat_name = sat.map(str::to_string);
            qso.qso_date = date;
            qso.is_hidden = hidden;
            store.upsert_qso(&qso).unwrap();
        };
        mk("a", Some("SO-50"), 1_000, false); // counts
        mk("b", Some("so-50 "), 1_500, false); // same bird, normalized
        mk("c", Some("AO-91"), 2_000, false); // counts
        mk("d", Some("SO-50"), 500, false); // before `since`
        mk("e", Some("SO-50"), 1_200, true); // hidden
        mk("f", None, 1_200, false); // terrestrial
        mk("g", Some(""), 1_200, false); // blank name

        let counts = store.satellite_qso_counts_since(1_000).unwrap();
        assert_eq!(counts, vec![("AO-91".to_string(), 1), ("SO-50".to_string(), 2)]);
        assert!(store.satellite_qso_counts_since(5_000).unwrap().is_empty());
    }

    #[test]
    fn dupe_candidates_returns_today_band_mode_park_for_callsign() {
        let store = Store::open_in_memory("k").unwrap();
        let day_start = 1_000;
        let mk = |id: &str, call: &str, band: Option<&str>, mode: Option<&str>, date: i64, park: Option<&str>| {
            let mut qso = sample_qso_full(id, call, band, mode);
            qso.qso_date = date;
            qso.their_park = park.map(|s| s.to_string());
            store.upsert_qso(&qso).unwrap();
        };
        mk("a", "N9HO", None, Some("SSB"), 2_000, None); // today, band Unknown→null
        mk("b", "N9HO", Some("20m"), Some("CW"), 1_500, Some("US-1")); // today
        mk("c", "N9HO", Some("40m"), Some("CW"), 500, None); // before day_start — excluded
        mk("d", "K2XX", Some("20m"), Some("CW"), 2_000, None); // other callsign

        let rows = store.dupe_candidates("n9ho", day_start).unwrap();
        assert_eq!(rows.len(), 2, "two N9HO QSOs at/after day_start");
        assert!(rows.contains(&(None, Some("SSB".into()), None)));
        assert!(rows.contains(&(Some("20m".into()), Some("CW".into()), Some("US-1".into()))));
    }

    #[test]
    fn dupe_candidates_for_activation_scopes_by_own_park_not_theirs() {
        let store = Store::open_in_memory("k").unwrap();
        let day_start = 1_000;
        // Each QSO carries the operator's own park (`park`) and, independently, the
        // contacted station's park (`their_park`). Activation dedup must read the
        // former; hunter dedup the latter.
        let mk = |id: &str, band: Option<&str>, mode: Option<&str>, my_park: Option<&str>, their_park: Option<&str>| {
            let mut qso = sample_qso_full(id, "N9HO", band, mode);
            qso.qso_date = 1_500;
            qso.park = my_park.map(|s| s.to_string());
            qso.their_park = their_park.map(|s| s.to_string());
            store.upsert_qso(&qso).unwrap();
        };
        mk("a", Some("20m"), Some("CW"), Some("US-1"), Some("US-9")); // my park US-1
        mk("b", Some("40m"), Some("CW"), Some("US-2"), Some("US-1")); // my park US-2

        // Activation variant surfaces the operator's own park column.
        let activation = store.dupe_candidates_for_activation("n9ho", day_start).unwrap();
        assert!(activation.contains(&(Some("20m".into()), Some("CW".into()), Some("US-1".into()))));
        assert!(activation.contains(&(Some("40m".into()), Some("CW".into()), Some("US-2".into()))));

        // Hunter variant surfaces the contacted station's park column instead.
        let hunter = store.dupe_candidates("n9ho", day_start).unwrap();
        assert!(hunter.contains(&(Some("20m".into()), Some("CW".into()), Some("US-9".into()))));
        assert!(hunter.contains(&(Some("40m".into()), Some("CW".into()), Some("US-1".into()))));
    }

    #[test]
    fn fetch_qsos_for_session_filters_window_hidden_and_orders_desc() {
        let store = Store::open_in_memory("k").unwrap();
        let mk = |id: &str, session: Option<&str>, date: i64, hidden: bool| {
            let mut qso = sample_qso_full(id, "W1AW", Some("20m"), Some("CW"));
            qso.logging_session_id = session.map(|s| s.to_string());
            qso.qso_date = date;
            qso.is_hidden = hidden;
            store.upsert_qso(&qso).unwrap();
        };
        mk("a", Some("log-1"), 100, false); // in window
        mk("b", Some("log-1"), 300, false); // in window, newest
        mk("c", Some("log-1"), 50, false); // before window
        mk("d", Some("log-1"), 400, true); // hidden — excluded
        mk("e", Some("log-2"), 500, false); // other session — excluded

        // Whole session (no `since`): newest first, hidden excluded.
        let all = store.fetch_qsos_for_session("log-1", None, 500).unwrap();
        assert_eq!(all.iter().map(|q| q.id.clone()).collect::<Vec<_>>(), vec!["b", "a", "c"]);

        // Windowed to qso_date >= 100 (drops "c").
        let today = store.fetch_qsos_for_session("log-1", Some(100), 500).unwrap();
        assert_eq!(today.iter().map(|q| q.id.clone()).collect::<Vec<_>>(), vec!["b", "a"]);

        // Limit is honored.
        let limited = store.fetch_qsos_for_session("log-1", None, 1).unwrap();
        assert_eq!(limited.iter().map(|q| q.id.clone()).collect::<Vec<_>>(), vec!["b"]);
    }

    #[test]
    fn fetch_qsos_for_session_rejects_oversized_limit() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store.fetch_qsos_for_session("log-1", None, MAX_FETCH_LIMIT + 1).unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn query_filters_and_counts_with_full_dsl() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&sample_qso_full("a", "W1AW", Some("20m"), Some("FT8"))).unwrap();
        store.upsert_qso(&sample_qso_full("b", "K2XX", Some("40m"), Some("CW"))).unwrap();
        store.upsert_qso(&sample_qso_full("c", "W3YY", Some("20m"), Some("CW"))).unwrap();

        let q = cw_domain::query::parse("band:20m mode:cw").unwrap();
        let rows = store.fetch_qsos_query(&q, 100, 0).unwrap();
        assert_eq!(rows.iter().map(|r| r.id.clone()).collect::<Vec<_>>(), vec!["c"]);
        assert_eq!(store.count_query(&q).unwrap(), 1);
    }

    #[test]
    fn query_excludes_hidden_and_orders_desc() {
        let store = Store::open_in_memory("k").unwrap();
        let mut hidden = sample_qso_full("h", "W1AW", Some("20m"), Some("CW"));
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();
        let mut newer = sample_qso_full("n", "W1AW", Some("20m"), Some("CW"));
        newer.qso_date = 2_000;
        let mut older = sample_qso_full("o", "W1AW", Some("20m"), Some("CW"));
        older.qso_date = 1_000;
        store.upsert_qso(&newer).unwrap();
        store.upsert_qso(&older).unwrap();

        let q = cw_domain::query::parse("call:w1aw").unwrap();
        let rows = store.fetch_qsos_query(&q, 100, 0).unwrap();
        assert_eq!(rows.iter().map(|r| r.id.clone()).collect::<Vec<_>>(), vec!["n", "o"]);
    }

    #[test]
    fn query_empty_returns_all_non_hidden() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&sample_qso_full("a", "W1AW", Some("20m"), Some("FT8"))).unwrap();
        let mut hidden = sample_qso_full("h", "K2XX", Some("40m"), Some("CW"));
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();

        let q = cw_domain::query::parse("").unwrap();
        let rows = store.fetch_qsos_query(&q, 100, 0).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "a");
        assert_eq!(store.count_query(&q).unwrap(), 1);
    }

    #[test]
    fn dirty_qso_count_counts_only_dirty() {
        let store = Store::open_in_memory("k").unwrap();
        let mut clean = sample_qso_full("c", "W1AW", Some("20m"), Some("CW"));
        clean.dirty = false;
        store.upsert_qso(&clean).unwrap();
        store.upsert_qso(&sample_qso_full("d", "K2XX", Some("40m"), Some("CW"))).unwrap(); // dirty
        assert_eq!(store.dirty_qso_count().unwrap(), 1);
    }

    #[test]
    fn fetch_qso_returns_row_including_hidden() {
        let store = Store::open_in_memory("k").unwrap();
        let mut hidden = sample_qso_full("h", "W1AW", Some("20m"), Some("CW"));
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();

        let fetched = store.fetch_qso("h").unwrap().expect("hidden row is fetchable by id");
        assert_eq!(fetched.id, "h");
        assert!(fetched.is_hidden);
        assert!(store.fetch_qso("missing").unwrap().is_none());
    }

    #[test]
    fn fetch_qsos_dirty_only_restricts_to_dirty_rows() {
        let store = Store::open_in_memory("k").unwrap();
        let mut clean = sample_qso_full("clean", "W1AW", Some("20m"), Some("CW"));
        clean.dirty = false;
        let dirty = sample_qso_full("dirty", "K2XX", Some("40m"), Some("CW")); // dirty = true
        store.upsert_qso(&clean).unwrap();
        store.upsert_qso(&dirty).unwrap();

        // No filter → both rows.
        assert_eq!(store.fetch_qsos(&QsoFilter::default(), 100, 0).unwrap().len(), 2);

        // dirty_only → just the dirty row.
        let filter = QsoFilter { dirty_only: true, ..Default::default() };
        let rows = store.fetch_qsos(&filter, 100, 0).unwrap();
        assert_eq!(rows.iter().map(|q| q.id.clone()).collect::<Vec<_>>(), vec!["dirty"]);
    }

    /// Regression test for the v15 migration (`idx_qso_park_upper`): the fresh-DB path is
    /// exercised by `open_in_memory`, but the v14→v15 *upgrade* path — an existing
    /// store that predates the index — was untested. Simulate a v14 DB by dropping
    /// the index and rewinding `user_version`, then re-run the migration and confirm
    /// the index is rebuilt. Modeled on
    /// `gis_cache::tests::migration_recreates_table_when_upgrading_from_v13`.
    #[test]
    fn migration_recreates_index_when_upgrading_from_v14() {
        let store = Store::open_in_memory("k").unwrap();

        // Roll back to a pre-v15 DB: drop the index this migration adds and rewind
        // user_version to 14, as if the store had never seen v15.
        store.conn.execute_batch("DROP INDEX idx_qso_park_upper;").unwrap();
        store.conn.pragma_update(None, "user_version", 14_i64).unwrap();

        // Re-run the migration path the store uses on open.
        crate::migrations::migrate(&store.conn).unwrap();

        let version: i64 =
            store.conn.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
        assert_eq!(version, crate::migrations::SCHEMA_VERSION);

        // The index must be present again.
        let index_exists: i64 = store
            .conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_qso_park_upper'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(index_exists, 1, "idx_qso_park_upper must be rebuilt on upgrade");
    }
}
