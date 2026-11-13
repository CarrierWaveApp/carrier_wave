#[derive(uniffi::Record)]
pub struct FfiMapFilter {
    pub band: Option<String>,
    pub mode: Option<String>,
    pub park: Option<String>,
    pub start_date: Option<i64>,   // unix seconds UTC, day granularity
    pub end_date: Option<i64>,
    pub confirmed_only: bool,
    pub show_individual: bool,     // per-QSO pins instead of grid clusters
    pub show_paths: bool,          // build arcs
    pub max_qsos: Option<u32>,     // None = show all; Some(500) default cap
}

#[derive(uniffi::Record)]
pub struct FfiQsoMapAnnotation {
    pub id: String,                // qso id (individual) or grid key (cluster)
    pub latitude: f64,
    pub longitude: f64,
    pub grid_square: String,       // 4-char uppercase
    pub qso_count: i64,
    pub callsigns: Vec<String>,    // sorted
    pub most_recent: i64,          // unix seconds
    pub park_references: Vec<String>, // sorted
    pub weather: Option<String>,
    pub solar_conditions: Option<String>,
    pub average_wpm: Option<i64>,
    pub radio: Option<String>,
    pub antenna: Option<String>,
    pub key: Option<String>,
    pub mic: Option<String>,
}

#[derive(uniffi::Record)]
pub struct FfiMapPolyline {
    pub points: Vec<crate::FfiCoordinate>,
}

#[derive(uniffi::Record)]
pub struct FfiMapArc {
    pub id: String,                // qso id
    pub callsign: String,
    pub segments: Vec<FfiMapPolyline>,
}

#[derive(uniffi::Record)]
pub struct FfiMapBounds {
    pub center_lat: f64,
    pub center_lon: f64,
    pub lat_span: f64,
    pub lon_span: f64,
    pub camera_lat_span: f64,      // padded, min 5°, capped
    pub camera_lon_span: f64,
    pub requires_globe_view: bool,
}

#[derive(uniffi::Record)]
pub struct FfiMapStats {
    pub duration_seconds: Option<i64>,
    pub qso_rate: Option<f64>,     // QSOs/hour
    pub average_distance_km: Option<f64>,
    pub longest_distance_km: Option<f64>,
    pub watts_per_mile: Option<f64>,
    pub unique_states: i64,
    pub unique_dxcc: i64,
}

#[derive(uniffi::Record)]
pub struct FfiGridBounds {        // for Android grid-overlay polygons
    pub south: f64,
    pub west: f64,
    pub north: f64,
    pub east: f64,
}

/// One row's worth of input to [`super::compute_map_statistics`] — the subset
/// of `MapQsoRow` the stats aggregation actually reads. This is what iOS
/// `ActivationStatsHelper` switches to in Task 7.
#[derive(uniffi::Record)]
pub struct FfiMapStatInput {
    pub my_grid: Option<String>,
    pub their_grid: Option<String>,
    pub qso_date: i64,
    pub power: Option<i64>,
    pub logging_session_id: Option<String>,
    pub state: Option<String>,
    pub dxcc: Option<i64>,
}

/// One event on the session-replay timeline: a logged QSO or an RBN spot.
#[derive(uniffi::Record)]
pub struct FfiTimelineEvent {
    pub id: String,
    pub timestamp: i64,            // unix seconds
    pub is_qso: bool,             // false = RBN spot
    pub callsign: String,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub latitude: Option<f64>,    // resolved event coordinate (their grid / spotter)
    pub longitude: Option<f64>,
    pub snr: Option<i64>,
    pub spotter: Option<String>,  // original spotter string incl. skimmer suffix
}

/// The full timeline-replay data for one session: merged/sorted events plus the
/// operator's location and the session window. Port of `TimelineLoadedData`.
#[derive(uniffi::Record)]
pub struct FfiTimelineData {
    pub events: Vec<FfiTimelineEvent>,    // sorted ascending by timestamp
    pub my_grid: Option<String>,
    pub my_latitude: Option<f64>,
    pub my_longitude: Option<f64>,
    pub started_at: i64,
    pub ended_at: i64,
    pub unresolved_spotters: Vec<String>, // base calls (suffix-stripped, deduped, max 30)
}

/// The QSO-session map view-model: individual pins (session maps never
/// cluster), rove-stop coordinates, home→contact arcs, and bounds.
#[derive(uniffi::Record)]
pub struct FfiSessionMapData {
    pub annotations: Vec<FfiQsoMapAnnotation>, // individual pins (session maps don't cluster)
    pub rove_stops: Vec<crate::FfiCoordinate>,
    pub arcs: Vec<FfiMapArc>,
    pub bounds: Option<FfiMapBounds>,
}

/// The point-to-point QSO-detail map: operator + contacted station coordinates,
/// the arc between them, and distance/bearing. Port of `QSODetailView+Map`.
#[derive(uniffi::Record)]
pub struct FfiQsoDetailMap {
    pub my: Option<crate::FfiCoordinate>,
    pub their: Option<crate::FfiCoordinate>,
    pub their_source: String,       // "grid" | "park" | "none"
    pub arc: Vec<FfiMapPolyline>,   // empty unless both coordinates resolve
    pub distance_km: Option<f64>,
    pub bearing: Option<f64>,
}

#[derive(uniffi::Record)]
pub struct FfiQsoMapData {
    pub annotations: Vec<FfiQsoMapAnnotation>,
    pub arcs: Vec<FfiMapArc>,
    pub bounds: Option<FfiMapBounds>,
    pub stats: FfiMapStats,
    pub filtered_count: i64,       // rows matching filter (pre-cap)
    pub displayed_count: i64,      // rows after cap
    pub is_limited: bool,
    pub total_count: i64,          // all visible QSOs
    pub available_bands: Vec<String>,
    pub available_modes: Vec<String>,
    pub available_parks: Vec<String>,
    pub earliest_date: Option<i64>,
}
