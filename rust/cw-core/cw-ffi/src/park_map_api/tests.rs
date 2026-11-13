//! Tests for [`super`]. Store-backed for the synchronous read paths
//! (pins/search/zones); the cache-through hit/miss/evict/error logic is tested
//! as the pure [`super::resolve_cache_through`] over canned fetch outcomes (no
//! network); the rosette scan is tested end-to-end from cached geometry,
//! including the same-list contract and the merge/sort.

use super::*;
use crate::FieldStore;
use cw_domain::multiplier::MultiplierCandidate as DomainCandidate;
use cw_domain::reference_csv::{SotaSummitRow, WwffReferenceRow};
use cw_store::PotaPark;

fn store() -> Arc<FieldStore> {
    Arc::new(FieldStore::open_in_memory("k".into()).unwrap())
}

fn api(store: Arc<FieldStore>) -> ParkMapApi {
    ParkMapApi::new(store, "https://example.invalid".into()).unwrap()
}

fn park(reference: &str, name: &str, lat: f64, lon: f64) -> PotaPark {
    PotaPark {
        reference: reference.to_string(),
        name: name.to_string(),
        location_desc: "US-WY".to_string(),
        latitude: Some(lat),
        longitude: Some(lon),
        grid: None,
        entity_id: 291,
        is_active: true,
    }
}

fn summit(code: &str, name: &str, lat: f64, lon: f64) -> SotaSummitRow {
    SotaSummitRow {
        code: code.to_string(),
        name: name.to_string(),
        association_name: "USA".to_string(),
        region_name: "Region".to_string(),
        altitude_m: 2_037,
        altitude_ft: 6_684,
        latitude: Some(lat),
        longitude: Some(lon),
        points: 10,
        bonus_points: 3,
        activation_count: 42,
        last_activation_date: None,
        last_activation_call: None,
        grid: None,
    }
}

fn wwff(reference: &str, name: &str, lat: f64, lon: f64) -> WwffReferenceRow {
    WwffReferenceRow {
        reference: reference.to_string(),
        name: name.to_string(),
        program: "KFF".to_string(),
        status: "active".to_string(),
        continent: Some("NA".to_string()),
        iota: None,
        grid: None,
        latitude: Some(lat),
        longitude: Some(lon),
        iucn_category: None,
        country: Some("United States".to_string()),
        region: None,
        dxcc_entity: Some(291),
    }
}

fn full_box() -> FfiBoundingBox {
    FfiBoundingBox { west: -180.0, south: -90.0, east: 180.0, north: 90.0 }
}

/// A GeoJSON Polygon for the unit square [0,1]×[0,1] in `[lon,lat]` order.
fn unit_square_geojson() -> String {
    r#"{"type":"Polygon","coordinates":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,1.0],[0.0,0.0]]]}"#
        .to_string()
}

// -- pins_in_box passthrough ------------------------------------------------

#[test]
fn pins_in_box_returns_requested_kinds_only() {
    let s = store();
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_pota_parks(&[park("US-0001", "Yellowstone", 44.5, -110.5)]).unwrap();
        inner.replace_sota_summits(&[summit("W7/SU-001", "Some Peak", 45.0, -111.0)]).unwrap();
        inner.replace_wwff_references(&[wwff("KFF-0001", "Some Refuge", 44.0, -110.0)]).unwrap();
    }
    let map = api(s);

    let parks_only = map.pins_in_box(full_box(), vec!["park".into()], 100).unwrap();
    assert_eq!(parks_only.len(), 1);
    assert_eq!(parks_only[0].kind, "park");
    assert!(parks_only[0].activation_count.is_none());

    let summits_only = map.pins_in_box(full_box(), vec!["summit".into()], 100).unwrap();
    assert_eq!(summits_only.len(), 1);
    assert_eq!(summits_only[0].kind, "summit");
    assert_eq!(summits_only[0].activation_count, Some(42));
    assert_eq!(summits_only[0].altitude_m, Some(2_037));

    let all = map
        .pins_in_box(full_box(), vec!["park".into(), "summit".into(), "wwff".into()], 100)
        .unwrap();
    assert_eq!(all.len(), 3);

    // Unknown kind is silently ignored, not an error.
    let unknown = map.pins_in_box(full_box(), vec!["bogus".into()], 100).unwrap();
    assert!(unknown.is_empty());
}

#[test]
fn pins_in_box_respects_the_bounding_box() {
    let s = store();
    {
        let inner = s.inner.lock().unwrap();
        inner
            .upsert_pota_parks(&[
                park("US-0001", "Inside", 10.0, 10.0),
                park("US-0002", "Outside", 80.0, 80.0),
            ])
            .unwrap();
    }
    let map = api(s);
    let bbox = FfiBoundingBox { west: 0.0, south: 0.0, east: 20.0, north: 20.0 };
    let pins = map.pins_in_box(bbox, vec!["park".into()], 100).unwrap();
    assert_eq!(pins.len(), 1);
    assert_eq!(pins[0].reference, "US-0001");
}

// -- search passthrough -----------------------------------------------------

#[test]
fn search_passthrough_maps_kinds_and_hits() {
    let s = store();
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_pota_parks(&[park("US-0001", "Grand Teton NP", 43.7, -110.8)]).unwrap();
        inner.replace_sota_summits(&[summit("W7/GR-001", "Grand Peak", 43.8, -110.9)]).unwrap();
    }
    let map = api(s);

    let both = map
        .search("grand".into(), vec!["park".into(), "summit".into()], 10)
        .unwrap();
    assert_eq!(both.len(), 2);

    // Empty kinds fails closed → empty.
    let none = map.search("grand".into(), vec![], 10).unwrap();
    assert!(none.is_empty());
}

// -- sota_zones_for (pure cached read) --------------------------------------

#[test]
fn sota_zones_for_reads_cached_zone_rows() {
    let s = store();
    {
        let inner = s.inner.lock().unwrap();
        inner
            .upsert_sota_zones(&[cw_store::SotaZoneRow {
                code: "W7/GR-001".to_string(),
                altitude_m: 3_000,
                geometry_geojson: r#"{"type":"Polygon"}"#.to_string(),
            }])
            .unwrap();
    }
    let map = api(s);
    let zones = map.sota_zones_for(vec!["W7/GR-001".into(), "W7/GR-999".into()]).unwrap();
    assert_eq!(zones.len(), 1);
    assert_eq!(zones[0].reference, "W7/GR-001");
    assert!(zones[0].geojson.contains("Polygon"));
}

// -- resolve_cache_through (pure: hit / miss / evict / error) ---------------

fn boundary(reference: &str) -> FfiGeoBoundary {
    FfiGeoBoundary {
        reference: reference.into(),
        name: Some("N".into()),
        geojson: "{}".into(),
        properties_json: None,
        kind: None,
    }
}

#[test]
fn cache_through_miss_returns_and_caches_fetched() {
    // Cache miss: nothing cached, one row fetched → returned + queued to cache.
    let outcome =
        resolve_cache_through(vec![], vec![boundary("US-0001")], None).unwrap();
    assert_eq!(outcome.result.len(), 1);
    assert_eq!(outcome.to_cache.len(), 1, "fetched row must be written to the cache");
}

#[test]
fn cache_through_hit_and_miss_merges_fetched_over_cached() {
    // One cached hit + one fetched miss → both returned; only the fetched one
    // is (re)written to the cache.
    let outcome = resolve_cache_through(
        vec![boundary("US-0001")],
        vec![boundary("US-0002")],
        None,
    )
    .unwrap();
    let mut refs: Vec<&str> = outcome.result.iter().map(|b| b.reference.as_str()).collect();
    refs.sort();
    assert_eq!(refs, vec!["US-0001", "US-0002"]);
    assert_eq!(outcome.to_cache.len(), 1);
    assert_eq!(outcome.to_cache[0].reference, "US-0002");
}

#[test]
fn cache_through_fetched_wins_key_collision() {
    let mut fresh = boundary("US-0001");
    fresh.geojson = "{\"v\":2}".into();
    let outcome = resolve_cache_through(vec![boundary("US-0001")], vec![fresh], None).unwrap();
    assert_eq!(outcome.result.len(), 1, "no duplicate row on key collision");
    assert_eq!(outcome.result[0].geojson, "{\"v\":2}", "fetched copy wins");
}

#[test]
fn cache_through_warm_cache_swallows_network_error() {
    // Warm cache (a hit) + fetch failure → cached subset returned, no error.
    let err = CwError::Network { reason: "boom".into() };
    let outcome = resolve_cache_through(vec![boundary("US-0001")], vec![], Some(err)).unwrap();
    assert_eq!(outcome.result.len(), 1);
    assert!(outcome.to_cache.is_empty());
}

#[test]
fn cache_through_cold_cache_propagates_network_error() {
    // Cold cache (no hits) + fetch failure + nothing fetched → error.
    let err = CwError::Network { reason: "boom".into() };
    let result = resolve_cache_through(vec![], vec![], Some(err));
    assert!(matches!(result, Err(CwError::Network { .. })));
}

#[test]
fn cache_through_partial_success_swallows_later_error() {
    // First chunk succeeded (fetched non-empty), later chunk failed → return
    // the partial success, no error, even with a cold starting cache.
    let err = CwError::Network { reason: "boom".into() };
    let outcome =
        resolve_cache_through(vec![], vec![boundary("US-0001")], Some(err)).unwrap();
    assert_eq!(outcome.result.len(), 1);
    assert_eq!(outcome.to_cache.len(), 1);
}

// -- upsert_and_evict side effect on the real store -------------------------

#[test]
fn upsert_and_evict_writes_then_trims_to_cap() {
    let s = store();
    let map = api(s.clone());
    let now = 1_000;
    let rows: Vec<FfiGeoBoundary> =
        (0..5).map(|i| FfiGeoBoundary {
            reference: format!("US-{i:04}"),
            name: None,
            geojson: "{}".into(),
            properties_json: None,
            kind: None,
        }).collect();
    // Insert with strictly increasing fetched_at so eviction order is defined.
    for (i, row) in rows.iter().enumerate() {
        map.upsert_and_evict(KIND_PARK, std::slice::from_ref(row), 3, now + i as i64).unwrap();
    }
    let inner = s.inner.lock().unwrap();
    let all: Vec<String> = (0..5).map(|i| format!("US-{i:04}")).collect();
    let remaining = inner.fetch_gis(KIND_PARK, &all, now + 100, GIS_CACHE_TTL_SECS).unwrap();
    assert_eq!(remaining.len(), 3, "cap enforced");
}

// -- GeoJSON decode ---------------------------------------------------------

#[test]
fn geojson_polygon_decodes_to_lat_lon_rings() {
    let polygons = geojson_to_polygons(&unit_square_geojson());
    assert_eq!(polygons.len(), 1);
    let (exterior, holes) = &polygons[0];
    assert!(holes.is_empty());
    // First coord [0,0] → (lat=0, lon=0); the [1,0] coord → (lat=0, lon=1).
    assert_eq!(exterior[0], (0.0, 0.0));
    assert_eq!(exterior[1], (0.0, 1.0));
}

#[test]
fn geojson_multipolygon_and_collection_flatten() {
    let multi = r#"{"type":"MultiPolygon","coordinates":[[[[0,0],[1,0],[1,1],[0,0]]],[[[2,2],[3,2],[3,3],[2,2]]]]}"#;
    assert_eq!(geojson_to_polygons(multi).len(), 2);

    let collection = format!(
        r#"{{"type":"GeometryCollection","geometries":[{},{}]}}"#,
        unit_square_geojson(),
        unit_square_geojson()
    );
    assert_eq!(geojson_to_polygons(&collection).len(), 2);

    // Non-polygon geometry → no polygons, no panic.
    assert!(geojson_to_polygons(r#"{"type":"Point","coordinates":[0,0]}"#).is_empty());
    assert!(geojson_to_polygons("not json").is_empty());
}

// -- rosette end-to-end from cached geometry --------------------------------

#[test]
fn find_multipliers_pota_sota_from_cached_park_polygon() {
    let s = store();
    let now = now_secs();
    {
        let inner = s.inner.lock().unwrap();
        // A park covering the unit square, and a summit inside it.
        inner.upsert_pota_parks(&[park("US-0001", "Square Park", 0.5, 0.5)]).unwrap();
        inner.replace_sota_summits(&[summit("W7/SQ-001", "Inside Summit", 0.5, 0.5)]).unwrap();
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
    }
    let map = api(s);
    let candidates = map
        .find_multipliers(vec!["W7/SQ-001".into()], vec!["US-0001".into()], vec![], vec![])
        .unwrap();
    assert_eq!(candidates.len(), 1);
    let c = &candidates[0];
    assert_eq!(c.id, "summit:W7/SQ-001");
    assert_eq!(c.title, "Inside Summit");
    assert_eq!(c.kinds, vec!["POTA + SOTA".to_string()]);
    assert_eq!(c.score, 1);
    assert_eq!(c.detail, "W7/SQ-001 · US-0001");
}

#[test]
fn find_multipliers_summit_in_park_and_near_county_merges_to_one_record() {
    let s = store();
    let now = now_secs();
    // County boundary: a segment right next to the summit so it's within 1.5km.
    let offset_deg = 500.0 / 111_320.0;
    let county_geojson = format!(
        r#"{{"type":"Polygon","coordinates":[[[{lon},0.0],[{lon},1.0],[{lon2},1.0],[{lon},0.0]]]}}"#,
        lon = 0.5 + offset_deg,
        lon2 = 0.5 + offset_deg + 0.001,
    );
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_pota_parks(&[park("US-0001", "Square Park", 0.5, 0.5)]).unwrap();
        inner.replace_sota_summits(&[summit("W7/SQ-001", "Both Summit", 0.5, 0.5)]).unwrap();
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
        inner.upsert_gis(KIND_ADMIN, "county-1", &county_geojson, now).unwrap();
    }
    let map = api(s);
    let candidates = map
        .find_multipliers(
            vec!["W7/SQ-001".into()],
            vec!["US-0001".into()],
            vec![],
            vec!["county-1".into()],
        )
        .unwrap();
    // One record for the summit, both kinds folded in (score 2), plus a
    // park-county record for the park center near the same county line.
    let summit_rec = candidates.iter().find(|c| c.id == "summit:W7/SQ-001").unwrap();
    assert_eq!(summit_rec.kinds, vec!["POTA + SOTA".to_string(), "County line".to_string()]);
    assert_eq!(summit_rec.score, 2);
    // Highest score sorts first.
    assert_eq!(candidates[0].id, "summit:W7/SQ-001");
}

#[test]
fn find_multipliers_sorts_score_desc_then_title_asc() {
    // Feed the merge helper directly to pin the sort without geometry setup.
    let summit_set: std::collections::HashSet<&String> = std::collections::HashSet::new();
    let summit_names = HashMap::new();
    let park_names = HashMap::new();
    let wwff_names = HashMap::new();
    let flat = vec![
        DomainCandidate {
            kind: MultiplierKind::PotaWwff,
            latitude: 0.0,
            longitude: 0.0,
            refs: vec!["ZEBRA".to_string()],
            distance_m: None,
        },
        DomainCandidate {
            kind: MultiplierKind::PotaWwff,
            latitude: 0.0,
            longitude: 0.0,
            refs: vec!["ALPHA".to_string()],
            distance_m: None,
        },
    ];
    let merged = merge_candidates(flat, &summit_set, &summit_names, &park_names, &wwff_names);
    // Both score 1 → title ascending: ALPHA before ZEBRA.
    assert_eq!(merged[0].title, "ALPHA");
    assert_eq!(merged[1].title, "ZEBRA");
}

#[test]
fn find_multipliers_park_polygons_and_centers_stay_same_length() {
    // The same-list contract: for N cached park polygons, exactly N centers are
    // built in the same pass. Exercise it through a park-county scan and assert
    // the park-county candidate carries the park's own center-derived record.
    let s = store();
    let now = now_secs();
    let offset_deg = 400.0 / 111_320.0;
    // County line hugging the unit-square park's east edge (center lon ~0.5).
    let county_geojson = format!(
        r#"{{"type":"Polygon","coordinates":[[[{lon},0.0],[{lon},1.0],[{lon2},1.0],[{lon},0.0]]]}}"#,
        lon = 0.5 + offset_deg,
        lon2 = 0.5 + offset_deg + 0.001,
    );
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_pota_parks(&[park("US-0001", "Square Park", 0.5, 0.5)]).unwrap();
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
        inner.upsert_gis(KIND_ADMIN, "county-1", &county_geojson, now).unwrap();
    }
    let map = api(s);
    let candidates = map
        .find_multipliers(vec![], vec!["US-0001".into()], vec![], vec!["county-1".into()])
        .unwrap();
    let park_rec = candidates.iter().find(|c| c.id == "park:US-0001").unwrap();
    assert_eq!(park_rec.kinds, vec!["County line".to_string()]);
    assert_eq!(park_rec.detail, "US-0001 · near county line");
    // Center is the unit-square centroid (0.5, 0.5).
    assert!((park_rec.latitude - 0.5).abs() < 1e-9);
    assert!((park_rec.longitude - 0.5).abs() < 1e-9);
}

#[test]
fn find_multipliers_wwff_borrowed_passthrough() {
    let s = store();
    let now = now_secs();
    {
        let inner = s.inner.lock().unwrap();
        // The borrowed POTA polygon (US-0001) must be cached so the WWFF pin
        // gets a center.
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
    }
    let map = api(s);
    let candidates = map
        .find_multipliers(vec![], vec!["US-0001".into()], vec!["KFF-0001".into()], vec![])
        .unwrap();
    let wwff_rec = candidates.iter().find(|c| c.id == "wwff:KFF-0001").unwrap();
    assert_eq!(wwff_rec.kinds, vec!["POTA + WWFF".to_string()]);
}

#[test]
fn find_multipliers_wwff_candidate_uses_own_name_and_coordinate_not_polygon_centroid() {
    // Swift parity: MultiplierFinder.wwffCandidates titles off item.name (code
    // fallback only when empty) and centers on the WWFF ref's own lat/lon
    // (WWFFRenderItem.center), never the borrowed POTA polygon centroid. Pick
    // a WWFF coordinate well outside the unit-square park's [0,1]x[0,1]
    // centroid (0.5, 0.5) so the two are distinguishable.
    let s = store();
    let now = now_secs();
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
        inner
            .replace_wwff_references(&[wwff("KFF-0001", "Some Refuge", 44.0, -110.0)])
            .unwrap();
    }
    let map = api(s);
    let candidates = map
        .find_multipliers(vec![], vec!["US-0001".into()], vec!["KFF-0001".into()], vec![])
        .unwrap();
    let wwff_rec = candidates.iter().find(|c| c.id == "wwff:KFF-0001").unwrap();
    assert_eq!(wwff_rec.title, "Some Refuge");
    assert!((wwff_rec.latitude - 44.0).abs() < 1e-9);
    assert!((wwff_rec.longitude - (-110.0)).abs() < 1e-9);
}

#[test]
fn find_multipliers_wwff_candidate_falls_back_to_code_when_name_is_empty() {
    let s = store();
    let now = now_secs();
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
        inner.replace_wwff_references(&[wwff("KFF-0001", "", 44.0, -110.0)]).unwrap();
    }
    let map = api(s);
    let candidates = map
        .find_multipliers(vec![], vec!["US-0001".into()], vec!["KFF-0001".into()], vec![])
        .unwrap();
    let wwff_rec = candidates.iter().find(|c| c.id == "wwff:KFF-0001").unwrap();
    assert_eq!(wwff_rec.title, "KFF-0001");
}

#[test]
fn find_multipliers_wwff_candidate_falls_back_to_polygon_centroid_when_ref_uncached() {
    // No WWFF reference row cached at all (the current
    // `find_multipliers_wwff_borrowed_passthrough` scenario) — degrade to the
    // borrowed park polygon centroid rather than dropping the candidate.
    let s = store();
    let now = now_secs();
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
    }
    let map = api(s);
    let candidates = map
        .find_multipliers(vec![], vec!["US-0001".into()], vec!["KFF-0001".into()], vec![])
        .unwrap();
    let wwff_rec = candidates.iter().find(|c| c.id == "wwff:KFF-0001").unwrap();
    assert_eq!(wwff_rec.title, "KFF-0001");
    assert!((wwff_rec.latitude - 0.5).abs() < 1e-9);
    assert!((wwff_rec.longitude - 0.5).abs() < 1e-9);
}

// -- WWFF-borrow match rule -------------------------------------------------

#[test]
fn reference_numeric_and_pota_borrow_mapping() {
    assert_eq!(reference_numeric("KFF-1234").as_deref(), Some("1234"));
    assert_eq!(reference_numeric("KFF-").as_deref(), None);
    assert_eq!(reference_numeric("KFF-12A").as_deref(), None);
    assert_eq!(pota_ref_for_wwff("KFF-1234").as_deref(), Some("US-1234"));
    assert_eq!(pota_ref_for_wwff("NOPE").as_deref(), None);
}

// -- free exports -----------------------------------------------------------

#[test]
fn point_in_ring_export_matches_domain() {
    let ring = || {
        vec![
            FfiCoordinate { latitude: 0.0, longitude: 0.0 },
            FfiCoordinate { latitude: 0.0, longitude: 1.0 },
            FfiCoordinate { latitude: 1.0, longitude: 1.0 },
            FfiCoordinate { latitude: 1.0, longitude: 0.0 },
        ]
    };
    assert!(point_in_ring(FfiCoordinate { latitude: 0.5, longitude: 0.5 }, ring()));
    assert!(!point_in_ring(FfiCoordinate { latitude: 5.0, longitude: 5.0 }, ring()));
}

#[test]
fn tota_tiles_in_region_export_wraps_domain() {
    let tiles = tota_tiles_in_region(
        FfiCoordinate { latitude: 40.0, longitude: -105.0 },
        0.01,
        0.01,
        100,
    );
    assert!(!tiles.is_empty());
    assert_eq!(tiles[0].tile.len(), 6);
}

// -- Feature-envelope cache round-trip --------------------------------------

#[test]
fn feature_envelope_wraps_geometry_and_properties() {
    let geometry = r#"{"type":"Polygon","coordinates":[]}"#;
    let props = r#"{"designation":"State Park"}"#;
    let envelope = feature_envelope(geometry, Some(props));
    let value: serde_json::Value = serde_json::from_str(&envelope).unwrap();
    assert_eq!(value["type"], "Feature");
    assert_eq!(value["geometry"]["type"], "Polygon");
    assert_eq!(value["properties"]["designation"], "State Park");
}

#[test]
fn feature_envelope_defaults_absent_properties_to_empty_object() {
    let envelope = feature_envelope(r#"{"type":"Polygon"}"#, None);
    let value: serde_json::Value = serde_json::from_str(&envelope).unwrap();
    assert_eq!(value["properties"], serde_json::json!({}));
}

#[test]
fn split_feature_envelope_recovers_geometry_and_properties() {
    let envelope = feature_envelope(
        r#"{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,0]]]}"#,
        Some(r#"{"acreage":100.5,"matchQuality":"exact"}"#),
    );
    let (geometry, properties) = split_feature_envelope(&envelope);
    assert!(geometry.contains("Polygon"));
    assert!(!geometry.contains("Feature"), "geometry is unwrapped, not the envelope");
    let props: serde_json::Value = serde_json::from_str(&properties.unwrap()).unwrap();
    assert_eq!(props["acreage"], 100.5);
    assert_eq!(props["matchQuality"], "exact");
}

#[test]
fn split_feature_envelope_legacy_bare_geometry_degrades_to_none() {
    // A pre-existing cache row written before the envelope round-trip is a bare
    // geometry — it must pass through unchanged with no properties.
    let bare = r#"{"type":"MultiPolygon","coordinates":[]}"#;
    let (geometry, properties) = split_feature_envelope(bare);
    assert_eq!(geometry, bare);
    assert!(properties.is_none());

    // Non-JSON garbage also passes through (defensive) with no properties.
    let (geometry, properties) = split_feature_envelope("not json");
    assert_eq!(geometry, "not json");
    assert!(properties.is_none());
}

#[test]
fn split_feature_envelope_empty_properties_object_is_none() {
    let envelope = feature_envelope(r#"{"type":"Polygon"}"#, None);
    let (_geometry, properties) = split_feature_envelope(&envelope);
    assert!(properties.is_none(), "an empty {{}} properties object yields None");
}

#[test]
fn park_boundaries_cache_hit_preserves_properties_and_kind() {
    // Write a park boundary the way `upsert_and_evict` does (as an envelope),
    // then read it back through `read_gis_cache` and confirm the callout
    // properties + kind survive the cache round-trip.
    let s = store();
    let map = api(s.clone());
    let now = now_secs();
    let boundary = FfiGeoBoundary {
        reference: "US-0001".into(),
        name: Some("Yellowstone".into()),
        geojson: unit_square_geojson(),
        properties_json: Some(r#"{"designation":"National Park","acreage":100.5,"matchQuality":"exact"}"#.into()),
        kind: Some("park".into()),
    };
    map.upsert_and_evict(KIND_PARK, std::slice::from_ref(&boundary), GIS_CACHE_CAP_PARK, now)
        .unwrap();

    let (hits, misses) = map.read_gis_cache(KIND_PARK, &["US-0001".to_string()], now + 10);
    assert!(misses.is_empty());
    assert_eq!(hits.len(), 1);
    let hit = &hits[0];
    assert!(hit.geojson.contains("Polygon"));
    assert!(!hit.geojson.contains("Feature"), "geometry is unwrapped from the envelope");
    assert_eq!(hit.kind.as_deref(), Some("park"));
    let props: serde_json::Value =
        serde_json::from_str(hit.properties_json.as_deref().unwrap()).unwrap();
    assert_eq!(props["designation"], "National Park");
    assert_eq!(props["acreage"], 100.5);
}

#[test]
fn park_boundaries_legacy_bare_geometry_cache_row_reads_without_properties() {
    // Simulate a pre-envelope cache row: a bare geometry written straight to the
    // GIS cache. `read_gis_cache` must return it with properties_json = None.
    let s = store();
    let map = api(s.clone());
    let now = now_secs();
    {
        let inner = s.inner.lock().unwrap();
        inner.upsert_gis(KIND_PARK, "US-0001", &unit_square_geojson(), now).unwrap();
    }
    let (hits, _misses) = map.read_gis_cache(KIND_PARK, &["US-0001".to_string()], now + 10);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].geojson, unit_square_geojson(), "bare geometry passes through");
    assert!(hits[0].properties_json.is_none());
    assert_eq!(hits[0].kind.as_deref(), Some("park"), "kind still tagged on hits");
}

// -- properties builders ----------------------------------------------------

#[test]
fn park_properties_json_omits_empty_and_serializes_present() {
    assert!(park_properties_json(None, None, None, "").is_none());
    let json = park_properties_json(Some("State Park"), None, Some(42.0), "exact").unwrap();
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["designation"], "State Park");
    assert_eq!(value["acreage"], 42.0);
    assert_eq!(value["matchQuality"], "exact");
    assert!(value.get("manager").is_none(), "absent field omitted");
}

#[test]
fn trail_properties_json_serializes_camel_case_keys() {
    let json = trail_properties_json(
        Some("National Historic Trail"),
        Some("NPS"),
        Some(12.5),
        Some("NC"),
        "exact",
    )
    .unwrap();
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["managingAgency"], "NPS");
    assert_eq!(value["lengthMiles"], 12.5);
    assert_eq!(value["state"], "NC");
}

// -- admin kind tagging (incl. combined/nil fallback) -----------------------

#[test]
fn admin_boundary_kind_uses_feature_kind_then_fips_fallback() {
    // Explicit per-feature kind wins.
    assert_eq!(admin_boundary_kind("state", "37021"), "admin_state");
    assert_eq!(admin_boundary_kind("county", "37"), "admin_county");
    // Unknown/empty kind (e.g. a combined query row the server didn't label)
    // falls back to the FIPS-id-length heuristic: ≤2 chars = state.
    assert_eq!(admin_boundary_kind("", "37"), "admin_state");
    assert_eq!(admin_boundary_kind("", "37021"), "admin_county");
    assert_eq!(admin_boundary_kind("bogus", "6"), "admin_state");
}
