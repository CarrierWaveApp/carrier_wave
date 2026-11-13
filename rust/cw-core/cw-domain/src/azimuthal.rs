//! Azimuthal equidistant projection. Port of `AzimuthalProjection.swift`.
//!
//! Pure math: projecting lat/lon onto a plane centered on the operator's
//! QTH, bearing-binning helper, and the great-circle path generator. All
//! coordinates are in degrees on the input/output surface; internal math is
//! radians.

use std::f64::consts::PI;

use crate::maidenhead;

/// One point in azimuthal projection space (bearing + great-circle distance).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AzimuthalPoint {
    /// Degrees, 0 = North.
    pub bearing: f64,
    pub distance_km: f64,
    /// 0.0–1.0, clamped to `max_distance_km`.
    pub normalized_radius: f64,
}

/// Aggregated data for one angular sector of the azimuthal view.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BearingSector {
    pub id: usize,
    pub start_bearing: f64,
    pub end_bearing: f64,
    pub center_bearing: f64,
    pub spot_count: u32,
    pub qso_count: u32,
    /// 0.0–1.0, relative to the densest sector.
    pub density: f64,
}

/// Caller-supplied (bearing, is_spot) input for sector binning.
#[derive(Debug, Clone, Copy)]
pub struct BearingItem {
    pub bearing: f64,
    pub is_spot: bool,
}

/// Azimuthal equidistant projection centered on a single point.
#[derive(Debug, Clone, Copy)]
pub struct AzimuthalProjection {
    center_lat: f64,
    center_lon: f64,
    cos_center_lat: f64,
    sin_center_lat: f64,
}

/// Half of Earth's circumference, in km. Default `max_distance_km`.
pub const EARTH_HALF_CIRCUMFERENCE_KM: f64 = 20_020.0;

impl AzimuthalProjection {
    pub fn new(center_lat_deg: f64, center_lon_deg: f64) -> Self {
        let center_lat = center_lat_deg * PI / 180.0;
        let center_lon = center_lon_deg * PI / 180.0;
        Self {
            center_lat,
            center_lon,
            cos_center_lat: center_lat.cos(),
            sin_center_lat: center_lat.sin(),
        }
    }

    /// Project a point in degrees. Returns normalized `(x, y)` where ±1
    /// represents π radians (antipodal). `None` only for the exact antipode.
    pub fn project(&self, lat_deg: f64, lon_deg: f64) -> Option<(f64, f64)> {
        let lat = lat_deg * PI / 180.0;
        let lon = lon_deg * PI / 180.0;
        let d_lon = lon - self.center_lon;

        let cos_lat = lat.cos();
        let sin_lat = lat.sin();
        let cos_d_lon = d_lon.cos();
        let sin_d_lon = d_lon.sin();

        let cos_ang = self.sin_center_lat * sin_lat + self.cos_center_lat * cos_lat * cos_d_lon;
        let ang_dist = cos_ang.clamp(-1.0, 1.0).acos();

        if ang_dist > PI - 1e-10 {
            return None;
        }
        if ang_dist < 1e-10 {
            return Some((0.0, 0.0));
        }
        let sin_ang = ang_dist.sin();
        let k_scale = ang_dist / sin_ang;

        let x = k_scale * cos_lat * sin_d_lon;
        let y = k_scale * (self.cos_center_lat * sin_lat - self.sin_center_lat * cos_lat * cos_d_lon);
        Some((x / PI, y / PI))
    }

    /// Inverse projection. Returns degrees. `None` outside the unit circle
    /// (beyond the antipode).
    pub fn inverse_project(&self, nx: f64, ny: f64) -> Option<(f64, f64)> {
        let x = nx * PI;
        let y = ny * PI;
        let rho = (x * x + y * y).sqrt();
        if rho > PI {
            return None;
        }
        if rho < 1e-10 {
            return Some((self.center_lat * 180.0 / PI, self.center_lon * 180.0 / PI));
        }
        let sin_c = rho.sin();
        let cos_c = rho.cos();

        let lat = (cos_c * self.sin_center_lat + y * sin_c * self.cos_center_lat / rho).asin();
        let mut lon = self.center_lon
            + (x * sin_c).atan2(rho * self.cos_center_lat * cos_c - y * self.sin_center_lat * sin_c);
        while lon > PI {
            lon -= 2.0 * PI;
        }
        while lon < -PI {
            lon += 2.0 * PI;
        }
        Some((lat * 180.0 / PI, lon * 180.0 / PI))
    }

    /// Generate a great-circle path between two points in degrees. Returns
    /// `segments + 1` (lat, lon) pairs.
    pub fn great_circle_path(
        from_lat_deg: f64,
        from_lon_deg: f64,
        to_lat_deg: f64,
        to_lon_deg: f64,
        segments: usize,
    ) -> Vec<(f64, f64)> {
        let lat1 = from_lat_deg * PI / 180.0;
        let lon1 = from_lon_deg * PI / 180.0;
        let lat2 = to_lat_deg * PI / 180.0;
        let lon2 = to_lon_deg * PI / 180.0;

        let dist = angular_distance(lat1, lon1, lat2, lon2);
        if dist < 1e-10 {
            return vec![(from_lat_deg, from_lon_deg), (to_lat_deg, to_lon_deg)];
        }
        let sin_dist = dist.sin();
        let mut path = Vec::with_capacity(segments + 1);
        for i in 0..=segments {
            let frac = i as f64 / segments as f64;
            let a = ((1.0 - frac) * dist).sin() / sin_dist;
            let b = (frac * dist).sin() / sin_dist;
            let x = a * lat1.cos() * lon1.cos() + b * lat2.cos() * lon2.cos();
            let y = a * lat1.cos() * lon1.sin() + b * lat2.cos() * lon2.sin();
            let z = a * lat1.sin() + b * lat2.sin();
            let lat = z.atan2((x * x + y * y).sqrt()) * 180.0 / PI;
            let lon = y.atan2(x) * 180.0 / PI;
            path.push((lat, lon));
        }
        path
    }

    /// Project a target grid square relative to a center grid.
    pub fn project_from_grids(
        center_grid: &str,
        target_grid: &str,
        max_distance_km: f64,
    ) -> Option<AzimuthalPoint> {
        let bearing = maidenhead::bearing(center_grid, target_grid)?;
        let distance_km = maidenhead::distance_km(center_grid, target_grid)?;
        let normalized_radius = (distance_km / max_distance_km).min(1.0);
        Some(AzimuthalPoint {
            bearing,
            distance_km,
            normalized_radius,
        })
    }

    /// Project a target with a known bearing and distance.
    pub fn project_from_bearing(
        bearing: f64,
        distance_km: f64,
        max_distance_km: f64,
    ) -> AzimuthalPoint {
        AzimuthalPoint {
            bearing,
            distance_km,
            normalized_radius: (distance_km / max_distance_km).min(1.0),
        }
    }

    /// Convert an azimuthal point to Cartesian for canvas rendering. North =
    /// up (-y), east = right (+x).
    pub fn cartesian(point: AzimuthalPoint, center_x: f64, center_y: f64, view_radius: f64) -> (f64, f64) {
        let radians = point.bearing * PI / 180.0;
        let radius = point.normalized_radius * view_radius;
        let x = center_x + radius * radians.sin();
        let y = center_y - radius * radians.cos();
        (x, y)
    }

    /// Bin bearing data into equal-width sectors. Density is normalized to
    /// the densest sector's spot count.
    pub fn bin_into_sectors(items: &[BearingItem], sector_count: usize) -> Vec<BearingSector> {
        if sector_count == 0 {
            return Vec::new();
        }
        let sector_width = 360.0 / sector_count as f64;
        let mut spot_counts = vec![0u32; sector_count];
        let mut qso_counts = vec![0u32; sector_count];

        for item in items {
            let mut bearing = item.bearing.rem_euclid(360.0);
            if bearing < 0.0 {
                bearing += 360.0;
            }
            let mut idx = (bearing / sector_width) as usize;
            if idx >= sector_count {
                idx = sector_count - 1;
            }
            if item.is_spot {
                spot_counts[idx] += 1;
            } else {
                qso_counts[idx] += 1;
            }
        }

        let max_count = *spot_counts.iter().max().unwrap_or(&0);
        let normalizer = if max_count > 0 { max_count as f64 } else { 1.0 };

        (0..sector_count)
            .map(|i| {
                let start = i as f64 * sector_width;
                let end = start + sector_width;
                BearingSector {
                    id: i,
                    start_bearing: start,
                    end_bearing: end,
                    center_bearing: start + sector_width / 2.0,
                    spot_count: spot_counts[i],
                    qso_count: qso_counts[i],
                    density: spot_counts[i] as f64 / normalizer,
                }
            })
            .collect()
    }
}

fn angular_distance(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let s1 = ((lat2 - lat1) / 2.0).sin();
    let s2 = ((lon2 - lon1) / 2.0).sin();
    let inner = s1 * s1 + lat1.cos() * lat2.cos() * s2 * s2;
    2.0 * inner.sqrt().asin()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn projecting_center_yields_origin() {
        let proj = AzimuthalProjection::new(37.0, -122.0);
        let (x, y) = proj.project(37.0, -122.0).unwrap();
        assert!(x.abs() < 1e-12);
        assert!(y.abs() < 1e-12);
    }

    #[test]
    fn inverse_of_project_round_trips() {
        let proj = AzimuthalProjection::new(37.0, -122.0);
        let original_lat = 51.5; // London-ish
        let original_lon = -0.1;
        let (x, y) = proj.project(original_lat, original_lon).unwrap();
        let (lat, lon) = proj.inverse_project(x, y).unwrap();
        assert!((lat - original_lat).abs() < 1e-6);
        assert!((lon - original_lon).abs() < 1e-6);
    }

    #[test]
    fn antipodal_projection_is_none() {
        let proj = AzimuthalProjection::new(0.0, 0.0);
        // Exact antipode of (0, 0) — (0, 180) — angular distance is π.
        assert_eq!(proj.project(0.0, 180.0), None);
    }

    #[test]
    fn project_from_bearing_clamps_radius() {
        let p = AzimuthalProjection::project_from_bearing(45.0, 30_000.0, EARTH_HALF_CIRCUMFERENCE_KM);
        assert_eq!(p.normalized_radius, 1.0);
        assert_eq!(p.bearing, 45.0);
    }

    #[test]
    fn cartesian_due_north_is_above_center() {
        let p = AzimuthalPoint {
            bearing: 0.0,
            distance_km: 1.0,
            normalized_radius: 1.0,
        };
        let (x, y) = AzimuthalProjection::cartesian(p, 100.0, 100.0, 10.0);
        assert!((x - 100.0).abs() < 1e-9);
        assert!((y - 90.0).abs() < 1e-9); // y decreases going up
    }

    #[test]
    fn great_circle_path_endpoints_match_inputs() {
        let path = AzimuthalProjection::great_circle_path(37.0, -122.0, 51.5, -0.1, 10);
        assert_eq!(path.len(), 11);
        let (s_lat, s_lon) = path[0];
        let (e_lat, e_lon) = path[10];
        assert!((s_lat - 37.0).abs() < 1e-6);
        assert!((s_lon - (-122.0)).abs() < 1e-6);
        assert!((e_lat - 51.5).abs() < 1e-6);
        assert!((e_lon - (-0.1)).abs() < 1e-6);
    }

    #[test]
    fn bin_into_sectors_density_normalized() {
        let items = vec![
            BearingItem { bearing: 0.0, is_spot: true },
            BearingItem { bearing: 5.0, is_spot: true },
            BearingItem { bearing: 90.0, is_spot: true },
            BearingItem { bearing: 180.0, is_spot: false },
        ];
        let sectors = AzimuthalProjection::bin_into_sectors(&items, 36);
        assert_eq!(sectors.len(), 36);
        // Sector 0 (0–10°) should hold both spots and have density 1.0.
        assert_eq!(sectors[0].spot_count, 2);
        assert!((sectors[0].density - 1.0).abs() < 1e-9);
        // Sector 18 (180–190°) carries the QSO, not a spot — density 0.
        assert_eq!(sectors[18].qso_count, 1);
        assert_eq!(sectors[18].spot_count, 0);
        assert_eq!(sectors[18].density, 0.0);
    }
}
