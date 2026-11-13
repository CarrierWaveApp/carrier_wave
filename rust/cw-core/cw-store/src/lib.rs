//! Carrier Wave encrypted entity store.
//!
//! SQLCipher-backed (encrypted at rest) SQLite store. The encryption key is
//! supplied by the host at open time (the platform keychain owns it — Rust never
//! does), passed straight to `PRAGMA key`. Exposes plain value types and a
//! bounded query API so the project's performance rules ("max 1,000 objects",
//! "always set a fetch limit") hold at the data layer, not just the UI.

pub mod activation_metadata;
pub mod adif_import;
pub mod analytics;
pub mod query;
pub mod activity_log;
pub mod callbook_location;
pub mod cloud_sync_metadata;
pub mod club;
pub mod club_member;
pub mod contest_definition;
pub mod equipment_item;
pub mod friendship;
pub mod error;
pub mod gis_cache;
pub mod loadout;
pub mod logging_session;
pub mod map_data;
pub mod migrations;
pub mod pota_awards;
pub mod pota_park;
pub mod qso;
pub mod radio_macro;
pub mod reference_search;
pub mod rove_stop;
pub mod satellite_cache;
pub mod service_presence;
pub mod session_spot;
pub mod sync_dirty;
pub mod sync_kv;
pub mod synced_config;
pub mod sota_summit;
pub mod sota_zone;
#[cfg(feature = "testing")]
pub mod testing;
pub mod upload_destination;
pub mod wwff_reference;
pub mod websdr_favorite;
pub mod websdr_recording;
pub mod wsjtx_import;

pub use activation_metadata::{ActivationMetadata, ActivationMetadataFilter};
pub use analytics::{
    normalized_valid_state, ActivationRollup, AggregateDimension, BragBandRecord,
    BragBestActivation, BragContact, BragDistanceStats, BragEfficiency, BragGeographic,
    BragPeriodMetrics, BragPota, BragPowerContact, BragRecords,
    BragSessionStats, BragStreaks, DimensionCount, DistinctCounts, DxccWorked, GridTile, ItemTally,
    ModeStreak, ParkRollup,
    ServicePresenceCount, SessionComboRollup, SessionEquipmentRollup, SessionItemDetail,
    StateCount, StreakValue, Was250, WasDrilldownRow, WasModeStates, WasSummary,
};
pub use activity_log::{ActivityLog, ActivityLogFilter};
pub use callbook_location::CallbookLocation;
pub use cloud_sync_metadata::{CloudSyncMetadata, CloudSyncMetadataFilter};
pub use club::{Club, ClubFilter};
pub use club_member::{ClubMember, ClubMemberFilter};
pub use contest_definition::ContestDefinitionRow;
pub use equipment_item::{EquipmentItem, EquipmentItemFilter, EquipmentSort};
pub use error::{Result, StoreError};
pub use friendship::{Friendship, FriendshipFilter, STATUS_ACCEPTED, STATUS_PENDING};
pub use gis_cache::{
    GIS_CACHE_CAP_ADMIN, GIS_CACHE_CAP_PARK, GIS_CACHE_CAP_TRAIL, GIS_CACHE_TTL_SECS,
};
pub use adif_import::{filter_for_multi_op, strip_portable_suffix, ADIF_FILE_IMPORT_SOURCE};
pub use loadout::Loadout;
pub use logging_session::{LoggingSession, LoggingSessionFilter};
pub use map_data::{MapFilterOptions, MapQsoRow, TimelineQsoRow};
pub use pota_awards::{NearKiloPark, PotaAwards};
pub use pota_park::PotaPark;
pub use qso::{DupeCandidate, Qso, QsoFilter, MAX_FETCH_LIMIT};
pub use radio_macro::{RadioMacro, RadioMacroFilter};
pub use reference_search::{RefKind, RefSearchHit};
pub use rove_stop::RoveStop;
pub use service_presence::{ServicePresence, ServicePresenceFilter};
pub use session_spot::{SessionSpot, SessionSpotFilter};
pub use synced_config::{synced_config_id, SyncedConfig};
pub use sota_zone::SotaZoneRow;
pub use upload_destination::UploadDestination;
pub use websdr_favorite::WebSDRFavorite;
pub use websdr_recording::{WebSDRRecording, WebSDRRecordingFilter};
pub use wsjtx_import::{
    qso_from_adif_record, qso_from_logged_adif, qso_from_qso_logged, wsjtx_dedup_key,
    wsjtx_qso_id, WsjtxImportContext, WsjtxImportError, WSJTX_IMPORT_SOURCE,
    WSJTX_QSO_NAMESPACE,
};

use rusqlite::Connection;
use std::path::Path;

/// An open, encrypted store.
pub struct Store {
    pub(crate) conn: Connection,
}

impl Store {
    /// Open (or create) an encrypted database at `path` with the given key.
    /// A wrong key surfaces as a `StoreError::Sqlite` on first access.
    pub fn open(path: impl AsRef<Path>, key: &str) -> Result<Self> {
        Self::open_with_vfs(path, key, None)
    }

    /// Open through an explicit VFS (test fault-injection); `None` = default VFS.
    pub fn open_with_vfs(path: impl AsRef<Path>, key: &str, vfs: Option<&str>) -> Result<Self> {
        use rusqlite::OpenFlags;
        let flags = OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_CREATE
            | OpenFlags::SQLITE_OPEN_URI | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let conn = match vfs {
            Some(name) => Connection::open_with_flags_and_vfs(path, flags, name)?,
            None => Connection::open_with_flags(path, flags)?,
        };
        Self::key_and_migrate(conn, key)
    }

    /// Open an encrypted in-memory store (tests / ephemeral use).
    pub fn open_in_memory(key: &str) -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        Self::key_and_migrate(conn, key)
    }

    fn key_and_migrate(conn: Connection, key: &str) -> Result<Self> {
        // SQLCipher: set the key before any other access. `pragma_update`
        // quotes the value, so an arbitrary passphrase is safe.
        conn.pragma_update(None, "key", key)?;
        // Force a read so a wrong key fails fast ("file is not a database").
        let _: i64 = conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| row.get(0))?;
        // Register cw_lower UDF on every connection so query compilation is
        // case-insensitive at the SQL level, matching Swift String.lowercased().
        crate::query::sql::register_cw_lower(&conn)?;
        // Mode-family classifier UDF, used by the analytics aggregates to GROUP BY
        // mode family at the SQL level (reuses cw-domain's classification).
        crate::query::sql::register_cw_mode_family(&conn)?;
        // Grid-distance UDF (great-circle km between two Maidenhead locators), used by
        // the per-item / brag distance aggregates. Reuses cw-domain's haversine.
        crate::query::sql::register_cw_grid_distance_km(&conn)?;
        // Continent classifier UDF (DXCC entity → continent), used by the brag geographic
        // aggregate. Reuses cw-domain's ContinentMapper port.
        crate::query::sql::register_cw_continent(&conn)?;
        // Canonical-mode UDF (raw mode → canonical name), used by the brag records aggregate
        // (active modes / busiest mode). Reuses cw-domain's ModeEquivalence.
        crate::query::sql::register_cw_mode_canonical(&conn)?;
        // RST strength-digit UDF (rst_rcvd → S digit), used by the brag averageRST aggregate.
        // Replicates BragSheetComputationActor.computeAverageRST's digit logic.
        crate::query::sql::register_cw_rst_s(&conn)?;
        Self::apply_durability_pragmas(&conn)?;
        migrations::migrate(&conn)?;
        Ok(Store { conn })
    }

    /// Durability-critical pragmas, set explicitly so the guarantee is
    /// regression-proof rather than riding on SQLite defaults.
    ///
    /// `journal_mode = DELETE` (rollback journal) + `synchronous = FULL` is
    /// power-loss durable: a returned COMMIT has fsync'd journal then db.
    /// Do NOT switch to WAL without `synchronous = FULL` + checkpoint
    /// discipline, or the last commit is silently lost on power loss.
    /// `fullfsync` makes fsync issue F_FULLFSYNC on Apple platforms (flush the
    /// drive write cache); it is a harmless no-op elsewhere.
    fn apply_durability_pragmas(conn: &Connection) -> Result<()> {
        conn.busy_timeout(std::time::Duration::from_millis(5_000))?;
        conn.pragma_update(None, "synchronous", "FULL")?;
        conn.pragma_update(None, "fullfsync", "ON")?;
        // In-memory dbs reject journal_mode=DELETE; only set it for file-backed.
        let is_memory: bool = conn
            .query_row("PRAGMA journal_mode", [], |r| r.get::<_, String>(0))
            .map(|m| m.eq_ignore_ascii_case("memory"))
            .unwrap_or(false);
        if !is_memory {
            conn.pragma_update(None, "journal_mode", "DELETE")?;
        }
        Ok(())
    }

    /// Test-only: raise this connection's busy_timeout (e.g. for high-contention
    /// torture tests that would otherwise exceed the production 5s default).
    #[cfg(feature = "testing")]
    pub fn set_busy_timeout(&self, ms: u32) -> Result<()> {
        self.conn.busy_timeout(std::time::Duration::from_millis(u64::from(ms)))?;
        Ok(())
    }

    /// Run `PRAGMA cipher_integrity_check` and return the first row
    /// (`"ok"` when the database is clean, mirroring `PRAGMA integrity_check`).
    pub fn integrity_check(&self) -> Result<String> {
        let mut stmt = self.conn.prepare("PRAGMA cipher_integrity_check")?;
        let mut rows = stmt.query([])?;
        match rows.next()? {
            Some(r) => Ok(r.get::<_, String>(0)?),
            None => Ok("ok".into()),
        }
    }

    /// Whether the underlying SQLite was built with SQLCipher (encryption).
    pub fn is_encrypted_build(&self) -> bool {
        self.conn
            .query_row("PRAGMA cipher_version", [], |row| row.get::<_, String>(0))
            .map(|version| !version.is_empty())
            .unwrap_or(false)
    }

    /// Re-encrypt the open database in place with `new_key` (SQLCipher
    /// `PRAGMA rekey`). The connection must already be open with the *current*
    /// key. `pragma_update` quotes the value, so an arbitrary passphrase is
    /// safe. On success every subsequent access on this connection uses the new
    /// key, and the file on disk is re-encrypted.
    ///
    /// SAFETY: `PRAGMA rekey` rewrites every page in place and is **not**
    /// crash-atomic — a power loss mid-rekey can leave a partially re-encrypted,
    /// unopenable file. Only run this against a store you can rebuild from
    /// another source (as cw-store is, from SwiftData), or copy-then-swap first.
    /// Currently unused (the recovery path wraps the existing key rather than
    /// changing it); reserved for a future passphrase-rotation-with-new-key.
    pub fn rekey(&self, new_key: &str) -> Result<()> {
        self.conn.pragma_update(None, "rekey", new_key)?;
        Ok(())
    }

    /// Run `body` inside a single SQLite transaction: one journal + fsync cycle
    /// for the whole batch instead of one per statement. With `synchronous =
    /// FULL` + `fullfsync` a per-row autocommit costs two F_FULLFSYNC barriers
    /// per row, which is what made bulk seeding block for minutes; batching
    /// collapses that to one commit. Rolls back if `body` errors.
    ///
    /// Uses `unchecked_transaction` because `Store` holds the connection behind
    /// `&self`; nested calls would fail at runtime (SQLite has no nested BEGIN),
    /// so `body` must only issue plain statements.
    pub fn in_transaction<T>(&self, body: impl FnOnce() -> Result<T>) -> Result<T> {
        self.in_transaction_with(body)
    }

    /// [`in_transaction`](Self::in_transaction) for bodies that return a
    /// different error type (e.g. cw-ffi's `CwError`), as long as it can absorb
    /// a [`StoreError`] from the BEGIN/COMMIT themselves.
    pub fn in_transaction_with<T, E: From<StoreError>>(
        &self,
        body: impl FnOnce() -> std::result::Result<T, E>,
    ) -> std::result::Result<T, E> {
        let txn = self.conn.unchecked_transaction().map_err(StoreError::from)?;
        let out = body()?;
        txn.commit().map_err(StoreError::from)?;
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::qso::Qso;

    pub(crate) fn sample_qso(id: &str, call: &str, band: &str, when: i64) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: call.to_string(),
            band: Some(band.to_string()),
            mode: Some("FT8".to_string()),
            freq_khz: Some(14_074.0),
            qso_date: when,
            my_grid: Some("FN31".to_string()),
            their_grid: Some("EM12".to_string()),
            rst_sent: Some("-10".to_string()),
            rst_rcvd: Some("-12".to_string()),
            my_callsign: Some("W1XYZ".to_string()),
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: when,
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
    fn build_is_sqlcipher() {
        let store = Store::open_in_memory("test-key").unwrap();
        assert!(store.is_encrypted_build(), "expected a SQLCipher build");
    }

    #[test]
    fn in_transaction_commits_batch() {
        let store = Store::open_in_memory("test-key").unwrap();
        store
            .in_transaction(|| {
                store.upsert_qso(&sample_qso("a", "W1AW", "20m", 1))?;
                store.upsert_qso(&sample_qso("b", "K2XX", "40m", 2))?;
                Ok(())
            })
            .unwrap();
        assert_eq!(store.qso_count().unwrap(), 2);
    }

    #[test]
    fn in_transaction_rolls_back_on_error() {
        let store = Store::open_in_memory("test-key").unwrap();
        let result: Result<()> = store.in_transaction(|| {
            store.upsert_qso(&sample_qso("a", "W1AW", "20m", 1))?;
            Err(StoreError::Sqlite(rusqlite::Error::InvalidQuery))
        });
        assert!(result.is_err());
        assert_eq!(store.qso_count().unwrap(), 0, "failed batch must not persist rows");
    }

    #[test]
    fn upsert_count_and_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&sample_qso("1", "W1AW", "20m", 1000)).unwrap();
        store.upsert_qso(&sample_qso("2", "K2ABC", "40m", 2000)).unwrap();
        store.upsert_qso(&sample_qso("3", "W1XYZ", "20m", 3000)).unwrap();
        assert_eq!(store.qso_count().unwrap(), 3);

        // Newest first, band filter.
        let twenty = store
            .fetch_qsos(&QsoFilter { band: Some("20m".into()), ..Default::default() }, 100, 0)
            .unwrap();
        assert_eq!(twenty.len(), 2);
        assert_eq!(twenty[0].id, "3"); // qso_date DESC

        // Callsign prefix is case-insensitive / uppercased.
        let w1 = store
            .fetch_qsos(&QsoFilter { callsign_prefix: Some("w1".into()), ..Default::default() }, 100, 0)
            .unwrap();
        assert_eq!(w1.len(), 2);
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&sample_qso("1", "W1AW", "20m", 1000)).unwrap();
        let mut updated = sample_qso("1", "W1AW", "40m", 1000);
        updated.notes = Some("edited".into());
        store.upsert_qso(&updated).unwrap();
        assert_eq!(store.qso_count().unwrap(), 1);
        let rows = store.fetch_qsos(&QsoFilter::default(), 10, 0).unwrap();
        assert_eq!(rows[0].band.as_deref(), Some("40m"));
        assert_eq!(rows[0].notes.as_deref(), Some("edited"));
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store.fetch_qsos(&QsoFilter::default(), MAX_FETCH_LIMIT + 1, 0).unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn wrong_key_fails_on_disk() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("log.db");
        {
            let store = Store::open(&path, "correct-horse").unwrap();
            store.upsert_qso(&sample_qso("1", "W1AW", "20m", 1000)).unwrap();
        }
        // Reopen with the right key: works.
        {
            let store = Store::open(&path, "correct-horse").unwrap();
            assert_eq!(store.qso_count().unwrap(), 1);
        }
        // Reopen with the wrong key: fails (encrypted at rest).
        let wrong = Store::open(&path, "battery-staple");
        assert!(wrong.is_err(), "wrong key must not open an encrypted db");
    }

    #[test]
    fn rekey_reencrypts_in_place() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("log.db");
        // Create under the legacy key and write a row.
        {
            let store = Store::open(&path, "old-random-key").unwrap();
            store.upsert_qso(&sample_qso("1", "W1AW", "20m", 1000)).unwrap();
            // Rekey in place to the new (escrow-derived) key; data survives on
            // the same connection.
            store.rekey("new-escrow-key").unwrap();
            assert_eq!(store.qso_count().unwrap(), 1);
        }
        // Reopen with the NEW key: works, data intact.
        {
            let store = Store::open(&path, "new-escrow-key").unwrap();
            assert_eq!(store.qso_count().unwrap(), 1);
        }
        // Reopen with the OLD key: fails — the file is re-encrypted.
        assert!(
            Store::open(&path, "old-random-key").is_err(),
            "old key must not open a rekeyed db"
        );
    }

    #[test]
    fn durability_pragmas_are_set() {
        let store = Store::open_in_memory("k").unwrap();
        let sync: i64 = store.conn.query_row("PRAGMA synchronous", [], |r| r.get(0)).unwrap();
        assert_eq!(sync, 2, "synchronous must be FULL (2)");
        let busy: i64 = store.conn.query_row("PRAGMA busy_timeout", [], |r| r.get(0)).unwrap();
        assert_eq!(busy, 5_000, "busy_timeout must be 5000ms");
        // In-memory journal_mode reports "memory"; on disk it must be "delete".
    }

    #[test]
    fn journal_mode_is_delete_on_disk() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(dir.path().join("log.db"), "k").unwrap();
        let mode: String = store.conn.query_row("PRAGMA journal_mode", [], |r| r.get(0)).unwrap();
        assert_eq!(mode.to_lowercase(), "delete");
    }

    #[test]
    fn concurrent_writers_serialize_without_busy() {
        use std::sync::Arc;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("log.db");
        Store::open(&path, "k").unwrap(); // create
        let path = Arc::new(path);
        let handles: Vec<_> = (0..4).map(|t| {
            let path = Arc::clone(&path);
            std::thread::spawn(move || {
                let store = Store::open(&*path, "k").unwrap();
                for i in 0..50 {
                    store.upsert_qso(&super::tests::sample_qso(&format!("{t}-{i}"), "W1AW", "20m", 1000)).unwrap();
                }
            })
        }).collect();
        for h in handles { h.join().unwrap(); }
        let store = Store::open(&*path, "k").unwrap();
        assert_eq!(store.qso_count().unwrap(), 200);
    }
}
