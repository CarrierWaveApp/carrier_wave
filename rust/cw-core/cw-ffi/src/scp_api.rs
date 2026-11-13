//! MASTER.SCP download + cache — the download/caching half of iOS
//! `SCPService`, for hosts without their own networking layer (Android).
//!
//! Downloads the supercheckpartial.com master list (ETag-conditional, 7-day
//! freshness window), kv-caches the raw text in the encrypted store so a cold
//! start works offline, and serves a shared [`ScpDatabase`] for suggestion
//! queries. iOS keeps its own on-disk `SCPService` cache and constructs
//! `ScpDatabase` directly from it.

use std::sync::{Arc, Mutex as StdMutex};
use std::time::{SystemTime, UNIX_EPOCH};

use cw_net::{Conditional, HttpClient};

use crate::scp::ScpDatabase;
use crate::{CwError, FieldStore};

/// supercheckpartial.com master list (matches `SCPService.remoteURL`).
const SCP_URL: &str = "http://www.supercheckpartial.com/MASTER.SCP";

/// Store kv keys for the cached download.
const KV_SCP: &str = "scp.master";
const KV_SCP_ETAG: &str = "scp.master_etag";
const KV_SCP_FETCHED_AT: &str = "scp.master_fetched_at";

/// Freshness window, matching iOS `SCPService` (`staleInterval` = 7 days).
const SCP_TTL_SECS: i64 = 7 * 24 * 60 * 60;

/// Super Check Partial API bound to a [`FieldStore`] (for the kv cache).
#[derive(uniffi::Object)]
pub struct ScpApi {
    http: HttpClient,
    store: Arc<FieldStore>,
    db: StdMutex<Option<Arc<ScpDatabase>>>,
}

#[uniffi::export]
impl ScpApi {
    /// Build the API, hydrating the database from the store's kv cache if a
    /// prior [`refresh`](ScpApi::refresh) persisted one (offline cold start).
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        let raw = {
            let inner = store.inner.lock().expect("store mutex poisoned");
            inner.kv_get(KV_SCP)?
        };
        let db = raw.map(|raw| Arc::new(ScpDatabase::new(parse_callsigns(&raw))));
        Ok(ScpApi { http, store, db: StdMutex::new(db) })
    }

    /// The loaded database, or `None` before the first successful refresh.
    pub fn database(&self) -> Option<Arc<ScpDatabase>> {
        self.db.lock().expect("scp mutex poisoned").clone()
    }

    /// Whether a database is loaded (cached or freshly downloaded).
    pub fn is_loaded(&self) -> bool {
        self.db.lock().expect("scp mutex poisoned").is_some()
    }

    /// Unix seconds of the last successful refresh/check, if any — drives
    /// the External Data screen's "checked N ago" row.
    pub fn fetched_at(&self) -> Result<Option<i64>, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner.kv_get(KV_SCP_FETCHED_AT)?.and_then(|raw| raw.parse().ok()))
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl ScpApi {
    /// Download MASTER.SCP, swap the database in, and cache the raw text.
    /// ETag-conditional and gated by the 7-day freshness window unless
    /// `force` is set (matching iOS `SCPService.loadAndRefresh`).
    pub async fn refresh(&self, force: bool) -> Result<(), CwError> {
        let (etag, fetched_at) = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            (inner.kv_get(KV_SCP_ETAG)?, inner.kv_get(KV_SCP_FETCHED_AT)?)
        };
        if !force {
            let has_db = self.db.lock().expect("scp mutex poisoned").is_some();
            if has_db {
                if let Some(ts) = fetched_at.as_deref().and_then(|raw| raw.parse::<i64>().ok()) {
                    if now_secs().saturating_sub(ts) < SCP_TTL_SECS {
                        return Ok(());
                    }
                }
            }
        }

        match self
            .http
            .get_text_conditional(SCP_URL, "text/plain", etag.as_deref())
            .await?
        {
            Conditional::NotModified => {
                // Cache is current — just bump the freshness timestamp.
                let inner = self.store.inner.lock().expect("store mutex poisoned");
                inner.kv_set(KV_SCP_FETCHED_AT, &now_secs().to_string())?;
            }
            Conditional::Modified { data: raw, etag: new_etag } => {
                let db = Arc::new(ScpDatabase::new(parse_callsigns(&raw)));
                {
                    let inner = self.store.inner.lock().expect("store mutex poisoned");
                    inner.kv_set(KV_SCP, &raw)?;
                    if let Some(tag) = &new_etag {
                        inner.kv_set(KV_SCP_ETAG, tag)?;
                    }
                    inner.kv_set(KV_SCP_FETCHED_AT, &now_secs().to_string())?;
                }
                *self.db.lock().expect("scp mutex poisoned") = Some(db);
            }
        }
        Ok(())
    }
}

/// Split lines, trim, drop empties (port of `SCPService.parseCallsigns`).
fn parse_callsigns(text: &str) -> Vec<String> {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect()
}

fn now_secs() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|dur| dur.as_secs() as i64).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_trims_and_drops_empties() {
        let calls = parse_callsigns("W1AW\n  K2A  \n\n#HEADER\nJA1ABC\n");
        assert_eq!(calls, vec!["W1AW", "K2A", "#HEADER", "JA1ABC"]);
    }

    #[test]
    fn cold_start_without_cache_has_no_database() {
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        let api = ScpApi::new(store).unwrap();
        assert!(!api.is_loaded());
        assert!(api.database().is_none());
    }

    #[test]
    fn hydrates_from_kv_cache() {
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        {
            let inner = store.inner.lock().unwrap();
            inner.kv_set(KV_SCP, "W1AW\nJA1ABC\n").unwrap();
        }
        let api = ScpApi::new(store).unwrap();
        let db = api.database().expect("hydrated");
        assert_eq!(db.count(), 2);
        assert!(db.contains("W1AW".into()));
    }
}
