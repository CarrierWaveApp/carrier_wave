//! Equipment API over UniFFI — higher-level gear logic that the low-level
//! `FieldStore` CRUD doesn't own: fuzzy **catalog search** (the
//! `CatalogMatcher.swift` port in `cw-domain`) and equipment **construction**
//! (minting custom items + hydrating catalog items, then persisting through
//! `FieldStore` so the store observer fires).
//!
//! The catalog itself is downloaded/cached by `ReferenceDataApi` as JSON in the
//! store's `sync_kv`; this API reads that cache (parse-once, ETag-keyed) so
//! typeahead search is a lock + in-memory scan, not a JSON parse per keystroke.

use std::sync::{Arc, Mutex};

use cw_domain::catalog_matcher::{self, CatalogEntryRef};
use cw_net::{EquipmentCatalogWire, EquipmentEntryWire};
use cw_store::EquipmentItem;
use uuid::Uuid;

use crate::entities::equipment_item::FfiEquipmentItem;
use crate::reference_data_api::FfiEquipmentCatalogEntry;
use crate::{CwError, FieldStore};

// Mirror the reference-data cache keys (owned privately there).
const KV_EQUIPMENT_JSON: &str = "refdata.equipment_json";
const KV_EQUIPMENT_ETAG: &str = "refdata.equipment_etag";

/// A scored catalog match returned by [`EquipmentApi::search_catalog`].
#[derive(uniffi::Record)]
pub struct FfiCatalogMatch {
    pub entry: FfiEquipmentCatalogEntry,
    /// Confidence in 0.0..=1.0 (1.0 = exact).
    pub confidence: f64,
}

/// Fields for a free-form custom equipment add (mirrors the iOS manual-entry form).
#[derive(uniffi::Record)]
pub struct FfiCustomEquipmentInput {
    pub name: String,
    pub category: String,
    pub manufacturer: Option<String>,
    pub bands: Vec<String>,
    pub modes: Vec<String>,
    pub max_power: Option<i64>,
    pub portability: String,
}

/// Parsed catalog kept in memory, invalidated when the cache token changes.
struct CachedCatalog {
    /// ETag when present, else the raw-JSON byte length as a stringified token.
    token: String,
    entries: Vec<EquipmentEntryWire>,
}

/// Gear logic bound to a [`FieldStore`]: catalog search + item construction.
#[derive(uniffi::Object)]
pub struct EquipmentApi {
    store: Arc<FieldStore>,
    catalog_cache: Mutex<Option<CachedCatalog>>,
}

#[uniffi::export]
impl EquipmentApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        EquipmentApi { store, catalog_cache: Mutex::new(None) }
    }

    /// Fuzzy-search the cached equipment catalog. `category` filters on the
    /// catalog category raw value (e.g. "radio"); `limit` caps the results.
    /// Returns `[]` for a blank query or an empty/absent catalog cache.
    pub fn search_catalog(
        &self,
        query: String,
        category: Option<String>,
        limit: u32,
    ) -> Result<Vec<FfiCatalogMatch>, CwError> {
        self.hydrate()?;
        let cache = self.catalog_cache.lock().expect("catalog cache poisoned");
        let Some(cached) = cache.as_ref() else {
            return Ok(Vec::new());
        };
        let refs: Vec<CatalogEntryRef<'_>> = cached
            .entries
            .iter()
            .map(|entry| CatalogEntryRef {
                id: &entry.id,
                name: &entry.name,
                manufacturer: entry.manufacturer.as_deref().unwrap_or(""),
                category: entry.category.as_deref(),
                aliases: &entry.aliases,
            })
            .collect();
        let matches =
            catalog_matcher::search(&query, &refs, category.as_deref(), limit as usize);
        Ok(matches
            .into_iter()
            .map(|hit| FfiCatalogMatch {
                entry: wire_to_ffi(&cached.entries[hit.index]),
                confidence: hit.confidence,
            })
            .collect())
    }

    /// Look up a single catalog entry by its slug id.
    pub fn catalog_entry(
        &self,
        id: String,
    ) -> Result<Option<FfiEquipmentCatalogEntry>, CwError> {
        self.hydrate()?;
        let cache = self.catalog_cache.lock().expect("catalog cache poisoned");
        Ok(cache
            .as_ref()
            .and_then(|cached| cached.entries.iter().find(|entry| entry.id == id))
            .map(wire_to_ffi))
    }

    /// Create a free-form custom item, persist it to inventory, and return it.
    /// Mints a `custom-XXXX` catalog id — only the `custom-` prefix is
    /// load-bearing (the iOS `isCustom` check).
    pub fn add_custom_item(
        &self,
        input: FfiCustomEquipmentInput,
    ) -> Result<FfiEquipmentItem, CwError> {
        let item = EquipmentItem {
            id: Uuid::new_v4().to_string(),
            catalog_id: format!("custom-{}", &Uuid::new_v4().simple().to_string()[..8]),
            catalog_name: input.name,
            category_raw_value: input.category,
            nickname: None,
            notes: None,
            acquired_date: None,
            is_retired: false,
            bands_json: serde_json::to_vec(&input.bands).map_err(store_err)?,
            modes_json: serde_json::to_vec(&input.modes).map_err(store_err)?,
            max_power_watts: input.max_power,
            portability_raw_value: input.portability,
            manufacturer: input.manufacturer.unwrap_or_default(),
            created_at: now_secs(),
            weight_ounces: None,
            connection_profile_json: None,
        };
        // Persist through FieldStore so the store observer notifies.
        self.store.upsert_equipment_item(item.clone().into())?;
        Ok(item.into())
    }

    /// Create an inventory item from a catalog entry (hydrating specs), persist
    /// it, and return it. Errors if `catalog_id` isn't in the cached catalog.
    pub fn add_catalog_item(&self, catalog_id: String) -> Result<FfiEquipmentItem, CwError> {
        self.hydrate()?;
        let entry = {
            let cache = self.catalog_cache.lock().expect("catalog cache poisoned");
            cache
                .as_ref()
                .and_then(|cached| cached.entries.iter().find(|entry| entry.id == catalog_id).cloned())
        };
        let Some(entry) = entry else {
            return Err(CwError::Store { reason: format!("unknown catalog id: {catalog_id}") });
        };
        let item = EquipmentItem {
            id: Uuid::new_v4().to_string(),
            catalog_id: entry.id,
            catalog_name: entry.name,
            category_raw_value: entry.category.unwrap_or_else(|| "accessory".to_string()),
            nickname: None,
            notes: None,
            acquired_date: None,
            is_retired: false,
            bands_json: serde_json::to_vec(&entry.bands).map_err(store_err)?,
            modes_json: serde_json::to_vec(&entry.modes).map_err(store_err)?,
            max_power_watts: entry.max_power_watts.map(|watts| watts as i64),
            portability_raw_value: entry.portability.unwrap_or_else(|| "portable".to_string()),
            manufacturer: entry.manufacturer.unwrap_or_default(),
            created_at: now_secs(),
            // Catalog adds carry no weight (matches the iOS catalog→item path).
            weight_ounces: None,
            connection_profile_json: None,
        };
        self.store.upsert_equipment_item(item.clone().into())?;
        Ok(item.into())
    }
}

impl EquipmentApi {
    /// Ensure `catalog_cache` holds the current catalog. Cheap when the ETag (or
    /// JSON length) token is unchanged.
    fn hydrate(&self) -> Result<(), CwError> {
        let (raw, etag) = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            (inner.kv_get(KV_EQUIPMENT_JSON)?, inner.kv_get(KV_EQUIPMENT_ETAG)?)
        };
        let Some(raw) = raw else {
            *self.catalog_cache.lock().expect("catalog cache poisoned") =
                Some(CachedCatalog { token: String::new(), entries: Vec::new() });
            return Ok(());
        };
        let token = etag.unwrap_or_else(|| raw.len().to_string());
        {
            let cache = self.catalog_cache.lock().expect("catalog cache poisoned");
            if let Some(cached) = cache.as_ref() {
                if !token.is_empty() && cached.token == token {
                    return Ok(());
                }
            }
        }
        let catalog: EquipmentCatalogWire =
            serde_json::from_str(&raw).map_err(store_err)?;
        *self.catalog_cache.lock().expect("catalog cache poisoned") =
            Some(CachedCatalog { token, entries: catalog.entries });
        Ok(())
    }
}

fn wire_to_ffi(entry: &EquipmentEntryWire) -> FfiEquipmentCatalogEntry {
    FfiEquipmentCatalogEntry {
        id: entry.id.clone(),
        name: entry.name.clone(),
        manufacturer: entry.manufacturer.clone(),
        category: entry.category.clone(),
        bands: entry.bands.clone(),
        modes: entry.modes.clone(),
        max_power_watts: entry.max_power_watts,
        portability: entry.portability.clone(),
        weight_grams: entry.weight_grams,
        description: entry.description.clone(),
        aliases: entry.aliases.clone(),
        image_url: entry.image_url.clone(),
        antenna_connector: entry.antenna_connector.clone(),
        power_connector: entry.power_connector.clone(),
        key_jack: entry.key_jack.clone(),
        mic_jack: entry.mic_jack.clone(),
    }
}

fn now_secs() -> i64 {
    chrono::Utc::now().timestamp()
}

fn store_err(err: impl std::fmt::Display) -> CwError {
    CwError::Store { reason: err.to_string() }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CATALOG_JSON: &str = r#"{
        "version": 1,
        "entries": [
            {"id":"elecraft-kx2","name":"KX2","manufacturer":"Elecraft","category":"radio",
             "bands":["20m","40m"],"modes":["CW","SSB"],"max_power_watts":10.0,"portability":"backpack","aliases":[]},
            {"id":"mountain-topper-mtr4b","name":"MTR-4B","manufacturer":"Mountain Topper","category":"radio",
             "bands":["20m"],"modes":["CW"],"aliases":["mtr4b"]},
            {"id":"efhw-40-10","name":"EFHW 40-10","manufacturer":"Generic","category":"antenna",
             "bands":["40m","20m"],"modes":[],"aliases":[]}
        ]
    }"#;

    fn store_with_catalog() -> Arc<FieldStore> {
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        {
            let inner = store.inner.lock().unwrap();
            inner.kv_set(KV_EQUIPMENT_JSON, CATALOG_JSON).unwrap();
        }
        store
    }

    #[test]
    fn search_uses_cached_catalog() {
        let api = EquipmentApi::new(store_with_catalog());
        let hits = api.search_catalog("kx2".into(), None, 5).unwrap();
        assert_eq!(hits[0].entry.id, "elecraft-kx2");
        assert_eq!(hits[0].confidence, 1.0);
    }

    #[test]
    fn search_category_filter() {
        let api = EquipmentApi::new(store_with_catalog());
        assert!(api.search_catalog("efhw".into(), Some("radio".into()), 5).unwrap().is_empty());
        let antennas = api.search_catalog("efhw".into(), Some("antenna".into()), 5).unwrap();
        assert_eq!(antennas[0].entry.id, "efhw-40-10");
    }

    #[test]
    fn search_empty_query_is_empty() {
        let api = EquipmentApi::new(store_with_catalog());
        assert!(api.search_catalog("".into(), None, 5).unwrap().is_empty());
    }

    #[test]
    fn catalog_entry_by_id() {
        let api = EquipmentApi::new(store_with_catalog());
        assert_eq!(api.catalog_entry("elecraft-kx2".into()).unwrap().unwrap().name, "KX2");
        assert!(api.catalog_entry("nope".into()).unwrap().is_none());
    }

    #[test]
    fn add_custom_item_persists_with_custom_prefix() {
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        let api = EquipmentApi::new(store.clone());
        let item = api
            .add_custom_item(FfiCustomEquipmentInput {
                name: "Homebrew Yagi".into(),
                category: "antenna".into(),
                manufacturer: Some("W6JY".into()),
                bands: vec!["20m".into()],
                modes: vec![],
                max_power: None,
                portability: "portable".into(),
            })
            .unwrap();
        assert!(item.catalog_id.starts_with("custom-"));
        assert_eq!(store.equipment_item_count().unwrap(), 1);
        let fetched = store.fetch_equipment_item(item.id.clone()).unwrap().unwrap();
        assert_eq!(fetched.catalog_name, "Homebrew Yagi");
        assert_eq!(fetched.bands_json, b"[\"20m\"]");
    }

    #[test]
    fn add_catalog_item_hydrates_specs() {
        let store = store_with_catalog();
        let api = EquipmentApi::new(store.clone());
        let item = api.add_catalog_item("elecraft-kx2".into()).unwrap();
        assert_eq!(item.catalog_id, "elecraft-kx2");
        assert_eq!(item.catalog_name, "KX2");
        assert_eq!(item.category_raw_value, "radio");
        assert_eq!(item.max_power_watts, Some(10));
        assert_eq!(item.manufacturer, "Elecraft");
        assert_eq!(store.equipment_item_count().unwrap(), 1);
    }

    #[test]
    fn add_catalog_item_unknown_id_errors() {
        let api = EquipmentApi::new(store_with_catalog());
        assert!(api.add_catalog_item("nope".into()).is_err());
    }

    #[test]
    fn add_catalog_item_category_fallback() {
        // Entry without a category → "accessory".
        let store = Arc::new(FieldStore::open_in_memory("k".into()).unwrap());
        {
            let inner = store.inner.lock().unwrap();
            inner
                .kv_set(
                    KV_EQUIPMENT_JSON,
                    r#"{"version":1,"entries":[{"id":"widget","name":"Widget","aliases":[]}]}"#,
                )
                .unwrap();
        }
        let api = EquipmentApi::new(store);
        let item = api.add_catalog_item("widget".into()).unwrap();
        assert_eq!(item.category_raw_value, "accessory");
        assert_eq!(item.portability_raw_value, "portable");
    }
}
