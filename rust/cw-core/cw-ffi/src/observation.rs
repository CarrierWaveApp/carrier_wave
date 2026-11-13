//! Store observation API — the UniFFI callback bridge that replaces SwiftData
//! `@Query` reactivity (migration plan §5, the flagged risk).
//!
//! Foreign code (Swift/Kotlin) implements [`StoreObserver`] and registers it via
//! [`FieldStore::add_observer`], receiving a token it later passes to
//! [`FieldStore::remove_observer`]. After any committed mutation the store calls
//! every observer's [`StoreObserver::on_change`] **with the store connection lock
//! released**, so an observer may re-enter the store to re-fetch (the typical
//! "refresh the SwiftUI view" path) without deadlocking. The Swift adapter turns
//! these callbacks into an `AsyncStream`/`@Observable` the view layer drives
//! `.task` refreshes from.
//!
//! Changes are coarse-grained (table + kind), not row diffs: an observer
//! re-fetches the affected table, mirroring how `@Query` invalidates an entire
//! result set rather than patching individual rows.

use std::sync::Arc;

use crate::FieldStore;

/// Which store table changed. One variant per `cw-store` entity.
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiStoreTable {
    Qso,
    LoggingSession,
    ServicePresence,
    SessionSpot,
    ActivationMetadata,
    ActivityLog,
    EquipmentItem,
    RadioMacro,
    WebSdrRecording,
    WebSdrFavorite,
    UploadDestination,
    CloudSyncMetadata,
    Club,
    ClubMember,
    Friendship,
    RoveStop,
    Loadout,
    SyncedConfig,
}

/// The kind of mutation that occurred.
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiChangeKind {
    Upsert,
    Delete,
}

/// A single store change delivered to observers.
#[derive(uniffi::Record, Clone, Copy)]
pub struct FfiStoreChange {
    pub table: FfiStoreTable,
    pub kind: FfiChangeKind,
}

/// Foreign-implementable observer. `with_foreign` lets Swift/Kotlin provide the
/// impl while Rust tests provide their own. Must be `Send + Sync` — UniFFI holds
/// the boxed observer across threads and the store calls it from whichever
/// thread performed the mutation.
#[uniffi::export(with_foreign)]
pub trait StoreObserver: Send + Sync {
    /// Invoked once per committed mutation, after the store connection lock is
    /// released. Safe to re-enter the store from here.
    fn on_change(&self, change: FfiStoreChange);
}

/// Token-keyed observer list. Lives behind its own `Mutex` on [`FieldStore`],
/// deliberately separate from the store connection lock so notifications never
/// hold the DB lock.
#[derive(Default)]
pub(crate) struct ObserverRegistry {
    next_token: u64,
    observers: Vec<(u64, Arc<dyn StoreObserver>)>,
}

impl ObserverRegistry {
    fn add(&mut self, observer: Arc<dyn StoreObserver>) -> u64 {
        let token = self.next_token;
        self.next_token += 1;
        self.observers.push((token, observer));
        token
    }

    fn remove(&mut self, token: u64) {
        self.observers.retain(|(existing, _)| *existing != token);
    }

    fn snapshot(&self) -> Vec<Arc<dyn StoreObserver>> {
        self.observers.iter().map(|(_, obs)| obs.clone()).collect()
    }
}

impl FieldStore {
    /// Notify every registered observer of `change`. **Call with no store
    /// connection lock held** — observers routinely re-enter the store to
    /// re-fetch. We snapshot the observer list under its own short-lived lock,
    /// then release it before invoking callbacks, so an observer that
    /// (de)registers observers during its callback can't deadlock either.
    pub(crate) fn notify(&self, change: FfiStoreChange) {
        let observers = {
            let registry = self.observers.lock().expect("observers mutex poisoned");
            registry.snapshot()
        };
        for observer in observers {
            observer.on_change(change);
        }
    }
}

#[uniffi::export]
impl FieldStore {
    /// Register `observer`; returns a token to pass to [`FieldStore::remove_observer`].
    /// The Swift adapter calls this on `init` and removes on `deinit`.
    pub fn add_observer(&self, observer: Arc<dyn StoreObserver>) -> u64 {
        let mut registry = self.observers.lock().expect("observers mutex poisoned");
        registry.add(observer)
    }

    /// Deregister a previously-added observer. Unknown tokens are ignored.
    pub fn remove_observer(&self, token: u64) {
        let mut registry = self.observers.lock().expect("observers mutex poisoned");
        registry.remove(token);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entities::service_presence::FfiServicePresence;
    use crate::FfiQso;
    use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};
    use std::sync::Weak;

    fn sample_qso(id: &str) -> FfiQso {
        FfiQso {
            id: id.into(),
            callsign: "W1AW".into(),
            band: Some("20m".into()),
            mode: Some("FT8".into()),
            freq_khz: Some(14_074.0),
            qso_date: 1000,
            dirty: true,
            ..Default::default()
        }
    }

    /// Records every change it receives.
    struct CountingObserver {
        count: AtomicUsize,
        last_table_is_qso: std::sync::atomic::AtomicBool,
        last_kind_is_delete: std::sync::atomic::AtomicBool,
    }

    impl StoreObserver for CountingObserver {
        fn on_change(&self, change: FfiStoreChange) {
            self.count.fetch_add(1, Ordering::SeqCst);
            self.last_table_is_qso
                .store(change.table == FfiStoreTable::Qso, Ordering::SeqCst);
            self.last_kind_is_delete
                .store(change.kind == FfiChangeKind::Delete, Ordering::SeqCst);
        }
    }

    #[test]
    fn observer_fires_on_qso_upsert() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        let observer = Arc::new(CountingObserver {
            count: AtomicUsize::new(0),
            last_table_is_qso: false.into(),
            last_kind_is_delete: false.into(),
        });
        store.add_observer(observer.clone());

        store.upsert_qso(sample_qso("1")).unwrap();
        store.upsert_qso(sample_qso("2")).unwrap();

        assert_eq!(observer.count.load(Ordering::SeqCst), 2);
        assert!(observer.last_table_is_qso.load(Ordering::SeqCst));
    }

    #[test]
    fn removed_observer_stops_firing() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        let observer = Arc::new(CountingObserver {
            count: AtomicUsize::new(0),
            last_table_is_qso: false.into(),
            last_kind_is_delete: false.into(),
        });
        let token = store.add_observer(observer.clone());

        store.upsert_qso(sample_qso("1")).unwrap();
        store.remove_observer(token);
        store.upsert_qso(sample_qso("2")).unwrap();

        assert_eq!(observer.count.load(Ordering::SeqCst), 1, "no fire after removal");
        // Removing an unknown token is a no-op, not a panic.
        store.remove_observer(9999);
    }

    /// Re-enters the store from inside its callback — the deadlock case the
    /// "notify with the lock released" design exists to prevent. If `notify`
    /// ran while holding `inner`, this `qso_count()` would deadlock forever.
    struct ReentrantObserver {
        store: Weak<FieldStore>,
        seen_count: AtomicI64,
    }

    impl StoreObserver for ReentrantObserver {
        fn on_change(&self, _change: FfiStoreChange) {
            if let Some(store) = self.store.upgrade() {
                let count = store.qso_count().expect("re-entrant count");
                self.seen_count.store(count, Ordering::SeqCst);
            }
        }
    }

    #[test]
    fn callback_can_reenter_store_without_deadlock() {
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        let observer = Arc::new(ReentrantObserver {
            store: Arc::downgrade(&store),
            seen_count: AtomicI64::new(-1),
        });
        store.add_observer(observer.clone());

        store.upsert_qso(sample_qso("1")).unwrap();

        // The callback ran, re-read the store mid-notification, and saw the
        // committed write (count == 1) — no deadlock, write already visible.
        assert_eq!(observer.seen_count.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn delete_qso_fires_delete_notification() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        store.upsert_qso(sample_qso("1")).unwrap();

        let observer = Arc::new(CountingObserver {
            count: AtomicUsize::new(0),
            last_table_is_qso: false.into(),
            last_kind_is_delete: false.into(),
        });
        let token = store.add_observer(observer.clone());

        store.delete_qso("1".into()).unwrap();

        assert_eq!(observer.count.load(Ordering::SeqCst), 1, "delete fires exactly one notification");
        assert!(observer.last_table_is_qso.load(Ordering::SeqCst), "notification table is Qso");
        assert!(observer.last_kind_is_delete.load(Ordering::SeqCst), "notification kind is Delete");
        assert_eq!(store.qso_count().unwrap(), 0, "QSO is gone from the store");

        store.remove_observer(token);
    }

    fn sample_ffi_service_presence(id: &str) -> FfiServicePresence {
        FfiServicePresence {
            id: id.into(),
            service_type_raw_value: "pota".into(),
            is_present: true,
            needs_upload: false,
            upload_rejected: false,
            rejected_at_build: None,
            is_submitted: false,
            last_confirmed_at: None,
            park_reference: Some("K-1234".into()),
            cloud_dirty_flag: false,
            qso_id: None,
        }
    }

    #[test]
    fn delete_service_presence_fires_delete_notification() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        store
            .upsert_service_presence(sample_ffi_service_presence("a"))
            .unwrap();

        let observer = Arc::new(CountingObserver {
            count: AtomicUsize::new(0),
            last_table_is_qso: false.into(),
            last_kind_is_delete: false.into(),
        });
        let token = store.add_observer(observer.clone());

        store.delete_service_presence("a".into()).unwrap();

        assert_eq!(observer.count.load(Ordering::SeqCst), 1, "delete fires exactly one notification");
        assert!(
            !observer.last_table_is_qso.load(Ordering::SeqCst),
            "notification table is ServicePresence, not Qso"
        );
        assert!(observer.last_kind_is_delete.load(Ordering::SeqCst), "notification kind is Delete");
        assert_eq!(store.service_presence_count().unwrap(), 0, "ServicePresence is gone from the store");

        store.remove_observer(token);
    }
}
