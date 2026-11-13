//! Map view-model: one-call QSO map aggregation (`MapApi.qso_map`) plus free
//! geo-helper exports consumed independently by both platforms (great-circle
//! arcs, bounds, Maidenhead tile bounds, and the standalone stats aggregator
//! `compute_map_statistics`, which iOS `ActivationStatsHelper` also switches
//! to). Port of the deleted Swift `QSOMapView+Data.swift` /
//! `MapDataLoadingActor.swift` — see `.superpowers/sdd/task-5-brief.md` for
//! the aggregation semantics this must match exactly.

mod aggregate;
mod cards;
mod filter;
mod records;

use std::collections::HashMap;
use std::sync::Arc;

use cw_domain::great_circle::great_circle_segments;
use cw_domain::map_bounds::{bounds_for, camera_spans, requires_globe_view};
use cw_domain::maidenhead;
use cw_store::{ActivationMetadataFilter, LoggingSessionFilter, MAX_FETCH_LIMIT};

use self::aggregate::{MetaEntry, MetaIndex};
pub use records::*;

use crate::{CwError, FfiCoordinate, FieldStore};

/// Map view-model API bound to a [`FieldStore`]. Stateless — every call reads
/// straight from the store, mirroring [`crate::session_api::SessionApi`].
#[derive(uniffi::Object)]
pub struct MapApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl MapApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        MapApi { store }
    }

    /// One-call QSO map view-model: filtered annotations/arcs/bounds/stats
    /// plus the filter-sheet options. Empty store → empty data, no error.
    pub fn qso_map(&self, filter: FfiMapFilter) -> Result<FfiQsoMapData, CwError> {
        let parsed = cw_domain::query::parse(&filter::filter_query_string(&filter)).map_err(CwError::from)?;

        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.qso_map_rows(&parsed, filter.confirmed_only, None)?;
        let opts = store.qso_map_filter_options()?;
        let meta = build_metadata_index(&store)?;
        drop(store);

        Ok(aggregate::build(rows, opts, &meta, &filter))
    }
}

/// Antenna/key/mic pulled from a `LoggingSession`, keyed by activation
/// reference + UTC day. Mirrors the Swift `SessionEquipment` snapshot.
#[derive(Debug, Clone, Default)]
struct SessionEquipment {
    antenna: Option<String>,
    key: Option<String>,
    mic: Option<String>,
}

/// Build the `"{park}|yyyy-MM-dd"` metadata lookup index: activation metadata
/// (weather/solar/WPM) joined with session equipment (antenna/key/mic) from
/// sessions that have a `park_reference`/`sota_reference` and at least one of
/// antenna/key/mic set. Port of `fetchActivationMetadata` /
/// `fetchSessionEquipment` (`MapDataLoadingActor.swift:330-392`).
///
/// Session equipment is keyed by `park_reference` if present, else
/// `sota_reference` — the two reference columns `MapDataLoadingActor`'s
/// predicate admits. `MapQsoRow.park` (the key rows are looked up by) is the
/// POTA park reference, so `park_reference` matches take priority.
fn build_metadata_index(store: &cw_store::Store) -> Result<MetaIndex, CwError> {
    let metadatas = store.fetch_activation_metadatas(&ActivationMetadataFilter::default(), MAX_FETCH_LIMIT, 0)?;
    let sessions = store.fetch_logging_sessions(&LoggingSessionFilter::default(), MAX_FETCH_LIMIT, 0)?;

    let mut equipment: HashMap<String, SessionEquipment> = HashMap::new();
    for session in &sessions {
        let Some(ref_key) = session.park_reference.clone().or_else(|| session.sota_reference.clone()) else {
            continue;
        };
        let has_equipment = session.my_antenna.is_some() || session.my_key.is_some() || session.my_mic.is_some();
        if !has_equipment {
            continue;
        }
        let day = day_string(session.started_at);
        equipment.insert(
            format!("{ref_key}|{day}"),
            SessionEquipment {
                antenna: session.my_antenna.clone(),
                key: session.my_key.clone(),
                mic: session.my_mic.clone(),
            },
        );
    }

    let mut index = MetaIndex::new();
    for meta in metadatas {
        let has_data = meta.weather.is_some() || meta.solar_conditions.is_some() || meta.average_wpm.is_some();
        let key = format!("{}|{}", meta.park_reference, day_string(meta.date));
        let equip = equipment.get(&key).cloned().unwrap_or_default();
        if !has_data && equip.antenna.is_none() && equip.key.is_none() && equip.mic.is_none() {
            continue;
        }
        index.insert(
            key,
            MetaEntry {
                weather: meta.weather,
                solar_conditions: meta.solar_conditions,
                average_wpm: meta.average_wpm,
                antenna: equip.antenna,
                key: equip.key,
                mic: equip.mic,
            },
        );
    }
    Ok(index)
}

/// UTC day string (`yyyy-MM-dd`) for a unix-seconds timestamp. Mirrors
/// `MapDataLoadingActor.dateKeyFormatter`.
fn day_string(unix: i64) -> String {
    chrono::DateTime::from_timestamp(unix, 0)
        .map(|dt| dt.format("%Y-%m-%d").to_string())
        .unwrap_or_default()
}

/// Great-circle arc between two coordinates, split at antimeridian crossings.
/// Free export (not store-bound) so both platforms can preview a path without
/// a `MapApi` instance.
#[uniffi::export]
pub fn great_circle_arc(from: FfiCoordinate, to: FfiCoordinate, segments: u32) -> Vec<FfiMapPolyline> {
    great_circle_segments((from.latitude, from.longitude), (to.latitude, to.longitude), segments as usize)
        .into_iter()
        .map(|seg| FfiMapPolyline {
            points: seg.into_iter().map(|(latitude, longitude)| FfiCoordinate { latitude, longitude }).collect(),
        })
        .collect()
}

/// Timeline replay: spot opacity for a spot of the given age (full until 5 min,
/// then fades linearly to zero at 10 min). Free export wrapping
/// [`cw_domain::timeline::spot_opacity`].
#[uniffi::export]
pub fn timeline_spot_opacity(age_secs: f64) -> f64 {
    cw_domain::timeline::spot_opacity(age_secs)
}

/// Timeline replay: spot decay fraction (1.0 at birth → 0.3 at the 10-min
/// limit). Free export wrapping [`cw_domain::timeline::spot_decay_fraction`].
#[uniffi::export]
pub fn timeline_spot_decay(age_secs: f64) -> f64 {
    cw_domain::timeline::spot_decay_fraction(age_secs)
}

/// Timeline replay: SNR → marker diameter in points (10–36). Free export
/// wrapping [`cw_domain::timeline::snr_marker_size`].
#[uniffi::export]
pub fn timeline_snr_marker_size(snr: Option<i64>) -> f64 {
    cw_domain::timeline::snr_marker_size(snr)
}

/// Timeline replay: SNR → color-band index (0 red / 1 orange / 2 blue / 3
/// green). Free export wrapping [`cw_domain::timeline::snr_color_band`].
#[uniffi::export]
pub fn timeline_snr_color_band(snr: i64) -> u8 {
    cw_domain::timeline::snr_color_band(snr)
}

/// Bounding region (+ padded camera spans, + globe-view flag) for a set of
/// coordinates. `None` if `coords` is empty.
#[uniffi::export]
pub fn map_bounds_for(coords: Vec<FfiCoordinate>) -> Option<FfiMapBounds> {
    let points: Vec<(f64, f64)> = coords.iter().map(|c| (c.latitude, c.longitude)).collect();
    let bounds = bounds_for(&points)?;
    let (camera_lat_span, camera_lon_span) = camera_spans(&bounds);
    Some(FfiMapBounds {
        center_lat: bounds.center_lat,
        center_lon: bounds.center_lon,
        lat_span: bounds.lat_span,
        lon_span: bounds.lon_span,
        camera_lat_span,
        camera_lon_span,
        requires_globe_view: requires_globe_view(&bounds),
    })
}

/// SW/NE corners of a 6-char (or longer) Maidenhead tile, for Android
/// grid-overlay polygons. Requires at least 6 characters — `None` for
/// anything shorter (including 4-char grid squares; use
/// `maidenhead_grid_bounds` for those) or otherwise invalid input.
#[uniffi::export]
pub fn maidenhead_tile_bounds(tile: String) -> Option<FfiGridBounds> {
    let (sw, ne) = maidenhead::tile_bounds(&tile)?;
    Some(FfiGridBounds { south: sw.latitude, west: sw.longitude, north: ne.latitude, east: ne.longitude })
}

/// SW/NE corners of a 4-char Maidenhead grid square (2° lon × 1° lat), for
/// Android grid-overlay polygons. `None` for an invalid or too-short grid.
/// Use `maidenhead_tile_bounds` for 6-char (or longer) subsquares.
#[uniffi::export]
pub fn maidenhead_grid_bounds(grid: String) -> Option<FfiGridBounds> {
    let (sw, ne) = maidenhead::grid_bounds(&grid)?;
    Some(FfiGridBounds { south: sw.latitude, west: sw.longitude, north: ne.latitude, east: ne.longitude })
}

/// Standalone stats aggregator over caller-supplied rows — the same
/// computation `MapApi::qso_map` runs internally, exposed for callers (e.g.
/// iOS `ActivationStatsHelper`, Task 7) that already hold rows in memory and
/// don't need the full fetch-and-aggregate round trip.
#[uniffi::export]
pub fn compute_map_statistics(rows: Vec<FfiMapStatInput>) -> FfiMapStats {
    let mapped: Vec<cw_store::MapQsoRow> = rows
        .into_iter()
        .map(|r| cw_store::MapQsoRow {
            id: String::new(),
            callsign: String::new(),
            band: None,
            mode: None,
            qso_date: r.qso_date,
            my_grid: r.my_grid,
            their_grid: r.their_grid.unwrap_or_default(),
            park: None,
            state: r.state,
            dxcc: r.dxcc,
            qrz_confirmed: false,
            lotw_confirmed: false,
            power: r.power,
            logging_session_id: r.logging_session_id,
            my_rig: None,
        })
        .collect();
    let refs: Vec<&cw_store::MapQsoRow> = mapped.iter().collect();
    aggregate::compute_stats(&refs)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::FieldStore;

    fn store() -> Arc<FieldStore> {
        Arc::new(FieldStore::open_in_memory("k".into()).unwrap())
    }

    #[test]
    fn qso_map_end_to_end() {
        let field_store = store();
        {
            let inner = field_store.inner.lock().unwrap();
            inner
                .upsert_qso(&cw_store::Qso {
                    their_grid: Some("EM12".to_string()),
                    my_grid: Some("CM87".to_string()),
                    band: Some("20m".to_string()),
                    qso_date: 1000,
                    ..base_qso("a", "W1AW")
                })
                .unwrap();
            inner
                .upsert_qso(&cw_store::Qso {
                    their_grid: Some("PM95".to_string()),
                    my_grid: Some("CM87".to_string()),
                    band: Some("20m".to_string()),
                    qso_date: 2000,
                    ..base_qso("b", "K2XX")
                })
                .unwrap();
        }

        let api = MapApi::new(field_store);
        let filter = FfiMapFilter {
            band: Some("20m".to_string()),
            mode: None,
            park: None,
            start_date: None,
            end_date: None,
            confirmed_only: false,
            show_individual: false,
            show_paths: true,
            max_qsos: None,
        };
        let data = api.qso_map(filter).unwrap();
        assert_eq!(data.annotations.len(), 2);
        assert_eq!(data.arcs.len(), 2);
        assert!(data.bounds.is_some());
        assert_eq!(data.available_bands, vec!["20M".to_string()]);
        assert_eq!(data.total_count, 2);
    }

    #[test]
    fn timeline_curve_exports_wrap_domain() {
        assert_eq!(timeline_spot_opacity(0.0), 1.0);
        assert_eq!(timeline_spot_opacity(600.0), 0.0);
        assert!((timeline_spot_decay(600.0) - 0.3).abs() < 1e-9);
        assert_eq!(timeline_snr_marker_size(None), 10.0);
        assert_eq!(timeline_snr_marker_size(Some(40)), 36.0);
        assert_eq!(timeline_snr_color_band(-3), 0);
        assert_eq!(timeline_snr_color_band(25), 3);
    }

    #[test]
    fn maidenhead_grid_bounds_accepts_4char() {
        let bounds = maidenhead_grid_bounds("EM12".to_string()).expect("4-char grid should resolve");
        assert!((bounds.east - bounds.west - 2.0).abs() < 1e-9);
        assert!((bounds.north - bounds.south - 1.0).abs() < 1e-9);

        // Pin the misuse this bug rode in on: tile_bounds must NOT accept a
        // 4-char grid.
        assert!(maidenhead_tile_bounds("EM12".to_string()).is_none());
    }

    fn base_qso(id: &str, callsign: &str) -> cw_store::Qso {
        cw_store::Qso {
            id: id.to_string(),
            callsign: callsign.to_string(),
            band: None,
            mode: Some("FT8".to_string()),
            freq_khz: Some(14_074.0),
            qso_date: 1_700_000_000,
            my_grid: None,
            their_grid: None,
            rst_sent: None,
            rst_rcvd: None,
            my_callsign: Some("W6JY".to_string()),
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: 1_700_000_000,
            modified_at: None,
            raw_adif: None,
            name: None,
            qth: None,
            state: None,
            country: None,
            power: None,
            my_rig: None,
            station_profile_name: None,
            sota_ref: None,
            wwff_ref: None,
            aoa_code: None,
            qrz_log_id: None,
            qrz_confirmed: false,
            lotw_confirmed_date: None,
            lotw_confirmed: false,
            dxcc: None,
            their_license_class: None,
            contest_name: None,
            contest_serial_sent: None,
            contest_serial_received: None,
            contest_exchange_sent: None,
            contest_exchange_received: None,
            is_hidden: false,
            is_activity_log_qso: false,
            station_callsign: None,
            logging_session_id: None,
            dirty: true,
            sat_name: None,
            prop_mode: None,
        }
    }
}
