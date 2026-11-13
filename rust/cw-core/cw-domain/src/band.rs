//! Band derivation and frequency ranges. Port of `BandUtilities.swift`.

/// Band-related operations. Stateless namespace.
pub struct BandUtilities;

impl BandUtilities {
    /// Band order for sorting (frequency order low to high).
    pub const BAND_ORDER: [&'static str; 14] = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm",
        "Other",
    ];

    /// Bands the user is most likely to operate, in display order.
    pub const STANDARD_BANDS: [&'static str; 13] = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm",
    ];

    /// Approximate top of CW/digital portion of an HF band, in kHz.
    pub fn digital_boundary_khz(band: &str) -> Option<f64> {
        Some(match band {
            "160m" => 1_840.0,
            "80m" => 3_570.0,
            "40m" => 7_070.0,
            "30m" => 10_130.0,
            "20m" => 14_070.0,
            "17m" => 18_095.0,
            "15m" => 21_070.0,
            "12m" => 24_910.0,
            "10m" => 28_070.0,
            "6m" => 50_300.0,
            _ => return None,
        })
    }

    /// Approximate start of SSB/phone portion of an HF band, in kHz.
    pub fn ssb_boundary_khz(band: &str) -> Option<f64> {
        Some(match band {
            "160m" => 1_840.0,
            "80m" => 3_600.0,
            "40m" => 7_125.0,
            "20m" => 14_150.0,
            "17m" => 18_110.0,
            "15m" => 21_200.0,
            "12m" => 24_930.0,
            "10m" => 28_300.0,
            "6m" => 50_100.0,
            _ => return None,
        })
    }

    /// Frequency range (lowMHz, highMHz) for a band, or `None` if unknown.
    pub fn range(band: &str) -> Option<(f64, f64)> {
        Some(match band {
            "160m" => (1.8, 2.0),
            "80m" => (3.5, 4.0),
            "60m" => (5.3, 5.4),
            "40m" => (7.0, 7.3),
            "30m" => (10.1, 10.15),
            "20m" => (14.0, 14.35),
            "17m" => (18.068, 18.168),
            "15m" => (21.0, 21.45),
            "12m" => (24.89, 24.99),
            "10m" => (28.0, 29.7),
            "6m" => (50.0, 54.0),
            "2m" => (144.0, 148.0),
            "70cm" => (420.0, 450.0),
            _ => return None,
        })
    }

    /// Derive the amateur band from a frequency in kHz. Half-open ranges
    /// `[low, high)` exactly mirror the Swift `..<` semantics.
    pub fn derive_band(frequency_khz: Option<f64>) -> Option<&'static str> {
        let mhz = frequency_khz? / 1_000.0;
        Some(match mhz {
            m if (1.8..2.0).contains(&m) => "160m",
            m if (3.5..4.0).contains(&m) => "80m",
            m if (5.3..5.4).contains(&m) => "60m",
            m if (7.0..7.3).contains(&m) => "40m",
            m if (10.1..10.15).contains(&m) => "30m",
            m if (14.0..14.35).contains(&m) => "20m",
            m if (18.068..18.168).contains(&m) => "17m",
            m if (21.0..21.45).contains(&m) => "15m",
            m if (24.89..24.99).contains(&m) => "12m",
            m if (28.0..29.7).contains(&m) => "10m",
            m if (50.0..54.0).contains(&m) => "6m",
            m if (144.0..148.0).contains(&m) => "2m",
            m if (420.0..450.0).contains(&m) => "70cm",
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_band_known() {
        assert_eq!(BandUtilities::derive_band(Some(14_074.0)), Some("20m"));
        assert_eq!(BandUtilities::derive_band(Some(7_040.0)), Some("40m"));
        assert_eq!(BandUtilities::derive_band(Some(28_400.0)), Some("10m"));
    }

    #[test]
    fn derive_band_boundaries_are_half_open() {
        // 2.0 MHz is the exclusive upper edge of 160m and not in 80m.
        assert_eq!(BandUtilities::derive_band(Some(2_000.0)), None);
        // 1.8 MHz is the inclusive lower edge of 160m.
        assert_eq!(BandUtilities::derive_band(Some(1_800.0)), Some("160m"));
    }

    #[test]
    fn derive_band_unknown_and_nil() {
        assert_eq!(BandUtilities::derive_band(Some(9_999.0)), None);
        assert_eq!(BandUtilities::derive_band(None), None);
    }
}
