//! In-memory scope SQLite database for the spot engine. Port of the
//! GRDB-backed `QueryStore.swift` + `ScopeSchema.swift` + `Migrations.swift`
//! + `QuerySQLFunctions.swift` stack.
//!
//! One plain (unencrypted) in-memory connection; a second in-memory database
//! is `ATTACH`ed as `scope` so every existing `.cwquery` written against
//! `scope.spots` / `scope.spot_observations` / `scope.spotters` runs
//! unmodified. Main-schema tables (`qsos`, `dxcc`, `dxcc_status`,
//! `polo_notes`, `operator_profiles`, `meta`) mirror the Sweep workbench
//! schema so JOIN-style starter queries work too.

use std::sync::{Arc, Mutex, RwLock};

use cw_domain::maidenhead;
use cw_domain::spots::observations::{SpotObservationRow, SpotterRow};
use rusqlite::functions::FunctionFlags;
use rusqlite::types::ValueRef;
use rusqlite::{Connection, InterruptHandle};

/// A query error with the editor-facing position info (1-based line/column
/// derived from SQLite's byte-level error offset, when available).
#[derive(Debug, Clone, PartialEq)]
pub struct ScopeQueryError {
    pub message: String,
    pub line: Option<u32>,
    pub column: Option<u32>,
}

impl ScopeQueryError {
    fn plain(message: impl Into<String>) -> ScopeQueryError {
        ScopeQueryError { message: message.into(), line: None, column: None }
    }

    fn from_rusqlite(err: rusqlite::Error, sql: &str) -> ScopeQueryError {
        if let rusqlite::Error::SqlInputError { msg, offset, .. } = &err {
            let (line, column) = line_column(sql, *offset as usize);
            return ScopeQueryError {
                message: msg.clone(),
                line: Some(line),
                column: Some(column),
            };
        }
        ScopeQueryError::plain(err.to_string())
    }
}

/// Convert a byte offset in `sql` to a 1-based (line, column) pair — the
/// same prefix-newline count the Swift `QueryEditorView` derives from
/// SQLite's `errorOffset`.
fn line_column(sql: &str, offset: usize) -> (u32, u32) {
    let clamped = offset.min(sql.len());
    let prefix = &sql.as_bytes()[..clamped];
    let line = prefix.iter().filter(|byte| **byte == b'\n').count() as u32 + 1;
    let column = match prefix.iter().rposition(|byte| *byte == b'\n') {
        Some(pos) => (clamped - pos) as u32,
        None => clamped as u32 + 1,
    };
    (line, column)
}

/// Result set from `run_query` — values rendered as display strings
/// (NULL → `None`), which is what both query-runner UIs consume.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct QueryResultSet {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<Option<String>>>,
    /// True when the row cap cut the result short.
    pub truncated: bool,
}

/// A row of the mirrored `qsos` table (Sweep's `QSORow`).
#[derive(Debug, Clone, PartialEq)]
pub struct ScopeQsoRow {
    pub id: String,
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub frequency: Option<f64>,
    /// Unix epoch seconds.
    pub timestamp: f64,
    pub my_callsign: String,
    pub their_grid: Option<String>,
    pub my_grid: Option<String>,
    pub park_ref: Option<String>,
    pub their_park_ref: Option<String>,
    pub dxcc: Option<i64>,
    pub modified_at: Option<f64>,
    pub is_hidden: bool,
    pub is_activity_log: bool,
}

/// A row of the mirrored `dxcc` table (Sweep's `DXCCRow`).
#[derive(Debug, Clone, PartialEq)]
pub struct ScopeDxccRow {
    pub entity: String,
    pub prefix: Option<String>,
    pub continent: Option<String>,
    pub cq_zone: Option<i64>,
    pub itu_zone: Option<i64>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

/// A row of the mirrored `polo_notes` table.
#[derive(Debug, Clone, PartialEq)]
pub struct ScopePoloNoteRow {
    pub callsign: String,
    pub tag: Option<String>,
    pub body: Option<String>,
}

/// A matched-need projection row (`scope.spot_needs`) — rewritten in full
/// on every publish so profile SQL can reference "needed" state.
#[derive(Debug, Clone, PartialEq)]
pub struct ScopeSpotNeedRow {
    pub spot_id: String,
    pub category: String,
    pub label: String,
    pub priority: i64,
}

/// A club-roster row (`scope.club_members`), host-seeded. SKCC ships a
/// full roster; LICW/CWOps arrive opportunistically from enrichment.
#[derive(Debug, Clone, PartialEq)]
pub struct ScopeClubMemberRow {
    pub callsign: String,
    pub club: String,
}

/// The in-memory scope database. `Connection` is `!Sync`, so it lives
/// behind a `Mutex`; the `InterruptHandle` is separately shareable so a
/// running query can be broken from another thread.
pub struct ScopeDb {
    conn: Mutex<Connection>,
    interrupt: InterruptHandle,
    user_grid: Arc<RwLock<Option<String>>>,
}

impl ScopeDb {
    pub fn new_in_memory() -> Result<ScopeDb, ScopeQueryError> {
        let conn = Connection::open_in_memory()
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        conn.execute_batch("ATTACH DATABASE ':memory:' AS scope;")
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        apply_schema(&conn).map_err(|err| ScopeQueryError::plain(err.to_string()))?;

        let user_grid: Arc<RwLock<Option<String>>> = Arc::new(RwLock::new(None));
        register_functions(&conn, Arc::clone(&user_grid))
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;

        let interrupt = conn.get_interrupt_handle();
        Ok(ScopeDb { conn: Mutex::new(conn), interrupt, user_grid })
    }

    /// Update the grid the `cw_user_*` SQL functions resolve against.
    pub fn set_user_grid(&self, grid: Option<String>) {
        *self.user_grid.write().expect("user grid lock") =
            grid.filter(|value| !value.is_empty());
    }

    /// Break any currently-running query (maps to `sqlite3_interrupt`).
    pub fn interrupt(&self) {
        self.interrupt.interrupt();
    }

    // ---- Query surface ----

    /// Run an arbitrary read query, returning up to `limit` rows as
    /// display strings.
    pub fn run_query(&self, sql: &str, limit: u32) -> Result<QueryResultSet, ScopeQueryError> {
        let conn = self.conn.lock().expect("scope db lock");
        let mut stmt =
            conn.prepare(sql).map_err(|err| ScopeQueryError::from_rusqlite(err, sql))?;
        let columns: Vec<String> = stmt.column_names().iter().map(|s| s.to_string()).collect();
        let column_count = columns.len();

        let mut rows_out: Vec<Vec<Option<String>>> = Vec::new();
        let mut truncated = false;
        let mut rows =
            stmt.query([]).map_err(|err| ScopeQueryError::from_rusqlite(err, sql))?;
        loop {
            match rows.next() {
                Ok(Some(row)) => {
                    if rows_out.len() as u32 >= limit {
                        truncated = true;
                        break;
                    }
                    let mut values = Vec::with_capacity(column_count);
                    for idx in 0..column_count {
                        values.push(render_value(row.get_ref(idx).map_err(|err| {
                            ScopeQueryError::plain(err.to_string())
                        })?));
                    }
                    rows_out.push(values);
                }
                Ok(None) => break,
                Err(err) => return Err(ScopeQueryError::from_rusqlite(err, sql)),
            }
        }
        Ok(QueryResultSet { columns, rows: rows_out, truncated })
    }

    /// `EXPLAIN QUERY PLAN` for the workbench Profile button.
    pub fn profile_query(&self, sql: &str) -> Result<QueryResultSet, ScopeQueryError> {
        self.run_query(&format!("EXPLAIN QUERY PLAN {sql}"), 512)
    }

    /// Validate a band-scope query: it must prepare, be read-only, and
    /// emit a `spot_id` column (the `BandScopeQueryRunner` contract).
    pub fn validate_scope_query(&self, sql: &str) -> Result<(), ScopeQueryError> {
        let conn = self.conn.lock().expect("scope db lock");
        let stmt =
            conn.prepare(sql).map_err(|err| ScopeQueryError::from_rusqlite(err, sql))?;
        if !stmt.readonly() {
            return Err(ScopeQueryError::plain("band scope queries must be read-only"));
        }
        let has_spot_id = stmt.column_names().contains(&"spot_id");
        if !has_spot_id {
            return Err(ScopeQueryError::plain(
                "query must select a spot_id column to drive the band scope",
            ));
        }
        Ok(())
    }

    /// Run a validated band-scope query and collect the `spot_id` column.
    pub fn allowed_spot_ids(&self, sql: &str) -> Result<Vec<String>, ScopeQueryError> {
        let result = self.run_query(sql, 10_000)?;
        let Some(idx) = result.columns.iter().position(|name| name == "spot_id") else {
            return Err(ScopeQueryError::plain("query does not emit spot_id"));
        };
        Ok(result.rows.into_iter().filter_map(|row| row.into_iter().nth(idx).flatten()).collect())
    }

    // ---- Spot scope writes ----

    /// Insert observation rows and upsert the deduped `scope.spots`
    /// projection (Sweep's `recordObservations` + `upsertSpotProjection`).
    pub fn record_observations(
        &self,
        rows: &[SpotObservationRow],
    ) -> Result<(), ScopeQueryError> {
        let mut conn = self.conn.lock().expect("scope db lock");
        let tx = conn.transaction().map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        for row in rows {
            tx.execute(
                "INSERT OR REPLACE INTO scope.spot_observations (
                    obs_id, spot_id, callsign, band, mode, freq_hz, source, spotter,
                    spot_lat, spot_lon, snr_db, speed_wpm, comment, received_at, priority
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)",
                rusqlite::params![
                    row.obs_id,
                    row.spot_id,
                    row.callsign,
                    row.band,
                    row.mode,
                    row.freq_hz,
                    row.source,
                    row.spotter,
                    row.spot_lat,
                    row.spot_lon,
                    row.snr_db,
                    row.speed_wpm,
                    row.comment,
                    row.received_at as f64,
                    row.priority,
                ],
            )
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
            // Enrichment columns prefer the higher-priority source's value
            // but never clobber a known value with NULL from a sparser
            // source (an RBN re-spot must not erase a POTA park_ref).
            tx.execute(
                "INSERT INTO scope.spots (
                    spot_id, callsign, band, mode, freq_hz,
                    dxcc_entity, continent, cq_zone, itu_zone, grid, park_ref,
                    source, last_seen_at, priority
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
                ON CONFLICT(callsign, band) DO UPDATE SET
                    spot_id = CASE WHEN excluded.priority >= spots.priority
                                   THEN excluded.spot_id ELSE spots.spot_id END,
                    mode = CASE WHEN excluded.priority >= spots.priority
                                THEN excluded.mode ELSE spots.mode END,
                    freq_hz = CASE WHEN excluded.priority >= spots.priority
                                   THEN excluded.freq_hz ELSE spots.freq_hz END,
                    dxcc_entity = CASE WHEN excluded.priority >= spots.priority
                                       THEN COALESCE(excluded.dxcc_entity, spots.dxcc_entity)
                                       ELSE COALESCE(spots.dxcc_entity, excluded.dxcc_entity) END,
                    continent = CASE WHEN excluded.priority >= spots.priority
                                     THEN COALESCE(excluded.continent, spots.continent)
                                     ELSE COALESCE(spots.continent, excluded.continent) END,
                    cq_zone = CASE WHEN excluded.priority >= spots.priority
                                   THEN COALESCE(excluded.cq_zone, spots.cq_zone)
                                   ELSE COALESCE(spots.cq_zone, excluded.cq_zone) END,
                    itu_zone = CASE WHEN excluded.priority >= spots.priority
                                    THEN COALESCE(excluded.itu_zone, spots.itu_zone)
                                    ELSE COALESCE(spots.itu_zone, excluded.itu_zone) END,
                    grid = CASE WHEN excluded.priority >= spots.priority
                                THEN COALESCE(excluded.grid, spots.grid)
                                ELSE COALESCE(spots.grid, excluded.grid) END,
                    park_ref = CASE WHEN excluded.priority >= spots.priority
                                    THEN COALESCE(excluded.park_ref, spots.park_ref)
                                    ELSE COALESCE(spots.park_ref, excluded.park_ref) END,
                    source = CASE WHEN excluded.priority >= spots.priority
                                  THEN excluded.source ELSE spots.source END,
                    last_seen_at = MAX(spots.last_seen_at, excluded.last_seen_at),
                    priority = MAX(spots.priority, excluded.priority)",
                rusqlite::params![
                    row.spot_id,
                    row.callsign,
                    row.band,
                    row.mode,
                    row.freq_hz,
                    row.dxcc_entity,
                    row.continent,
                    row.cq_zone,
                    row.itu_zone,
                    row.grid,
                    row.park_ref,
                    row.source,
                    row.received_at as f64,
                    row.priority,
                ],
            )
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        }
        tx.commit().map_err(|err| ScopeQueryError::plain(err.to_string()))
    }

    pub fn upsert_spotter(&self, row: &SpotterRow) -> Result<(), ScopeQueryError> {
        let conn = self.conn.lock().expect("scope db lock");
        conn.execute(
            "INSERT OR REPLACE INTO scope.spotters (
                callsign, grid, lat, lon, dxcc_entity, continent, is_skimmer
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            rusqlite::params![
                row.callsign,
                row.grid,
                row.lat,
                row.lon,
                row.dxcc_entity,
                row.continent,
                row.is_skimmer as i64,
            ],
        )
        .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        Ok(())
    }

    /// Drop observations older than the window and orphaned projections
    /// (Sweep's `pruneScope`).
    pub fn prune_scope(&self, now: f64, window_secs: f64) -> Result<(), ScopeQueryError> {
        let cutoff = now - window_secs;
        let conn = self.conn.lock().expect("scope db lock");
        conn.execute(
            "DELETE FROM scope.spot_observations WHERE received_at < ?1",
            rusqlite::params![cutoff],
        )
        .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        conn.execute_batch(
            "DELETE FROM scope.spots
             WHERE NOT EXISTS (
                 SELECT 1 FROM scope.spot_observations
                 WHERE spot_observations.callsign = spots.callsign
                   AND spot_observations.band = spots.band
             )",
        )
        .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        Ok(())
    }

    // ---- Mirror writes ----

    pub fn upsert_qsos(&self, rows: &[ScopeQsoRow]) -> Result<(), ScopeQueryError> {
        let mut conn = self.conn.lock().expect("scope db lock");
        let tx = conn.transaction().map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        for row in rows {
            tx.execute(
                "INSERT OR REPLACE INTO qsos (
                    id, callsign, band, mode, frequency, timestamp, my_callsign,
                    their_grid, my_grid, park_ref, their_park_ref, dxcc,
                    modified_at, is_hidden, is_activity_log
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)",
                rusqlite::params![
                    row.id,
                    row.callsign,
                    row.band,
                    row.mode,
                    row.frequency,
                    row.timestamp,
                    row.my_callsign,
                    row.their_grid,
                    row.my_grid,
                    row.park_ref,
                    row.their_park_ref,
                    row.dxcc,
                    row.modified_at,
                    row.is_hidden as i64,
                    row.is_activity_log as i64,
                ],
            )
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        }
        tx.commit().map_err(|err| ScopeQueryError::plain(err.to_string()))
    }

    pub fn delete_qso(&self, id: &str) -> Result<(), ScopeQueryError> {
        let conn = self.conn.lock().expect("scope db lock");
        conn.execute("DELETE FROM qsos WHERE id = ?1", rusqlite::params![id])
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        Ok(())
    }

    pub fn seed_dxcc(&self, rows: &[ScopeDxccRow]) -> Result<(), ScopeQueryError> {
        let mut conn = self.conn.lock().expect("scope db lock");
        let tx = conn.transaction().map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        tx.execute_batch("DELETE FROM dxcc")
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        for row in rows {
            tx.execute(
                "INSERT INTO dxcc (entity, prefix, continent, cq_zone, itu_zone, lat, lon)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    row.entity,
                    row.prefix,
                    row.continent,
                    row.cq_zone,
                    row.itu_zone,
                    row.lat,
                    row.lon,
                ],
            )
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        }
        tx.commit().map_err(|err| ScopeQueryError::plain(err.to_string()))
    }

    /// Replace the matched-needs projection wholesale (per publish; the
    /// needs set is small and derived, so a full rewrite stays honest).
    pub fn replace_spot_needs(&self, rows: &[ScopeSpotNeedRow]) -> Result<(), ScopeQueryError> {
        let mut conn = self.conn.lock().expect("scope db lock");
        let tx = conn.transaction().map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        tx.execute_batch("DELETE FROM scope.spot_needs")
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        for row in rows {
            tx.execute(
                "INSERT INTO scope.spot_needs (spot_id, category, label, priority)
                 VALUES (?1, ?2, ?3, ?4)",
                rusqlite::params![row.spot_id, row.category, row.label, row.priority],
            )
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        }
        tx.commit().map_err(|err| ScopeQueryError::plain(err.to_string()))
    }

    pub fn seed_club_members(&self, rows: &[ScopeClubMemberRow]) -> Result<(), ScopeQueryError> {
        let mut conn = self.conn.lock().expect("scope db lock");
        let tx = conn.transaction().map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        tx.execute_batch("DELETE FROM scope.club_members")
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        for row in rows {
            tx.execute(
                "INSERT OR REPLACE INTO scope.club_members (callsign, club)
                 VALUES (?1, ?2)",
                rusqlite::params![row.callsign, row.club],
            )
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        }
        tx.commit().map_err(|err| ScopeQueryError::plain(err.to_string()))
    }

    pub fn seed_polo_notes(&self, rows: &[ScopePoloNoteRow]) -> Result<(), ScopeQueryError> {
        let mut conn = self.conn.lock().expect("scope db lock");
        let tx = conn.transaction().map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        tx.execute_batch("DELETE FROM polo_notes")
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        for row in rows {
            tx.execute(
                "INSERT INTO polo_notes (callsign, tag, body) VALUES (?1, ?2, ?3)",
                rusqlite::params![row.callsign, row.tag, row.body],
            )
            .map_err(|err| ScopeQueryError::plain(err.to_string()))?;
        }
        tx.commit().map_err(|err| ScopeQueryError::plain(err.to_string()))
    }
}

fn render_value(value: ValueRef<'_>) -> Option<String> {
    match value {
        ValueRef::Null => None,
        ValueRef::Integer(int) => Some(int.to_string()),
        ValueRef::Real(real) => Some(real.to_string()),
        ValueRef::Text(text) => Some(String::from_utf8_lossy(text).into_owned()),
        ValueRef::Blob(blob) => Some(format!("<blob {} bytes>", blob.len())),
    }
}

/// The Sweep workbench schema: `Migrations.swift` v1+v2 (main schema) +
/// `ScopeSchema.swift` (attached `scope` schema).
fn apply_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE meta (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT
        );
        CREATE TABLE qsos (
            id TEXT PRIMARY KEY NOT NULL,
            callsign TEXT NOT NULL,
            band TEXT NOT NULL,
            mode TEXT NOT NULL,
            frequency REAL,
            timestamp REAL NOT NULL,
            my_callsign TEXT NOT NULL,
            their_grid TEXT,
            my_grid TEXT,
            park_ref TEXT,
            their_park_ref TEXT,
            dxcc INTEGER,
            modified_at REAL,
            is_hidden INTEGER NOT NULL DEFAULT 0,
            is_activity_log INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX qsos_callsign ON qsos(callsign);
        CREATE INDEX qsos_band_mode ON qsos(band, mode);
        CREATE INDEX qsos_dxcc ON qsos(dxcc);
        CREATE INDEX qsos_timestamp ON qsos(timestamp);
        CREATE TABLE dxcc (
            entity TEXT PRIMARY KEY NOT NULL,
            prefix TEXT,
            continent TEXT,
            cq_zone INTEGER,
            itu_zone INTEGER,
            lat REAL,
            lon REAL
        );
        CREATE INDEX dxcc_continent ON dxcc(continent);
        CREATE TABLE polo_notes (
            callsign TEXT PRIMARY KEY NOT NULL,
            tag TEXT,
            body TEXT
        );
        CREATE TABLE operator_profiles (
            callsign TEXT PRIMARY KEY NOT NULL,
            name TEXT,
            first_name TEXT,
            nickname TEXT,
            qth TEXT,
            state TEXT,
            country TEXT,
            grid TEXT,
            license_class TEXT,
            source TEXT NOT NULL,
            updated_at REAL NOT NULL,
            enriched_at REAL
        );
        CREATE VIEW dxcc_status AS
        SELECT
            dxcc.entity AS entity,
            qsos.band AS band,
            qsos.mode AS mode,
            COUNT(qsos.id) AS worked_count,
            MAX(qsos.timestamp) AS last_worked_at,
            dxcc.continent AS continent,
            dxcc.cq_zone AS cq_zone
        FROM dxcc
        LEFT JOIN qsos ON qsos.dxcc IS NOT NULL
            AND CAST(qsos.dxcc AS TEXT) = dxcc.entity
            AND qsos.is_hidden = 0
        GROUP BY dxcc.entity, qsos.band, qsos.mode;
        CREATE TABLE scope.spots (
            spot_id TEXT PRIMARY KEY NOT NULL,
            callsign TEXT NOT NULL,
            band TEXT NOT NULL,
            mode TEXT NOT NULL,
            freq_hz INTEGER,
            dxcc_entity TEXT,
            continent TEXT,
            cq_zone INTEGER,
            itu_zone INTEGER,
            grid TEXT,
            park_ref TEXT,
            source TEXT,
            last_seen_at REAL NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0,
            UNIQUE(callsign, band)
        );
        CREATE INDEX scope.spots_band ON spots(band);
        CREATE INDEX scope.spots_callsign ON spots(callsign);
        CREATE TABLE scope.spot_needs (
            spot_id TEXT NOT NULL,
            category TEXT NOT NULL,
            label TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX scope.spot_needs_spot ON spot_needs(spot_id);
        CREATE TABLE scope.club_members (
            callsign TEXT NOT NULL,
            club TEXT NOT NULL,
            PRIMARY KEY(callsign, club)
        );
        CREATE TABLE scope.spot_observations (
            obs_id TEXT PRIMARY KEY NOT NULL,
            spot_id TEXT NOT NULL,
            callsign TEXT NOT NULL,
            band TEXT NOT NULL,
            mode TEXT NOT NULL,
            freq_hz INTEGER,
            source TEXT NOT NULL,
            spotter TEXT,
            spot_lat REAL,
            spot_lon REAL,
            snr_db INTEGER,
            speed_wpm INTEGER,
            comment TEXT,
            received_at REAL NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX scope.obs_callsign_band ON spot_observations(callsign, band);
        CREATE INDEX scope.obs_source ON spot_observations(source);
        CREATE INDEX scope.obs_received_at ON spot_observations(received_at);
        CREATE TABLE scope.spotters (
            callsign TEXT PRIMARY KEY NOT NULL,
            grid TEXT,
            lat REAL,
            lon REAL,
            dxcc_entity TEXT,
            continent TEXT,
            is_skimmer INTEGER NOT NULL DEFAULT 0
        );",
    )
}

// ---- Custom SQL functions (QuerySQLFunctions.swift) ----

const EARTH_RADIUS_KM: f64 = 6_371.0;
const MILES_PER_KM: f64 = 0.621_371;

fn haversine_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let phi1 = lat1.to_radians();
    let phi2 = lat2.to_radians();
    let d_phi = (lat2 - lat1).to_radians();
    let d_lambda = (lon2 - lon1).to_radians();
    let a = (d_phi / 2.0).sin().powi(2)
        + phi1.cos() * phi2.cos() * (d_lambda / 2.0).sin().powi(2);
    EARTH_RADIUS_KM * 2.0 * a.sqrt().atan2((1.0 - a).sqrt())
}

fn initial_bearing_deg(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let phi1 = lat1.to_radians();
    let phi2 = lat2.to_radians();
    let d_lambda = (lon2 - lon1).to_radians();
    let x_part = d_lambda.sin() * phi2.cos();
    let y_part = phi1.cos() * phi2.sin() - phi1.sin() * phi2.cos() * d_lambda.cos();
    (x_part.atan2(y_part).to_degrees() + 360.0) % 360.0
}

/// Pull a Double out of a SQLite value, accepting integer/text storage too
/// (numeric affinity — a REAL column can hold integer storage).
fn double_arg(ctx: &rusqlite::functions::Context<'_>, idx: usize) -> Option<f64> {
    match ctx.get_raw(idx) {
        ValueRef::Null => None,
        ValueRef::Integer(int) => Some(int as f64),
        ValueRef::Real(real) => Some(real),
        ValueRef::Text(text) => std::str::from_utf8(text).ok()?.parse().ok(),
        ValueRef::Blob(_) => None,
    }
}

fn string_arg(ctx: &rusqlite::functions::Context<'_>, idx: usize) -> Option<String> {
    match ctx.get_raw(idx) {
        ValueRef::Text(text) => {
            let value = std::str::from_utf8(text).ok()?;
            if value.is_empty() { None } else { Some(value.to_string()) }
        }
        _ => None,
    }
}

fn grid_coord(grid: &str) -> Option<(f64, f64)> {
    maidenhead::coordinate_from_grid(grid).map(|coord| (coord.latitude, coord.longitude))
}

fn register_functions(
    conn: &Connection,
    user_grid: Arc<RwLock<Option<String>>>,
) -> rusqlite::Result<()> {
    let pure = FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC;
    let volatile = FunctionFlags::SQLITE_UTF8;

    for (name, in_miles) in [("cw_distance_km", false), ("cw_distance_mi", true)] {
        conn.create_scalar_function(name, 4, pure, move |ctx| {
            Ok(match (
                double_arg(ctx, 0), double_arg(ctx, 1),
                double_arg(ctx, 2), double_arg(ctx, 3),
            ) {
                (Some(lat1), Some(lon1), Some(lat2), Some(lon2)) => {
                    let km = haversine_km(lat1, lon1, lat2, lon2);
                    Some(if in_miles { km * MILES_PER_KM } else { km })
                }
                _ => None,
            })
        })?;
    }

    conn.create_scalar_function("cw_bearing_deg", 4, pure, |ctx| {
        Ok(match (
            double_arg(ctx, 0), double_arg(ctx, 1),
            double_arg(ctx, 2), double_arg(ctx, 3),
        ) {
            (Some(lat1), Some(lon1), Some(lat2), Some(lon2)) => {
                Some(initial_bearing_deg(lat1, lon1, lat2, lon2))
            }
            _ => None,
        })
    })?;

    for (name, in_miles) in [("cw_grid_distance_km", false), ("cw_grid_distance_mi", true)] {
        conn.create_scalar_function(name, 2, pure, move |ctx| {
            Ok(match (
                string_arg(ctx, 0).as_deref().and_then(grid_coord),
                string_arg(ctx, 1).as_deref().and_then(grid_coord),
            ) {
                (Some((lat1, lon1)), Some((lat2, lon2))) => {
                    let km = haversine_km(lat1, lon1, lat2, lon2);
                    Some(if in_miles { km * MILES_PER_KM } else { km })
                }
                _ => None,
            })
        })?;
    }

    conn.create_scalar_function("cw_grid_bearing_deg", 2, pure, |ctx| {
        Ok(match (
            string_arg(ctx, 0).as_deref().and_then(grid_coord),
            string_arg(ctx, 1).as_deref().and_then(grid_coord),
        ) {
            (Some((lat1, lon1)), Some((lat2, lon2))) => {
                Some(initial_bearing_deg(lat1, lon1, lat2, lon2))
            }
            _ => None,
        })
    })?;

    {
        let grid = Arc::clone(&user_grid);
        conn.create_scalar_function("cw_user_grid", 0, volatile, move |_ctx| {
            Ok(grid.read().expect("user grid lock").clone())
        })?;
    }

    for (name, in_miles) in
        [("cw_user_grid_distance_km", false), ("cw_user_grid_distance_mi", true)]
    {
        let grid = Arc::clone(&user_grid);
        conn.create_scalar_function(name, 1, volatile, move |ctx| {
            let user = grid.read().expect("user grid lock").clone();
            Ok(match (
                user.as_deref().and_then(grid_coord),
                string_arg(ctx, 0).as_deref().and_then(grid_coord),
            ) {
                (Some((lat1, lon1)), Some((lat2, lon2))) => {
                    let km = haversine_km(lat1, lon1, lat2, lon2);
                    Some(if in_miles { km * MILES_PER_KM } else { km })
                }
                _ => None,
            })
        })?;
    }

    for (name, in_miles) in [("cw_user_distance_km", false), ("cw_user_distance_mi", true)] {
        let grid = Arc::clone(&user_grid);
        conn.create_scalar_function(name, 2, volatile, move |ctx| {
            let user = grid.read().expect("user grid lock").clone();
            Ok(match (
                user.as_deref().and_then(grid_coord),
                double_arg(ctx, 0),
                double_arg(ctx, 1),
            ) {
                (Some((lat1, lon1)), Some(lat2), Some(lon2)) => {
                    let km = haversine_km(lat1, lon1, lat2, lon2);
                    Some(if in_miles { km * MILES_PER_KM } else { km })
                }
                _ => None,
            })
        })?;
    }

    {
        let grid = Arc::clone(&user_grid);
        conn.create_scalar_function("cw_user_grid_bearing_deg", 1, volatile, move |ctx| {
            let user = grid.read().expect("user grid lock").clone();
            Ok(match (
                user.as_deref().and_then(grid_coord),
                string_arg(ctx, 0).as_deref().and_then(grid_coord),
            ) {
                (Some((lat1, lon1)), Some((lat2, lon2))) => {
                    Some(initial_bearing_deg(lat1, lon1, lat2, lon2))
                }
                _ => None,
            })
        })?;
    }

    {
        let grid = Arc::clone(&user_grid);
        conn.create_scalar_function("cw_user_bearing_deg", 2, volatile, move |ctx| {
            let user = grid.read().expect("user grid lock").clone();
            Ok(match (
                user.as_deref().and_then(grid_coord),
                double_arg(ctx, 0),
                double_arg(ctx, 1),
            ) {
                (Some((lat1, lon1)), Some(lat2), Some(lon2)) => {
                    Some(initial_bearing_deg(lat1, lon1, lat2, lon2))
                }
                _ => None,
            })
        })?;
    }

    conn.create_scalar_function("cw_now", 0, volatile, |_ctx| {
        Ok(std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0))
    })?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn obs(id: &str, callsign: &str, band: &str, priority: i32, at: i64) -> SpotObservationRow {
        SpotObservationRow {
            obs_id: format!("obs-{id}"),
            spot_id: id.to_string(),
            callsign: callsign.to_string(),
            band: band.to_string(),
            mode: "CW".to_string(),
            freq_hz: 14_040_000,
            source: "rbn".to_string(),
            spotter: Some("W3LPL".to_string()),
            spot_lat: Some(35.0),
            spot_lon: Some(139.0),
            snr_db: Some(20),
            speed_wpm: Some(25),
            comment: None,
            received_at: at,
            priority,
            dxcc_entity: Some("Japan".to_string()),
            continent: Some("AS".to_string()),
            cq_zone: Some(25),
            itu_zone: Some(45),
            grid: None,
            park_ref: None,
        }
    }

    #[test]
    fn schema_applies_and_starter_shapes_run() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.record_observations(&[obs("rbn-1", "JA1ABC", "20m", 0, 100)]).unwrap();
        let result = db
            .run_query(
                "SELECT callsign, band, COUNT(*) AS n FROM scope.spot_observations GROUP BY callsign, band",
                100,
            )
            .unwrap();
        assert_eq!(result.columns, vec!["callsign", "band", "n"]);
        assert_eq!(result.rows, vec![vec![
            Some("JA1ABC".to_string()),
            Some("20m".to_string()),
            Some("1".to_string()),
        ]]);
    }

    #[test]
    fn projection_upsert_prefers_higher_priority() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.record_observations(&[
            obs("rbn-1", "JA1ABC", "20m", 0, 100),
            obs("pota-1", "JA1ABC", "20m", 4, 90),
            obs("rbn-2", "JA1ABC", "20m", 0, 200),
        ])
        .unwrap();
        let result = db
            .run_query("SELECT spot_id, priority, last_seen_at FROM scope.spots", 10)
            .unwrap();
        assert_eq!(result.rows.len(), 1);
        // Priority 4 wins the id; last_seen_at advances to the newest.
        assert_eq!(result.rows[0][0].as_deref(), Some("pota-1"));
        assert_eq!(result.rows[0][1].as_deref(), Some("4"));
        assert_eq!(result.rows[0][2].as_deref(), Some("200"));
    }

    #[test]
    fn projection_carries_enrichment_and_source() {
        let db = ScopeDb::new_in_memory().unwrap();
        // Sparse RBN row first, then a richer POTA row, then another
        // sparse RBN re-spot: enrichment must survive the whole sequence.
        let mut rbn = obs("rbn-1", "JA1ABC", "20m", 0, 100);
        rbn.dxcc_entity = Some("Japan".to_string());
        rbn.park_ref = None;
        let mut pota = obs("pota-1", "JA1ABC", "20m", 4, 150);
        pota.source = "pota".to_string();
        pota.park_ref = Some("JP-0014".to_string());
        let mut rbn2 = obs("rbn-2", "JA1ABC", "20m", 0, 200);
        rbn2.dxcc_entity = None;
        db.record_observations(&[rbn, pota, rbn2]).unwrap();

        let result = db
            .run_query(
                "SELECT dxcc_entity, continent, park_ref, source FROM scope.spots",
                10,
            )
            .unwrap();
        assert_eq!(result.rows.len(), 1);
        assert_eq!(result.rows[0][0].as_deref(), Some("Japan"));
        assert_eq!(result.rows[0][1].as_deref(), Some("AS"));
        // POTA's park_ref survives the later sparse RBN re-spot, and the
        // winning source is the higher-priority one.
        assert_eq!(result.rows[0][2].as_deref(), Some("JP-0014"));
        assert_eq!(result.rows[0][3].as_deref(), Some("pota"));
    }

    #[test]
    fn spot_needs_replace_wholesale() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.replace_spot_needs(&[ScopeSpotNeedRow {
            spot_id: "rbn-1".to_string(),
            category: "dxcc".to_string(),
            label: "NEW DXCC".to_string(),
            priority: 2,
        }])
        .unwrap();
        db.replace_spot_needs(&[ScopeSpotNeedRow {
            spot_id: "pota-2".to_string(),
            category: "pota_new_park".to_string(),
            label: "NEW PARK".to_string(),
            priority: 1,
        }])
        .unwrap();
        let result =
            db.run_query("SELECT spot_id, category FROM scope.spot_needs", 10).unwrap();
        assert_eq!(result.rows.len(), 1);
        assert_eq!(result.rows[0][0].as_deref(), Some("pota-2"));
    }

    #[test]
    fn club_members_seed_and_join() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.record_observations(&[obs("rbn-1", "JA1ABC", "20m", 0, 100)]).unwrap();
        db.seed_club_members(&[
            ScopeClubMemberRow { callsign: "JA1ABC".to_string(), club: "skcc".to_string() },
            ScopeClubMemberRow { callsign: "W1AW".to_string(), club: "skcc".to_string() },
        ])
        .unwrap();
        let ids = db
            .allowed_spot_ids(
                "SELECT spot_id FROM scope.spots
                 WHERE callsign IN (SELECT callsign FROM scope.club_members WHERE club = 'skcc')",
            )
            .unwrap();
        assert_eq!(ids, vec!["rbn-1".to_string()]);
        // Re-seed replaces wholesale.
        db.seed_club_members(&[]).unwrap();
        let result = db.run_query("SELECT COUNT(*) FROM scope.club_members", 1).unwrap();
        assert_eq!(result.rows[0][0].as_deref(), Some("0"));
    }

    #[test]
    fn prune_drops_old_observations_and_orphans() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.record_observations(&[
            obs("rbn-1", "JA1ABC", "20m", 0, 100),
            obs("rbn-2", "W1AW", "40m", 0, 900),
        ])
        .unwrap();
        db.prune_scope(1_000.0, 500.0).unwrap();
        let spots = db.run_query("SELECT callsign FROM scope.spots", 10).unwrap();
        assert_eq!(spots.rows.len(), 1);
        assert_eq!(spots.rows[0][0].as_deref(), Some("W1AW"));
    }

    #[test]
    fn qso_mirror_and_dxcc_status_view_join() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.seed_dxcc(&[ScopeDxccRow {
            entity: "291".to_string(),
            prefix: Some("K".to_string()),
            continent: Some("NA".to_string()),
            cq_zone: Some(5),
            itu_zone: Some(8),
            lat: Some(37.53),
            lon: Some(-91.67),
        }])
        .unwrap();
        db.upsert_qsos(&[ScopeQsoRow {
            id: "q1".to_string(),
            callsign: "W1AW".to_string(),
            band: "20m".to_string(),
            mode: "CW".to_string(),
            frequency: Some(14.04),
            timestamp: 1_000.0,
            my_callsign: "W6JY".to_string(),
            their_grid: Some("FN31".to_string()),
            my_grid: Some("DM04".to_string()),
            park_ref: None,
            their_park_ref: None,
            dxcc: Some(291),
            modified_at: None,
            is_hidden: false,
            is_activity_log: false,
        }])
        .unwrap();
        let result = db
            .run_query(
                "SELECT entity, band, worked_count FROM dxcc_status WHERE band IS NOT NULL",
                10,
            )
            .unwrap();
        assert_eq!(result.rows, vec![vec![
            Some("291".to_string()),
            Some("20m".to_string()),
            Some("1".to_string()),
        ]]);
    }

    #[test]
    fn user_grid_functions_resolve() {
        let db = ScopeDb::new_in_memory().unwrap();
        // No grid set → NULL.
        let result = db.run_query("SELECT cw_user_grid_distance_km('FN31')", 1).unwrap();
        assert_eq!(result.rows[0][0], None);

        db.set_user_grid(Some("DM04".to_string()));
        let result = db
            .run_query("SELECT cw_user_grid(), cw_user_grid_distance_km('FN31')", 1)
            .unwrap();
        assert_eq!(result.rows[0][0].as_deref(), Some("DM04"));
        let km: f64 = result.rows[0][1].as_deref().unwrap().parse().unwrap();
        // LA → CT is roughly 4,000 km.
        assert!((3_500.0..4_500.0).contains(&km), "km = {km}");
    }

    #[test]
    fn grid_math_functions() {
        let db = ScopeDb::new_in_memory().unwrap();
        let result = db
            .run_query(
                "SELECT cw_grid_distance_km('DM04', 'FN31'),
                        cw_grid_bearing_deg('DM04', 'FN31'),
                        cw_distance_km(34.0, -118.0, 41.0, -73.0),
                        cw_now() > 1000000000",
                1,
            )
            .unwrap();
        let km: f64 = result.rows[0][0].as_deref().unwrap().parse().unwrap();
        assert!((3_500.0..4_500.0).contains(&km));
        let bearing: f64 = result.rows[0][1].as_deref().unwrap().parse().unwrap();
        assert!((0.0..360.0).contains(&bearing));
        assert!(result.rows[0][2].is_some());
        assert_eq!(result.rows[0][3].as_deref(), Some("1"));
    }

    #[test]
    fn validate_scope_query_contract() {
        let db = ScopeDb::new_in_memory().unwrap();
        assert!(db.validate_scope_query("SELECT spot_id FROM scope.spots").is_ok());
        // Missing spot_id column.
        let err = db.validate_scope_query("SELECT callsign FROM scope.spots").unwrap_err();
        assert!(err.message.contains("spot_id"));
        // Writes are rejected.
        assert!(db.validate_scope_query("DELETE FROM scope.spots").is_err());
    }

    #[test]
    fn allowed_spot_ids_collects_column() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.record_observations(&[
            obs("rbn-1", "JA1ABC", "20m", 0, 100),
            obs("rbn-2", "W1AW", "40m", 0, 100),
        ])
        .unwrap();
        let ids = db
            .allowed_spot_ids("SELECT spot_id FROM scope.spots WHERE band = '20m'")
            .unwrap();
        assert_eq!(ids, vec!["rbn-1".to_string()]);
    }

    #[test]
    fn compiled_profile_queries_execute_against_live_schema() {
        use cw_domain::spots::goal_profile::{
            compile_profile_queries, BasePredicate, GoalProfile, QuickToggles,
        };
        let db = ScopeDb::new_in_memory().unwrap();
        let mut rbn = obs("rbn-1", "JA1ABC", "20m", 0, 100);
        rbn.park_ref = None;
        let mut pota = obs("pota-1", "W1AW", "40m", 4, 100);
        pota.source = "pota".to_string();
        pota.park_ref = Some("US-0001".to_string());
        db.record_observations(&[rbn, pota]).unwrap();
        db.replace_spot_needs(&[ScopeSpotNeedRow {
            spot_id: "rbn-1".to_string(),
            category: "dxcc".to_string(),
            label: "NEW DXCC".to_string(),
            priority: 2,
        }])
        .unwrap();

        let toggles = QuickToggles {
            wpm_ceiling: Some(30),
            suppress_worked_today: true,
            rbn_enabled: false,
            // Exercises the mode predicate against the live schema.
            enabled_modes: vec!["CW".to_string()],
        };
        for predicate in [
            BasePredicate::All,
            BasePredicate::Parks,
            BasePredicate::DxccNeeded,
            BasePredicate::ClubMembers,
            BasePredicate::NeededOnly,
        ] {
            let profile = GoalProfile {
                id: "p".to_string(),
                name: "P".to_string(),
                base_predicate: predicate.clone(),
                clubs: vec!["skcc".to_string()],
                need_categories: vec![],
            };
            let queries = compile_profile_queries(&profile, &toggles);
            // Every compiled query must satisfy the band-scope contract
            // (read-only, emits spot_id) and run without error.
            db.validate_scope_query(&queries.scope_pass)
                .unwrap_or_else(|err| panic!("{predicate:?} scope: {}", err.message));
            db.validate_scope_query(&queries.heard_pass)
                .unwrap_or_else(|err| panic!("{predicate:?} heard: {}", err.message));
            db.allowed_spot_ids(&queries.scope_pass).unwrap();
            db.allowed_spot_ids(&queries.heard_pass).unwrap();
            if let Some(wpm) = &queries.wpm_dim {
                db.allowed_spot_ids(wpm).unwrap();
            }
        }

        // Semantics spot-checks: Parks matches the POTA spot only; the
        // needs projection drives DxccNeeded; RBN-off keeps human spots.
        let parks = compile_profile_queries(
            &GoalProfile {
                id: "parks".to_string(),
                name: "Parks".to_string(),
                base_predicate: BasePredicate::Parks,
                clubs: vec![],
                need_categories: vec![],
            },
            &QuickToggles {
                wpm_ceiling: None,
                suppress_worked_today: false,
                rbn_enabled: true,
                enabled_modes: vec![],
            },
        );
        assert_eq!(db.allowed_spot_ids(&parks.heard_pass).unwrap(), vec!["pota-1".to_string()]);

        let dxcc = compile_profile_queries(
            &GoalProfile {
                id: "dxcc".to_string(),
                name: "DXCC".to_string(),
                base_predicate: BasePredicate::DxccNeeded,
                clubs: vec![],
                need_categories: vec![],
            },
            &QuickToggles {
                wpm_ceiling: None,
                suppress_worked_today: false,
                rbn_enabled: true,
                enabled_modes: vec![],
            },
        );
        assert_eq!(db.allowed_spot_ids(&dxcc.heard_pass).unwrap(), vec!["rbn-1".to_string()]);
    }

    #[test]
    fn error_carries_line_and_column() {
        let db = ScopeDb::new_in_memory().unwrap();
        let err = db.run_query("SELECT spot_id\nFROM scope.spots\nWHERE bogus_col = 1", 10);
        let err = err.unwrap_err();
        assert!(err.message.contains("bogus_col") || err.message.contains("no such column"));
        if let (Some(line), Some(_col)) = (err.line, err.column) {
            assert_eq!(line, 3);
        }
    }

    #[test]
    fn run_query_truncates_at_limit() {
        let db = ScopeDb::new_in_memory().unwrap();
        db.record_observations(&[
            obs("rbn-1", "A1A", "20m", 0, 100),
            obs("rbn-2", "B2B", "40m", 0, 100),
            obs("rbn-3", "C3C", "15m", 0, 100),
        ])
        .unwrap();
        let result = db.run_query("SELECT obs_id FROM scope.spot_observations", 2).unwrap();
        assert_eq!(result.rows.len(), 2);
        assert!(result.truncated);
    }
}
