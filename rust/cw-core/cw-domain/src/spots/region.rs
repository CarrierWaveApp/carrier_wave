//! Geographic region classification for spot locations. Port of Sweep's
//! `SpotRegion.swift` (`SpotRegion` / `SpotRegionGroup` / `SpotContinent`).
//!
//! Classification is coordinate-first (grid → Maidenhead center → lat/lon
//! boxes) with a two-letter-prefix fallback table for grids the converter
//! rejects — same order as the Swift original.

use crate::maidenhead;

/// Fine-grained region classification (14 values).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SpotRegion {
    NeUs,
    SeUs,
    MwUs,
    SwUs,
    NwUs,
    Canada,
    Mexico,
    Caribbean,
    Europe,
    Asia,
    Oceania,
    Africa,
    SouthAmerica,
    Other,
}

impl SpotRegion {
    /// Raw value, matching Swift's `rawValue` (persisted in
    /// `SessionSpot.region`).
    pub fn raw_value(self) -> &'static str {
        match self {
            SpotRegion::NeUs => "NE US",
            SpotRegion::SeUs => "SE US",
            SpotRegion::MwUs => "MW US",
            SpotRegion::SwUs => "SW US",
            SpotRegion::NwUs => "NW US",
            SpotRegion::Canada => "Canada",
            SpotRegion::Mexico => "Mexico",
            SpotRegion::Caribbean => "Caribbean",
            SpotRegion::Europe => "Europe",
            SpotRegion::Asia => "Asia",
            SpotRegion::Oceania => "Oceania",
            SpotRegion::Africa => "Africa",
            SpotRegion::SouthAmerica => "S. America",
            SpotRegion::Other => "Other",
        }
    }

    pub fn from_raw(raw: &str) -> Option<SpotRegion> {
        Some(match raw {
            "NE US" => SpotRegion::NeUs,
            "SE US" => SpotRegion::SeUs,
            "MW US" => SpotRegion::MwUs,
            "SW US" => SpotRegion::SwUs,
            "NW US" => SpotRegion::NwUs,
            "Canada" => SpotRegion::Canada,
            "Mexico" => SpotRegion::Mexico,
            "Caribbean" => SpotRegion::Caribbean,
            "Europe" => SpotRegion::Europe,
            "Asia" => SpotRegion::Asia,
            "Oceania" => SpotRegion::Oceania,
            "Africa" => SpotRegion::Africa,
            "S. America" => SpotRegion::SouthAmerica,
            "Other" => SpotRegion::Other,
            _ => return None,
        })
    }

    /// Short display name for compact views.
    pub fn short_name(self) -> &'static str {
        match self {
            SpotRegion::NeUs => "NE",
            SpotRegion::SeUs => "SE",
            SpotRegion::MwUs => "MW",
            SpotRegion::SwUs => "SW",
            SpotRegion::NwUs => "NW",
            SpotRegion::Canada => "CA",
            SpotRegion::Mexico => "MX",
            SpotRegion::Caribbean => "Carib",
            SpotRegion::Europe => "EU",
            SpotRegion::Asia => "AS",
            SpotRegion::Oceania => "OC",
            SpotRegion::Africa => "AF",
            SpotRegion::SouthAmerica => "SA",
            SpotRegion::Other => "Other",
        }
    }

    /// Classify a grid square into a region.
    pub fn from_grid(grid: Option<&str>) -> SpotRegion {
        let Some(grid) = grid else {
            return SpotRegion::Other;
        };
        let grid = grid.to_uppercase();
        if grid.chars().count() < 2 {
            return SpotRegion::Other;
        }

        if let Some(coord) = maidenhead::coordinate_from_grid(&grid) {
            return SpotRegion::from_coordinate(coord.latitude, coord.longitude);
        }

        let mut chars = grid.chars();
        let first = chars.next().unwrap();
        let second = chars.next().unwrap();
        let prefix: String = [first, second].iter().collect();
        classify_by_prefix(&prefix, second)
    }

    /// Classify a coordinate into a region. Box order matches the Swift
    /// original exactly — earlier boxes win on overlap.
    pub fn from_coordinate(lat: f64, lon: f64) -> SpotRegion {
        // North America
        if (24.0..=72.0).contains(&lat) && (-170.0..=-50.0).contains(&lon) {
            if (24.0..=49.0).contains(&lat) && (-125.0..=-66.0).contains(&lon) {
                return classify_us_region(lat, lon);
            }
            if lat > 49.0 && (-141.0..=-52.0).contains(&lon) {
                return SpotRegion::Canada;
            }
            if (14.0..=33.0).contains(&lat) && (-118.0..=-86.0).contains(&lon) {
                return SpotRegion::Mexico;
            }
        }

        if (10.0..=27.0).contains(&lat) && (-85.0..=-59.0).contains(&lon) {
            return SpotRegion::Caribbean;
        }
        if (35.0..=72.0).contains(&lat) && (-25.0..=45.0).contains(&lon) {
            return SpotRegion::Europe;
        }
        if ((0.0..=80.0).contains(&lat) && (45.0..=180.0).contains(&lon))
            || ((0.0..=80.0).contains(&lat) && (-180.0..=-140.0).contains(&lon))
        {
            return SpotRegion::Asia;
        }
        if ((-50.0..=0.0).contains(&lat) && (110.0..=180.0).contains(&lon))
            || ((-50.0..=0.0).contains(&lat) && (-180.0..=-130.0).contains(&lon))
        {
            return SpotRegion::Oceania;
        }
        if (-35.0..=37.0).contains(&lat) && (-20.0..=55.0).contains(&lon) {
            return SpotRegion::Africa;
        }
        if (-56.0..=15.0).contains(&lat) && (-82.0..=-34.0).contains(&lon) {
            return SpotRegion::SouthAmerica;
        }

        SpotRegion::Other
    }

    /// Map this fine-grained region to its coarser group.
    pub fn group(self) -> SpotRegionGroup {
        match self {
            SpotRegion::NeUs
            | SpotRegion::SeUs
            | SpotRegion::MwUs
            | SpotRegion::SwUs
            | SpotRegion::NwUs => SpotRegionGroup::Us,
            SpotRegion::Canada => SpotRegionGroup::Canada,
            SpotRegion::Mexico => SpotRegionGroup::Mexico,
            SpotRegion::Caribbean => SpotRegionGroup::Caribbean,
            SpotRegion::Europe => SpotRegionGroup::Europe,
            SpotRegion::Asia => SpotRegionGroup::Asia,
            SpotRegion::Oceania => SpotRegionGroup::Oceania,
            SpotRegion::Africa => SpotRegionGroup::Africa,
            SpotRegion::SouthAmerica => SpotRegionGroup::SouthAmerica,
            SpotRegion::Other => SpotRegionGroup::Other,
        }
    }

    /// Map this fine-grained region directly to its continent.
    pub fn continent(self) -> SpotContinent {
        self.group().continent()
    }
}

/// Coarser geographic region groups for spot filtering (10 values).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SpotRegionGroup {
    Us,
    Canada,
    Mexico,
    Caribbean,
    Europe,
    Asia,
    Oceania,
    Africa,
    SouthAmerica,
    Other,
}

impl SpotRegionGroup {
    pub fn raw_value(self) -> &'static str {
        match self {
            SpotRegionGroup::Us => "US",
            SpotRegionGroup::Canada => "Canada",
            SpotRegionGroup::Mexico => "Mexico",
            SpotRegionGroup::Caribbean => "Caribbean",
            SpotRegionGroup::Europe => "Europe",
            SpotRegionGroup::Asia => "Asia",
            SpotRegionGroup::Oceania => "Oceania",
            SpotRegionGroup::Africa => "Africa",
            SpotRegionGroup::SouthAmerica => "S. America",
            SpotRegionGroup::Other => "Other",
        }
    }

    /// Map this region group to its continent.
    pub fn continent(self) -> SpotContinent {
        match self {
            SpotRegionGroup::Us
            | SpotRegionGroup::Canada
            | SpotRegionGroup::Mexico
            | SpotRegionGroup::Caribbean => SpotContinent::NorthAmerica,
            SpotRegionGroup::SouthAmerica => SpotContinent::SouthAmerica,
            SpotRegionGroup::Europe => SpotContinent::Europe,
            SpotRegionGroup::Africa => SpotContinent::Africa,
            SpotRegionGroup::Asia => SpotContinent::Asia,
            SpotRegionGroup::Oceania => SpotContinent::Oceania,
            SpotRegionGroup::Other => SpotContinent::Other,
        }
    }
}

/// Continent-level grouping for DX spot filtering. Standard ITU/DXCC
/// six-continent model.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SpotContinent {
    NorthAmerica,
    SouthAmerica,
    Europe,
    Africa,
    Asia,
    Oceania,
    Other,
}

impl SpotContinent {
    pub fn raw_value(self) -> &'static str {
        match self {
            SpotContinent::NorthAmerica => "NA",
            SpotContinent::SouthAmerica => "SA",
            SpotContinent::Europe => "EU",
            SpotContinent::Africa => "AF",
            SpotContinent::Asia => "AS",
            SpotContinent::Oceania => "OC",
            SpotContinent::Other => "Other",
        }
    }

    pub fn from_raw(raw: &str) -> Option<SpotContinent> {
        Some(match raw {
            "NA" => SpotContinent::NorthAmerica,
            "SA" => SpotContinent::SouthAmerica,
            "EU" => SpotContinent::Europe,
            "AF" => SpotContinent::Africa,
            "AS" => SpotContinent::Asia,
            "OC" => SpotContinent::Oceania,
            "Other" => SpotContinent::Other,
            _ => return None,
        })
    }

    pub fn display_name(self) -> &'static str {
        match self {
            SpotContinent::NorthAmerica => "N. America",
            SpotContinent::SouthAmerica => "S. America",
            SpotContinent::Europe => "Europe",
            SpotContinent::Africa => "Africa",
            SpotContinent::Asia => "Asia",
            SpotContinent::Oceania => "Oceania",
            SpotContinent::Other => "Other",
        }
    }
}

fn classify_us_region(lat: f64, lon: f64) -> SpotRegion {
    if lon >= -100.0 {
        if lat >= 37.0 {
            SpotRegion::NeUs
        } else {
            SpotRegion::SeUs
        }
    } else if lat >= 42.0 {
        if lon >= -115.0 {
            SpotRegion::MwUs
        } else {
            SpotRegion::NwUs
        }
    } else {
        SpotRegion::SwUs
    }
}

/// Two-letter grid prefix fallback (Swift `prefixRegionMap` +
/// eastern/western US prefix rules).
fn classify_by_prefix(prefix: &str, second_char: char) -> SpotRegion {
    let mapped = match prefix {
        "DN" | "DM" | "CN" | "CM" => Some(SpotRegion::MwUs),
        "FO" | "EO" | "DO" | "CO" | "BO" => Some(SpotRegion::Canada),
        "DK" | "EK" => Some(SpotRegion::Mexico),
        "FK" | "FL" => Some(SpotRegion::Caribbean),
        "IO" | "JO" | "JN" | "IN" | "KO" | "KN" | "LO" | "LN" => Some(SpotRegion::Europe),
        "PM" | "OM" | "PL" | "OL" | "QL" | "QM" => Some(SpotRegion::Asia),
        "QF" | "QG" | "RF" | "RG" | "PF" | "PG" => Some(SpotRegion::Oceania),
        "KH" | "JH" | "IH" | "KG" | "JG" | "IG" => Some(SpotRegion::Africa),
        "FH" | "GH" | "GG" | "FG" | "FF" | "GF" => Some(SpotRegion::SouthAmerica),
        _ => None,
    };
    if let Some(region) = mapped {
        return region;
    }
    if matches!(prefix, "FN" | "FM" | "EN" | "EM" | "EL") {
        return if second_char >= 'L' { SpotRegion::NeUs } else { SpotRegion::SeUs };
    }
    if matches!(prefix, "DL" | "CL" | "BL" | "BM" | "BN") {
        return if second_char <= 'M' { SpotRegion::SwUs } else { SpotRegion::NwUs };
    }
    SpotRegion::Other
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn coordinate_boxes_match_swift_order() {
        // CN87 (Seattle) — NW US via coordinate path.
        assert_eq!(SpotRegion::from_grid(Some("CN87")), SpotRegion::NwUs);
        // FN31 (Connecticut) — NE US.
        assert_eq!(SpotRegion::from_grid(Some("FN31")), SpotRegion::NeUs);
        // EM12 (Texas) — SE US per Swift's lon >= -100 / lat < 37 rule.
        assert_eq!(SpotRegion::from_grid(Some("EM12")), SpotRegion::SeUs);
        // JO65 (Denmark) — Europe.
        assert_eq!(SpotRegion::from_grid(Some("JO65")), SpotRegion::Europe);
        // PM95 (Tokyo) — Asia.
        assert_eq!(SpotRegion::from_grid(Some("PM95")), SpotRegion::Asia);
        // QF56 (Sydney) — Oceania.
        assert_eq!(SpotRegion::from_grid(Some("QF56")), SpotRegion::Oceania);
        // GF05 (Buenos Aires) — South America.
        assert_eq!(SpotRegion::from_grid(Some("GF05")), SpotRegion::SouthAmerica);
    }

    #[test]
    fn missing_or_short_grid_is_other() {
        assert_eq!(SpotRegion::from_grid(None), SpotRegion::Other);
        assert_eq!(SpotRegion::from_grid(Some("A")), SpotRegion::Other);
        assert_eq!(SpotRegion::from_grid(Some("")), SpotRegion::Other);
    }

    #[test]
    fn us_split_boundaries() {
        // Denver-ish: lat 39.7, lon -105 → lat < 42 west of -100 → SW US.
        assert_eq!(SpotRegion::from_coordinate(39.7, -105.0), SpotRegion::SwUs);
        // Chicago-ish: lat 41.9, lon -87.6 → east of -100, lat >= 37 → NE US.
        assert_eq!(SpotRegion::from_coordinate(41.9, -87.6), SpotRegion::NeUs);
        // Boise-ish: lat 43.6, lon -116.2 → lat >= 42, lon < -115 → NW US.
        assert_eq!(SpotRegion::from_coordinate(43.6, -116.2), SpotRegion::NwUs);
        // Minneapolis-ish: lat 45, lon -93.3 → east of -100 → NE US (Swift quirk).
        assert_eq!(SpotRegion::from_coordinate(45.0, -93.3), SpotRegion::NeUs);
    }

    #[test]
    fn group_and_continent_mappings() {
        assert_eq!(SpotRegion::NwUs.group(), SpotRegionGroup::Us);
        assert_eq!(SpotRegion::NwUs.continent(), SpotContinent::NorthAmerica);
        assert_eq!(SpotRegion::Caribbean.continent(), SpotContinent::NorthAmerica);
        assert_eq!(SpotRegion::SouthAmerica.continent(), SpotContinent::SouthAmerica);
        assert_eq!(SpotRegion::Other.continent(), SpotContinent::Other);
    }

    #[test]
    fn raw_values_round_trip() {
        for region in [
            SpotRegion::NeUs,
            SpotRegion::SeUs,
            SpotRegion::MwUs,
            SpotRegion::SwUs,
            SpotRegion::NwUs,
            SpotRegion::Canada,
            SpotRegion::Mexico,
            SpotRegion::Caribbean,
            SpotRegion::Europe,
            SpotRegion::Asia,
            SpotRegion::Oceania,
            SpotRegion::Africa,
            SpotRegion::SouthAmerica,
            SpotRegion::Other,
        ] {
            assert_eq!(SpotRegion::from_raw(region.raw_value()), Some(region));
        }
    }
}
