//! Schema migrations, versioned via SQLite `user_version`.
//!
//! Mirrors the synced SwiftData entities. v1 added `qso`; v2 adds the remaining
//! synced `@Model` types (each entity owns its `CREATE TABLE` DDL as a
//! `pub(crate) const` next to its struct, assembled here).

use crate::error::Result;
use rusqlite::Connection;

/// Schema version the code understands. Bump when adding a migration step.
pub const SCHEMA_VERSION: i64 = 17;

/// DDL for the entities added in schema v2, in dependency-free order.
const V2_DDLS: &[&str] = &[
    crate::logging_session::LOGGING_SESSION_DDL,
    crate::service_presence::SERVICE_PRESENCE_DDL,
    crate::session_spot::SESSION_SPOT_DDL,
    crate::activation_metadata::ACTIVATION_METADATA_DDL,
    crate::activity_log::ACTIVITY_LOG_DDL,
    crate::equipment_item::EQUIPMENT_ITEM_DDL,
    crate::radio_macro::RADIO_MACRO_DDL,
    crate::websdr_recording::WEBSDR_RECORDING_DDL,
    crate::websdr_favorite::WEBSDR_FAVORITE_DDL,
    crate::upload_destination::UPLOAD_DESTINATION_DDL,
    crate::cloud_sync_metadata::CLOUD_SYNC_METADATA_DDL,
];

/// v3: `activation_metadata`'s primary key changed from `park_reference` to the
/// composite `(park_reference, date)` (one row per park per day). SQLite can't
/// alter a primary key in place, so rebuild the table. cw-store has no consumers
/// yet and is repopulated by the one-time importer, so dropping the rows is safe.
const V3_DDLS: &[&str] = &[
    "DROP TABLE IF EXISTS activation_metadata;",
    crate::activation_metadata::ACTIVATION_METADATA_DDL,
];

/// v4: `pota_park` reference table — park metadata (name/location/states) written
/// through from the `POTAParksCache` download so Rust awards/state aggregates can
/// resolve `qso.park` without the Swift cache. Reference data, not a synced entity.
const V4_DDLS: &[&str] = &[crate::pota_park::POTA_PARK_DDL];

/// v5: `club` + `club_member` cache tables — the user's amateur-radio clubs and
/// memberships served by `/v1/clubs`. Mirrors `Club.swift` / `ClubMember.swift`.
const V5_DDLS: &[&str] = &[crate::club::CLUB_DDL, crate::club_member::CLUB_MEMBER_DDL];

/// v6: `sync_kv` — local sync bookkeeping (clubs/membership ETags, future cursors).
const V6_DDLS: &[&str] = &[crate::sync_kv::SYNC_KV_DDL];

/// v7: `friendship` — the operator's social graph (accepted friends + pending
/// requests) served by `/v1/friends` and `/v1/friends/requests/pending`. Mirrors
/// `Friendship.swift`. The activity feed stays unpersisted (fetched on demand).
const V7_DDLS: &[&str] = &[crate::friendship::FRIENDSHIP_DDL];

/// v8: `rove_stop` — structured, portable rove-park stops. Normalises what iOS
/// kept as a Swift-`JSONEncoder` `[RoveStop]` blob on `logging_session.rove_stops_data`
/// (Date-as-2001-double, un-portable) into Unix-seconds rows so the POTA
/// UTC-midnight split and Android can manipulate them. The blob column stays for
/// the iOS transition; the table is the new source of truth (iOS backfills it).
const V8_DDLS: &[&str] = &[crate::rove_stop::ROVE_STOP_DDL];

/// v9: `contest_definition` — cache of the server's v0.3 contest definitions
/// (`/v1/contests`), replacing the iOS `ContestDefinitionsStore` JSON-file
/// cache. Summary columns for lists + the raw body for `cw_domain::contest`.
const V9_DDLS: &[&str] = &[crate::contest_definition::CONTEST_DEFINITION_DDL];

/// v10: SOTA/WWFF reference tables + SOTA activation zones — the remaining
/// External Data downloads move into the shared core (`ReferenceDataApi`).
/// `sota_summit` mirrors `SOTASummitsCache`, `wwff_reference` mirrors
/// `WWFFReferencesCache`, `sota_zone` mirrors the `SOTAZonesCache` disk file.
/// Reference data, not synced entities.
const V10_DDLS: &[&str] = &[
    crate::sota_summit::SOTA_SUMMIT_DDL,
    crate::wwff_reference::WWFF_REFERENCE_DDL,
    crate::sota_zone::SOTA_ZONE_DDL,
];

/// v11: `loadout` — equipment-only named collections (radio/antenna/key/mic +
/// radio_item_id), the portable replacement for the iOS `SavedSessionTemplate`
/// UserDefaults blob. Local/observed only — not part of the cloud sync dirty journal.
const V11_DDLS: &[&str] = &[crate::loadout::LOADOUT_DDL];

/// v12: `synced_config` — small per-type configuration blobs (e.g. the brag
/// sheet configuration) that ride the shared E2E sync dirty/push/pull journal
/// as the `syncedConfig` entity, LWW on `modified_at`. Unlike the local-only
/// `sync_kv` bookkeeping table, these rows sync across devices.
const V12_DDLS: &[&str] = &[crate::synced_config::SYNCED_CONFIG_DDL];

/// v13: `callbook_location` — cache of resolved callsign→lat/lon lookups
/// (QRZ/HamDB/grid-square fallback), replacing the iOS `CallbookLocationCache`
/// JSON-file cache. TTL-filtered at read time by the caller; local/observed
/// only — not part of the cloud sync dirty journal.
const V13_DDLS: &[&str] = &[crate::callbook_location::CALLBOOK_LOCATION_DDL];

/// v14: `gis_boundary_cache` — TTL-cached GeoJSON boundary geometry (park/
/// trail/admin polygons from `cw-net::boundaries`, plus SOTA activation
/// zones) keyed by `(kind, cache_key)`. Replaces per-kind ad-hoc disk caches
/// with one shared table for the map GIS layer. Local/observed only — not
/// part of the cloud sync dirty journal.
const V14_DDLS: &[&str] = &[crate::gis_cache::GIS_BOUNDARY_CACHE_DDL];

/// v15: `idx_qso_park_upper` — EXPRESSION index on `qso(UPPER(park))`. The POTA
/// activation rollup (`qso_activation_rollup`) and the activation-detail fetch
/// (`fetch_activation_qsos`) both compare `UPPER(park)`, which a plain
/// `qso(park)` index cannot serve (verified via EXPLAIN QUERY PLAN — a bare
/// column index leaves both queries on a full scan). No new table — an
/// index-only migration.
const V15_DDLS: &[&str] =
    &["CREATE INDEX IF NOT EXISTS idx_qso_park_upper ON qso(UPPER(park));"];

/// `ALTER TABLE ... ADD COLUMN`, skipped when the column already exists. Column
/// additions need this guard because entity DDLs carry the *current* schema: a
/// fresh database gets the column from the `CREATE TABLE` at `current < 1` and
/// would hit "duplicate column name" when the same `migrate()` pass reaches the
/// ALTER step.
fn add_column_if_missing(conn: &Connection, table: &str, column: &str, decl: &str) -> Result<()> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    let exists = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .filter_map(std::result::Result::ok)
        .any(|name| name == column);
    if !exists {
        conn.execute_batch(&format!("ALTER TABLE {table} ADD COLUMN {column} {decl};"))?;
    }
    Ok(())
}

/// Apply any pending migrations. Idempotent.
pub fn migrate(conn: &Connection) -> Result<()> {
    let current: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;

    if current < 1 {
        conn.execute_batch(crate::qso::QSO_DDL)?;
    }

    if current < 2 {
        for ddl in V2_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 3 {
        for ddl in V3_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 4 {
        for ddl in V4_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 5 {
        for ddl in V5_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 6 {
        for ddl in V6_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 7 {
        for ddl in V7_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 8 {
        for ddl in V8_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 9 {
        for ddl in V9_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 10 {
        for ddl in V10_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 11 {
        for ddl in V11_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 12 {
        for ddl in V12_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 13 {
        for ddl in V13_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 14 {
        for ddl in V14_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    if current < 15 {
        for ddl in V15_DDLS {
            conn.execute_batch(ddl)?;
        }
    }

    // v16: `qso.sat_name` + `qso.prop_mode` — first-class satellite logging
    // (ADIF SAT_NAME / PROP_MODE). First column addition to an existing table,
    // hence the guarded ALTERs instead of a DDL list.
    if current < 16 {
        add_column_if_missing(conn, "qso", "sat_name", "TEXT")?;
        add_column_if_missing(conn, "qso", "prop_mode", "TEXT")?;
    }

    // v17: `satellite_data_cache` — raw SatNOGS/AMSAT wire-JSON blobs (one
    // row per kind, 6 h TTL applied by the reader) backing the shared
    // SatelliteApi's cache-through refresh.
    if current < 17 {
        conn.execute_batch(crate::satellite_cache::SATELLITE_DATA_CACHE_DDL)?;
    }

    conn.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    Ok(())
}
