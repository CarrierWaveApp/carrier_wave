//! FFI records for [`super::ParkMapApi`] — pins, search hits, boundary
//! geometry, multiplier candidates, and TOTA tiles. Field sets verified
//! against the Task 9–13 consumers (the iOS `ParkSearchMapView` overlays and
//! the Android park-map screen).

/// One map pin: a POTA park, SOTA summit, or WWFF reference resolved to a
/// coordinate. `kind` is `"park"` | `"summit"` | `"wwff"`. `activation_count`
/// (summits) and `altitude_m` (summits) are `None` for the other kinds.
#[derive(uniffi::Record, Clone, PartialEq)]
pub struct FfiParkPin {
    pub reference: String,
    pub name: String,
    pub latitude: f64,
    pub longitude: f64,
    /// `"park"` | `"summit"` | `"wwff"`.
    pub kind: String,
    pub activation_count: Option<i64>,
    pub altitude_m: Option<i64>,
}

/// One unified reference-search hit (mirrors `cw_store::RefSearchHit`). `kind`
/// is `"park"` | `"summit"` | `"wwff"`; `latitude`/`longitude` are `None` for
/// rows the reference table stored without coordinates.
#[derive(uniffi::Record, Clone, PartialEq)]
pub struct FfiRefSearchHit {
    pub kind: String,
    pub reference: String,
    pub name: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}

/// One cached boundary: a reference id, an optional display name, the raw
/// GeoJSON **geometry** string (verbatim — the renderer decodes it), and the
/// callout metadata that rode alongside it. Trails and admin boundaries reuse
/// this shape; `name` carries the trail/region name.
///
/// `geojson` is always a bare GeoJSON *geometry* (`Polygon`/`MultiPolygon`/
/// `LineString`/`GeometryCollection`), never a `Feature` envelope — the
/// properties are split out into `properties_json` on the way through the GIS
/// cache so the geometry decode path stays unchanged.
///
/// `properties_json` is the feature's `properties` object as a raw JSON string
/// (park designation/manager/acreage/matchQuality; trail managingAgency/
/// lengthMiles/state; etc.), or `None` for boundaries with no properties (SOTA
/// zones, or legacy cache rows written before the Feature-envelope round-trip).
///
/// `kind` is the boundary's own kind label where known — `"park"` | `"trail"` |
/// `"admin_state"` | `"admin_county"` — so the iOS admin path can drop its
/// FIPS-length heuristic. `None` when the kind isn't carried (SOTA zones,
/// full-res single park, legacy rows).
#[derive(uniffi::Record, Clone, PartialEq)]
pub struct FfiGeoBoundary {
    pub reference: String,
    pub name: Option<String>,
    pub geojson: String,
    pub properties_json: Option<String>,
    pub kind: Option<String>,
}

/// A location flagged as an activation-multiplier opportunity — the merged,
/// display-ready record the "Multipliers" sheet renders. Port of the Swift
/// `MultiplierCandidate`: one record per source location with **all** of its
/// overlapping multiplier `kinds` folded in (`score = kinds.len()`), sorted by
/// the caller ([`super::ParkMapApi::find_multipliers`]) score-desc then
/// title-asc.
#[derive(uniffi::Record, Clone, PartialEq)]
pub struct FfiMultiplierCandidate {
    /// Stable id: `"summit:<code>"` | `"wwff:<code>"` | `"park:<ref>"`.
    pub id: String,
    pub title: String,
    /// Human detail line (e.g. `"W4C/CM-001 · US-1234"` or
    /// `"US-1234 · near county line"`), matching the Swift `detail`.
    pub detail: String,
    pub latitude: f64,
    pub longitude: f64,
    /// The multiplier reasons, each `"POTA + SOTA"` | `"POTA + WWFF"` |
    /// `"County line"` — the Swift `MultiplierKind` raw values, badge order
    /// preserved (POTA+SOTA before County line for a summit that is both).
    pub kinds: Vec<String>,
    /// `kinds.len()` — more overlapping multipliers rank higher.
    pub score: i64,
}

/// One 6-char TOTA tile rectangle (mirrors `cw_domain::maidenhead::TotaTile`).
#[derive(uniffi::Record, Clone, PartialEq)]
pub struct FfiTotaTile {
    pub tile: String,
    pub south: f64,
    pub west: f64,
    pub north: f64,
    pub east: f64,
}

/// A `west,south,east,north` viewport for the box/bbox queries (mirrors
/// `cw_net::BoundingBox`; kept as its own FFI record so callers don't depend on
/// the net crate's type).
#[derive(uniffi::Record, Clone, Copy, PartialEq)]
pub struct FfiBoundingBox {
    pub west: f64,
    pub south: f64,
    pub east: f64,
    pub north: f64,
}
