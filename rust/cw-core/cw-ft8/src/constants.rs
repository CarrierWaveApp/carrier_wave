//! FT8 timing/tone constants + dial frequencies. Port of `FT8Constants.swift`.

pub struct Ft8Constants;

impl Ft8Constants {
    /// Duration of one FT8 time slot in seconds.
    pub const SLOT_DURATION: f64 = 15.0;
    /// Duration of one symbol period in seconds.
    pub const SYMBOL_PERIOD: f64 = 0.160;
    /// Frequency spacing between adjacent tones in Hz.
    pub const TONE_SPACING: f64 = 6.25;
    /// Number of distinct tones used (8-FSK).
    pub const TONE_COUNT: i32 = 8;
    /// Total number of symbols per FT8 transmission.
    pub const TOTAL_SYMBOLS: i32 = 79;
    /// Audio sample rate in Hz.
    pub const SAMPLE_RATE: i32 = 12_000;

    /// Actual transmission duration in seconds (79 × 0.160).
    pub fn tx_duration() -> f64 {
        Self::TOTAL_SYMBOLS as f64 * Self::SYMBOL_PERIOD
    }

    /// Number of audio samples in one 15-second slot.
    pub fn samples_per_slot() -> i32 {
        Self::SAMPLE_RATE * Self::SLOT_DURATION as i32
    }

    /// Bands in ascending frequency order.
    pub const SUPPORTED_BANDS: [&'static str; 13] = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm",
    ];

    /// Standard FT8 dial frequency (MHz) for a band, or `None`.
    pub fn dial_frequency(band: &str) -> Option<f64> {
        Some(match band {
            "160m" => 1.840,
            "80m" => 3.573,
            "60m" => 5.357,
            "40m" => 7.074,
            "30m" => 10.136,
            "20m" => 14.074,
            "17m" => 18.100,
            "15m" => 21.074,
            "12m" => 24.915,
            "10m" => 28.074,
            "6m" => 50.313,
            "2m" => 144.174,
            "70cm" => 432.174,
            _ => return None,
        })
    }

    /// Echo back the band only if it is a supported FT8 band.
    pub fn resolve_band(band: Option<&str>) -> Option<String> {
        let band = band?;
        if Self::SUPPORTED_BANDS.contains(&band) {
            Some(band.to_string())
        } else {
            None
        }
    }

    /// Band name for a given dial frequency in MHz (first within 0.001 MHz).
    pub fn band_for_dial_frequency(frequency: f64) -> Option<&'static str> {
        let tolerance = 0.001;
        for band in Self::SUPPORTED_BANDS {
            if let Some(dial) = Self::dial_frequency(band) {
                if (dial - frequency).abs() < tolerance {
                    return Some(band);
                }
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derived_constants() {
        assert_eq!(Ft8Constants::samples_per_slot(), 180_000);
        assert!((Ft8Constants::tx_duration() - 12.64).abs() < 1e-9);
    }

    #[test]
    fn dial_frequencies_round_trip() {
        assert_eq!(Ft8Constants::dial_frequency("20m"), Some(14.074));
        assert_eq!(Ft8Constants::band_for_dial_frequency(14.074), Some("20m"));
        assert_eq!(Ft8Constants::band_for_dial_frequency(14.0), None);
        assert_eq!(Ft8Constants::dial_frequency("11m"), None);
    }

    #[test]
    fn resolve_band_filters() {
        assert_eq!(Ft8Constants::resolve_band(Some("20m")), Some("20m".to_string()));
        assert_eq!(Ft8Constants::resolve_band(Some("11m")), None);
        assert_eq!(Ft8Constants::resolve_band(None), None);
    }
}
