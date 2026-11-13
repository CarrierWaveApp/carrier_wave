use std::path::Path;

use num_complex::Complex;
use rustfft::FftPlanner;

use crate::db::models::SegmentRow;
use crate::error::RecordingError;
use crate::recording::dsp::BiquadCascade;

/// Maximum alignment search range: 1 second at any sample rate.
const MAX_LAG_SECS: f32 = 1.0;

/// Window size for windowed cross-correlation drift estimation.
const DRIFT_WINDOW_SECS: f32 = 5.0;
/// Maximum residual lag search range for drift windows (8.3ms @ 12kHz).
const DRIFT_MAX_LAG: usize = 100;
/// Minimum correlation in a drift window to trust the measurement.
const DRIFT_MIN_CORRELATION: f32 = 0.15;
/// Minimum valid windows for a reliable linear drift fit.
const DRIFT_MIN_WINDOWS: usize = 3;
/// Minimum drift rate (samples/sec) to bother resampling (~4 ppm @ 12kHz).
const DRIFT_MIN_RATE: f32 = 0.05;

/// Read a WAV file produced by FlacWriter, returning (sample_rate, f32 samples).
///
/// Expects the standard 44-byte header: RIFF/WAVE/fmt(16 bytes)/data.
/// Only 16-bit PCM mono is supported.
pub fn read_wav_samples(path: &Path) -> Result<(u32, Vec<f32>), RecordingError> {
    let data = std::fs::read(path)?;

    if data.len() < 44 {
        return Err(RecordingError::Incompatible(format!(
            "WAV file too small: {} bytes",
            data.len()
        )));
    }

    // Validate RIFF + WAVE magic
    if &data[0..4] != b"RIFF" || &data[8..12] != b"WAVE" {
        return Err(RecordingError::Incompatible(format!(
            "not a WAV file: {}",
            path.display()
        )));
    }

    // Extract sample rate from fmt chunk (bytes 24..28)
    let sample_rate = u32::from_le_bytes([data[24], data[25], data[26], data[27]]);

    // Verify mono 16-bit PCM
    let channels = u16::from_le_bytes([data[22], data[23]]);
    let bits_per_sample = u16::from_le_bytes([data[34], data[35]]);
    if channels != 1 || bits_per_sample != 16 {
        return Err(RecordingError::Incompatible(format!(
            "unsupported WAV format: {} channels, {} bits (need mono 16-bit)",
            channels, bits_per_sample
        )));
    }

    // Extract data size from bytes 40..44
    let data_size = u32::from_le_bytes([data[40], data[41], data[42], data[43]]) as usize;
    let num_samples = data_size / 2;

    let audio_start = 44;
    let available = (data.len() - audio_start) / 2;
    let count = num_samples.min(available);

    let mut samples = Vec::with_capacity(count);
    for i in 0..count {
        let offset = audio_start + i * 2;
        let i16_val = i16::from_le_bytes([data[offset], data[offset + 1]]);
        samples.push(i16_val as f32 / 32768.0);
    }

    Ok((sample_rate, samples))
}

/// Read and concatenate all segment WAV files for one recording into a flat buffer.
/// Returns (sample_rate, samples). All segments must share the same sample rate.
pub fn read_recording_audio(segments: &[SegmentRow]) -> Result<(u32, Vec<f32>), RecordingError> {
    if segments.is_empty() {
        return Err(RecordingError::Incompatible(
            "recording has no segments".into(),
        ));
    }

    let mut all_samples = Vec::new();
    let mut rate: Option<u32> = None;

    for seg in segments {
        let (sr, samples) = read_wav_samples(Path::new(&seg.file_path))?;
        match rate {
            None => rate = Some(sr),
            Some(r) if r != sr => {
                return Err(RecordingError::Incompatible(format!(
                    "segment sample rate mismatch: expected {r}, got {sr}"
                )));
            }
            _ => {}
        }
        all_samples.extend_from_slice(&samples);
    }

    Ok((rate.unwrap(), all_samples))
}

/// Average multiple audio buffers sample-by-sample.
/// Uses the minimum length across sources (trims to shortest).
pub fn average_samples(sources: &[Vec<f32>]) -> Vec<f32> {
    if sources.is_empty() {
        return Vec::new();
    }

    let min_len = sources.iter().map(|s| s.len()).min().unwrap_or(0);
    let n = sources.len() as f32;

    let mut output = vec![0.0f32; min_len];
    for source in sources {
        for (i, &s) in source.iter().enumerate().take(min_len) {
            output[i] += s;
        }
    }
    for sample in &mut output {
        *sample /= n;
    }

    output
}

/// Correlation-weighted average of variable-length audio buffers.
///
/// Unlike [`average_samples`], this function:
/// - Uses the **maximum** length (no data lost to the shortest source)
/// - Weights each source by its quality (e.g. Pearson correlation with reference)
/// - When `onsets` is provided, sources before their signal onset contribute
///   nothing (neither signal nor weight), preventing silence-padded regions
///   from diluting the average.
///
/// At each sample position, computes `Σ(w_k * source_k[i]) / Σ(w_k)` over
/// sources that have data at position `i` and are past their onset. Sources
/// that end early or haven't started yet simply don't contribute.
pub fn weighted_average_samples(
    sources: &[Vec<f32>],
    weights: &[f32],
    onsets: Option<&[usize]>,
) -> Vec<f32> {
    if sources.is_empty() {
        return Vec::new();
    }

    let max_len = sources.iter().map(|s| s.len()).max().unwrap_or(0);
    let mut output = vec![0.0f32; max_len];
    let mut weight_sums = vec![0.0f32; max_len];

    for (idx, (source, &w)) in sources.iter().zip(weights.iter()).enumerate() {
        let onset = onsets.map_or(0, |o| o.get(idx).copied().unwrap_or(0));
        for (i, &s) in source.iter().enumerate() {
            if i >= onset {
                output[i] += w * s;
                weight_sums[i] += w;
            }
        }
    }

    for i in 0..max_len {
        if weight_sums[i] > 1e-10 {
            output[i] /= weight_sums[i];
        }
    }

    output
}

/// Trimmed-mean average of variable-length audio buffers.
///
/// At each sample position: collects contributing values (sources past their
/// onset that have data), sorts them, drops the top and bottom `trim_fraction`
/// (e.g. 0.20 = drop 20% from each end), and averages the middle.
///
/// This rejects outlier spikes/drops from individual receivers while
/// preserving the common signal. With 5 sources and 20% trim, the strongest
/// and weakest sample at each position are discarded.
///
/// Falls back to simple mean if fewer than 3 sources contribute at a position
/// (trimming would discard too much).
pub fn trimmed_mean_samples(
    sources: &[Vec<f32>],
    onsets: Option<&[usize]>,
    trim_fraction: f32,
) -> Vec<f32> {
    if sources.is_empty() {
        return Vec::new();
    }

    let max_len = sources.iter().map(|s| s.len()).max().unwrap_or(0);
    let mut output = vec![0.0f32; max_len];
    let mut sample_buf: Vec<f32> = Vec::with_capacity(sources.len());

    for i in 0..max_len {
        sample_buf.clear();
        for (idx, source) in sources.iter().enumerate() {
            let onset = onsets.map_or(0, |o| o.get(idx).copied().unwrap_or(0));
            if i >= onset && i < source.len() {
                sample_buf.push(source[i]);
            }
        }

        if sample_buf.is_empty() {
            continue;
        }

        if sample_buf.len() < 3 {
            // Too few sources to trim meaningfully — simple mean
            output[i] = sample_buf.iter().sum::<f32>() / sample_buf.len() as f32;
            continue;
        }

        sample_buf.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let n = sample_buf.len();
        let trim_count = ((n as f32 * trim_fraction).floor() as usize).max(0);
        let start = trim_count;
        let end = n - trim_count;

        if start >= end {
            // Edge case: over-trimmed, just use median
            output[i] = sample_buf[n / 2];
        } else {
            let sum: f32 = sample_buf[start..end].iter().sum();
            output[i] = sum / (end - start) as f32;
        }
    }

    output
}

/// Compute correlation-based weights for combining.
///
/// Returns a weight for each source: the reference gets 1.0, others get their
/// Pearson correlation with the reference (clamped to 0.0 — negative correlation
/// means the source would subtract from the signal).
pub fn compute_source_weights(sources: &[Vec<f32>], ref_idx: usize) -> Vec<f32> {
    sources
        .iter()
        .enumerate()
        .map(|(i, source)| {
            if i == ref_idx {
                1.0
            } else {
                let min_len = sources[ref_idx].len().min(source.len());
                if min_len == 0 {
                    return 0.0;
                }
                pearson_correlation(&sources[ref_idx][..min_len], &source[..min_len]).max(0.0)
            }
        })
        .collect()
}

// --- Time-varying source weights ---

/// Window size in seconds for per-window correlation estimation.
const WEIGHT_WINDOW_SECS: f32 = 2.0;
/// Hop size in seconds (50% overlap for smooth transitions).
const WEIGHT_HOP_SECS: f32 = 1.0;
/// Minimum per-window correlation to receive non-zero weight.
const MIN_WINDOW_CORRELATION: f32 = 0.1;
/// Minimum interpolated weight for a source to be included in trimmed mean.
pub const MIN_INCLUDE_WEIGHT: f32 = 0.15;

/// Per-window quality weights for time-varying source combining.
///
/// Each window stores a weight per source based on that window's correlation
/// with the reference. `weight_at()` linearly interpolates between adjacent
/// windows for smooth cross-fades at window boundaries.
pub struct WindowedWeights {
    /// weights\[window_idx\]\[source_idx\]
    weights: Vec<Vec<f32>>,
    /// Number of samples per window.
    window_samples: usize,
    /// Number of samples per hop.
    hop_samples: usize,
    /// Number of sources.
    num_sources: usize,
}

impl WindowedWeights {
    /// Number of analysis windows.
    pub fn num_windows(&self) -> usize {
        self.weights.len()
    }

    /// Get the raw weight for a source in a specific window.
    pub fn window_weight(&self, window_idx: usize, source_idx: usize) -> f32 {
        self.weights
            .get(window_idx)
            .and_then(|w| w.get(source_idx))
            .copied()
            .unwrap_or(0.0)
    }

    /// Get the interpolated weight for `source_idx` at `sample_pos`.
    ///
    /// Linearly interpolates between adjacent window centers for smooth
    /// cross-fade. Returns 0.0 for out-of-range positions.
    pub fn weight_at(&self, source_idx: usize, sample_pos: usize) -> f32 {
        if self.weights.is_empty() || source_idx >= self.num_sources {
            return 0.0;
        }

        if self.weights.len() == 1 {
            return self.weights[0][source_idx];
        }

        // Window centers are at hop_samples/2, hop_samples*3/2, hop_samples*5/2, ...
        // i.e., center[w] = w * hop_samples + window_samples / 2
        // For interpolation, we use hop-based fractional index:
        let center_offset = self.window_samples / 2;
        if sample_pos < center_offset {
            return self.weights[0][source_idx];
        }

        let pos_from_first_center = sample_pos - center_offset;
        let frac_idx = pos_from_first_center as f32 / self.hop_samples as f32;
        let w_lo = frac_idx.floor() as usize;
        let w_hi = w_lo + 1;
        let frac = frac_idx - w_lo as f32;

        if w_hi >= self.weights.len() {
            return self.weights.last().unwrap()[source_idx];
        }

        let lo = self.weights[w_lo][source_idx];
        let hi = self.weights[w_hi][source_idx];
        lo * (1.0 - frac) + hi * frac
    }
}

/// Compute per-window correlation weights for each source against the reference.
///
/// For each 2-second window (1-second hop), computes Pearson correlation of each
/// source against the reference. Negative correlations are clamped to 0, and
/// correlations below `MIN_WINDOW_CORRELATION` are set to 0. The reference
/// always gets weight 1.0.
///
/// For recordings shorter than one window, returns a single window.
pub fn compute_windowed_weights(
    sources: &[Vec<f32>],
    ref_idx: usize,
    sample_rate: u32,
) -> WindowedWeights {
    let window_samples = (WEIGHT_WINDOW_SECS * sample_rate as f32) as usize;
    let hop_samples = (WEIGHT_HOP_SECS * sample_rate as f32) as usize;
    let num_sources = sources.len();

    if num_sources == 0 {
        return WindowedWeights {
            weights: Vec::new(),
            window_samples,
            hop_samples,
            num_sources: 0,
        };
    }

    let max_len = sources.iter().map(|s| s.len()).max().unwrap_or(0);

    // Single window for short recordings
    if max_len <= window_samples {
        let global = compute_source_weights(sources, ref_idx);
        return WindowedWeights {
            weights: vec![global],
            window_samples: max_len.max(1),
            hop_samples: max_len.max(1),
            num_sources,
        };
    }

    let mut all_weights: Vec<Vec<f32>> = Vec::new();
    let mut start = 0;

    while start + window_samples <= max_len {
        let end = start + window_samples;
        let ref_end = end.min(sources[ref_idx].len());
        if ref_end <= start {
            // Reference source has no data in this window; skip
            start += hop_samples;
            continue;
        }
        let ref_window = &sources[ref_idx][start..ref_end];

        let mut window_weights = vec![0.0f32; num_sources];
        for (i, source) in sources.iter().enumerate() {
            if i == ref_idx {
                window_weights[i] = 1.0;
            } else {
                let src_end = end.min(source.len());
                if src_end <= start {
                    // Source has no data in this window
                    window_weights[i] = 0.0;
                } else {
                    let src_window = &source[start..src_end];
                    let min_len = ref_window.len().min(src_window.len());
                    if min_len < 100 {
                        window_weights[i] = 0.0;
                    } else {
                        let corr =
                            pearson_correlation(&ref_window[..min_len], &src_window[..min_len]);
                        let clamped = corr.max(0.0);
                        window_weights[i] = if clamped < MIN_WINDOW_CORRELATION {
                            0.0
                        } else {
                            clamped
                        };
                    }
                }
            }
        }
        all_weights.push(window_weights);
        start += hop_samples;
    }

    // Handle tail: if there's remaining data past the last full window,
    // add one final window covering the end
    if all_weights.is_empty() {
        let global = compute_source_weights(sources, ref_idx);
        all_weights.push(global);
    }

    WindowedWeights {
        weights: all_weights,
        window_samples,
        hop_samples,
        num_sources,
    }
}

/// Trimmed-mean average with per-window quality gating.
///
/// Like [`trimmed_mean_samples`] but before including a source at position `i`,
/// checks that `windowed_weights.weight_at(idx, i) >= min_include_weight`.
/// Sources below this weight in the current window are excluded from the
/// trimmed mean, preventing degraded sources from contaminating the output.
pub fn windowed_trimmed_mean_samples(
    sources: &[Vec<f32>],
    onsets: Option<&[usize]>,
    trim_fraction: f32,
    windowed_weights: &WindowedWeights,
    min_include_weight: f32,
) -> Vec<f32> {
    if sources.is_empty() {
        return Vec::new();
    }

    let max_len = sources.iter().map(|s| s.len()).max().unwrap_or(0);
    let mut output = vec![0.0f32; max_len];
    let mut sample_buf: Vec<f32> = Vec::with_capacity(sources.len());

    for i in 0..max_len {
        sample_buf.clear();
        for (idx, source) in sources.iter().enumerate() {
            let onset = onsets.map_or(0, |o| o.get(idx).copied().unwrap_or(0));
            if i >= onset && i < source.len() {
                let w = windowed_weights.weight_at(idx, i);
                if w >= min_include_weight {
                    sample_buf.push(source[i]);
                }
            }
        }

        if sample_buf.is_empty() {
            // Fall back: include all available sources regardless of weight
            for (idx, source) in sources.iter().enumerate() {
                let onset = onsets.map_or(0, |o| o.get(idx).copied().unwrap_or(0));
                if i >= onset && i < source.len() {
                    sample_buf.push(source[i]);
                }
            }
        }

        if sample_buf.is_empty() {
            continue;
        }

        if sample_buf.len() < 3 {
            output[i] = sample_buf.iter().sum::<f32>() / sample_buf.len() as f32;
            continue;
        }

        sample_buf.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let n = sample_buf.len();
        let trim_count = (n as f32 * trim_fraction).floor() as usize;
        let start = trim_count;
        let end = n - trim_count;

        if start >= end {
            output[i] = sample_buf[n / 2];
        } else {
            let sum: f32 = sample_buf[start..end].iter().sum();
            output[i] = sum / (end - start) as f32;
        }
    }

    output
}

/// Correlation-weighted average with per-window weights.
///
/// Like [`weighted_average_samples`] but uses `windowed_weights.weight_at(idx, i)`
/// instead of a single global weight per source. This allows the contribution
/// of each source to vary over time as signal quality changes.
pub fn windowed_weighted_average_samples(
    sources: &[Vec<f32>],
    windowed_weights: &WindowedWeights,
    onsets: Option<&[usize]>,
) -> Vec<f32> {
    if sources.is_empty() {
        return Vec::new();
    }

    let max_len = sources.iter().map(|s| s.len()).max().unwrap_or(0);
    let mut output = vec![0.0f32; max_len];
    let mut weight_sums = vec![0.0f32; max_len];

    for (idx, source) in sources.iter().enumerate() {
        let onset = onsets.map_or(0, |o| o.get(idx).copied().unwrap_or(0));
        for (i, &s) in source.iter().enumerate() {
            if i >= onset {
                let w = windowed_weights.weight_at(idx, i);
                output[i] += w * s;
                weight_sums[i] += w;
            }
        }
    }

    for i in 0..max_len {
        if weight_sums[i] > 1e-10 {
            output[i] /= weight_sums[i];
        }
    }

    output
}

/// Apply a steep bandpass filter to audio samples in-place.
/// Uses a cascaded biquad (3rd-order per edge = 18 dB/oct rolloff).
pub fn bandpass_filter(samples: &mut [f32], low_hz: f32, high_hz: f32, sample_rate: u32) {
    let mut filter = BiquadCascade::bandpass(low_hz, high_hz, 3, sample_rate);
    filter.process_block(samples);
}

/// Peak-normalize audio samples so the loudest sample reaches `target_peak`.
/// This amplifies the CW signal (400-900 Hz) after bandpass + averaging,
/// making weak signals audible without clipping.
///
/// Returns the gain factor applied (useful for logging). Returns 1.0 if the
/// signal is silent (avoids divide-by-zero).
pub fn normalize_audio(samples: &mut [f32], target_peak: f32) -> f32 {
    let peak = samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);

    if peak < 1e-10 {
        return 1.0;
    }

    let gain = target_peak / peak;
    for s in samples.iter_mut() {
        *s *= gain;
    }
    gain
}

// --- Cross-correlation time alignment ---

/// Detect the sample index where signal begins in a source audio buffer.
///
/// Uses RMS energy in 50ms windows. Signal onset is the first window where
/// RMS exceeds 3× the minimum-RMS window. This identifies the end of
/// reference-time alignment padding (leading zeros) without being fooled
/// by filter ringing or low-level noise.
///
/// Returns 0 if no clear onset boundary is found (signal starts immediately).
pub fn detect_signal_onset(samples: &[f32], sample_rate: u32) -> usize {
    let window_size = (sample_rate as usize) / 20; // 50ms
    if window_size == 0 || samples.len() < window_size {
        return 0;
    }

    let rms_values: Vec<f32> = samples
        .chunks(window_size)
        .filter(|chunk| chunk.len() == window_size)
        .map(|chunk| (chunk.iter().map(|s| s * s).sum::<f32>() / chunk.len() as f32).sqrt())
        .collect();

    if rms_values.is_empty() {
        return 0;
    }

    let min_rms = rms_values.iter().cloned().fold(f32::MAX, f32::min);

    // If minimum RMS is near-zero (digital silence from reference-time padding),
    // use a small absolute threshold so any real signal qualifies as onset.
    let threshold = if min_rms < 1e-6 { 1e-6 } else { min_rms * 3.0 };

    for (i, &rms) in rms_values.iter().enumerate() {
        if rms > threshold {
            return i * window_size;
        }
    }

    0
}

/// One windowed cross-correlation measurement for drift estimation.
#[derive(Debug, Clone)]
pub struct WindowedLag {
    /// Center time of the window in seconds.
    pub time_sec: f32,
    /// Residual lag after global alignment (in samples).
    pub residual_lag: i32,
    /// Peak cross-correlation for this window.
    pub correlation: f32,
}

/// Diagnostic info for one aligned source.
#[derive(Debug, Clone)]
pub struct AlignmentInfo {
    /// Index in the original source list.
    pub source_index: usize,
    /// Lag in samples (positive = source was late, shifted left).
    pub lag_samples: i32,
    /// Lag in milliseconds.
    pub lag_ms: f32,
    /// Peak cross-correlation value (0..1 range after normalization).
    pub correlation_peak: f32,
    /// Clock drift rate in samples/sec, None if not estimated.
    pub drift_rate: Option<f32>,
    /// Clock drift in parts-per-million, None if not estimated.
    pub drift_ppm: Option<f32>,
    /// Whether drift resampling was applied to this source.
    pub drift_corrected: bool,
}

/// Find the lag (in samples) that best aligns `source` to `reference` using
/// FFT-based cross-correlation. Returns `(lag, peak_correlation)`.
///
/// A positive lag means `source` is delayed relative to `reference` by that
/// many samples. The search is limited to ±`max_lag` samples.
pub fn find_lag(reference: &[f32], source: &[f32], max_lag: usize) -> (i32, f32) {
    let n_ref = reference.len();
    let n_src = source.len();
    if n_ref == 0 || n_src == 0 {
        return (0, 0.0);
    }

    // Linear (non-circular) correlation requires zero-padding to at least n_ref + n_src - 1
    let conv_len = n_ref + n_src - 1;
    let fft_len = conv_len.next_power_of_two();

    let mut planner = FftPlanner::<f32>::new();
    let fft_fwd = planner.plan_fft_forward(fft_len);
    let fft_inv = planner.plan_fft_inverse(fft_len);

    // Pack reference into complex buffer, zero-padded
    let mut ref_freq: Vec<Complex<f32>> = reference
        .iter()
        .map(|&s| Complex::new(s, 0.0))
        .chain(std::iter::repeat(Complex::new(0.0, 0.0)))
        .take(fft_len)
        .collect();

    // Pack source into complex buffer, zero-padded
    let mut src_freq: Vec<Complex<f32>> = source
        .iter()
        .map(|&s| Complex::new(s, 0.0))
        .chain(std::iter::repeat(Complex::new(0.0, 0.0)))
        .take(fft_len)
        .collect();

    fft_fwd.process(&mut ref_freq);
    fft_fwd.process(&mut src_freq);

    // Cross-power spectrum: FFT(src) · conj(FFT(ref))
    // This gives c[k] = sum_n src[n] * ref[n-k], which peaks at positive k
    // when source is delayed by k samples relative to reference.
    let mut cross: Vec<Complex<f32>> = src_freq
        .iter()
        .zip(ref_freq.iter())
        .map(|(s, r)| s * r.conj())
        .collect();

    fft_inv.process(&mut cross);

    // Normalize by fft_len (rustfft doesn't normalize IFFT)
    let scale = 1.0 / fft_len as f32;

    // Compute energy norms for normalization
    let energy_ref: f32 = reference.iter().map(|s| s * s).sum();
    let energy_src: f32 = source.iter().map(|s| s * s).sum();
    let norm = (energy_ref * energy_src).sqrt();

    if norm < 1e-10 {
        return (0, 0.0);
    }

    // The cross-correlation result is indexed as:
    //   index 0         → lag 0 (source is aligned)
    //   index 1..n_src  → lag +1..+n_src (source is delayed)
    //   index fft_len-n_ref+1..fft_len → lag -(n_ref-1)..−1 (source is early)
    //
    // We search within ±max_lag.
    let max_lag = max_lag
        .min(n_ref.saturating_sub(1))
        .min(n_src.saturating_sub(1));

    let mut best_lag: i32 = 0;
    let mut best_val: f32 = f32::NEG_INFINITY;

    // Positive lags (source delayed): indices 0..=max_lag
    for (lag, c) in cross.iter().enumerate().take(max_lag + 1) {
        let val = c.re * scale / norm;
        if val > best_val {
            best_val = val;
            best_lag = lag as i32;
        }
    }

    // Negative lags (source early): indices fft_len-max_lag..fft_len
    for neg in 1..=max_lag {
        let idx = fft_len - neg;
        let val = cross[idx].re * scale / norm;
        if val > best_val {
            best_val = val;
            best_lag = -(neg as i32);
        }
    }

    (best_lag, best_val)
}

/// Align multiple audio sources using onset-aware cross-correlation.
///
/// Sources often have leading silence from reference-time alignment padding
/// (3-19 seconds of zeros). This function detects each source's signal onset,
/// runs cross-correlation only on the signal-bearing portions (avoiding
/// dilution from silence), then computes the total shift as
/// `onset_difference + fine_lag`.
///
/// Picks the source with highest RMS energy (of the signal portion) as the
/// reference. Returns the (shifted sources, alignment diagnostics).
pub fn align_sources(
    sources: Vec<Vec<f32>>,
    sample_rate: u32,
) -> (Vec<Vec<f32>>, Vec<AlignmentInfo>) {
    if sources.len() < 2 {
        let info: Vec<AlignmentInfo> = sources
            .iter()
            .enumerate()
            .map(|(i, _)| AlignmentInfo {
                source_index: i,
                lag_samples: 0,
                lag_ms: 0.0,
                correlation_peak: 1.0,
                drift_rate: None,
                drift_ppm: None,
                drift_corrected: false,
            })
            .collect();
        return (sources, info);
    }

    let max_lag = (MAX_LAG_SECS * sample_rate as f32) as usize;

    // Detect signal onset for each source (skip leading silence/padding).
    let onsets: Vec<usize> = sources
        .iter()
        .map(|s| detect_signal_onset(s, sample_rate))
        .collect();

    // Pick reference: highest-RMS signal portion that has temporal structure.
    // Use signal portions (from onset) for both RMS and CV evaluation.
    let ref_idx = sources
        .iter()
        .enumerate()
        .filter(|(i, _)| {
            let signal = &sources[*i][onsets[*i]..];
            envelope_cv(signal, sample_rate) >= MIN_REFERENCE_CV
        })
        .max_by(|(i, _), (j, _)| {
            let a = &sources[*i][onsets[*i]..];
            let b = &sources[*j][onsets[*j]..];
            rms_energy(a)
                .partial_cmp(&rms_energy(b))
                .unwrap_or(std::cmp::Ordering::Equal)
        })
        .map(|(i, _)| i)
        .unwrap_or_else(|| {
            // No source has enough envelope variation — fall back to highest RMS
            sources
                .iter()
                .enumerate()
                .max_by(|(i, _), (j, _)| {
                    let a = &sources[*i][onsets[*i]..];
                    let b = &sources[*j][onsets[*j]..];
                    rms_energy(a)
                        .partial_cmp(&rms_energy(b))
                        .unwrap_or(std::cmp::Ordering::Equal)
                })
                .map(|(i, _)| i)
                .unwrap_or(0)
        });

    // Cross-correlate signal-bearing portions only, then compute total lag
    // as onset_difference + fine_lag.
    let ref_signal = &sources[ref_idx][onsets[ref_idx]..];
    let mut lags: Vec<(i32, f32)> = Vec::with_capacity(sources.len());
    for (i, source) in sources.iter().enumerate() {
        if i == ref_idx {
            lags.push((0, 1.0));
        } else {
            let src_signal = &source[onsets[i]..];
            if src_signal.is_empty() {
                // Source is all silence — assign zero lag, let quality filter handle it
                lags.push((0, 0.0));
            } else {
                let (fine_lag, corr) = find_lag(ref_signal, src_signal, max_lag);
                let onset_diff = onsets[i] as i32 - onsets[ref_idx] as i32;
                lags.push((onset_diff + fine_lag, corr));
            }
        }
    }

    // Build alignment info
    let info: Vec<AlignmentInfo> = lags
        .iter()
        .enumerate()
        .map(|(i, &(lag, corr))| AlignmentInfo {
            source_index: i,
            lag_samples: lag,
            lag_ms: lag as f32 * 1000.0 / sample_rate as f32,
            correlation_peak: corr,
            drift_rate: None,
            drift_ppm: None,
            drift_corrected: false,
        })
        .collect();

    // Apply shifts: positive lag means source is delayed, so trim from start.
    // Negative lag means source is early, so pad zeros at start.
    let shifted: Vec<Vec<f32>> = sources
        .into_iter()
        .zip(lags.iter())
        .map(|(source, &(lag, _))| {
            if lag > 0 {
                // Source was late — trim `lag` samples from the start
                let skip = (lag as usize).min(source.len());
                source[skip..].to_vec()
            } else if lag < 0 {
                // Source was early — prepend zeros
                let pad = (-lag) as usize;
                let mut shifted = vec![0.0f32; pad];
                shifted.extend_from_slice(&source);
                shifted
            } else {
                source
            }
        })
        .collect();

    (shifted, info)
}

// --- Clock drift correction ---

/// Least-squares linear fit: y = intercept + slope * x.
/// Returns `(intercept, slope)`.
pub fn linear_fit(points: &[(f32, f32)]) -> (f32, f32) {
    let n = points.len() as f32;
    if points.len() < 2 {
        return (0.0, 0.0);
    }

    let mean_x = points.iter().map(|(x, _)| x).sum::<f32>() / n;
    let mean_y = points.iter().map(|(_, y)| y).sum::<f32>() / n;

    let mut cov_xy = 0.0f32;
    let mut var_x = 0.0f32;
    for &(x, y) in points {
        let dx = x - mean_x;
        cov_xy += dx * (y - mean_y);
        var_x += dx * dx;
    }

    if var_x < 1e-10 {
        return (mean_y, 0.0);
    }

    let slope = cov_xy / var_x;
    let intercept = mean_y - slope * mean_x;
    (intercept, slope)
}

/// Resample audio using linear interpolation at the given ratio.
///
/// For each output sample `i`, reads from input position `i * ratio`.
/// Output length = `floor(input.len() / ratio)`.
/// When ratio = 1.0, this is (approximately) identity.
pub fn resample_linear(input: &[f32], ratio: f64) -> Vec<f32> {
    if input.is_empty() || ratio <= 0.0 {
        return Vec::new();
    }

    let output_len = (input.len() as f64 / ratio).floor() as usize;
    let mut output = Vec::with_capacity(output_len);

    for i in 0..output_len {
        let pos = i as f64 * ratio;
        let idx = pos as usize;
        let frac = (pos - idx as f64) as f32;

        let sample = if idx + 1 < input.len() {
            input[idx] * (1.0 - frac) + input[idx + 1] * frac
        } else if idx < input.len() {
            input[idx]
        } else {
            0.0
        };
        output.push(sample);
    }

    output
}

/// Estimate clock drift between two globally-aligned signals using
/// windowed cross-correlation + linear fit.
///
/// Returns `(drift_rate_samples_per_sec, window_measurements)` or `None`
/// if there aren't enough valid windows for a reliable estimate.
fn estimate_drift(
    reference: &[f32],
    source: &[f32],
    sample_rate: u32,
) -> Option<(f32, Vec<WindowedLag>)> {
    let window_size = (DRIFT_WINDOW_SECS * sample_rate as f32) as usize;
    let min_len = reference.len().min(source.len());

    if min_len < window_size * 2 {
        // Not enough data for meaningful drift estimation
        return None;
    }

    let num_windows = min_len / window_size;
    let mut measurements = Vec::with_capacity(num_windows);

    for w in 0..num_windows {
        let start = w * window_size;
        let end = start + window_size;

        let ref_window = &reference[start..end];
        let src_window = &source[start..end];

        let (lag, corr) = find_lag(ref_window, src_window, DRIFT_MAX_LAG);

        let time_sec = (start + window_size / 2) as f32 / sample_rate as f32;
        measurements.push(WindowedLag {
            time_sec,
            residual_lag: lag,
            correlation: corr,
        });
    }

    // Filter windows by correlation quality
    let valid: Vec<(f32, f32)> = measurements
        .iter()
        .filter(|m| m.correlation >= DRIFT_MIN_CORRELATION)
        .map(|m| (m.time_sec, m.residual_lag as f32))
        .collect();

    if valid.len() < DRIFT_MIN_WINDOWS {
        return None;
    }

    let (_intercept, slope) = linear_fit(&valid);
    Some((slope, measurements))
}

/// Two-pass alignment: global offset (existing) + clock drift correction (new).
///
/// Pass 1: `align_sources` applies integer-sample global lag correction.
/// Pass 2: Windowed cross-correlation estimates linear drift per source,
/// then fractional resampling corrects it.
pub fn align_sources_with_drift(
    sources: Vec<Vec<f32>>,
    sample_rate: u32,
) -> (Vec<Vec<f32>>, Vec<AlignmentInfo>) {
    // Pass 1: Global alignment (existing)
    let (mut aligned, mut info) = align_sources(sources, sample_rate);

    if aligned.len() < 2 {
        return (aligned, info);
    }

    // Find reference index (lag=0, correlation≈1.0)
    let ref_idx = info
        .iter()
        .position(|a| a.lag_samples == 0 && a.correlation_peak >= 0.999)
        .unwrap_or(0);

    // Pass 2: Drift estimation and correction for each non-reference source
    let mut any_corrected = false;
    for i in 0..aligned.len() {
        if i == ref_idx {
            continue;
        }

        if let Some((drift_rate, _measurements)) =
            estimate_drift(&aligned[ref_idx], &aligned[i], sample_rate)
        {
            let drift_ppm = drift_rate * 1e6 / sample_rate as f32;
            info[i].drift_rate = Some(drift_rate);
            info[i].drift_ppm = Some(drift_ppm);

            if drift_rate.abs() >= DRIFT_MIN_RATE {
                let ratio = 1.0 + drift_rate as f64 / sample_rate as f64;
                aligned[i] = resample_linear(&aligned[i], ratio);
                info[i].drift_corrected = true;
                any_corrected = true;
            }
        }
    }

    // Pass 3: Re-align after drift correction. Pass 1's global lag was computed
    // with drift present, so it found the average lag across the drifting signal.
    // After resampling removes the drift slope, a residual constant offset remains.
    // A final find_lag corrects this.
    //
    // Sources may have different lengths (different recording durations, resampling).
    // We intentionally do NOT trim to minimum length — downstream consumers
    // (weighted_average_samples, filter_sources) handle variable-length inputs.
    if any_corrected {
        let max_lag = (MAX_LAG_SECS * sample_rate as f32) as usize;
        for i in 0..aligned.len() {
            if i == ref_idx {
                continue;
            }
            let (lag, _corr) = find_lag(&aligned[ref_idx], &aligned[i], max_lag);
            if lag > 0 {
                let skip = (lag as usize).min(aligned[i].len());
                aligned[i] = aligned[i][skip..].to_vec();
            } else if lag < 0 {
                let pad = (-lag) as usize;
                let mut shifted = vec![0.0f32; pad];
                shifted.extend_from_slice(&aligned[i]);
                aligned[i] = shifted;
            }
        }
    }

    (aligned, info)
}

// --- Quality filtering ---

/// Minimum RMS energy to consider a recording "alive" (not a dead receiver).
const MIN_RMS: f32 = 0.001;

/// Minimum leave-one-out Pearson correlation to keep a recording.
/// Below this the recording is considered uncorrelated noise/interference.
/// 0.3 means a source shares ~9% of variance with the group — below this
/// the source adds more noise than signal.
const MIN_CORRELATION: f32 = 0.3;

/// Minimum coefficient of variation of the windowed RMS envelope.
/// Sources below this have a constant envelope (unkeyed carrier, not CW).
/// Keyed CW typically has CV > 0.5; constant carriers have CV < 0.05.
/// Weak CW in noise has CV 0.15-0.20; this threshold sits in the gap.
const MIN_ENVELOPE_CV: f32 = 0.12;

/// Minimum envelope CV for a source to be considered as alignment reference.
/// The reference must have temporal structure (keying) for cross-correlation
/// to produce meaningful lags. Constant carriers (CV < 0.05) are excluded.
const MIN_REFERENCE_CV: f32 = 0.10;

/// Window size in milliseconds for envelope variation analysis.
const ENVELOPE_WINDOW_MS: u32 = 50;

/// Result of quality filtering source recordings before combining.
#[derive(Debug)]
pub struct FilterResult {
    /// Indices of sources that passed filtering (in original order).
    pub included: Vec<usize>,
    /// (index, reason) for each excluded source.
    pub excluded: Vec<(usize, String)>,
}

/// RMS energy of an audio buffer.
pub fn rms_energy(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    (samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32).sqrt()
}

/// Pearson correlation coefficient between two signals.
/// Uses the minimum length of the two buffers.
pub fn pearson_correlation(a: &[f32], b: &[f32]) -> f32 {
    let n = a.len().min(b.len());
    if n == 0 {
        return 0.0;
    }

    let nf = n as f32;
    let mean_a: f32 = a[..n].iter().sum::<f32>() / nf;
    let mean_b: f32 = b[..n].iter().sum::<f32>() / nf;

    let mut cov = 0.0f32;
    let mut var_a = 0.0f32;
    let mut var_b = 0.0f32;

    for i in 0..n {
        let da = a[i] - mean_a;
        let db = b[i] - mean_b;
        cov += da * db;
        var_a += da * da;
        var_b += db * db;
    }

    let denom = (var_a * var_b).sqrt();
    if denom < 1e-10 {
        0.0
    } else {
        cov / denom
    }
}

/// Coefficient of variation of the windowed RMS envelope.
///
/// Divides the audio into windows and computes RMS per window, then returns
/// std(rms_values) / mean(rms_values). Keyed CW has high CV (amplitude swings
/// between key-down and key-up); constant carriers have near-zero CV.
pub fn envelope_cv(samples: &[f32], sample_rate: u32) -> f32 {
    let window_size = (sample_rate * ENVELOPE_WINDOW_MS / 1000) as usize;
    if window_size == 0 || samples.len() < window_size {
        return 0.0;
    }

    let rms_values: Vec<f32> = samples
        .chunks(window_size)
        .filter(|chunk| chunk.len() == window_size) // skip partial final chunk
        .map(|chunk| (chunk.iter().map(|s| s * s).sum::<f32>() / chunk.len() as f32).sqrt())
        .collect();

    // Skip leading zero-energy windows (reference-time alignment padding).
    // Without this, the silence→signal transition inflates CV for all sources,
    // making constant carriers look like they have envelope variation.
    let rms_values: Vec<f32> = rms_values.into_iter().skip_while(|&r| r < 1e-6).collect();

    if rms_values.is_empty() {
        return 0.0;
    }

    let mean = rms_values.iter().sum::<f32>() / rms_values.len() as f32;
    if mean < 1e-10 {
        return 0.0;
    }

    let variance = rms_values
        .iter()
        .map(|r| (r - mean) * (r - mean))
        .sum::<f32>()
        / rms_values.len() as f32;
    variance.sqrt() / mean
}

/// Filter source recordings, removing dead receivers, constant carriers,
/// and uncorrelated noise.
///
/// Phase 1: Drop sources with RMS energy below [`MIN_RMS`] (dead receivers).
/// Phase 2: Drop sources with low envelope variation (constant carriers, not keyed CW).
/// Phase 3: Iteratively drop the source with lowest leave-one-out correlation
///          until all remaining sources exceed [`MIN_CORRELATION`] or only 2 remain.
pub fn filter_sources(sources: &[Vec<f32>], sample_rate: u32) -> FilterResult {
    let mut active: Vec<usize> = (0..sources.len()).collect();
    let mut excluded = Vec::new();

    // Phase 1: RMS pre-filter (dead receivers)
    active.retain(|&i| {
        let rms = rms_energy(&sources[i]);
        if rms < MIN_RMS {
            excluded.push((i, format!("dead receiver (RMS energy {rms:.6})")));
            false
        } else {
            true
        }
    });

    // Phase 2: Envelope variation filter (constant carriers).
    // Sources with a flat envelope (no keying) are unkeyed carriers, not CW.
    active.retain(|&i| {
        let cv = envelope_cv(&sources[i], sample_rate);
        if cv < MIN_ENVELOPE_CV {
            excluded.push((
                i,
                format!("constant envelope / unkeyed carrier (CV {cv:.4})"),
            ));
            false
        } else {
            true
        }
    });

    if active.len() < 3 {
        // Can't do meaningful leave-one-out with fewer than 3.
        // With exactly 2, check pairwise correlation as a warning but keep both
        // since we can't determine which is the bad one.
        return FilterResult {
            included: active,
            excluded,
        };
    }

    // Trim all to minimum length for correlation computation
    let min_len = active.iter().map(|&i| sources[i].len()).min().unwrap_or(0);

    // Compute running sum for efficient leave-one-out means
    let mut sum = vec![0.0f32; min_len];
    for &i in &active {
        for (j, &s) in sources[i].iter().enumerate().take(min_len) {
            sum[j] += s;
        }
    }

    // Phase 2: iterative correlation rejection
    loop {
        if active.len() <= 2 {
            break;
        }

        // For each active source, correlate with leave-one-out mean
        let n = active.len();
        let mut worst_pos = 0;
        let mut worst_corr = f32::MAX;

        for (pos, &src_idx) in active.iter().enumerate() {
            let loo_mean: Vec<f32> = (0..min_len)
                .map(|j| (sum[j] - sources[src_idx][j]) / (n - 1) as f32)
                .collect();

            let corr = pearson_correlation(&sources[src_idx][..min_len], &loo_mean);
            if corr < worst_corr {
                worst_corr = corr;
                worst_pos = pos;
            }
        }

        if worst_corr < MIN_CORRELATION {
            let removed_idx = active.remove(worst_pos);
            // Update running sum
            for (j, &s) in sources[removed_idx].iter().enumerate().take(min_len) {
                sum[j] -= s;
            }
            excluded.push((
                removed_idx,
                format!("low correlation with group ({worst_corr:.4})"),
            ));
        } else {
            break;
        }
    }

    FilterResult {
        included: active,
        excluded,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recording::flac::FlacWriter;

    #[test]
    fn read_wav_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.wav");

        // Generate a known signal
        let original: Vec<f32> = (0..1200)
            .map(|i| {
                let t = i as f32 / 12000.0;
                (2.0 * std::f32::consts::PI * 800.0 * t).sin() * 0.5
            })
            .collect();

        {
            let mut writer = FlacWriter::create(&path, 12_000).unwrap();
            writer.write_samples(&original).unwrap();
            writer.finalize().unwrap();
        }

        let (sr, read_back) = read_wav_samples(&path).unwrap();
        assert_eq!(sr, 12_000);
        assert_eq!(read_back.len(), original.len());

        // Verify samples match within i16 quantization error
        for (i, (&orig, &back)) in original.iter().zip(read_back.iter()).enumerate() {
            let err = (orig - back).abs();
            assert!(
                err < 1.0 / 32768.0 + 0.0001,
                "sample {i}: orig={orig}, back={back}, err={err}"
            );
        }
    }

    #[test]
    fn average_two_signals() {
        let a = vec![1.0, 0.0, -1.0, 0.5];
        let b = vec![0.0, 1.0, -1.0, -0.5];
        let avg = average_samples(&[a, b]);
        assert_eq!(avg.len(), 4);
        assert!((avg[0] - 0.5).abs() < 1e-6);
        assert!((avg[1] - 0.5).abs() < 1e-6);
        assert!((avg[2] - (-1.0)).abs() < 1e-6);
        assert!((avg[3] - 0.0).abs() < 1e-6);
    }

    #[test]
    fn average_reduces_noise() {
        // signal + noise and signal - noise: averaging recovers signal
        let signal: Vec<f32> = (0..1000).map(|i| (i as f32 * 0.1).sin()).collect();
        let noise: Vec<f32> = (0..1000)
            .map(|i| ((i * 7 + 3) as f32 * 0.37).sin() * 0.5)
            .collect();

        let a: Vec<f32> = signal.iter().zip(&noise).map(|(s, n)| s + n).collect();
        let b: Vec<f32> = signal.iter().zip(&noise).map(|(s, n)| s - n).collect();

        let avg = average_samples(&[a, b]);
        assert_eq!(avg.len(), 1000);

        for (i, (&expected, &actual)) in signal.iter().zip(avg.iter()).enumerate() {
            let err = (expected - actual).abs();
            assert!(
                err < 1e-5,
                "sample {i}: expected={expected}, actual={actual}, err={err}"
            );
        }
    }

    #[test]
    fn average_trims_to_shortest() {
        let a = vec![1.0, 2.0, 3.0];
        let b = vec![1.0, 2.0];
        let avg = average_samples(&[a, b]);
        assert_eq!(avg.len(), 2);
    }

    #[test]
    fn average_empty_sources() {
        let avg = average_samples(&[]);
        assert!(avg.is_empty());
    }

    // --- Weighted averaging tests ---

    #[test]
    fn weighted_average_uses_max_length() {
        let a = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let b = vec![1.0, 2.0];
        let weights = vec![1.0, 1.0];
        let avg = weighted_average_samples(&[a, b], &weights, None);

        // Output should be max length (5), not min (2)
        assert_eq!(avg.len(), 5);
        // First 2 samples: average of both
        assert!((avg[0] - 1.0).abs() < 1e-6);
        assert!((avg[1] - 2.0).abs() < 1e-6);
        // Last 3 samples: only source a contributes
        assert!((avg[2] - 3.0).abs() < 1e-6);
        assert!((avg[3] - 4.0).abs() < 1e-6);
        assert!((avg[4] - 5.0).abs() < 1e-6);
    }

    #[test]
    fn weighted_average_respects_weights() {
        let a = vec![1.0, 0.0];
        let b = vec![0.0, 1.0];
        // a has 3x the weight of b
        let weights = vec![0.75, 0.25];
        let avg = weighted_average_samples(&[a, b], &weights, None);

        assert!((avg[0] - 0.75).abs() < 1e-6);
        assert!((avg[1] - 0.25).abs() < 1e-6);
    }

    #[test]
    fn weighted_average_empty() {
        let avg = weighted_average_samples(&[], &[], None);
        assert!(avg.is_empty());
    }

    // --- Onset detection tests ---

    #[test]
    fn detect_onset_all_signal() {
        let sr = 12_000u32;
        // Signal starting immediately — no padding
        let signal: Vec<f32> = (0..12000).map(|i| (i as f32 * 0.1).sin() * 0.5).collect();
        let onset = detect_signal_onset(&signal, sr);
        assert_eq!(
            onset, 0,
            "signal with no leading silence should have onset at 0"
        );
    }

    #[test]
    fn detect_onset_with_leading_zeros() {
        let sr = 12_000u32;
        // 3 seconds of zeros + 1 second of signal
        let mut samples = vec![0.0f32; 36000]; // 3s at 12kHz
        for i in 0..12000 {
            samples.push((i as f32 * 0.1).sin() * 0.5);
        }
        let onset = detect_signal_onset(&samples, sr);
        // Should detect onset at ~3s (36000 samples), within one window (600 samples)
        assert!(
            (onset as i64 - 36000).abs() <= 600,
            "expected onset near 36000, got {onset}"
        );
    }

    #[test]
    fn detect_onset_all_silence() {
        let sr = 12_000u32;
        let samples = vec![0.0f32; 12000];
        let onset = detect_signal_onset(&samples, sr);
        assert_eq!(onset, 0, "all-silence buffer should return 0");
    }

    // --- Onset-aware weighted averaging tests ---

    #[test]
    fn weighted_average_onset_skips_silence() {
        // Source A: signal from the start (onset=0)
        // Source B: 3 samples of silence, then signal (onset=3)
        let a = vec![1.0, 1.0, 1.0, 1.0, 1.0];
        let b = vec![0.0, 0.0, 0.0, 1.0, 1.0];
        let weights = vec![1.0, 1.0];
        let onsets = vec![0usize, 3usize];

        let avg = weighted_average_samples(&[a, b], &weights, Some(&onsets));

        // First 3 samples: only source A contributes → 1.0
        assert!(
            (avg[0] - 1.0).abs() < 1e-6,
            "sample 0: expected 1.0, got {}",
            avg[0]
        );
        assert!(
            (avg[1] - 1.0).abs() < 1e-6,
            "sample 1: expected 1.0, got {}",
            avg[1]
        );
        assert!(
            (avg[2] - 1.0).abs() < 1e-6,
            "sample 2: expected 1.0, got {}",
            avg[2]
        );
        // Samples 3-4: both contribute → (1.0+1.0)/2 = 1.0
        assert!(
            (avg[3] - 1.0).abs() < 1e-6,
            "sample 3: expected 1.0, got {}",
            avg[3]
        );
    }

    #[test]
    fn weighted_average_without_onset_dilutes() {
        // Same data but WITHOUT onset awareness — demonstrates the dilution problem
        let a = vec![1.0, 1.0, 1.0, 1.0, 1.0];
        let b = vec![0.0, 0.0, 0.0, 1.0, 1.0];
        let weights = vec![1.0, 1.0];

        let avg = weighted_average_samples(&[a, b], &weights, None);

        // First 3 samples: (1.0*1 + 0.0*1) / 2 = 0.5 — diluted!
        assert!(
            (avg[0] - 0.5).abs() < 1e-6,
            "without onset, sample 0 should be diluted to 0.5, got {}",
            avg[0]
        );
    }

    // --- Trimmed mean tests ---

    #[test]
    fn trimmed_mean_rejects_spike() {
        // 5 sources: 4 clean at 1.0, one with a spike at 10.0
        let clean = vec![1.0f32; 100];
        let spike = vec![10.0f32; 100];
        let sources = vec![
            clean.clone(),
            clean.clone(),
            clean.clone(),
            clean.clone(),
            spike,
        ];

        let result = trimmed_mean_samples(&sources, None, 0.20);

        // 20% trim on 5 sources drops 1 from each end → middle 3
        // With spike in top, it gets trimmed. Result should be close to 1.0.
        for (i, &v) in result.iter().enumerate() {
            assert!(
                (v - 1.0).abs() < 0.01,
                "sample {i}: expected ~1.0 after trimming spike, got {v}"
            );
        }
    }

    #[test]
    fn trimmed_mean_onset_aware() {
        // Source A: signal from start (onset=0), value=1.0
        // Source B: 3 samples silence, then signal (onset=3), value=1.0
        // Source C: signal from start (onset=0), value=1.0
        let a = vec![1.0f32; 5];
        let b = vec![0.0, 0.0, 0.0, 1.0, 1.0];
        let c = vec![1.0f32; 5];
        let onsets = vec![0usize, 3usize, 0usize];

        let result = trimmed_mean_samples(&[a, b, c], Some(&onsets), 0.20);

        // First 3 samples: only A and C contribute (2 sources, <3 → simple mean)
        assert!(
            (result[0] - 1.0).abs() < 1e-6,
            "sample 0: expected 1.0, got {}",
            result[0]
        );
        // Samples 3-4: all three contribute
        assert!(
            (result[3] - 1.0).abs() < 1e-6,
            "sample 3: expected 1.0, got {}",
            result[3]
        );
    }

    #[test]
    fn trimmed_mean_few_sources_falls_back_to_mean() {
        let a = vec![1.0, 2.0];
        let b = vec![3.0, 4.0];

        let result = trimmed_mean_samples(&[a, b], None, 0.20);

        assert!((result[0] - 2.0).abs() < 1e-6);
        assert!((result[1] - 3.0).abs() < 1e-6);
    }

    #[test]
    fn compute_weights_reference_is_one() {
        let signal: Vec<f32> = (0..1000).map(|i| (i as f32 * 0.1).sin()).collect();
        let noise: Vec<f32> = (0..1000).map(|i| (i as f32 * 3.71).sin()).collect();
        let weights = compute_source_weights(&[signal, noise], 0);

        assert!(
            (weights[0] - 1.0).abs() < 1e-6,
            "reference weight should be 1.0"
        );
        assert!(
            weights[1] < 0.1,
            "uncorrelated source should have near-zero weight, got {:.4}",
            weights[1]
        );
    }

    #[test]
    fn compute_weights_correlated_source_high() {
        let signal: Vec<f32> = (0..1000).map(|i| (i as f32 * 0.1).sin()).collect();
        // Same signal + small noise
        let noisy: Vec<f32> = signal
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.1)
            .collect();
        let weights = compute_source_weights(&[signal, noisy], 0);

        assert!(
            weights[1] > 0.9,
            "correlated source should have high weight, got {:.4}",
            weights[1]
        );
    }

    // --- Quality filter tests ---

    #[test]
    fn rms_of_silence_is_zero() {
        assert_eq!(rms_energy(&[0.0; 1000]), 0.0);
        assert_eq!(rms_energy(&[]), 0.0);
    }

    #[test]
    fn rms_of_signal_is_positive() {
        let signal: Vec<f32> = (0..1000).map(|i| (i as f32 * 0.1).sin() * 0.5).collect();
        let rms = rms_energy(&signal);
        assert!(rms > 0.3, "expected RMS > 0.3, got {rms}");
    }

    #[test]
    fn pearson_identical_signals() {
        let a: Vec<f32> = (0..1000).map(|i| (i as f32 * 0.1).sin()).collect();
        let corr = pearson_correlation(&a, &a);
        assert!(
            (corr - 1.0).abs() < 1e-5,
            "self-correlation should be ~1.0, got {corr}"
        );
    }

    #[test]
    fn pearson_uncorrelated_signals() {
        // Two sine waves at incommensurate frequencies over many samples
        let a: Vec<f32> = (0..10000).map(|i| (i as f32 * 0.05).sin()).collect();
        let b: Vec<f32> = (0..10000).map(|i| (i as f32 * 3.71).sin()).collect();
        let corr = pearson_correlation(&a, &b);
        assert!(
            corr.abs() < 0.05,
            "uncorrelated signals should have near-zero correlation, got {corr}"
        );
    }

    /// Generate a keyed signal: alternates tone and silence every `key_samples` samples.
    /// This simulates CW keying and produces high envelope CV.
    fn keyed_signal(len: usize, freq_factor: f32, amplitude: f32, key_samples: usize) -> Vec<f32> {
        (0..len)
            .map(|i| {
                let tone = (i as f32 * freq_factor).sin() * amplitude;
                if (i / key_samples) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect()
    }

    #[test]
    fn filter_drops_dead_receiver() {
        let sr = 12_000u32;
        let signal = keyed_signal(24000, 0.05, 0.5, 600);
        let dead = vec![0.0f32; 24000];
        let noisy: Vec<f32> = signal
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.1)
            .collect();

        let result = filter_sources(&[signal, dead, noisy], sr);
        assert_eq!(result.included, vec![0, 2]);
        assert!(result
            .excluded
            .iter()
            .any(|(idx, r)| *idx == 1 && r.contains("dead")));
    }

    #[test]
    fn filter_drops_uncorrelated_noise() {
        let sr = 12_000u32;
        // Three keyed recordings sharing a signal, one pure noise (also keyed so it passes CV)
        let base = keyed_signal(24000, 0.05, 0.5, 600);
        let s1: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| {
                s + if s != 0.0 {
                    (i as f32 * 0.73).sin() * 0.1
                } else {
                    0.0
                }
            })
            .collect();
        let s2: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| {
                s + if s != 0.0 {
                    (i as f32 * 1.31).sin() * 0.1
                } else {
                    0.0
                }
            })
            .collect();
        let s3: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| {
                s + if s != 0.0 {
                    (i as f32 * 2.17).sin() * 0.1
                } else {
                    0.0
                }
            })
            .collect();
        // Noise at different keying: keyed but uncorrelated with the others
        let noise = keyed_signal(24000, 3.71, 0.3, 900);

        let result = filter_sources(&[s1, s2, s3, noise], sr);
        assert_eq!(result.included, vec![0, 1, 2]);
        assert!(result.excluded.iter().any(|(idx, _)| *idx == 3));
    }

    #[test]
    fn normalize_boosts_quiet_signal() {
        let mut samples: Vec<f32> = (0..1000)
            .map(|i| (i as f32 * 0.1).sin() * 0.1) // peak ~0.1
            .collect();
        let gain = normalize_audio(&mut samples, 0.9);

        // Gain should be ~9x
        assert!(
            (gain - 9.0).abs() < 0.5,
            "expected gain ~9.0, got {gain:.2}"
        );

        // Peak should now be ~0.9
        let peak = samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        assert!(
            (peak - 0.9).abs() < 0.01,
            "expected peak ~0.9, got {peak:.4}"
        );
    }

    #[test]
    fn normalize_silent_signal_returns_unity() {
        let mut samples = vec![0.0f32; 100];
        let gain = normalize_audio(&mut samples, 0.9);
        assert_eq!(gain, 1.0);
        assert!(samples.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn normalize_already_loud_signal() {
        let mut samples: Vec<f32> = (0..1000)
            .map(|i| (i as f32 * 0.1).sin() * 0.95) // peak ~0.95
            .collect();
        let gain = normalize_audio(&mut samples, 0.9);

        // Gain should be slightly less than 1 (attenuating to 0.9)
        assert!(gain < 1.0, "expected gain < 1.0, got {gain:.4}");
        let peak = samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        assert!(
            (peak - 0.9).abs() < 0.01,
            "expected peak ~0.9, got {peak:.4}"
        );
    }

    #[test]
    fn filter_keeps_all_good_sources() {
        let sr = 12_000u32;
        let base = keyed_signal(24000, 0.05, 0.5, 600);
        let s1: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| {
                s + if s != 0.0 {
                    (i as f32 * 0.73).sin() * 0.1
                } else {
                    0.0
                }
            })
            .collect();
        let s2: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| {
                s + if s != 0.0 {
                    (i as f32 * 1.31).sin() * 0.1
                } else {
                    0.0
                }
            })
            .collect();
        let s3: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| {
                s + if s != 0.0 {
                    (i as f32 * 2.17).sin() * 0.1
                } else {
                    0.0
                }
            })
            .collect();

        let result = filter_sources(&[s1, s2, s3], sr);
        assert_eq!(result.included, vec![0, 1, 2]);
        assert!(result.excluded.is_empty());
    }

    // --- Envelope CV tests ---

    #[test]
    fn envelope_cv_constant_tone_is_low() {
        let sr = 12_000u32;
        // Constant 650 Hz tone for 2 seconds — no keying
        let samples: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5
            })
            .collect();
        let cv = envelope_cv(&samples, sr);
        assert!(
            cv < MIN_ENVELOPE_CV,
            "constant tone should have low CV, got {cv:.4}"
        );
    }

    #[test]
    fn envelope_cv_keyed_cw_is_high() {
        let sr = 12_000u32;
        // Keyed 650 Hz tone: 100ms on, 100ms off, repeated
        let samples: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                // Toggle every 1200 samples (100ms at 12kHz)
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();
        let cv = envelope_cv(&samples, sr);
        assert!(
            cv > MIN_ENVELOPE_CV,
            "keyed CW should have high CV, got {cv:.4}"
        );
    }

    #[test]
    fn filter_drops_constant_carrier() {
        let sr = 12_000u32;
        // Three keyed CW sources + one constant carrier
        let keyed1: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.3;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();
        let keyed2: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.3;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();
        let keyed3: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.3;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();
        // Constant carrier at 650 Hz — much stronger
        let carrier: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.8
            })
            .collect();

        let result = filter_sources(&[keyed1, keyed2, keyed3, carrier], sr);
        // Carrier should be excluded
        assert!(
            !result.included.contains(&3),
            "constant carrier should be excluded, included: {:?}",
            result.included
        );
        assert!(
            result
                .excluded
                .iter()
                .any(|(idx, r)| *idx == 3 && r.contains("constant envelope")),
            "expected constant envelope exclusion for index 3, got: {:?}",
            result.excluded
        );
    }

    // --- Cross-correlation alignment tests ---

    #[test]
    fn find_lag_identical_signals() {
        let signal: Vec<f32> = (0..12000)
            .map(|i| {
                let t = i as f32 / 12000.0;
                (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5
            })
            .collect();

        let (lag, corr) = find_lag(&signal, &signal, 12000);
        assert_eq!(lag, 0, "identical signals should have zero lag");
        assert!(
            corr > 0.99,
            "identical signals should have correlation ~1.0, got {corr:.4}"
        );
    }

    #[test]
    fn align_corrects_known_offset() {
        let sr = 12_000u32;
        let shift = 600; // 50ms at 12kHz

        // Generate a keyed CW signal
        let signal: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();

        // Create a delayed copy: shift samples forward by `shift`
        let mut delayed = vec![0.0f32; shift];
        delayed.extend_from_slice(&signal[..signal.len() - shift]);

        let (aligned, info) = align_sources(vec![signal.clone(), delayed], sr);

        // The delayed source (index 1) should have been detected with a positive lag
        // or the reference (index 0) with a negative lag. Either way, after alignment
        // the signals should be highly correlated.
        let corr = pearson_correlation(&aligned[0], &aligned[1]);
        assert!(
            corr > 0.95,
            "aligned signals should correlate > 0.95, got {corr:.4}"
        );

        // At least one source should show a non-zero lag
        let any_shifted = info.iter().any(|a| a.lag_samples != 0);
        assert!(any_shifted, "expected at least one source to be shifted");
    }

    #[test]
    fn align_with_noise() {
        let sr = 12_000u32;
        let shift = 300; // 25ms at 12kHz

        let signal: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();

        // Add different noise to each copy
        let noisy_a: Vec<f32> = signal
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.1)
            .collect();
        let mut noisy_b: Vec<f32> = vec![0.0f32; shift];
        noisy_b.extend(
            signal[..signal.len() - shift]
                .iter()
                .enumerate()
                .map(|(i, &s)| s + (i as f32 * 1.31).sin() * 0.1),
        );

        let (aligned, info) = align_sources(vec![noisy_a, noisy_b], sr);

        let corr = pearson_correlation(&aligned[0], &aligned[1]);
        assert!(
            corr > 0.85,
            "aligned noisy signals should correlate > 0.85, got {corr:.4}"
        );

        let any_shifted = info.iter().any(|a| a.lag_samples != 0);
        assert!(any_shifted, "expected at least one source to be shifted");
    }

    #[test]
    fn align_reference_prefers_keyed_source() {
        let sr = 12_000u32;

        // Source 0: constant carrier — high RMS, low CV (no keying)
        let carrier: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.8
            })
            .collect();

        // Source 1: keyed CW — lower RMS, high CV
        let keyed: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.3;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();

        // Carrier has higher RMS but the keyed source should be chosen as reference
        assert!(rms_energy(&carrier) > rms_energy(&keyed));
        assert!(envelope_cv(&carrier, sr) < MIN_REFERENCE_CV);
        assert!(envelope_cv(&keyed, sr) >= MIN_REFERENCE_CV);

        let (_, info) = align_sources(vec![carrier, keyed], sr);

        // Source 1 (keyed) should be the reference (lag=0, corr=1.0)
        assert_eq!(
            info[1].lag_samples, 0,
            "keyed source should be reference (zero lag)"
        );
        assert!(
            (info[1].correlation_peak - 1.0).abs() < 1e-5,
            "reference should have perfect self-correlation"
        );
    }

    #[test]
    fn align_no_shift_needed() {
        let sr = 12_000u32;

        // Two slightly different but already-aligned signals
        let signal: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5
            })
            .collect();

        let noisy_a: Vec<f32> = signal
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.05)
            .collect();
        let noisy_b: Vec<f32> = signal
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 1.31).sin() * 0.05)
            .collect();

        let (_aligned, info) = align_sources(vec![noisy_a, noisy_b], sr);

        // All lags should be 0 or very small (within a couple samples)
        for ai in &info {
            assert!(
                ai.lag_samples.abs() <= 2,
                "already-aligned signals should have near-zero lag, got {} for source {}",
                ai.lag_samples,
                ai.source_index
            );
        }
    }

    #[test]
    fn align_with_leading_silence_padding() {
        let sr = 12_000u32;

        // Simulate reference-time padding: two sources with different amounts
        // of leading silence before the same keyed CW signal.
        let signal: Vec<f32> = (0..24000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();

        // Source A: 3000 samples (250ms) of silence padding
        let mut source_a = vec![0.0f32; 3000];
        source_a.extend_from_slice(&signal);

        // Source B: 12000 samples (1s) of silence padding
        let mut source_b = vec![0.0f32; 12000];
        source_b.extend_from_slice(&signal);

        let (aligned, info) = align_sources(vec![source_a, source_b], sr);

        // After onset-aware alignment, the signal portions should be well-aligned
        let corr = pearson_correlation(&aligned[0], &aligned[1]);
        assert!(
            corr > 0.90,
            "signals with different leading silence should align well, got {corr:.4}"
        );

        // The source with more silence should have a larger lag
        let max_lag = info.iter().map(|a| a.lag_samples.abs()).max().unwrap_or(0);
        assert!(
            max_lag > 1000,
            "expected significant lag from onset difference, got {max_lag}"
        );
    }

    // --- Drift correction tests ---

    /// Create a drifted version of a signal: initial delay + clock drift.
    ///
    /// A positive `drift_ppm` means the source clock runs faster (more samples
    /// per real second), which compresses the waveform in sample space.
    fn apply_drift(
        signal: &[f32],
        initial_offset: usize,
        drift_ppm: f32,
        _sample_rate: u32,
    ) -> Vec<f32> {
        let ratio = 1.0 + drift_ppm as f64 / 1e6;
        let output_len = (signal.len() as f64 * ratio) as usize;
        let mut output = vec![0.0f32; initial_offset + output_len];

        for i in 0..output_len {
            let src_pos = i as f64 / ratio;
            let idx = src_pos as usize;
            let frac = (src_pos - idx as f64) as f32;

            if idx + 1 < signal.len() {
                output[initial_offset + i] = signal[idx] * (1.0 - frac) + signal[idx + 1] * frac;
            } else if idx < signal.len() {
                output[initial_offset + i] = signal[idx];
            }
        }

        output
    }

    #[test]
    fn linear_fit_exact() {
        // y = 2x + 3
        let points: Vec<(f32, f32)> = (0..10).map(|i| (i as f32, 2.0 * i as f32 + 3.0)).collect();
        let (intercept, slope) = linear_fit(&points);
        assert!(
            (intercept - 3.0).abs() < 1e-4,
            "expected intercept ~3.0, got {intercept:.6}"
        );
        assert!(
            (slope - 2.0).abs() < 1e-4,
            "expected slope ~2.0, got {slope:.6}"
        );
    }

    #[test]
    fn resample_linear_identity() {
        let input: Vec<f32> = (0..1000).map(|i| (i as f32 * 0.1).sin()).collect();
        let output = resample_linear(&input, 1.0);

        // Length should be the same
        assert_eq!(output.len(), input.len());

        // Values should match closely
        for (i, (&inp, &out)) in input.iter().zip(output.iter()).enumerate() {
            let err = (inp - out).abs();
            assert!(
                err < 1e-5,
                "sample {i}: input={inp}, output={out}, err={err}"
            );
        }
    }

    #[test]
    fn resample_linear_stretches() {
        // ratio=2.0 means each output reads from 2x the position → half the output length
        let input: Vec<f32> = (0..1000).map(|i| (i as f32 * 0.1).sin()).collect();
        let output = resample_linear(&input, 2.0);

        assert_eq!(output.len(), 500);

        // output[i] should equal input[2*i] (approximately, with interpolation)
        for i in 0..499 {
            let expected = input[2 * i];
            let err = (output[i] - expected).abs();
            assert!(
                err < 1e-4,
                "sample {i}: expected={expected}, output={}, err={err}",
                output[i]
            );
        }
    }

    #[test]
    fn estimate_drift_no_drift() {
        let sr = 12_000u32;

        // Generate 30 seconds of keyed CW (need > 2 windows × 5s)
        let signal: Vec<f32> = (0..(sr as usize * 30))
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();

        let result = estimate_drift(&signal, &signal, sr);

        match result {
            Some((drift_rate, _)) => {
                assert!(
                    drift_rate.abs() < DRIFT_MIN_RATE,
                    "identical signals should have near-zero drift, got {drift_rate:.4}"
                );
            }
            None => {
                // Also acceptable — not enough variation to detect
            }
        }
    }

    #[test]
    fn estimate_drift_known_drift() {
        let sr = 12_000u32;
        let drift_ppm = 50.0;

        // Generate 60 seconds of keyed CW
        let signal: Vec<f32> = (0..(sr as usize * 60))
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();

        // Apply 50 ppm drift (no initial offset — that's handled by pass 1)
        let drifted = apply_drift(&signal, 0, drift_ppm, sr);

        // Trim to same length for estimate_drift (simulate post-global-alignment)
        let min_len = signal.len().min(drifted.len());

        let result = estimate_drift(&signal[..min_len], &drifted[..min_len], sr);
        assert!(result.is_some(), "should detect drift at 50 ppm");

        let (drift_rate, _measurements) = result.unwrap();
        let estimated_ppm = drift_rate * 1e6 / sr as f32;
        assert!(
            (estimated_ppm - drift_ppm).abs() < 15.0,
            "expected ~{drift_ppm} ppm, got {estimated_ppm:.1} ppm"
        );
    }

    #[test]
    fn align_with_drift_correction() {
        let sr = 12_000u32;
        let initial_offset = 120; // samples
        let drift_ppm = 30.0;

        // Generate 60 seconds of keyed CW
        let signal: Vec<f32> = (0..(sr as usize * 60))
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                if (i / 1200) % 2 == 0 {
                    tone
                } else {
                    0.0
                }
            })
            .collect();

        // Create drifted copy with initial offset + clock drift
        let drifted = apply_drift(&signal, initial_offset, drift_ppm, sr);

        let (aligned, info) = align_sources_with_drift(vec![signal.clone(), drifted], sr);

        // Check global alignment was detected
        let any_shifted = info.iter().any(|a| a.lag_samples != 0);
        assert!(any_shifted, "expected initial offset to be detected");

        // Check drift was detected and corrected
        let drifted_info = &info[1]; // source 1 is the drifted one
        assert!(
            drifted_info.drift_corrected,
            "expected drift correction to be applied, drift_rate={:?}, drift_ppm={:?}",
            drifted_info.drift_rate, drifted_info.drift_ppm
        );

        // After correction, correlation across the full length should be high
        let corr = pearson_correlation(&aligned[0], &aligned[1]);
        assert!(
            corr > 0.95,
            "drift-corrected signals should correlate > 0.95 across full length, got {corr:.4}"
        );

        // Compare with uncorrected: correlation in the last quarter should be much worse
        let n = signal.len().min(aligned[0].len());
        let quarter = n / 4;
        let (uncorrected, _) = align_sources(
            vec![
                signal.clone(),
                apply_drift(&signal, initial_offset, drift_ppm, sr),
            ],
            sr,
        );
        let uncorr_len = uncorrected[0].len().min(uncorrected[1].len());
        if uncorr_len > quarter {
            let corr_uncorrected = pearson_correlation(
                &uncorrected[0][uncorr_len - quarter..],
                &uncorrected[1][uncorr_len - quarter..],
            );
            let corr_corrected =
                pearson_correlation(&aligned[0][n - quarter..], &aligned[1][n - quarter..]);
            assert!(
                corr_corrected > corr_uncorrected,
                "drift correction should improve late-recording correlation: corrected={corr_corrected:.4} vs uncorrected={corr_uncorrected:.4}"
            );
        }
    }

    /// Integration test: run drift-corrected combine on real recording data.
    /// Produces combined_drift.wav for manual listening comparison.
    #[test]
    #[ignore]
    fn combine_real_data_with_drift() {
        use std::path::PathBuf;

        let dir = PathBuf::from("/Users/jsvana/tmp/recording-20260218-173305");
        if !dir.exists() {
            eprintln!("Skipping: real data directory not found");
            return;
        }

        // Read all source WAV files (skip combined_ outputs)
        let mut sources = Vec::new();
        let mut names = Vec::new();
        let mut sr = 0u32;
        for entry in std::fs::read_dir(&dir).unwrap() {
            let entry = entry.unwrap();
            let name = entry.file_name().to_string_lossy().to_string();
            if name.ends_with("_seg0.wav") && !name.starts_with("combined") {
                let (rate, samples) = read_wav_samples(&entry.path()).unwrap();
                sr = rate;
                eprintln!(
                    "  {} — {} samples ({:.1}s), RMS {:.6}",
                    name,
                    samples.len(),
                    samples.len() as f32 / rate as f32,
                    rms_energy(&samples)
                );
                names.push(name);
                sources.push(samples);
            }
        }

        eprintln!("Read {} sources at {} Hz", sources.len(), sr);

        // Bandpass filter
        for source in &mut sources {
            bandpass_filter(source, 400.0, 900.0, sr);
        }

        // Align with drift correction
        let (mut sources, alignment_info) = align_sources_with_drift(sources, sr);
        for (i, ai) in alignment_info.iter().enumerate() {
            eprintln!(
                "  [{}] {} — lag={}({:.1}ms) corr={:.4} drift={:?}ppm corrected={}",
                i,
                names[i],
                ai.lag_samples,
                ai.lag_ms,
                ai.correlation_peak,
                ai.drift_ppm.map(|p| format!("{:.1}", p)),
                ai.drift_corrected,
            );
        }

        // Quality filter
        let result = filter_sources(&sources, sr);
        eprintln!(
            "Quality filter: {} included, {} excluded",
            result.included.len(),
            result.excluded.len()
        );
        for (i, reason) in &result.excluded {
            eprintln!("  excluded [{}] {}: {}", i, names[*i], reason);
        }

        // Find reference in filtered set, compute weights
        let ref_source = alignment_info
            .iter()
            .find(|a| a.lag_samples == 0 && a.correlation_peak >= 0.999)
            .map(|a| a.source_index);
        let ref_in_filtered = ref_source
            .and_then(|ref_idx| result.included.iter().position(|&i| i == ref_idx))
            .unwrap_or(0);

        let filtered: Vec<Vec<f32>> = result
            .included
            .iter()
            .map(|&i| std::mem::take(&mut sources[i]))
            .collect();

        let weights = compute_source_weights(&filtered, ref_in_filtered);
        for (pos, (&kept_idx, &w)) in result.included.iter().zip(weights.iter()).enumerate() {
            eprintln!(
                "  weight [{}] {} = {:.4}{}",
                kept_idx,
                names[kept_idx],
                w,
                if pos == ref_in_filtered {
                    " (reference)"
                } else {
                    ""
                }
            );
        }

        let onsets: Vec<usize> = filtered
            .iter()
            .map(|s| detect_signal_onset(s, sr))
            .collect();
        let mut averaged = trimmed_mean_samples(&filtered, Some(&onsets), 0.20);

        // Normalize
        let gain = normalize_audio(&mut averaged, 0.9);
        eprintln!(
            "Output: {} samples ({:.1}s), gain={:.1}x",
            averaged.len(),
            averaged.len() as f32 / sr as f32,
            gain
        );

        // Write output
        let out_path = dir.join("combined_drift.wav");
        let mut writer = FlacWriter::create(&out_path, sr).unwrap();
        writer.write_samples(&averaged).unwrap();
        writer.finalize().unwrap();
        eprintln!("Wrote {}", out_path.display());
    }

    // --- Windowed weights tests ---

    #[test]
    fn windowed_weights_detect_quality_change() {
        let sr = 12_000u32;
        let duration_samples = sr as usize * 10; // 10 seconds

        // Reference: keyed CW signal throughout
        let reference = keyed_signal(duration_samples, 0.05, 0.5, 600);

        // Source 1: good correlation first 5s, noise second 5s
        let half = duration_samples / 2;
        let mut source1: Vec<f32> = reference[..half]
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.05)
            .collect();
        // Second half: uncorrelated noise
        source1.extend((0..half).map(|i| ((i + half) as f32 * 3.71).sin() * 0.3));

        let ww = compute_windowed_weights(&[reference.clone(), source1], 0, sr);

        // First windows should have high weight for source 1
        let early_weight = ww.weight_at(1, sr as usize); // 1s in
        assert!(
            early_weight > 0.5,
            "source 1 should have high weight early, got {early_weight:.4}"
        );

        // Late windows should have low/zero weight for source 1
        let late_weight = ww.weight_at(1, sr as usize * 8); // 8s in
        assert!(
            late_weight < 0.3,
            "source 1 should have low weight late, got {late_weight:.4}"
        );
    }

    #[test]
    fn windowed_trimmed_mean_excludes_degraded() {
        let sr = 12_000u32;
        let duration_samples = sr as usize * 6; // 6 seconds

        // Two good sources: correlated keyed signals
        let base = keyed_signal(duration_samples, 0.05, 0.5, 600);
        let good1: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.05)
            .collect();
        let good2: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 1.31).sin() * 0.05)
            .collect();

        // Third source: good first 3s, noise last 3s
        let half = duration_samples / 2;
        let mut bad: Vec<f32> = base[..half]
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 2.17).sin() * 0.05)
            .collect();
        bad.extend((0..half).map(|i| ((i + half) as f32 * 3.71).sin() * 0.5));

        let sources = vec![good1, good2, bad];
        let ww = compute_windowed_weights(&sources, 0, sr);
        let onsets = vec![0usize; 3];

        let result =
            windowed_trimmed_mean_samples(&sources, Some(&onsets), 0.20, &ww, MIN_INCLUDE_WEIGHT);

        assert_eq!(result.len(), duration_samples);
        // Output should exist and not be empty
        let rms_late = rms_energy(&result[half..]);
        assert!(
            rms_late > 0.01,
            "late output should still have signal (good sources remain)"
        );
    }

    #[test]
    fn windowed_weights_single_window_fallback() {
        let sr = 12_000u32;
        // 1 second of audio (< 2s window)
        let short = keyed_signal(sr as usize, 0.05, 0.5, 600);
        let short2: Vec<f32> = short
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.05)
            .collect();

        let ww = compute_windowed_weights(&[short, short2], 0, sr);

        assert_eq!(ww.weights.len(), 1, "short audio should get single window");
        assert!(
            (ww.weights[0][0] - 1.0).abs() < 1e-6,
            "reference should have weight 1.0"
        );
        assert!(
            ww.weights[0][1] > 0.5,
            "correlated source should have high weight in single window"
        );
    }

    #[test]
    fn windowed_matches_global_for_steady_sources() {
        let sr = 12_000u32;
        let duration_samples = sr as usize * 10;

        // All sources have constant quality throughout
        let base = keyed_signal(duration_samples, 0.05, 0.5, 600);
        let s1: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.05)
            .collect();
        let s2: Vec<f32> = base
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 1.31).sin() * 0.05)
            .collect();

        let global = compute_source_weights(&[base.clone(), s1.clone(), s2.clone()], 0);
        let ww = compute_windowed_weights(&[base, s1, s2], 0, sr);

        // All window weights for source 1 should be close to global weight
        for (w_idx, window) in ww.weights.iter().enumerate() {
            assert!(
                (window[1] - global[1]).abs() < 0.15,
                "window {w_idx}: windowed weight {:.4} should be near global {:.4}",
                window[1],
                global[1]
            );
        }
    }

    #[test]
    fn weight_interpolation_smooth() {
        let sr = 12_000u32;
        let duration_samples = sr as usize * 10;

        let base = keyed_signal(duration_samples, 0.05, 0.5, 600);

        // Source with changing quality (correlated first 5s, noise last 5s)
        let half = duration_samples / 2;
        let mut changing: Vec<f32> = base[..half]
            .iter()
            .enumerate()
            .map(|(i, &s)| s + (i as f32 * 0.73).sin() * 0.05)
            .collect();
        changing.extend((0..half).map(|i| ((i + half) as f32 * 3.71).sin() * 0.3));

        let ww = compute_windowed_weights(&[base, changing], 0, sr);

        // Check that adjacent sample weights don't have step changes
        // Sample every 10 samples across window boundaries
        let hop = ww.hop_samples;
        for boundary in (0..duration_samples).step_by(hop) {
            if boundary == 0 || boundary + 100 >= duration_samples {
                continue;
            }
            let w_before = ww.weight_at(1, boundary.saturating_sub(50));
            let w_at = ww.weight_at(1, boundary);
            let w_after = ww.weight_at(1, boundary + 50);

            // Weights should change gradually (no step > 0.3 in 100 samples)
            let max_step = (w_before - w_at).abs().max((w_at - w_after).abs());
            assert!(
                max_step < 0.3,
                "weight step too large at boundary {boundary}: {w_before:.4} -> {w_at:.4} -> {w_after:.4}"
            );
        }
    }
}
