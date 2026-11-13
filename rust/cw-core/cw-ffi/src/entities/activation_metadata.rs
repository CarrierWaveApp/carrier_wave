//! FFI surface for `ActivationMetadata` (mirrors `cw-store`'s `ActivationMetadata`).
//!
//! Primary key is `(park_reference, date)` (no `id` field); the by-key fetch uses
//! `fetch_activation_metadata(park_reference, date)` and the plural is
//! `fetch_activation_metadatas`.

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{ActivationMetadata, ActivationMetadataFilter};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiActivationMetadata {
    pub park_reference: String,
    pub date: i64,
    pub title: Option<String>,
    pub watts: Option<i64>,
    pub weather: Option<String>,
    pub solar_conditions: Option<String>,
    pub average_wpm: Option<i64>,
    pub solar_k_index: Option<f64>,
    pub solar_flux: Option<f64>,
    pub solar_sunspots: Option<i64>,
    pub solar_propagation_rating: Option<String>,
    pub solar_a_index: Option<i64>,
    pub solar_band_conditions: Option<String>,
    pub solar_timestamp: Option<i64>,
    pub weather_temperature_f: Option<f64>,
    pub weather_temperature_c: Option<f64>,
    pub weather_humidity: Option<i64>,
    pub weather_wind_speed: Option<f64>,
    pub weather_wind_direction: Option<String>,
    pub weather_description: Option<String>,
    pub weather_timestamp: Option<i64>,
    pub cloud_dirty_flag: bool,
}

// ---------- Conversions ----------

impl From<ActivationMetadata> for FfiActivationMetadata {
    fn from(x: ActivationMetadata) -> Self {
        FfiActivationMetadata {
            park_reference: x.park_reference,
            date: x.date,
            title: x.title,
            watts: x.watts,
            weather: x.weather,
            solar_conditions: x.solar_conditions,
            average_wpm: x.average_wpm,
            solar_k_index: x.solar_k_index,
            solar_flux: x.solar_flux,
            solar_sunspots: x.solar_sunspots,
            solar_propagation_rating: x.solar_propagation_rating,
            solar_a_index: x.solar_a_index,
            solar_band_conditions: x.solar_band_conditions,
            solar_timestamp: x.solar_timestamp,
            weather_temperature_f: x.weather_temperature_f,
            weather_temperature_c: x.weather_temperature_c,
            weather_humidity: x.weather_humidity,
            weather_wind_speed: x.weather_wind_speed,
            weather_wind_direction: x.weather_wind_direction,
            weather_description: x.weather_description,
            weather_timestamp: x.weather_timestamp,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

impl From<FfiActivationMetadata> for ActivationMetadata {
    fn from(x: FfiActivationMetadata) -> Self {
        ActivationMetadata {
            park_reference: x.park_reference,
            date: x.date,
            title: x.title,
            watts: x.watts,
            weather: x.weather,
            solar_conditions: x.solar_conditions,
            average_wpm: x.average_wpm,
            solar_k_index: x.solar_k_index,
            solar_flux: x.solar_flux,
            solar_sunspots: x.solar_sunspots,
            solar_propagation_rating: x.solar_propagation_rating,
            solar_a_index: x.solar_a_index,
            solar_band_conditions: x.solar_band_conditions,
            solar_timestamp: x.solar_timestamp,
            weather_temperature_f: x.weather_temperature_f,
            weather_temperature_c: x.weather_temperature_c,
            weather_humidity: x.weather_humidity,
            weather_wind_speed: x.weather_wind_speed,
            weather_wind_direction: x.weather_wind_direction,
            weather_description: x.weather_description,
            weather_timestamp: x.weather_timestamp,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiActivationMetadataFilter {
    pub since: Option<i64>,
}

impl From<FfiActivationMetadataFilter> for ActivationMetadataFilter {
    fn from(f: FfiActivationMetadataFilter) -> Self {
        ActivationMetadataFilter { since: f.since }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_activation_metadata(&self, item: FfiActivationMetadata) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_activation_metadata(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ActivationMetadata, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of activation-metadata rows in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_activation_metadata_batch(&self, items: Vec<FfiActivationMetadata>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_activation_metadata(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ActivationMetadata, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn activation_metadata_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.activation_metadata_count()?)
    }

    pub fn fetch_activation_metadatas(
        &self,
        filter: FfiActivationMetadataFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiActivationMetadata>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_activation_metadatas(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiActivationMetadata::from).collect())
    }

    pub fn fetch_activation_metadata(
        &self,
        park_reference: String,
        date: i64,
    ) -> Result<Option<FfiActivationMetadata>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .fetch_activation_metadata(&park_reference, date)?
            .map(FfiActivationMetadata::from))
    }

    pub fn delete_activation_metadata(
        &self,
        park_reference: String,
        date: i64,
    ) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_activation_metadata(&park_reference, date)?;
        }
        self.notify(FfiStoreChange {
            table: FfiStoreTable::ActivationMetadata,
            kind: FfiChangeKind::Delete,
        });
        Ok(())
    }
}
