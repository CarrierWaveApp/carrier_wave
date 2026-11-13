//! The ActivationMetadata entity + its bounded query API.
//! Mirrors CarrierWaveData/Models/ActivationMetadata.swift.
//!
//! Primary key: `(park_reference, date)`. The Swift model has no `id`; it stores
//! one row per park per day (the initializer normalises `date` to midnight UTC),
//! and the app + cloud-sync layer look it up by park *and* date. Keying on
//! `park_reference` alone collapses multi-day activations of the same park.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// Operator notes and conditions captured during a park activation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActivationMetadata {
    /// Part of the natural primary key — POTA/SOTA reference (e.g. "K-1234").
    pub park_reference: String,
    /// Part of the natural primary key. Unix seconds, UTC (Swift normalises to
    /// midnight UTC before storing) — one row per park per day.
    pub date: i64,
    pub title: Option<String>,
    pub watts: Option<i64>,
    pub weather: Option<String>,
    pub solar_conditions: Option<String>,
    pub average_wpm: Option<i64>,

    // Structured Solar Fields
    pub solar_k_index: Option<f64>,
    pub solar_flux: Option<f64>,
    pub solar_sunspots: Option<i64>,
    pub solar_propagation_rating: Option<String>,
    pub solar_a_index: Option<i64>,
    /// JSON text — stored as a serialised string in Swift (`solarBandConditions`).
    pub solar_band_conditions: Option<String>,
    /// Unix seconds, UTC.
    pub solar_timestamp: Option<i64>,

    // Structured Weather Fields
    pub weather_temperature_f: Option<f64>,
    pub weather_temperature_c: Option<f64>,
    pub weather_humidity: Option<i64>,
    pub weather_wind_speed: Option<f64>,
    pub weather_wind_direction: Option<String>,
    pub weather_description: Option<String>,
    /// Unix seconds, UTC.
    pub weather_timestamp: Option<i64>,

    /// Whether this row has un-synced local changes (sync journal flag).
    pub cloud_dirty_flag: bool,
}

/// DDL for the `activation_metadata` table and its supporting indexes.
pub(crate) const ACTIVATION_METADATA_DDL: &str = r#"
    CREATE TABLE IF NOT EXISTS activation_metadata (
        park_reference              TEXT NOT NULL,
        date                        INTEGER NOT NULL,
        title                       TEXT,
        watts                       INTEGER,
        weather                     TEXT,
        solar_conditions            TEXT,
        average_wpm                 INTEGER,
        solar_k_index               REAL,
        solar_flux                  REAL,
        solar_sunspots              INTEGER,
        solar_propagation_rating    TEXT,
        solar_a_index               INTEGER,
        solar_band_conditions       TEXT,
        solar_timestamp             INTEGER,
        weather_temperature_f       REAL,
        weather_temperature_c       REAL,
        weather_humidity            INTEGER,
        weather_wind_speed          REAL,
        weather_wind_direction      TEXT,
        weather_description         TEXT,
        weather_timestamp           INTEGER,
        cloud_dirty_flag            INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (park_reference, date)
    );

    CREATE INDEX IF NOT EXISTS idx_am_date             ON activation_metadata(date);
    CREATE INDEX IF NOT EXISTS idx_am_cloud_dirty_flag ON activation_metadata(cloud_dirty_flag);
"#;

/// Bounded query parameters for `activation_metadata`.
#[derive(Debug, Clone, Default)]
pub struct ActivationMetadataFilter {
    /// Only records at/after this unix-seconds date.
    pub since: Option<i64>,
}

impl Store {
    /// Insert or replace an `ActivationMetadata` record.
    pub fn upsert_activation_metadata(&self, am: &ActivationMetadata) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO activation_metadata (
                park_reference, date, title, watts, weather, solar_conditions, average_wpm,
                solar_k_index, solar_flux, solar_sunspots, solar_propagation_rating,
                solar_a_index, solar_band_conditions, solar_timestamp,
                weather_temperature_f, weather_temperature_c, weather_humidity,
                weather_wind_speed, weather_wind_direction, weather_description,
                weather_timestamp, cloud_dirty_flag
            )
            VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7,
                ?8, ?9, ?10, ?11,
                ?12, ?13, ?14,
                ?15, ?16, ?17,
                ?18, ?19, ?20,
                ?21, ?22
            )
            ON CONFLICT(park_reference, date) DO UPDATE SET
                title=excluded.title,
                watts=excluded.watts,
                weather=excluded.weather,
                solar_conditions=excluded.solar_conditions,
                average_wpm=excluded.average_wpm,
                solar_k_index=excluded.solar_k_index,
                solar_flux=excluded.solar_flux,
                solar_sunspots=excluded.solar_sunspots,
                solar_propagation_rating=excluded.solar_propagation_rating,
                solar_a_index=excluded.solar_a_index,
                solar_band_conditions=excluded.solar_band_conditions,
                solar_timestamp=excluded.solar_timestamp,
                weather_temperature_f=excluded.weather_temperature_f,
                weather_temperature_c=excluded.weather_temperature_c,
                weather_humidity=excluded.weather_humidity,
                weather_wind_speed=excluded.weather_wind_speed,
                weather_wind_direction=excluded.weather_wind_direction,
                weather_description=excluded.weather_description,
                weather_timestamp=excluded.weather_timestamp,
                cloud_dirty_flag=excluded.cloud_dirty_flag
            "#,
            params![
                am.park_reference,
                am.date,
                am.title,
                am.watts,
                am.weather,
                am.solar_conditions,
                am.average_wpm,
                am.solar_k_index,
                am.solar_flux,
                am.solar_sunspots,
                am.solar_propagation_rating,
                am.solar_a_index,
                am.solar_band_conditions,
                am.solar_timestamp,
                am.weather_temperature_f,
                am.weather_temperature_c,
                am.weather_humidity,
                am.weather_wind_speed,
                am.weather_wind_direction,
                am.weather_description,
                am.weather_timestamp,
                am.cloud_dirty_flag as i64,
            ],
        )?;
        Ok(())
    }

    /// Total count of `activation_metadata` rows.
    pub fn activation_metadata_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM activation_metadata", [], |row| {
                row.get(0)
            })?)
    }

    /// Fetch a single `ActivationMetadata` by its `(park_reference, date)` key,
    /// or `None` if absent.
    /// Delete an `activation_metadata` row by its `(park_reference, date)` key.
    /// Idempotent — a missing key succeeds.
    pub fn delete_activation_metadata(&self, park_reference: &str, date: i64) -> Result<()> {
        self.conn.execute(
            "DELETE FROM activation_metadata WHERE park_reference = ?1 AND date = ?2",
            params![park_reference, date],
        )?;
        Ok(())
    }

    pub fn fetch_activation_metadata(
        &self,
        park_reference: &str,
        date: i64,
    ) -> Result<Option<ActivationMetadata>> {
        let sql = "SELECT park_reference, date, title, watts, weather, solar_conditions, \
            average_wpm, solar_k_index, solar_flux, solar_sunspots, solar_propagation_rating, \
            solar_a_index, solar_band_conditions, solar_timestamp, \
            weather_temperature_f, weather_temperature_c, weather_humidity, \
            weather_wind_speed, weather_wind_direction, weather_description, \
            weather_timestamp, cloud_dirty_flag \
            FROM activation_metadata WHERE park_reference = ? AND date = ?";
        Ok(self
            .conn
            .query_row(
                sql,
                params![park_reference, date],
                Self::row_to_activation_metadata,
            )
            .optional()?)
    }

    /// Bounded, paginated fetch with optional filters.
    /// `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_activation_metadatas(
        &self,
        filter: &ActivationMetadataFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<ActivationMetadata>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded {
                requested: limit,
                max: MAX_FETCH_LIMIT,
            });
        }

        let mut sql = String::from(
            "SELECT park_reference, date, title, watts, weather, solar_conditions, \
            average_wpm, solar_k_index, solar_flux, solar_sunspots, solar_propagation_rating, \
            solar_a_index, solar_band_conditions, solar_timestamp, \
            weather_temperature_f, weather_temperature_c, weather_humidity, \
            weather_wind_speed, weather_wind_direction, weather_description, \
            weather_timestamp, cloud_dirty_flag \
            FROM activation_metadata WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(since) = filter.since {
            sql.push_str(" AND date >= ?");
            args.push(Box::new(since));
        }
        sql.push_str(" ORDER BY date DESC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_activation_metadata)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_activation_metadata(row: &rusqlite::Row<'_>) -> rusqlite::Result<ActivationMetadata> {
        Ok(ActivationMetadata {
            park_reference: row.get(0)?,
            date: row.get(1)?,
            title: row.get(2)?,
            watts: row.get(3)?,
            weather: row.get(4)?,
            solar_conditions: row.get(5)?,
            average_wpm: row.get(6)?,
            solar_k_index: row.get(7)?,
            solar_flux: row.get(8)?,
            solar_sunspots: row.get(9)?,
            solar_propagation_rating: row.get(10)?,
            solar_a_index: row.get(11)?,
            solar_band_conditions: row.get(12)?,
            solar_timestamp: row.get(13)?,
            weather_temperature_f: row.get(14)?,
            weather_temperature_c: row.get(15)?,
            weather_humidity: row.get(16)?,
            weather_wind_speed: row.get(17)?,
            weather_wind_direction: row.get(18)?,
            weather_description: row.get(19)?,
            weather_timestamp: row.get(20)?,
            cloud_dirty_flag: row.get::<_, i64>(21)? != 0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(park_ref: &str, date: i64) -> ActivationMetadata {
        ActivationMetadata {
            park_reference: park_ref.to_string(),
            date,
            title: Some("Summit Run".to_string()),
            watts: Some(10),
            weather: Some("Sunny".to_string()),
            solar_conditions: Some("Good".to_string()),
            average_wpm: Some(20),
            solar_k_index: Some(1.0),
            solar_flux: Some(120.5),
            solar_sunspots: Some(45),
            solar_propagation_rating: Some("Good".to_string()),
            solar_a_index: Some(3),
            solar_band_conditions: Some(r#"{"20m":"Good"}"#.to_string()),
            solar_timestamp: Some(date),
            weather_temperature_f: Some(72.0),
            weather_temperature_c: Some(22.2),
            weather_humidity: Some(55),
            weather_wind_speed: Some(5.0),
            weather_wind_direction: Some("NW".to_string()),
            weather_description: Some("Clear".to_string()),
            weather_timestamp: Some(date),
            cloud_dirty_flag: false,
        }
    }

    #[test]
    fn delete_by_composite_key() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_activation_metadata(&sample("K-1234", 1_000_000)).unwrap();
        store.upsert_activation_metadata(&sample("K-1234", 2_000_000)).unwrap();
        // Deleting one (park, date) leaves the same park's other date intact.
        store.delete_activation_metadata("K-1234", 1_000_000).unwrap();
        assert_eq!(store.activation_metadata_count().unwrap(), 1);
        assert!(store.fetch_activation_metadata("K-1234", 1_000_000).unwrap().is_none());
        assert!(store.fetch_activation_metadata("K-1234", 2_000_000).unwrap().is_some());
        store.delete_activation_metadata("K-1234", 2_000_000).unwrap();
        assert_eq!(store.activation_metadata_count().unwrap(), 0);
    }

    #[test]
    fn upsert_count_and_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activation_metadata(&sample("K-1234", 1_000_000))
            .unwrap();
        store
            .upsert_activation_metadata(&sample("K-5678", 2_000_000))
            .unwrap();
        assert_eq!(store.activation_metadata_count().unwrap(), 2);

        let am = store
            .fetch_activation_metadata("K-1234", 1_000_000)
            .unwrap()
            .unwrap();
        assert_eq!(am.park_reference, "K-1234");
        assert_eq!(am.watts, Some(10));
        assert!((am.solar_flux.unwrap() - 120.5).abs() < f64::EPSILON);
    }

    #[test]
    fn same_park_different_dates_are_distinct_rows() {
        // The natural key is (park_reference, date): activating the same park on
        // two days must yield two rows, not one. Regression for the importer's
        // verify mismatch caused by keying on park_reference alone.
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activation_metadata(&sample("K-1234", 1_000_000))
            .unwrap();
        store
            .upsert_activation_metadata(&sample("K-1234", 2_000_000))
            .unwrap();
        assert_eq!(store.activation_metadata_count().unwrap(), 2);
        assert!(store
            .fetch_activation_metadata("K-1234", 1_000_000)
            .unwrap()
            .is_some());
        assert!(store
            .fetch_activation_metadata("K-1234", 2_000_000)
            .unwrap()
            .is_some());
    }

    #[test]
    fn fetch_since_filter() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activation_metadata(&sample("K-1234", 1_000_000))
            .unwrap();
        store
            .upsert_activation_metadata(&sample("K-5678", 2_000_000))
            .unwrap();

        let filter = ActivationMetadataFilter {
            since: Some(1_500_000),
        };
        let rows = store.fetch_activation_metadatas(&filter, 100, 0).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].park_reference, "K-5678");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activation_metadata(&sample("K-1234", 1_000_000))
            .unwrap();
        let mut updated = sample("K-1234", 1_000_000);
        updated.watts = Some(100);
        updated.cloud_dirty_flag = true;
        store.upsert_activation_metadata(&updated).unwrap();
        assert_eq!(store.activation_metadata_count().unwrap(), 1);
        let am = store
            .fetch_activation_metadata("K-1234", 1_000_000)
            .unwrap()
            .unwrap();
        assert_eq!(am.watts, Some(100));
        assert!(am.cloud_dirty_flag);
    }

    #[test]
    fn missing_ref_returns_none() {
        let store = Store::open_in_memory("k").unwrap();
        assert!(store
            .fetch_activation_metadata("no-such-ref", 0)
            .unwrap()
            .is_none());
    }

    #[test]
    fn fetch_limit_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_activation_metadatas(
                &ActivationMetadataFilter::default(),
                MAX_FETCH_LIMIT + 1,
                0,
            )
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
