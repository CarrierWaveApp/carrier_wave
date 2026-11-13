//! Band edge frequency definitions for band map rendering and the
//! mode-guess heuristic. Port of Sweep's `BandEdges.swift`.
//!
//! Distinct from [`crate::band::BandUtilities`]: these ranges are
//! **inclusive** on both ends, cover only the 11 HF/6m map bands, and 60m
//! spans 5330–5405 kHz (the channelized allocation, not the 5.3–5.4 MHz
//! utility range).

/// A single band's edge definition.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BandEdge {
    pub id: &'static str,
    pub lower_khz: f64,
    pub upper_khz: f64,
}

impl BandEdge {
    /// CW/digital boundary (approximate).
    pub fn digital_boundary_khz(&self) -> Option<f64> {
        Some(match self.id {
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

    /// SSB boundary (approximate). 30m is CW/digital only.
    pub fn ssb_boundary_khz(&self) -> Option<f64> {
        Some(match self.id {
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

    pub fn width_khz(&self) -> f64 {
        self.upper_khz - self.lower_khz
    }
}

/// The HF + 6m band map, in ascending frequency order.
pub const HF_BANDS: [BandEdge; 11] = [
    BandEdge { id: "160m", lower_khz: 1_800.0, upper_khz: 2_000.0 },
    BandEdge { id: "80m", lower_khz: 3_500.0, upper_khz: 4_000.0 },
    BandEdge { id: "60m", lower_khz: 5_330.0, upper_khz: 5_405.0 },
    BandEdge { id: "40m", lower_khz: 7_000.0, upper_khz: 7_300.0 },
    BandEdge { id: "30m", lower_khz: 10_100.0, upper_khz: 10_150.0 },
    BandEdge { id: "20m", lower_khz: 14_000.0, upper_khz: 14_350.0 },
    BandEdge { id: "17m", lower_khz: 18_068.0, upper_khz: 18_168.0 },
    BandEdge { id: "15m", lower_khz: 21_000.0, upper_khz: 21_450.0 },
    BandEdge { id: "12m", lower_khz: 24_890.0, upper_khz: 24_990.0 },
    BandEdge { id: "10m", lower_khz: 28_000.0, upper_khz: 29_700.0 },
    BandEdge { id: "6m", lower_khz: 50_000.0, upper_khz: 54_000.0 },
];

/// Find the band edge containing a frequency in kHz (inclusive bounds).
pub fn band_for(frequency_khz: f64) -> Option<&'static BandEdge> {
    HF_BANDS
        .iter()
        .find(|edge| frequency_khz >= edge.lower_khz && frequency_khz <= edge.upper_khz)
}

/// Convert a frequency to an x-position within a band (0.0 to 1.0, clamped).
pub fn x_position(frequency_khz: f64, edge: &BandEdge) -> f64 {
    let clamped = frequency_khz.clamp(edge.lower_khz, edge.upper_khz);
    (clamped - edge.lower_khz) / edge.width_khz()
}

/// Convert an x-position (0.0 to 1.0) back to a frequency within a band.
pub fn frequency_at(x_position: f64, edge: &BandEdge) -> f64 {
    edge.lower_khz + x_position * edge.width_khz()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn band_for_is_inclusive_both_ends() {
        assert_eq!(band_for(1_800.0).unwrap().id, "160m");
        assert_eq!(band_for(2_000.0).unwrap().id, "160m");
        assert_eq!(band_for(5_405.0).unwrap().id, "60m");
        assert!(band_for(2_500.0).is_none());
        // 2m is deliberately absent from the band map.
        assert!(band_for(145_000.0).is_none());
    }

    #[test]
    fn x_position_clamps_and_round_trips() {
        let edge = band_for(14_175.0).unwrap();
        assert_eq!(x_position(14_000.0, edge), 0.0);
        assert_eq!(x_position(14_350.0, edge), 1.0);
        assert_eq!(x_position(13_000.0, edge), 0.0);
        let x = x_position(14_175.0, edge);
        assert!((frequency_at(x, edge) - 14_175.0).abs() < 1e-9);
    }
}
