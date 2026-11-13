//! FFI surface for `LoggingSession` (mirrors `cw-store`'s `LoggingSession`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{LoggingSession, LoggingSessionFilter};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiLoggingSession {
    pub id: String,
    pub my_callsign: String,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    pub frequency: Option<f64>,
    pub mode: String,
    pub activation_type_raw_value: String,
    pub programs_raw_value: String,
    pub status_raw_value: String,
    pub park_reference: Option<String>,
    pub sota_reference: Option<String>,
    pub mission_reference: Option<String>,
    pub wwff_reference: Option<String>,
    pub my_grid: Option<String>,
    pub power: Option<i64>,
    pub my_rig: Option<String>,
    pub notes: Option<String>,
    pub qso_comment: Option<String>,
    pub custom_title: Option<String>,
    pub qso_count: i64,
    pub spot_comments_data: Option<Vec<u8>>,
    pub is_rove: bool,
    pub rove_stops_data: Option<Vec<u8>>,
    pub my_antenna: Option<String>,
    pub my_key: Option<String>,
    pub my_mic: Option<String>,
    pub extra_equipment: Option<String>,
    pub attendees: Option<String>,
    pub photo_filenames: String,
    pub radio_item_id: Option<String>,
    pub station_callsign: Option<String>,
    pub operator_callsigns_raw_value: String,
    pub solar_k_index: Option<f64>,
    pub solar_flux: Option<f64>,
    pub solar_sunspots: Option<i64>,
    pub solar_propagation_rating: Option<String>,
    pub solar_a_index: Option<i64>,
    pub solar_band_conditions: Option<String>,
    pub solar_timestamp: Option<i64>,
    pub solar_conditions: Option<String>,
    pub weather_temperature_f: Option<f64>,
    pub weather_temperature_c: Option<f64>,
    pub weather_humidity: Option<i64>,
    pub weather_wind_speed: Option<f64>,
    pub weather_wind_direction: Option<String>,
    pub weather_description: Option<String>,
    pub weather_timestamp: Option<i64>,
    pub weather: Option<String>,
    pub cloud_dirty_flag: bool,
    pub contest_id: Option<String>,
    pub contest_category: Option<String>,
    pub contest_overlay_category: Option<String>,
    pub contest_power: Option<String>,
    pub contest_bands: Option<String>,
    pub contest_operator: Option<String>,
    pub activation_latitude: Option<f64>,
    pub activation_longitude: Option<f64>,
    pub activation_distance_miles: Option<f64>,
    pub activation_elevation_gain_feet: Option<f64>,
    pub ruck_weight_pounds: Option<f64>,
    pub qrp_activation: bool,
    pub with_pets: bool,
    pub with_kids: bool,
    pub winlink_sent: bool,
    pub aprs_sent: bool,
    pub varac_sent: bool,
    pub adaptive_sport: bool,
    pub track_points_data: Option<Vec<u8>>,
    pub tota_category_raw_value: Option<String>,
    pub personal_effort_factor: Option<i64>,
    pub first_activation_of_tile_ever: bool,
    pub winter_activation_override: Option<i64>,
    pub tiles_activated_data: Option<Vec<u8>>,
    pub tota_t3_candidates_data: Option<Vec<u8>>,
    pub tota_t3_snapshot_at: Option<i64>,
    pub tota_official_points: Option<f64>,
}

// ---------- Conversions ----------

impl From<LoggingSession> for FfiLoggingSession {
    fn from(x: LoggingSession) -> Self {
        FfiLoggingSession {
            id: x.id,
            my_callsign: x.my_callsign,
            started_at: x.started_at,
            ended_at: x.ended_at,
            frequency: x.frequency,
            mode: x.mode,
            activation_type_raw_value: x.activation_type_raw_value,
            programs_raw_value: x.programs_raw_value,
            status_raw_value: x.status_raw_value,
            park_reference: x.park_reference,
            sota_reference: x.sota_reference,
            mission_reference: x.mission_reference,
            wwff_reference: x.wwff_reference,
            my_grid: x.my_grid,
            power: x.power,
            my_rig: x.my_rig,
            notes: x.notes,
            qso_comment: x.qso_comment,
            custom_title: x.custom_title,
            qso_count: x.qso_count,
            spot_comments_data: x.spot_comments_data,
            is_rove: x.is_rove,
            rove_stops_data: x.rove_stops_data,
            my_antenna: x.my_antenna,
            my_key: x.my_key,
            my_mic: x.my_mic,
            extra_equipment: x.extra_equipment,
            attendees: x.attendees,
            photo_filenames: x.photo_filenames,
            radio_item_id: x.radio_item_id,
            station_callsign: x.station_callsign,
            operator_callsigns_raw_value: x.operator_callsigns_raw_value,
            solar_k_index: x.solar_k_index,
            solar_flux: x.solar_flux,
            solar_sunspots: x.solar_sunspots,
            solar_propagation_rating: x.solar_propagation_rating,
            solar_a_index: x.solar_a_index,
            solar_band_conditions: x.solar_band_conditions,
            solar_timestamp: x.solar_timestamp,
            solar_conditions: x.solar_conditions,
            weather_temperature_f: x.weather_temperature_f,
            weather_temperature_c: x.weather_temperature_c,
            weather_humidity: x.weather_humidity,
            weather_wind_speed: x.weather_wind_speed,
            weather_wind_direction: x.weather_wind_direction,
            weather_description: x.weather_description,
            weather_timestamp: x.weather_timestamp,
            weather: x.weather,
            cloud_dirty_flag: x.cloud_dirty_flag,
            contest_id: x.contest_id,
            contest_category: x.contest_category,
            contest_overlay_category: x.contest_overlay_category,
            contest_power: x.contest_power,
            contest_bands: x.contest_bands,
            contest_operator: x.contest_operator,
            activation_latitude: x.activation_latitude,
            activation_longitude: x.activation_longitude,
            activation_distance_miles: x.activation_distance_miles,
            activation_elevation_gain_feet: x.activation_elevation_gain_feet,
            ruck_weight_pounds: x.ruck_weight_pounds,
            qrp_activation: x.qrp_activation,
            with_pets: x.with_pets,
            with_kids: x.with_kids,
            winlink_sent: x.winlink_sent,
            aprs_sent: x.aprs_sent,
            varac_sent: x.varac_sent,
            adaptive_sport: x.adaptive_sport,
            track_points_data: x.track_points_data,
            tota_category_raw_value: x.tota_category_raw_value,
            personal_effort_factor: x.personal_effort_factor,
            first_activation_of_tile_ever: x.first_activation_of_tile_ever,
            winter_activation_override: x.winter_activation_override,
            tiles_activated_data: x.tiles_activated_data,
            tota_t3_candidates_data: x.tota_t3_candidates_data,
            tota_t3_snapshot_at: x.tota_t3_snapshot_at,
            tota_official_points: x.tota_official_points,
        }
    }
}

impl From<FfiLoggingSession> for LoggingSession {
    fn from(x: FfiLoggingSession) -> Self {
        LoggingSession {
            id: x.id,
            my_callsign: x.my_callsign,
            started_at: x.started_at,
            ended_at: x.ended_at,
            frequency: x.frequency,
            mode: x.mode,
            activation_type_raw_value: x.activation_type_raw_value,
            programs_raw_value: x.programs_raw_value,
            status_raw_value: x.status_raw_value,
            park_reference: x.park_reference,
            sota_reference: x.sota_reference,
            mission_reference: x.mission_reference,
            wwff_reference: x.wwff_reference,
            my_grid: x.my_grid,
            power: x.power,
            my_rig: x.my_rig,
            notes: x.notes,
            qso_comment: x.qso_comment,
            custom_title: x.custom_title,
            qso_count: x.qso_count,
            spot_comments_data: x.spot_comments_data,
            is_rove: x.is_rove,
            rove_stops_data: x.rove_stops_data,
            my_antenna: x.my_antenna,
            my_key: x.my_key,
            my_mic: x.my_mic,
            extra_equipment: x.extra_equipment,
            attendees: x.attendees,
            photo_filenames: x.photo_filenames,
            radio_item_id: x.radio_item_id,
            station_callsign: x.station_callsign,
            operator_callsigns_raw_value: x.operator_callsigns_raw_value,
            solar_k_index: x.solar_k_index,
            solar_flux: x.solar_flux,
            solar_sunspots: x.solar_sunspots,
            solar_propagation_rating: x.solar_propagation_rating,
            solar_a_index: x.solar_a_index,
            solar_band_conditions: x.solar_band_conditions,
            solar_timestamp: x.solar_timestamp,
            solar_conditions: x.solar_conditions,
            weather_temperature_f: x.weather_temperature_f,
            weather_temperature_c: x.weather_temperature_c,
            weather_humidity: x.weather_humidity,
            weather_wind_speed: x.weather_wind_speed,
            weather_wind_direction: x.weather_wind_direction,
            weather_description: x.weather_description,
            weather_timestamp: x.weather_timestamp,
            weather: x.weather,
            cloud_dirty_flag: x.cloud_dirty_flag,
            contest_id: x.contest_id,
            contest_category: x.contest_category,
            contest_overlay_category: x.contest_overlay_category,
            contest_power: x.contest_power,
            contest_bands: x.contest_bands,
            contest_operator: x.contest_operator,
            activation_latitude: x.activation_latitude,
            activation_longitude: x.activation_longitude,
            activation_distance_miles: x.activation_distance_miles,
            activation_elevation_gain_feet: x.activation_elevation_gain_feet,
            ruck_weight_pounds: x.ruck_weight_pounds,
            qrp_activation: x.qrp_activation,
            with_pets: x.with_pets,
            with_kids: x.with_kids,
            winlink_sent: x.winlink_sent,
            aprs_sent: x.aprs_sent,
            varac_sent: x.varac_sent,
            adaptive_sport: x.adaptive_sport,
            track_points_data: x.track_points_data,
            tota_category_raw_value: x.tota_category_raw_value,
            personal_effort_factor: x.personal_effort_factor,
            first_activation_of_tile_ever: x.first_activation_of_tile_ever,
            winter_activation_override: x.winter_activation_override,
            tiles_activated_data: x.tiles_activated_data,
            tota_t3_candidates_data: x.tota_t3_candidates_data,
            tota_t3_snapshot_at: x.tota_t3_snapshot_at,
            tota_official_points: x.tota_official_points,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiLoggingSessionFilter {
    pub my_callsign: Option<String>,
    pub since: Option<i64>,
    pub dirty_only: Option<bool>,
}

impl From<FfiLoggingSessionFilter> for LoggingSessionFilter {
    fn from(f: FfiLoggingSessionFilter) -> Self {
        LoggingSessionFilter {
            my_callsign: f.my_callsign,
            since: f.since,
            dirty_only: f.dirty_only,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_logging_session(&self, item: FfiLoggingSession) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_logging_session(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::LoggingSession, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of logging sessions in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_logging_sessions(&self, items: Vec<FfiLoggingSession>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_logging_session(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::LoggingSession, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn logging_session_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.logging_session_count()?)
    }

    pub fn fetch_logging_sessions(
        &self,
        filter: FfiLoggingSessionFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiLoggingSession>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_logging_sessions(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiLoggingSession::from).collect())
    }

    pub fn fetch_logging_session(&self, id: String) -> Result<Option<FfiLoggingSession>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_logging_session(&id)?.map(FfiLoggingSession::from))
    }

    pub fn delete_logging_session(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_logging_session(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::LoggingSession, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
