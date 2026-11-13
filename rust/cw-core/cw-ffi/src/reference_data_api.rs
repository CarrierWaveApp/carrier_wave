//! Async reference-data API over UniFFI — the shared core behind the iOS
//! "External Data" screen: POTA parks, SOTA summits, the WWFF directory,
//! the equipment catalog, the FCC amateur-callsign database, and SOTA
//! activation zones. Ports `POTAParksCache`, `SOTASummitsCache`,
//! `WWFFReferencesCache`, `EquipmentCatalogService`, `FCCLookupService`,
//! and `SOTAZonesCache`'s download/refresh halves (SCP and contest
//! definitions already live in `ScpApi` / `ContestApi`).
//!
//! Row data lands in cw-store tables (`pota_park`, `sota_summit`,
//! `wwff_reference`, `sota_zone`); the equipment catalog and freshness /
//! ETag bookkeeping use the store's kv, mirroring the iOS metadata
//! sidecars; the FCC database is a plain read-only SQLite file under the
//! host-provided `data_dir` (it ships as SQLite — re-importing ~800k rows
//! into cw-store would only add cost).

use std::path::PathBuf;
use std::sync::{Arc, Mutex as StdMutex};

use cw_domain::reference_csv::{
    parse_pota_parks_csv, parse_sota_summits_csv, parse_wwff_directory_csv,
};
use cw_net::{
    fetch_reference_csv, Conditional, EquipmentCatalogClient, EquipmentCatalogWire, FccClient,
    HttpClient, SotaZoneInput, SotaZonesClient, POTA_PARKS_CSV_URL, SOTA_SUMMITS_CSV_URL,
    WWFF_DIRECTORY_CSV_URL,
};
use cw_store::{PotaPark, SotaZoneRow};
use sha2::{Digest, Sha256};

use crate::{CwError, FieldStore};

// Freshness windows, matching the iOS caches.
const POTA_TTL_SECS: i64 = 14 * 24 * 60 * 60;
const SOTA_TTL_SECS: i64 = 30 * 24 * 60 * 60;
const WWFF_TTL_SECS: i64 = 30 * 24 * 60 * 60;
const EQUIPMENT_TTL_SECS: i64 = 24 * 60 * 60;
const FCC_TTL_SECS: i64 = 7 * 24 * 60 * 60;

// Download timeouts. The CSVs run tens of MB; WWFF's server is slow (iOS
// uses a dedicated 120 s/300 s session for it).
const CSV_TIMEOUT_SECS: u64 = 180;
const WWFF_TIMEOUT_SECS: u64 = 300;

/// Newest FCC bundle schema this code understands (`FCCLookupService`'s
/// guard: refuse to overwrite with a newer, unknown layout).
const FCC_MAX_SCHEMA_VERSION: i64 = 1;

const KV_POTA_FETCHED_AT: &str = "refdata.pota_fetched_at";
const KV_SOTA_FETCHED_AT: &str = "refdata.sota_fetched_at";
const KV_WWFF_FETCHED_AT: &str = "refdata.wwff_fetched_at";
const KV_EQUIPMENT_JSON: &str = "refdata.equipment_json";
const KV_EQUIPMENT_ETAG: &str = "refdata.equipment_etag";
const KV_EQUIPMENT_COUNT: &str = "refdata.equipment_count";
const KV_EQUIPMENT_FETCHED_AT: &str = "refdata.equipment_fetched_at";
const KV_FCC_SHA256: &str = "refdata.fcc_sha256";
const KV_FCC_COUNT: &str = "refdata.fcc_record_count";
const KV_FCC_FETCHED_AT: &str = "refdata.fcc_fetched_at";
const KV_ZONES_PENDING: &str = "refdata.sota_zones_pending";
const KV_ZONES_FETCHED_AT: &str = "refdata.sota_zones_fetched_at";
/// Inter-chunk pace for the SOTA activation-zone refresh POSTs. The activities
/// server's public API is rate-limited to 10 req/s per IP (burst 20); spacing
/// the `/v1/sota/zones` chunk POSTs ~150 ms apart keeps a full-database refresh
/// (hundreds of chunks) under that ceiling with headroom for the app's other
/// traffic. `send_bytes_retrying` honoring `Retry-After` is the backstop.
const ZONES_CHUNK_DELAY_MS: u64 = 150;

const FCC_DB_FILE: &str = "amateur-callsigns.db";

// ---------------------------------------------------------------------------
// FFI DTOs
// ---------------------------------------------------------------------------

/// Freshness + size of one cached dataset.
#[derive(uniffi::Record, Clone)]
pub struct FfiDatasetStatus {
    /// Cached rows/entries (0 = never downloaded).
    pub count: i64,
    /// Unix seconds of the last successful refresh, if any.
    pub fetched_at: Option<i64>,
}

/// Snapshot of every dataset this API manages — one call drives the whole
/// External Data screen.
#[derive(uniffi::Record, Clone)]
pub struct FfiExternalDataStatus {
    pub pota_parks: FfiDatasetStatus,
    pub sota_summits: FfiDatasetStatus,
    pub wwff_references: FfiDatasetStatus,
    pub equipment_entries: FfiDatasetStatus,
    pub fcc_callsigns: FfiDatasetStatus,
    pub sota_zones: FfiDatasetStatus,
    /// Summits whose zones the server is still computing (iOS shows
    /// "N still computing — tap Refresh again later").
    pub sota_zones_pending: i64,
}

/// Result of one dataset refresh.
#[derive(uniffi::Record, Clone)]
pub struct FfiRefreshOutcome {
    /// False when the cache was fresh (TTL) or the server said not-modified
    /// (ETag / unchanged SHA-256).
    pub refreshed: bool,
    /// Rows/entries now cached.
    pub count: i64,
}

/// Result of a SOTA zones pass.
#[derive(uniffi::Record, Clone)]
pub struct FfiZonesRefreshOutcome {
    /// Summits requested this pass.
    pub requested: i64,
    /// Zones newly resolved this pass.
    pub resolved: i64,
    /// Requested summits the server hasn't computed yet.
    pub pending: i64,
    /// Total zones now cached.
    pub total: i64,
}

/// One catalog entry (Swift `EquipmentAPIEntry` field set).
#[derive(uniffi::Record, Clone)]
pub struct FfiEquipmentCatalogEntry {
    pub id: String,
    pub name: String,
    pub manufacturer: Option<String>,
    pub category: Option<String>,
    pub bands: Vec<String>,
    pub modes: Vec<String>,
    pub max_power_watts: Option<f64>,
    pub portability: Option<String>,
    pub weight_grams: Option<f64>,
    pub description: Option<String>,
    pub aliases: Vec<String>,
    pub image_url: Option<String>,
    pub antenna_connector: Option<String>,
    pub power_connector: Option<String>,
    pub key_jack: Option<String>,
    pub mic_jack: Option<String>,
}

/// One SOTA summit (mirrors the Swift `SOTASummit` / cw-store `sota_summit`).
#[derive(uniffi::Record, Clone)]
pub struct FfiSotaSummit {
    pub code: String,
    pub name: String,
    pub association_name: String,
    pub region_name: String,
    pub altitude_m: i64,
    pub altitude_ft: i64,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub points: i64,
    pub bonus_points: i64,
    pub activation_count: i64,
    /// "dd/MM/yyyy" from the CSV, verbatim.
    pub last_activation_date: Option<String>,
    pub last_activation_call: Option<String>,
    pub grid: Option<String>,
}

/// One WWFF reference (mirrors the Swift `WWFFReference`).
#[derive(uniffi::Record, Clone)]
pub struct FfiWwffReference {
    pub reference: String,
    pub name: String,
    pub program: String,
    pub status: String,
    pub continent: Option<String>,
    pub iota: Option<String>,
    pub grid: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub iucn_category: Option<String>,
    pub country: Option<String>,
    pub region: Option<String>,
    pub dxcc_entity: Option<i64>,
}

/// One cached SOTA activation zone (GeoJSON geometry verbatim).
#[derive(uniffi::Record, Clone)]
pub struct FfiSotaZone {
    pub code: String,
    pub altitude_m: i64,
    pub geometry_geojson: String,
}

/// One FCC amateur-callsign record.
#[derive(uniffi::Record, Clone)]
pub struct FfiFccRecord {
    pub callsign: String,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub grid: Option<String>,
    pub operator_class: Option<String>,
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

/// Async reference-data API bound to a [`FieldStore`], the activities-server
/// base URL (equipment catalog + SOTA zones), and a host directory for the
/// FCC SQLite file.
#[derive(uniffi::Object)]
pub struct ReferenceDataApi {
    store: Arc<FieldStore>,
    equipment: EquipmentCatalogClient,
    zones: SotaZonesClient,
    fcc: FccClient,
    data_dir: PathBuf,
    /// Cached read-only handle to the FCC SQLite; dropped after a refresh
    /// replaces the file.
    fcc_conn: StdMutex<Option<rusqlite::Connection>>,
}

#[uniffi::export]
impl ReferenceDataApi {
    #[uniffi::constructor]
    pub fn new(
        store: Arc<FieldStore>,
        base_url: String,
        data_dir: String,
    ) -> Result<Self, CwError> {
        let http = HttpClient::new().map_err(net_err)?;
        Ok(ReferenceDataApi {
            store,
            equipment: EquipmentCatalogClient::new(http.clone(), base_url.clone()),
            zones: SotaZonesClient::new(http.clone(), base_url),
            fcc: FccClient::new(http),
            data_dir: PathBuf::from(data_dir),
            fcc_conn: StdMutex::new(None),
        })
    }

    /// Freshness + counts for every dataset (drives the External Data UI).
    pub fn status(&self) -> Result<FfiExternalDataStatus, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        let kv_i64 = |key: &str| -> Result<Option<i64>, CwError> {
            Ok(inner.kv_get(key)?.and_then(|raw| raw.parse().ok()))
        };
        let dataset = |count: i64, key: &str| -> Result<FfiDatasetStatus, CwError> {
            Ok(FfiDatasetStatus { count, fetched_at: kv_i64(key)? })
        };
        Ok(FfiExternalDataStatus {
            pota_parks: dataset(inner.pota_park_count()?, KV_POTA_FETCHED_AT)?,
            sota_summits: dataset(inner.sota_summit_count()?, KV_SOTA_FETCHED_AT)?,
            wwff_references: dataset(inner.wwff_reference_count()?, KV_WWFF_FETCHED_AT)?,
            equipment_entries: dataset(
                kv_i64(KV_EQUIPMENT_COUNT)?.unwrap_or(0),
                KV_EQUIPMENT_FETCHED_AT,
            )?,
            fcc_callsigns: FfiDatasetStatus {
                count: if self.data_dir.join(FCC_DB_FILE).exists() {
                    kv_i64(KV_FCC_COUNT)?.unwrap_or(0)
                } else {
                    0
                },
                fetched_at: kv_i64(KV_FCC_FETCHED_AT)?,
            },
            sota_zones: dataset(inner.sota_zone_count()?, KV_ZONES_FETCHED_AT)?,
            sota_zones_pending: kv_i64(KV_ZONES_PENDING)?.unwrap_or(0),
        })
    }

    /// Cached equipment catalog entries (offline read).
    pub fn equipment_entries(&self) -> Result<Vec<FfiEquipmentCatalogEntry>, CwError> {
        let raw = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner.kv_get(KV_EQUIPMENT_JSON)?
        };
        let Some(raw) = raw else {
            return Ok(Vec::new());
        };
        let catalog: EquipmentCatalogWire =
            serde_json::from_str(&raw).map_err(|err| CwError::Store { reason: err.to_string() })?;
        Ok(catalog.entries.into_iter().map(equipment_entry_to_ffi).collect())
    }

    /// Paged POTA park rows ordered by reference (`limit` ≤ 1000) — the
    /// host-cache hydration path.
    pub fn pota_parks_page(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<crate::entities::pota_park::FfiPotaPark>, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner.fetch_pota_parks_page(limit, offset)?.into_iter().map(Into::into).collect())
    }

    /// Paged SOTA summit rows ordered by code (`limit` ≤ 1000).
    pub fn sota_summits_page(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiSotaSummit>, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner.fetch_sota_summits_page(limit, offset)?.into_iter().map(summit_to_ffi).collect())
    }

    /// Paged WWFF reference rows ordered by reference (`limit` ≤ 1000).
    pub fn wwff_references_page(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiWwffReference>, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner
            .fetch_wwff_references_page(limit, offset)?
            .into_iter()
            .map(wwff_to_ffi)
            .collect())
    }

    /// Paged SOTA zone rows ordered by code (`limit` ≤ 1000).
    pub fn sota_zones_page(&self, limit: i64, offset: i64) -> Result<Vec<FfiSotaZone>, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner
            .fetch_sota_zones_page(limit, offset)?
            .into_iter()
            .map(|zone| FfiSotaZone {
                code: zone.code,
                altitude_m: zone.altitude_m,
                geometry_geojson: zone.geometry_geojson,
            })
            .collect())
    }

    /// Seed the FCC bookkeeping from a pre-existing download — the iOS
    /// migration path: `FCCLookupService` already holds
    /// `amateur-callsigns.db` plus its SHA-256 sidecar, and seeding lets
    /// [`refresh_fcc`](Self::refresh_fcc) short-circuit instead of
    /// re-downloading hundreds of MB. No-op when the database file is
    /// missing from `data_dir`.
    pub fn seed_fcc_state(&self, sha256: String, record_count: i64) -> Result<(), CwError> {
        if !self.data_dir.join(FCC_DB_FILE).exists() {
            return Ok(());
        }
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        if inner.kv_get(KV_FCC_SHA256)?.is_some() {
            return Ok(());
        }
        inner.kv_set(KV_FCC_SHA256, &sha256)?;
        inner.kv_set(KV_FCC_COUNT, &record_count.to_string())?;
        inner.kv_set(KV_FCC_FETCHED_AT, &now_secs().to_string())?;
        Ok(())
    }

    /// Look a callsign up in the FCC database. `None` when the database has
    /// not been downloaded or the callsign is unknown.
    pub fn fcc_lookup(&self, callsign: String) -> Result<Option<FfiFccRecord>, CwError> {
        let mut guard = self.fcc_conn.lock().expect("fcc mutex poisoned");
        if guard.is_none() {
            let path = self.data_dir.join(FCC_DB_FILE);
            if !path.exists() {
                return Ok(None);
            }
            let conn = rusqlite::Connection::open_with_flags(
                &path,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )
            .map_err(|err| CwError::Store { reason: err.to_string() })?;
            *guard = Some(conn);
        }
        let conn = guard.as_ref().expect("fcc connection just set");
        let record = conn
            .query_row(
                "SELECT callsign, first_name, last_name, city, state, grid, operator_class \
                 FROM callsigns WHERE callsign = ?1",
                rusqlite::params![callsign.to_uppercase()],
                |row| {
                    Ok(FfiFccRecord {
                        callsign: row.get(0)?,
                        first_name: row.get(1)?,
                        last_name: row.get(2)?,
                        city: row.get(3)?,
                        state: row.get(4)?,
                        grid: row.get(5)?,
                        operator_class: row.get(6)?,
                    })
                },
            )
            .map(Some)
            .or_else(|err| match err {
                rusqlite::Error::QueryReturnedNoRows => Ok(None),
                other => Err(CwError::Store { reason: other.to_string() }),
            })?;
        Ok(record)
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl ReferenceDataApi {
    /// Download + parse + store the POTA parks directory (14-day TTL unless
    /// `force`). A fresh download fully replaces the table.
    pub async fn refresh_pota_parks(&self, force: bool) -> Result<FfiRefreshOutcome, CwError> {
        if !force && self.is_fresh(KV_POTA_FETCHED_AT, POTA_TTL_SECS)? {
            return self.unchanged_outcome(|inner| Ok(inner.pota_park_count()?));
        }
        let csv = fetch_reference_csv(
            POTA_PARKS_CSV_URL,
            std::time::Duration::from_secs(CSV_TIMEOUT_SECS),
        )
        .await
        .map_err(net_err)?;
        let parks: Vec<PotaPark> = parse_pota_parks_csv(&csv)
            .into_iter()
            .map(|row| PotaPark {
                reference: row.reference,
                name: row.name,
                location_desc: row.location_desc,
                latitude: row.latitude,
                longitude: row.longitude,
                grid: row.grid,
                entity_id: row.entity_id,
                is_active: row.is_active,
            })
            .collect();
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        inner.replace_pota_parks(&parks)?;
        inner.kv_set(KV_POTA_FETCHED_AT, &now_secs().to_string())?;
        Ok(FfiRefreshOutcome { refreshed: true, count: parks.len() as i64 })
    }

    /// Download + parse + store the SOTA summits list (30-day TTL unless
    /// `force`). Expired summits are dropped at parse time.
    pub async fn refresh_sota_summits(&self, force: bool) -> Result<FfiRefreshOutcome, CwError> {
        if !force && self.is_fresh(KV_SOTA_FETCHED_AT, SOTA_TTL_SECS)? {
            return self.unchanged_outcome(|inner| Ok(inner.sota_summit_count()?));
        }
        let csv = fetch_reference_csv(
            SOTA_SUMMITS_CSV_URL,
            std::time::Duration::from_secs(CSV_TIMEOUT_SECS),
        )
        .await
        .map_err(net_err)?;
        let today = chrono::Utc::now().format("%d/%m/%Y").to_string();
        let summits = parse_sota_summits_csv(&csv, &today);
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        inner.replace_sota_summits(&summits)?;
        inner.kv_set(KV_SOTA_FETCHED_AT, &now_secs().to_string())?;
        Ok(FfiRefreshOutcome { refreshed: true, count: summits.len() as i64 })
    }

    /// Download + parse + store the WWFF directory (30-day TTL unless
    /// `force`). wwff.co is slow — this uses a 300 s transfer timeout.
    pub async fn refresh_wwff_directory(&self, force: bool) -> Result<FfiRefreshOutcome, CwError> {
        if !force && self.is_fresh(KV_WWFF_FETCHED_AT, WWFF_TTL_SECS)? {
            return self.unchanged_outcome(|inner| Ok(inner.wwff_reference_count()?));
        }
        let csv = fetch_reference_csv(
            WWFF_DIRECTORY_CSV_URL,
            std::time::Duration::from_secs(WWFF_TIMEOUT_SECS),
        )
        .await
        .map_err(net_err)?;
        let references = parse_wwff_directory_csv(&csv);
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        inner.replace_wwff_references(&references)?;
        inner.kv_set(KV_WWFF_FETCHED_AT, &now_secs().to_string())?;
        Ok(FfiRefreshOutcome { refreshed: true, count: references.len() as i64 })
    }

    /// Refresh the equipment catalog (24 h TTL unless `force`,
    /// ETag-conditional). `bearer` is the OAuth access token when signed in.
    pub async fn refresh_equipment_catalog(
        &self,
        bearer: Option<String>,
        force: bool,
    ) -> Result<FfiRefreshOutcome, CwError> {
        if !force && self.is_fresh(KV_EQUIPMENT_FETCHED_AT, EQUIPMENT_TTL_SECS)? {
            return self.unchanged_outcome(|inner| {
                Ok(inner
                    .kv_get(KV_EQUIPMENT_COUNT)?
                    .and_then(|raw| raw.parse().ok())
                    .unwrap_or(0))
            });
        }
        let etag = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner.kv_get(KV_EQUIPMENT_ETAG)?
        };
        match self
            .equipment
            .fetch_catalog(etag.as_deref(), bearer.as_deref())
            .await
            .map_err(net_err)?
        {
            Conditional::NotModified => {
                let inner = self.store.inner.lock().expect("store mutex poisoned");
                inner.kv_set(KV_EQUIPMENT_FETCHED_AT, &now_secs().to_string())?;
                let count =
                    inner.kv_get(KV_EQUIPMENT_COUNT)?.and_then(|raw| raw.parse().ok()).unwrap_or(0);
                Ok(FfiRefreshOutcome { refreshed: false, count })
            }
            Conditional::Modified { data: catalog, etag: new_etag } => {
                let raw = serde_json::to_string(&catalog)
                    .map_err(|err| CwError::Store { reason: err.to_string() })?;
                let count = catalog.entries.len() as i64;
                let inner = self.store.inner.lock().expect("store mutex poisoned");
                inner.kv_set(KV_EQUIPMENT_JSON, &raw)?;
                inner.kv_set(KV_EQUIPMENT_COUNT, &count.to_string())?;
                if let Some(tag) = &new_etag {
                    inner.kv_set(KV_EQUIPMENT_ETAG, tag)?;
                }
                inner.kv_set(KV_EQUIPMENT_FETCHED_AT, &now_secs().to_string())?;
                Ok(FfiRefreshOutcome { refreshed: true, count })
            }
        }
    }

    /// Refresh the FCC callsign database (7-day TTL unless `force`). Fetches
    /// the metadata sidecar first; when its SHA-256 matches the cached copy
    /// only the freshness timestamp moves (no re-download) — the
    /// `FCCLookupService` short-circuit.
    pub async fn refresh_fcc(&self, force: bool) -> Result<FfiRefreshOutcome, CwError> {
        let db_path = self.data_dir.join(FCC_DB_FILE);
        if !force && db_path.exists() && self.is_fresh(KV_FCC_FETCHED_AT, FCC_TTL_SECS)? {
            return self.unchanged_outcome(|inner| {
                Ok(inner.kv_get(KV_FCC_COUNT)?.and_then(|raw| raw.parse().ok()).unwrap_or(0))
            });
        }

        let metadata = self.fcc.fetch_metadata().await.map_err(net_err)?;
        if metadata.schema_version > FCC_MAX_SCHEMA_VERSION {
            return Err(CwError::Network {
                reason: format!(
                    "FCC bundle schema v{} is newer than this app understands — update the app",
                    metadata.schema_version
                ),
            });
        }

        let cached_sha = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner.kv_get(KV_FCC_SHA256)?
        };
        if db_path.exists() && cached_sha.as_deref() == Some(metadata.db_sha256.as_str()) {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner.kv_set(KV_FCC_FETCHED_AT, &now_secs().to_string())?;
            inner.kv_set(KV_FCC_COUNT, &metadata.record_count.to_string())?;
            return Ok(FfiRefreshOutcome { refreshed: false, count: metadata.record_count });
        }

        let compressed = self.fcc.download_database().await.map_err(net_err)?;
        let digest = hex_sha256(&compressed);
        if !digest.eq_ignore_ascii_case(&metadata.db_sha256) {
            return Err(CwError::Network {
                reason: "FCC database download failed its SHA-256 check".into(),
            });
        }

        // Decompress to a sibling temp file, then atomically swap it in.
        std::fs::create_dir_all(&self.data_dir).map_err(io_err)?;
        let tmp_path = self.data_dir.join(format!("{FCC_DB_FILE}.tmp"));
        {
            let mut decoder = flate2::read::GzDecoder::new(compressed.as_slice());
            let mut out = std::fs::File::create(&tmp_path).map_err(io_err)?;
            std::io::copy(&mut decoder, &mut out).map_err(io_err)?;
        }
        std::fs::rename(&tmp_path, &db_path).map_err(io_err)?;
        // Drop the cached read handle — it points at the replaced inode.
        *self.fcc_conn.lock().expect("fcc mutex poisoned") = None;

        let inner = self.store.inner.lock().expect("store mutex poisoned");
        inner.kv_set(KV_FCC_SHA256, &metadata.db_sha256)?;
        inner.kv_set(KV_FCC_COUNT, &metadata.record_count.to_string())?;
        inner.kv_set(KV_FCC_FETCHED_AT, &now_secs().to_string())?;
        Ok(FfiRefreshOutcome { refreshed: true, count: metadata.record_count })
    }

    /// One SOTA activation-zone pass: request zones for cached summits that
    /// don't have one yet (500 per POST, like iOS). The server computes
    /// zones lazily, so summits can stay pending across passes — refresh
    /// again later to pick them up. Requires summits to be downloaded
    /// first. Manual-only (no TTL), matching `SOTAZonesCache`.
    ///
    /// Deviation from iOS (which re-requests every summit each pass):
    /// already-resolved zones are skipped, so repeat passes only chase the
    /// pending tail.
    pub async fn refresh_sota_zones(&self) -> Result<FfiZonesRefreshOutcome, CwError> {
        let (inputs, cached_codes) = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            (inner.sota_summit_zone_inputs()?, inner.sota_zone_codes()?)
        };
        if inputs.is_empty() {
            return Err(CwError::Store {
                reason: "Download the SOTA summits database first".into(),
            });
        }
        let cached: std::collections::HashSet<String> = cached_codes.into_iter().collect();
        let wanted: Vec<SotaZoneInput> = inputs
            .into_iter()
            .filter(|(code, _, _, _)| !cached.contains(code))
            .map(|(code, lat, lon, altitude_m)| SotaZoneInput { code, lat, lon, altitude_m })
            .collect();

        let requested = wanted.len() as i64;
        let mut resolved: i64 = 0;
        for (index, chunk) in wanted.chunks(SotaZonesClient::CHUNK_SIZE).enumerate() {
            if index > 0 {
                tokio::time::sleep(std::time::Duration::from_millis(ZONES_CHUNK_DELAY_MS)).await;
            }
            let features = self.zones.fetch_zones(chunk).await.map_err(net_err)?;
            let rows: Vec<SotaZoneRow> = features
                .into_iter()
                .map(|feature| SotaZoneRow {
                    code: feature.code,
                    altitude_m: feature.altitude_m,
                    geometry_geojson: feature.geometry_geojson,
                })
                .collect();
            resolved += rows.len() as i64;
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner.upsert_sota_zones(&rows)?;
        }

        let pending = requested - resolved;
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        inner.kv_set(KV_ZONES_PENDING, &pending.to_string())?;
        inner.kv_set(KV_ZONES_FETCHED_AT, &now_secs().to_string())?;
        Ok(FfiZonesRefreshOutcome {
            requested,
            resolved,
            pending,
            total: inner.sota_zone_count()?,
        })
    }
}

impl ReferenceDataApi {
    /// Whether `key`'s timestamp is inside `ttl_secs`.
    fn is_fresh(&self, key: &str, ttl_secs: i64) -> Result<bool, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        let fetched_at: Option<i64> = inner.kv_get(key)?.and_then(|raw| raw.parse().ok());
        Ok(fetched_at.is_some_and(|ts| now_secs().saturating_sub(ts) < ttl_secs))
    }

    /// `refreshed: false` outcome with a count read under the store lock.
    fn unchanged_outcome(
        &self,
        count: impl Fn(&cw_store::Store) -> Result<i64, CwError>,
    ) -> Result<FfiRefreshOutcome, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(FfiRefreshOutcome { refreshed: false, count: count(&inner)? })
    }
}

fn equipment_entry_to_ffi(entry: cw_net::EquipmentEntryWire) -> FfiEquipmentCatalogEntry {
    FfiEquipmentCatalogEntry {
        id: entry.id,
        name: entry.name,
        manufacturer: entry.manufacturer,
        category: entry.category,
        bands: entry.bands,
        modes: entry.modes,
        max_power_watts: entry.max_power_watts,
        portability: entry.portability,
        weight_grams: entry.weight_grams,
        description: entry.description,
        aliases: entry.aliases,
        image_url: entry.image_url,
        antenna_connector: entry.antenna_connector,
        power_connector: entry.power_connector,
        key_jack: entry.key_jack,
        mic_jack: entry.mic_jack,
    }
}

fn summit_to_ffi(row: cw_domain::reference_csv::SotaSummitRow) -> FfiSotaSummit {
    FfiSotaSummit {
        code: row.code,
        name: row.name,
        association_name: row.association_name,
        region_name: row.region_name,
        altitude_m: row.altitude_m,
        altitude_ft: row.altitude_ft,
        latitude: row.latitude,
        longitude: row.longitude,
        points: row.points,
        bonus_points: row.bonus_points,
        activation_count: row.activation_count,
        last_activation_date: row.last_activation_date,
        last_activation_call: row.last_activation_call,
        grid: row.grid,
    }
}

fn wwff_to_ffi(row: cw_domain::reference_csv::WwffReferenceRow) -> FfiWwffReference {
    FfiWwffReference {
        reference: row.reference,
        name: row.name,
        program: row.program,
        status: row.status,
        continent: row.continent,
        iota: row.iota,
        grid: row.grid,
        latitude: row.latitude,
        longitude: row.longitude,
        iucn_category: row.iucn_category,
        country: row.country,
        region: row.region,
        dxcc_entity: row.dxcc_entity,
    }
}

fn hex_sha256(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let digest = hasher.finalize();
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn now_secs() -> i64 {
    chrono::Utc::now().timestamp()
}

fn net_err(err: cw_net::HttpError) -> CwError {
    CwError::Network { reason: err.to_string() }
}

fn io_err(err: std::io::Error) -> CwError {
    CwError::Store { reason: err.to_string() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_hex_matches_known_vector() {
        assert_eq!(
            hex_sha256(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn gunzip_round_trip() {
        use flate2::write::GzEncoder;
        use flate2::Compression;
        use std::io::{Read, Write};
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(b"sqlite-ish payload").unwrap();
        let compressed = encoder.finish().unwrap();
        let mut decoder = flate2::read::GzDecoder::new(compressed.as_slice());
        let mut out = Vec::new();
        decoder.read_to_end(&mut out).unwrap();
        assert_eq!(out, b"sqlite-ish payload");
    }
}
