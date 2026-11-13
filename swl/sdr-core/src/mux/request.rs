use crate::types::{CapturePriority, DemodMode, FrequencyRange, SdrId};

/// A request for capture bandwidth from a consumer.
#[derive(Debug, Clone)]
pub struct CaptureRequest {
    /// Which SDR to use (or None for auto-assignment).
    pub sdr_id: Option<SdrId>,
    /// Center frequency in Hz.
    pub frequency: u64,
    /// Bandwidth needed in Hz.
    pub bandwidth: u32,
    /// Priority level.
    pub priority: CapturePriority,
    /// Demodulation mode (for informational purposes at mux level).
    pub mode: DemodMode,
}

impl CaptureRequest {
    /// The frequency range this request covers.
    pub fn frequency_range(&self) -> FrequencyRange {
        FrequencyRange::from_center_bandwidth(self.frequency, self.bandwidth)
    }
}

/// Result of checking if two capture requests can be merged into a single
/// SDR tuning.
#[derive(Debug, Clone)]
pub enum MergeResult {
    /// The requests can be merged. The merged range is returned.
    Merged(MergedCapture),
    /// The requests cannot be merged (disjoint bands or incompatible SDRs).
    Conflict,
}

/// A merged capture configuration that satisfies multiple requests.
#[derive(Debug, Clone)]
pub struct MergedCapture {
    /// The frequency range that covers all merged requests.
    pub range: FrequencyRange,
    /// Required sample rate to cover the merged bandwidth.
    pub sample_rate: u32,
}

/// Check if two requests targeting the same SDR can share a single capture.
///
/// They can merge if their frequency ranges overlap or are close enough
/// that a single SDR tuning can cover both.
pub fn check_merge(a: &CaptureRequest, b: &CaptureRequest, max_sdr_bandwidth: u32) -> MergeResult {
    let range_a = a.frequency_range();
    let range_b = b.frequency_range();

    // Try to merge ranges
    let merged_range = if let Some(merged) = range_a.merge(&range_b) {
        merged
    } else {
        // Not overlapping or adjacent — check if they fit within max bandwidth
        let combined =
            FrequencyRange::new(range_a.low.min(range_b.low), range_a.high.max(range_b.high));
        if combined.bandwidth() <= u64::from(max_sdr_bandwidth) {
            combined
        } else {
            return MergeResult::Conflict;
        }
    };

    // Check the merged range fits within SDR capabilities
    if merged_range.bandwidth() > u64::from(max_sdr_bandwidth) {
        return MergeResult::Conflict;
    }

    // Sample rate must be at least the merged bandwidth (Nyquist)
    // Round up to a reasonable sample rate
    let sample_rate = pick_sample_rate(merged_range.bandwidth() as u32);

    MergeResult::Merged(MergedCapture {
        range: merged_range,
        sample_rate,
    })
}

/// Pick a practical sample rate that's >= the required bandwidth.
pub fn pick_sample_rate(bandwidth: u32) -> u32 {
    // Common SDR sample rates
    const RATES: &[u32] = &[
        48_000, 96_000, 192_000, 240_000, 500_000, 1_000_000, 2_000_000, 2_400_000, 3_200_000,
    ];
    for &rate in RATES {
        if rate >= bandwidth {
            return rate;
        }
    }
    // If bandwidth exceeds all presets, use bandwidth directly
    bandwidth
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_request(freq: u64, bw: u32) -> CaptureRequest {
        CaptureRequest {
            sdr_id: None,
            frequency: freq,
            bandwidth: bw,
            priority: CapturePriority::Recording,
            mode: DemodMode::Cw,
        }
    }

    #[test]
    fn merge_overlapping_requests() {
        let a = make_request(7_030_000, 2_400);
        let b = make_request(7_035_000, 2_400);

        match check_merge(&a, &b, 240_000) {
            MergeResult::Merged(merged) => {
                // a covers 7028800-7031200, b covers 7033800-7036200
                // Gap of ~2600 Hz but within 240kHz SDR bandwidth
                assert!(merged.range.contains(&a.frequency_range()));
                assert!(merged.range.contains(&b.frequency_range()));
            }
            MergeResult::Conflict => panic!("expected merge"),
        }
    }

    #[test]
    fn merge_identical_requests() {
        let a = make_request(7_030_000, 2_400);
        let b = make_request(7_030_000, 2_400);

        match check_merge(&a, &b, 240_000) {
            MergeResult::Merged(merged) => {
                assert_eq!(merged.range.bandwidth(), 2_400);
            }
            MergeResult::Conflict => panic!("expected merge"),
        }
    }

    #[test]
    fn conflict_different_bands() {
        let a = make_request(7_030_000, 2_400);
        let b = make_request(14_035_000, 2_400);

        match check_merge(&a, &b, 2_400_000) {
            MergeResult::Conflict => {} // expected
            MergeResult::Merged(_) => panic!("expected conflict"),
        }
    }

    #[test]
    fn conflict_exceeds_max_bandwidth() {
        let a = make_request(7_000_000, 2_400);
        let b = make_request(7_200_000, 2_400);

        // 200kHz apart, but max_sdr_bandwidth is only 48kHz
        match check_merge(&a, &b, 48_000) {
            MergeResult::Conflict => {} // expected
            MergeResult::Merged(_) => panic!("expected conflict"),
        }
    }

    #[test]
    fn merge_within_gap() {
        // Two requests with a gap, but within SDR bandwidth
        let a = make_request(7_020_000, 2_400);
        let b = make_request(7_040_000, 2_400);

        // 20kHz apart, fits in 240kHz SDR
        match check_merge(&a, &b, 240_000) {
            MergeResult::Merged(merged) => {
                assert!(merged.range.contains(&a.frequency_range()));
                assert!(merged.range.contains(&b.frequency_range()));
            }
            MergeResult::Conflict => panic!("expected merge"),
        }
    }

    #[test]
    fn pick_sample_rate_picks_ceiling() {
        assert_eq!(pick_sample_rate(2_400), 48_000);
        assert_eq!(pick_sample_rate(48_000), 48_000);
        assert_eq!(pick_sample_rate(50_000), 96_000);
        assert_eq!(pick_sample_rate(240_000), 240_000);
        assert_eq!(pick_sample_rate(300_000), 500_000);
    }
}
