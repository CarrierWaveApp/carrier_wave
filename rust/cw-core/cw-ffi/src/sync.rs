//! Cross-entity sync-journal dirty-flag surface (`cw_store::sync_dirty`).
//!
//! `mark_all_dirty` / `clear_dirty` operate by `entity_type` — the Swift
//! `JournalEntityType` raw value (camelCase) — so the ported `CloudSyncJournalEngine`
//! seam drives them with the same identifier it already threads through the journal.

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};

/// Map a `JournalEntityType` raw value to the observation table whose rows the
/// dirty-flag op touched, so observers re-fetch. Unknown types (which the store
/// already rejected) yield `None` and skip the notification.
fn table_for(entity_type: &str) -> Option<FfiStoreTable> {
    match entity_type {
        "qso" => Some(FfiStoreTable::Qso),
        "servicePresence" => Some(FfiStoreTable::ServicePresence),
        "loggingSession" => Some(FfiStoreTable::LoggingSession),
        "activationMetadata" => Some(FfiStoreTable::ActivationMetadata),
        "sessionSpot" => Some(FfiStoreTable::SessionSpot),
        "activityLog" => Some(FfiStoreTable::ActivityLog),
        "radioMacro" => Some(FfiStoreTable::RadioMacro),
        "syncedConfig" => Some(FfiStoreTable::SyncedConfig),
        _ => None,
    }
}

#[uniffi::export]
impl FieldStore {
    /// Set the dirty flag on every row of `entity_type` (force full re-sync).
    /// Returns the number of rows marked. Port of `markAllRecordsDirty`'s
    /// per-entity pass (QSO excludes the WEATHER/SOLAR/NOTE metadata modes).
    pub fn mark_all_dirty(&self, entity_type: String) -> Result<i64, CwError> {
        let marked = {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.mark_all_dirty(&entity_type)?
        };
        if let Some(table) = table_for(&entity_type) {
            self.notify(FfiStoreChange { table, kind: FfiChangeKind::Upsert });
        }
        Ok(marked)
    }

    /// Clear the dirty flag for `ids` of `entity_type` — the outbound confirm
    /// step. Rows edited strictly after `not_if_modified_after` keep their flag
    /// (CAR-245). Returns the number of rows cleared.
    pub fn clear_dirty(
        &self,
        entity_type: String,
        ids: Vec<String>,
        not_if_modified_after: Option<i64>,
    ) -> Result<i64, CwError> {
        let cleared = {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.clear_dirty(&entity_type, &ids, not_if_modified_after)?
        };
        if cleared > 0 {
            if let Some(table) = table_for(&entity_type) {
                self.notify(FfiStoreChange { table, kind: FfiChangeKind::Upsert });
            }
        }
        Ok(cleared)
    }
}

#[cfg(test)]
mod tests {
    use crate::{FfiQso, FfiQsoFilter, FieldStore};

    fn dirty_qso(id: &str) -> FfiQso {
        FfiQso {
            id: id.into(),
            callsign: "W1AW".into(),
            band: Some("20m".into()),
            mode: Some("CW".into()),
            qso_date: 1000,
            dirty: true,
            ..Default::default()
        }
    }

    #[test]
    fn clear_dirty_round_trips_through_ffi() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        store.upsert_qso(dirty_qso("a")).unwrap();
        store.upsert_qso(dirty_qso("b")).unwrap();

        let cleared = store.clear_dirty("qso".into(), vec!["a".into()], None).unwrap();
        assert_eq!(cleared, 1);

        let still_dirty = store
            .fetch_qsos(FfiQsoFilter { dirty_only: true, ..Default::default() }, 100, 0)
            .unwrap();
        assert_eq!(still_dirty.iter().map(|q| q.id.clone()).collect::<Vec<_>>(), vec!["b"]);
    }

    #[test]
    fn mark_all_dirty_round_trips_through_ffi() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        // Insert clean (dirty=false) so mark_all_dirty has work to do.
        store.upsert_qso(FfiQso { dirty: false, ..dirty_qso("a") }).unwrap();
        store.upsert_qso(FfiQso { dirty: false, ..dirty_qso("b") }).unwrap();

        assert_eq!(store.mark_all_dirty("qso".into()).unwrap(), 2);
        let dirty = store
            .fetch_qsos(FfiQsoFilter { dirty_only: true, ..Default::default() }, 100, 0)
            .unwrap();
        assert_eq!(dirty.len(), 2);
    }

    #[test]
    fn unknown_entity_type_surfaces_store_error() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        assert!(store.mark_all_dirty("bogus".into()).is_err());
    }
}
