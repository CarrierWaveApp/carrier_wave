//! Pure aggregation over `MapQsoRow`s: clusters/individual annotations, arcs,
//! bounds, and stats. Port of the deleted Swift `QSOMapView+Data.swift` /
//! `MapDataLoadingActor.swift` (see task-5-brief.md for the semantics this
//! must match exactly). No store access here — `MapApi::qso_map` in `mod.rs`
//! fetches rows + builds the metadata index, then calls [`build`].

use std::collections::HashMap;

use cw_domain::great_circle::great_circle_segments;
use cw_domain::map_bounds::{bounds_for, camera_spans, requires_globe_view};
use cw_domain::maidenhead::{coordinate_from_grid, distance_km};
use cw_store::{normalized_valid_state, MapFilterOptions, MapQsoRow};

use super::records::{
    FfiMapArc, FfiMapBounds, FfiMapFilter, FfiMapPolyline, FfiMapStats, FfiQsoMapAnnotation,
    FfiQsoMapData,
};
use crate::FfiCoordinate;

/// Resolved per-annotation metadata: activation weather/solar/WPM plus
/// session equipment (antenna/key/mic), keyed by `"{park}|yyyy-MM-dd"`
/// (UTC day of the QSO). Built once per `qso_map` call in `mod.rs`.
#[derive(Debug, Clone, Default)]
pub struct MetaEntry {
    pub weather: Option<String>,
    pub solar_conditions: Option<String>,
    pub average_wpm: Option<i64>,
    pub antenna: Option<String>,
    pub key: Option<String>,
    pub mic: Option<String>,
}

/// Metadata lookup index: `"{park}|yyyy-MM-dd"` -> resolved fields.
pub type MetaIndex = HashMap<String, MetaEntry>;

/// First 4 chars of a grid locator, uppercased. `None` if the grid has fewer
/// than 4 chars. Char-based (not byte-slicing) so malformed/non-ASCII input
/// can't panic on a mid-codepoint boundary.
fn grid4(grid: &str) -> Option<String> {
    if grid.chars().count() < 4 {
        return None;
    }
    Some(grid.chars().take(4).collect::<String>().to_uppercase())
}

/// Build the metadata lookup key for a row: `"{park}|yyyy-MM-dd"` (UTC day of
/// `qso_date`). Port of `MapDataLoadingActor.dateKeyFormatter` + the
/// `"\(park)|\(dateStr)"` key construction.
fn meta_key(park: &str, qso_date: i64) -> String {
    let day = chrono::DateTime::from_timestamp(qso_date, 0)
        .map(|dt| dt.format("%Y-%m-%d").to_string())
        .unwrap_or_default();
    format!("{park}|{day}")
}

/// Port of `resolveMetadata` (`QSOMapView+Data.swift:93-144`): merge
/// activation metadata + session equipment across every row in the group.
/// First non-empty value wins for weather/solar/antenna/key/mic; WPM
/// averages across matches (integer division, matching Swift's `Int` avg);
/// radio is the first non-null `my_rig` among the rows (not metadata-scoped).
fn resolve_metadata(rows: &[&MapQsoRow], meta: &MetaIndex) -> (Vec<String>, MetaEntry, Option<String>) {
    let mut park_refs: Vec<String> = Vec::new();
    let mut weather = None;
    let mut solar = None;
    let mut wpms: Vec<i64> = Vec::new();
    let mut antenna = None;
    let mut key = None;
    let mut mic = None;

    for row in rows {
        let Some(park) = &row.park else { continue };
        if !park_refs.contains(park) {
            park_refs.push(park.clone());
        }
        let Some(entry) = meta.get(&meta_key(park, row.qso_date)) else {
            continue;
        };
        if weather.is_none() {
            if let Some(w) = &entry.weather {
                if !w.is_empty() {
                    weather = Some(w.clone());
                }
            }
        }
        if solar.is_none() {
            if let Some(s) = &entry.solar_conditions {
                if !s.is_empty() {
                    solar = Some(s.clone());
                }
            }
        }
        if let Some(wpm) = entry.average_wpm {
            wpms.push(wpm);
        }
        if antenna.is_none() {
            antenna = entry.antenna.clone();
        }
        if key.is_none() {
            key = entry.key.clone();
        }
        if mic.is_none() {
            mic = entry.mic.clone();
        }
    }

    park_refs.sort();
    let avg_wpm = if wpms.is_empty() { None } else { Some(wpms.iter().sum::<i64>() / wpms.len() as i64) };
    let radio = rows.iter().find_map(|r| r.my_rig.clone());
    (park_refs, MetaEntry { weather, solar_conditions: solar, average_wpm: avg_wpm, antenna, key, mic }, radio)
}

/// Clusters (`show_individual == false`): group by `their_grid[..4]`
/// uppercased, skipping rows whose grid is shorter than 4 chars.
pub fn cluster_annotations(rows: &[&MapQsoRow], meta: &MetaIndex) -> Vec<FfiQsoMapAnnotation> {
    let mut groups: HashMap<String, Vec<&MapQsoRow>> = HashMap::new();
    let mut order: Vec<String> = Vec::new();
    for &row in rows {
        let Some(key) = grid4(&row.their_grid) else { continue };
        if !groups.contains_key(&key) {
            order.push(key.clone());
        }
        groups.entry(key).or_default().push(row);
    }

    order
        .into_iter()
        .filter_map(|grid_key| {
            let group = groups.get(&grid_key)?;
            let coord = coordinate_from_grid(&grid_key)?;
            let mut callsigns: Vec<String> = group.iter().map(|r| r.callsign.clone()).collect();
            callsigns.sort();
            let most_recent = group.iter().map(|r| r.qso_date).max().unwrap_or(0);
            let (park_refs, resolved, radio) = resolve_metadata(group, meta);
            Some(FfiQsoMapAnnotation {
                id: grid_key.clone(),
                latitude: coord.latitude,
                longitude: coord.longitude,
                grid_square: grid_key,
                qso_count: group.len() as i64,
                callsigns,
                most_recent,
                park_references: park_refs,
                weather: resolved.weather,
                solar_conditions: resolved.solar_conditions,
                average_wpm: resolved.average_wpm,
                radio,
                antenna: resolved.antenna,
                key: resolved.key,
                mic: resolved.mic,
            })
        })
        .collect()
}

/// Individual (`show_individual == true`): one annotation per row with a
/// grid of 4+ chars.
pub fn individual_annotations(rows: &[&MapQsoRow], meta: &MetaIndex) -> Vec<FfiQsoMapAnnotation> {
    rows.iter()
        .filter_map(|&row| {
            let grid_square = grid4(&row.their_grid)?;
            let coord = coordinate_from_grid(&row.their_grid)?;
            let (park_refs, resolved, radio) = resolve_metadata(std::slice::from_ref(&row), meta);
            Some(FfiQsoMapAnnotation {
                id: row.id.clone(),
                latitude: coord.latitude,
                longitude: coord.longitude,
                grid_square,
                qso_count: 1,
                callsigns: vec![row.callsign.clone()],
                most_recent: row.qso_date,
                park_references: park_refs,
                weather: resolved.weather,
                solar_conditions: resolved.solar_conditions,
                average_wpm: resolved.average_wpm,
                radio,
                antenna: resolved.antenna,
                key: resolved.key,
                mic: resolved.mic,
            })
        })
        .collect()
}

/// Arcs (`show_paths == true` only): one per displayed row having both grids
/// resolvable via `coordinate_from_grid`.
pub fn build_arcs(rows: &[&MapQsoRow]) -> Vec<FfiMapArc> {
    rows.iter()
        .filter_map(|&row| {
            let my_grid = row.my_grid.as_ref()?;
            let from = coordinate_from_grid(my_grid)?;
            let to = coordinate_from_grid(&row.their_grid)?;
            let segments = great_circle_segments((from.latitude, from.longitude), (to.latitude, to.longitude), 30);
            Some(FfiMapArc {
                id: row.id.clone(),
                callsign: row.callsign.clone(),
                segments: segments
                    .into_iter()
                    .map(|seg| FfiMapPolyline {
                        points: seg.into_iter().map(|(lat, lon)| FfiCoordinate { latitude: lat, longitude: lon }).collect(),
                    })
                    .collect(),
            })
        })
        .collect()
}

/// Stats (port of `computeStatistics`, `QSOMapView+Data.swift:266-344`) over
/// ALL filtered rows (not just displayed).
pub fn compute_stats(rows: &[&MapQsoRow]) -> FfiMapStats {
    if rows.is_empty() {
        return FfiMapStats {
            duration_seconds: None,
            qso_rate: None,
            average_distance_km: None,
            longest_distance_km: None,
            watts_per_mile: None,
            unique_states: 0,
            unique_dxcc: 0,
        };
    }

    let duration_seconds = session_duration(rows);
    let qso_rate = duration_seconds
        .filter(|&d| d > 0)
        .map(|d| rows.len() as f64 / (d as f64 / 3_600.0));

    let mut distances: Vec<f64> = Vec::new();
    let mut power_values: Vec<i64> = Vec::new();
    let mut power_dist_miles: Vec<f64> = Vec::new();
    for &row in rows {
        let Some(my_grid) = &row.my_grid else { continue };
        let Some(dist) = distance_km(my_grid, &row.their_grid) else { continue };
        distances.push(dist);
        if let Some(power) = row.power {
            power_values.push(power);
            power_dist_miles.push(dist * 0.621_371);
        }
    }

    let average_distance_km = if distances.is_empty() { None } else { Some(distances.iter().sum::<f64>() / distances.len() as f64) };
    let longest_distance_km = distances.iter().cloned().fold(None, |acc: Option<f64>, d| Some(acc.map_or(d, |m| m.max(d))));

    let watts_per_mile = if power_values.is_empty() {
        None
    } else {
        let avg_power = power_values.iter().sum::<i64>() as f64 / power_values.len() as f64;
        let avg_dist_miles = power_dist_miles.iter().sum::<f64>() / power_dist_miles.len() as f64;
        if avg_dist_miles > 0.0 { Some(avg_power / avg_dist_miles) } else { None }
    };

    let mut states: Vec<&str> = rows.iter().filter_map(|r| r.state.as_deref().and_then(normalized_valid_state)).collect();
    states.sort_unstable();
    states.dedup();

    let mut dxcc: Vec<i64> = rows.iter().filter_map(|r| r.dxcc).collect();
    dxcc.sort_unstable();
    dxcc.dedup();

    FfiMapStats {
        duration_seconds,
        qso_rate,
        average_distance_km,
        longest_distance_km,
        watts_per_mile,
        unique_states: states.len() as i64,
        unique_dxcc: dxcc.len() as i64,
    }
}

/// Sum per-logging-session-group (max - min) qso_date. `None` if there is
/// only one row total, or the summed duration is 0.
fn session_duration(rows: &[&MapQsoRow]) -> Option<i64> {
    if rows.len() <= 1 {
        return None;
    }
    let mut groups: HashMap<Option<String>, Vec<i64>> = HashMap::new();
    for &row in rows {
        groups.entry(row.logging_session_id.clone()).or_default().push(row.qso_date);
    }
    let mut total = 0i64;
    for (_, mut dates) in groups {
        dates.sort_unstable();
        if let (Some(&first), Some(&last)) = (dates.first(), dates.last()) {
            total += last - first;
        }
    }
    if total > 0 { Some(total) } else { None }
}

/// Top-level aggregation: build the full `FfiQsoMapData` view-model from
/// fetched rows + filter options + the metadata index.
///
/// `rows` are already filtered + ordered newest-first by `qso_map_rows`.
/// Cap: `displayed = rows[..max_qsos]` when `filter.max_qsos` is `Some`;
/// `is_limited = filtered_count > cap`. Annotations/arcs come from displayed
/// rows; stats/unique-counts come from ALL filtered rows.
pub fn build(rows: Vec<MapQsoRow>, opts: MapFilterOptions, meta: &MetaIndex, filter: &FfiMapFilter) -> FfiQsoMapData {
    let filtered_count = rows.len() as i64;
    let cap = filter.max_qsos.map(|m| m as usize);
    let displayed: Vec<&MapQsoRow> = match cap {
        Some(cap) => rows.iter().take(cap).collect(),
        None => rows.iter().collect(),
    };
    let is_limited = match cap {
        Some(cap) => filtered_count > cap as i64,
        None => false,
    };

    let annotations = if filter.show_individual {
        individual_annotations(&displayed, meta)
    } else {
        cluster_annotations(&displayed, meta)
    };
    let arcs = if filter.show_paths { build_arcs(&displayed) } else { Vec::new() };

    let all_refs: Vec<&MapQsoRow> = rows.iter().collect();
    let stats = compute_stats(&all_refs);

    let mut bound_coords: Vec<(f64, f64)> = annotations.iter().map(|a| (a.latitude, a.longitude)).collect();
    for arc in &arcs {
        if let Some(first_segment) = arc.segments.first() {
            if let Some(point) = first_segment.points.first() {
                bound_coords.push((point.latitude, point.longitude));
            }
        }
    }
    let bounds = bounds_for(&bound_coords).map(|b| {
        let (camera_lat_span, camera_lon_span) = camera_spans(&b);
        FfiMapBounds {
            center_lat: b.center_lat,
            center_lon: b.center_lon,
            lat_span: b.lat_span,
            lon_span: b.lon_span,
            camera_lat_span,
            camera_lon_span,
            requires_globe_view: requires_globe_view(&b),
        }
    });

    FfiQsoMapData {
        displayed_count: displayed.len() as i64,
        annotations,
        arcs,
        bounds,
        stats,
        filtered_count,
        is_limited,
        total_count: opts.total,
        available_bands: opts.bands,
        available_modes: opts.modes,
        available_parks: opts.parks,
        earliest_date: opts.earliest,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, callsign: &str, their_grid: &str, my_grid: Option<&str>, qso_date: i64) -> MapQsoRow {
        MapQsoRow {
            id: id.to_string(),
            callsign: callsign.to_string(),
            band: Some("20M".to_string()),
            mode: Some("FT8".to_string()),
            qso_date,
            my_grid: my_grid.map(|g| g.to_string()),
            their_grid: their_grid.to_string(),
            park: None,
            state: None,
            dxcc: None,
            qrz_confirmed: false,
            lotw_confirmed: false,
            power: None,
            logging_session_id: None,
            my_rig: None,
        }
    }

    #[test]
    fn clusters_group_by_4char_grid_and_sort_callsigns() {
        let rows = [
            row("a", "W2AA", "EM12aa", None, 1000),
            row("b", "K1AA", "EM12bb", None, 2000),
            row("c", "W3ZZ", "FN31", None, 3000),
        ];
        let refs: Vec<&MapQsoRow> = rows.iter().collect();
        let meta = MetaIndex::new();
        let mut annotations = cluster_annotations(&refs, &meta);
        annotations.sort_by(|a, b| a.id.cmp(&b.id));
        assert_eq!(annotations.len(), 2);
        let em12 = annotations.iter().find(|a| a.id == "EM12").unwrap();
        assert_eq!(em12.qso_count, 2);
        assert_eq!(em12.callsigns, vec!["K1AA".to_string(), "W2AA".to_string()]);
        assert_eq!(em12.most_recent, 2000);
        let fn31 = annotations.iter().find(|a| a.id == "FN31").unwrap();
        assert_eq!(fn31.qso_count, 1);
    }

    #[test]
    fn individual_skips_short_grids() {
        let rows = [row("a", "W2AA", "EM", None, 1000)];
        let refs: Vec<&MapQsoRow> = rows.iter().collect();
        let meta = MetaIndex::new();
        let annotations = individual_annotations(&refs, &meta);
        assert!(annotations.is_empty());
    }

    #[test]
    fn stats_duration_groups_by_session() {
        // Session "s1": QSOs at t=0 and t=3600 (1h). Session "s2": QSOs at
        // t=10000 and t=13600 (1h). Total duration = 3600 + 3600 = 7200,
        // regardless of the 6400s gap between the sessions.
        let mut r1 = row("a", "W1AW", "EM12", None, 0);
        r1.logging_session_id = Some("s1".to_string());
        let mut r2 = row("b", "K2XX", "EM12", None, 3600);
        r2.logging_session_id = Some("s1".to_string());
        let mut r3 = row("c", "W3ZZ", "EM12", None, 10_000);
        r3.logging_session_id = Some("s2".to_string());
        let mut r4 = row("d", "W4YY", "EM12", None, 13_600);
        r4.logging_session_id = Some("s2".to_string());
        let rows = [r1, r2, r3, r4];
        let refs: Vec<&MapQsoRow> = rows.iter().collect();
        let stats = compute_stats(&refs);
        assert_eq!(stats.duration_seconds, Some(7200));
    }

    #[test]
    fn stats_watts_per_mile() {
        // FN31 -> EM12 grid-center distance is ~2344.005 km (hand-computed via
        // haversine on grid centers: FN31=(41.5,-73.0), EM12=(32.5,-97.0)),
        // i.e. ~1456.497 statute miles (km * 0.621371). Two rows with the same
        // grid pair, power 100 and 50 -> avg power 75, avg dist ~1456.497mi ->
        // watts_per_mile ~= 75 / 1456.497 ~= 0.051493.
        let mut r1 = row("a", "W1AW", "EM12", Some("FN31"), 0);
        r1.power = Some(100);
        let mut r2 = row("b", "K2XX", "EM12", Some("FN31"), 1000);
        r2.power = Some(50);
        let rows = [r1, r2];
        let refs: Vec<&MapQsoRow> = rows.iter().collect();
        let stats = compute_stats(&refs);
        let wpm = stats.watts_per_mile.unwrap();
        assert!((wpm - 0.051_493).abs() < 1e-5, "got {wpm}");
    }

    #[test]
    fn arcs_only_with_both_grids() {
        let mut with_both = row("a", "W1AW", "EM12", Some("FN31"), 1000);
        with_both.id = "with-both".to_string();
        let mut missing_my_grid = row("b", "K2XX", "EM12", None, 2000);
        missing_my_grid.id = "missing-my-grid".to_string();
        let rows = [with_both, missing_my_grid];
        let refs: Vec<&MapQsoRow> = rows.iter().collect();
        let arcs = build_arcs(&refs);
        assert_eq!(arcs.len(), 1);
        assert_eq!(arcs[0].id, "with-both");
    }

    #[test]
    fn cap_limits_display_not_stats() {
        let rows = vec![
            row("a", "W1AW", "EM12", None, 3000),
            row("b", "K2XX", "FN31", None, 2000),
            row("c", "W3ZZ", "DM79", None, 1000),
        ];
        let opts = MapFilterOptions { bands: vec![], modes: vec![], parks: vec![], earliest: None, total: 3 };
        let filter = FfiMapFilter {
            band: None,
            mode: None,
            park: None,
            start_date: None,
            end_date: None,
            confirmed_only: false,
            show_individual: false,
            show_paths: false,
            max_qsos: Some(1),
        };
        let meta = MetaIndex::new();
        let data = build(rows, opts, &meta, &filter);
        assert_eq!(data.annotations.len(), 1);
        assert_eq!(data.filtered_count, 3);
        assert_eq!(data.displayed_count, 1);
        assert!(data.is_limited);
    }
}
