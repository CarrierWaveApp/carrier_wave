//! Frequency + unit formatters. Ports of `FrequencyFormatter.swift` and
//! `UnitFormatter.swift`.
//!
//! `UnitFormatter.swift` reads `UserDefaults` for the imperial/metric
//! preference. That's a platform concern that doesn't belong inside the
//! portable core, so the Rust port takes a [`UnitSystem`] argument instead —
//! the iOS/macOS shim resolves the user setting and passes it in.

/// Imperial vs. metric. Caller-supplied because the core doesn't read
/// `UserDefaults`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnitSystem {
    Metric,
    Imperial,
}

impl UnitSystem {
    fn is_metric(self) -> bool {
        matches!(self, Self::Metric)
    }
}

// ---- FrequencyFormatter ---------------------------------------------------

const KM_TO_MILES: f64 = 0.621_371;
const MPH_TO_KMH: f64 = 1.609_34;

/// Format a frequency in MHz with the same precision rules as
/// `FrequencyFormatter.format` in Swift: 10 Hz precision, trailing zeros
/// trimmed but never fewer than 3 decimal places.
pub fn format_frequency(frequency_mhz: f64, include_unit: bool) -> String {
    let formatted = format!("{:.5}", frequency_mhz);
    let mut result = formatted;
    if let Some(dot_index) = result.find('.') {
        loop {
            if !result.ends_with('0') {
                break;
            }
            let current_decimals = result.len() - (dot_index + 1);
            if current_decimals > 3 {
                result.pop();
            } else {
                break;
            }
        }
    }
    if include_unit {
        format!("{result} MHz")
    } else {
        result
    }
}

/// Convenience: always include " MHz".
pub fn format_frequency_with_unit(frequency_mhz: f64) -> String {
    format_frequency(frequency_mhz, true)
}

/// Parse a frequency string. Same heuristics as the Swift `parse`:
/// - Plain number: > 1000 ⇒ kHz; 1.8–450 ⇒ MHz; anything else returns `None`.
/// - With suffix: `khz`, `mhz` (case-insensitive). Whitespace allowed.
/// - Dot-separated ham-radio notation `MHz.kHz.Hz`.
/// - Commas are stripped (thousands separator).
pub fn parse_frequency(input: &str) -> Option<f64> {
    let mut trimmed = input.trim().to_lowercase();
    trimmed = trimmed.replace(',', "");

    let mut explicit_khz = false;
    let mut explicit_mhz = false;
    if let Some(rest) = trimmed.strip_suffix("khz") {
        trimmed = rest.trim().to_string();
        explicit_khz = true;
    } else if let Some(rest) = trimmed.strip_suffix("mhz") {
        trimmed = rest.trim().to_string();
        explicit_mhz = true;
    }

    if !explicit_khz && !explicit_mhz {
        let dot_count = trimmed.chars().filter(|c| *c == '.').count();
        match dot_count {
            2 => return parse_dot_separated(&trimmed),
            n if n > 2 => return None,
            _ => {}
        }
    }

    let value: f64 = trimmed.parse().ok()?;
    if explicit_khz {
        return Some(value / 1_000.0);
    }
    if explicit_mhz {
        return Some(value);
    }
    if value > 1_000.0 {
        return Some(value / 1_000.0);
    }
    if (1.8..=450.0).contains(&value) {
        return Some(value);
    }
    None
}

fn parse_dot_separated(input: &str) -> Option<f64> {
    let parts: Vec<&str> = input.split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    let mhz_part = parts[0];
    let khz_part = parts[1];
    let hz_part = parts[2];
    if mhz_part.is_empty()
        || khz_part.is_empty()
        || !mhz_part.chars().all(|c| c.is_ascii_digit())
        || !khz_part.chars().all(|c| c.is_ascii_digit())
        || !hz_part.chars().all(|c| c.is_ascii_digit())
    {
        return None;
    }
    let combined = format!("{mhz_part}.{khz_part}{hz_part}");
    let value: f64 = combined.parse().ok()?;
    if (1.8..=450.0).contains(&value) {
        Some(value)
    } else {
        None
    }
}

// ---- UnitFormatter --------------------------------------------------------

/// Distance with unit, in km.
pub fn format_distance(km: f64, units: UnitSystem) -> String {
    if units.is_metric() {
        metric_distance(km)
    } else {
        imperial_distance(km * KM_TO_MILES)
    }
}

/// Compact distance with no unit label (e.g. "5.2k" or "340").
pub fn format_distance_compact(km: f64, units: UnitSystem) -> String {
    let value = if units.is_metric() { km } else { km * KM_TO_MILES };
    if value >= 1_000.0 {
        format!("{:.0}k", value / 1_000.0)
    } else {
        format!("{:.0}", value)
    }
}

/// Compact distance with a trailing label (e.g. "1.2k km max").
pub fn format_distance_compact_labeled(km: f64, label: &str, units: UnitSystem) -> String {
    let unit = if units.is_metric() { "km" } else { "mi" };
    let value = if units.is_metric() { km } else { km * KM_TO_MILES };
    if value >= 1_000.0 {
        let precision = if value >= 10_000.0 { 0 } else { 1 };
        format!(
            "{:.*}k {} {}",
            precision as usize,
            value / 1_000.0,
            unit,
            label
        )
    } else {
        format!("{:.0} {} {}", value, unit, label)
    }
}

/// Range from meters: e.g. "120-450 km" or "75-280 mi".
pub fn format_distance_range(min_meters: f64, max_meters: f64, units: UnitSystem) -> String {
    if units.is_metric() {
        let lo = min_meters / 1_000.0;
        let hi = max_meters / 1_000.0;
        format!("{:.0}-{:.0} km", lo, hi)
    } else {
        let lo = min_meters / 1_609.344;
        let hi = max_meters / 1_609.344;
        format!("{:.0}-{:.0} mi", lo, hi)
    }
}

/// Distance from meters.
pub fn format_distance_from_meters(meters: f64, units: UnitSystem) -> String {
    format_distance(meters / 1_000.0, units)
}

/// Temperature given in Fahrenheit; auto-converts to °C when metric.
pub fn format_temperature(fahrenheit: f64, units: UnitSystem) -> String {
    if units.is_metric() {
        let celsius = (fahrenheit - 32.0) * 5.0 / 9.0;
        format!("{}\u{00B0}C", celsius.round() as i64)
    } else {
        format!("{}\u{00B0}F", fahrenheit as i64)
    }
}

/// Compact temperature without unit suffix.
pub fn format_temperature_compact(fahrenheit: f64, units: UnitSystem) -> String {
    if units.is_metric() {
        let celsius = (fahrenheit - 32.0) * 5.0 / 9.0;
        format!("{}\u{00B0}", celsius.round() as i64)
    } else {
        format!("{}\u{00B0}", fahrenheit as i64)
    }
}

/// Secondary unit display (opposite of preference).
pub fn format_temperature_secondary(fahrenheit: f64, units: UnitSystem) -> String {
    if units.is_metric() {
        format!("{}\u{00B0}F", fahrenheit as i64)
    } else {
        let celsius = (fahrenheit - 32.0) * 5.0 / 9.0;
        format!("{}\u{00B0}C", celsius.round() as i64)
    }
}

/// Wind speed from mph, with optional cardinal direction.
pub fn format_wind_speed(mph: f64, direction: Option<&str>, units: UnitSystem) -> String {
    let suffix = direction.map(|d| format!(" {d}")).unwrap_or_default();
    if units.is_metric() {
        let kmh = mph * MPH_TO_KMH;
        format!("{} km/h{}", kmh.round() as i64, suffix)
    } else {
        format!("{} mph{}", mph as i64, suffix)
    }
}

/// W/mi → W/km when metric.
pub fn format_watts_per_distance(wpm: f64, units: UnitSystem) -> String {
    if units.is_metric() {
        format!("{:.2} W/km", wpm * KM_TO_MILES)
    } else {
        format!("{:.2} W/mi", wpm)
    }
}

/// Label only (for axis labels, etc.).
pub fn watts_per_distance_label(units: UnitSystem) -> &'static str {
    if units.is_metric() {
        "W/km"
    } else {
        "W/mi"
    }
}

/// Cardinal direction from a bearing in degrees.
pub fn cardinal(degrees: f64) -> &'static str {
    const DIRECTIONS: [&str; 8] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    let normalized = (degrees + 22.5).rem_euclid(360.0);
    let index = (normalized / 45.0) as usize;
    DIRECTIONS[index.min(7)]
}

/// "1240 mi NE" / "2000 km S".
pub fn format_distance_and_bearing(meters: f64, bearing_deg: f64, units: UnitSystem) -> String {
    let km = meters / 1_000.0;
    format!("{} {}", format_distance(km, units), cardinal(bearing_deg))
}

fn metric_distance(km: f64) -> String {
    if km < 1.0 {
        format!("{:.0} m", km * 1_000.0)
    } else if km < 10.0 {
        format!("{:.1} km", km)
    } else if km >= 1_000.0 {
        format!("{:.0}k km", km / 1_000.0)
    } else {
        format!("{:.0} km", km)
    }
}

fn imperial_distance(mi: f64) -> String {
    if mi < 0.1 {
        let feet = mi * 5_280.0;
        format!("{:.0} ft", feet)
    } else if mi < 10.0 {
        format!("{:.1} mi", mi)
    } else if mi >= 1_000.0 {
        format!("{:.0}k mi", mi / 1_000.0)
    } else {
        format!("{:.0} mi", mi)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- FrequencyFormatter -----------------------------------------------

    #[test]
    fn format_frequency_trims_to_three_decimals_by_default() {
        assert_eq!(format_frequency(14.062, false), "14.062");
        assert_eq!(format_frequency(14.06200, false), "14.062");
        // 10 Hz precision retained when needed
        assert_eq!(format_frequency(14.06205, false), "14.06205");
    }

    #[test]
    fn format_frequency_with_mhz_suffix() {
        assert_eq!(format_frequency_with_unit(7.040), "7.040 MHz");
    }

    #[test]
    fn parse_handles_explicit_units() {
        assert_eq!(parse_frequency("14060 kHz"), Some(14.060));
        assert_eq!(parse_frequency("14.060 MHz"), Some(14.060));
        assert_eq!(parse_frequency("14060kHz"), Some(14.060));
        assert_eq!(parse_frequency("14.060mhz"), Some(14.060));
    }

    #[test]
    fn parse_heuristic_for_plain_numbers() {
        assert_eq!(parse_frequency("14060"), Some(14.060));
        assert_eq!(parse_frequency("14.060"), Some(14.060));
        // Out of amateur band, no unit ⇒ None
        assert_eq!(parse_frequency("0.5"), None);
        assert_eq!(parse_frequency("1000"), None);
    }

    #[test]
    fn parse_dot_separated() {
        assert_eq!(parse_frequency("14.030.50"), Some(14.03050));
        assert_eq!(parse_frequency("7.040.00"), Some(7.04000));
    }

    #[test]
    fn parse_strips_commas() {
        assert_eq!(parse_frequency("14,060"), Some(14.060));
    }

    #[test]
    fn parse_rejects_nonsense() {
        assert_eq!(parse_frequency("abc"), None);
        assert_eq!(parse_frequency("14.060.50.30"), None);
    }

    // ---- UnitFormatter ----------------------------------------------------

    #[test]
    fn distance_metric_buckets() {
        assert_eq!(format_distance(0.5, UnitSystem::Metric), "500 m");
        assert_eq!(format_distance(5.4, UnitSystem::Metric), "5.4 km");
        assert_eq!(format_distance(120.0, UnitSystem::Metric), "120 km");
        assert_eq!(format_distance(1_500.0, UnitSystem::Metric), "2k km");
    }

    #[test]
    fn distance_imperial_buckets() {
        assert_eq!(format_distance(0.05, UnitSystem::Imperial), "164 ft");
        assert_eq!(format_distance(5.0, UnitSystem::Imperial), "3.1 mi");
        // 1000 mi → 1k mi (1609.344 km ≈ 1000 mi). Use a clearly large km.
        assert_eq!(format_distance(2_000.0, UnitSystem::Imperial), "1k mi");
    }

    #[test]
    fn temperature_converts() {
        assert_eq!(format_temperature(72.0, UnitSystem::Metric), "22\u{00B0}C");
        assert_eq!(
            format_temperature(72.0, UnitSystem::Imperial),
            "72\u{00B0}F"
        );
    }

    #[test]
    fn wind_speed_with_direction() {
        assert_eq!(
            format_wind_speed(10.0, Some("NW"), UnitSystem::Metric),
            "16 km/h NW"
        );
        assert_eq!(
            format_wind_speed(10.0, None, UnitSystem::Imperial),
            "10 mph"
        );
    }

    #[test]
    fn cardinal_directions_wrap() {
        assert_eq!(cardinal(0.0), "N");
        assert_eq!(cardinal(45.0), "NE");
        assert_eq!(cardinal(90.0), "E");
        assert_eq!(cardinal(180.0), "S");
        assert_eq!(cardinal(350.0), "N"); // wraps
    }

    #[test]
    fn distance_and_bearing_formatted_together() {
        let s = format_distance_and_bearing(2_000_000.0, 45.0, UnitSystem::Metric);
        assert_eq!(s, "2k km NE");
    }

    #[test]
    fn watts_per_distance_label_matches_units() {
        assert_eq!(watts_per_distance_label(UnitSystem::Metric), "W/km");
        assert_eq!(watts_per_distance_label(UnitSystem::Imperial), "W/mi");
    }
}
