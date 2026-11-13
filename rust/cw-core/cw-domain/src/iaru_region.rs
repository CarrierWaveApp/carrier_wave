//! IARU region (1/2/3) plus geographic helpers. Port of `IARURegion.swift`.

use crate::maidenhead;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IaruRegion {
    /// Europe, Africa, Middle East, northern Asia (including all of Russia).
    Region1,
    /// The Americas and Greenland.
    Region2,
    /// Asia-Pacific south of 40° N, Australia, most of Oceania.
    Region3,
}

impl IaruRegion {
    pub fn as_u8(self) -> u8 {
        match self {
            Self::Region1 => 1,
            Self::Region2 => 2,
            Self::Region3 => 3,
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Region1 => "IARU Region 1",
            Self::Region2 => "IARU Region 2",
            Self::Region3 => "IARU Region 3",
        }
    }

    pub fn region_description(self) -> &'static str {
        match self {
            Self::Region1 => "Europe, Africa, Middle East",
            Self::Region2 => "Americas",
            Self::Region3 => "Asia-Pacific, Oceania",
        }
    }

    /// Derive a region from a coordinate. Same heuristics as
    /// `IARURegion.from(latitude:longitude:)` in Swift.
    pub fn from_coord(latitude: f64, longitude: f64) -> Self {
        if (-30.0..60.0).contains(&longitude) {
            return Self::Region1;
        }
        if (-170.0..-30.0).contains(&longitude) {
            return Self::Region2;
        }
        if (60.0..180.0).contains(&longitude) && latitude < 40.0 {
            return Self::Region3;
        }
        if longitude >= 60.0 && latitude >= 40.0 {
            return Self::Region1;
        }
        Self::Region2
    }

    /// Derive from a Maidenhead grid square.
    pub fn from_grid(grid: &str) -> Option<Self> {
        let coord = maidenhead::coordinate_from_grid(grid)?;
        Some(Self::from_coord(coord.latitude, coord.longitude))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buckets_known_locations() {
        assert_eq!(IaruRegion::from_coord(51.5, -0.1), IaruRegion::Region1); // London
        assert_eq!(IaruRegion::from_coord(37.0, -122.0), IaruRegion::Region2); // SF
        assert_eq!(IaruRegion::from_coord(-33.9, 151.2), IaruRegion::Region3); // Sydney
        assert_eq!(IaruRegion::from_coord(55.8, 37.6), IaruRegion::Region1); // Moscow
    }

    #[test]
    fn display_strings_match_swift() {
        assert_eq!(IaruRegion::Region1.display_name(), "IARU Region 1");
        assert_eq!(IaruRegion::Region2.region_description(), "Americas");
    }
}
