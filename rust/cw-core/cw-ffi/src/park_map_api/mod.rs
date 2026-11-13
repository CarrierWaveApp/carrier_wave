//! Reference-map API (`ParkMapApi`) — the shared core behind the iOS
//! `ParkSearchMapView` and the Android park-map screen. Ties together the
//! Phase-C building blocks: viewport pins (POTA/SOTA/WWFF), unified reference
//! search, cache-through GIS boundary fetch (parks/trails/admin), the
//! WWFF-borrows-POTA boundary loan, cached SOTA zones, and the activation
//! "rosette" multiplier scan.
//!
//! Ports the network + geometry halves of `ParkSearchMapView+Data.swift`,
//! `ParkSearchMapView+WWFF.swift`, `ParkSearchMapView+Multipliers.swift`, and
//! `MultiplierFinder.swift`. Boundary geometry is kept as raw GeoJSON strings
//! (the `cw_net::boundaries` clients + the `gis_boundary_cache` store both hold
//! it verbatim; the renderer decodes it). See `.superpowers/sdd/task-7-brief.md`.
//!
//! ## Error model
//! Cache-warm boundary paths degrade to the cached data on a network failure
//! (no error). A cold-cache network failure throws [`CwError`] — the client
//! then shows that layer empty, matching the iOS behavior.

mod records;

use std::collections::HashMap;
use std::sync::Arc;

use cw_domain::maidenhead::{self, Coordinate};
use cw_domain::multiplier::{
    find_multipliers as domain_find_multipliers, CountyRings, LatLon, MultiplierKind, ParkPolygon,
    SummitPoint, WwffBorrowed,
};
use cw_domain::park_geometry::point_in_ring as domain_point_in_ring;
use cw_net::{
    AdminBoundariesClient, AdminBoundaryKind, BoundingBox, HttpClient, ParkBoundariesClient,
    ParkBoundaryGroup, TrailsClient,
};
use cw_store::{
    RefKind, GIS_CACHE_CAP_ADMIN, GIS_CACHE_CAP_PARK, GIS_CACHE_CAP_TRAIL, GIS_CACHE_TTL_SECS,
};

pub use records::*;

use crate::{CwError, FfiCoordinate, FieldStore};

// ---------------------------------------------------------------------------
// Fetch limit defaults (Swift's defaults; the server further clamps
// parks/trails to 100 and admin to 4000). These live HERE, not at the client.
// ---------------------------------------------------------------------------

/// Default max park boundaries per bbox fetch (Swift `ParkSearchMapView`).
pub const DEFAULT_PARK_FETCH_LIMIT: i64 = 50;
/// Default max trails per bbox fetch.
pub const DEFAULT_TRAIL_FETCH_LIMIT: i64 = 50;
/// Default max admin boundaries per bbox fetch.
pub const DEFAULT_ADMIN_FETCH_LIMIT: i64 = 500;

/// POTA references resolved per `by_refs` chunk — the Swift WWFF-borrow path's
/// `stride(..., by: 20)`; the park-boundaries endpoint caps at 20 refs.
const REF_CHUNK_SIZE: usize = 20;

/// GIS cache kind labels. `"zone"` is intentionally absent from any
/// `evict_gis` call site — zones are TTL-only by design (brief carry-forward).
const KIND_PARK: &str = "park";
const KIND_TRAIL: &str = "trail";
const KIND_ADMIN: &str = "admin";

/// [`FfiGeoBoundary::kind`] labels — the boundary's *own* kind, distinct from
/// the GIS cache `kind` column (`admin` splits into state/county here).
const BOUNDARY_KIND_PARK: &str = "park";
const BOUNDARY_KIND_TRAIL: &str = "trail";
const BOUNDARY_KIND_ADMIN_STATE: &str = "admin_state";
const BOUNDARY_KIND_ADMIN_COUNTY: &str = "admin_county";

impl From<BoundingBox> for FfiBoundingBox {
    fn from(bbox: BoundingBox) -> Self {
        FfiBoundingBox { west: bbox.west, south: bbox.south, east: bbox.east, north: bbox.north }
    }
}

impl From<FfiBoundingBox> for BoundingBox {
    fn from(bbox: FfiBoundingBox) -> Self {
        BoundingBox { west: bbox.west, south: bbox.south, east: bbox.east, north: bbox.north }
    }
}

/// Reference-map API bound to a [`FieldStore`] and the activities-server base
/// URL. Store reads (pins/search/zones) are synchronous; boundary fetches are
/// async and cache-through the store's `gis_boundary_cache`.
#[derive(uniffi::Object)]
pub struct ParkMapApi {
    store: Arc<FieldStore>,
    parks: ParkBoundariesClient,
    trails: TrailsClient,
    admin: AdminBoundariesClient,
}

#[uniffi::export]
impl ParkMapApi {
    /// Build a map API. `base_url` is the activities-server base (same URL the
    /// other net-backed APIs take); the three GIS clients are constructed on a
    /// shared [`HttpClient`], mirroring [`crate::reference_data_api::ReferenceDataApi::new`].
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>, base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(ParkMapApi {
            store,
            parks: ParkBoundariesClient::new(http.clone(), base_url.clone()),
            trails: TrailsClient::new(http.clone(), base_url.clone()),
            admin: AdminBoundariesClient::new(http, base_url),
        })
    }

    /// Viewport pins for the requested kinds (`"park"` | `"summit"` | `"wwff"`),
    /// each kind bounded by `limit` rows. Rows without coordinates are excluded
    /// by the store box readers. Empty store / unknown kind → empty, no error.
    pub fn pins_in_box(
        &self,
        bbox: FfiBoundingBox,
        kinds: Vec<String>,
        limit: i64,
    ) -> Result<Vec<FfiParkPin>, CwError> {
        let (min_lat, max_lat, min_lon, max_lon) = box_bounds(bbox);
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        let mut pins = Vec::new();
        for kind in &kinds {
            match kind.as_str() {
                "park" => {
                    for park in inner.fetch_pota_parks_in_box(min_lat, max_lat, min_lon, max_lon, limit)? {
                        if let (Some(latitude), Some(longitude)) = (park.latitude, park.longitude) {
                            pins.push(FfiParkPin {
                                reference: park.reference,
                                name: park.name,
                                latitude,
                                longitude,
                                kind: "park".to_string(),
                                activation_count: None,
                                altitude_m: None,
                            });
                        }
                    }
                }
                "summit" => {
                    for summit in inner.fetch_sota_summits_in_box(min_lat, max_lat, min_lon, max_lon, limit)? {
                        if let (Some(latitude), Some(longitude)) = (summit.latitude, summit.longitude) {
                            pins.push(FfiParkPin {
                                reference: summit.code,
                                name: summit.name,
                                latitude,
                                longitude,
                                kind: "summit".to_string(),
                                activation_count: Some(summit.activation_count),
                                altitude_m: Some(summit.altitude_m),
                            });
                        }
                    }
                }
                "wwff" => {
                    for wwff in inner.fetch_wwff_references_in_box(min_lat, max_lat, min_lon, max_lon, limit)? {
                        if let (Some(latitude), Some(longitude)) = (wwff.latitude, wwff.longitude) {
                            pins.push(FfiParkPin {
                                reference: wwff.reference,
                                name: wwff.name,
                                latitude,
                                longitude,
                                kind: "wwff".to_string(),
                                activation_count: None,
                                altitude_m: None,
                            });
                        }
                    }
                }
                _ => {}
            }
        }
        Ok(pins)
    }

    /// Unified reference search across the requested kinds — passthrough to
    /// `cw_store::search_references`. Empty `kinds` → empty (fails closed).
    pub fn search(
        &self,
        query: String,
        kinds: Vec<String>,
        limit: i64,
    ) -> Result<Vec<FfiRefSearchHit>, CwError> {
        let ref_kinds: Vec<RefKind> = kinds.iter().filter_map(|kind| ref_kind_from_str(kind)).collect();
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner
            .search_references(&query, &ref_kinds, limit)?
            .into_iter()
            .map(|hit| FfiRefSearchHit {
                kind: hit.kind,
                reference: hit.reference,
                name: hit.name,
                latitude: hit.latitude,
                longitude: hit.longitude,
            })
            .collect())
    }

    /// Cached SOTA activation zones for the given summit codes — a pure cached
    /// read of the `sota_zone` table (populated by `ReferenceDataApi`'s bulk
    /// zone refresh; no network here). Codes with no cached zone are absent.
    pub fn sota_zones_for(&self, codes: Vec<String>) -> Result<Vec<FfiGeoBoundary>, CwError> {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        Ok(inner
            .sota_zones_for_summits(&codes)?
            .into_iter()
            .map(|(code, geojson)| FfiGeoBoundary {
                reference: code,
                name: None,
                geojson,
                properties_json: None,
                kind: None,
            })
            .collect())
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl ParkMapApi {
    /// Park boundaries for explicit refs, cache-through the `"park"` GIS cache:
    /// read cache, fetch the misses via `by_refs` (chunked ≤20), upsert, evict.
    /// A network failure with at least one cache hit returns the cached subset;
    /// a fully-cold failure throws.
    pub async fn park_boundaries(
        &self,
        refs: Vec<String>,
        simplify: Option<f64>,
    ) -> Result<Vec<FfiGeoBoundary>, CwError> {
        let _ = simplify; // by_refs is full-resolution; simplify is a bbox-only knob.
        let now = now_secs();
        let (cached, misses) = self.read_gis_cache(KIND_PARK, &refs, now);
        if misses.is_empty() {
            return Ok(cached);
        }

        // Fetch the misses in chunks of ≤20 (the endpoint's ref cap). Stop at
        // the first chunk error, remembering what earlier chunks produced.
        let mut fetched: Vec<FfiGeoBoundary> = Vec::new();
        let mut fetch_error: Option<CwError> = None;
        for chunk in misses.chunks(REF_CHUNK_SIZE) {
            match self.parks.by_refs(chunk).await {
                Ok((groups, _meta)) => {
                    for group in groups {
                        // The server pre-merges per reference, but a park can
                        // still carry multiple features; join them into one
                        // GeoJSON GeometryCollection so the cache is one row per
                        // reference (matching the by-ref cache key contract).
                        fetched.push(park_group_boundary(group));
                    }
                }
                Err(err) => {
                    fetch_error = Some(err.into());
                    break;
                }
            }
        }

        // The hit/miss/upsert/evict/error decision is a pure function over the
        // (cached, fetched, error) triple — see `resolve_cache_through` + its
        // unit tests. Only the upsert/evict side-effect touches the store.
        let outcome = resolve_cache_through(cached, fetched, fetch_error)?;
        self.upsert_and_evict(KIND_PARK, &outcome.to_cache, GIS_CACHE_CAP_PARK, now)?;
        Ok(outcome.result)
    }

    /// Park boundaries within a viewport (`by_bbox`, `limit`/`simplify`), cached
    /// into the `"park"` GIS cache by reference. A bbox query has no known key
    /// set to read first, so a network failure throws (cold-cache semantics —
    /// the client shows the layer empty).
    pub async fn park_boundaries_in_box(
        &self,
        bbox: FfiBoundingBox,
        limit: Option<i64>,
        simplify: Option<f64>,
    ) -> Result<Vec<FfiGeoBoundary>, CwError> {
        let limit = limit.unwrap_or(DEFAULT_PARK_FETCH_LIMIT);
        let (groups, _meta) = self.parks.by_bbox(bbox.into(), limit, simplify).await?;
        let now = now_secs();
        let fetched: Vec<FfiGeoBoundary> = groups.into_iter().map(park_group_boundary).collect();
        self.upsert_and_evict(KIND_PARK, &fetched, GIS_CACHE_CAP_PARK, now)?;
        Ok(fetched)
    }

    /// A single park boundary at full resolution (`GET .../boundaries/{ref}`).
    /// Full-resolution geometry is not cached (the GIS cache holds the
    /// simplified by-ref/bbox rows); a network failure throws.
    pub async fn park_boundary_full(&self, reference: String) -> Result<FfiGeoBoundary, CwError> {
        let full = self.parks.full_res(&reference).await?;
        let properties_json = park_properties_json(
            full.designation.as_deref(),
            full.manager.as_deref(),
            full.acreage,
            &full.match_quality,
        );
        Ok(FfiGeoBoundary {
            reference: full.reference,
            name: Some(full.name),
            geojson: full.geometry_geojson,
            properties_json,
            kind: Some(BOUNDARY_KIND_PARK.to_string()),
        })
    }

    /// Historic trails within a viewport, cached into the `"trail"` GIS cache by
    /// reference. Cold-cache network failure throws.
    pub async fn trails_in_box(
        &self,
        bbox: FfiBoundingBox,
        limit: Option<i64>,
        simplify: Option<f64>,
    ) -> Result<Vec<FfiGeoBoundary>, CwError> {
        let limit = limit.unwrap_or(DEFAULT_TRAIL_FETCH_LIMIT);
        let (features, _meta) = self.trails.by_bbox(bbox.into(), limit, simplify).await?;
        let now = now_secs();
        let fetched: Vec<FfiGeoBoundary> = features
            .into_iter()
            .map(|feature| {
                let properties_json = trail_properties_json(
                    feature.designation.as_deref(),
                    feature.managing_agency.as_deref(),
                    feature.length_miles,
                    feature.state.as_deref(),
                    &feature.match_quality,
                );
                FfiGeoBoundary {
                    reference: feature.reference,
                    name: Some(feature.name),
                    geojson: feature.geometry_geojson,
                    properties_json,
                    kind: Some(BOUNDARY_KIND_TRAIL.to_string()),
                }
            })
            .collect();
        self.upsert_and_evict(KIND_TRAIL, &fetched, GIS_CACHE_CAP_TRAIL, now)?;
        Ok(fetched)
    }

    /// US admin boundaries (states/counties) within a viewport, cached into the
    /// `"admin"` GIS cache by region id. `kind` filters to `"state"`/`"county"`
    /// (any other value, or `None`, returns both). Cold-cache failure throws.
    pub async fn admin_boundaries_in_box(
        &self,
        bbox: FfiBoundingBox,
        kind: Option<String>,
        limit: Option<i64>,
        simplify: Option<f64>,
    ) -> Result<Vec<FfiGeoBoundary>, CwError> {
        let limit = limit.unwrap_or(DEFAULT_ADMIN_FETCH_LIMIT);
        let admin_kind = kind.as_deref().and_then(admin_kind_from_str);
        let features = self.admin.by_bbox(bbox.into(), admin_kind, limit, simplify).await?;
        let now = now_secs();
        let fetched: Vec<FfiGeoBoundary> = features
            .into_iter()
            .map(|feature| {
                // Per-feature kind from the admin client's own parsed `kind`
                // ("state"/"county"); fall back to the FIPS-id-length heuristic
                // (≤2 chars = state) if the server ever emits an unknown value,
                // so the classification logic lives here, not in two clients.
                let boundary_kind = admin_boundary_kind(&feature.kind, &feature.id);
                let properties_json = admin_properties_json(
                    &feature.kind,
                    feature.state_name.as_deref(),
                    &feature.fips,
                );
                FfiGeoBoundary {
                    reference: feature.id,
                    name: Some(feature.name),
                    geojson: feature.geometry_geojson,
                    properties_json,
                    kind: Some(boundary_kind),
                }
            })
            .collect();
        self.upsert_and_evict(KIND_ADMIN, &fetched, GIS_CACHE_CAP_ADMIN, now)?;
        Ok(fetched)
    }

    /// Borrow POTA park polygons for the given WWFF refs — port of
    /// `ParkSearchMapView+WWFF.swift`'s `loadWWFFItems`/`potaBoundaries`.
    ///
    /// Match rule: a WWFF reference `KFF-####` borrows the POTA park boundary
    /// `US-####` (same numeric tail, `KFF` prefix swapped for `US`). Only refs
    /// with a numeric tail participate. The borrowed POTA refs are resolved
    /// cache-first, in chunks of 20, via [`Self::park_boundaries`] — so any
    /// already-cached POTA polygon is reused with no network. Each returned
    /// [`FfiGeoBoundary`] is keyed by the **WWFF** reference (`reference`), with
    /// the borrowed POTA geometry; WWFF refs whose POTA park has no boundary are
    /// simply absent (the Swift path renders those as a bare marker instead).
    pub async fn wwff_borrowed_boundaries(
        &self,
        wwff_refs: Vec<String>,
    ) -> Result<Vec<FfiGeoBoundary>, CwError> {
        // KFF-#### → US-#### for the boundary lookup (Swift `potaForWWFF`).
        let mut pota_for_wwff: Vec<(String, String)> = Vec::new();
        for reference in &wwff_refs {
            if let Some(numeric) = reference_numeric(reference) {
                pota_for_wwff.push((reference.clone(), format!("US-{numeric}")));
            }
        }
        let mut pota_refs: Vec<String> =
            pota_for_wwff.iter().map(|(_, pota)| pota.clone()).collect();
        pota_refs.sort();
        pota_refs.dedup();

        let boundaries = self.park_boundaries(pota_refs, None).await?;
        let by_pota: HashMap<String, FfiGeoBoundary> =
            boundaries.into_iter().map(|b| (b.reference.clone(), b)).collect();

        let mut items = Vec::new();
        for (wwff_ref, pota_ref) in pota_for_wwff {
            if let Some(boundary) = by_pota.get(&pota_ref) {
                items.push(FfiGeoBoundary {
                    reference: wwff_ref,
                    name: boundary.name.clone(),
                    geojson: boundary.geojson.clone(),
                    properties_json: boundary.properties_json.clone(),
                    kind: boundary.kind.clone(),
                });
            }
        }
        Ok(items)
    }

    /// Activation-multiplier "rosette" scan over the viewport's loaded geometry.
    /// Resolves each summit/park/county's rings from the `"park"`/`"admin"` GIS
    /// caches (park polygons and their `park_centers` are built from the SAME
    /// park-ref list in this one call — the [`domain_find_multipliers`]
    /// same-list contract), runs the geometric detection, then merges the flat
    /// per-kind domain candidates back into one record per source location
    /// (`kinds`/`score`), sorted score-desc then title-asc. Port of
    /// `MultiplierFinder.find` + `MultipliersSheet`'s consumption.
    pub fn find_multipliers(
        &self,
        summit_refs: Vec<String>,
        park_refs: Vec<String>,
        wwff_borrowed_refs: Vec<String>,
        county_refs: Vec<String>,
    ) -> Result<Vec<FfiMultiplierCandidate>, CwError> {
        let now = now_secs();
        let inner = self.store.inner.lock().expect("store mutex poisoned");

        // Summit points + names.
        let mut summit_names: HashMap<String, String> = HashMap::new();
        let mut summits: Vec<SummitPoint> = Vec::new();
        for code in &summit_refs {
            if let Some(summit) = inner.fetch_sota_summit(code)? {
                if let (Some(latitude), Some(longitude)) = (summit.latitude, summit.longitude) {
                    summit_names.insert(summit.code.clone(), summit.name);
                    summits.push(SummitPoint { reference: summit.code, latitude, longitude });
                }
            }
        }

        // Park polygons + centers, built from the SAME park_refs list so the
        // domain same-list contract holds structurally (one center per polygon,
        // both derived from `park` below).
        let park_geojson = fetch_gis_geojson(&inner, KIND_PARK, &park_refs, now);
        let mut park_names: HashMap<String, String> = HashMap::new();
        for reference in &park_refs {
            if let Some(park) = inner.fetch_pota_park(reference)? {
                park_names.insert(park.reference, park.name);
            }
        }

        // County rings from the admin cache.
        let county_geojson = fetch_gis_geojson(&inner, KIND_ADMIN, &county_refs, now);
        drop(inner);

        let mut park_polygons: Vec<ParkPolygon> = Vec::new();
        let mut park_centers: Vec<(String, LatLon)> = Vec::new();
        for reference in &park_refs {
            let Some(geojson) = park_geojson.get(reference) else {
                continue;
            };
            let polygons = geojson_to_polygons(geojson);
            if polygons.is_empty() {
                continue;
            }
            let center = polygons_center(&polygons);
            debug_assert_eq!(
                park_polygons.len(),
                park_centers.len(),
                "park_polygons and park_centers must stay 1:1 (same-list contract)"
            );
            park_polygons.push(ParkPolygon { reference: reference.clone(), polygons });
            park_centers.push((reference.clone(), center));
        }

        let county_rings: Vec<CountyRings> = county_refs
            .iter()
            .filter_map(|reference| {
                county_geojson.get(reference).map(|geojson| CountyRings {
                    reference: reference.clone(),
                    rings: geojson_to_rings(geojson),
                })
            })
            .collect();

        // WWFF names + own coordinates, from the reference directory row —
        // Swift always centers/titles the rosette pin on the WWFF ref itself
        // (`ParkSearchMapView+WWFF.swift`'s `WWFFRenderItem.center`/`.name`),
        // never the borrowed POTA polygon's centroid.
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        let mut wwff_names: HashMap<String, String> = HashMap::new();
        let mut wwff_coords: HashMap<String, (f64, f64)> = HashMap::new();
        for reference in &wwff_borrowed_refs {
            if let Some(wwff) = inner.fetch_wwff_reference(reference)? {
                if let (Some(latitude), Some(longitude)) = (wwff.latitude, wwff.longitude) {
                    wwff_coords.insert(reference.clone(), (latitude, longitude));
                }
                wwff_names.insert(reference.clone(), wwff.name);
            }
        }
        drop(inner);

        let wwff_borrowed: Vec<WwffBorrowed> = wwff_borrowed_refs
            .iter()
            .filter_map(|reference| {
                // Prefer the WWFF ref's own coordinate; fall back to its
                // borrowed park polygon centroid only if the directory row
                // has no lat/lon (matches Swift, which requires `ref.latitude`/
                // `ref.longitude` to build a `WWFFRenderItem` at all — but the
                // Rust `wwff_borrowed_refs` list is caller-supplied without
                // that precondition, so degrade gracefully instead of dropping).
                if let Some(&(lat, lon)) = wwff_coords.get(reference) {
                    return Some(WwffBorrowed { reference: reference.clone(), latitude: lat, longitude: lon });
                }
                pota_ref_for_wwff(reference)
                    .and_then(|pota| park_geojson.get(&pota))
                    .map(|geojson| {
                        let (lat, lon) = polygons_center(&geojson_to_polygons(geojson));
                        WwffBorrowed { reference: reference.clone(), latitude: lat, longitude: lon }
                    })
            })
            .collect();

        let flat = domain_find_multipliers(
            &summits,
            &park_polygons,
            &park_centers,
            &wwff_borrowed,
            &county_rings,
        );

        let summit_ref_set: std::collections::HashSet<&String> = summit_refs.iter().collect();
        Ok(merge_candidates(flat, &summit_ref_set, &summit_names, &park_names, &wwff_names))
    }
}

impl ParkMapApi {
    /// Read cached `(reference → FfiGeoBoundary)` for `kind`+`refs`, returning
    /// `(hits, misses)`. `hits` preserve their cached name as `None` (the by-ref
    /// cache stores geometry only) so the caller keeps its own name map. The
    /// cached string is a Feature envelope (geometry + properties); it's split
    /// back into `geojson` + `properties_json` here (a legacy bare-geometry row
    /// yields `properties_json = None`).
    fn read_gis_cache(&self, kind: &str, refs: &[String], now: i64) -> (Vec<FfiGeoBoundary>, Vec<String>) {
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        let cached_pairs = inner
            .fetch_gis(kind, refs, now, GIS_CACHE_TTL_SECS)
            .unwrap_or_default();
        drop(inner);
        let cached_keys: std::collections::HashSet<String> =
            cached_pairs.iter().map(|(key, _)| key.clone()).collect();
        let hits: Vec<FfiGeoBoundary> = cached_pairs
            .into_iter()
            .map(|(reference, cached)| {
                let (geojson, properties_json) = split_feature_envelope(&cached);
                // `read_gis_cache` is only ever called for the "park" cache
                // (park_boundaries by-refs); tag the boundary kind so cache hits
                // and fresh fetches carry the same `kind`.
                let boundary_kind = (kind == KIND_PARK).then(|| BOUNDARY_KIND_PARK.to_string());
                FfiGeoBoundary { reference, name: None, geojson, properties_json, kind: boundary_kind }
            })
            .collect();
        let misses: Vec<String> =
            refs.iter().filter(|r| !cached_keys.contains(*r)).cloned().collect();
        (hits, misses)
    }

    /// Upsert freshly-fetched boundaries into `kind`'s cache and evict past
    /// `cap`. Never called with `kind == "zone"` (zones are TTL-only). The
    /// geometry + properties are stored as a single GeoJSON `Feature` envelope
    /// so the callout metadata survives a cache hit; [`read_gis_cache`] /
    /// [`fetch_gis_geojson`] split it back out on read.
    fn upsert_and_evict(
        &self,
        kind: &str,
        fetched: &[FfiGeoBoundary],
        cap: i64,
        now: i64,
    ) -> Result<(), CwError> {
        if fetched.is_empty() {
            return Ok(());
        }
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        for boundary in fetched {
            let envelope =
                feature_envelope(&boundary.geojson, boundary.properties_json.as_deref());
            inner.upsert_gis(kind, &boundary.reference, &envelope, now)?;
        }
        inner.evict_gis(kind, cap)?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Free exports (no `ParkMapApi` instance needed)
// ---------------------------------------------------------------------------

/// All 6-char TOTA tile rectangles within `lat_span`×`lon_span` of `center`,
/// capped at `cap`. Free export wrapping
/// [`cw_domain::maidenhead::tota_tiles_in_region`] (iOS Task 10 grid overlay).
#[uniffi::export]
pub fn tota_tiles_in_region(
    center: FfiCoordinate,
    lat_span: f64,
    lon_span: f64,
    cap: i64,
) -> Vec<FfiTotaTile> {
    maidenhead::tota_tiles_in_region(Coordinate::new(center.latitude, center.longitude), lat_span, lon_span, cap)
        .into_iter()
        .map(|tile| FfiTotaTile {
            tile: tile.tile,
            south: tile.south,
            west: tile.west,
            north: tile.north,
            east: tile.east,
        })
        .collect()
}

/// Ray-cast point-in-ring test (`[lat, lon]` degrees) — the same helper the
/// rosette scan uses, exported for iOS boundary-tap hit-testing (Task 10).
#[uniffi::export]
pub fn point_in_ring(point: FfiCoordinate, ring: Vec<FfiCoordinate>) -> bool {
    let ring_pts: Vec<(f64, f64)> = ring.iter().map(|c| (c.latitude, c.longitude)).collect();
    domain_point_in_ring((point.latitude, point.longitude), &ring_pts)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// `(min_lat, max_lat, min_lon, max_lon)` for a `west/south/east/north` box.
fn box_bounds(bbox: FfiBoundingBox) -> (f64, f64, f64, f64) {
    (bbox.south, bbox.north, bbox.west, bbox.east)
}

fn ref_kind_from_str(kind: &str) -> Option<RefKind> {
    match kind {
        "park" => Some(RefKind::Park),
        "summit" => Some(RefKind::Summit),
        "wwff" => Some(RefKind::Wwff),
        _ => None,
    }
}

fn admin_kind_from_str(kind: &str) -> Option<AdminBoundaryKind> {
    match kind {
        "state" => Some(AdminBoundaryKind::State),
        "county" => Some(AdminBoundaryKind::County),
        _ => None,
    }
}

/// Numeric tail of a reference (`"KFF-1234"` → `"1234"`), or `None`. Port of the
/// Swift `referenceNumeric`: everything after the last `-`, iff non-empty and
/// all digits.
fn reference_numeric(reference: &str) -> Option<String> {
    let dash = reference.rfind('-')?;
    let numeric = &reference[dash + 1..];
    if !numeric.is_empty() && numeric.chars().all(|c| c.is_ascii_digit()) {
        Some(numeric.to_string())
    } else {
        None
    }
}

/// `"KFF-####"` → `"US-####"` (the borrowed-park reference), or `None`.
fn pota_ref_for_wwff(wwff_ref: &str) -> Option<String> {
    reference_numeric(wwff_ref).map(|numeric| format!("US-{numeric}"))
}

/// The decision of a cache-through pass: the merged rows to hand back, and the
/// freshly-fetched subset to write into the cache.
struct CacheThroughOutcome {
    result: Vec<FfiGeoBoundary>,
    to_cache: Vec<FfiGeoBoundary>,
}

/// Pure cache-through resolution over a `(cached_hits, fetched, fetch_error)`
/// triple — the network-independent half of [`ParkMapApi::park_boundaries`],
/// factored out so the hit/miss/error semantics are unit-testable without HTTP:
///
/// - All refs cached (no misses) → the caller returns before ever calling this.
/// - Misses fetched OK → return `cached ∪ fetched` (fetched wins collisions),
///   cache the fetched subset.
/// - Fetch failed but the cache was warm (any hits) or partially succeeded →
///   return what we have, no error (iOS "network failure on a warm path
///   degrades to cache").
/// - Fetch failed with a fully cold cache and nothing fetched → propagate the
///   error (the client shows the layer empty).
fn resolve_cache_through(
    cached: Vec<FfiGeoBoundary>,
    fetched: Vec<FfiGeoBoundary>,
    fetch_error: Option<CwError>,
) -> Result<CacheThroughOutcome, CwError> {
    if let Some(err) = fetch_error {
        if cached.is_empty() && fetched.is_empty() {
            return Err(err);
        }
    }
    let fetched_keys: std::collections::HashSet<&String> =
        fetched.iter().map(|b| &b.reference).collect();
    let mut result: Vec<FfiGeoBoundary> =
        cached.into_iter().filter(|b| !fetched_keys.contains(&b.reference)).collect();
    result.extend(fetched.iter().cloned());
    Ok(CacheThroughOutcome { result, to_cache: fetched })
}

fn now_secs() -> i64 {
    chrono::Utc::now().timestamp()
}

/// Read `kind`+`refs` from the GIS cache into a `reference → geometry-geojson`
/// map (TTL applied), unwrapping each cached Feature envelope back to bare
/// geometry (a legacy bare-geometry row passes through unchanged). Used by the
/// rosette scan under a held store lock — it only needs the geometry.
fn fetch_gis_geojson(
    store: &cw_store::Store,
    kind: &str,
    refs: &[String],
    now: i64,
) -> HashMap<String, String> {
    store
        .fetch_gis(kind, refs, now, GIS_CACHE_TTL_SECS)
        .unwrap_or_default()
        .into_iter()
        .map(|(reference, cached)| (reference, split_feature_envelope(&cached).0))
        .collect()
}

/// Join per-feature GeoJSON geometry strings into one string: a single geometry
/// verbatim, or a `GeometryCollection` for 2+ (so one cache row holds a
/// multi-feature park).
fn geometry_collection(geometries: &[String]) -> String {
    match geometries {
        [] => "null".to_string(),
        [single] => single.clone(),
        many => {
            let joined = many.join(",");
            format!("{{\"type\":\"GeometryCollection\",\"geometries\":[{joined}]}}")
        }
    }
}

// ---------------------------------------------------------------------------
// Boundary construction + Feature-envelope cache round-trip
// ---------------------------------------------------------------------------

/// Build the park boundary FFI record for a grouped park (geometry joined into
/// one row, callout properties folded in, `kind = "park"`).
fn park_group_boundary(group: ParkBoundaryGroup) -> FfiGeoBoundary {
    let properties_json = park_properties_json(
        group.designation.as_deref(),
        group.manager.as_deref(),
        group.acreage,
        &group.match_quality,
    );
    FfiGeoBoundary {
        geojson: geometry_collection(&group.geometries_geojson),
        reference: group.reference,
        name: Some(group.name),
        properties_json,
        kind: Some(BOUNDARY_KIND_PARK.to_string()),
    }
}

/// Serialize the park callout properties into a JSON object string (`None` when
/// every field is empty). Keys mirror the Swift `BoundaryProperties`
/// camelCase and the iOS `ParkBoundary` callout decode.
fn park_properties_json(
    designation: Option<&str>,
    manager: Option<&str>,
    acreage: Option<f64>,
    match_quality: &str,
) -> Option<String> {
    let mut map = serde_json::Map::new();
    if let Some(designation) = designation {
        map.insert("designation".into(), designation.into());
    }
    if let Some(manager) = manager {
        map.insert("manager".into(), manager.into());
    }
    if let Some(acreage) = acreage {
        map.insert("acreage".into(), acreage.into());
    }
    if !match_quality.is_empty() {
        map.insert("matchQuality".into(), match_quality.into());
    }
    non_empty_object(map)
}

/// Serialize the trail callout properties into a JSON object string (`None` when
/// empty). Keys mirror the Swift `TrailProperties` camelCase.
fn trail_properties_json(
    designation: Option<&str>,
    managing_agency: Option<&str>,
    length_miles: Option<f64>,
    state: Option<&str>,
    match_quality: &str,
) -> Option<String> {
    let mut map = serde_json::Map::new();
    if let Some(designation) = designation {
        map.insert("designation".into(), designation.into());
    }
    if let Some(managing_agency) = managing_agency {
        map.insert("managingAgency".into(), managing_agency.into());
    }
    if let Some(length_miles) = length_miles {
        map.insert("lengthMiles".into(), length_miles.into());
    }
    if let Some(state) = state {
        map.insert("state".into(), state.into());
    }
    if !match_quality.is_empty() {
        map.insert("matchQuality".into(), match_quality.into());
    }
    non_empty_object(map)
}

/// Serialize the admin callout properties (`None` when empty). Keys mirror the
/// Swift `AdminBoundaryProperties` camelCase.
fn admin_properties_json(kind: &str, state_name: Option<&str>, fips: &str) -> Option<String> {
    let mut map = serde_json::Map::new();
    if !kind.is_empty() {
        map.insert("kind".into(), kind.into());
    }
    if let Some(state_name) = state_name {
        map.insert("stateName".into(), state_name.into());
    }
    if !fips.is_empty() {
        map.insert("fips".into(), fips.into());
    }
    non_empty_object(map)
}

/// `Some(json)` for a non-empty map, `None` otherwise.
fn non_empty_object(map: serde_json::Map<String, serde_json::Value>) -> Option<String> {
    if map.is_empty() {
        None
    } else {
        Some(serde_json::Value::Object(map).to_string())
    }
}

/// The [`FfiGeoBoundary::kind`] label for an admin feature: the client's own
/// per-feature `kind` (`"state"`/`"county"`), or the FIPS-id-length heuristic
/// (≤2 chars = state) when the value is unrecognized — one place for the rule.
fn admin_boundary_kind(feature_kind: &str, id: &str) -> String {
    match feature_kind {
        "state" => BOUNDARY_KIND_ADMIN_STATE.to_string(),
        "county" => BOUNDARY_KIND_ADMIN_COUNTY.to_string(),
        _ if id.chars().count() <= 2 => BOUNDARY_KIND_ADMIN_STATE.to_string(),
        _ => BOUNDARY_KIND_ADMIN_COUNTY.to_string(),
    }
}

/// Wrap a bare GeoJSON *geometry* string and its optional `properties` JSON into
/// a GeoJSON `Feature` envelope for the GIS cache, so the callout metadata
/// survives a cache hit. `properties` defaults to `{}` when absent.
fn feature_envelope(geometry_geojson: &str, properties_json: Option<&str>) -> String {
    let properties = properties_json.unwrap_or("{}");
    format!(
        "{{\"type\":\"Feature\",\"properties\":{properties},\"geometry\":{geometry_geojson}}}"
    )
}

/// Split a cached GIS string into `(geometry_geojson, properties_json)`. A
/// Feature envelope is split into its `geometry` (restringified) and
/// `properties` (restringified, `None` when absent/empty). A legacy bare
/// geometry (any non-Feature value, including one that fails to parse) passes
/// through unchanged with `properties_json = None` — backward compatible.
fn split_feature_envelope(cached: &str) -> (String, Option<String>) {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(cached) else {
        return (cached.to_string(), None);
    };
    if value.get("type").and_then(|t| t.as_str()) != Some("Feature") {
        return (cached.to_string(), None);
    }
    let geometry = value
        .get("geometry")
        .map(|geom| geom.to_string())
        .unwrap_or_else(|| "null".to_string());
    let properties = value.get("properties").and_then(|props| match props {
        serde_json::Value::Object(map) if !map.is_empty() => Some(props.to_string()),
        _ => None,
    });
    (geometry, properties)
}

/// Decode a GeoJSON geometry string into `(exterior, holes)` polygons in
/// `(lat, lon)` order. Handles `Polygon`, `MultiPolygon`, and
/// `GeometryCollection` (recursively); anything else yields no polygons.
/// GeoJSON coordinates are `[lon, lat]`, flipped here to the `(lat, lon)`
/// convention the geometry helpers use.
fn geojson_to_polygons(geojson: &str) -> Vec<(Vec<LatLon>, Vec<Vec<LatLon>>)> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(geojson) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    collect_polygons(&value, &mut out);
    out
}

fn collect_polygons(value: &serde_json::Value, out: &mut Vec<(Vec<LatLon>, Vec<Vec<LatLon>>)>) {
    let Some(kind) = value.get("type").and_then(|t| t.as_str()) else {
        return;
    };
    match kind {
        "Polygon" => {
            if let Some(rings) = value.get("coordinates").and_then(|c| c.as_array()) {
                if let Some(polygon) = polygon_from_rings(rings) {
                    out.push(polygon);
                }
            }
        }
        "MultiPolygon" => {
            if let Some(polygons) = value.get("coordinates").and_then(|c| c.as_array()) {
                for rings in polygons.iter().filter_map(|p| p.as_array()) {
                    if let Some(polygon) = polygon_from_rings(rings) {
                        out.push(polygon);
                    }
                }
            }
        }
        "GeometryCollection" => {
            if let Some(geometries) = value.get("geometries").and_then(|g| g.as_array()) {
                for geometry in geometries {
                    collect_polygons(geometry, out);
                }
            }
        }
        "Feature" => {
            // Safety net: a Feature envelope reaching here (should be split by
            // the cache readers first) unwraps to its geometry.
            if let Some(geometry) = value.get("geometry") {
                collect_polygons(geometry, out);
            }
        }
        _ => {}
    }
}

/// `[[exterior],[hole1],...]` GeoJSON ring array → `(exterior, holes)`.
fn polygon_from_rings(rings: &[serde_json::Value]) -> Option<(Vec<LatLon>, Vec<Vec<LatLon>>)> {
    let mut iter = rings.iter().filter_map(|ring| ring.as_array().map(|coords| ring_from_coords(coords)));
    let exterior = iter.next()?;
    let holes: Vec<Vec<LatLon>> = iter.collect();
    Some((exterior, holes))
}

/// A GeoJSON `[[lon,lat],...]` ring → `[(lat,lon),...]`.
fn ring_from_coords(coords: &[serde_json::Value]) -> Vec<LatLon> {
    coords
        .iter()
        .filter_map(|pt| {
            let pair = pt.as_array()?;
            let lon = pair.first()?.as_f64()?;
            let lat = pair.get(1)?.as_f64()?;
            Some((lat, lon))
        })
        .collect()
}

/// All rings (exteriors + holes, undifferentiated) of a GeoJSON geometry — the
/// `AdminBoundary.rings` shape the county-line test consumes.
fn geojson_to_rings(geojson: &str) -> Vec<Vec<LatLon>> {
    let mut rings = Vec::new();
    for (exterior, holes) in geojson_to_polygons(geojson) {
        rings.push(exterior);
        rings.extend(holes);
    }
    rings
}

/// Centroid of a polygon set's vertices (a cheap stand-in for the Swift
/// `park.bbox.center*`; both approximate the park center for the county-line
/// proximity test and the WWFF pin position). Empty → `(0.0, 0.0)`.
fn polygons_center(polygons: &[(Vec<LatLon>, Vec<Vec<LatLon>>)]) -> LatLon {
    let mut min_lat = f64::INFINITY;
    let mut max_lat = f64::NEG_INFINITY;
    let mut min_lon = f64::INFINITY;
    let mut max_lon = f64::NEG_INFINITY;
    let mut any = false;
    for (exterior, _holes) in polygons {
        for &(lat, lon) in exterior {
            any = true;
            min_lat = min_lat.min(lat);
            max_lat = max_lat.max(lat);
            min_lon = min_lon.min(lon);
            max_lon = max_lon.max(lon);
        }
    }
    if !any {
        return (0.0, 0.0);
    }
    ((min_lat + max_lat) / 2.0, (min_lon + max_lon) / 2.0)
}

/// Merge the flat per-kind domain candidates into one display record per source
/// location, keyed by the Swift id scheme (`summit:` / `wwff:` / `park:`), with
/// `kinds`/`score`/`title`/`detail` assembled and sorted score-desc, title-asc.
/// Port of `MultiplierFinder`'s per-source grouping + `MultiplierCandidate`.
fn merge_candidates(
    flat: Vec<cw_domain::multiplier::MultiplierCandidate>,
    summit_ref_set: &std::collections::HashSet<&String>,
    summit_names: &HashMap<String, String>,
    park_names: &HashMap<String, String>,
    wwff_names: &HashMap<String, String>,
) -> Vec<FfiMultiplierCandidate> {
    // Preserve first-seen order per location so `kinds` stays in emission order
    // (POTA+SOTA before County line for a summit that is both).
    let mut order: Vec<String> = Vec::new();
    let mut merged: HashMap<String, FfiMultiplierCandidate> = HashMap::new();

    for candidate in flat {
        let kind_label = kind_label(candidate.kind).to_string();
        let (id, title, detail) = match candidate.kind {
            MultiplierKind::PotaSota => {
                let summit_code = candidate.refs.first().cloned().unwrap_or_default();
                let park_ref = candidate.refs.get(1).cloned().unwrap_or_default();
                let title = summit_names.get(&summit_code).cloned().unwrap_or_else(|| summit_code.clone());
                let detail = format!("{summit_code} · {park_ref}");
                (format!("summit:{summit_code}"), title, detail)
            }
            MultiplierKind::PotaWwff => {
                let code = candidate.refs.first().cloned().unwrap_or_default();
                let title = wwff_names
                    .get(&code)
                    .filter(|name| !name.is_empty())
                    .cloned()
                    .unwrap_or_else(|| code.clone());
                (format!("wwff:{code}"), title, code)
            }
            MultiplierKind::CountyLine => {
                let reference = candidate.refs.first().cloned().unwrap_or_default();
                if summit_ref_set.contains(&reference) {
                    let title =
                        summit_names.get(&reference).cloned().unwrap_or_else(|| reference.clone());
                    (format!("summit:{reference}"), title, reference)
                } else {
                    let title =
                        park_names.get(&reference).cloned().unwrap_or_else(|| reference.clone());
                    let detail = format!("{reference} · near county line");
                    (format!("park:{reference}"), title, detail)
                }
            }
        };

        match merged.get_mut(&id) {
            Some(existing) => {
                if !existing.kinds.contains(&kind_label) {
                    existing.kinds.push(kind_label);
                    existing.score = existing.kinds.len() as i64;
                }
            }
            None => {
                order.push(id.clone());
                merged.insert(
                    id.clone(),
                    FfiMultiplierCandidate {
                        id,
                        title,
                        detail,
                        latitude: candidate.latitude,
                        longitude: candidate.longitude,
                        kinds: vec![kind_label],
                        score: 1,
                    },
                );
            }
        }
    }

    let mut candidates: Vec<FfiMultiplierCandidate> =
        order.into_iter().filter_map(|id| merged.remove(&id)).collect();
    candidates.sort_by(|lhs, rhs| {
        rhs.score.cmp(&lhs.score).then_with(|| lhs.title.cmp(&rhs.title))
    });
    candidates
}

/// The Swift `MultiplierKind` raw value used as the badge label.
fn kind_label(kind: MultiplierKind) -> &'static str {
    match kind {
        MultiplierKind::PotaSota => "POTA + SOTA",
        MultiplierKind::PotaWwff => "POTA + WWFF",
        MultiplierKind::CountyLine => "County line",
    }
}

#[cfg(test)]
mod tests;
