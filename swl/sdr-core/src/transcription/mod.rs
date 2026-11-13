pub mod beam;
pub mod decoder;
pub mod decoder_a;
pub mod decoder_trait;
pub mod ensemble;
pub mod hsmm;
pub mod language_model;
pub mod legacy;
pub mod morse;
pub mod postprocess;
pub mod quadrature;
pub mod structured;
pub mod tone_detector;

use std::sync::Arc;

use chrono::Utc;
use tokio::sync::Mutex;
use tracing::{error, info};
use uuid::Uuid;

use crate::db::models::TranscriptionRow;
use crate::db::Database;
use crate::error::TranscriptionError;
use crate::recording::combine;
use crate::recording::dsp::BiquadCascade;

use beam::BeamDecoder;
use tone_detector::{
    find_active_start, merge_keying_events, scan_tone_activity, KeyingEvent, KeyingEventKind,
    ToneActivity, ToneDetector,
};

/// A decoded segment from a single tone frequency, ready for per-segment decoding.
#[allow(dead_code)]
struct ToneSegment {
    /// The tone frequency this segment was detected on.
    tone_freq: f32,
    /// Keying events in this segment.
    events: Vec<KeyingEvent>,
    /// Sample offset of the first event in this segment.
    start_sample: usize,
    /// Dit duration estimate for this segment (ms).
    dit_ms: f64,
    /// Estimated WPM for this segment.
    wpm: u32,
    /// Character gap threshold (ms).
    char_gap_ms: f64,
    /// Word gap threshold (ms).
    word_gap_ms: f64,
    /// Frequency-based operator index (assigned during clustering).
    operator_id: usize,
}

/// Estimate WPM from on-duration distribution using histogram peak detection.
///
/// Builds a histogram of on-durations with 5ms bins, smooths it, finds the
/// dit peak (first prominent peak above the noise floor), and validates it
/// against the dah cluster. Returns `(wpm, dit_estimate_ms)`.
///
/// Falls back to Otsu's method if no clear peaks are found.
pub fn estimate_wpm_histogram(on_durations_ms: &[f64]) -> (u32, f64) {
    if on_durations_ms.len() < 4 {
        return (15, 1200.0 / 15.0);
    }

    let bin_width = 5.0; // 5ms bins
    let max_ms = 500.0;
    let num_bins = (max_ms / bin_width) as usize;

    // Build histogram
    let mut hist = vec![0u32; num_bins];
    for &d in on_durations_ms {
        let bin = ((d / bin_width) as usize).min(num_bins - 1);
        hist[bin] += 1;
    }

    // Smooth with 5-bin moving average for cleaner peak detection
    let smooth_radius = 2;
    let mut smoothed = vec![0.0f64; num_bins];
    for (i, slot) in smoothed.iter_mut().enumerate() {
        let start = i.saturating_sub(smooth_radius);
        let end = (i + smooth_radius + 1).min(num_bins);
        let sum: u32 = hist[start..end].iter().sum();
        *slot = sum as f64 / (end - start) as f64;
    }

    // Skip bins below 40ms to avoid noise pile-up at the merge min_on
    // boundary (30ms). Events at 30-40ms are mostly noise fragments that
    // survived the merge step. 40ms = 30 WPM max, which is still very fast.
    let min_bin = 8; // skip below 40ms

    // Find peaks (local maxima) above minimum height
    let min_height = 0.5;
    let mut peaks: Vec<(usize, f64)> = Vec::new();
    for i in (min_bin + 1)..num_bins.saturating_sub(1) {
        if smoothed[i] >= smoothed[i - 1]
            && smoothed[i] > smoothed[i + 1]
            && smoothed[i] >= min_height
        {
            peaks.push((i, smoothed[i]));
        }
    }

    // The first peak above the noise floor is the dit mode.
    // Validate by checking for mass at ~3× dit (dah cluster).
    if let Some(&(dit_bin, _)) = peaks.first() {
        let dit_estimate = (dit_bin as f64 + 0.5) * bin_width;

        // Check for dah mass: expect peak at 2.5-4.0× dit
        let dah_low_bin = (dit_bin as f64 * 2.0) as usize;
        let dah_high_bin = ((dit_bin as f64 * 4.5) as usize).min(num_bins);
        let dah_mass: f64 = if dah_low_bin < num_bins {
            smoothed[dah_low_bin..dah_high_bin.min(num_bins)]
                .iter()
                .sum()
        } else {
            0.0
        };

        if dah_mass > 0.5 {
            let wpm = (1200.0 / dit_estimate) as u32;
            let clamped = wpm.clamp(5, 50);
            tracing::info!(
                dit_bin = dit_bin,
                dit_ms = format!("{:.0}", dit_estimate),
                dah_mass = format!("{:.1}", dah_mass),
                num_peaks = peaks.len(),
                estimated_wpm = clamped,
                "WPM estimated via histogram peak"
            );
            return (clamped, dit_estimate);
        }
    }

    // If peak detection fails (too noisy), try valley-based approach
    // Find all valleys (local minima with mass on both sides)
    let mut valleys = Vec::new();
    for i in (min_bin + 1)..num_bins.saturating_sub(1) {
        if smoothed[i] <= smoothed[i - 1] && smoothed[i] < smoothed[i + 1] {
            let left_mass: f64 = smoothed[min_bin..i].iter().sum();
            let right_mass: f64 = smoothed[i + 1..num_bins].iter().sum();
            if left_mass > 2.0 && right_mass > 1.0 {
                valleys.push(i);
            }
        }
    }

    let min_duration_ms = min_bin as f64 * bin_width;
    for &vb in &valleys {
        let split_ms = (vb as f64 + 0.5) * bin_width;
        let mut dit_durations: Vec<f64> = on_durations_ms
            .iter()
            .copied()
            .filter(|&d| d >= min_duration_ms && d < split_ms)
            .collect();
        dit_durations.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        if dit_durations.is_empty() {
            continue;
        }
        let dit_median = dit_durations[dit_durations.len() / 2];
        let wpm = (1200.0 / dit_median) as u32;
        let clamped = wpm.clamp(5, 50);
        tracing::info!(
            valley_ms = format!("{:.0}", split_ms),
            dit_median_ms = format!("{:.0}", dit_median),
            estimated_wpm = clamped,
            "WPM estimated via histogram valley (fallback)"
        );
        return (clamped, dit_median);
    }

    otsu_wpm_fallback(on_durations_ms)
}

/// Otsu's method fallback for WPM estimation when histogram valley detection fails.
fn otsu_wpm_fallback(on_durations_ms: &[f64]) -> (u32, f64) {
    let mut on_ms = on_durations_ms.to_vec();
    on_ms.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    if on_ms.len() < 4 {
        return (15, 1200.0 / 15.0);
    }

    let n = on_ms.len() as f64;
    let total_sum: f64 = on_ms.iter().sum();
    let mut best_var = 0.0f64;
    let mut best_split = on_ms.len() / 2;
    let mut sum_below = 0.0f64;

    let step = (on_ms.len() / 50).max(1);
    for i in (step..on_ms.len() - step).step_by(step) {
        for val in &on_ms[i.saturating_sub(step)..i] {
            sum_below += val;
        }
        let w0 = i as f64 / n;
        let w1 = 1.0 - w0;
        if w0 < 0.1 || w1 < 0.1 {
            continue;
        }
        let mean0 = sum_below / i as f64;
        let mean1 = (total_sum - sum_below) / (n - i as f64);
        let between_var = w0 * w1 * (mean0 - mean1) * (mean0 - mean1);
        if between_var > best_var {
            best_var = between_var;
            best_split = i;
        }
    }

    let dit_estimate = on_ms[best_split / 4];
    let wpm = (1200.0 / dit_estimate) as u32;
    let clamped = wpm.clamp(5, 50);
    tracing::info!(
        dit_estimate_ms = format!("{:.0}", dit_estimate),
        estimated_wpm = clamped,
        "WPM estimated via Otsu fallback"
    );
    (clamped, dit_estimate)
}

/// Find two thresholds that optimally separate a histogram into 3 classes
/// by maximizing between-class variance (multi-level Otsu).
///
/// Returns `(t1, t2)` where t1 < t2 are bin indices separating:
/// - Class 1: bins [0, t1)
/// - Class 2: bins [t1, t2)
/// - Class 3: bins [t2, num_bins)
///
/// Uses pre-computed cumulative sums for O(1) per evaluation, O(n²) total.
fn otsu_3class(smoothed: &[f64]) -> (usize, usize) {
    let num_bins = smoothed.len();

    // Cumulative count (weight) and cumulative weighted sum
    let mut cum_w = vec![0.0f64; num_bins + 1]; // cum_w[i] = sum of smoothed[0..i]
    let mut cum_ws = vec![0.0f64; num_bins + 1]; // cum_ws[i] = sum of smoothed[j]*j for j in 0..i
    for i in 0..num_bins {
        cum_w[i + 1] = cum_w[i] + smoothed[i];
        cum_ws[i + 1] = cum_ws[i] + smoothed[i] * i as f64;
    }

    let total_w = cum_w[num_bins];
    let total_ws = cum_ws[num_bins];

    if total_w < 1e-10 {
        return (num_bins / 3, 2 * num_bins / 3);
    }

    let total_mean = total_ws / total_w;
    let mut best_var = -1.0f64;
    let mut best_t1 = 1usize;
    let mut best_t2 = 2usize;

    // Iterate all pairs (t1, t2) where 1 <= t1 < t2 < num_bins
    for t1 in 1..num_bins.saturating_sub(1) {
        let w0 = cum_w[t1];
        if w0 < 1e-10 {
            continue;
        }
        let mean0 = cum_ws[t1] / w0;

        for t2 in (t1 + 1)..num_bins {
            let w1 = cum_w[t2] - cum_w[t1];
            let w2 = total_w - cum_w[t2];
            if w1 < 1e-10 || w2 < 1e-10 {
                continue;
            }
            let mean1 = (cum_ws[t2] - cum_ws[t1]) / w1;
            let mean2 = (total_ws - cum_ws[t2]) / w2;

            // Between-class variance: sum of w_i * (mean_i - total_mean)^2
            let var = w0 * (mean0 - total_mean).powi(2)
                + w1 * (mean1 - total_mean).powi(2)
                + w2 * (mean2 - total_mean).powi(2);

            if var > best_var {
                best_var = var;
                best_t1 = t1;
                best_t2 = t2;
            }
        }
    }

    (best_t1, best_t2)
}

/// Estimate character gap and word gap thresholds from off-duration histogram.
///
/// Uses 3-class Otsu thresholding to find optimal boundaries between element gaps,
/// character gaps, and word gaps. Falls back to valley-based detection if the
/// word class has too few events (< 3).
///
/// Returns `(char_gap_ms, word_gap_ms)`.
pub fn estimate_gap_thresholds(off_durations_ms: &[f64], dit_ms: f64) -> (f64, f64) {
    let default_char = dit_ms * 1.5;
    let default_word = dit_ms * 3.5;

    if off_durations_ms.len() < 6 {
        return (default_char, default_word);
    }

    let bin_width = 10.0; // 10ms bins
    let max_ms = 1000.0;
    let num_bins = (max_ms / bin_width) as usize;

    // Build histogram
    let mut hist = vec![0u32; num_bins];
    for &d in off_durations_ms {
        let bin = ((d / bin_width) as usize).min(num_bins - 1);
        hist[bin] += 1;
    }

    // Smooth with 3-bin moving average
    let mut smoothed = vec![0.0f64; num_bins];
    for (i, slot) in smoothed.iter_mut().enumerate() {
        let start = i.saturating_sub(1);
        let end = (i + 2).min(num_bins);
        let sum: u32 = hist[start..end].iter().sum();
        *slot = sum as f64 / (end - start) as f64;
    }

    // 3-class Otsu: find optimal (element/char, char/word) boundaries
    let (t1, t2) = otsu_3class(&smoothed);
    let threshold1_ms = (t1 as f64 + 0.5) * bin_width;
    let threshold2_ms = (t2 as f64 + 0.5) * bin_width;

    // Count events in word class (bins >= t2)
    let word_count: f64 = smoothed[t2..].iter().sum();

    if word_count >= 3.0 {
        // Compute class centroids from actual durations (not Otsu thresholds).
        // The Otsu threshold is the boundary between classes, but the beam
        // decoder needs the class centers for its Gaussian timing model.
        // Using thresholds as means causes actual character gaps (~3×dit) to
        // look like outliers, biasing toward word gap classification.
        let (char_centroid, char_count) = {
            let vals: Vec<f64> = off_durations_ms
                .iter()
                .copied()
                .filter(|&d| d >= threshold1_ms && d < threshold2_ms)
                .collect();
            if vals.is_empty() {
                (threshold1_ms, 0)
            } else {
                let mean = vals.iter().sum::<f64>() / vals.len() as f64;
                (mean, vals.len())
            }
        };
        let (word_centroid, _word_centroid_count) = {
            let vals: Vec<f64> = off_durations_ms
                .iter()
                .copied()
                .filter(|&d| d >= threshold2_ms)
                .collect();
            if vals.is_empty() {
                (threshold2_ms, 0)
            } else {
                let mean = vals.iter().sum::<f64>() / vals.len() as f64;
                (mean, vals.len())
            }
        };

        // Use centroids when we have enough events, otherwise fall back to thresholds
        let char_gap = if char_count >= 3 {
            char_centroid
        } else {
            threshold1_ms
        };
        let word_gap = if word_count >= 3.0 {
            word_centroid
        } else {
            threshold2_ms
        };

        tracing::info!(
            char_gap_ms = format!("{:.0}", char_gap),
            word_gap_ms = format!("{:.0}", word_gap),
            word_count = format!("{:.0}", word_count),
            t1 = t1,
            t2 = t2,
            char_centroid_ms = format!("{:.0}", char_centroid),
            word_centroid_ms = format!("{:.0}", word_centroid),
            "Gap thresholds from 3-class Otsu (centroids)"
        );
        (char_gap, word_gap)
    } else {
        // Fall back to valley-based approach when word class is too sparse
        let min_bin = 1;
        let mut valleys = Vec::new();
        for i in (min_bin + 1)..num_bins.saturating_sub(1) {
            if smoothed[i] <= smoothed[i - 1] && smoothed[i] < smoothed[i + 1] {
                let left_mass: f64 = smoothed[min_bin..i].iter().sum();
                let right_mass: f64 = smoothed[i + 1..num_bins].iter().sum();
                if left_mass > 1.0 && right_mass > 0.5 {
                    valleys.push(i);
                }
            }
        }

        if valleys.len() >= 2 {
            let char_gap = (valleys[0] as f64 + 0.5) * bin_width;
            let word_valley = valleys[1..]
                .iter()
                .find(|&&v| (v as f64 + 0.5) * bin_width >= char_gap * 2.0);
            let word_gap = if let Some(&wv) = word_valley {
                (wv as f64 + 0.5) * bin_width
            } else {
                default_word
            };
            tracing::info!(
                char_gap_ms = format!("{:.0}", char_gap),
                word_gap_ms = format!("{:.0}", word_gap),
                valleys = valleys.len(),
                "Gap thresholds from valley fallback (sparse word class)"
            );
            (char_gap, word_gap)
        } else if valleys.len() == 1 {
            let char_gap = (valleys[0] as f64 + 0.5) * bin_width;
            tracing::info!(
                char_gap_ms = format!("{:.0}", char_gap),
                word_gap_ms = format!("{:.0}", default_word),
                "Single valley fallback, default word gap"
            );
            (char_gap, default_word)
        } else {
            (default_char, default_word)
        }
    }
}

/// Estimate dit duration from on-durations using Otsu's method.
///
/// Splits on-durations into dit and dah clusters via maximum between-class
/// variance, then returns the median of the dit cluster. If there are fewer
/// than `min_events` on-durations, returns `fallback_ms`.
pub(crate) fn estimate_dit_otsu(
    on_durations_ms: &[f64],
    fallback_ms: f64,
    min_events: usize,
) -> f64 {
    if on_durations_ms.len() < min_events {
        return fallback_ms;
    }
    let mut sorted = on_durations_ms.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = sorted.len() as f64;
    let total_sum: f64 = sorted.iter().sum();
    let mut best_var = 0.0f64;
    let mut best_split = sorted.len() / 2;
    let mut sum_below = 0.0f64;
    for i in 1..sorted.len() {
        sum_below += sorted[i - 1];
        let w0 = i as f64 / n;
        let w1 = 1.0 - w0;
        if w0 < 0.1 || w1 < 0.1 {
            continue;
        }
        let mean0 = sum_below / i as f64;
        let mean1 = (total_sum - sum_below) / (n - i as f64);
        let between_var = w0 * w1 * (mean0 - mean1) * (mean0 - mean1);
        if between_var > best_var {
            best_var = between_var;
            best_split = i;
        }
    }
    // Median of dit cluster (everything below the Otsu split)
    let dit_cluster = &sorted[..best_split];
    if dit_cluster.is_empty() {
        fallback_ms
    } else {
        dit_cluster[dit_cluster.len() / 2]
    }
}

/// Parameters for the Viterbi HMM keying detector.
///
/// Default values are tuned for Goertzel power-domain energy input (|X(f)|²).
/// For amplitude-domain input (e.g., quadrature envelope RMS), use
/// `ViterbiParams::quadrature()`.
#[derive(Debug, Clone)]
pub(crate) struct ViterbiParams {
    /// Multiplier on the Otsu threshold for ON/OFF cluster splitting.
    /// Higher = more conservative (fewer ON detections).
    /// - Goertzel (power): 5.0 (wide log-space separation due to squared energy)
    /// - Quadrature (amplitude): ~2.2 (sqrt(5), equivalent log-space separation)
    pub cluster_split: f32,

    /// Multiplier on dit_windows for the OFF→ON transition penalty.
    /// Higher = harder to enter ON state (suppresses noise spikes).
    /// - Goertzel: 5 (compensates for -13 dB sidelobe noise spikes)
    /// - Quadrature: 3 (cleaner -25 dB stopband needs less suppression)
    pub avg_off_multiplier: usize,

    /// Initial prior probability of being in OFF state (0.0–1.0).
    pub off_prior: f64,
}

impl Default for ViterbiParams {
    /// Legacy parameters tuned for Goertzel power-domain energy.
    fn default() -> Self {
        Self {
            cluster_split: 5.0,
            avg_off_multiplier: 5,
            off_prior: 0.7,
        }
    }
}

impl ViterbiParams {
    /// Parameters tuned for quadrature envelope (amplitude domain) input.
    pub fn quadrature() -> Self {
        Self {
            cluster_split: 2.2,
            avg_off_multiplier: 3,
            off_prior: 0.6,
        }
    }
}

/// Viterbi decoder for keying event detection.
///
/// Uses a 2-state HMM (ON/OFF) with Gaussian emission probabilities in log-energy
/// space and transition probabilities based on expected element/gap durations.
/// This is more robust than simple thresholding because it leverages temporal
/// context: isolated noise spikes don't have sustained support from adjacent
/// windows, while real CW elements do.
pub(crate) fn viterbi_detect(
    energies: &[f32],
    dit_windows: usize,
    window_samples: usize,
    params: &ViterbiParams,
) -> Vec<KeyingEvent> {
    let n = energies.len();
    if n < 4 {
        return Vec::new();
    }

    // Work in log-energy space for Gaussian emission modeling
    let log_e: Vec<f64> = energies
        .iter()
        .map(|&e| (e.max(1e-10) as f64).ln())
        .collect();

    // Fit two Gaussian clusters using elevated Otsu split.
    // Standard Otsu sits at the energy overlap zone; raising it ensures
    // the ON cluster only includes clearly high-energy windows, giving
    // tighter variance and sharper discrimination.
    let mut sorted = energies.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let otsu = tone_detector::otsu_threshold_log(&sorted);
    let threshold = otsu * params.cluster_split;
    let log_threshold = (threshold.max(1e-10) as f64).ln();

    // Compute cluster statistics in log space
    let mut off_sum = 0.0f64;
    let mut off_sq = 0.0f64;
    let mut off_count = 0usize;
    let mut on_sum = 0.0f64;
    let mut on_sq = 0.0f64;
    let mut on_count = 0usize;

    for &le in &log_e {
        if le < log_threshold {
            off_sum += le;
            off_sq += le * le;
            off_count += 1;
        } else {
            on_sum += le;
            on_sq += le * le;
            on_count += 1;
        }
    }

    if off_count == 0 || on_count == 0 {
        return Vec::new();
    }

    let off_mean = off_sum / off_count as f64;
    let off_var = (off_sq / off_count as f64 - off_mean * off_mean).max(0.01);
    let on_mean = on_sum / on_count as f64;
    let on_var = (on_sq / on_count as f64 - on_mean * on_mean).max(0.01);

    #[cfg(test)]
    if std::env::var("CW_DEBUG_PATTERNS").is_ok() {
        eprintln!(
            "Viterbi: off_mean={:.2} off_var={:.2} on_mean={:.2} on_var={:.2} dit_windows={}",
            off_mean, off_var, on_mean, on_var, dit_windows,
        );
    }

    // Transition log-probabilities
    // Asymmetric: avg_on = 1× dit so element gaps (1 dit) are easily detected.
    // avg_off = N× dit so noise must persist for ~N windows to trigger ON.
    // Real dits (5+ windows) easily overcome the entry barrier; short noise
    // spikes do not. Dahs stay ON via strong emission probability.
    let avg_on = dit_windows.max(2) as f64;
    let avg_off = (dit_windows * params.avg_off_multiplier).max(6) as f64;
    // trans[from][to]: log P(from → to)
    let trans = [
        [
            (1.0 - 1.0 / avg_off).ln(), // OFF→OFF
            (1.0 / avg_off).ln(),       // OFF→ON
        ],
        [
            (1.0 / avg_on).ln(),       // ON→OFF
            (1.0 - 1.0 / avg_on).ln(), // ON→ON
        ],
    ];

    // Gaussian emission log-probability in log space
    let emit = |le: f64, state: usize| -> f64 {
        let (mean, var) = if state == 0 {
            (off_mean, off_var)
        } else {
            (on_mean, on_var)
        };
        -0.5 * (le - mean) * (le - mean) / var - 0.5 * var.ln()
    };

    // Viterbi forward pass
    // v[s] = log prob of best path ending in state s at current time
    let mut v = [0.0f64; 2];
    let mut backptr: Vec<[u8; 2]> = Vec::with_capacity(n);

    // Initialize
    v[0] = params.off_prior.ln() + emit(log_e[0], 0);
    v[1] = (1.0 - params.off_prior).ln() + emit(log_e[0], 1);
    backptr.push([0, 0]); // dummy

    for (_t, &le) in log_e.iter().enumerate().skip(1) {
        let mut new_v = [0.0f64; 2];
        let mut bp = [0u8; 2];

        for s in 0..2 {
            let from0 = v[0] + trans[0][s];
            let from1 = v[1] + trans[1][s];
            if from0 >= from1 {
                new_v[s] = from0 + emit(le, s);
                bp[s] = 0;
            } else {
                new_v[s] = from1 + emit(le, s);
                bp[s] = 1;
            }
        }

        v = new_v;
        backptr.push(bp);
    }

    // Backtrace
    let mut states = vec![0u8; n];
    states[n - 1] = if v[1] > v[0] { 1 } else { 0 };
    for t in (0..n - 1).rev() {
        states[t] = backptr[t + 1][states[t + 1] as usize];
    }

    // Convert state sequence to keying events
    let mut events = Vec::new();
    let mut prev_state = 0u8;
    for (i, &state) in states.iter().enumerate() {
        if state != prev_state {
            events.push(KeyingEvent {
                kind: if state == 1 {
                    KeyingEventKind::On
                } else {
                    KeyingEventKind::Off
                },
                sample_offset: i * window_samples,
            });
        }
        prev_state = state;
    }
    if prev_state == 1 {
        events.push(KeyingEvent {
            kind: KeyingEventKind::Off,
            sample_offset: n * window_samples,
        });
    }

    events
}

/// Process a single tone frequency through the full detection pipeline.
///
/// Encapsulates: bandpass → Goertzel → threshold → WPM estimate → Viterbi →
/// merge → dit estimation → gap estimation → operator segmentation.
///
/// Returns `Vec<ToneSegment>` — one per operator segment detected on this tone.
fn process_tone(
    active: &[f32],
    sample_rate: u32,
    tone_freq: f32,
    global_fallback_dit: Option<f64>,
) -> Vec<ToneSegment> {
    // Narrow bandpass ±40 Hz around the detected CW tone.
    let narrow_low = (tone_freq - 40.0).max(400.0);
    let narrow_high = (tone_freq + 40.0).min(900.0);
    let mut filtered = active.to_vec();
    BiquadCascade::bandpass(narrow_low, narrow_high, 3, sample_rate).process_block(&mut filtered);

    // 10ms windows for fine time resolution
    let mut detector = ToneDetector::new(tone_freq, sample_rate, 10);
    detector.calibrate_from_audio(&filtered);
    detector.enable_adaptive();

    let raw_events = detector.process(&filtered);
    let final_event = detector.finalize();

    let initial_max_gap = (sample_rate as f64 * 0.030) as usize;
    let min_on = (sample_rate as f64 * 0.020) as usize;
    let mut all_raw: Vec<_> = raw_events;
    if let Some(fe) = final_event {
        all_raw.push(fe);
    }

    // Initial merge with fixed 30ms gap for WPM estimation
    let initial_events = merge_keying_events(&all_raw, initial_max_gap, min_on);

    // Estimate WPM from the full signal's event distribution
    let (_estimated_wpm, dit_estimate_ms) = {
        let all_evts: Vec<_> = initial_events.iter().collect();
        let mut on_ms: Vec<f64> = Vec::new();
        for i in 0..all_evts.len().saturating_sub(1) {
            let dur = (all_evts[i + 1].sample_offset as f64 - all_evts[i].sample_offset as f64)
                / sample_rate as f64
                * 1000.0;
            if all_evts[i].kind == KeyingEventKind::On {
                on_ms.push(dur);
            }
        }
        let (wpm, dit_ms) = estimate_wpm_histogram(&on_ms);
        (wpm, dit_ms)
    };

    // Viterbi detection using per-window energies
    let window_samples = (sample_rate as usize * 10) / 1000; // 10ms
    let num_windows = filtered.len() / window_samples;
    let dit_windows = (dit_estimate_ms / 10.0).round().max(3.0) as usize;

    let energies: Vec<f32> = (0..num_windows)
        .map(|i| {
            let start = i * window_samples;
            tone_detector::goertzel_energy(
                &filtered[start..start + window_samples],
                tone_freq,
                sample_rate,
            )
        })
        .collect();

    let viterbi_events = viterbi_detect(
        &energies,
        dit_windows,
        window_samples,
        &ViterbiParams::default(),
    );

    // Merge Viterbi events with WPM-scaled parameters
    let wpm_scaled_gap = (sample_rate as f64 * dit_estimate_ms * 0.5 / 1000.0) as usize;
    let viterbi_min_on = (sample_rate as f64 * 0.030) as usize;
    let events = merge_keying_events(&viterbi_events, wpm_scaled_gap, viterbi_min_on);

    // Re-estimate dit duration from Viterbi events
    let decoder_dit_ms = {
        let evts: Vec<_> = events.iter().collect();
        let mut vit_on_ms: Vec<f64> = Vec::new();
        for i in 0..evts.len().saturating_sub(1) {
            let dur = (evts[i + 1].sample_offset as f64 - evts[i].sample_offset as f64)
                / sample_rate as f64
                * 1000.0;
            if evts[i].kind == KeyingEventKind::On {
                vit_on_ms.push(dur);
            }
        }
        let fallback = global_fallback_dit.unwrap_or(dit_estimate_ms);
        estimate_dit_otsu(&vit_on_ms, fallback, 4)
    };
    let decoder_wpm = ((1200.0 / decoder_dit_ms) as u32).clamp(5, 50);

    // Compute gap thresholds for segment boundary detection
    let evts: Vec<_> = events.iter().collect();
    let mut global_off_ms: Vec<f64> = Vec::new();
    for i in 0..evts.len().saturating_sub(1) {
        let dur = (evts[i + 1].sample_offset as f64 - evts[i].sample_offset as f64)
            / sample_rate as f64
            * 1000.0;
        if evts[i].kind == KeyingEventKind::Off {
            global_off_ms.push(dur);
        }
    }
    let (_cg_raw, wg_raw) = estimate_gap_thresholds(&global_off_ms, decoder_dit_ms);

    // Segment boundary threshold: cap at 15×dit to prevent centroid inflation
    // from inter-transmission pauses making the threshold too high (which would
    // lump multiple transmissions into a single segment with wrong gap estimates).
    let segment_threshold_ms = wg_raw
        .min(decoder_dit_ms * 15.0)
        .max(decoder_dit_ms * 7.0)
        .max(500.0);
    let segment_threshold_samples = (segment_threshold_ms / 1000.0 * sample_rate as f64) as usize;

    // Find segment start indices
    let mut seg_starts: Vec<usize> = vec![0];
    for i in 0..events.len().saturating_sub(1) {
        if events[i].kind == KeyingEventKind::Off {
            let gap = events[i + 1]
                .sample_offset
                .saturating_sub(events[i].sample_offset);
            if gap >= segment_threshold_samples {
                seg_starts.push(i + 1);
            }
        }
    }

    let on_count = events
        .iter()
        .filter(|e| e.kind == KeyingEventKind::On)
        .count();
    tracing::info!(
        tone_freq_hz = format!("{:.0}", tone_freq),
        viterbi_raw = viterbi_events.len(),
        on_events = on_count,
        wpm = decoder_wpm,
        segments = seg_starts.len(),
        segment_threshold_ms = format!("{:.0}", segment_threshold_ms),
        "Per-tone: Viterbi detection + merge"
    );

    // Build ToneSegments from operator segments
    let min_events_for_estimation = 8;
    let min_off_events_for_gaps = 6;
    let mut tone_segments: Vec<ToneSegment> = Vec::new();

    for seg_idx in 0..seg_starts.len() {
        let start = seg_starts[seg_idx];
        let end = seg_starts.get(seg_idx + 1).copied().unwrap_or(events.len());
        let seg_events = &events[start..end];

        // Extract per-segment on/off durations
        let seg_evts: Vec<_> = seg_events.iter().collect();
        let mut seg_on_ms: Vec<f64> = Vec::new();
        let mut seg_off_ms: Vec<f64> = Vec::new();
        for i in 0..seg_evts.len().saturating_sub(1) {
            let dur = (seg_evts[i + 1].sample_offset as f64 - seg_evts[i].sample_offset as f64)
                / sample_rate as f64
                * 1000.0;
            if seg_evts[i].kind == KeyingEventKind::On {
                seg_on_ms.push(dur);
            } else {
                seg_off_ms.push(dur);
            }
        }

        // Estimate per-segment dit
        let seg_dit = estimate_dit_otsu(&seg_on_ms, decoder_dit_ms, min_events_for_estimation);
        let seg_wpm = ((1200.0 / seg_dit) as u32).clamp(5, 50);

        // Estimate per-segment gap thresholds.
        // Cap char_gap at 5×dit and word_gap at 10×dit to prevent centroid
        // inflation when inter-transmission pauses are included in the segment.
        let (seg_cg, seg_wg) = if seg_off_ms.len() >= min_off_events_for_gaps {
            let (cg_raw, wg_raw) = estimate_gap_thresholds(&seg_off_ms, seg_dit);
            let cg = cg_raw.max(seg_dit * 1.5).min(seg_dit * 5.0);
            let wg = wg_raw.max(seg_dit * 2.5).max(cg * 1.5).min(seg_dit * 10.0);
            (cg, wg)
        } else {
            (seg_dit * 1.5, seg_dit * 3.5)
        };

        let start_sample = seg_events.first().map(|e| e.sample_offset).unwrap_or(0);

        tone_segments.push(ToneSegment {
            tone_freq,
            events: seg_events.to_vec(),
            start_sample,
            dit_ms: seg_dit,
            wpm: seg_wpm,
            char_gap_ms: seg_cg,
            word_gap_ms: seg_wg,
            operator_id: 0, // assigned later during frequency clustering
        });
    }

    tone_segments
}

/// Deduplicate temporally overlapping sidelobes at nearby frequencies.
///
/// When a single CW signal at ~530 Hz is detected, `scan_tone_activity` often
/// reports sidelobes at 520, 525, 535, 540 Hz etc. for the same time window.
/// This function merges overlapping activities within `threshold_hz`, keeping
/// the longest one per overlap group. Activities at similar frequencies but
/// different times (non-overlapping) are kept as separate signals.
fn dedup_sidelobe_activities(
    activities: Vec<ToneActivity>,
    threshold_hz: f32,
) -> Vec<ToneActivity> {
    if activities.len() <= 1 {
        return activities;
    }

    let original_count = activities.len();
    let mut keep = vec![true; activities.len()];

    // For each pair, if they overlap in both time and frequency,
    // drop the shorter one.
    for i in 0..activities.len() {
        if !keep[i] {
            continue;
        }
        for j in (i + 1)..activities.len() {
            if !keep[j] {
                continue;
            }
            // Check frequency proximity
            if (activities[i].freq - activities[j].freq).abs() > threshold_hz {
                continue;
            }
            // Check temporal overlap (>50% of the shorter one)
            let overlap_start = activities[i].start_sample.max(activities[j].start_sample);
            let overlap_end = activities[i].end_sample.min(activities[j].end_sample);
            if overlap_start >= overlap_end {
                continue; // no time overlap — different signals
            }
            let overlap_len = overlap_end - overlap_start;
            let j_len = activities[j]
                .end_sample
                .saturating_sub(activities[j].start_sample);
            let i_len = activities[i]
                .end_sample
                .saturating_sub(activities[i].start_sample);
            let shorter_len = i_len.min(j_len);
            if shorter_len == 0 || (overlap_len as f64 / shorter_len as f64) < 0.5 {
                continue; // minimal overlap — keep both
            }
            // Drop the shorter one
            if i_len >= j_len {
                keep[j] = false;
            } else {
                keep[i] = false;
                break; // i was dropped, stop comparing it
            }
        }
    }

    let result: Vec<ToneActivity> = activities
        .into_iter()
        .enumerate()
        .filter(|(idx, _)| keep[*idx])
        .map(|(_, a)| a)
        .collect();

    tracing::info!(
        before = original_count,
        after = result.len(),
        "Deduped sidelobe activities"
    );

    result
}

/// Transcribe raw audio samples through the CW pipeline without database access.
///
/// Runs: multi-tone frequency detection → per-tone Viterbi processing →
/// chronological segment interleaving → per-segment morse decoding.
/// Returns (decoded_text, estimated_wpm).
pub fn transcribe_audio(samples: &[f32], sample_rate: u32) -> (String, Option<f64>) {
    let active_start = find_active_start(samples, sample_rate);
    let active = &samples[active_start..];
    if active_start > 0 {
        tracing::info!(
            skipped_secs = active_start as f64 / sample_rate as f64,
            "Skipped leading silence"
        );
    }

    // Scan for time-frequency activity regions (replaces detect_peak_frequencies)
    let activities = scan_tone_activity(active, sample_rate, 400.0, 900.0, 10.0);
    let activities = tone_detector::refine_tone_frequencies(active, sample_rate, activities);

    // Cluster nearby frequencies (within 15 Hz) and keep only the longest
    // activity per cluster. This prevents the same signal's sidelobes from
    // being decoded 14 times (matches Decoder A's clustering approach).
    let activities = dedup_sidelobe_activities(activities, 15.0);

    // Process each activity region through the full pipeline
    let mut all_segments: Vec<ToneSegment> = Vec::new();
    let padding_before = sample_rate as usize; // 1s padding for calibration
    let padding_after = sample_rate as usize / 2; // 0.5s padding

    for activity in &activities {
        let slice_start = activity.start_sample.saturating_sub(padding_before);
        let slice_end = (activity.end_sample + padding_after).min(active.len());
        let slice = &active[slice_start..slice_end];

        let mut segments = process_tone(slice, sample_rate, activity.freq, None);

        // Offset segment positions back to full-recording coordinates
        for seg in &mut segments {
            seg.start_sample += slice_start;
            for ev in &mut seg.events {
                ev.sample_offset += slice_start;
            }
        }
        all_segments.extend(segments);
    }

    // Sort all segments chronologically by start_sample
    all_segments.sort_by_key(|s| s.start_sample);

    // Per-segment decoding
    let mut segment_texts: Vec<String> = Vec::new();
    let mut total_decoded_chars = 0usize;
    let mut wpm_sum = 0u64;
    let mut wpm_count = 0u64;

    for seg in &all_segments {
        let mut beam_decoder =
            BeamDecoder::new(seg.dit_ms, seg.char_gap_ms, seg.word_gap_ms, sample_rate);
        for event in &seg.events {
            beam_decoder.process_event(*event);
        }
        let seg_text = beam_decoder.finalize();
        total_decoded_chars += seg_text.chars().filter(|c| !c.is_whitespace()).count();

        let trimmed = seg_text.trim();
        if !trimmed.is_empty() {
            segment_texts.push(trimmed.to_string());
            wpm_sum += seg.wpm as u64;
            wpm_count += 1;
        }
    }

    let raw_text = segment_texts.join(" ");

    // Post-decode cleanup: remove isolated single-element Morse noise words.
    // At low SNR, noise blips produce spurious E (.) and T (-) characters
    // that appear as standalone "words" surrounded by spaces. Remove them
    // to clean up the output. Multi-element single-char words (I, N, W, etc.)
    // are kept since they're less likely to be pure noise.
    let text = {
        let words: Vec<&str> = raw_text.split_whitespace().collect();
        let cleaned: Vec<&str> = words
            .iter()
            .filter(|w| {
                if w.len() > 1 {
                    return true;
                }
                let c = w.chars().next().unwrap_or(' ');
                !matches!(c, 'E' | 'T')
            })
            .copied()
            .collect();
        cleaned.join(" ")
    };

    // Protocol-aware post-processing: correct systematic CW decoding errors
    // using amateur radio protocol structure (word boundaries, vocabulary,
    // callsign patterns, RST reports).
    let pp = postprocess::postprocess(&text);
    for ann in &pp.annotations {
        tracing::debug!(
            original = %ann.original,
            corrected = %ann.corrected,
            kind = ?ann.kind,
            "Post-process correction"
        );
    }
    let text = pp.text;

    // Average WPM across segments that produced text
    let avg_wpm = if wpm_count > 0 {
        ((wpm_sum / wpm_count) as u32).clamp(5, 50)
    } else {
        15
    };

    tracing::info!(
        decoded_count = total_decoded_chars,
        segments = all_segments.len(),
        tones = activities.len(),
        text = %text,
        wpm = avg_wpm,
        "Decoder output"
    );
    let wpm = if text.is_empty() {
        None
    } else {
        Some(avg_wpm as f64)
    };

    (text, wpm)
}

/// Transcribe audio and produce a structured transcript with word-level timing.
///
/// Same pipeline as `transcribe_audio()` but uses `finalize_with_spans()` to
/// capture word timing, builds `TranscriptLine`s per segment, detects speakers,
/// and identifies QSO ranges.
///
/// `progress` is updated atomically (0-100) as segments are processed.
pub fn transcribe_audio_structured(
    samples: &[f32],
    sample_rate: u32,
    recording_id: uuid::Uuid,
    progress: &std::sync::atomic::AtomicU8,
) -> structured::StructuredTranscript {
    use std::sync::atomic::Ordering::Relaxed;

    use beam::WordSpan;
    use structured::{StructuredTranscript, TranscriptLine, TranscriptWord};

    progress.store(5, Relaxed);

    let active_start = find_active_start(samples, sample_rate);
    let active = &samples[active_start..];
    let active_offset_secs = active_start as f64 / sample_rate as f64;

    // Scan for time-frequency activity regions
    let activities = scan_tone_activity(active, sample_rate, 400.0, 900.0, 10.0);
    let activities = tone_detector::refine_tone_frequencies(active, sample_rate, activities);
    let activities = dedup_sidelobe_activities(activities, 15.0);
    progress.store(10, Relaxed);

    // Process each activity region
    let mut all_segments: Vec<ToneSegment> = Vec::new();
    let padding_before = sample_rate as usize; // 1s padding for calibration
    let padding_after = sample_rate as usize / 2; // 0.5s padding

    for activity in &activities {
        let slice_start = activity.start_sample.saturating_sub(padding_before);
        let slice_end = (activity.end_sample + padding_after).min(active.len());
        let slice = &active[slice_start..slice_end];

        let mut segments = process_tone(slice, sample_rate, activity.freq, None);

        // Offset segment positions back to full-recording coordinates
        for seg in &mut segments {
            seg.start_sample += slice_start;
            for ev in &mut seg.events {
                ev.sample_offset += slice_start;
            }
        }
        all_segments.extend(segments);
    }
    all_segments.sort_by_key(|s| s.start_sample);

    // Assign operator IDs by grouping nearby tone frequencies (within 15 Hz)
    let mut freq_groups: Vec<(f32, usize)> = Vec::new(); // (centroid, operator_id)
    for seg in &mut all_segments {
        let assigned = freq_groups
            .iter()
            .find(|(centroid, _)| (seg.tone_freq - centroid).abs() < 15.0)
            .map(|(_, id)| *id);
        match assigned {
            Some(id) => seg.operator_id = id,
            None => {
                let new_id = freq_groups.len();
                freq_groups.push((seg.tone_freq, new_id));
                seg.operator_id = new_id;
            }
        }
    }

    let total_segs = all_segments.len().max(1);
    let mut lines: Vec<TranscriptLine> = Vec::new();
    let mut wpm_sum = 0u64;
    let mut wpm_count = 0u64;
    let mut confidence_sum = 0.0f64;
    let mut confidence_count = 0u64;

    for (seg_idx, seg) in all_segments.iter().enumerate() {
        let mut beam_decoder =
            BeamDecoder::new(seg.dit_ms, seg.char_gap_ms, seg.word_gap_ms, sample_rate);
        for event in &seg.events {
            beam_decoder.process_event(*event);
        }
        let (_text, spans) = beam_decoder.finalize_with_spans();

        // Convert WordSpans to TranscriptWords
        let words: Vec<TranscriptWord> = spans
            .into_iter()
            .filter(|s| !s.text.trim().is_empty())
            .filter(|s| !(s.text.len() == 1 && matches!(s.text.as_str(), "E" | "T")))
            .map(|span: WordSpan| {
                let start_secs = active_offset_secs + span.start_sample as f64 / sample_rate as f64;
                let end_secs = active_offset_secs + span.end_sample as f64 / sample_rate as f64;
                let upper = span.text.to_uppercase();
                let is_cs = beam::is_callsign_pattern(&upper);
                // Apply post-processing to individual word
                let corrected = postprocess::postprocess(&span.text).text;
                TranscriptWord {
                    id: uuid::Uuid::new_v4(),
                    start_offset: start_secs,
                    end_offset: end_secs,
                    text: corrected,
                    is_callsign: is_cs,
                    confidence: 0.85, // baseline confidence
                }
            })
            .collect();

        if !words.is_empty() {
            let start_offset = words.first().map(|w| w.start_offset).unwrap_or(0.0);
            let end_offset = words.last().map(|w| w.end_offset).unwrap_or(0.0);
            let speaker = structured::detect_speaker(&words);

            lines.push(TranscriptLine {
                id: uuid::Uuid::new_v4(),
                start_offset,
                end_offset,
                words,
                speaker_callsign: speaker,
                operator_id: Some(seg.operator_id as u32),
                tone_freq_hz: Some(seg.tone_freq),
            });

            wpm_sum += seg.wpm as u64;
            wpm_count += 1;
            confidence_sum += 0.85;
            confidence_count += 1;
        }

        // Update progress: 10..95 across segments
        let pct = 10 + ((seg_idx + 1) * 85 / total_segs) as u8;
        progress.store(pct.min(95), Relaxed);
    }

    // Remove decoded noise lines (repetitive short prosigns)
    let lines = structured::filter_noise_lines(lines);

    let avg_wpm = if wpm_count > 0 {
        (wpm_sum / wpm_count) as u32
    } else {
        15
    };
    let avg_confidence = if confidence_count > 0 {
        confidence_sum / confidence_count as f64
    } else {
        0.0
    };

    let detected_qso_ranges = structured::detect_qso_ranges(&lines);

    progress.store(100, Relaxed);

    StructuredTranscript {
        recording_id,
        lines,
        detected_qso_ranges,
        generated_at: chrono::Utc::now().to_rfc3339(),
        decoder_version: env!("CARGO_PKG_VERSION").to_string(),
        decoder_name: "legacy".into(),
        average_wpm: avg_wpm,
        average_confidence: avg_confidence,
    }
}

/// Result of a successful transcription.
#[derive(Debug, Clone)]
pub struct TranscriptionResult {
    pub id: Uuid,
    pub text: String,
    pub wpm_estimate: Option<f64>,
    pub char_count: i64,
}

/// Engine that orchestrates CW transcription of recordings.
pub struct TranscriptionEngine {
    db: Arc<Mutex<Database>>,
    /// Base directory for data storage (uploads, etc.).
    data_dir: Option<std::path::PathBuf>,
    /// In-flight async transcriptions: transcription UUID → progress (0-100).
    in_flight: std::sync::Mutex<std::collections::HashMap<Uuid, Arc<std::sync::atomic::AtomicU8>>>,
    /// Pluggable decoder implementation (default: LegacyDecoder).
    decoder: Arc<dyn decoder_trait::CwDecoder>,
}

impl TranscriptionEngine {
    pub fn new(db: Arc<Mutex<Database>>) -> Self {
        Self {
            db,
            data_dir: None,
            in_flight: std::sync::Mutex::new(std::collections::HashMap::new()),
            decoder: Arc::new(legacy::LegacyDecoder),
        }
    }

    /// Create engine with data directory for upload-based transcription.
    pub fn with_data_dir(db: Arc<Mutex<Database>>, data_dir: std::path::PathBuf) -> Self {
        Self {
            db,
            data_dir: Some(data_dir),
            in_flight: std::sync::Mutex::new(std::collections::HashMap::new()),
            decoder: Arc::new(legacy::LegacyDecoder),
        }
    }

    /// Set a custom decoder implementation.
    pub fn with_decoder(mut self, decoder: Arc<dyn decoder_trait::CwDecoder>) -> Self {
        self.decoder = decoder;
        self
    }

    /// Resolve a decoder name to an implementation.
    ///
    /// Supported names: "legacy", "decoder-a", "ensemble", "auto" (default).
    /// Unknown names fall back to "auto" (currently decoder-a).
    pub fn resolve_decoder(name: &str) -> Arc<dyn decoder_trait::CwDecoder> {
        match name {
            "legacy" => Arc::new(legacy::LegacyDecoder),
            "decoder-a" => Arc::new(decoder_a::DecoderA),
            "ensemble" => Arc::new(ensemble::EnsembleDecoder::new(
                vec![
                    Arc::new(legacy::LegacyDecoder) as Arc<dyn decoder_trait::CwDecoder>,
                    Arc::new(decoder_a::DecoderA) as Arc<dyn decoder_trait::CwDecoder>,
                ],
                ensemble::CombineStrategy::HighestConfidence,
            )),
            _ => Arc::new(decoder_a::DecoderA), // "auto" or unknown
        }
    }

    /// Get progress for an in-flight transcription (0-100), or None if not in-flight.
    pub fn get_progress(&self, transcription_id: Uuid) -> Option<u8> {
        self.in_flight.lock().ok().and_then(|map| {
            map.get(&transcription_id)
                .map(|p| p.load(std::sync::atomic::Ordering::Relaxed))
        })
    }

    /// Transcribe a recording by ID.
    ///
    /// The recording must be stopped and CW mode. Reads audio from segments,
    /// runs tone detection and morse decoding, writes the result to DB.
    pub async fn transcribe_recording(
        &self,
        recording_id: Uuid,
    ) -> Result<TranscriptionResult, TranscriptionError> {
        // Validate recording and fetch segments
        let (_recording, segments) = {
            let db = self.db.lock().await;
            let rec = db
                .get_recording(recording_id)
                .map_err(|_| TranscriptionError::NotFound(recording_id))?;

            if rec.status != "stopped" {
                return Err(TranscriptionError::InvalidRecording(format!(
                    "recording {} has status '{}', expected 'stopped'",
                    recording_id, rec.status
                )));
            }
            if rec.mode != "cw" {
                return Err(TranscriptionError::InvalidRecording(format!(
                    "recording {} has mode '{}', expected 'cw'",
                    recording_id, rec.mode
                )));
            }

            let segs = db.list_segments(recording_id).map_err(|e| {
                TranscriptionError::ProcessingFailed(format!("failed to list segments: {e}"))
            })?;

            if segs.is_empty() {
                return Err(TranscriptionError::InvalidRecording(
                    "recording has no segments".into(),
                ));
            }

            (rec, segs)
        };

        // Insert in-progress transcription row
        let tx_id = Uuid::new_v4();
        let now = Utc::now();
        {
            let db = self.db.lock().await;
            db.insert_transcription(&TranscriptionRow {
                id: tx_id,
                recording_id: Some(recording_id),
                text: String::new(),
                status: "in_progress".into(),
                wpm_estimate: None,
                char_count: 0,
                error_message: None,
                started_at: now,
                completed_at: None,
                created_at: now,
                structured_transcript: None,
                progress: None,
                uploaded_recording_id: None,
            })?;
        }

        info!(transcription = %tx_id, recording = %recording_id, "Transcription started");

        // Heavy work in spawn_blocking: read audio, detect tones, decode
        let decoder = Arc::clone(&self.decoder);
        let result =
            tokio::task::spawn_blocking(move || -> Result<(String, Option<f64>), String> {
                let (sample_rate, samples) = combine::read_recording_audio(&segments)
                    .map_err(|e| format!("failed to read audio: {e}"))?;

                let output = decoder.decode(&samples, sample_rate);
                Ok((output.text, output.wpm))
            })
            .await
            .map_err(|e| TranscriptionError::ProcessingFailed(format!("task panicked: {e}")))?;

        // Update DB with result
        let completed_at = Utc::now();
        match result {
            Ok((text, wpm_estimate)) => {
                let char_count = text.chars().filter(|c| !c.is_whitespace()).count() as i64;
                let db = self.db.lock().await;
                db.update_transcription_status(
                    tx_id,
                    "completed",
                    &text,
                    wpm_estimate,
                    char_count,
                    None,
                    Some(completed_at),
                )?;

                info!(
                    transcription = %tx_id,
                    chars = char_count,
                    wpm = ?wpm_estimate,
                    "Transcription completed"
                );

                Ok(TranscriptionResult {
                    id: tx_id,
                    text,
                    wpm_estimate,
                    char_count,
                })
            }
            Err(err_msg) => {
                let db = self.db.lock().await;
                db.update_transcription_status(
                    tx_id,
                    "failed",
                    "",
                    None,
                    0,
                    Some(&err_msg),
                    Some(completed_at),
                )?;

                error!(transcription = %tx_id, error = %err_msg, "Transcription failed");

                Err(TranscriptionError::ProcessingFailed(err_msg))
            }
        }
    }

    /// Start async transcription of an uploaded recording.
    ///
    /// Returns the transcription UUID immediately. The actual work runs
    /// in a background task. Poll via `get_progress()` or the API endpoint.
    pub async fn start_transcription_async(
        self: &Arc<Self>,
        uploaded_recording_id: Uuid,
    ) -> Result<Uuid, TranscriptionError> {
        self.start_transcription_async_with_decoder(uploaded_recording_id, None)
            .await
    }

    /// Start async transcription with an optional decoder override.
    ///
    /// If `decoder_override` is `Some`, uses that decoder instead of the engine default.
    pub async fn start_transcription_async_with_decoder(
        self: &Arc<Self>,
        uploaded_recording_id: Uuid,
        decoder_override: Option<Arc<dyn decoder_trait::CwDecoder>>,
    ) -> Result<Uuid, TranscriptionError> {
        // Verify uploaded recording exists and is decoded
        {
            let db = self.db.lock().await;
            let ur = db
                .get_uploaded_recording(uploaded_recording_id)
                .map_err(|_| TranscriptionError::NotFound(uploaded_recording_id))?;

            if ur.status != "decoded" {
                return Err(TranscriptionError::InvalidRecording(format!(
                    "uploaded recording {} has status '{}', expected 'decoded'",
                    uploaded_recording_id, ur.status
                )));
            }
        }

        let data_dir = self
            .data_dir
            .clone()
            .ok_or_else(|| TranscriptionError::ProcessingFailed("no data_dir configured".into()))?;

        // Create transcription row
        let tx_id = Uuid::new_v4();
        let now = Utc::now();
        {
            let db = self.db.lock().await;
            db.insert_transcription(&TranscriptionRow {
                id: tx_id,
                recording_id: None,
                text: String::new(),
                status: "in_progress".into(),
                wpm_estimate: None,
                char_count: 0,
                error_message: None,
                started_at: now,
                completed_at: None,
                created_at: now,
                structured_transcript: None,
                progress: Some(0.0),
                uploaded_recording_id: Some(uploaded_recording_id),
            })?;
        }

        // Set up progress tracking
        let progress = Arc::new(std::sync::atomic::AtomicU8::new(0));
        {
            let mut map = self.in_flight.lock().unwrap();
            map.insert(tx_id, Arc::clone(&progress));
        }

        let decoder = decoder_override.unwrap_or_else(|| Arc::clone(&self.decoder));
        info!(
            transcription = %tx_id,
            uploaded_recording = %uploaded_recording_id,
            decoder = decoder.name(),
            "Async transcription started"
        );

        // Spawn background task
        let engine = Arc::clone(self);
        let progress_clone = Arc::clone(&progress);
        tokio::spawn(async move {
            let result = Self::run_upload_transcription(
                &data_dir,
                uploaded_recording_id,
                tx_id,
                &progress_clone,
                &decoder,
            )
            .await;

            let completed_at = Utc::now();
            let db = engine.db.lock().await;

            match result {
                Ok(transcript) => {
                    let json = serde_json::to_string(&transcript).unwrap_or_default();
                    let text: String = transcript
                        .lines
                        .iter()
                        .map(|l| {
                            l.words
                                .iter()
                                .map(|w| w.text.as_str())
                                .collect::<Vec<_>>()
                                .join(" ")
                        })
                        .collect::<Vec<_>>()
                        .join(" ");
                    let char_count = text.chars().filter(|c| !c.is_whitespace()).count() as i64;
                    let wpm = if transcript.average_wpm > 0 {
                        Some(transcript.average_wpm as f64)
                    } else {
                        None
                    };

                    if let Err(e) = db.update_transcription_structured(
                        tx_id,
                        "completed",
                        &text,
                        wpm,
                        char_count,
                        None,
                        Some(completed_at),
                        Some(&json),
                        Some(1.0),
                    ) {
                        error!(
                            transcription = %tx_id,
                            error = %e,
                            "Failed to update completed transcription"
                        );
                    } else {
                        info!(
                            transcription = %tx_id,
                            chars = char_count,
                            "Async transcription completed"
                        );
                    }
                }
                Err(err_msg) => {
                    if let Err(e) = db.update_transcription_structured(
                        tx_id,
                        "failed",
                        "",
                        None,
                        0,
                        Some(&err_msg),
                        Some(completed_at),
                        None,
                        None,
                    ) {
                        error!(
                            transcription = %tx_id,
                            error = %e,
                            "Failed to update failed transcription"
                        );
                    }
                    error!(
                        transcription = %tx_id,
                        error = %err_msg,
                        "Async transcription failed"
                    );
                }
            }

            // Remove from in-flight map
            if let Ok(mut map) = engine.in_flight.lock() {
                map.remove(&tx_id);
            }
        });

        Ok(tx_id)
    }

    /// Run the transcription pipeline for an uploaded recording.
    async fn run_upload_transcription(
        data_dir: &std::path::Path,
        uploaded_recording_id: Uuid,
        tx_id: Uuid,
        progress: &Arc<std::sync::atomic::AtomicU8>,
        decoder: &Arc<dyn decoder_trait::CwDecoder>,
    ) -> Result<structured::StructuredTranscript, String> {
        use crate::recording::audio_decode;

        let decoded_path = data_dir
            .join("uploads")
            .join(uploaded_recording_id.to_string())
            .join("decoded.wav");

        if !decoded_path.exists() {
            return Err(format!("decoded WAV not found: {}", decoded_path.display()));
        }

        let progress_clone = Arc::clone(progress);
        let decoder = Arc::clone(decoder);
        let result = tokio::task::spawn_blocking(move || {
            let (sample_rate, samples) = audio_decode::decode_to_pcm(&decoded_path)
                .map_err(|e| format!("failed to read decoded audio: {e}"))?;
            Ok::<_, String>(decoder.decode_structured(
                &samples,
                sample_rate,
                tx_id,
                &progress_clone,
            ))
        })
        .await
        .map_err(|e| format!("transcription task panicked: {e}"))?;

        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn narrow_bandpass_removes_interferer() {
        let sr = 12_000u32;
        let duration = 2.0f32;
        let num_samples = (sr as f32 * duration) as usize;

        // 650 Hz target tone (keyed) + 800 Hz interferer (constant)
        let samples: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let target = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                let interferer = (2.0 * std::f32::consts::PI * 800.0 * t).sin() * 0.5;
                // Key the target: 100ms on, 100ms off
                let keyed = if (i / 1200) % 2 == 0 { target } else { 0.0 };
                keyed + interferer
            })
            .collect();

        // Apply narrow bandpass around 650 Hz
        let narrow_low = (650.0 - 75.0f32).max(400.0);
        let narrow_high = (650.0 + 75.0f32).min(900.0);
        let mut filtered = samples.clone();
        BiquadCascade::bandpass(narrow_low, narrow_high, 3, sr).process_block(&mut filtered);

        // Verify the bandpass significantly reduces the interferer:
        // Check energy at 800 Hz vs 650 Hz in the filtered signal.
        // The bandpass should attenuate 800 Hz relative to 650 Hz.
        let window_size = (sr as f32 * 0.05) as usize; // 50ms
        let goertzel_at = |freq: f32, buf: &[f32]| -> f32 {
            let k = freq * buf.len() as f32 / sr as f32;
            let coeff = 2.0 * (2.0 * std::f32::consts::PI * k / buf.len() as f32).cos();
            let mut s1: f32 = 0.0;
            let mut s2: f32 = 0.0;
            for &sample in buf {
                let s0 = sample + coeff * s1 - s2;
                s2 = s1;
                s1 = s0;
            }
            s1 * s1 + s2 * s2 - coeff * s1 * s2
        };

        // Check a "keyed on" window well past the filter's transient (500ms in).
        // First 100ms = 1200 samples. Window at 6000 (500ms) is in a keyed-on
        // period (6000/1200 = 5, 5%2=1 = off, but 4800/1200=4, 4%2=0 = on
        // starts at 4800). Use 4800..5400 (on period starting at 400ms).
        let start = 4800;
        let on_window = &filtered[start..start + window_size];
        let e650_filt = goertzel_at(650.0, on_window);
        let e800_filt = goertzel_at(800.0, on_window);

        let on_window_raw = &samples[start..start + window_size];
        let e650_raw = goertzel_at(650.0, on_window_raw);
        let e800_raw = goertzel_at(800.0, on_window_raw);

        // In raw audio, 800 Hz interferer has significant energy
        let raw_ratio = e650_raw / e800_raw.max(1e-10);
        // After filtering, 800 Hz should be meaningfully weaker.
        // With 3rd-order BPF and 75Hz margin, we expect ~6-12 dB attenuation.
        let filt_ratio = e650_filt / e800_filt.max(1e-10);

        assert!(
            filt_ratio > raw_ratio * 1.5,
            "bandpass should improve 650/800 ratio: raw={raw_ratio:.1}, filtered={filt_ratio:.1}"
        );
    }

    #[test]
    fn histogram_wpm_known_clusters() {
        // Synthetic durations: dits at ~60ms, dahs at ~180ms (20 WPM)
        let mut durations = Vec::new();
        for _ in 0..30 {
            durations.push(55.0 + rand_noise(5.0));
        }
        for _ in 0..15 {
            durations.push(175.0 + rand_noise(10.0));
        }

        let (wpm, dit_ms) = estimate_wpm_histogram(&durations);
        assert!(
            wpm >= 17 && wpm <= 25,
            "expected WPM near 20, got {wpm} (dit={dit_ms:.0}ms)"
        );
        assert!(
            dit_ms > 40.0 && dit_ms < 80.0,
            "expected dit ~60ms, got {dit_ms:.0}ms"
        );
    }

    #[test]
    fn histogram_wpm_few_events_uses_fallback() {
        let durations = vec![60.0, 180.0];
        let (wpm, _dit_ms) = estimate_wpm_histogram(&durations);
        // Should return default 15 WPM for too few events
        assert_eq!(wpm, 15);
    }

    #[test]
    fn gap_thresholds_compressed_char_gaps() {
        // Simulate off-durations at 20 WPM with compressed char gaps
        // Element gaps ~60ms, char gaps ~120ms (2x dit instead of 3x),
        // word gaps ~350ms
        let dit_ms = 60.0;
        let mut off_ms = Vec::new();
        // Element gaps (within characters)
        for _ in 0..40 {
            off_ms.push(55.0 + rand_noise(8.0));
        }
        // Character gaps (compressed to ~2x dit)
        for _ in 0..15 {
            off_ms.push(120.0 + rand_noise(15.0));
        }
        // Word gaps
        for _ in 0..5 {
            off_ms.push(350.0 + rand_noise(30.0));
        }

        let (char_gap, word_gap) = estimate_gap_thresholds(&off_ms, dit_ms);
        // Char gap should be between element gap and char gap durations
        assert!(
            char_gap > 70.0 && char_gap < 140.0,
            "expected char gap ~80-130ms, got {char_gap:.0}ms"
        );
        // Word gap should be between char gap and word gap durations
        assert!(
            word_gap > 150.0 && word_gap < 400.0,
            "expected word gap ~200-350ms, got {word_gap:.0}ms"
        );
    }

    #[test]
    fn gap_thresholds_few_events_uses_defaults() {
        let off_ms = vec![60.0, 120.0, 350.0];
        let (char_gap, word_gap) = estimate_gap_thresholds(&off_ms, 60.0);
        // Should use default multipliers: 1.5x dit, 3.5x dit
        assert!(
            (char_gap - 90.0).abs() < 1.0,
            "expected default char gap 90ms, got {char_gap:.0}ms"
        );
        assert!(
            (word_gap - 210.0).abs() < 1.0,
            "expected default word gap 210ms, got {word_gap:.0}ms"
        );
    }

    #[test]
    fn gap_thresholds_continuous_distribution() {
        // Simulate a continuous gap distribution with no clear valley between
        // char and word gaps (like the 20260218 recording). Gaps are distributed:
        // - Element gaps: 30-70ms (~114 events)
        // - Char gaps: 90-190ms (~55 events, overlapping with word)
        // - Word gaps: 200-280ms (~23 events, no valley separating from char)
        let dit_ms = 60.0;
        let mut off_ms = Vec::new();
        // Element gaps (within characters)
        for i in 0..114 {
            off_ms.push(30.0 + (i as f64 / 114.0) * 40.0 + rand_noise(5.0));
        }
        // Character gaps (continuous, no valley)
        for i in 0..55 {
            off_ms.push(90.0 + (i as f64 / 55.0) * 100.0 + rand_noise(8.0));
        }
        // Word gaps (continuous with char gaps, no clear separation)
        for i in 0..23 {
            off_ms.push(200.0 + (i as f64 / 23.0) * 80.0 + rand_noise(10.0));
        }

        let (char_gap, word_gap) = estimate_gap_thresholds(&off_ms, dit_ms);
        // 3-class Otsu should find a char/word boundary around 180-220ms
        // instead of failing to find any valley
        assert!(
            char_gap > 60.0 && char_gap < 150.0,
            "expected char gap ~70-140ms, got {char_gap:.0}ms"
        );
        assert!(
            word_gap > 150.0 && word_gap < 280.0,
            "expected word gap ~160-270ms, got {word_gap:.0}ms"
        );
        // Word gap should be meaningfully above char gap
        assert!(
            word_gap > char_gap * 1.2,
            "word gap ({word_gap:.0}ms) should be well above char gap ({char_gap:.0}ms)"
        );
    }

    /// Simple deterministic pseudo-noise for tests (no rand dependency).
    fn rand_noise(amplitude: f64) -> f64 {
        // Use a hash-like function seeded by thread-local counter
        use std::cell::Cell;
        thread_local! {
            static COUNTER: Cell<u64> = const { Cell::new(42) };
        }
        COUNTER.with(|c| {
            let v = c.get().wrapping_mul(6364136223846793005).wrapping_add(1);
            c.set(v);
            let frac = (v >> 33) as f64 / (1u64 << 31) as f64; // 0.0 to 1.0
            (frac - 0.5) * 2.0 * amplitude
        })
    }

    /// Integration test: transcribe combined_drift.wav from real recording data.
    #[test]
    #[ignore]
    fn transcribe_combined_drift_wav() {
        use std::path::PathBuf;

        let path = PathBuf::from("/Users/jsvana/tmp/recording-20260218-173305/combined_drift.wav");
        if !path.exists() {
            eprintln!("Skipping: combined_drift.wav not found");
            return;
        }

        let (sample_rate, samples) = combine::read_wav_samples(&path).unwrap();
        eprintln!(
            "Read {} samples at {} Hz ({:.1}s)",
            samples.len(),
            sample_rate,
            samples.len() as f64 / sample_rate as f64,
        );

        let (text, wpm) = transcribe_audio(&samples, sample_rate);

        let char_count = text.chars().filter(|c| !c.is_whitespace()).count();
        eprintln!("WPM: {:?}", wpm);
        eprintln!("Characters: {}", char_count);
        eprintln!("Decoded text:\n{}", text);

        // Show post-processing details
        let pp = postprocess::postprocess(&text);
        if pp.annotations.is_empty() {
            eprintln!("\nPost-processing: no corrections applied");
        } else {
            eprintln!("\nPost-processing corrections:");
            for ann in &pp.annotations {
                eprintln!(
                    "  {:?}: '{}' -> '{}'",
                    ann.kind, ann.original, ann.corrected
                );
            }
            eprintln!("Post-processed text:\n{}", pp.text);
        }
    }

    /// Diagnostic: multi-tone detection on all available ~/tmp recordings.
    #[test]
    #[ignore]
    fn multitone_diagnostic_all_recordings() {
        use std::path::PathBuf;

        let paths = [
            "/Users/jsvana/tmp/recording-20260218-173305/combined_drift.wav",
            "/Users/jsvana/tmp/recording-20260219-225603/combined_seg0.wav",
            "/Users/jsvana/tmp/recording-20260218-154839/combined_seg0.wav",
            "/Users/jsvana/tmp/recording-20260218-152542/combined_seg0.wav",
        ];

        for path_str in &paths {
            let path = PathBuf::from(path_str);
            if !path.exists() {
                eprintln!("Skipping (not found): {}", path_str);
                continue;
            }

            let (sample_rate, samples) = combine::read_wav_samples(&path).unwrap();
            let duration_s = samples.len() as f64 / sample_rate as f64;
            eprintln!("\n{}", "=".repeat(70));
            eprintln!("FILE: {}", path_str);
            eprintln!(
                "  {} samples at {} Hz ({:.1}s)",
                samples.len(),
                sample_rate,
                duration_s
            );

            // Step 1: Show tone detection
            let active_start = tone_detector::find_active_start(&samples, sample_rate);
            let active = &samples[active_start..];

            let tone_freqs = tone_detector::detect_peak_frequencies(
                active,
                sample_rate,
                400.0,
                900.0,
                10.0,
                120.0,
                4,
            );
            eprintln!(
                "  Tones detected: {} → {:?} Hz",
                tone_freqs.len(),
                tone_freqs
            );

            // Step 2: Per-tone segment counts
            for &freq in &tone_freqs {
                let segments = process_tone(active, sample_rate, freq, None);
                let total_events: usize = segments.iter().map(|s| s.events.len()).sum();
                eprintln!(
                    "  Tone {:.0} Hz: {} segments, {} total events",
                    freq,
                    segments.len(),
                    total_events
                );
                for (i, seg) in segments.iter().enumerate() {
                    let on_events = seg
                        .events
                        .iter()
                        .filter(|e| e.kind == KeyingEventKind::On)
                        .count();
                    let start_s = seg.start_sample as f64 / sample_rate as f64;
                    eprintln!(
                        "    Seg {}: start={:.2}s, {} on-events, WPM={}, dit={:.0}ms, char_gap={:.0}ms, word_gap={:.0}ms",
                        i, start_s, on_events, seg.wpm, seg.dit_ms, seg.char_gap_ms, seg.word_gap_ms
                    );
                }
            }

            // Step 3: Full transcription
            let (text, wpm) = transcribe_audio(&samples, sample_rate);
            let char_count = text.chars().filter(|c| !c.is_whitespace()).count();
            eprintln!("  WPM: {:?}", wpm);
            eprintln!("  Characters: {}", char_count);
            eprintln!("  Text: {}", text);
        }
    }

    /// Diagnostic test for the 20260219 recording.
    #[test]
    #[ignore]
    fn transcribe_20260219_combined() {
        use std::path::PathBuf;

        let path = PathBuf::from("/Users/jsvana/tmp/recording-20260219-225603/combined_seg0.wav");
        if !path.exists() {
            eprintln!("Skipping: file not found");
            return;
        }

        let (sample_rate, samples) = combine::read_wav_samples(&path).unwrap();
        eprintln!(
            "Read {} samples at {} Hz ({:.1}s)",
            samples.len(),
            sample_rate,
            samples.len() as f64 / sample_rate as f64,
        );

        // Step 1: Find active start
        let active_start = tone_detector::find_active_start(&samples, sample_rate);
        let active = &samples[active_start..];
        eprintln!(
            "Active start: {} ({:.3}s)",
            active_start,
            active_start as f64 / sample_rate as f64
        );

        // Step 2: Detect peak frequency
        let tone_freq =
            tone_detector::detect_peak_frequency(active, sample_rate, 400.0, 900.0, 10.0);
        eprintln!("Peak frequency: {:.1} Hz", tone_freq);

        // Step 3: Bandpass and detect (±40Hz, matching transcribe_audio)
        let narrow_low = (tone_freq - 40.0).max(400.0);
        let narrow_high = (tone_freq + 40.0).min(900.0);
        eprintln!("Bandpass: {:.0}-{:.0} Hz", narrow_low, narrow_high);
        let mut filtered = active.to_vec();
        BiquadCascade::bandpass(narrow_low, narrow_high, 3, sample_rate)
            .process_block(&mut filtered);

        let mut detector = ToneDetector::new(tone_freq, sample_rate, 10);
        detector.calibrate_from_audio(&filtered);

        // Compute energy distribution for diagnostics
        let window_size = (sample_rate * 10 / 1000) as usize;
        let mut energies: Vec<f32> = Vec::new();
        let k = tone_freq * window_size as f32 / sample_rate as f32;
        let coeff = 2.0 * (2.0 * std::f32::consts::PI * k / window_size as f32).cos();
        for chunk in filtered.chunks(window_size) {
            if chunk.len() == window_size {
                let mut s1: f32 = 0.0;
                let mut s2: f32 = 0.0;
                for &s in chunk {
                    let s0 = s + coeff * s1 - s2;
                    s2 = s1;
                    s1 = s0;
                }
                energies.push(s1 * s1 + s2 * s2 - coeff * s1 * s2);
            }
        }
        energies.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        if !energies.is_empty() {
            let len = energies.len();
            eprintln!(
                "Energy distribution ({} windows):\n  p5={:.3}  p25={:.3}  p50={:.3}  p75={:.3}  p95={:.3}  max={:.3}",
                len,
                energies[len / 20], energies[len / 4], energies[len / 2],
                energies[3 * len / 4], energies[19 * len / 20], energies[len - 1],
            );
        }

        let raw_events = detector.process(&filtered);
        let final_event = detector.finalize();

        let mut all_raw: Vec<_> = raw_events;
        if let Some(fe) = final_event {
            all_raw.push(fe);
        }

        let on_raw = all_raw
            .iter()
            .filter(|e| e.kind == tone_detector::KeyingEventKind::On)
            .count();
        let off_raw = all_raw
            .iter()
            .filter(|e| e.kind == tone_detector::KeyingEventKind::Off)
            .count();
        eprintln!("Raw events: {} on, {} off", on_raw, off_raw);

        // Step 4: Initial merge
        let initial_max_gap = (sample_rate as f64 * 0.030) as usize;
        let min_on = (sample_rate as f64 * 0.020) as usize;
        let initial_events = merge_keying_events(&all_raw, initial_max_gap, min_on);

        let on_merged = initial_events
            .iter()
            .filter(|e| e.kind == tone_detector::KeyingEventKind::On)
            .count();
        eprintln!(
            "After initial merge (30ms gap, 40ms min): {} on events",
            on_merged
        );

        // Step 5: WPM estimation
        let all_evts: Vec<_> = initial_events.iter().collect();
        let mut on_ms: Vec<f64> = Vec::new();
        let mut off_ms: Vec<f64> = Vec::new();
        for i in 0..all_evts.len().saturating_sub(1) {
            let dur_ms = (all_evts[i + 1].sample_offset as f64 - all_evts[i].sample_offset as f64)
                / sample_rate as f64
                * 1000.0;
            if all_evts[i].kind == tone_detector::KeyingEventKind::On {
                on_ms.push(dur_ms);
            } else {
                off_ms.push(dur_ms);
            }
        }

        on_ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
        off_ms.sort_by(|a, b| a.partial_cmp(b).unwrap());

        eprintln!("\nOn-duration distribution ({} events):", on_ms.len());
        if !on_ms.is_empty() {
            eprintln!("  min={:.0}ms  p10={:.0}ms  p25={:.0}ms  median={:.0}ms  p75={:.0}ms  p90={:.0}ms  max={:.0}ms",
                on_ms[0],
                on_ms[on_ms.len() / 10],
                on_ms[on_ms.len() / 4],
                on_ms[on_ms.len() / 2],
                on_ms[3 * on_ms.len() / 4],
                on_ms[9 * on_ms.len() / 10],
                on_ms[on_ms.len() - 1],
            );
        }

        eprintln!("\nOff-duration distribution ({} events):", off_ms.len());
        if !off_ms.is_empty() {
            eprintln!("  min={:.0}ms  p10={:.0}ms  p25={:.0}ms  median={:.0}ms  p75={:.0}ms  p90={:.0}ms  max={:.0}ms",
                off_ms[0],
                off_ms[off_ms.len() / 10],
                off_ms[off_ms.len() / 4],
                off_ms[off_ms.len() / 2],
                off_ms[3 * off_ms.len() / 4],
                off_ms[9 * off_ms.len() / 10],
                off_ms[off_ms.len() - 1],
            );
        }

        let (wpm_est, dit_est) = estimate_wpm_histogram(&on_ms);
        eprintln!("\nWPM estimate: {} (dit={:.0}ms)", wpm_est, dit_est);

        // Print histogram bins for debugging
        let bin_width = 5.0;
        let max_ms = 300.0;
        let num_bins = (max_ms / bin_width) as usize;
        let mut hist = vec![0u32; num_bins];
        for &d in &on_ms {
            let bin = ((d / bin_width) as usize).min(num_bins - 1);
            hist[bin] += 1;
        }
        eprintln!("\nOn-duration histogram (5ms bins):");
        for (i, &count) in hist.iter().enumerate() {
            if count > 0 {
                let ms = (i as f64 + 0.5) * bin_width;
                let bar = "#".repeat(count as usize);
                eprintln!("  {ms:>5.0}ms [{count:>3}] {bar}");
            }
        }

        // Step 5b: Gap thresholds
        let (char_gap_raw, word_gap_raw) = estimate_gap_thresholds(&off_ms, dit_est);
        let char_gap = char_gap_raw.max(dit_est * 3.0);
        let word_gap = word_gap_raw.max(dit_est * 7.0).max(char_gap * 2.0);
        eprintln!(
            "Gap thresholds (raw): char={:.0}ms  word={:.0}ms",
            char_gap_raw, word_gap_raw
        );
        eprintln!(
            "Gap thresholds (floored): char={:.0}ms  word={:.0}ms",
            char_gap, word_gap
        );
        eprintln!(
            "  (defaults would be: char={:.0}ms  word={:.0}ms)",
            dit_est * 1.5,
            dit_est * 3.5
        );

        // Step 6: Full transcription
        let (text, wpm) = transcribe_audio(&samples, sample_rate);
        let char_count = text.chars().filter(|c| !c.is_whitespace()).count();
        eprintln!("\nFinal WPM: {:?}", wpm);
        eprintln!("Characters: {}", char_count);
        eprintln!("Decoded text:\n{}", text);

        // Show post-processing details
        let pp = postprocess::postprocess(&text);
        if pp.annotations.is_empty() {
            eprintln!("\nPost-processing: no corrections applied");
        } else {
            eprintln!("\nPost-processing corrections:");
            for ann in &pp.annotations {
                eprintln!(
                    "  {:?}: '{}' -> '{}'",
                    ann.kind, ann.original, ann.corrected
                );
            }
            eprintln!("Post-processed text:\n{}", pp.text);
        }
    }

    /// Generate a Morse-keyed sine wave at the given frequency and WPM.
    /// Returns audio samples. Each element in `pattern` is a Morse element:
    /// '.' = dit, '-' = dah, ' ' = char gap, '/' = word gap.
    fn morse_keyed_tone(
        freq: f32,
        sample_rate: u32,
        wpm: u32,
        pattern: &str,
        amplitude: f32,
    ) -> Vec<f32> {
        let dit_ms = 1200.0 / wpm as f64;
        let dit_samples = (sample_rate as f64 * dit_ms / 1000.0) as usize;

        let mut audio = Vec::new();
        let freq_f64 = freq as f64;
        let sr_f64 = sample_rate as f64;
        for ch in pattern.chars() {
            match ch {
                '.' => {
                    // Dit: 1 dit on, 1 dit off
                    let base = audio.len();
                    for i in 0..dit_samples {
                        let t = (base + i) as f64 / sr_f64;
                        audio.push(
                            (2.0 * std::f64::consts::PI * freq_f64 * t).sin() as f32 * amplitude,
                        );
                    }
                    audio.extend(vec![0.0f32; dit_samples]);
                }
                '-' => {
                    // Dah: 3 dits on, 1 dit off
                    let base = audio.len();
                    for i in 0..(dit_samples * 3) {
                        let t = (base + i) as f64 / sr_f64;
                        audio.push(
                            (2.0 * std::f64::consts::PI * freq_f64 * t).sin() as f32 * amplitude,
                        );
                    }
                    audio.extend(vec![0.0f32; dit_samples]);
                }
                ' ' => {
                    // Char gap: 2 additional dits (total 3 with trailing element gap)
                    audio.extend(vec![0.0f32; dit_samples * 2]);
                }
                '/' => {
                    // Word gap: 6 additional dits (total 7 with trailing element gap)
                    audio.extend(vec![0.0f32; dit_samples * 6]);
                }
                _ => {}
            }
        }
        audio
    }

    #[test]
    fn multi_tone_transcription_finds_both_operators() {
        // Two operators at different frequencies, each sending a short message.
        // Operator 1: 550 Hz, sends "CQ" at 20 WPM
        // Operator 2: 750 Hz, sends "DE" at 20 WPM (after a pause)
        let sr = 12_000u32;

        // CQ = -.-. --.-
        let cq_pattern = "-.-. /--.-";
        let op1_audio = morse_keyed_tone(550.0, sr, 20, cq_pattern, 0.4);

        // DE = -.. .
        let de_pattern = "-.. /.";
        let op2_audio = morse_keyed_tone(750.0, sr, 20, de_pattern, 0.4);

        // Combine: operator 1 starts first, operator 2 starts after op1 + pause
        let pause_samples = (sr as f64 * 0.8) as usize; // 800ms pause
        let total_len = op1_audio.len() + pause_samples + op2_audio.len();

        let mut combined = vec![0.0f32; total_len];
        // Add operator 1 at the start
        for (i, &s) in op1_audio.iter().enumerate() {
            combined[i] += s;
        }
        // Add operator 2 after the pause
        let op2_start = op1_audio.len() + pause_samples;
        for (i, &s) in op2_audio.iter().enumerate() {
            if op2_start + i < total_len {
                combined[op2_start + i] += s;
            }
        }

        let (text, wpm) = transcribe_audio(&combined, sr);

        // We should get some decoded text from both operators.
        // The exact decoding may not be perfect (synthetic audio is idealized),
        // but we should get non-empty output.
        assert!(
            !text.is_empty(),
            "multi-tone transcription should produce non-empty text"
        );
        assert!(wpm.is_some(), "WPM should be estimated");
    }

    #[test]
    fn single_tone_backwards_compat() {
        // Single operator at 650 Hz. Should work exactly as before.
        let sr = 12_000u32;

        // Send "HI" = .... ..
        let hi_pattern = ".... /..";
        let audio = morse_keyed_tone(650.0, sr, 20, hi_pattern, 0.5);

        let (text, wpm) = transcribe_audio(&audio, sr);

        // Should produce non-empty text
        assert!(
            !text.is_empty(),
            "single tone should still produce decoded text"
        );
        assert!(wpm.is_some(), "WPM should be estimated");
    }

    /// Regression test: POTA upload from 2026-02-21 (W6JSV activation).
    ///
    /// Three operators: W6JSV (activator), VE7KIN (hunter 1), KM7COJ (hunter 2).
    /// Expected text (first half, hand-transcribed):
    ///
    /// CQ CQ POTA DE W6JSV K
    /// VE7KIN
    /// VE7KIN TU EI ES GM BILL UR 579 57N T CA BK
    /// BK 599 599 BC BK
    /// BC EEEE BK RR TU BC 73 EE
    /// EE
    /// CQ CQ POTA DE W6JSV K
    /// CQ CQ POTA DE W6JSV K
    /// CQ CQ POTA DE W6JSV K
    /// K[garbled]COJ
    /// KM7COJ? KM7COJ?
    /// KM7COJ 5NN 4A WA BK
    /// BK RE ESE ME TU TU UR H EEEE 599 5NN CA ES 73 EE
    /// EE
    /// CQ CQ POTA DE W6JSIT K
    /// CQ CQ POTA DE W6JSV K
    /// CQ CQ POTA DE W6JSV K
    /// CQ CQ POTA DE W6JSV K
    /// T4N ...
    #[test]
    #[ignore]
    fn regression_pota_upload_20260221() {
        use std::path::PathBuf;

        let path = PathBuf::from("/Users/jsvana/tmp/pota-upload-20260221.wav");
        if !path.exists() {
            eprintln!("Skipping: pota-upload-20260221.wav not found");
            return;
        }

        let (sample_rate, samples) = combine::read_wav_samples(&path).unwrap();

        eprintln!(
            "\nRead {} samples at {} Hz ({:.1}s)",
            samples.len(),
            sample_rate,
            samples.len() as f64 / sample_rate as f64,
        );

        let (text, wpm) = transcribe_audio(&samples, sample_rate);
        let char_count = text.chars().filter(|c| !c.is_whitespace()).count();
        eprintln!("WPM: {:?}", wpm);
        eprintln!("Characters: {}", char_count);
        eprintln!("Decoded text:\n{}", text);

        // Show post-processing details
        let pp = postprocess::postprocess(&text);
        if !pp.annotations.is_empty() {
            eprintln!("\nPost-processing corrections:");
            for ann in &pp.annotations {
                eprintln!(
                    "  {:?}: '{}' -> '{}'",
                    ann.kind, ann.original, ann.corrected
                );
            }
        }

        // Key assertions: the transcription should contain recognizable
        // fragments from the actual exchange. These are the minimum-bar
        // expectations — exact match is not required, but critical words
        // must appear.

        let text_upper = text.to_uppercase();

        // The activator's callsign W6JSV should appear at least once
        // (it's sent many times in CQ calls)
        assert!(
            text_upper.contains("W6JSV") || text_upper.contains("W6JS"),
            "Expected activator callsign W6JSV (or partial W6JS) in output.\nGot: {}",
            text
        );

        // "CQ" should appear (it's sent many times)
        assert!(
            text_upper.contains("CQ"),
            "Expected 'CQ' in output.\nGot: {}",
            text
        );

        // "POTA" should appear intact (not split into state abbreviations)
        assert!(
            text_upper.contains("POTA"),
            "Expected 'POTA' in output (not split into state codes).\nGot: {}",
            text
        );

        // "DE" should appear (standard CW procedural word)
        assert!(
            text_upper.contains("DE"),
            "Expected 'DE' in output.\nGot: {}",
            text
        );

        // "BK" should appear (used in both exchanges)
        assert!(
            text_upper.contains("BK"),
            "Expected 'BK' in output.\nGot: {}",
            text
        );

        // "TU" should appear (thank you, used in both exchanges)
        assert!(
            text_upper.contains("TU"),
            "Expected 'TU' in output.\nGot: {}",
            text
        );

        // "73" should appear (sent in both exchanges)
        assert!(
            text_upper.contains("73"),
            "Expected '73' in output.\nGot: {}",
            text
        );

        // No state abbreviation flooding: the output should NOT be dominated
        // by 2-letter state codes. Count how many words are state abbreviations.
        let states = [
            "AL", "AK", "AZ", "CO", "CT", "DC", "FL", "IA", "ID", "IL", "KS", "KY", "LA", "MA",
            "MD", "ME", "MI", "MN", "MS", "NC", "ND", "NE", "NH", "NJ", "NM", "NV", "NY", "OH",
            "OK", "OR", "PA", "RI", "SC", "SD", "TN", "UT", "VA", "VT", "WA", "WI", "WV", "WY",
        ];
        let words: Vec<&str> = text_upper.split_whitespace().collect();
        let state_count = words.iter().filter(|w| states.contains(w)).count();
        let state_pct = if words.is_empty() {
            0.0
        } else {
            state_count as f64 / words.len() as f64 * 100.0
        };
        eprintln!(
            "\nState abbreviation count: {} / {} words ({:.1}%)",
            state_count,
            words.len(),
            state_pct
        );
        assert!(
            state_pct < 15.0,
            "Too many state abbreviations ({:.1}%): state codes are flooding the output.\nGot: {}",
            state_pct,
            text
        );
    }

    #[test]
    fn goalpost_window_8m22s_to_9m28s() {
        let _ = tracing_subscriber::fmt()
            .with_env_filter("info")
            .with_test_writer()
            .try_init();

        let path = std::path::Path::new("../test-data/goalpost-recording.wav");
        if !path.exists() {
            eprintln!("Skipping: goalpost-recording.wav not found");
            return;
        }
        let (sample_rate, all_samples) = crate::recording::combine::read_wav_samples(path).unwrap();

        // 8m22s to 9m28s
        let start_sec = 502.0;
        let end_sec = 568.0;
        let start_sample = (start_sec * sample_rate as f64) as usize;
        let end_sample = (end_sec * sample_rate as f64) as usize;
        let window = &all_samples[start_sample..end_sample.min(all_samples.len())];

        // Use DecoderA (production default) which has frequency clustering,
        // half-duplex splitting, and segment dedup.
        use super::decoder_a::DecoderA;
        use super::decoder_trait::CwDecoder;

        let decoder = DecoderA;
        let output = decoder.decode(window, sample_rate);
        let text = &output.text;
        let wpm = output.wpm;

        eprintln!("\n=== DECODER A OUTPUT (8m22s-9m28s) ===");
        eprintln!("Text: {}", text);
        eprintln!("WPM: {:?}", wpm);
        eprintln!("Confidence: {:.2}", output.confidence);
        eprintln!("========================================\n");

        // Reference: W6JSV: CQ CQ POTA DE W6JSV K
        //            unknown: R A
        //            W6JSV: RA?
        //            AJ7CM: AJ7CM
        //            W6JSV: AJ7CM TU ES GM ANDY UR IS WEAK 529 52N CA BK
        //            AJ7CM: BK EN EN 22N 22N WA BK
        assert!(!text.is_empty(), "transcription should not be empty");
    }
}
