//! Bulk sync-journal dirty-flag operations, shared by every synced entity.
//!
//! Ports the cross-entity halves of the Swift `CloudSyncJournalEngine`:
//!   - [`Store::mark_all_dirty`] mirrors `+MarkAllDirty.swift`'s per-entity
//!     "force full re-sync" flag set (QSO excludes the WEATHER/SOLAR/NOTE
//!     metadata pseudo-modes, exactly like `markAllRecordsDirty`).
//!   - [`Store::clear_dirty`] mirrors `+Outbound.swift`'s `clearDirtyFlag`
//!     confirm-step, including the CAR-245 "skip if locally newer" guard: a row
//!     edited after the journal snapshot (`modified_col > not_if_modified_after`)
//!     keeps its dirty flag so the newer write flushes on the next outbound pass.
//!
//! `entity_type` is the Swift `JournalEntityType` raw value (camelCase: `qso`,
//! `servicePresence`, `loggingSession`, `activationMetadata`, `sessionSpot`,
//! `activityLog`, `radioMacro`, `syncedConfig`) — the sync-side identifier,
//! distinct from the PascalCase class names stored in
//! `cloud_sync_metadata.entity_type`.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;

/// Static table metadata for one synced entity's dirty flag.
struct SyncEntity {
    /// SQL table name.
    table: &'static str,
    /// The dirty-flag column (`dirty` for QSO, `cloud_dirty_flag` elsewhere).
    dirty_col: &'static str,
    /// The single-column primary key used by [`Store::clear_dirty`]'s id list.
    /// `None` for `activationMetadata`, which is keyed on `(park_reference, date)`
    /// — its confirm step is a no-op in Swift (`clearDirtyFlag` `break`s on it).
    id_col: Option<&'static str>,
    /// The "last local edit" column backing the CAR-245 newer-than-snapshot
    /// guard. `Some` only for entities Swift guards (`qso` / `radioMacro`).
    modified_col: Option<&'static str>,
    /// QSO alone skips the WEATHER/SOLAR/NOTE metadata pseudo-modes when marking
    /// all dirty (`markAllRecordsDirty`).
    exclude_metadata_modes: bool,
}

/// Resolve a `JournalEntityType` raw value to its table metadata, or
/// `UnknownSyncEntity` for anything outside the synced set.
fn resolve(entity_type: &str) -> Result<SyncEntity> {
    let entity = match entity_type {
        "qso" => SyncEntity {
            table: "qso",
            dirty_col: "dirty",
            id_col: Some("id"),
            modified_col: Some("modified_at"),
            exclude_metadata_modes: true,
        },
        "servicePresence" => SyncEntity {
            table: "service_presence",
            dirty_col: "cloud_dirty_flag",
            id_col: Some("id"),
            modified_col: None,
            exclude_metadata_modes: false,
        },
        "loggingSession" => SyncEntity {
            table: "logging_session",
            dirty_col: "cloud_dirty_flag",
            id_col: Some("id"),
            modified_col: None,
            exclude_metadata_modes: false,
        },
        "activationMetadata" => SyncEntity {
            table: "activation_metadata",
            dirty_col: "cloud_dirty_flag",
            id_col: None,
            modified_col: None,
            exclude_metadata_modes: false,
        },
        "sessionSpot" => SyncEntity {
            table: "session_spot",
            dirty_col: "cloud_dirty_flag",
            id_col: Some("id"),
            modified_col: None,
            exclude_metadata_modes: false,
        },
        "activityLog" => SyncEntity {
            table: "activity_log",
            dirty_col: "cloud_dirty_flag",
            id_col: Some("id"),
            modified_col: None,
            exclude_metadata_modes: false,
        },
        "radioMacro" => SyncEntity {
            table: "radio_macro",
            dirty_col: "cloud_dirty_flag",
            id_col: Some("id"),
            modified_col: Some("updated_at"),
            exclude_metadata_modes: false,
        },
        "syncedConfig" => SyncEntity {
            table: "synced_config",
            dirty_col: "cloud_dirty_flag",
            id_col: Some("id"),
            modified_col: Some("modified_at"),
            exclude_metadata_modes: false,
        },
        other => {
            return Err(StoreError::UnknownSyncEntity { entity_type: other.to_string() });
        }
    };
    Ok(entity)
}

impl Store {
    /// Set the dirty flag on every row of `entity_type` (force a full re-sync).
    /// QSO skips the metadata pseudo-modes, matching `markAllRecordsDirty`.
    /// Returns the number of rows marked.
    pub fn mark_all_dirty(&self, entity_type: &str) -> Result<i64> {
        let entity = resolve(entity_type)?;
        let mut sql = format!("UPDATE {} SET {} = 1", entity.table, entity.dirty_col);
        if entity.exclude_metadata_modes {
            sql.push_str(" WHERE mode IS NULL OR mode NOT IN ('WEATHER', 'SOLAR', 'NOTE')");
        }
        let marked = self.conn.execute(&sql, [])?;
        Ok(marked as i64)
    }

    /// Clear the dirty flag for the given `ids` of `entity_type` — the outbound
    /// confirm step after CloudKit accepts the records.
    ///
    /// When the entity has a "last local edit" column and `not_if_modified_after`
    /// is `Some`, rows edited strictly after that snapshot timestamp keep their
    /// dirty flag (CAR-245), so the newer write flushes on the next pass.
    ///
    /// `activationMetadata` is keyed on `(park_reference, date)`, not a single id;
    /// its confirm step is a no-op (returns 0), mirroring the Swift `break`. An
    /// empty `ids` list is a no-op. `ids.len()` must be ≤ [`MAX_FETCH_LIMIT`].
    /// Returns the number of rows cleared.
    pub fn clear_dirty(
        &self,
        entity_type: &str,
        ids: &[String],
        not_if_modified_after: Option<i64>,
    ) -> Result<i64> {
        let entity = resolve(entity_type)?;
        let Some(id_col) = entity.id_col else {
            // Not single-id-keyed (activationMetadata) — no-op, like Swift.
            return Ok(0);
        };
        if ids.is_empty() {
            return Ok(0);
        }
        if ids.len() as i64 > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded {
                requested: ids.len() as i64,
                max: MAX_FETCH_LIMIT,
            });
        }

        let placeholders = vec!["?"; ids.len()].join(", ");
        let mut sql = format!(
            "UPDATE {} SET {} = 0 WHERE {} IN ({})",
            entity.table, entity.dirty_col, id_col, placeholders
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> =
            ids.iter().map(|id| Box::new(id.clone()) as Box<dyn rusqlite::types::ToSql>).collect();

        // CAR-245 guard: keep rows the user edited after the journal snapshot.
        if let (Some(modified_col), Some(cutoff)) = (entity.modified_col, not_if_modified_after) {
            sql.push_str(&format!(
                " AND NOT ({modified_col} IS NOT NULL AND {modified_col} > ?)"
            ));
            args.push(Box::new(cutoff));
        }

        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let cleared = self.conn.execute(&sql, arg_refs.as_slice())?;
        Ok(cleared as i64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::activity_log::ActivityLog;
    use crate::qso::{Qso, QsoFilter};
    use crate::session_spot::{SessionSpot, SessionSpotFilter};

    fn qso(id: &str, mode: Option<&str>, dirty: bool, modified_at: Option<i64>) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: "W1AW".to_string(),
            band: Some("20m".to_string()),
            mode: mode.map(str::to_string),
            freq_khz: Some(14_074.0),
            qso_date: 1000,
            my_grid: None,
            their_grid: None,
            rst_sent: None,
            rst_rcvd: None,
            my_callsign: None,
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: 1000,
            modified_at,
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
            dirty,
            sat_name: None,
            prop_mode: None,
        }
    }

    fn dirty_qso_ids(store: &Store) -> Vec<String> {
        let mut ids = store
            .fetch_qsos(&QsoFilter { dirty_only: true, ..Default::default() }, MAX_FETCH_LIMIT, 0)
            .unwrap()
            .into_iter()
            .map(|q| q.id)
            .collect::<Vec<_>>();
        ids.sort();
        ids
    }

    #[test]
    fn unknown_entity_type_errors() {
        let store = Store::open_in_memory("k").unwrap();
        assert!(matches!(
            store.mark_all_dirty("bogus"),
            Err(StoreError::UnknownSyncEntity { .. })
        ));
        assert!(matches!(
            store.clear_dirty("bogus", &["a".into()], None),
            Err(StoreError::UnknownSyncEntity { .. })
        ));
    }

    #[test]
    fn mark_all_dirty_qso_excludes_metadata_modes() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&qso("a", Some("CW"), false, None)).unwrap();
        store.upsert_qso(&qso("b", Some("SSB"), false, None)).unwrap();
        store.upsert_qso(&qso("meta", Some("WEATHER"), false, None)).unwrap();

        let marked = store.mark_all_dirty("qso").unwrap();
        assert_eq!(marked, 2, "metadata-mode QSO is left clean");
        assert_eq!(dirty_qso_ids(&store), vec!["a", "b"]);
    }

    #[test]
    fn mark_all_dirty_non_qso_marks_every_row() {
        let store = Store::open_in_memory("k").unwrap();
        let mk = |id: &str| ActivityLog {
            id: id.to_string(),
            name: format!("Log {id}"),
            my_callsign: "W6JY".to_string(),
            created_at: 1000,
            station_profile_id: None,
            current_grid: None,
            location_label: None,
            is_active: true,
            cloud_dirty_flag: false,
        };
        store.upsert_activity_log(&mk("l1")).unwrap();
        store.upsert_activity_log(&mk("l2")).unwrap();

        assert_eq!(store.mark_all_dirty("activityLog").unwrap(), 2);
        let dirty = store
            .fetch_activity_logs(
                &crate::activity_log::ActivityLogFilter { dirty_only: true, ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert_eq!(dirty.len(), 2);
    }

    #[test]
    fn clear_dirty_clears_listed_ids_only() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&qso("a", Some("CW"), true, None)).unwrap();
        store.upsert_qso(&qso("b", Some("CW"), true, None)).unwrap();
        store.upsert_qso(&qso("c", Some("CW"), true, None)).unwrap();

        let cleared = store.clear_dirty("qso", &["a".into(), "b".into()], None).unwrap();
        assert_eq!(cleared, 2);
        assert_eq!(dirty_qso_ids(&store), vec!["c"], "only unlisted 'c' stays dirty");
    }

    #[test]
    fn clear_dirty_keeps_rows_modified_after_snapshot() {
        let store = Store::open_in_memory("k").unwrap();
        // "edited" was modified at t=200, after the snapshot at t=100; "stale"
        // at t=50, before it.
        store.upsert_qso(&qso("edited", Some("CW"), true, Some(200))).unwrap();
        store.upsert_qso(&qso("stale", Some("CW"), true, Some(50))).unwrap();
        store.upsert_qso(&qso("null_mod", Some("CW"), true, None)).unwrap();

        let cleared = store
            .clear_dirty(
                "qso",
                &["edited".into(), "stale".into(), "null_mod".into()],
                Some(100),
            )
            .unwrap();
        assert_eq!(cleared, 2, "stale + null_mod cleared; edited kept");
        assert_eq!(dirty_qso_ids(&store), vec!["edited"]);
    }

    #[test]
    fn clear_dirty_without_cutoff_ignores_modified_guard() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&qso("edited", Some("CW"), true, Some(999))).unwrap();
        // No cutoff → guard does not apply, row clears regardless of modified_at.
        assert_eq!(store.clear_dirty("qso", &["edited".into()], None).unwrap(), 1);
        assert!(dirty_qso_ids(&store).is_empty());
    }

    #[test]
    fn clear_dirty_activation_metadata_is_noop() {
        let store = Store::open_in_memory("k").unwrap();
        // No id column → no-op, mirroring the Swift `break`.
        assert_eq!(store.clear_dirty("activationMetadata", &["anything".into()], None).unwrap(), 0);
    }

    #[test]
    fn clear_dirty_empty_ids_is_noop() {
        let store = Store::open_in_memory("k").unwrap();
        assert_eq!(store.clear_dirty("qso", &[], None).unwrap(), 0);
    }

    #[test]
    fn clear_dirty_rejects_oversized_id_list() {
        let store = Store::open_in_memory("k").unwrap();
        let ids: Vec<String> = (0..=MAX_FETCH_LIMIT).map(|i| i.to_string()).collect();
        assert!(matches!(
            store.clear_dirty("qso", &ids, None),
            Err(StoreError::FetchLimitExceeded { .. })
        ));
    }

    #[test]
    fn clear_dirty_session_spot_uses_cloud_dirty_flag() {
        let store = Store::open_in_memory("k").unwrap();
        let mut spot = SessionSpot {
            id: "s1".to_string(),
            logging_session_id: "sess".to_string(),
            callsign: "W1AW".to_string(),
            frequency_k_hz: 14_074.0,
            mode: "FT8".to_string(),
            timestamp: 1000,
            source: "pota".to_string(),
            snr: None,
            wpm: None,
            spotter: None,
            spotter_grid: None,
            park_ref: None,
            park_name: None,
            comments: None,
            region: "NA".to_string(),
            distance_meters: None,
            bearing_degrees: None,
            cloud_dirty_flag: true,
        };
        store.upsert_session_spot(&spot).unwrap();
        spot.id = "s2".to_string();
        store.upsert_session_spot(&spot).unwrap();

        assert_eq!(store.clear_dirty("sessionSpot", &["s1".into()], None).unwrap(), 1);
        let still_dirty = store
            .fetch_session_spots(
                &SessionSpotFilter { dirty_only: true, ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert_eq!(still_dirty.iter().map(|s| s.id.clone()).collect::<Vec<_>>(), vec!["s2"]);
    }
}
