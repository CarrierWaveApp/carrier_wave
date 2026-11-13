//! Callsign enrichment — DXCC entity (CTY.dat) + SKCC membership + clubs +
//! server membership dataset (CWops, etc.).
//!
//! `EnrichmentApi` owns the reference datasets the iOS `CTYService` /
//! `SKCCMembershipStore` download (CTY.dat and the SKCC roster) plus the server
//! callsign-enrichment dataset the iOS `CallsignEnrichmentCache` caches: it
//! fetches them, parses them with the shared `cw_domain`/`cw_net` parsers,
//! caches the raw text in the encrypted store (so a cold start works offline),
//! and answers a fast, network-free [`lookup`](EnrichmentApi::lookup) that folds
//! in the operator's club membership and any server memberships.
//!
//! QRZ name/QTH enrichment is the separate async `QrzApi` (it needs
//! credentials + a session). Polo callsign notes are intentionally *not* here:
//! they have no global source — each club configures its own notes URL — so
//! they belong with the clubs surface, not this dataset.

use std::collections::HashMap;
use std::sync::{Arc, Mutex as StdMutex};
use std::time::{SystemTime, UNIX_EPOCH};

use cw_domain::cty::{self, CtyDatabase as CoreCtyDatabase};
use cw_domain::skcc::{self, SkccMember};
use cw_net::{Conditional, EnrichmentClient, EnrichmentDataset, HttpClient};

use crate::{CwError, FieldStore};

/// country-files.com bigcty distribution (matches `CTYService.downloadURL`).
const CTY_URL: &str = "https://www.country-files.com/bigcty/cty.dat";
const CTY_FALLBACK_URL: &str = "https://www.country-files.com/cty/cty.dat";
/// SKCC roster (matches `SKCCMembershipStore.rosterURL`).
const SKCC_URL: &str = "https://www.skccgroup.com/membership_data/skccdata.txt";

/// Store kv keys for the cached raw downloads.
const KV_CTY: &str = "enrichment.cty_dat";
const KV_SKCC: &str = "enrichment.skcc_roster";
/// Store kv keys for the cached server membership dataset.
const KV_ENRICH_DATASET: &str = "enrichment.dataset_json";
const KV_ENRICH_ETAG: &str = "enrichment.dataset_etag";
const KV_ENRICH_FETCHED_AT: &str = "enrichment.dataset_fetched_at";

/// Membership-dataset freshness window, matching iOS `CallsignEnrichmentCache`
/// (`refreshInterval = 12 * 60 * 60`).
const MEMBERSHIP_TTL_SECS: i64 = 12 * 60 * 60;

/// The parsed reference datasets held in memory.
struct Datasets {
    cty: Option<CoreCtyDatabase>,
    skcc: HashMap<String, SkccMember>,
    /// Uppercased callsign → resolved server memberships.
    memberships: HashMap<String, Vec<FfiMembership>>,
}

/// One server-membership row for a callsign (CWops, SKCC-via-server, etc.).
#[derive(uniffi::Record, Clone)]
pub struct FfiMembership {
    pub source_slug: String,
    pub source_name: String,
    pub emoji: Option<String>,
    pub name: Option<String>,
    /// Member number as a string (no leading `#`).
    pub member_number: Option<String>,
    pub note: Option<String>,
    /// Precomputed display label, e.g. "🎹 CWops #1532".
    pub chip_label: String,
}

/// Combined enrichment for one callsign. All fields are best-effort; absent data
/// (datasets not yet downloaded, or no match) is simply `None` / empty.
#[derive(uniffi::Record)]
pub struct FfiCallsignEnrichment {
    /// The looked-up callsign, uppercased.
    pub callsign: String,
    pub dxcc_name: Option<String>,
    pub dxcc_prefix: Option<String>,
    pub cq_zone: Option<i32>,
    pub continent: Option<String>,
    pub skcc_number: Option<i64>,
    /// Precomputed SKCC badge, e.g. "12345T".
    pub skcc_badge: Option<String>,
    /// Carrier Wave clubs this callsign belongs to (from the local store).
    pub clubs: Vec<String>,
    /// Server memberships (CWops, etc.) from the cached enrichment dataset.
    pub memberships: Vec<FfiMembership>,
}

/// Enrichment API bound to a [`FieldStore`] (for the kv cache + club membership).
#[derive(uniffi::Object)]
pub struct EnrichmentApi {
    http: HttpClient,
    enrichment: EnrichmentClient,
    store: Arc<FieldStore>,
    data: StdMutex<Datasets>,
}

#[uniffi::export]
impl EnrichmentApi {
    /// Build the API, hydrating the datasets from the store's kv cache if a prior
    /// [`refresh`](EnrichmentApi::refresh) persisted them (offline cold start).
    /// `base_url` is the activities server (for the membership dataset).
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>, base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        let enrichment = EnrichmentClient::new(http.clone(), base_url);
        let (cty_raw, skcc_raw, dataset_raw) = {
            let inner = store.inner.lock().expect("store mutex poisoned");
            (inner.kv_get(KV_CTY)?, inner.kv_get(KV_SKCC)?, inner.kv_get(KV_ENRICH_DATASET)?)
        };
        let memberships = dataset_raw
            .and_then(|raw| serde_json::from_str::<EnrichmentDataset>(&raw).ok())
            .map(|dataset| build_membership_index(&dataset))
            .unwrap_or_default();
        let data = Datasets {
            cty: cty_raw.map(|raw| cty::parse(&raw)),
            skcc: skcc_raw.map(|raw| build_skcc_index(&raw)).unwrap_or_default(),
            memberships,
        };
        Ok(EnrichmentApi { http, enrichment, store, data: StdMutex::new(data) })
    }

    /// Whether either reference dataset (CTY/SKCC) is loaded.
    pub fn is_loaded(&self) -> bool {
        let data = self.data.lock().expect("enrichment mutex poisoned");
        data.cty.is_some() || !data.skcc.is_empty()
    }

    /// The cached raw CTY.dat text, if a prior [`refresh`](EnrichmentApi::refresh)
    /// persisted one. Hosts feed this to `SpotEngineApi::set_cty_database` (iOS
    /// keeps its own `CTYService` cache; Android's only copy lives here).
    pub fn cty_content(&self) -> Result<Option<String>, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner.kv_get(KV_CTY)?)
    }

    /// Look a callsign up across the loaded datasets + local club membership +
    /// server memberships. Network-free and fast — safe to call from a UI
    /// render path.
    pub fn lookup(&self, callsign: String) -> Result<FfiCallsignEnrichment, CwError> {
        let upper = callsign.to_uppercase();

        // Dataset reads (own everything before dropping the lock — `lookup`
        // borrows the database).
        let (dxcc_name, dxcc_prefix, cq_zone, continent, skcc_number, skcc_badge, memberships) = {
            let data = self.data.lock().expect("enrichment mutex poisoned");
            let (name, prefix, cq, continent) = match data.cty.as_ref().and_then(|db| db.lookup(&upper)) {
                Some(entity) => (
                    Some(entity.name.clone()),
                    Some(entity.primary_prefix.clone()),
                    Some(entity.cq_zone),
                    Some(entity.continent.clone()),
                ),
                None => (None, None, None, None),
            };
            let (number, badge) = match data.skcc.get(&upper) {
                Some(member) => (Some(member.number), Some(member.badge())),
                None => (None, None),
            };
            let memberships = data.memberships.get(&upper).cloned().unwrap_or_default();
            (name, prefix, cq, continent, number, badge, memberships)
        };

        // Club membership comes from the store (separate lock, taken after the
        // dataset lock is released).
        let clubs = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner.clubs_for_callsign(&upper)?
        };

        Ok(FfiCallsignEnrichment {
            callsign: upper,
            dxcc_name,
            dxcc_prefix,
            cq_zone,
            continent,
            skcc_number,
            skcc_badge,
            clubs,
            memberships,
        })
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl EnrichmentApi {
    /// Download CTY.dat and the SKCC roster, parse them, swap them in, and cache
    /// the raw text in the store. Each source is independent — one failing does
    /// not discard the other. Errors only if *both* fetches fail.
    pub async fn refresh(&self) -> Result<(), CwError> {
        let cty_raw = match self.http.get_text(CTY_URL, "text/plain").await {
            Ok(text) => Some(text),
            Err(_) => self.http.get_text(CTY_FALLBACK_URL, "text/plain").await.ok(),
        };
        let skcc_raw = self.http.get_text(SKCC_URL, "text/plain").await.ok();

        if cty_raw.is_none() && skcc_raw.is_none() {
            return Err(CwError::Network { reason: "enrichment data fetch failed".into() });
        }

        let parsed_cty = cty_raw.as_ref().map(|raw| cty::parse(raw));
        let parsed_skcc = skcc_raw.as_ref().map(|raw| build_skcc_index(raw));

        // Persist whichever downloads succeeded.
        {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            if let Some(raw) = &cty_raw {
                inner.kv_set(KV_CTY, raw)?;
            }
            if let Some(raw) = &skcc_raw {
                inner.kv_set(KV_SKCC, raw)?;
            }
        }

        let mut data = self.data.lock().expect("enrichment mutex poisoned");
        if let Some(cty) = parsed_cty {
            data.cty = Some(cty);
        }
        if let Some(skcc) = parsed_skcc {
            data.skcc = skcc;
        }
        Ok(())
    }

    /// Refresh the server membership dataset (CWops, etc.). ETag-conditional and
    /// gated by a 12h freshness window (matching iOS `CallsignEnrichmentCache`)
    /// unless `force` is set. Persists the dataset + ETag for offline cold start.
    pub async fn refresh_memberships(&self, force: bool) -> Result<(), CwError> {
        let (etag, fetched_at) = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            (inner.kv_get(KV_ENRICH_ETAG)?, inner.kv_get(KV_ENRICH_FETCHED_AT)?)
        };
        if !force {
            if let Some(ts) = fetched_at.as_deref().and_then(|raw| raw.parse::<i64>().ok()) {
                if now_secs().saturating_sub(ts) < MEMBERSHIP_TTL_SECS {
                    return Ok(());
                }
            }
        }

        match self.enrichment.fetch_dataset(etag.as_deref()).await? {
            Conditional::NotModified => {
                // Cache is current — just bump the freshness timestamp.
                let inner = self.store.inner.lock().expect("store mutex poisoned");
                inner.kv_set(KV_ENRICH_FETCHED_AT, &now_secs().to_string())?;
            }
            Conditional::Modified { data: dataset, etag: new_etag } => {
                let index = build_membership_index(&dataset);
                let raw = serde_json::to_string(&dataset)
                    .map_err(|err| CwError::Network { reason: err.to_string() })?;
                {
                    let inner = self.store.inner.lock().expect("store mutex poisoned");
                    inner.kv_set(KV_ENRICH_DATASET, &raw)?;
                    if let Some(tag) = &new_etag {
                        inner.kv_set(KV_ENRICH_ETAG, tag)?;
                    }
                    inner.kv_set(KV_ENRICH_FETCHED_AT, &now_secs().to_string())?;
                }
                self.data.lock().expect("enrichment mutex poisoned").memberships = index;
            }
        }
        Ok(())
    }
}

/// Parse a SKCC roster body into the by-callsign lookup index.
fn build_skcc_index(raw: &str) -> HashMap<String, SkccMember> {
    let members = skcc::parse_roster(raw);
    skcc::build_index(&members)
}

/// Resolve the server dataset into a by-callsign membership index, resolving
/// each row's source name + emoji from the dataset's source catalog (per-row
/// emoji overrides the source default, matching iOS `indexedByCallsign`).
fn build_membership_index(dataset: &EnrichmentDataset) -> HashMap<String, Vec<FfiMembership>> {
    let source_by_slug: HashMap<&str, &cw_net::EnrichmentSource> =
        dataset.sources.iter().map(|src| (src.slug.as_str(), src)).collect();

    let mut index: HashMap<String, Vec<FfiMembership>> = HashMap::new();
    for entry in &dataset.callsigns {
        let memberships = entry
            .memberships
            .iter()
            .map(|row| {
                let source = source_by_slug.get(row.source_slug.as_str());
                let source_name =
                    source.map(|src| src.name.clone()).unwrap_or_else(|| row.source_slug.clone());
                let emoji = row.emoji.clone().or_else(|| source.and_then(|src| src.emoji.clone()));
                let chip_label = make_chip_label(emoji.as_deref(), &source_name, row.member_number.as_deref());
                FfiMembership {
                    source_slug: row.source_slug.clone(),
                    source_name,
                    emoji,
                    name: row.name.clone(),
                    member_number: row.member_number.clone(),
                    note: row.note.clone(),
                    chip_label,
                }
            })
            .collect();
        index.insert(entry.callsign.to_uppercase(), memberships);
    }
    index
}

/// "🎹 CWops #1532" — emoji prefix omitted if absent, ` #number` omitted if
/// absent/empty (port of `CallsignEnrichmentMembership.chipLabel`).
fn make_chip_label(emoji: Option<&str>, source_name: &str, number: Option<&str>) -> String {
    let mut label = String::new();
    if let Some(emoji) = emoji {
        label.push_str(emoji);
        label.push(' ');
    }
    label.push_str(source_name);
    if let Some(number) = number {
        if !number.is_empty() {
            label.push_str(" #");
            label.push_str(number);
        }
    }
    label
}

fn now_secs() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|dur| dur.as_secs() as i64).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn in_memory_api() -> EnrichmentApi {
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        EnrichmentApi::new(store, "https://activities.example".into()).unwrap()
    }

    #[test]
    fn lookup_without_data_is_all_empty() {
        let api = in_memory_api();
        assert!(!api.is_loaded());

        let enriched = api.lookup("W6JY".into()).unwrap();
        assert_eq!(enriched.callsign, "W6JY");
        assert!(enriched.dxcc_name.is_none());
        assert!(enriched.skcc_number.is_none());
        assert!(enriched.clubs.is_empty());
        assert!(enriched.memberships.is_empty());
    }

    #[test]
    fn cty_content_round_trips_the_kv_cache() {
        let api = in_memory_api();
        assert_eq!(api.cty_content().unwrap(), None);

        let raw = "Japan:  25:  45:  AS:  36.40:  -138.38:  -9.0:  JA:\n    JA;\n";
        {
            let inner = api.store.inner.lock().unwrap();
            inner.kv_set(KV_CTY, raw).unwrap();
        }
        assert_eq!(api.cty_content().unwrap().as_deref(), Some(raw));
    }

    #[test]
    fn skcc_index_resolves_member_number() {
        let index = build_skcc_index("Number|Call|Name|SPC\n12345|W6JY|Jay|CA\n");
        assert!(index.contains_key("W6JY"), "callsign indexed uppercase");
        assert_eq!(index.get("W6JY").map(|m| m.number), Some(12345));
    }

    #[test]
    fn membership_index_resolves_source_and_chip_label() {
        let dataset: EnrichmentDataset = serde_json::from_str(
            r##"{"sources":[{"slug":"cwops","name":"CWops","emoji":"🎹"}],
                 "callsigns":[{"c":"w6jy","m":[{"s":"cwops","n":"Jay","#":"1532"}]}]}"##,
        )
        .unwrap();
        let index = build_membership_index(&dataset);
        let rows = index.get("W6JY").expect("uppercased key");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].source_name, "CWops");
        assert_eq!(rows[0].emoji.as_deref(), Some("🎹"));
        assert_eq!(rows[0].chip_label, "🎹 CWops #1532");
    }

    #[test]
    fn chip_label_omits_missing_parts() {
        assert_eq!(make_chip_label(None, "SKCC", Some("123")), "SKCC #123");
        assert_eq!(make_chip_label(Some("🎹"), "CWops", None), "🎹 CWops");
        assert_eq!(make_chip_label(None, "Club", Some("")), "Club");
    }
}
