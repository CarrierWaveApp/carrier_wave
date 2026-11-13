//! Timeline replay curves + RBN spotter helpers. Port of the playback math in
//! iOS `TimelineMapView` (spotOpacity/spotDecayFraction/snrCircleSize) and the
//! SNR color banding in `SpotsMiniMapView.snrColor`, plus
//! `TimelineMapDataActor.stripSkimmerSuffix`. Pure functions so both
//! platforms render replay identically.

/// Spots render at full opacity for this many seconds…
pub const SPOT_FADE_START_SECS: f64 = 300.0;
/// …then fade linearly to zero at this age.
pub const SPOT_FADE_END_SECS: f64 = 600.0;

pub fn spot_opacity(age_secs: f64) -> f64 {
    if age_secs < SPOT_FADE_START_SECS {
        return 1.0;
    }
    if age_secs >= SPOT_FADE_END_SECS {
        return 0.0;
    }
    1.0 - (age_secs - SPOT_FADE_START_SECS) / (SPOT_FADE_END_SECS - SPOT_FADE_START_SECS)
}

/// 1.0 at birth decaying to 0.3 at the 10-minute limit.
pub fn spot_decay_fraction(age_secs: f64) -> f64 {
    let fraction = (age_secs / SPOT_FADE_END_SECS).min(1.0);
    1.0 - 0.7 * fraction
}

/// SNR (typically 0–40 dB) → marker diameter in points (10–36).
pub fn snr_marker_size(snr: Option<i64>) -> f64 {
    let Some(snr) = snr else { return 10.0 };
    let clamped = snr.clamp(0, 40) as f64;
    10.0 + 26.0 * (clamped / 40.0)
}

/// SNR → color band index: 0 red (<5), 1 orange (5..15), 2 blue (15..25),
/// 3 green (>=25). Clients map indices to platform colors.
pub fn snr_color_band(snr: i64) -> u8 {
    match snr {
        s if s >= 25 => 3,
        s if s >= 15 => 2,
        s if s >= 5 => 1,
        _ => 0,
    }
}

/// Strip an RBN skimmer suffix: everything from the last `-`.
pub fn strip_skimmer_suffix(callsign: &str) -> &str {
    match callsign.rfind('-') {
        Some(idx) => &callsign[..idx],
        None => callsign,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Pinning tests: values captured from TimelineMapView.swift:212-242 and
    // SpotsMiniMapView.swift:108-115 before deletion.
    #[test]
    fn opacity_is_full_then_fades_linearly() {
        assert_eq!(spot_opacity(0.0), 1.0);
        assert_eq!(spot_opacity(299.9), 1.0);
        assert!((spot_opacity(450.0) - 0.5).abs() < 1e-9);
        assert_eq!(spot_opacity(600.0), 0.0);
        assert_eq!(spot_opacity(10_000.0), 0.0);
    }

    #[test]
    fn decay_fraction_reaches_point_three() {
        assert_eq!(spot_decay_fraction(0.0), 1.0);
        assert!((spot_decay_fraction(300.0) - 0.65).abs() < 1e-9);
        assert!((spot_decay_fraction(600.0) - 0.3).abs() < 1e-9);
        assert!((spot_decay_fraction(1200.0) - 0.3).abs() < 1e-9);
    }

    #[test]
    fn snr_size_clamps_0_to_40() {
        assert_eq!(snr_marker_size(None), 10.0);
        assert_eq!(snr_marker_size(Some(-5)), 10.0);
        assert!((snr_marker_size(Some(20)) - 23.0).abs() < 1e-9);
        assert_eq!(snr_marker_size(Some(40)), 36.0);
        assert_eq!(snr_marker_size(Some(99)), 36.0);
    }

    #[test]
    fn snr_bands() {
        assert_eq!(snr_color_band(-3), 0);
        assert_eq!(snr_color_band(5), 1);
        assert_eq!(snr_color_band(15), 2);
        assert_eq!(snr_color_band(24), 2);
        assert_eq!(snr_color_band(25), 3);
    }

    #[test]
    fn skimmer_suffix_strips_last_dash() {
        assert_eq!(strip_skimmer_suffix("KM3T-#"), "KM3T");
        assert_eq!(strip_skimmer_suffix("W3LPL-1"), "W3LPL");
        assert_eq!(strip_skimmer_suffix("N4ZR"), "N4ZR");
    }
}
