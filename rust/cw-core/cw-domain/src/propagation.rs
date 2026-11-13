//! Rough HF band-propagation estimator from SFI + K-index + UTC hour.
//! Port of `PropagationEstimator.swift` (rough empirical model, not real
//! ionosonde data — preserves the exact thresholds Swift uses so UI labels
//! stay stable across the language boundary).

use std::f64::consts::PI;

#[derive(Debug, Clone, PartialEq)]
pub struct BandPropagation {
    pub band: String,
    pub quality: PropagationQuality,
    pub muf_estimate_mhz: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[repr(i32)]
pub enum PropagationQuality {
    Closed = 0,
    Poor = 1,
    Fair = 2,
    Good = 3,
    Excellent = 4,
}

impl PropagationQuality {
    pub fn label(self) -> &'static str {
        match self {
            Self::Closed => "Closed",
            Self::Poor => "Poor",
            Self::Fair => "Fair",
            Self::Good => "Good",
            Self::Excellent => "Excellent",
        }
    }
}

struct BandDef {
    name: &'static str,
    center_mhz: f64,
    is_low: bool,
}

const BANDS: &[BandDef] = &[
    BandDef { name: "160m", center_mhz: 1.9, is_low: true },
    BandDef { name: "80m", center_mhz: 3.6, is_low: true },
    BandDef { name: "60m", center_mhz: 5.3, is_low: true },
    BandDef { name: "40m", center_mhz: 7.1, is_low: false },
    BandDef { name: "30m", center_mhz: 10.1, is_low: false },
    BandDef { name: "20m", center_mhz: 14.1, is_low: false },
    BandDef { name: "17m", center_mhz: 18.1, is_low: false },
    BandDef { name: "15m", center_mhz: 21.1, is_low: false },
    BandDef { name: "12m", center_mhz: 24.9, is_low: false },
    BandDef { name: "10m", center_mhz: 28.3, is_low: false },
];

/// Per-band estimates, low-freq → high-freq.
pub fn estimate(sfi: f64, k_index: f64, utc_hour: i32) -> Vec<BandPropagation> {
    let muf = estimate_muf(sfi, k_index, utc_hour);
    BANDS
        .iter()
        .map(|band| {
            let quality = band_quality(band.center_mhz, muf, k_index, utc_hour, band.is_low);
            BandPropagation {
                band: band.name.to_string(),
                quality,
                muf_estimate_mhz: Some(muf),
            }
        })
        .collect()
}

/// Best band for current conditions (`None` if all closed).
pub fn best_band(sfi: f64, k_index: f64, utc_hour: i32) -> Option<BandPropagation> {
    estimate(sfi, k_index, utc_hour)
        .into_iter()
        .max_by_key(|b| b.quality)
}

pub fn sfi_description(sfi: f64) -> &'static str {
    if sfi < 80.0 {
        "Low"
    } else if sfi < 120.0 {
        "Moderate"
    } else if sfi < 180.0 {
        "High"
    } else {
        "Very High"
    }
}

pub fn k_index_description(k_index: f64) -> &'static str {
    if k_index < 2.0 {
        "Quiet"
    } else if k_index < 4.0 {
        "Unsettled"
    } else if k_index < 5.0 {
        "Active"
    } else if k_index < 6.0 {
        "Storm"
    } else {
        "Severe Storm"
    }
}

fn estimate_muf(sfi: f64, k_index: f64, utc_hour: i32) -> f64 {
    // Empirical: SFI 70 → ~14 MHz, SFI 150 → ~21 MHz, SFI 250 → ~28 MHz.
    let base_muf = 1.7 * sfi.sqrt();
    let k_penalty = (k_index - 2.0).max(0.0) * 0.08;
    let k_factor = (1.0 - k_penalty).max(0.5);
    let diurnal = diurnal_multiplier(utc_hour);
    base_muf * k_factor * diurnal
}

fn diurnal_multiplier(utc_hour: i32) -> f64 {
    // Peak at 14 UTC, trough at ~04 UTC.
    let hour = utc_hour as f64;
    let phase = (hour - 14.0) * PI / 12.0;
    0.7 + 0.3 * phase.cos()
}

fn band_quality(
    band_freq_mhz: f64,
    muf: f64,
    k_index: f64,
    utc_hour: i32,
    is_low_band: bool,
) -> PropagationQuality {
    if is_low_band {
        return low_band_quality(band_freq_mhz, k_index, utc_hour);
    }
    let headroom = muf - band_freq_mhz;
    if headroom < -5.0 {
        PropagationQuality::Closed
    } else if headroom < 0.0 {
        PropagationQuality::Poor
    } else if headroom < 5.0 {
        if k_index < 3.0 { PropagationQuality::Fair } else { PropagationQuality::Poor }
    } else if headroom < 15.0 {
        if k_index < 2.0 {
            PropagationQuality::Excellent
        } else if k_index < 4.0 {
            PropagationQuality::Good
        } else {
            PropagationQuality::Fair
        }
    } else if k_index < 3.0 {
        PropagationQuality::Good
    } else {
        PropagationQuality::Fair
    }
}

fn low_band_quality(band_freq_mhz: f64, k_index: f64, utc_hour: i32) -> PropagationQuality {
    let is_night = !(6..=20).contains(&utc_hour);
    if k_index >= 5.0 {
        return PropagationQuality::Poor;
    }
    if is_night {
        if band_freq_mhz < 2.0 {
            // 160m: best at night with low K
            if k_index < 2.0 {
                PropagationQuality::Good
            } else if k_index < 4.0 {
                PropagationQuality::Fair
            } else {
                PropagationQuality::Poor
            }
        } else if k_index < 3.0 {
            PropagationQuality::Good
        } else {
            PropagationQuality::Fair
        }
    } else if band_freq_mhz < 4.0 {
        PropagationQuality::Poor
    } else {
        PropagationQuality::Fair
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn estimate_returns_ten_bands_low_to_high() {
        let bands = estimate(150.0, 1.0, 14);
        assert_eq!(bands.len(), 10);
        assert_eq!(bands[0].band, "160m");
        assert_eq!(bands.last().unwrap().band, "10m");
        // High-SFI midday should open at least one upper band.
        assert!(bands.iter().any(|b| b.quality >= PropagationQuality::Good));
    }

    #[test]
    fn high_k_index_collapses_upper_bands() {
        let bands = estimate(150.0, 7.0, 14);
        // 10m with severe storm should be at most fair.
        let ten = bands.iter().find(|b| b.band == "10m").unwrap();
        assert!(ten.quality <= PropagationQuality::Fair);
    }

    #[test]
    fn night_favors_low_bands() {
        let night = estimate(80.0, 1.0, 2);
        let day = estimate(80.0, 1.0, 14);
        let night_80 = night.iter().find(|b| b.band == "80m").unwrap();
        let day_80 = day.iter().find(|b| b.band == "80m").unwrap();
        assert!(night_80.quality > day_80.quality);
    }

    #[test]
    fn best_band_returns_highest_quality() {
        let best = best_band(180.0, 1.0, 14).unwrap();
        // With SFI 180 + low K + midday, MUF lands somewhere in the upper HF.
        assert!(["10m", "12m", "15m", "17m", "20m"].contains(&best.band.as_str()));
    }

    #[test]
    fn sfi_label_thresholds() {
        assert_eq!(sfi_description(60.0), "Low");
        assert_eq!(sfi_description(100.0), "Moderate");
        assert_eq!(sfi_description(150.0), "High");
        assert_eq!(sfi_description(250.0), "Very High");
    }

    #[test]
    fn k_label_thresholds() {
        assert_eq!(k_index_description(0.5), "Quiet");
        assert_eq!(k_index_description(3.0), "Unsettled");
        assert_eq!(k_index_description(4.0), "Active");
        assert_eq!(k_index_description(5.0), "Storm");
        assert_eq!(k_index_description(7.0), "Severe Storm");
    }

    #[test]
    fn quality_is_ordered() {
        assert!(PropagationQuality::Closed < PropagationQuality::Poor);
        assert!(PropagationQuality::Poor < PropagationQuality::Good);
        assert!(PropagationQuality::Good < PropagationQuality::Excellent);
    }
}
