//! Antenna types + radiation pattern math + free-text description parser.
//! Ports `AntennaPattern.swift` and `AntennaDescriptionParser.swift`.

use std::f64::consts::PI;

use regex::Regex;

use crate::band::BandUtilities;

// ---- AntennaType ----------------------------------------------------------

/// Antenna kind. Mirrors `AntennaType` in Swift; raw values match.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AntennaType {
    Dipole,
    Vertical,
    Loop,
    Yagi,
    LogPeriodic,
    Whip,
    Beverage,
    Longwire,
    EndFed,
    HexBeam,
    Unknown,
}

impl AntennaType {
    /// Swift raw value (camelCased enum-case string).
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Dipole => "dipole",
            Self::Vertical => "vertical",
            Self::Loop => "loop",
            Self::Yagi => "yagi",
            Self::LogPeriodic => "logPeriodic",
            Self::Whip => "whip",
            Self::Beverage => "beverage",
            Self::Longwire => "longwire",
            Self::EndFed => "endFed",
            Self::HexBeam => "hexBeam",
            Self::Unknown => "unknown",
        }
    }
}

// ---- AntennaPattern -------------------------------------------------------

/// Simplified 2D azimuthal radiation pattern. Port of `AntennaPattern`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AntennaPattern {
    Omnidirectional,
    /// `orientation` = wire direction in degrees. Max radiation is broadside (±90°).
    FigureEight { orientation: f64 },
    /// `heading` = direction of maximum gain; `beamwidth_deg` = -3 dB full beamwidth.
    Cardioid { heading: f64, beamwidth_deg: f64 },
}

impl AntennaPattern {
    /// Default pattern for an antenna type. `orientation_deg` is the wire or
    /// boom direction.
    pub fn default_for(antenna_type: AntennaType, orientation_deg: f64) -> Self {
        match antenna_type {
            AntennaType::Vertical | AntennaType::Whip | AntennaType::Loop => Self::Omnidirectional,
            AntennaType::Dipole
            | AntennaType::EndFed
            | AntennaType::Longwire
            | AntennaType::Beverage => Self::FigureEight {
                orientation: orientation_deg,
            },
            AntennaType::Yagi => Self::Cardioid {
                heading: orientation_deg,
                beamwidth_deg: 60.0,
            },
            AntennaType::LogPeriodic => Self::Cardioid {
                heading: orientation_deg,
                beamwidth_deg: 70.0,
            },
            AntennaType::HexBeam => Self::Cardioid {
                heading: orientation_deg,
                beamwidth_deg: 80.0,
            },
            AntennaType::Unknown => Self::Omnidirectional,
        }
    }

    /// Relative gain at the given bearing (0–360°), normalized 0.0–1.0.
    pub fn gain(self, bearing: f64) -> f64 {
        match self {
            Self::Omnidirectional => 1.0,
            Self::FigureEight { orientation } => {
                let broadside = normalized_angle(orientation + 90.0);
                let delta = angle_difference(bearing, broadside);
                let cos_val = (delta * PI / 180.0).cos();
                cos_val * cos_val
            }
            Self::Cardioid {
                heading,
                beamwidth_deg,
            } => {
                let sigma = beamwidth_deg / 2.35;
                if sigma <= 0.0 {
                    return 1.0;
                }
                let delta = angle_difference(bearing, heading);
                let abs_delta = delta.abs();
                let gaussian = (-(abs_delta * abs_delta) / (2.0 * sigma * sigma)).exp();
                let rear_delta = angle_difference(bearing, normalized_angle(heading + 180.0));
                let rear_gaussian = (-(rear_delta * rear_delta) / (2.0 * sigma * sigma)).exp();
                (gaussian + 0.15 * rear_gaussian).min(1.0)
            }
        }
    }

    /// `steps` evenly-spaced (angle, normalized_radius) pairs for rendering.
    pub fn polar_points(self, steps: usize) -> Vec<(f64, f64)> {
        let step_size = 360.0 / steps as f64;
        (0..steps)
            .map(|i| {
                let angle = i as f64 * step_size;
                (angle, self.gain(angle))
            })
            .collect()
    }
}

fn normalized_angle(angle: f64) -> f64 {
    let mut a = angle.rem_euclid(360.0);
    if a < 0.0 {
        a += 360.0;
    }
    a
}

fn angle_difference(a: f64, b: f64) -> f64 {
    let mut diff = (a - b).rem_euclid(360.0);
    if diff > 180.0 {
        diff -= 360.0;
    }
    diff
}

// ---- AntennaDescriptionParser ---------------------------------------------

/// Parsed structure from a free-text antenna description (typically pulled
/// from a KiwiSDR receiver). Port of `ParsedAntenna`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedAntenna {
    pub antenna_type: Option<AntennaType>,
    pub bands: Vec<String>,
    pub directionality: Option<String>,
    pub model_name: Option<String>,
    pub raw_description: String,
}

struct KnownModel {
    name: &'static str,
    antenna_type: AntennaType,
    direction: Option<&'static str>,
}

const KNOWN_MODELS: &[KnownModel] = &[
    KnownModel {
        name: "TCI 530",
        antenna_type: AntennaType::LogPeriodic,
        direction: Some("omni"),
    },
    KnownModel {
        name: "ALA1530",
        antenna_type: AntennaType::Loop,
        direction: Some("omni"),
    },
    KnownModel {
        name: "Mini-Whip",
        antenna_type: AntennaType::Whip,
        direction: Some("omni"),
    },
    KnownModel {
        name: "mini whip",
        antenna_type: AntennaType::Whip,
        direction: Some("omni"),
    },
    KnownModel {
        name: "miniwhip",
        antenna_type: AntennaType::Whip,
        direction: Some("omni"),
    },
    KnownModel {
        name: "W6LVP",
        antenna_type: AntennaType::Loop,
        direction: Some("omni"),
    },
    KnownModel {
        name: "T2FD",
        antenna_type: AntennaType::Dipole,
        direction: None,
    },
    KnownModel {
        name: "Wellbrook",
        antenna_type: AntennaType::Loop,
        direction: Some("omni"),
    },
    KnownModel {
        name: "PA0RDT",
        antenna_type: AntennaType::Whip,
        direction: Some("omni"),
    },
];

#[derive(Debug, Clone, Copy)]
struct BandRange {
    name: &'static str,
    low: f64,
    high: f64,
}

const BAND_RANGES: &[BandRange] = &[
    BandRange { name: "160m", low: 1.8, high: 2.0 },
    BandRange { name: "80m", low: 3.5, high: 4.0 },
    BandRange { name: "60m", low: 5.3, high: 5.4 },
    BandRange { name: "40m", low: 7.0, high: 7.3 },
    BandRange { name: "30m", low: 10.1, high: 10.15 },
    BandRange { name: "20m", low: 14.0, high: 14.35 },
    BandRange { name: "17m", low: 18.068, high: 18.168 },
    BandRange { name: "15m", low: 21.0, high: 21.45 },
    BandRange { name: "12m", low: 24.89, high: 24.99 },
    BandRange { name: "10m", low: 28.0, high: 29.7 },
    BandRange { name: "6m", low: 50.0, high: 54.0 },
];

/// Parse a free-text antenna description.
pub fn parse_antenna_description(description: &str) -> ParsedAntenna {
    let trimmed = description.trim();
    if trimmed.is_empty() {
        return ParsedAntenna {
            antenna_type: None,
            bands: Vec::new(),
            directionality: None,
            model_name: None,
            raw_description: description.to_string(),
        };
    }

    let lower = trimmed.to_lowercase();

    if let Some(model) = match_known_model(&lower) {
        let bands = extract_bands(&lower);
        let directionality = model
            .direction
            .map(|s| s.to_string())
            .or_else(|| extract_directionality(&lower));
        return ParsedAntenna {
            antenna_type: Some(model.antenna_type),
            bands,
            directionality,
            model_name: Some(model.name.to_string()),
            raw_description: description.to_string(),
        };
    }

    let antenna_type = extract_type(&lower);
    let bands = extract_bands(&lower);
    let directionality = extract_directionality(&lower);

    ParsedAntenna {
        antenna_type,
        bands,
        directionality,
        model_name: None,
        raw_description: description.to_string(),
    }
}

fn match_known_model(lower: &str) -> Option<&'static KnownModel> {
    KNOWN_MODELS.iter().find(|m| lower.contains(&m.name.to_lowercase()))
}

fn extract_type(lower: &str) -> Option<AntennaType> {
    if lower.contains("log periodic") || lower.contains("lpda") || lower.contains("log-periodic") {
        return Some(AntennaType::LogPeriodic);
    }
    if lower.contains("hex beam") || lower.contains("hexbeam") {
        return Some(AntennaType::HexBeam);
    }
    if lower.contains("end-fed") || lower.contains("end fed") || lower.contains("efhw") {
        return Some(AntennaType::EndFed);
    }
    if lower.contains("long wire") || lower.contains("longwire") {
        return Some(AntennaType::Longwire);
    }
    if lower.contains("beverage") {
        return Some(AntennaType::Beverage);
    }
    if lower.contains("yagi") {
        return Some(AntennaType::Yagi);
    }
    if lower.contains("dipole") || lower.contains("inverted-v") || lower.contains("inverted v") {
        return Some(AntennaType::Dipole);
    }
    if lower.contains("vertical") || lower.contains("vert ") || lower.starts_with("vert") {
        return Some(AntennaType::Vertical);
    }
    if lower.contains("loop") {
        return Some(AntennaType::Loop);
    }
    if lower.contains("whip") {
        return Some(AntennaType::Whip);
    }
    None
}

fn band_regex() -> &'static Regex {
    use std::sync::OnceLock;
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?i)(?:^|\b)(160|80|60|40|30|20|17|15|12|10|6|2)\s*m(?:eter)?s?\b").unwrap()
    })
}

fn mhz_range_regex() -> &'static Regex {
    use std::sync::OnceLock;
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)\s*[Mm][Hh][Zz]").unwrap()
    })
}

fn compass_regex() -> &'static Regex {
    use std::sync::OnceLock;
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        let dirs = "N|S|E|W|NE|NW|SE|SW|NNE|NNW|SSE|SSW|ENE|ESE|WNW|WSW";
        Regex::new(&format!(r"\b({dirs})\s*/\s*({dirs})\b")).unwrap()
    })
}

fn extract_bands(lower: &str) -> Vec<String> {
    let mut bands: Vec<String> = Vec::new();

    for caps in band_regex().captures_iter(lower) {
        let number = &caps[1];
        let band_name = format!("{number}m");
        if !bands.contains(&band_name) {
            bands.push(band_name);
        }
    }

    if bands.is_empty() {
        for caps in mhz_range_regex().captures_iter(lower) {
            let low: f64 = caps[1].parse().unwrap_or(0.0);
            let high: f64 = caps[2].parse().unwrap_or(0.0);
            for range in BAND_RANGES {
                if range.low < high && range.high > low {
                    let name = range.name.to_string();
                    if !bands.contains(&name) {
                        bands.push(name);
                    }
                }
            }
        }
    }

    bands.sort_by_key(|name| {
        BandUtilities::BAND_ORDER
            .iter()
            .position(|b| *b == name.as_str())
            .unwrap_or(usize::MAX)
    });
    bands
}

fn extract_directionality(lower: &str) -> Option<String> {
    if lower.contains("omni") {
        return Some("omni".to_string());
    }
    if let Some(m) = compass_regex().find(lower) {
        return Some(m.as_str().replace(' ', "").to_uppercase());
    }
    if lower.contains("broadside") {
        if let Some((_, after)) = lower.split_once("broadside") {
            let after = after.trim();
            if let Some(first) = after.split_whitespace().next() {
                let upper = first.to_uppercase();
                if upper.contains('/') {
                    return Some(upper);
                }
            }
        }
    }
    if lower.contains("directional") {
        return Some("directional".to_string());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- AntennaPattern ---------------------------------------------------

    #[test]
    fn omnidirectional_is_flat() {
        let p = AntennaPattern::Omnidirectional;
        for bearing in (0..360).step_by(30) {
            assert_eq!(p.gain(bearing as f64), 1.0);
        }
    }

    #[test]
    fn figure_eight_peaks_broadside_to_wire() {
        let p = AntennaPattern::FigureEight { orientation: 0.0 }; // wire E-W
        assert!((p.gain(90.0) - 1.0).abs() < 1e-9); // broadside
        assert!((p.gain(270.0) - 1.0).abs() < 1e-9);
        // Along the wire is a null
        assert!(p.gain(0.0).abs() < 1e-9);
        assert!(p.gain(180.0).abs() < 1e-9);
    }

    #[test]
    fn cardioid_peaks_on_heading() {
        let p = AntennaPattern::Cardioid {
            heading: 0.0,
            beamwidth_deg: 60.0,
        };
        let on_heading = p.gain(0.0);
        let off_heading = p.gain(90.0);
        assert!(on_heading > off_heading);
        assert!(on_heading > 0.95);
    }

    #[test]
    fn default_pattern_per_type() {
        assert!(matches!(
            AntennaPattern::default_for(AntennaType::Yagi, 30.0),
            AntennaPattern::Cardioid { heading: 30.0, beamwidth_deg: 60.0 }
        ));
        assert!(matches!(
            AntennaPattern::default_for(AntennaType::Dipole, 45.0),
            AntennaPattern::FigureEight { orientation: 45.0 }
        ));
        assert_eq!(
            AntennaPattern::default_for(AntennaType::Vertical, 0.0),
            AntennaPattern::Omnidirectional
        );
    }

    #[test]
    fn polar_points_have_expected_count() {
        let p = AntennaPattern::Omnidirectional;
        assert_eq!(p.polar_points(72).len(), 72);
    }

    // ---- Description parser ----------------------------------------------

    #[test]
    fn empty_returns_blank() {
        let parsed = parse_antenna_description("   ");
        assert_eq!(parsed.antenna_type, None);
        assert!(parsed.bands.is_empty());
    }

    #[test]
    fn known_model_short_circuits() {
        let parsed = parse_antenna_description("ALA1530 mag loop antenna");
        assert_eq!(parsed.model_name.as_deref(), Some("ALA1530"));
        assert_eq!(parsed.antenna_type, Some(AntennaType::Loop));
        assert_eq!(parsed.directionality.as_deref(), Some("omni"));
    }

    #[test]
    fn extracts_type_and_explicit_bands() {
        let parsed = parse_antenna_description("Inverted-V dipole for 40m and 20m");
        assert_eq!(parsed.antenna_type, Some(AntennaType::Dipole));
        assert_eq!(parsed.bands, vec!["40m", "20m"]);
    }

    #[test]
    fn extracts_bands_from_mhz_range_only_when_no_explicit_bands() {
        let parsed = parse_antenna_description("Wideband whip 0.01-30MHz");
        assert!(parsed.bands.contains(&"160m".to_string()));
        assert!(parsed.bands.contains(&"10m".to_string()));
        assert_eq!(parsed.antenna_type, Some(AntennaType::Whip));
    }

    #[test]
    fn directionality_omni_keyword() {
        let parsed = parse_antenna_description("Beverage omni-directional reception");
        assert_eq!(parsed.antenna_type, Some(AntennaType::Beverage));
        assert_eq!(parsed.directionality.as_deref(), Some("omni"));
    }

    // NOTE: the Swift compass-pair pattern matches against the lowercased
    // description with an uppercase-only regex, so it never fires in
    // practice. We mirror that behavior — fixing it is out of scope for the
    // port and would diverge from Swift's observable output.
    #[test]
    fn directionality_lowercase_compass_pair_unmatched_matches_swift_bug() {
        let parsed = parse_antenna_description("Beverage NE / SW oriented");
        assert_eq!(parsed.antenna_type, Some(AntennaType::Beverage));
        assert_eq!(parsed.directionality, None);
    }

    #[test]
    fn raw_description_preserved() {
        let raw = "Some 40m vertical";
        let parsed = parse_antenna_description(raw);
        assert_eq!(parsed.raw_description, raw);
    }
}
