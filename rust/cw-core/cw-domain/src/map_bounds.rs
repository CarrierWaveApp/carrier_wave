//! Dateline-aware map bounds/camera math. Port of iOS
//! `ActivationMapHelpers.coordinateBounds` / `mapCameraPosition` /
//! `requiresGlobeView`.

/// Bounding region for a set of coordinates. `lon_span` is the minimal
/// angular span (may cross the antimeridian, in which case `center_lon`
/// is near ±180).
#[derive(Debug, Clone, PartialEq)]
pub struct MapBounds {
    pub center_lat: f64,
    pub center_lon: f64,
    pub lat_span: f64,
    pub lon_span: f64,
}

/// Spans larger than this use a globe camera on platforms that support it.
pub const GLOBE_THRESHOLD_DEG: f64 = 90.0;

/// NOTE: this is a two-arc (min/max) longitude bounds calculation, distinct
/// from `crate::share_render::viewport::tightest_longitude_bounds`, which
/// finds the true minimal enclosing arc via largest-gap search and is correct
/// for 3+ scattered points. Do NOT unify them: the viewport variant exists to
/// match the deleted Swift `FlatMapRenderer.computeViewport` exactly for
/// share-card framing — swapping either for the other silently reframes
/// multi-point share cards or QSO-map cameras and breaks golden/parity tests.
pub fn bounds_for(coords: &[(f64, f64)]) -> Option<MapBounds> {
    if coords.is_empty() {
        return None;
    }
    let min_lat = coords.iter().map(|c| c.0).fold(f64::INFINITY, f64::min);
    let max_lat = coords.iter().map(|c| c.0).fold(f64::NEG_INFINITY, f64::max);
    let min_lon = coords.iter().map(|c| c.1).fold(f64::INFINITY, f64::min);
    let max_lon = coords.iter().map(|c| c.1).fold(f64::NEG_INFINITY, f64::max);

    let lat_span = max_lat - min_lat;
    let center_lat = (min_lat + max_lat) / 2.0;

    let direct = max_lon - min_lon;
    let across = 360.0 - direct;
    let (lon_span, center_lon) = if across < direct {
        // Shorter to cross the dateline.
        let raw = max_lon + across / 2.0;
        (across, if raw > 180.0 { raw - 360.0 } else { raw })
    } else {
        (direct, (min_lon + max_lon) / 2.0)
    };

    Some(MapBounds { center_lat, center_lon, lat_span, lon_span })
}

pub fn requires_globe_view(b: &MapBounds) -> bool {
    b.lat_span.max(b.lon_span) > GLOBE_THRESHOLD_DEG
}

/// Padded camera spans: generous padding for wide views so endpoints are
/// not clipped; minimum 5° span; capped at 180°/360°.
pub fn camera_spans(b: &MapBounds) -> (f64, f64) {
    let padding = if b.lon_span > GLOBE_THRESHOLD_DEG { 1.5 } else { 1.3 };
    let lat = (b.lat_span.max(5.0) * padding).min(180.0);
    let lon = (b.lon_span.max(5.0) * padding).min(360.0);
    (lat, lon)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simple_bounds() {
        let b = bounds_for(&[(30.0, -100.0), (40.0, -90.0)]).unwrap();
        assert!((b.center_lat - 35.0).abs() < 1e-9);
        assert!((b.center_lon - -95.0).abs() < 1e-9);
        assert!((b.lat_span - 10.0).abs() < 1e-9);
        assert!((b.lon_span - 10.0).abs() < 1e-9);
    }

    // Points at 170° and -170°: crossing the dateline gives a 20° span
    // centered on ±180, not a 340° span centered on 0.
    #[test]
    fn dateline_crossing_prefers_short_span() {
        let b = bounds_for(&[(10.0, 170.0), (20.0, -170.0)]).unwrap();
        assert!((b.lon_span - 20.0).abs() < 1e-9);
        assert!(b.center_lon.abs() >= 179.999 || (b.center_lon - -180.0).abs() < 1e-9);
    }

    #[test]
    fn empty_is_none() {
        assert!(bounds_for(&[]).is_none());
    }

    #[test]
    fn globe_threshold_is_90() {
        let narrow = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 89.0, lon_span: 10.0 };
        let wide = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 10.0, lon_span: 91.0 };
        assert!(!requires_globe_view(&narrow));
        assert!(requires_globe_view(&wide));
    }

    // padding 1.3 normally, 1.5 when lon_span > 90; min span 5, caps 180/360.
    #[test]
    fn camera_spans_padding() {
        let b = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 2.0, lon_span: 100.0 };
        let (lat, lon) = camera_spans(&b);
        assert!((lat - 5.0 * 1.5).abs() < 1e-9); // max(2,5)=5, wide padding
        assert!((lon - 100.0 * 1.5).abs() < 1e-9);
        let small = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 20.0, lon_span: 30.0 };
        let (lat2, lon2) = camera_spans(&small);
        assert!((lat2 - 26.0).abs() < 1e-9);
        assert!((lon2 - 39.0).abs() < 1e-9);
    }
}
