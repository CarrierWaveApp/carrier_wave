//! Async QRZ callbook enrichment — name / QTH / grid lookup.
//!
//! Wraps `cw_net::QrzClient`. Credentials and the cached session key live in the
//! host [`SecureStore`] (the same foreign trait `AuthApi` uses); the session key
//! is cached in memory and refreshed under a single-flight guard, re-authing
//! once on expiry. Ports the QRZ XML half of `CallsignLookupService+QRZ`.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use cw_domain::maidenhead;
use cw_net::{HamdbClient, HamdbLookup, HttpClient, QrzClient, QrzError, QrzLookup};
use cw_store::CallbookLocation;
use tokio::sync::Mutex as AsyncMutex;

use crate::auth_api::SecureStore;
use crate::{CwError, FieldStore};

const KEY_USERNAME: &str = "cw.qrz.username";
const KEY_PASSWORD: &str = "cw.qrz.password";

/// TTL for cached `callbook_location` rows consumed by [`QrzApi::locate`]:
/// 30 days, matching iOS `MemberLocationCache.maxAge`.
const LOCATION_TTL_SECS: i64 = 30 * 24 * 60 * 60;
/// Concurrent lookups per chunk, matching iOS `ClubMapView+Lookup`'s
/// `chunked(into: 3)`.
const LOCATE_CHUNK_SIZE: usize = 3;
/// Pause between chunks, matching iOS's `Task.sleep(for: .milliseconds(200))`.
const LOCATE_CHUNK_DELAY_MS: u64 = 200;

impl From<QrzError> for CwError {
    fn from(err: QrzError) -> Self {
        match err {
            QrzError::Http(http) => CwError::Network { reason: http.to_string() },
            QrzError::Auth(reason) => CwError::Auth { reason },
            QrzError::SessionExpired => CwError::Auth { reason: "QRZ session expired".into() },
        }
    }
}

/// A QRZ callbook record for the host. `name` is the combined "First Last".
#[derive(uniffi::Record)]
pub struct FfiQrzLookup {
    pub callsign: String,
    pub name: Option<String>,
    pub first_name: Option<String>,
    pub nickname: Option<String>,
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub grid: Option<String>,
    pub license_class: Option<String>,
    pub previous_callsign: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

impl From<QrzLookup> for FfiQrzLookup {
    fn from(lookup: QrzLookup) -> Self {
        let name = lookup.full_name();
        FfiQrzLookup {
            callsign: lookup.call,
            name,
            first_name: lookup.first_name,
            nickname: lookup.nickname,
            qth: lookup.qth,
            state: lookup.state,
            country: lookup.country,
            grid: lookup.grid,
            license_class: lookup.license_class,
            previous_callsign: lookup.previous_callsign,
            lat: lookup.lat,
            lon: lookup.lon,
        }
    }
}

/// A resolved callsign location, cache-backed, for the club/QSO map.
/// Ports the merged output of iOS `ClubMapView+Lookup` + `MemberLocationCache`.
#[derive(uniffi::Record, Clone)]
pub struct FfiCallsignLocation {
    /// Uppercase base call as queried.
    pub callsign: String,
    pub latitude: f64,
    pub longitude: f64,
    pub grid: Option<String>,
    /// `"qrz"` | `"hamdb"` | `"grid"`.
    pub source: String,
}

/// Async QRZ enrichment API bound to a [`SecureStore`], with a free HamDB
/// fill-nil fallback (no credentials needed) folded in by [`lookup_callbook`].
#[derive(uniffi::Object)]
pub struct QrzApi {
    client: QrzClient,
    hamdb: HamdbClient,
    secure: Arc<dyn SecureStore>,
    /// In-memory session key; never persisted (it's short-lived server-side).
    session: StdMutex<Option<String>>,
    /// Single-flight guard so concurrent lookups share one auth round-trip.
    auth_guard: AsyncMutex<()>,
    /// Backing store for the `callbook_location` cache. Only present when
    /// constructed via [`QrzApi::with_store`]; [`QrzApi::locate`] requires it.
    store: Option<Arc<FieldStore>>,
}

#[uniffi::export]
impl QrzApi {
    #[uniffi::constructor]
    pub fn new(secure: Arc<dyn SecureStore>) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(QrzApi {
            client: QrzClient::new(http.clone()),
            hamdb: HamdbClient::new(http),
            secure,
            session: StdMutex::new(None),
            auth_guard: AsyncMutex::new(()),
            store: None,
        })
    }

    /// Build a store-backed API — required for [`QrzApi::locate`], which
    /// read-throughs against `store`'s `callbook_location` cache.
    #[uniffi::constructor]
    pub fn with_store(secure: Arc<dyn SecureStore>, store: Arc<FieldStore>) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(QrzApi {
            client: QrzClient::new(http.clone()),
            hamdb: HamdbClient::new(http),
            secure,
            session: StdMutex::new(None),
            auth_guard: AsyncMutex::new(()),
            store: Some(store),
        })
    }

    /// Store QRZ XML-callbook credentials, invalidating any cached session.
    pub fn set_credentials(&self, username: String, password: String) {
        self.secure.set(KEY_USERNAME.into(), username);
        self.secure.set(KEY_PASSWORD.into(), password);
        *self.session.lock().expect("qrz session mutex poisoned") = None;
    }

    /// Whether QRZ credentials are stored.
    pub fn has_credentials(&self) -> bool {
        self.secure.get(KEY_USERNAME.into()).is_some()
            && self.secure.get(KEY_PASSWORD.into()).is_some()
    }

    /// Forget the stored credentials and the cached session.
    pub fn clear_credentials(&self) {
        self.secure.delete(KEY_USERNAME.into());
        self.secure.delete(KEY_PASSWORD.into());
        *self.session.lock().expect("qrz session mutex poisoned") = None;
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl QrzApi {
    /// Look `callsign` up. `Ok(None)` means no QRZ record (or no credentials).
    /// Re-authenticates once on session expiry.
    pub async fn lookup(&self, callsign: String) -> Result<Option<FfiQrzLookup>, CwError> {
        let (username, password) =
            match (self.secure.get(KEY_USERNAME.into()), self.secure.get(KEY_PASSWORD.into())) {
                (Some(username), Some(password)) => (username, password),
                _ => return Ok(None),
            };

        let key = self.ensure_session(&username, &password).await?;
        match self.client.lookup(&key, &callsign).await {
            Ok(found) => Ok(found.map(Into::into)),
            Err(QrzError::SessionExpired) => {
                *self.session.lock().expect("qrz session mutex poisoned") = None;
                let key = self.ensure_session(&username, &password).await?;
                let found = self.client.lookup(&key, &callsign).await?;
                Ok(found.map(Into::into))
            }
            Err(err) => Err(err.into()),
        }
    }

    /// Look `callsign` up across QRZ + HamDB and return the merged callbook
    /// record. QRZ wins every field; HamDB only fills fields QRZ left empty
    /// (the iOS "QRZ > HamDB, HamDB fill-nil" precedence). HamDB needs no
    /// credentials, so this still returns US data when QRZ is unconfigured.
    /// `Ok(None)` means neither source had a usable record.
    pub async fn lookup_callbook(&self, callsign: String) -> Result<Option<FfiQrzLookup>, CwError> {
        // QRZ failures (no creds / network) degrade to HamDB rather than error.
        let qrz = self.lookup(callsign.clone()).await.unwrap_or(None);
        let hamdb = self.hamdb.lookup(&callsign).await.ok().flatten();
        Ok(merge_callbook(&callsign, qrz, hamdb))
    }

    /// Batch callsign → coordinate resolution for the map, read-through
    /// against the `callbook_location` cache (30-day TTL). Ports iOS
    /// `ClubMapView+Lookup` + `MemberLocationCache`:
    /// 1. Uppercase/trim/dedupe/drop-empty the inputs.
    /// 2. Cache hits return immediately.
    /// 3. Misses are resolved in chunks of 3 concurrent lookups with a 200ms
    ///    pause between chunks; each lookup queries QRZ, then HamDB (skipped
    ///    only when QRZ already returned raw coordinates).
    /// 4. Precedence across both backends: QRZ raw lat/lon > HamDB raw
    ///    lat/lon > QRZ grid centroid > HamDB grid centroid (see
    ///    `resolve_location`). A miss (neither backend usable) is skipped,
    ///    not cached, so it's retried on the next call.
    /// 5. Successes are upserted into the cache.
    ///
    /// Errors only if this `QrzApi` was built via [`QrzApi::new`] (no store).
    pub async fn locate(&self, callsigns: Vec<String>) -> Result<Vec<FfiCallsignLocation>, CwError> {
        let Some(store) = self.store.as_ref() else {
            return Err(CwError::Store { reason: "locate requires a store-backed QrzApi".into() });
        };

        let mut seen = HashSet::new();
        let inputs: Vec<String> = callsigns
            .iter()
            .map(|call| call.trim().to_uppercase())
            .filter(|call| !call.is_empty())
            .filter(|call| seen.insert(call.clone()))
            .collect();
        if inputs.is_empty() {
            return Ok(Vec::new());
        }

        let now = now_secs();
        let cached = {
            let inner = store.inner.lock().expect("store mutex poisoned");
            inner.fetch_callbook_locations(&inputs, now, LOCATION_TTL_SECS)?
        };
        let mut resolved: HashMap<String, FfiCallsignLocation> = cached
            .into_iter()
            .map(|loc| {
                let location = FfiCallsignLocation {
                    callsign: loc.callsign.clone(),
                    latitude: loc.latitude,
                    longitude: loc.longitude,
                    grid: loc.grid,
                    source: loc.source,
                };
                (loc.callsign, location)
            })
            .collect();

        let misses: Vec<String> =
            inputs.iter().filter(|call| !resolved.contains_key(*call)).cloned().collect();

        for (index, chunk) in misses.chunks(LOCATE_CHUNK_SIZE).enumerate() {
            if index > 0 {
                tokio::time::sleep(Duration::from_millis(LOCATE_CHUNK_DELAY_MS)).await;
            }
            let results = self.locate_chunk(chunk).await;
            for location in results.into_iter().flatten() {
                let inner = store.inner.lock().expect("store mutex poisoned");
                inner.upsert_callbook_location(&CallbookLocation {
                    callsign: location.callsign.clone(),
                    latitude: location.latitude,
                    longitude: location.longitude,
                    grid: location.grid.clone(),
                    source: location.source.clone(),
                    fetched_at: now,
                })?;
                drop(inner);
                resolved.insert(location.callsign.clone(), location);
            }
        }

        Ok(inputs.into_iter().filter_map(|call| resolved.remove(&call)).collect())
    }
}

/// Merge a QRZ record over a HamDB record (QRZ-priority, HamDB fill-nil).
fn merge_callbook(
    queried: &str,
    qrz: Option<FfiQrzLookup>,
    hamdb: Option<HamdbLookup>,
) -> Option<FfiQrzLookup> {
    if qrz.is_none() && hamdb.is_none() {
        return None;
    }
    let callsign = qrz
        .as_ref()
        .map(|rec| rec.callsign.clone())
        .or_else(|| hamdb.as_ref().map(|rec| rec.call.clone()))
        .unwrap_or_else(|| queried.to_uppercase());

    Some(FfiQrzLookup {
        callsign,
        name: pick(qrz.as_ref().and_then(|rec| rec.name.clone()), hamdb.as_ref().and_then(|rec| rec.name.clone())),
        // HamDB has no first-name / nickname / previous-call split.
        first_name: qrz.as_ref().and_then(|rec| rec.first_name.clone()),
        nickname: qrz.as_ref().and_then(|rec| rec.nickname.clone()),
        qth: pick(qrz.as_ref().and_then(|rec| rec.qth.clone()), hamdb.as_ref().and_then(|rec| rec.qth.clone())),
        state: pick(qrz.as_ref().and_then(|rec| rec.state.clone()), hamdb.as_ref().and_then(|rec| rec.state.clone())),
        country: pick(qrz.as_ref().and_then(|rec| rec.country.clone()), hamdb.as_ref().and_then(|rec| rec.country.clone())),
        grid: pick(qrz.as_ref().and_then(|rec| rec.grid.clone()), hamdb.as_ref().and_then(|rec| rec.grid.clone())),
        license_class: pick(
            qrz.as_ref().and_then(|rec| rec.license_class.clone()),
            hamdb.as_ref().and_then(|rec| rec.license_class.clone()),
        ),
        lat: qrz.as_ref().and_then(|rec| rec.lat).or_else(|| hamdb.as_ref().and_then(|rec| rec.lat)),
        lon: qrz.as_ref().and_then(|rec| rec.lon).or_else(|| hamdb.as_ref().and_then(|rec| rec.lon)),
        previous_callsign: qrz.and_then(|rec| rec.previous_callsign),
    })
}

/// First non-`None`, preferring `primary`.
fn pick(primary: Option<String>, fallback: Option<String>) -> Option<String> {
    primary.or(fallback)
}

impl QrzApi {
    /// Return the cached session key, fetching a fresh one under the single-flight
    /// guard if absent.
    async fn ensure_session(&self, username: &str, password: &str) -> Result<String, CwError> {
        if let Some(key) = self.session.lock().expect("qrz session mutex poisoned").clone() {
            return Ok(key);
        }
        let _guard = self.auth_guard.lock().await;
        // Re-check: another caller may have authenticated while we waited.
        if let Some(key) = self.session.lock().expect("qrz session mutex poisoned").clone() {
            return Ok(key);
        }
        let key = self.client.session_key(username, password).await?;
        *self.session.lock().expect("qrz session mutex poisoned") = Some(key.clone());
        Ok(key)
    }

    /// Resolve one callsign for [`QrzApi::locate`]: thin fetch orchestration
    /// only — the cross-backend precedence itself lives in the pure
    /// [`resolve_location`]. Fetches QRZ first; HamDB is only fetched when
    /// QRZ didn't already yield raw coordinates (tier 1), to avoid an
    /// unnecessary network round-trip when QRZ alone is conclusive. Errors
    /// from either backend are swallowed — `locate` skips misses rather than
    /// failing the whole batch.
    async fn locate_one(&self, callsign: String) -> Option<FfiCallsignLocation> {
        let qrz = self.lookup(callsign.clone()).await.unwrap_or(None);
        let needs_hamdb = raw_location_from_lookup(&callsign, qrz.as_ref()).is_none();
        let hamdb = if needs_hamdb {
            self.hamdb.lookup(&callsign).await.ok().flatten().map(|rec| hamdb_to_ffi(&callsign, rec))
        } else {
            None
        };
        resolve_location(&callsign, qrz.as_ref(), hamdb.as_ref())
    }

    /// Run `locate_one` over a chunk of up to [`LOCATE_CHUNK_SIZE`] callsigns
    /// concurrently. Fixed-size match avoids pulling in a `futures` crate
    /// dependency for a bound this small.
    async fn locate_chunk(&self, chunk: &[String]) -> Vec<Option<FfiCallsignLocation>> {
        match chunk {
            [] => Vec::new(),
            [call1] => vec![self.locate_one(call1.clone()).await],
            [call1, call2] => {
                let (result1, result2) =
                    tokio::join!(self.locate_one(call1.clone()), self.locate_one(call2.clone()));
                vec![result1, result2]
            }
            _ => {
                // `chunk` is bounded to LOCATE_CHUNK_SIZE (3) by `.chunks()`,
                // so any remainder beyond the first two is exactly one more.
                let (result1, result2, result3) = tokio::join!(
                    self.locate_one(chunk[0].clone()),
                    self.locate_one(chunk[1].clone()),
                    self.locate_one(chunk[2].clone())
                );
                vec![result1, result2, result3]
            }
        }
    }
}

/// Adapt a HamDB record into the shared [`FfiQrzLookup`] shape so
/// [`resolve_location`] can treat both backends uniformly.
fn hamdb_to_ffi(queried: &str, hamdb: HamdbLookup) -> FfiQrzLookup {
    FfiQrzLookup {
        callsign: if hamdb.call.is_empty() { queried.to_uppercase() } else { hamdb.call },
        name: hamdb.name,
        first_name: None,
        nickname: None,
        qth: hamdb.qth,
        state: hamdb.state,
        country: hamdb.country,
        grid: hamdb.grid,
        license_class: hamdb.license_class,
        previous_callsign: None,
        lat: hamdb.lat,
        lon: hamdb.lon,
    }
}

/// Pure cross-backend precedence for [`QrzApi::locate_one`]. Raw coordinates
/// are globally preferred over grid centroids; within a tier, QRZ is
/// preferred over HamDB:
/// 1. QRZ raw lat/lon (source `"qrz"`)
/// 2. HamDB raw lat/lon (source `"hamdb"`)
/// 3. QRZ grid centroid (source `"grid"`)
/// 4. HamDB grid centroid (source `"grid"`)
/// 5. `None`
///
/// `qrz`/`hamdb` are each optional and independent — either backend may be
/// absent (no record, no credentials, network failure already swallowed by
/// the caller).
fn resolve_location(
    callsign: &str,
    qrz: Option<&FfiQrzLookup>,
    hamdb: Option<&FfiQrzLookup>,
) -> Option<FfiCallsignLocation> {
    if let Some(location) = raw_location_from_lookup(callsign, qrz) {
        return Some(FfiCallsignLocation { source: "qrz".to_string(), ..location });
    }
    if let Some(location) = raw_location_from_lookup(callsign, hamdb) {
        return Some(FfiCallsignLocation { source: "hamdb".to_string(), ..location });
    }
    if let Some(location) = grid_location_from_lookup(callsign, qrz) {
        return Some(location);
    }
    grid_location_from_lookup(callsign, hamdb)
}

/// Raw-coordinate resolution for one optional lookup. `None` if `lookup` is
/// absent or lacks either `lat`/`lon`. `source` is always `"qrz"` here — the
/// caller ([`resolve_location`]) overwrites it to tag whichever backend
/// actually supplied the record.
fn raw_location_from_lookup(callsign: &str, lookup: Option<&FfiQrzLookup>) -> Option<FfiCallsignLocation> {
    let lookup = lookup?;
    let (latitude, longitude) = (lookup.lat?, lookup.lon?);
    Some(FfiCallsignLocation {
        callsign: callsign.trim().to_uppercase(),
        latitude,
        longitude,
        grid: lookup.grid.clone(),
        source: "qrz".to_string(),
    })
}

/// Grid-centroid fallback resolution for one optional lookup. `None` if
/// `lookup` is absent, has no grid, or the grid fails to parse. `source` is
/// always `"grid"`.
fn grid_location_from_lookup(callsign: &str, lookup: Option<&FfiQrzLookup>) -> Option<FfiCallsignLocation> {
    let lookup = lookup?;
    let grid = lookup.grid.as_ref()?;
    let coord = maidenhead::coordinate_from_grid(grid)?;
    Some(FfiCallsignLocation {
        callsign: callsign.trim().to_uppercase(),
        latitude: coord.latitude,
        longitude: coord.longitude,
        grid: Some(grid.clone()),
        source: "grid".to_string(),
    })
}

fn now_secs() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|dur| dur.as_secs() as i64).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lookup(lat: Option<f64>, lon: Option<f64>, grid: Option<&str>) -> FfiQrzLookup {
        FfiQrzLookup {
            callsign: "W6JY".to_string(),
            name: None,
            first_name: None,
            nickname: None,
            qth: None,
            state: None,
            country: None,
            grid: grid.map(str::to_string),
            license_class: None,
            previous_callsign: None,
            lat,
            lon,
        }
    }

    #[test]
    fn location_prefers_raw_lat_lon_over_grid() {
        let record = lookup(Some(37.7749), Some(-122.4194), Some("CM87"));
        let location = resolve_location("w6jy", Some(&record), None).expect("expected a location");
        assert_eq!(location.callsign, "W6JY");
        assert_eq!(location.latitude, 37.7749);
        assert_eq!(location.longitude, -122.4194);
        assert_eq!(location.grid.as_deref(), Some("CM87"));
        assert_eq!(location.source, "qrz");
    }

    #[test]
    fn location_falls_back_to_grid_centroid() {
        let record = lookup(None, None, Some("CM87"));
        let location = resolve_location("w6jy", Some(&record), None).expect("expected a grid centroid");
        assert_eq!(location.source, "grid");
        let expected = maidenhead::coordinate_from_grid("CM87").expect("valid grid");
        assert_eq!(location.latitude, expected.latitude);
        assert_eq!(location.longitude, expected.longitude);
        assert_eq!(location.grid.as_deref(), Some("CM87"));
    }

    #[test]
    fn location_none_without_coords_or_grid() {
        let record = lookup(None, None, None);
        assert!(resolve_location("w6jy", Some(&record), None).is_none());
    }

    #[test]
    fn location_none_with_invalid_grid_and_no_coords() {
        let record = lookup(None, None, Some("not-a-grid"));
        assert!(resolve_location("w6jy", Some(&record), None).is_none());
    }

    #[test]
    fn location_none_when_both_backends_absent() {
        assert!(resolve_location("w6jy", None, None).is_none());
    }

    #[test]
    fn hamdb_to_ffi_falls_back_to_queried_callsign_when_call_is_empty() {
        let hamdb = HamdbLookup { call: String::new(), lat: Some(1.0), lon: Some(2.0), ..Default::default() };
        let ffi = hamdb_to_ffi("w6jy", hamdb);
        assert_eq!(ffi.callsign, "W6JY");
        assert_eq!(ffi.lat, Some(1.0));
        assert_eq!(ffi.lon, Some(2.0));
    }

    // -- Cross-backend precedence (resolve_location) --------------------
    //
    // Required precedence: QRZ raw > HamDB raw > QRZ grid > HamDB grid > None.

    #[test]
    fn hamdb_raw_coords_win_over_qrz_grid_only() {
        // THE regression test: QRZ has only a coarse grid square, HamDB has
        // precise raw lat/lon. Before the fix, locate_one short-circuited on
        // QRZ's grid centroid and never consulted HamDB.
        let qrz = lookup(None, None, Some("CM87"));
        let hamdb = lookup(Some(37.7749), Some(-122.4194), Some("CM87ux"));
        let location = resolve_location("w6jy", Some(&qrz), Some(&hamdb)).expect("expected a location");
        assert_eq!(location.source, "hamdb");
        assert_eq!(location.latitude, 37.7749);
        assert_eq!(location.longitude, -122.4194);
        assert_eq!(location.grid.as_deref(), Some("CM87ux"));
    }

    #[test]
    fn qrz_raw_coords_win_when_present() {
        let qrz = lookup(Some(37.7749), Some(-122.4194), Some("CM87"));
        let hamdb = lookup(Some(1.0), Some(2.0), Some("AA00"));
        let location = resolve_location("w6jy", Some(&qrz), Some(&hamdb)).expect("expected a location");
        assert_eq!(location.source, "qrz");
        assert_eq!(location.latitude, 37.7749);
        assert_eq!(location.longitude, -122.4194);

        // The pure layer proves HamDB wasn't needed to resolve this case:
        // QRZ raw coords alone are sufficient, independent of whatever
        // HamDB would have returned.
        let qrz_only = resolve_location("w6jy", Some(&qrz), None).expect("expected a location");
        assert_eq!(qrz_only.latitude, location.latitude);
        assert_eq!(qrz_only.longitude, location.longitude);
        assert_eq!(qrz_only.source, "qrz");
    }

    #[test]
    fn qrz_grid_centroid_wins_when_both_grid_only() {
        let qrz = lookup(None, None, Some("CM87"));
        let hamdb = lookup(None, None, Some("CM88"));
        let location = resolve_location("w6jy", Some(&qrz), Some(&hamdb)).expect("expected a location");
        assert_eq!(location.source, "grid");
        let expected = maidenhead::coordinate_from_grid("CM87").expect("valid grid");
        assert_eq!(location.latitude, expected.latitude);
        assert_eq!(location.longitude, expected.longitude);
        assert_eq!(location.grid.as_deref(), Some("CM87"));
    }

    #[test]
    fn hamdb_grid_centroid_used_when_qrz_absent() {
        let hamdb = lookup(None, None, Some("CM88"));
        let location = resolve_location("w6jy", None, Some(&hamdb)).expect("expected a location");
        assert_eq!(location.source, "grid");
        let expected = maidenhead::coordinate_from_grid("CM88").expect("valid grid");
        assert_eq!(location.latitude, expected.latitude);
        assert_eq!(location.longitude, expected.longitude);
        assert_eq!(location.grid.as_deref(), Some("CM88"));
    }
}
