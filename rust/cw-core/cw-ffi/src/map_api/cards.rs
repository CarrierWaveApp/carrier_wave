//! Store-pure card view-models for the three per-session/per-QSO map surfaces:
//! `session_map`, `session_timeline`, and `qso_detail_map`. No network — every
//! coordinate resolves from the store (grids, the `callbook_location` cache, or
//! `pota_park` rows). Faithful ports of the deleted Swift `SessionQSOMap`,
//! `TimelineMapDataActor`, and `QSODetailView+Map`. See task-5-brief.md for the
//! binding semantics.

use std::collections::BTreeSet;

use cw_domain::great_circle::great_circle_segments;
use cw_domain::maidenhead::{bearing_between, coordinate_from_grid, distance_km_between, Coordinate};
use cw_domain::map_bounds::{bounds_for, camera_spans, requires_globe_view};
use cw_domain::timeline::strip_skimmer_suffix;
use cw_store::{SessionSpot, SessionSpotFilter, Store, TimelineQsoRow};

use super::aggregate::{individual_annotations, MetaIndex};
use super::records::{
    FfiMapArc, FfiMapBounds, FfiMapPolyline, FfiQsoDetailMap, FfiSessionMapData, FfiTimelineData,
    FfiTimelineEvent,
};
use super::MapApi;
use crate::{CwError, FfiCoordinate};

/// Location-cache TTL for spotter callbook lookups: 30 days (matches the iOS
/// cache expiry the timeline used for HamDB-resolved spotter grids).
const CALLBOOK_TTL_SECS: i64 = 2_592_000;
/// Max distinct base callsigns the timeline resolves per load (iOS
/// `lookupMissingSpotterGrids.maxLookups`); the tail is reported as unresolved.
const MAX_SPOTTER_LOOKUPS: usize = 30;
/// Cap on QSO window rows (iOS `fetchQSOEvents` `limit: 500`).
const TIMELINE_QSO_LIMIT: i64 = 500;
/// Cap on session spots (iOS `fetchSpotEvents` `fetchLimit: 2_000`), clamped to
/// the store's `MAX_FETCH_LIMIT` of 1_000.
const TIMELINE_SPOT_LIMIT: i64 = 1_000;

#[uniffi::export]
impl MapApi {
    /// Session QSO map: individual pins for the session's mappable QSOs, rove
    /// stops, home→contact arcs, and bounds. Store-pure.
    pub fn session_map(&self, session_id: String) -> Result<FfiSessionMapData, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.session_map_rows(&session_id)?;
        let session = store.fetch_logging_session(&session_id)?;
        let rove_stops = store.fetch_rove_stops(&session_id)?;
        drop(store);

        let my_grid = session.as_ref().and_then(|s| s.my_grid.clone());
        let refs: Vec<&cw_store::MapQsoRow> = rows.iter().collect();
        let meta = MetaIndex::new();
        let annotations = individual_annotations(&refs, &meta);
        let arcs = session_arcs(&refs);
        let rove_coords = rove_stop_coords(&rove_stops, my_grid.as_deref());
        let bounds = session_bounds(&annotations, my_grid.as_deref(), &rove_coords);

        Ok(FfiSessionMapData { annotations, rove_stops: rove_coords, arcs, bounds })
    }

    /// Session timeline replay: merged, time-sorted QSO + RBN-spot events plus
    /// the operator's location, session window, and any unresolved spotters.
    /// Store-pure — spotter grids resolve from the `callbook_location` cache
    /// (no HamDB network; unresolved base calls are surfaced to the caller).
    pub fn session_timeline(&self, session_id: String) -> Result<FfiTimelineData, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let session = store.fetch_logging_session(&session_id)?;
        let (my_grid, started_at, ended_at) = session_window(session.as_ref());

        let qsos = store.timeline_window_qsos(started_at, ended_at, TIMELINE_QSO_LIMIT)?;
        let filter = SessionSpotFilter { logging_session_id: Some(session_id), ..Default::default() };
        let spots = store.fetch_session_spots(&filter, TIMELINE_SPOT_LIMIT, 0)?;
        let rbn: Vec<&SessionSpot> = spots.iter().filter(|s| is_rbn(s)).collect();

        let (resolved, unresolved) = resolve_spotters(&store, &rbn, ended_at);
        drop(store);

        let mut events: Vec<FfiTimelineEvent> = Vec::with_capacity(qsos.len() + rbn.len());
        events.extend(qsos.iter().map(qso_event));
        events.extend(rbn.iter().map(|spot| spot_event(spot, &resolved)));
        events.sort_by_key(|e| e.timestamp);

        let my_coord = my_grid.as_deref().and_then(coordinate_from_grid);
        Ok(FfiTimelineData {
            events,
            my_grid,
            my_latitude: my_coord.map(|c| c.latitude),
            my_longitude: my_coord.map(|c| c.longitude),
            started_at,
            ended_at,
            unresolved_spotters: unresolved,
        })
    }

    /// QSO-detail point-to-point map: my/their coordinates (their grid, else a
    /// POTA-park fallback), the arc + distance + bearing when both resolve.
    pub fn qso_detail_map(&self, qso_id: String) -> Result<FfiQsoDetailMap, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(qso) = store.fetch_qso(&qso_id)? else {
            return Ok(empty_detail_map());
        };
        let my = resolve_my(&store, &qso)?;
        let (their, their_source) = resolve_their(&store, &qso)?;
        drop(store);

        match (my, their) {
            (Some(my_coord), Some(their_coord)) => {
                let arc = coord_arc(my_coord, their_coord);
                Ok(FfiQsoDetailMap {
                    my: Some(my_coord.into()),
                    their: Some(their_coord.into()),
                    their_source,
                    arc,
                    distance_km: Some(distance_km_between(my_coord, their_coord)),
                    bearing: Some(bearing_between(my_coord, their_coord)),
                })
            }
            (my, their) => Ok(FfiQsoDetailMap {
                my: my.map(Into::into),
                their: their.map(Into::into),
                their_source,
                arc: Vec::new(),
                distance_km: None,
                bearing: None,
            }),
        }
    }
}

/// `SessionSpot.isRBN`: `source == "rbn"` OR the POTA→RBN relay case
/// (`source == "pota"` with a `comments` string beginning `"RBN"`). Exact port
/// of `SessionSpot.isRBN`/`isRBNRelay`.
fn is_rbn(spot: &SessionSpot) -> bool {
    spot.source == "rbn"
        || (spot.source == "pota" && spot.comments.as_deref().is_some_and(|c| c.starts_with("RBN")))
}

/// Home→contact arcs for the session (30 segments), one per row whose `my_grid`
/// and `their_grid` both resolve. Mirrors `individual_annotations`' arc pairing.
fn session_arcs(rows: &[&cw_store::MapQsoRow]) -> Vec<FfiMapArc> {
    rows.iter()
        .filter_map(|&row| {
            let from = coordinate_from_grid(row.my_grid.as_deref()?)?;
            let to = coordinate_from_grid(&row.their_grid)?;
            let segments = great_circle_segments((from.latitude, from.longitude), (to.latitude, to.longitude), 30);
            Some(FfiMapArc {
                id: row.id.clone(),
                callsign: row.callsign.clone(),
                segments: segments.into_iter().map(polyline).collect(),
            })
        })
        .collect()
}

/// Rove-stop coordinates: `stop.my_grid` if present, else the session `my_grid`;
/// skip stops that resolve to neither (grid < 4 chars / invalid). Port of
/// `SessionQSOMap.roveStopCoordinates`.
fn rove_stop_coords(stops: &[cw_store::RoveStop], session_grid: Option<&str>) -> Vec<FfiCoordinate> {
    stops
        .iter()
        .filter_map(|stop| {
            let grid = stop.my_grid.as_deref().or(session_grid)?;
            if grid.chars().count() < 4 {
                return None;
            }
            coordinate_from_grid(grid).map(Into::into)
        })
        .collect()
}

/// Bounds over all pins + home + rove stops (port of the `SessionQSOMap`
/// camera fit). `None` when nothing resolves.
fn session_bounds(
    annotations: &[super::records::FfiQsoMapAnnotation],
    my_grid: Option<&str>,
    rove_coords: &[FfiCoordinate],
) -> Option<FfiMapBounds> {
    let mut coords: Vec<(f64, f64)> = annotations.iter().map(|a| (a.latitude, a.longitude)).collect();
    if let Some(coord) = my_grid.and_then(coordinate_from_grid) {
        coords.push((coord.latitude, coord.longitude));
    }
    coords.extend(rove_coords.iter().map(|c| (c.latitude, c.longitude)));
    let bounds = bounds_for(&coords)?;
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

/// The session window `(my_grid, started_at, ended_at)`. A missing session (or
/// a still-open one with `ended_at == None`) degrades to `started_at == 0` /
/// `ended_at == i64::MAX`, matching the Swift `Date()` defaults' intent of "an
/// open-ended window" — the client still gets whatever QSOs/spots exist.
fn session_window(session: Option<&cw_store::LoggingSession>) -> (Option<String>, i64, i64) {
    let Some(session) = session else { return (None, 0, i64::MAX) };
    let started = session.started_at;
    let ended = session.ended_at.unwrap_or(i64::MAX);
    (session.my_grid.clone(), started, ended)
}

/// Resolved spotter grid map + the sorted, deduped, capped list of base calls
/// that stayed unresolved. Grid comes from the spot's stored `spotter_grid`, or
/// the `callbook_location` cache keyed by the suffix-stripped base call.
fn resolve_spotters(
    store: &Store,
    rbn: &[&SessionSpot],
    now: i64,
) -> (std::collections::HashMap<String, Coordinate>, Vec<String>) {
    use std::collections::HashMap;

    // Base calls needing a lookup: spots without a usable stored grid.
    let mut needing: BTreeSet<String> = BTreeSet::new();
    for spot in rbn {
        if spot.spotter_grid.as_deref().and_then(coordinate_from_grid).is_some() {
            continue;
        }
        if let Some(spotter) = &spot.spotter {
            needing.insert(strip_skimmer_suffix(spotter).to_uppercase());
        }
    }

    let base_calls: Vec<String> = needing.iter().take(MAX_SPOTTER_LOOKUPS).cloned().collect();
    let cached = store
        .fetch_callbook_locations(&base_calls, now, CALLBOOK_TTL_SECS)
        .unwrap_or_default();
    let mut resolved: HashMap<String, Coordinate> = HashMap::new();
    for loc in cached {
        resolved.insert(loc.callsign.to_uppercase(), Coordinate::new(loc.latitude, loc.longitude));
    }

    let unresolved: Vec<String> = base_calls.into_iter().filter(|call| !resolved.contains_key(call)).collect();
    (resolved, unresolved)
}

/// Build one timeline event from a QSO window row.
fn qso_event(row: &TimelineQsoRow) -> FfiTimelineEvent {
    let coord = row.their_grid.as_deref().and_then(coordinate_from_grid);
    FfiTimelineEvent {
        id: row.id.clone(),
        timestamp: row.qso_date,
        is_qso: true,
        callsign: row.callsign.clone(),
        band: row.band.clone(),
        mode: row.mode.clone(),
        latitude: coord.map(|c| c.latitude),
        longitude: coord.map(|c| c.longitude),
        snr: None,
        spotter: None,
    }
}

/// Build one timeline event from an RBN spot: coordinate from the stored
/// `spotter_grid`, else the resolved callbook location for the base call.
fn spot_event(spot: &SessionSpot, resolved: &std::collections::HashMap<String, Coordinate>) -> FfiTimelineEvent {
    let coord = spot
        .spotter_grid
        .as_deref()
        .and_then(coordinate_from_grid)
        .or_else(|| {
            let base = spot.spotter.as_deref().map(|s| strip_skimmer_suffix(s).to_uppercase())?;
            resolved.get(&base).copied()
        });
    FfiTimelineEvent {
        id: spot.id.clone(),
        timestamp: spot.timestamp,
        is_qso: false,
        callsign: spot.callsign.clone(),
        band: cw_domain::band::BandUtilities::derive_band(Some(spot.frequency_k_hz)).map(str::to_string),
        mode: Some(spot.mode.clone()),
        latitude: coord.map(|c| c.latitude),
        longitude: coord.map(|c| c.longitude),
        snr: spot.snr,
        spotter: spot.spotter.clone(),
    }
}

/// My-location resolution: `my_grid` centroid, else the QSO's own park
/// (`park`) lat/lon. Port of `QSODetailView.resolveMyLocation`.
fn resolve_my(store: &Store, qso: &cw_store::Qso) -> Result<Option<Coordinate>, CwError> {
    if let Some(coord) = qso.my_grid.as_deref().and_then(coordinate_from_grid) {
        return Ok(Some(coord));
    }
    if let Some(park_ref) = &qso.park {
        return park_coordinate(store, park_ref);
    }
    Ok(None)
}

/// Their-location resolution + source tag: `their_grid` centroid (`"grid"`),
/// else `their_park` lat/lon (`"park"`), else `None` (`"none"`). Port of
/// `QSODetailView.resolveTheirLocation`.
fn resolve_their(store: &Store, qso: &cw_store::Qso) -> Result<(Option<Coordinate>, String), CwError> {
    if let Some(coord) = qso.their_grid.as_deref().and_then(coordinate_from_grid) {
        return Ok((Some(coord), "grid".to_string()));
    }
    if let Some(park_ref) = &qso.their_park {
        if let Some(coord) = park_coordinate(store, park_ref)? {
            return Ok((Some(coord), "park".to_string()));
        }
    }
    Ok((None, "none".to_string()))
}

/// POTA park coordinate by reference, or `None` if the park is absent / lacks
/// lat/lon. Port of `QSODetailView.parkCoordinate`.
fn park_coordinate(store: &Store, reference: &str) -> Result<Option<Coordinate>, CwError> {
    let Some(park) = store.fetch_pota_park(reference)? else { return Ok(None) };
    match (park.latitude, park.longitude) {
        (Some(lat), Some(lon)) => Ok(Some(Coordinate::new(lat, lon))),
        _ => Ok(None),
    }
}

/// Great-circle arc (30 segments) between two coordinates.
fn coord_arc(from: Coordinate, to: Coordinate) -> Vec<FfiMapPolyline> {
    great_circle_segments((from.latitude, from.longitude), (to.latitude, to.longitude), 30)
        .into_iter()
        .map(polyline)
        .collect()
}

/// Wrap a segment of `(lat, lon)` points into an `FfiMapPolyline`.
fn polyline(seg: Vec<(f64, f64)>) -> FfiMapPolyline {
    FfiMapPolyline {
        points: seg.into_iter().map(|(latitude, longitude)| FfiCoordinate { latitude, longitude }).collect(),
    }
}

fn empty_detail_map() -> FfiQsoDetailMap {
    FfiQsoDetailMap {
        my: None,
        their: None,
        their_source: "none".to_string(),
        arc: Vec::new(),
        distance_km: None,
        bearing: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::FieldStore;
    use std::sync::Arc;

    fn store() -> Arc<FieldStore> {
        Arc::new(FieldStore::open_in_memory("k".into()).unwrap())
    }

    fn base_qso(id: &str, callsign: &str) -> cw_store::Qso {
        cw_store::Qso {
            id: id.to_string(),
            callsign: callsign.to_string(),
            band: Some("20m".to_string()),
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

    fn base_session(id: &str) -> cw_store::LoggingSession {
        cw_store::LoggingSession {
            id: id.to_string(),
            my_callsign: "W6JY".to_string(),
            started_at: 1_000,
            ended_at: Some(100_000),
            frequency: None,
            mode: "CW".to_string(),
            activation_type_raw_value: "pota".to_string(),
            programs_raw_value: "[]".to_string(),
            status_raw_value: "active".to_string(),
            park_reference: None,
            sota_reference: None,
            mission_reference: None,
            wwff_reference: None,
            my_grid: Some("CM87".to_string()),
            power: None,
            my_rig: None,
            notes: None,
            qso_comment: None,
            custom_title: None,
            qso_count: 0,
            spot_comments_data: None,
            is_rove: false,
            rove_stops_data: None,
            my_antenna: None,
            my_key: None,
            my_mic: None,
            extra_equipment: None,
            attendees: None,
            photo_filenames: "[]".to_string(),
            radio_item_id: None,
            station_callsign: None,
            operator_callsigns_raw_value: "[]".to_string(),
            solar_k_index: None,
            solar_flux: None,
            solar_sunspots: None,
            solar_propagation_rating: None,
            solar_a_index: None,
            solar_band_conditions: None,
            solar_timestamp: None,
            solar_conditions: None,
            weather_temperature_f: None,
            weather_temperature_c: None,
            weather_humidity: None,
            weather_wind_speed: None,
            weather_wind_direction: None,
            weather_description: None,
            weather_timestamp: None,
            weather: None,
            cloud_dirty_flag: false,
            contest_id: None,
            contest_category: None,
            contest_overlay_category: None,
            contest_power: None,
            contest_bands: None,
            contest_operator: None,
            activation_latitude: None,
            activation_longitude: None,
            activation_distance_miles: None,
            activation_elevation_gain_feet: None,
            ruck_weight_pounds: None,
            qrp_activation: false,
            with_pets: false,
            with_kids: false,
            winlink_sent: false,
            aprs_sent: false,
            varac_sent: false,
            adaptive_sport: false,
            track_points_data: None,
            tota_category_raw_value: None,
            personal_effort_factor: None,
            first_activation_of_tile_ever: false,
            winter_activation_override: None,
            tiles_activated_data: None,
            tota_t3_candidates_data: None,
            tota_t3_snapshot_at: None,
            tota_official_points: None,
        }
    }

    fn base_spot(id: &str, session_id: &str, callsign: &str, when: i64) -> SessionSpot {
        SessionSpot {
            id: id.to_string(),
            logging_session_id: session_id.to_string(),
            callsign: callsign.to_string(),
            frequency_k_hz: 14_074.0,
            mode: "FT8".to_string(),
            timestamp: when,
            source: "rbn".to_string(),
            snr: Some(10),
            wpm: None,
            spotter: Some("KM3T-#".to_string()),
            spotter_grid: None,
            park_ref: None,
            park_name: None,
            comments: None,
            region: "North America".to_string(),
            distance_meters: None,
            bearing_degrees: None,
            cloud_dirty_flag: false,
        }
    }

    #[test]
    fn session_map_pins_arcs_rove_stops() {
        let field_store = store();
        {
            let inner = field_store.inner.lock().unwrap();
            inner.upsert_logging_session(&base_session("sess")).unwrap();
            inner
                .upsert_qso(&cw_store::Qso {
                    their_grid: Some("EM12".to_string()),
                    my_grid: Some("CM87".to_string()),
                    qso_date: 2_000,
                    logging_session_id: Some("sess".to_string()),
                    ..base_qso("q1", "W1AW")
                })
                .unwrap();
            inner
                .upsert_qso(&cw_store::Qso {
                    their_grid: Some("PM95".to_string()),
                    my_grid: Some("CM87".to_string()),
                    qso_date: 3_000,
                    logging_session_id: Some("sess".to_string()),
                    ..base_qso("q2", "K2XX")
                })
                .unwrap();
            inner
                .upsert_rove_stop(&cw_store::RoveStop {
                    id: "r1".to_string(),
                    logging_session_id: "sess".to_string(),
                    park_reference: "K-1".to_string(),
                    started_at: 1_500,
                    ended_at: None,
                    my_grid: Some("DM79".to_string()),
                    qso_count: 1,
                    notes: None,
                    cloud_dirty_flag: false,
                })
                .unwrap();
        }

        let api = MapApi::new(field_store);
        let data = api.session_map("sess".to_string()).unwrap();
        assert_eq!(data.annotations.len(), 2);
        assert_eq!(data.arcs.len(), 2);
        assert_eq!(data.rove_stops.len(), 1);
        assert!(data.bounds.is_some());
    }

    #[test]
    fn session_timeline_merges_and_sorts() {
        let field_store = store();
        {
            let inner = field_store.inner.lock().unwrap();
            inner.upsert_logging_session(&base_session("sess")).unwrap();
            inner
                .upsert_qso(&cw_store::Qso {
                    their_grid: Some("EM12".to_string()),
                    qso_date: 2_000,
                    logging_session_id: Some("sess".to_string()),
                    ..base_qso("q1", "W1AW")
                })
                .unwrap();
            let mut s1 = base_spot("sp1", "sess", "K2XX", 1_000);
            s1.spotter_grid = Some("FN31".to_string());
            inner.upsert_session_spot(&s1).unwrap();
            let mut s2 = base_spot("sp2", "sess", "W3ZZ", 3_000);
            s2.spotter_grid = Some("DM79".to_string());
            inner.upsert_session_spot(&s2).unwrap();
        }

        let api = MapApi::new(field_store);
        let data = api.session_timeline("sess".to_string()).unwrap();
        assert_eq!(data.events.len(), 3);
        // Ascending by timestamp.
        assert_eq!(data.events.iter().map(|e| e.timestamp).collect::<Vec<_>>(), vec![1_000, 2_000, 3_000]);
        assert!(!data.events[0].is_qso);
        assert!(data.events[1].is_qso);
        assert!(!data.events[2].is_qso);
        // The QSO event resolved a coordinate from its grid.
        assert!(data.events[1].latitude.is_some());
    }

    #[test]
    fn session_timeline_window_not_session_scoped() {
        let field_store = store();
        {
            let inner = field_store.inner.lock().unwrap();
            inner.upsert_logging_session(&base_session("sess")).unwrap();
            // QSO in the session's time window but with NO logging_session_id.
            inner
                .upsert_qso(&cw_store::Qso {
                    their_grid: Some("EM12".to_string()),
                    qso_date: 5_000,
                    logging_session_id: None,
                    ..base_qso("q-orphan", "W1AW")
                })
                .unwrap();
        }

        let api = MapApi::new(field_store);
        let data = api.session_timeline("sess".to_string()).unwrap();
        assert_eq!(data.events.len(), 1);
        assert_eq!(data.events[0].id, "q-orphan");
        assert!(data.events[0].is_qso);
    }

    #[test]
    fn session_timeline_unresolved_spotters_stripped_deduped() {
        let field_store = store();
        {
            let inner = field_store.inner.lock().unwrap();
            inner.upsert_logging_session(&base_session("sess")).unwrap();
            // Two skimmer variants of the same base call, neither with a grid
            // nor a cache row.
            let mut a = base_spot("sp1", "sess", "K2XX", 1_000);
            a.spotter = Some("KM3T-#".to_string());
            inner.upsert_session_spot(&a).unwrap();
            let mut b = base_spot("sp2", "sess", "W3ZZ", 2_000);
            b.spotter = Some("KM3T-1".to_string());
            inner.upsert_session_spot(&b).unwrap();
        }

        let api = MapApi::new(field_store);
        let data = api.session_timeline("sess".to_string()).unwrap();
        assert_eq!(data.unresolved_spotters, vec!["KM3T".to_string()]);
        // Both events present, both off-map.
        assert_eq!(data.events.len(), 2);
        assert!(data.events.iter().all(|e| e.latitude.is_none()));
    }

    #[test]
    fn session_timeline_uses_callbook_cache() {
        let field_store = store();
        {
            let inner = field_store.inner.lock().unwrap();
            inner.upsert_logging_session(&base_session("sess")).unwrap();
            inner
                .upsert_callbook_location(&cw_store::CallbookLocation {
                    callsign: "KM3T".to_string(),
                    latitude: 42.0,
                    longitude: -71.0,
                    grid: None,
                    source: "qrz".to_string(),
                    fetched_at: 99_000,
                })
                .unwrap();
            let spot = base_spot("sp1", "sess", "K2XX", 1_000); // spotter KM3T-#, no grid
            inner.upsert_session_spot(&spot).unwrap();
        }

        let api = MapApi::new(field_store);
        let data = api.session_timeline("sess".to_string()).unwrap();
        assert!(data.unresolved_spotters.is_empty());
        assert_eq!(data.events.len(), 1);
        assert!(data.events[0].latitude.is_some());
        assert_eq!(data.events[0].latitude.unwrap(), 42.0);
    }

    #[test]
    fn qso_detail_park_fallback() {
        let field_store = store();
        {
            let inner = field_store.inner.lock().unwrap();
            inner
                .upsert_pota_parks(&[cw_store::PotaPark {
                    reference: "US-1234".to_string(),
                    name: "Test Park".to_string(),
                    location_desc: "US-CA".to_string(),
                    latitude: Some(37.0),
                    longitude: Some(-122.0),
                    grid: None,
                    entity_id: 291,
                    is_active: true,
                }])
                .unwrap();
            inner
                .upsert_qso(&cw_store::Qso {
                    my_grid: Some("CM87".to_string()),
                    their_grid: None,
                    their_park: Some("US-1234".to_string()),
                    ..base_qso("q1", "W1AW")
                })
                .unwrap();
        }

        let api = MapApi::new(field_store);
        let data = api.qso_detail_map("q1".to_string()).unwrap();
        assert_eq!(data.their_source, "park");
        let their = data.their.unwrap();
        assert_eq!(their.latitude, 37.0);
        assert_eq!(their.longitude, -122.0);
        assert!(data.my.is_some());
        assert!(!data.arc.is_empty());
        assert!(data.distance_km.is_some());
        assert!(data.bearing.is_some());
    }
}
