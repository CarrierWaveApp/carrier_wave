// src/snapshots.rs
//
//! Periodic disk snapshots of aggregated data (parks, GIS, statistics).
//!
//! Writes JSONL files (one row per line) to a configurable directory every N
//! hours so that state can be recovered on startup when the data is less than
//! a configurable max age. This avoids expensive re-fetches from upstream
//! APIs after restarts.
//!
//! Rows are streamed from Postgres to disk (and back on restore) one at a
//! time — tables are never fully materialized in memory. The previous
//! whole-table-as-JSON-array format OOM-killed the server once the
//! park_boundaries and pota_activations tables outgrew the service's memory
//! limit.

use std::path::{Path, PathBuf};

use chrono::{DateTime, NaiveDate, Utc};
use futures_util::TryStreamExt;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tokio::fs;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt};

use crate::config::Config;

// ---------------------------------------------------------------------------
// Snapshot envelope
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct SnapshotManifest {
    pub version: u32,
    pub created_at: DateTime<Utc>,
    pub pota_parks_count: usize,
    pub pota_activations_count: usize,
    pub pota_hunter_qsos_count: usize,
    pub pota_fetch_status_count: usize,
    pub park_boundaries_count: usize,
    pub historic_trails_count: usize,
}

// ---------------------------------------------------------------------------
// Serializable row types (mirrors of DB rows)
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct ParkSnapshot {
    pub reference: String,
    pub name: String,
    pub location_desc: Option<String>,
    pub state: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub grid: Option<String>,
    pub active: bool,
    pub total_attempts: i32,
    pub total_activations: i32,
    pub total_qsos: i32,
    pub stats_fetched_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct ActivationSnapshot {
    pub park_reference: String,
    pub callsign: String,
    pub qso_date: NaiveDate,
    pub total_qsos: i32,
    pub qsos_cw: i32,
    pub qsos_data: i32,
    pub qsos_phone: i32,
    pub state: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct HunterQsoSnapshot {
    pub park_reference: String,
    pub callsign: String,
    pub qso_count: i32,
    pub state: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct FetchStatusSnapshot {
    pub park_reference: String,
    pub activations_fetched_at: Option<DateTime<Utc>>,
    pub leaderboard_fetched_at: Option<DateTime<Utc>>,
    pub fetch_error: Option<String>,
    pub consecutive_errors: i32,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct BoundarySnapshot {
    pub pota_reference: String,
    pub park_name: String,
    pub designation: Option<String>,
    pub manager: Option<String>,
    pub acreage: Option<f64>,
    pub match_quality: String,
    pub source: String,
    pub geometry_json: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct TrailSnapshot {
    pub trail_reference: String,
    pub trail_name: String,
    pub designation: Option<String>,
    pub managing_agency: Option<String>,
    pub length_miles: Option<f64>,
    pub state: Option<String>,
    pub match_quality: String,
    pub source: String,
    pub geometry_json: Option<String>,
}

// ---------------------------------------------------------------------------
// Export queries
// ---------------------------------------------------------------------------

const PARKS_SQL: &str = r#"SELECT reference, name, location_desc, state, latitude, longitude,
       grid, active, total_attempts, total_activations, total_qsos,
       stats_fetched_at
FROM pota_parks"#;

const ACTIVATIONS_SQL: &str = r#"SELECT park_reference, callsign, qso_date, total_qsos,
       qsos_cw, qsos_data, qsos_phone, state
FROM pota_activations"#;

const HUNTER_QSOS_SQL: &str = r#"SELECT park_reference, callsign, qso_count, state
FROM pota_hunter_qsos"#;

const FETCH_STATUS_SQL: &str = r#"SELECT park_reference, activations_fetched_at, leaderboard_fetched_at,
       fetch_error, consecutive_errors
FROM pota_fetch_status"#;

const BOUNDARIES_SQL: &str = r#"SELECT pota_reference, park_name, designation, manager, acreage,
       match_quality, source,
       ST_AsGeoJSON(geometry) as geometry_json
FROM park_boundaries"#;

const TRAILS_SQL: &str = r#"SELECT trail_reference, trail_name, designation, managing_agency,
       length_miles, state, match_quality, source,
       ST_AsGeoJSON(geometry) as geometry_json
FROM historic_trails"#;

// ---------------------------------------------------------------------------
// Import queries (single row)
// ---------------------------------------------------------------------------

async fn import_park(pool: &PgPool, p: ParkSnapshot) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"INSERT INTO pota_parks
               (reference, name, location_desc, state, latitude, longitude,
                grid, active, total_attempts, total_activations, total_qsos,
                stats_fetched_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
           ON CONFLICT (reference) DO NOTHING"#,
    )
    .bind(&p.reference)
    .bind(&p.name)
    .bind(&p.location_desc)
    .bind(&p.state)
    .bind(p.latitude)
    .bind(p.longitude)
    .bind(&p.grid)
    .bind(p.active)
    .bind(p.total_attempts)
    .bind(p.total_activations)
    .bind(p.total_qsos)
    .bind(p.stats_fetched_at)
    .execute(pool)
    .await?;
    Ok(())
}

async fn import_activation(pool: &PgPool, r: ActivationSnapshot) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"INSERT INTO pota_activations
               (park_reference, callsign, qso_date, total_qsos,
                qsos_cw, qsos_data, qsos_phone, state)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
           ON CONFLICT (park_reference, callsign, qso_date) DO NOTHING"#,
    )
    .bind(&r.park_reference)
    .bind(&r.callsign)
    .bind(r.qso_date)
    .bind(r.total_qsos)
    .bind(r.qsos_cw)
    .bind(r.qsos_data)
    .bind(r.qsos_phone)
    .bind(&r.state)
    .execute(pool)
    .await?;
    Ok(())
}

async fn import_hunter_qso(pool: &PgPool, r: HunterQsoSnapshot) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"INSERT INTO pota_hunter_qsos (park_reference, callsign, qso_count, state)
           VALUES ($1,$2,$3,$4)
           ON CONFLICT (park_reference, callsign) DO NOTHING"#,
    )
    .bind(&r.park_reference)
    .bind(&r.callsign)
    .bind(r.qso_count)
    .bind(&r.state)
    .execute(pool)
    .await?;
    Ok(())
}

async fn import_fetch_status(pool: &PgPool, r: FetchStatusSnapshot) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"INSERT INTO pota_fetch_status
               (park_reference, activations_fetched_at, leaderboard_fetched_at,
                fetch_error, consecutive_errors)
           VALUES ($1,$2,$3,$4,$5)
           ON CONFLICT (park_reference) DO NOTHING"#,
    )
    .bind(&r.park_reference)
    .bind(r.activations_fetched_at)
    .bind(r.leaderboard_fetched_at)
    .bind(&r.fetch_error)
    .bind(r.consecutive_errors)
    .execute(pool)
    .await?;
    Ok(())
}

async fn import_boundary(pool: &PgPool, r: BoundarySnapshot) -> Result<(), sqlx::Error> {
    if let Some(ref geojson) = r.geometry_json {
        sqlx::query(
            r#"INSERT INTO park_boundaries
                   (pota_reference, park_name, designation, manager, acreage,
                    match_quality, geometry, geometry_simplified, source,
                    fetched_at, matched_at)
               VALUES ($1,$2,$3,$4,$5,$6,
                       ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($7), 3)),
                       ST_Simplify(ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($7), 3)), 0.001),
                       $8, NOW(), NOW())
               ON CONFLICT (pota_reference) DO NOTHING"#,
        )
        .bind(&r.pota_reference)
        .bind(&r.park_name)
        .bind(&r.designation)
        .bind(&r.manager)
        .bind(r.acreage)
        .bind(&r.match_quality)
        .bind(geojson)
        .bind(&r.source)
        .execute(pool)
        .await?;
    } else {
        // no-match sentinel row
        sqlx::query(
            r#"INSERT INTO park_boundaries
                   (pota_reference, park_name, match_quality, geometry,
                    geometry_simplified, source, fetched_at, matched_at)
               VALUES ($1,$2,$3, NULL, NULL, $4, NOW(), NOW())
               ON CONFLICT (pota_reference) DO NOTHING"#,
        )
        .bind(&r.pota_reference)
        .bind(&r.park_name)
        .bind(&r.match_quality)
        .bind(&r.source)
        .execute(pool)
        .await?;
    }
    Ok(())
}

async fn import_trail(pool: &PgPool, r: TrailSnapshot) -> Result<(), sqlx::Error> {
    if let Some(ref geojson) = r.geometry_json {
        sqlx::query(
            r#"INSERT INTO historic_trails
                   (trail_reference, trail_name, designation, managing_agency,
                    length_miles, state, match_quality,
                    geometry, geometry_simplified, source,
                    fetched_at, matched_at)
               VALUES ($1,$2,$3,$4,$5,$6,$7,
                       ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($8), 2)),
                       ST_Simplify(ST_Multi(ST_CollectionExtract(ST_GeomFromGeoJSON($8), 2)), 0.005),
                       $9, NOW(), NOW())
               ON CONFLICT (trail_reference) DO NOTHING"#,
        )
        .bind(&r.trail_reference)
        .bind(&r.trail_name)
        .bind(&r.designation)
        .bind(&r.managing_agency)
        .bind(r.length_miles)
        .bind(&r.state)
        .bind(&r.match_quality)
        .bind(geojson)
        .bind(&r.source)
        .execute(pool)
        .await?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Streaming JSONL I/O
// ---------------------------------------------------------------------------

/// Stream a table to a JSONL file (one JSON object per line), row by row.
/// Written atomically (to .tmp, then renamed). Returns the row count.
async fn export_jsonl<T>(
    pool: &PgPool,
    dir: &Path,
    filename: &str,
    sql: &'static str,
) -> Result<usize, String>
where
    T: Serialize + Send + Unpin + for<'r> sqlx::FromRow<'r, sqlx::postgres::PgRow>,
{
    let tmp = dir.join(format!("{filename}.tmp"));
    let file = fs::File::create(&tmp)
        .await
        .map_err(|e| format!("create {filename}: {e}"))?;
    let mut writer = tokio::io::BufWriter::new(file);

    let mut rows = sqlx::query_as::<_, T>(sql).fetch(pool);
    let mut count = 0usize;
    let mut buf = Vec::with_capacity(4096);
    while let Some(row) = rows
        .try_next()
        .await
        .map_err(|e| format!("stream {filename}: {e}"))?
    {
        buf.clear();
        serde_json::to_writer(&mut buf, &row).map_err(|e| format!("serialize {filename}: {e}"))?;
        buf.push(b'\n');
        writer
            .write_all(&buf)
            .await
            .map_err(|e| format!("write {filename}: {e}"))?;
        count += 1;
    }
    writer
        .flush()
        .await
        .map_err(|e| format!("flush {filename}: {e}"))?;
    drop(writer);
    fs::rename(&tmp, dir.join(filename))
        .await
        .map_err(|e| format!("rename {filename}: {e}"))?;
    Ok(count)
}

/// Stream a JSONL file back into the DB, one row per line. Returns the number
/// of rows imported, or 0 if the file doesn't exist. Bad lines are skipped.
async fn restore_jsonl<T, F, Fut>(
    dir: &Path,
    filename: &str,
    label: &str,
    mut import: F,
) -> Result<u64, String>
where
    T: serde::de::DeserializeOwned,
    F: FnMut(T) -> Fut,
    Fut: std::future::Future<Output = Result<(), sqlx::Error>>,
{
    let path = dir.join(filename);
    let file = match fs::File::open(&path).await {
        Ok(f) => f,
        Err(_) => return Ok(0),
    };
    let mut lines = tokio::io::BufReader::new(file).lines();
    let mut count = 0u64;
    while let Some(line) = lines
        .next_line()
        .await
        .map_err(|e| format!("read {filename}: {e}"))?
    {
        if line.trim().is_empty() {
            continue;
        }
        let row: T = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                tracing::warn!("Snapshot restore: skipping bad {label} row: {e}");
                continue;
            }
        };
        import(row)
            .await
            .map_err(|e| format!("import {label}: {e}"))?;
        count += 1;
    }
    if count > 0 {
        tracing::info!(count, table = label, "Restored table from snapshot");
    }
    Ok(count)
}

/// Write an atomic JSON file (write to .tmp, then rename).
async fn write_json<T: Serialize>(dir: &Path, filename: &str, data: &T) -> std::io::Result<()> {
    let path = dir.join(filename);
    let tmp = dir.join(format!("{filename}.tmp"));
    let json = serde_json::to_string(data).map_err(std::io::Error::other)?;
    fs::write(&tmp, json.as_bytes()).await?;
    fs::rename(&tmp, &path).await?;
    Ok(())
}

/// Read a JSON file and deserialize it.
async fn read_json<T: serde::de::DeserializeOwned>(dir: &Path, filename: &str) -> Option<T> {
    let path = dir.join(filename);
    let bytes = fs::read(&path).await.ok()?;
    serde_json::from_slice(&bytes).ok()
}

/// Delete legacy whole-array .json snapshot files superseded by .jsonl.
async fn cleanup_legacy_json(dir: &Path) {
    for name in [
        "pota_parks.json",
        "pota_activations.json",
        "pota_hunter_qsos.json",
        "pota_fetch_status.json",
        "park_boundaries.json",
        "historic_trails.json",
    ] {
        let _ = fs::remove_file(dir.join(name)).await;
    }
}

// ---------------------------------------------------------------------------
// Snapshot save
// ---------------------------------------------------------------------------

/// Save a full snapshot to disk, streaming each table row-by-row. The
/// manifest is written last so its timestamp only advances once every table
/// file has been fully replaced.
pub async fn save_snapshot(pool: &PgPool, dir: &Path) -> Result<(), String> {
    fs::create_dir_all(dir)
        .await
        .map_err(|e| format!("create snapshot dir: {e}"))?;

    let parks = export_jsonl::<ParkSnapshot>(pool, dir, "pota_parks.jsonl", PARKS_SQL).await?;
    let activations =
        export_jsonl::<ActivationSnapshot>(pool, dir, "pota_activations.jsonl", ACTIVATIONS_SQL)
            .await?;
    let hunter_qsos =
        export_jsonl::<HunterQsoSnapshot>(pool, dir, "pota_hunter_qsos.jsonl", HUNTER_QSOS_SQL)
            .await?;
    let fetch_status =
        export_jsonl::<FetchStatusSnapshot>(pool, dir, "pota_fetch_status.jsonl", FETCH_STATUS_SQL)
            .await?;
    let boundaries =
        export_jsonl::<BoundarySnapshot>(pool, dir, "park_boundaries.jsonl", BOUNDARIES_SQL)
            .await?;
    let trails =
        export_jsonl::<TrailSnapshot>(pool, dir, "historic_trails.jsonl", TRAILS_SQL).await?;

    let manifest = SnapshotManifest {
        version: 2,
        created_at: Utc::now(),
        pota_parks_count: parks,
        pota_activations_count: activations,
        pota_hunter_qsos_count: hunter_qsos,
        pota_fetch_status_count: fetch_status,
        park_boundaries_count: boundaries,
        historic_trails_count: trails,
    };

    write_json(dir, "manifest.json", &manifest)
        .await
        .map_err(|e| format!("write manifest: {e}"))?;

    cleanup_legacy_json(dir).await;

    tracing::info!(
        parks,
        activations,
        hunter_qsos,
        boundaries,
        trails,
        "Snapshot saved to {}",
        dir.display()
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// Snapshot restore
// ---------------------------------------------------------------------------

/// Check if tables are empty (candidate for restore).
async fn tables_are_empty(pool: &PgPool) -> Result<bool, sqlx::Error> {
    let park_count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM pota_parks")
        .fetch_one(pool)
        .await?;
    let boundary_count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM park_boundaries")
        .fetch_one(pool)
        .await?;
    let trail_count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM historic_trails")
        .fetch_one(pool)
        .await?;
    Ok(park_count.0 == 0 && boundary_count.0 == 0 && trail_count.0 == 0)
}

/// Restore from the most recent snapshot if all target tables are empty and
/// the snapshot is within the configured max age.
pub async fn try_restore(pool: &PgPool, config: &Config) -> Result<bool, String> {
    let dir = PathBuf::from(&config.snapshot_dir);

    let manifest: SnapshotManifest = match read_json(&dir, "manifest.json").await {
        Some(m) => m,
        None => {
            tracing::info!("No snapshot manifest found, skipping restore");
            return Ok(false);
        }
    };

    // Check age
    let age = Utc::now() - manifest.created_at;
    let max_age = chrono::Duration::hours(config.snapshot_max_age_hours as i64);
    if age > max_age {
        tracing::info!(
            age_hours = age.num_hours(),
            max_hours = config.snapshot_max_age_hours,
            "Snapshot too old, skipping restore"
        );
        return Ok(false);
    }

    // Check if tables are empty
    let empty = tables_are_empty(pool)
        .await
        .map_err(|e| format!("check tables empty: {e}"))?;
    if !empty {
        tracing::info!("Tables already have data, skipping snapshot restore");
        return Ok(false);
    }

    tracing::info!(
        created_at = %manifest.created_at,
        age_hours = age.num_hours(),
        "Restoring from snapshot"
    );

    // Restore parks first (foreign key target)
    restore_jsonl(&dir, "pota_parks.jsonl", "pota_parks", |p| {
        import_park(pool, p)
    })
    .await?;

    restore_jsonl(&dir, "pota_fetch_status.jsonl", "pota_fetch_status", |r| {
        import_fetch_status(pool, r)
    })
    .await?;

    restore_jsonl(&dir, "pota_activations.jsonl", "pota_activations", |r| {
        import_activation(pool, r)
    })
    .await?;

    restore_jsonl(&dir, "pota_hunter_qsos.jsonl", "pota_hunter_qsos", |r| {
        import_hunter_qso(pool, r)
    })
    .await?;

    restore_jsonl(&dir, "park_boundaries.jsonl", "park_boundaries", |r| {
        import_boundary(pool, r)
    })
    .await?;

    restore_jsonl(&dir, "historic_trails.jsonl", "historic_trails", |r| {
        import_trail(pool, r)
    })
    .await?;

    tracing::info!("Snapshot restore complete");
    Ok(true)
}

// ---------------------------------------------------------------------------
// Background loop
// ---------------------------------------------------------------------------

/// Periodically save snapshots.
pub async fn snapshot_loop(pool: PgPool, config: Config) {
    let dir = PathBuf::from(&config.snapshot_dir);
    let interval = std::time::Duration::from_secs(config.snapshot_interval_hours * 3600);
    let mut ticker = tokio::time::interval(interval);

    // Skip the immediate first tick (let the server start up and aggregators populate data)
    ticker.tick().await;

    loop {
        ticker.tick().await;
        if let Err(e) = save_snapshot(&pool, &dir).await {
            tracing::error!("Snapshot save failed: {e}");
        }
    }
}
