//! Async clubs API — the first networking exposed over UniFFI.
//!
//! `ClubsApi` wraps `cw_net::ClubsClient` and the encrypted store: it fetches
//! from the activities server, parses, writes the cache, reconciles deletes, and
//! manages the clubs/membership ETags — all in Rust, so iOS and Android share
//! the entire sync path and the host only supplies a bearer token. Methods are
//! exported with `async_runtime = "tokio"`, the mechanism that lets the
//! reqwest-backed futures run on a tokio reactor.
//!
//! Locking discipline mirrors the rest of the store surface: network I/O happens
//! with **no** lock held, then writes apply in bounded-size critical sections
//! (`APPLY_CHUNK_ROWS` per transaction — a single multi-second hold starves
//! main-thread store writes into a watchdog kill) and the change notification
//! fires after the lock is released. No `MutexGuard` is ever held across an
//! `.await`, so the futures stay `Send`.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use chrono::Utc;
use cw_net::{
    ClubActivityResponseWire, ClubDetailWire, ClubMemberWire, ClubMembershipEntryWire, ClubWire,
    ClubsClient, Conditional, HttpClient, MemberOnlineStatusWire, MemberStatusWire,
};
use cw_store::{Club, ClubFilter, ClubMember, Store, MAX_FETCH_LIMIT};

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};

const CLUBS_ETAG_KEY: &str = "clubs_etag";
const MEMBERSHIP_ETAG_KEY: &str = "membership_etag";

/// Max membership rows applied per transaction. Bounds how long one commit
/// holds the global store mutex: a realistic membership cache is ~82k rows, and
/// applying it as a single transaction holds the mutex for multiple seconds —
/// a main-thread store write blocked behind it trips the 5 s process-exit /
/// 10 s scene-update watchdog (0x8badf00d, TestFlight crashes of 2026-07-02/03).
/// Chunks re-acquire the mutex per transaction so main-thread writes interleave.
const APPLY_CHUNK_ROWS: usize = 2_000;

// ---------------------------------------------------------------------------
// FFI DTOs
// ---------------------------------------------------------------------------

/// Outcome of a [`ClubsApi::sync_clubs`] call. The `*_changed` flags are false
/// when the server answered `304 Not Modified`, so the host can skip UI work.
#[derive(uniffi::Record)]
pub struct FfiClubSyncSummary {
    pub clubs_changed: bool,
    pub membership_changed: bool,
    pub club_count: i64,
}

/// One page of a club activity feed.
#[derive(uniffi::Record)]
pub struct FfiClubActivityPage {
    pub items: Vec<FfiClubActivityItem>,
    pub has_more: bool,
    pub next_cursor: Option<String>,
}

/// A single activity-feed item. `details_json` carries the opaque per-activity
/// payload verbatim (the host decodes what it needs to render).
#[derive(uniffi::Record)]
pub struct FfiClubActivityItem {
    pub id: String,
    pub callsign: String,
    pub activity_type: String,
    /// Unix seconds, UTC.
    pub timestamp: i64,
    pub details_json: String,
    /// Unix seconds, UTC.
    pub created_at: i64,
}

/// Online status classification for a club member.
#[derive(uniffi::Enum)]
pub enum FfiMemberOnlineStatus {
    OnAir,
    RecentlyActive,
    Inactive,
}

impl From<MemberOnlineStatusWire> for FfiMemberOnlineStatus {
    fn from(status: MemberOnlineStatusWire) -> Self {
        match status {
            MemberOnlineStatusWire::OnAir => FfiMemberOnlineStatus::OnAir,
            MemberOnlineStatusWire::RecentlyActive => FfiMemberOnlineStatus::RecentlyActive,
            MemberOnlineStatusWire::Inactive => FfiMemberOnlineStatus::Inactive,
        }
    }
}

/// The spot backing an on-air member status.
#[derive(uniffi::Record)]
pub struct FfiMemberSpot {
    pub frequency: f64,
    pub mode: Option<String>,
    pub source: String,
    /// Unix seconds, UTC.
    pub spotted_at: i64,
}

/// Real-time status for one club member.
#[derive(uniffi::Record)]
pub struct FfiMemberStatus {
    pub callsign: String,
    pub status: FfiMemberOnlineStatus,
    pub spot: Option<FfiMemberSpot>,
    /// Unix seconds, UTC.
    pub last_seen_at: Option<i64>,
}

// ---------------------------------------------------------------------------
// Object
// ---------------------------------------------------------------------------

/// Async clubs API bound to a [`FieldStore`] and an activities-server base URL.
#[derive(uniffi::Object)]
pub struct ClubsApi {
    client: ClubsClient,
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl ClubsApi {
    /// Build an API against `base_url` (e.g. `https://activities.carrierwave.app`),
    /// writing into `store`.
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>, base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(ClubsApi { client: ClubsClient::new(http, base_url), store })
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl ClubsApi {
    /// Sync the user's clubs and the compact membership cache. `prior_callsigns`
    /// expands the request to clubs joined under previous calls. Both requests are
    /// ETag-conditional; unchanged data is left in place.
    pub async fn sync_clubs(
        &self,
        bearer: String,
        prior_callsigns: Vec<String>,
    ) -> Result<FfiClubSyncSummary, CwError> {
        // Read the stored ETags (short critical section, no I/O).
        let (clubs_etag, membership_etag) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            (store.kv_get(CLUBS_ETAG_KEY)?, store.kv_get(MEMBERSHIP_ETAG_KEY)?)
        };

        // Network — no lock held.
        let clubs_res = self
            .client
            .get_my_clubs(&bearer, &prior_callsigns, clubs_etag.as_deref())
            .await?;
        let membership_res = self
            .client
            .get_membership(&bearer, &prior_callsigns, membership_etag.as_deref())
            .await?;

        // Apply in bounded transactions (never one row at a time: per-row
        // autocommit under `synchronous = FULL` costs minutes of fsyncs). The
        // clubs list is small — one short transaction, ETag included. The
        // membership cache is tens of thousands of rows, so it's applied in
        // `APPLY_CHUNK_ROWS` chunks, releasing the store mutex between chunks
        // so a concurrent main-thread store write is never starved into a
        // watchdog kill. Its ETag commits only with the final chunk — an
        // interrupted apply persists no ETag, and the next sync re-fetches and
        // re-applies (links are INSERT OR IGNORE; reconcile is idempotent).
        let mut clubs_changed = false;
        let mut membership_changed = false;

        if let Conditional::Modified { data, etag } = &clubs_res {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                apply_clubs(&store, data, Utc::now().timestamp())?;
                if let Some(tag) = etag {
                    store.kv_set(CLUBS_ETAG_KEY, tag)?;
                }
                Ok(())
            })?;
            clubs_changed = true;
        }

        if let Conditional::Modified { data, etag } = &membership_res {
            apply_membership(&self.store.inner, data, etag.as_deref(), APPLY_CHUNK_ROWS)?;
            membership_changed = true;
        }

        let club_count = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            store.club_count()?
        };

        if clubs_changed {
            self.store
                .notify(FfiStoreChange { table: FfiStoreTable::Club, kind: FfiChangeKind::Upsert });
        }
        if membership_changed {
            self.store.notify(FfiStoreChange {
                table: FfiStoreTable::ClubMember,
                kind: FfiChangeKind::Upsert,
            });
        }

        Ok(FfiClubSyncSummary { clubs_changed, membership_changed, club_count })
    }

    /// Fetch one club's full detail (with members) and persist it: club metadata
    /// plus enriched member rows (role, grid, last-seen), preserving any local
    /// member numbers and reconciling departed members.
    pub async fn sync_club_details(&self, bearer: String, club_id: String) -> Result<(), CwError> {
        let detail = self.client.get_club_details(&bearer, &club_id, true).await?;
        // A large roster is thousands of member upserts — chunked transactions
        // (mutex released between chunks) for the same watchdog reason as
        // `sync_clubs`. Detail syncs are unconditional, so an interrupted apply
        // is simply retried in full the next time the club is opened.
        apply_detail(&self.store.inner, &detail, Utc::now().timestamp(), APPLY_CHUNK_ROWS)?;
        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::Club, kind: FfiChangeKind::Upsert });
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::ClubMember,
            kind: FfiChangeKind::Upsert,
        });
        Ok(())
    }

    /// Fetch a page of a club's activity feed. Not persisted — feeds are
    /// presentation-only and paged on demand.
    pub async fn fetch_activity(
        &self,
        bearer: String,
        club_id: String,
        cursor: Option<String>,
        limit: i64,
    ) -> Result<FfiClubActivityPage, CwError> {
        let page = self.client.get_activity(&bearer, &club_id, cursor.as_deref(), limit).await?;
        Ok(activity_page_from_wire(page))
    }

    /// Fetch real-time online status for a club's members. Not persisted.
    pub async fn fetch_status(
        &self,
        bearer: String,
        club_id: String,
    ) -> Result<Vec<FfiMemberStatus>, CwError> {
        let statuses = self.client.get_status(&bearer, &club_id).await?;
        Ok(statuses.into_iter().map(member_status_from_wire).collect())
    }
}

// ---------------------------------------------------------------------------
// Mapping helpers (wire → store / wire → FFI)
// ---------------------------------------------------------------------------

fn club_from_wire(wire: &ClubWire, now: i64) -> Club {
    Club {
        id: wire.id.clone(),
        name: wire.name.clone(),
        callsign: wire.callsign.clone(),
        description: wire.description.clone(),
        notes_url: wire.notes_url.clone(),
        notes_title: wire.notes_title.clone(),
        has_logo: wire.has_logo,
        cached_member_count: wire.member_count,
        last_synced_at: now,
    }
}

fn club_from_detail(detail: &ClubDetailWire, now: i64) -> Club {
    Club {
        id: detail.id.clone(),
        name: detail.name.clone(),
        callsign: detail.callsign.clone(),
        description: detail.description.clone(),
        notes_url: detail.notes_url.clone(),
        notes_title: detail.notes_title.clone(),
        has_logo: detail.has_logo,
        cached_member_count: detail.members.as_ref().map_or(0, |m| m.len() as i64),
        last_synced_at: now,
    }
}

fn member_from_wire(club_id: &str, wire: &ClubMemberWire) -> ClubMember {
    ClubMember {
        club_id: club_id.to_string(),
        callsign: wire.callsign.clone(),
        role: wire.role.clone(),
        last_seen_at: wire.last_seen_at.map(|date| date.timestamp()),
        last_grid: wire.last_grid.clone(),
        is_carrier_wave_user: wire.is_carrier_wave_user,
        // Local-only; the from-server upsert preserves any existing value.
        number: None,
    }
}

fn activity_page_from_wire(page: ClubActivityResponseWire) -> FfiClubActivityPage {
    FfiClubActivityPage {
        items: page
            .items
            .into_iter()
            .map(|item| FfiClubActivityItem {
                id: item.id,
                callsign: item.callsign,
                activity_type: item.activity_type,
                timestamp: item.timestamp.timestamp(),
                details_json: item.details.to_string(),
                created_at: item.created_at.timestamp(),
            })
            .collect(),
        has_more: page.pagination.has_more,
        next_cursor: page.pagination.next_cursor,
    }
}

fn member_status_from_wire(status: MemberStatusWire) -> FfiMemberStatus {
    FfiMemberStatus {
        callsign: status.callsign,
        status: status.status.into(),
        spot: status.spot_info.map(|spot| FfiMemberSpot {
            frequency: spot.frequency,
            mode: spot.mode,
            source: spot.source,
            spotted_at: spot.spotted_at.timestamp(),
        }),
        last_seen_at: status.last_seen_at.map(|date| date.timestamp()),
    }
}

// ---------------------------------------------------------------------------
// Store application (extracted so the sync write path is testable without HTTP)
// ---------------------------------------------------------------------------

/// Upsert the full club list and reconcile away clubs no longer returned.
fn apply_clubs(store: &Store, clubs: &[ClubWire], now: i64) -> Result<(), cw_store::StoreError> {
    let mut ids = Vec::with_capacity(clubs.len());
    for club in clubs {
        store.upsert_club(&club_from_wire(club, now))?;
        ids.push(club.id.clone());
    }
    store.retain_clubs(&ids)
}

/// Apply `rows` for one club in `chunk_rows`-bounded transactions, re-acquiring
/// the store mutex for each so concurrent (main-thread) store writes interleave
/// instead of blocking for the whole apply. `finish` runs inside the final
/// chunk's transaction (roster reconcile, ETag persist); it runs even when
/// `rows` is empty, so an empty roster still reconciles.
fn apply_rows_chunked<Row>(
    store_mutex: &Mutex<Store>,
    rows: &[Row],
    chunk_rows: usize,
    apply: impl Fn(&Store, &Row) -> Result<(), cw_store::StoreError>,
    finish: impl FnOnce(&Store) -> Result<(), cw_store::StoreError>,
) -> Result<(), cw_store::StoreError> {
    let chunk_total = rows.len().div_ceil(chunk_rows).max(1);
    let mut finish = Some(finish);
    for chunk_index in 0..chunk_total {
        let start = chunk_index * chunk_rows;
        let end = rows.len().min(start + chunk_rows);
        let store = store_mutex.lock().expect("store mutex poisoned");
        store.in_transaction(|| {
            for row in &rows[start..end] {
                apply(&store, row)?;
            }
            if let Some(finish) = (chunk_index + 1 == chunk_total).then(|| finish.take()).flatten() {
                finish(&store)?;
            }
            Ok(())
        })?;
    }
    Ok(())
}

/// Materialize the compact membership cache as bare `(club, callsign)` links,
/// resolving each entry's club name to its stored id, then reconcile each club's
/// roster to the listed callsigns. Existing role/grid/number are left untouched.
/// Applies in `chunk_rows`-bounded transactions; `etag` commits with the final
/// chunk only, so an interrupted apply re-syncs in full (inserts are idempotent).
fn apply_membership(
    store_mutex: &Mutex<Store>,
    entries: &[ClubMembershipEntryWire],
    etag: Option<&str>,
    chunk_rows: usize,
) -> Result<(), cw_store::StoreError> {
    // Resolve club names → stored ids under a short lock (entries whose club
    // the store doesn't know are skipped, matching the pre-chunking behavior).
    let plan: Vec<(String, &ClubMembershipEntryWire)> = {
        let store = store_mutex.lock().expect("store mutex poisoned");
        let clubs = store.fetch_clubs(&ClubFilter::default(), MAX_FETCH_LIMIT, 0)?;
        let by_name: HashMap<String, String> =
            clubs.into_iter().map(|club| (club.name.to_uppercase(), club.id)).collect();
        entries
            .iter()
            .filter_map(|entry| by_name.get(&entry.name.to_uppercase()).map(|id| (id.clone(), entry)))
            .collect()
    };

    if plan.is_empty() {
        if let Some(tag) = etag {
            let store = store_mutex.lock().expect("store mutex poisoned");
            store.in_transaction(|| store.kv_set(MEMBERSHIP_ETAG_KEY, tag))?;
        }
        return Ok(());
    }

    let last = plan.len() - 1;
    for (index, (club_id, entry)) in plan.iter().enumerate() {
        let etag_here = if index == last { etag } else { None };
        apply_rows_chunked(
            store_mutex,
            &entry.callsigns,
            chunk_rows,
            |store, callsign| store.insert_club_member_link(club_id, callsign),
            |store| {
                store.retain_club_members(club_id, &entry.callsigns)?;
                if let Some(tag) = etag_here {
                    store.kv_set(MEMBERSHIP_ETAG_KEY, tag)?;
                }
                Ok(())
            },
        )?;
    }
    Ok(())
}

/// Apply a single club's full detail: metadata plus enriched member rows
/// (role/grid/last-seen), preserving local numbers and reconciling departures.
/// The roster applies in `chunk_rows`-bounded transactions (see `sync_clubs`).
fn apply_detail(
    store_mutex: &Mutex<Store>,
    detail: &ClubDetailWire,
    now: i64,
    chunk_rows: usize,
) -> Result<(), cw_store::StoreError> {
    {
        let store = store_mutex.lock().expect("store mutex poisoned");
        store.in_transaction(|| store.upsert_club(&club_from_detail(detail, now)))?;
    }
    if let Some(members) = &detail.members {
        let keep: Vec<String> = members.iter().map(|m| m.callsign.clone()).collect();
        apply_rows_chunked(
            store_mutex,
            members,
            chunk_rows,
            |store, member| store.upsert_club_member_from_server(&member_from_wire(&detail.id, member)),
            |store| store.retain_club_members(&detail.id, &keep),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use cw_store::ClubMemberFilter;

    fn club_wire(id: &str, name: &str, member_count: i64) -> ClubWire {
        ClubWire {
            id: id.to_string(),
            name: name.to_string(),
            callsign: None,
            description: None,
            notes_url: None,
            notes_title: None,
            has_logo: false,
            member_count,
        }
    }

    fn membership(name: &str, callsigns: &[&str]) -> ClubMembershipEntryWire {
        ClubMembershipEntryWire {
            name: name.to_string(),
            callsigns: callsigns.iter().map(|s| s.to_string()).collect(),
        }
    }

    /// In-memory store wrapped the way production hands it to the chunked
    /// appliers. Callers lock for direct `Store` calls and pass the mutex to
    /// `apply_membership` / `apply_detail` (never both at once — not reentrant).
    fn mutex_store() -> Mutex<Store> {
        Mutex::new(Store::open_in_memory("k").unwrap())
    }

    #[test]
    fn apply_clubs_then_membership_builds_lookups() {
        let mutex = mutex_store();
        apply_clubs(
            &mutex.lock().unwrap(),
            &[club_wire("c1", "SKCC", 2), club_wire("c2", "FISTS", 1)],
            1000,
        )
        .unwrap();
        apply_membership(
            &mutex,
            &[membership("SKCC", &["W6JY", "N6ABC"]), membership("FISTS", &["W6JY"])],
            Some("etag-1"),
            APPLY_CHUNK_ROWS,
        )
        .unwrap();

        // Both lookups resolve through the stored links; the ETag persisted.
        let store = mutex.lock().unwrap();
        assert_eq!(store.clubs_for_callsign("w6jy").unwrap(), vec!["FISTS", "SKCC"]);
        assert_eq!(store.callsigns_in_club("SKCC").unwrap(), vec!["N6ABC", "W6JY"]);
        assert_eq!(store.kv_get(MEMBERSHIP_ETAG_KEY).unwrap().as_deref(), Some("etag-1"));
    }

    #[test]
    fn membership_reconciles_removed_members() {
        let mutex = mutex_store();
        apply_clubs(&mutex.lock().unwrap(), &[club_wire("c1", "SKCC", 2)], 1000).unwrap();
        apply_membership(&mutex, &[membership("SKCC", &["W6JY", "N6ABC"])], None, APPLY_CHUNK_ROWS)
            .unwrap();
        assert_eq!(mutex.lock().unwrap().callsigns_in_club("SKCC").unwrap().len(), 2);

        // N6ABC left the club.
        apply_membership(&mutex, &[membership("SKCC", &["W6JY"])], None, APPLY_CHUNK_ROWS).unwrap();
        assert_eq!(mutex.lock().unwrap().callsigns_in_club("SKCC").unwrap(), vec!["W6JY"]);
    }

    #[test]
    fn membership_chunked_apply_matches_single_transaction() {
        let mutex = mutex_store();
        apply_clubs(&mutex.lock().unwrap(), &[club_wire("c1", "SKCC", 5)], 1000).unwrap();
        // chunk_rows=2 over 5 callsigns → 3 transactions; reconcile + ETag land
        // with the final chunk and the result matches an unchunked apply.
        apply_membership(
            &mutex,
            &[membership("SKCC", &["W6JY", "N6ABC", "K7XYZ", "W1AW", "N0CALL"])],
            Some("etag-chunked"),
            2,
        )
        .unwrap();
        {
            let store = mutex.lock().unwrap();
            assert_eq!(store.club_member_count().unwrap(), 5);
            assert_eq!(store.kv_get(MEMBERSHIP_ETAG_KEY).unwrap().as_deref(), Some("etag-chunked"));
        }

        // Shrinking the roster through the chunked path reconciles departures.
        apply_membership(&mutex, &[membership("SKCC", &["W6JY"])], Some("etag-2"), 2).unwrap();
        let store = mutex.lock().unwrap();
        assert_eq!(store.callsigns_in_club("SKCC").unwrap(), vec!["W6JY"]);
        assert_eq!(store.kv_get(MEMBERSHIP_ETAG_KEY).unwrap().as_deref(), Some("etag-2"));
    }

    #[test]
    fn membership_with_no_known_clubs_still_persists_etag() {
        let mutex = mutex_store();
        // Server said Modified but none of the entries resolve to stored clubs —
        // the ETag must still persist or every sync re-downloads the cache.
        apply_membership(&mutex, &[membership("SKCC", &["W6JY"])], Some("etag-empty"), 2).unwrap();
        let store = mutex.lock().unwrap();
        assert_eq!(store.club_member_count().unwrap(), 0);
        assert_eq!(store.kv_get(MEMBERSHIP_ETAG_KEY).unwrap().as_deref(), Some("etag-empty"));
    }

    #[test]
    fn apply_clubs_reconciles_removed_clubs_and_their_members() {
        let mutex = mutex_store();
        apply_clubs(
            &mutex.lock().unwrap(),
            &[club_wire("c1", "SKCC", 1), club_wire("c2", "FISTS", 1)],
            1000,
        )
        .unwrap();
        apply_membership(
            &mutex,
            &[membership("SKCC", &["W6JY"]), membership("FISTS", &["W6JY"])],
            None,
            APPLY_CHUNK_ROWS,
        )
        .unwrap();
        {
            let store = mutex.lock().unwrap();
            assert_eq!(store.club_count().unwrap(), 2);
            assert_eq!(store.club_member_count().unwrap(), 2);
        }

        // Next sync returns only SKCC — FISTS and its members must vanish.
        let store = mutex.lock().unwrap();
        apply_clubs(&store, &[club_wire("c1", "SKCC", 1)], 2000).unwrap();
        assert_eq!(store.club_count().unwrap(), 1);
        assert_eq!(store.clubs_for_callsign("W6JY").unwrap(), vec!["SKCC"]);
    }

    #[test]
    fn detail_enriches_role_without_dropping_local_number() {
        let mutex = mutex_store();
        {
            let store = mutex.lock().unwrap();
            apply_clubs(&store, &[club_wire("c1", "SKCC", 1)], 1000).unwrap();
            // Operator records a member number locally, then membership links appear.
            store.set_club_member_number("c1", "W6JY", Some("12345")).unwrap();
        }
        apply_membership(&mutex, &[membership("SKCC", &["W6JY"])], None, APPLY_CHUNK_ROWS).unwrap();

        // A detail sync enriches the member with an admin role + grid.
        let detail = ClubDetailWire {
            id: "c1".to_string(),
            name: "SKCC".to_string(),
            callsign: None,
            description: None,
            notes_url: None,
            notes_title: None,
            has_logo: false,
            members: Some(vec![ClubMemberWire {
                callsign: "W6JY".to_string(),
                role: "admin".to_string(),
                joined_at: None,
                last_seen_at: None,
                last_grid: Some("CM87".to_string()),
                is_carrier_wave_user: true,
            }]),
        };
        apply_detail(&mutex, &detail, 3000, APPLY_CHUNK_ROWS).unwrap();

        let rows = mutex
            .lock()
            .unwrap()
            .fetch_club_members(
                &ClubMemberFilter { club_id: Some("c1".into()), ..Default::default() },
                10,
                0,
            )
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].role, "admin", "detail enriched the role");
        assert_eq!(rows[0].last_grid.as_deref(), Some("CM87"));
        assert!(rows[0].is_carrier_wave_user);
        assert_eq!(rows[0].number.as_deref(), Some("12345"), "local number preserved through both syncs");
    }
}
