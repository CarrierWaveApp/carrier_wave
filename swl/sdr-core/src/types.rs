use num_complex::Complex;
use serde::{Deserialize, Serialize};
use std::fmt;
use std::sync::Arc;

/// A single IQ sample (32-bit float complex).
pub type IqSample = Complex<f32>;

/// A timestamped buffer of IQ samples from an SDR.
#[derive(Debug, Clone)]
pub struct TimestampedIqBuffer {
    /// UTC timestamp of the first sample in this buffer.
    pub timestamp: chrono::DateTime<chrono::Utc>,
    /// The center frequency this buffer was captured at (Hz).
    pub center_frequency: u64,
    /// The sample rate (samples/sec).
    pub sample_rate: u32,
    /// The IQ samples.
    pub samples: Arc<Vec<IqSample>>,
}

/// A frequency range in Hz, used for capture requests and SDR tuning.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct FrequencyRange {
    /// Lower bound in Hz (inclusive).
    pub low: u64,
    /// Upper bound in Hz (inclusive).
    pub high: u64,
}

impl FrequencyRange {
    /// Create a new frequency range from center frequency and bandwidth.
    pub fn from_center_bandwidth(center: u64, bandwidth: u32) -> Self {
        let half = u64::from(bandwidth) / 2;
        Self {
            low: center.saturating_sub(half),
            high: center + half,
        }
    }

    /// Create a new frequency range from low and high bounds.
    pub fn new(low: u64, high: u64) -> Self {
        assert!(low <= high, "low ({low}) must be <= high ({high})");
        Self { low, high }
    }

    /// Bandwidth in Hz.
    pub fn bandwidth(&self) -> u64 {
        self.high - self.low
    }

    /// Center frequency in Hz.
    pub fn center(&self) -> u64 {
        (self.low + self.high) / 2
    }

    /// Check if this range fully contains another range.
    pub fn contains(&self, other: &FrequencyRange) -> bool {
        self.low <= other.low && self.high >= other.high
    }

    /// Check if this range overlaps with another range.
    pub fn overlaps(&self, other: &FrequencyRange) -> bool {
        self.low <= other.high && other.low <= self.high
    }

    /// Check if this range is adjacent to another (touching but not overlapping).
    pub fn adjacent(&self, other: &FrequencyRange) -> bool {
        self.high + 1 == other.low || other.high + 1 == self.low
    }

    /// Merge two ranges into the smallest range covering both.
    /// Returns None if ranges are not overlapping or adjacent.
    pub fn merge(&self, other: &FrequencyRange) -> Option<FrequencyRange> {
        if self.overlaps(other) || self.adjacent(other) {
            Some(FrequencyRange {
                low: self.low.min(other.low),
                high: self.high.max(other.high),
            })
        } else {
            None
        }
    }

    /// Check if a single frequency (Hz) falls within this range.
    pub fn contains_frequency(&self, freq: u64) -> bool {
        freq >= self.low && freq <= self.high
    }
}

impl fmt::Display for FrequencyRange {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}-{} Hz", self.low, self.high)
    }
}

/// Demodulation mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DemodMode {
    Cw,
    Usb,
    Lsb,
    Am,
}

impl fmt::Display for DemodMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DemodMode::Cw => write!(f, "CW"),
            DemodMode::Usb => write!(f, "USB"),
            DemodMode::Lsb => write!(f, "LSB"),
            DemodMode::Am => write!(f, "AM"),
        }
    }
}

/// Priority level for capture requests.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum CapturePriority {
    /// Lowest priority — background monitoring.
    Background = 0,
    /// Medium priority — live streaming.
    Stream = 1,
    /// Highest priority — active recording.
    Recording = 2,
}

/// Gain setting for an SDR.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GainSetting {
    #[default]
    Auto,
    Manual(f64),
}

/// Unique identifier for a discovered SDR device.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct SdrId(pub String);

impl fmt::Display for SdrId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for SdrId {
    fn from(s: String) -> Self {
        SdrId(s)
    }
}

impl From<&str> for SdrId {
    fn from(s: &str) -> Self {
        SdrId(s.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frequency_range_from_center_bandwidth() {
        let range = FrequencyRange::from_center_bandwidth(7_030_000, 2_400);
        assert_eq!(range.low, 7_028_800);
        assert_eq!(range.high, 7_031_200);
        assert_eq!(range.bandwidth(), 2_400);
        assert_eq!(range.center(), 7_030_000);
    }

    #[test]
    fn frequency_range_contains() {
        let wide = FrequencyRange::new(7_000_000, 7_100_000);
        let narrow = FrequencyRange::new(7_028_800, 7_031_200);

        assert!(wide.contains(&narrow));
        assert!(!narrow.contains(&wide));
        assert!(wide.contains(&wide));
    }

    #[test]
    fn frequency_range_overlaps() {
        let a = FrequencyRange::new(7_000_000, 7_050_000);
        let b = FrequencyRange::new(7_030_000, 7_080_000);
        let c = FrequencyRange::new(7_060_000, 7_100_000);

        assert!(a.overlaps(&b));
        assert!(b.overlaps(&a));
        assert!(!a.overlaps(&c));
        assert!(b.overlaps(&c));
    }

    #[test]
    fn frequency_range_adjacent() {
        let a = FrequencyRange::new(7_000_000, 7_050_000);
        let b = FrequencyRange::new(7_050_001, 7_100_000);
        let c = FrequencyRange::new(7_060_000, 7_100_000);

        assert!(a.adjacent(&b));
        assert!(b.adjacent(&a));
        assert!(!a.adjacent(&c));
    }

    #[test]
    fn frequency_range_merge_overlapping() {
        let a = FrequencyRange::new(7_000_000, 7_050_000);
        let b = FrequencyRange::new(7_030_000, 7_080_000);

        let merged = a.merge(&b).unwrap();
        assert_eq!(merged.low, 7_000_000);
        assert_eq!(merged.high, 7_080_000);
    }

    #[test]
    fn frequency_range_merge_adjacent() {
        let a = FrequencyRange::new(7_000_000, 7_050_000);
        let b = FrequencyRange::new(7_050_001, 7_100_000);

        let merged = a.merge(&b).unwrap();
        assert_eq!(merged.low, 7_000_000);
        assert_eq!(merged.high, 7_100_000);
    }

    #[test]
    fn frequency_range_merge_disjoint() {
        let a = FrequencyRange::new(7_000_000, 7_050_000);
        let c = FrequencyRange::new(14_000_000, 14_050_000);

        assert!(a.merge(&c).is_none());
    }

    #[test]
    fn frequency_range_contains_frequency() {
        let range = FrequencyRange::new(7_000_000, 7_100_000);

        assert!(range.contains_frequency(7_000_000));
        assert!(range.contains_frequency(7_050_000));
        assert!(range.contains_frequency(7_100_000));
        assert!(!range.contains_frequency(6_999_999));
        assert!(!range.contains_frequency(7_100_001));
    }

    #[test]
    fn demod_mode_serde_roundtrip() {
        let json = serde_json::to_string(&DemodMode::Cw).unwrap();
        assert_eq!(json, "\"cw\"");
        let parsed: DemodMode = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, DemodMode::Cw);
    }
}
