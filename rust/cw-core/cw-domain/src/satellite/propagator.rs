//! SGP4 propagation + coordinate frames: TEME → ECEF → geodetic/topocentric.
//!
//! No Swift analogue — SatelliteKit's `geoPosition`/`topPosition` did these
//! conversions internally; this file replaces them on top of the `sgp4`
//! crate. Deliberate, documented approximations (both also made by
//! SatelliteKit): UT1 ≈ UTC (sub-second, ~0.004° of Earth rotation) and no
//! polar motion (arcsecond-level). Ellipsoid is WGS-72 (a = 6378.135 km,
//! f = 1/298.26) — the frame SGP4 is specified in.
//!
//! Units: kilometers and degrees externally; radians internally.

use chrono::{DateTime, Utc};

use super::Observer;
use super::SatTle;

/// WGS-72 semi-major axis, km.
const WGS72_A_KM: f64 = 6_378.135;
/// WGS-72 flattening.
const WGS72_F: f64 = 1.0 / 298.26;
/// Mean Earth radius for the footprint model, m (matches the Swift
/// `coverageRadiusMeters`).
const EARTH_RADIUS_M: f64 = 6_371_000.0;

/// Geodetic sub-satellite point. Mirrors what iOS read off SatelliteKit's
/// `geoPosition` (`alt` in km, longitude normalized to [−180, 180]).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GeoPosition {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub alt_km: f64,
}

/// Observer-relative look angles. Mirrors SatelliteKit's `AziEleDst`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Look {
    pub azimuth_deg: f64,
    pub elevation_deg: f64,
    pub range_km: f64,
}

/// One satellite's SGP4 state, built from a TLE. Mirrors the role of
/// SatelliteKit's `Satellite(withTLE:)`.
pub struct SatPropagator {
    constants: sgp4::Constants,
    epoch: chrono::NaiveDateTime,
    /// Mean motion from the TLE, revolutions per day (for the orbital-period
    /// ground-track span; SatelliteKit exposed radians/minute).
    pub mean_motion_rev_per_day: f64,
}

impl SatPropagator {
    /// Parse + initialize; `None` mirrors the Swift `try? Elements(...)`
    /// swallow — a malformed TLE just drops the satellite from the catalog.
    pub fn from_tle(tle: &SatTle) -> Option<SatPropagator> {
        let elements = sgp4::Elements::from_tle(
            Some(tle.name.clone()),
            tle.line1.as_bytes(),
            tle.line2.as_bytes(),
        )
        .ok()?;
        let constants = sgp4::Constants::from_elements(&elements).ok()?;
        Some(SatPropagator {
            constants,
            epoch: elements.datetime,
            mean_motion_rev_per_day: elements.mean_motion,
        })
    }

    /// Orbital period in minutes (1440 / rev-per-day), defaulting to 90 for
    /// degenerate mean motions — mirrors the Swift `periodMinutes` fallback.
    pub fn period_minutes(&self) -> f64 {
        if self.mean_motion_rev_per_day > 0.0 {
            1_440.0 / self.mean_motion_rev_per_day
        } else {
            90.0
        }
    }

    /// TEME position/velocity (km, km/s) at `t`, or `None` on propagation
    /// error (decayed orbit, out-of-range epoch — the Swift `try?` posture).
    pub fn teme_state(&self, t: DateTime<Utc>) -> Option<([f64; 3], [f64; 3])> {
        let minutes = (t.naive_utc() - self.epoch).num_milliseconds() as f64 / 60_000.0;
        let prediction = self.constants.propagate(sgp4::MinutesSinceEpoch(minutes)).ok()?;
        let finite = prediction.position.iter().chain(prediction.velocity.iter());
        if finite.clone().any(|v| !v.is_finite()) {
            return None;
        }
        Some((prediction.position, prediction.velocity))
    }

    /// Geodetic sub-satellite point at `t`. Mirrors SatelliteKit
    /// `geoPosition(julianDays:)`.
    pub fn geo_position(&self, t: DateTime<Utc>) -> Option<GeoPosition> {
        let (teme, _) = self.teme_state(t)?;
        let ecef = teme_to_ecef(teme, gmst_rad(julian_date(t)));
        let geo = ecef_to_geodetic(ecef);
        if !geo.lat_deg.is_finite() || !geo.lon_deg.is_finite() || !geo.alt_km.is_finite() {
            return None;
        }
        Some(geo)
    }

    /// Observer look angles at `t`. Mirrors SatelliteKit
    /// `topPosition(julianDays:observer:)` — including its observer
    /// round-trip: `topPosition` runs the observer through
    /// `geo2eci → eci2geo → geo2eci`, and because SatelliteKit's forward
    /// model is non-standard (see `geodetic_to_ecef`) while its inverse is
    /// standard, the effective observer lands ~16 km below the ellipsoid at
    /// mid-latitudes, with the SEZ basis taken from the round-tripped
    /// lat/lon. Ported verbatim (numerically verified to ~1e-5° / ~150 m
    /// against SatelliteKit output); a "corrected" observer would shift
    /// AOS/LOS by ~30 s vs the shipped iOS engine.
    pub fn look(&self, t: DateTime<Utc>, observer: Observer) -> Option<Look> {
        let (teme, _) = self.teme_state(t)?;
        let theta = gmst_rad(julian_date(t));
        let sat_ecef = teme_to_ecef(teme, theta);
        let round_trip = ecef_to_geodetic(geodetic_to_ecef(observer));
        let effective = Observer {
            lat_deg: round_trip.lat_deg,
            lon_deg: round_trip.lon_deg,
            alt_m: round_trip.alt_km * 1_000.0,
        };
        let obs_ecef = geodetic_to_ecef(effective);
        let rho = [
            sat_ecef[0] - obs_ecef[0],
            sat_ecef[1] - obs_ecef[1],
            sat_ecef[2] - obs_ecef[2],
        ];
        let lat = effective.lat_deg.to_radians();
        let lon = effective.lon_deg.to_radians();
        let (sin_lat, cos_lat) = lat.sin_cos();
        let (sin_lon, cos_lon) = lon.sin_cos();
        // ECEF → SEZ (South-East-Zenith).
        let south = sin_lat * cos_lon * rho[0] + sin_lat * sin_lon * rho[1] - cos_lat * rho[2];
        let east = -sin_lon * rho[0] + cos_lon * rho[1];
        let zenith = cos_lat * cos_lon * rho[0] + cos_lat * sin_lon * rho[1] + sin_lat * rho[2];
        let range = (south * south + east * east + zenith * zenith).sqrt();
        if range <= 0.0 || !range.is_finite() {
            return None;
        }
        let elevation = (zenith / range).asin().to_degrees();
        let azimuth = normalize_azimuth(east.atan2(-south).to_degrees());
        Some(Look { azimuth_deg: azimuth, elevation_deg: elevation, range_km: range })
    }

    /// Elevation-only helper for the pass scans (`-90` sentinel on failure,
    /// mirroring the Swift `elevation(_:at:site:)`).
    pub fn elevation_deg(&self, t: DateTime<Utc>, observer: Observer) -> f64 {
        self.look(t, observer).map_or(-90.0, |look| look.elevation_deg)
    }
}

/// Ground-coverage (footprint) radius in meters: great-circle distance from
/// the sub-satellite point to the 0° horizon. Port of the Swift
/// `SatellitePosition.coverageRadiusMeters`.
pub fn footprint_radius_m(altitude_km: f64) -> f64 {
    let orbit_radius = EARTH_RADIUS_M + altitude_km * 1_000.0;
    if orbit_radius <= EARTH_RADIUS_M {
        return 0.0;
    }
    EARTH_RADIUS_M * (EARTH_RADIUS_M / orbit_radius).acos()
}

/// Julian date from a UTC instant (UT1 ≈ UTC approximation).
pub fn julian_date(t: DateTime<Utc>) -> f64 {
    t.timestamp_millis() as f64 / 86_400_000.0 + 2_440_587.5
}

/// Greenwich Mean Sidereal Time, radians in [0, 2π) — IAU-1982 polynomial
/// (Vallado eq. 3-47) over Julian centuries of UT1 from J2000.
pub fn gmst_rad(jd_ut1: f64) -> f64 {
    let centuries = (jd_ut1 - 2_451_545.0) / 36_525.0;
    let seconds = 67_310.548_41
        + (876_600.0 * 3_600.0 + 8_640_184.812_866) * centuries
        + 0.093_104 * centuries * centuries
        - 6.2e-6 * centuries * centuries * centuries;
    let degrees = (seconds % 86_400.0) / 240.0;
    let mut radians = degrees.to_radians() % (2.0 * std::f64::consts::PI);
    if radians < 0.0 {
        radians += 2.0 * std::f64::consts::PI;
    }
    radians
}

/// Rotate a TEME vector into ECEF about Z by GMST (no polar motion).
fn teme_to_ecef(teme: [f64; 3], gmst: f64) -> [f64; 3] {
    let (sin_t, cos_t) = gmst.sin_cos();
    [
        cos_t * teme[0] + sin_t * teme[1],
        -sin_t * teme[0] + cos_t * teme[1],
        teme[2],
    ]
}

/// Geodetic observer → ECEF (km), **SatelliteKit-compatible**.
///
/// DELIBERATE DEVIATION FROM THE TEXTBOOK FORMULA: SatelliteKit's
/// `geo2eci` (Geography.swift) computes the prime vertical as
/// `Rₑ/√(1 + e²sin²φ)` — a **plus** where the standard formula has a
/// minus — which places the observer ~16 km lower at mid-latitudes
/// (≈ −0.2° elevation, ≈ +20 km slant range vs the textbook model).
/// The port mirrors it verbatim so the Rust engine reproduces the numbers
/// the shipped iOS engine shows (the repo's faithful-port rule), and so the
/// eventual iOS engine swap changes nothing user-visible. If SatelliteKit
/// ever fixes this upstream, flip the sign here together with regenerated
/// parity fixtures.
fn geodetic_to_ecef(observer: Observer) -> [f64; 3] {
    let lat = observer.lat_deg.to_radians();
    let lon = observer.lon_deg.to_radians();
    let alt_km = observer.alt_m / 1_000.0;
    let e2 = 2.0 * WGS72_F - WGS72_F * WGS72_F;
    let (sin_lat, cos_lat) = lat.sin_cos();
    let prime_vertical = WGS72_A_KM / (1.0 + e2 * sin_lat * sin_lat).sqrt();
    let z_scale = (1.0 - e2) * prime_vertical;
    [
        (prime_vertical + alt_km) * cos_lat * lon.cos(),
        (prime_vertical + alt_km) * cos_lat * lon.sin(),
        (z_scale + alt_km) * sin_lat,
    ]
}

/// ECEF (km) → geodetic on WGS-72, iterative latitude refinement.
fn ecef_to_geodetic(ecef: [f64; 3]) -> GeoPosition {
    let e2 = 2.0 * WGS72_F - WGS72_F * WGS72_F;
    let lon = ecef[1].atan2(ecef[0]);
    let axial = (ecef[0] * ecef[0] + ecef[1] * ecef[1]).sqrt();
    let mut lat = ecef[2].atan2(axial);
    let mut prime_vertical = WGS72_A_KM;
    for _ in 0..8 {
        let sin_lat = lat.sin();
        prime_vertical = WGS72_A_KM / (1.0 - e2 * sin_lat * sin_lat).sqrt();
        let next = (ecef[2] + prime_vertical * e2 * sin_lat).atan2(axial);
        if (next - lat).abs() < 1e-12 {
            lat = next;
            break;
        }
        lat = next;
    }
    let cos_lat = lat.cos();
    let alt_km = if cos_lat.abs() > 1e-9 {
        axial / cos_lat - prime_vertical
    } else {
        ecef[2].abs() - prime_vertical * (1.0 - e2)
    };
    GeoPosition {
        lat_deg: lat.to_degrees(),
        lon_deg: normalize_longitude(lon.to_degrees()),
        alt_km,
    }
}

/// Wrap longitude to [−180, 180]. Port of the Swift `normalizedLongitude`.
pub fn normalize_longitude(lon_deg: f64) -> f64 {
    let mut value = lon_deg % 360.0;
    if value > 180.0 {
        value -= 360.0;
    }
    if value < -180.0 {
        value += 360.0;
    }
    value
}

/// Wrap azimuth to [0, 360). Port of the Swift `normalizedAzimuth`.
pub fn normalize_azimuth(az_deg: f64) -> f64 {
    let mut value = az_deg % 360.0;
    if value < 0.0 {
        value += 360.0;
    }
    value
}

/// Shared test fixture: the ISS TLE from `SatNOGSClientTests.swift`
/// (epoch 2026-09-19), used by the propagator/pass-predictor parity tests.
#[cfg(test)]
pub(crate) fn iss_propagator() -> SatPropagator {
    let tle = SatTle {
        name: "ISS (ZARYA)".to_string(),
        norad_id: 25_544,
        line1: "1 25544U 98067A   26262.30395647  .00006211  00000-0  12007-3 0  9998"
            .to_string(),
        line2: "2 25544  51.6308 194.2901 0004815 157.3949 202.7252 15.49175317586346"
            .to_string(),
    };
    SatPropagator::from_tle(&tle).expect("valid TLE")
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    /// Vallado example 3-5: 1992 Aug 20 12:14:00 UT1 → GMST 152.578787810°.
    #[test]
    fn gmst_matches_vallado_example() {
        let t = Utc.with_ymd_and_hms(1992, 8, 20, 12, 14, 0).unwrap();
        let gmst_deg = gmst_rad(julian_date(t)).to_degrees();
        assert!((gmst_deg - 152.578_787_810).abs() < 1e-4, "gmst {gmst_deg}");
    }

    /// `ecef_to_geodetic` (the sub-point path) must invert the *textbook*
    /// forward transform. The observer path (`geodetic_to_ecef`) is
    /// deliberately NOT its inverse — it mirrors SatelliteKit's variant
    /// (see its doc comment), so the forward transform here is computed
    /// inline with the standard formula.
    #[test]
    fn subpoint_geodetic_inverts_standard_forward_transform() {
        let (lat_deg, lon_deg, alt_km) = (37.7_f64, -122.2_f64, 421.0_f64);
        let e2 = 2.0 * WGS72_F - WGS72_F * WGS72_F;
        let lat = lat_deg.to_radians();
        let lon = lon_deg.to_radians();
        let (sin_lat, cos_lat) = lat.sin_cos();
        let prime_vertical = WGS72_A_KM / (1.0 - e2 * sin_lat * sin_lat).sqrt();
        let ecef = [
            (prime_vertical + alt_km) * cos_lat * lon.cos(),
            (prime_vertical + alt_km) * cos_lat * lon.sin(),
            (prime_vertical * (1.0 - e2) + alt_km) * sin_lat,
        ];
        let geo = ecef_to_geodetic(ecef);
        assert!((geo.lat_deg - lat_deg).abs() < 1e-6, "lat {}", geo.lat_deg);
        assert!((geo.lon_deg - lon_deg).abs() < 1e-6, "lon {}", geo.lon_deg);
        assert!((geo.alt_km - alt_km).abs() < 1e-5, "alt {}", geo.alt_km);
    }

    #[test]
    fn footprint_radius_matches_swift_formula() {
        // 500 km LEO: R·acos(R/(R+h)) = 2_445_496.85 m (independently
        // verified against the closed form).
        let radius = footprint_radius_m(500.0);
        assert!((radius - 2_445_496.85).abs() < 1.0, "radius {radius}");
        assert_eq!(footprint_radius_m(-10.0), 0.0);
    }

    /// SatelliteKit parity fixtures. Generated 2026-09-20 by a throwaway
    /// Swift harness (SatelliteKit main, `Elements`/`geoPosition`/
    /// `topPosition`) with the ISS TLE from `SatNOGSClientTests.swift` and
    /// observer 37.7749, −122.4194. The committed tolerances are loose
    /// (±0.05° geodetic, ±0.5° az/el, ±5 km range) because they freeze one
    /// SatelliteKit version's output; observed agreement is far tighter.
    #[test]
    fn matches_satellitekit_fixtures() {
        let sat = iss_propagator();
        let observer = Observer::new(37.7749, -122.4194);
        let start = Utc.with_ymd_and_hms(2026, 9, 19, 12, 0, 0).unwrap();
        // (minutes, lat, lon, alt_km, az, el, range_km) — lon normalized
        // to [−180, 180] (SatelliteKit emits [0, 360)).
        let fixtures = [
            (0.0, 11.042_785, 23.750_156, 421.763_070, 39.926_188, -59.748_420, 11_492.906_467),
            (30.0, 36.768_753, 151.250_994, 418.998_485, 298.926_486, -29.961_801, 7_174.010_392),
            (90.0, 2.253_405, -6.183_916, 422.590_362, 71.235_517, -53.021_922, 10_702.453_906),
            (360.0, -23.733_194, -96.824_397, 429.022_870, 154.220_858, -29.907_996, 7_144.587_056),
            (720.0, -49.521_889, 124.642_514, 437.883_260, 233.680_226, -65.000_608, 11_988.636_586),
        ];
        for (minutes, lat, lon, alt, az, el, range) in fixtures {
            let t = start + chrono::Duration::seconds((minutes * 60.0) as i64);
            let geo = sat.geo_position(t).expect("geo");
            assert!((geo.lat_deg - lat).abs() < 0.05, "t+{minutes} lat {}", geo.lat_deg);
            assert!((geo.lon_deg - lon).abs() < 0.05, "t+{minutes} lon {}", geo.lon_deg);
            assert!((geo.alt_km - alt).abs() < 5.0, "t+{minutes} alt {}", geo.alt_km);
            let look = sat.look(t, observer).expect("look");
            assert!((look.azimuth_deg - az).abs() < 0.5, "t+{minutes} az {}", look.azimuth_deg);
            assert!(
                (look.elevation_deg - el).abs() < 0.5,
                "t+{minutes} el {}",
                look.elevation_deg
            );
            assert!((look.range_km - range).abs() < 5.0, "t+{minutes} range {}", look.range_km);
        }
    }

    #[test]
    fn normalizers() {
        assert_eq!(normalize_longitude(190.0), -170.0);
        assert_eq!(normalize_longitude(-190.0), 170.0);
        assert_eq!(normalize_azimuth(-10.0), 350.0);
        assert_eq!(normalize_azimuth(370.0), 10.0);
    }
}
