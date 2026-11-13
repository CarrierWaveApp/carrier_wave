/// A keying event produced by the tone detector.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyingEventKind {
    On,
    Off,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyingEvent {
    pub kind: KeyingEventKind,
    pub sample_offset: usize,
}

/// Find the sample index where audio activity begins (skips leading digital
/// silence from reference-time alignment padding). Returns 0 if no silence.
pub fn find_active_start(samples: &[f32], sample_rate: u32) -> usize {
    // Check peak amplitude in 50ms chunks. Reference-time padding is exactly
    // zero; real noise floors always have some nonzero content.
    let chunk_size = (sample_rate as usize) / 20; // 50ms
    if chunk_size == 0 {
        return 0;
    }
    for (i, chunk) in samples.chunks(chunk_size).enumerate() {
        let peak = chunk.iter().fold(0.0f32, |acc, &s| acc.max(s.abs()));
        if peak > f32::EPSILON {
            return i * chunk_size;
        }
    }
    0 // all silence — just use the start
}

/// Scan audio in `low_hz..=high_hz` at `step_hz` resolution to find the frequency
/// with the highest Goertzel energy. Returns the peak frequency in Hz.
///
/// Caller should skip leading silence before calling this function.
/// Uses a coarse scan at `step_hz`, then refines to 1 Hz around the winner.
pub fn detect_peak_frequency(
    samples: &[f32],
    sample_rate: u32,
    low_hz: f32,
    high_hz: f32,
    step_hz: f32,
) -> f32 {
    let active = samples;

    let window_size = (sample_rate as f32 * 0.05) as usize; // 50ms window
    let window_size = window_size.min(active.len());
    if window_size == 0 {
        return (low_hz + high_hz) / 2.0;
    }

    // Accumulate energy across multiple windows for robustness
    let num_windows = (active.len() / window_size).min(40);
    if num_windows == 0 {
        return (low_hz + high_hz) / 2.0;
    }

    let goertzel_energy_at = |freq: f32, window: &[f32]| -> f32 {
        let k = freq * window.len() as f32 / sample_rate as f32;
        let coeff = 2.0 * (2.0 * std::f32::consts::PI * k / window.len() as f32).cos();
        let mut s1: f32 = 0.0;
        let mut s2: f32 = 0.0;
        for &sample in window {
            let s0 = sample + coeff * s1 - s2;
            s2 = s1;
            s1 = s0;
        }
        s1 * s1 + s2 * s2 - coeff * s1 * s2
    };

    // Coarse scan
    let mut best_freq = (low_hz + high_hz) / 2.0;
    let mut best_energy = 0.0f32;
    let mut freq = low_hz;
    while freq <= high_hz {
        let mut total_energy = 0.0f32;
        for w in 0..num_windows {
            let start = w * window_size;
            let window = &active[start..start + window_size];
            total_energy += goertzel_energy_at(freq, window);
        }
        if total_energy > best_energy {
            best_energy = total_energy;
            best_freq = freq;
        }
        freq += step_hz;
    }

    // Fine scan: 1 Hz steps around the coarse winner
    let fine_low = (best_freq - step_hz).max(low_hz);
    let fine_high = (best_freq + step_hz).min(high_hz);
    freq = fine_low;
    while freq <= fine_high {
        let mut total_energy = 0.0f32;
        for w in 0..num_windows {
            let start = w * window_size;
            let window = &active[start..start + window_size];
            total_energy += goertzel_energy_at(freq, window);
        }
        if total_energy > best_energy {
            best_energy = total_energy;
            best_freq = freq;
        }
        freq += 1.0;
    }

    best_freq
}

/// Scan audio for multiple CW tone frequencies in the given range.
///
/// Uses chunked detection to find operators who transmit at different times:
/// 1. Divide recording into ~5-second chunks with 50% overlap
/// 2. Per chunk: Goertzel scan, find local maxima above the chunk's noise floor
/// 3. Score each candidate frequency by presence count (number of chunks where
///    it appears as a peak), not total energy — prevents a tone present in 5
///    chunks from being drowned out by one present in 50 chunks
/// 4. Filter: keep candidates appearing in ≥2 chunks (eliminates one-off noise)
/// 5. Enforce `min_separation_hz` minimum separation (keep higher-presence peak)
/// 6. Cap at `max_tones` (take top N by presence count)
/// 7. Fine-scan each selected frequency to 1 Hz resolution
/// 8. Return frequencies sorted ascending
///
/// Falls back to single-tone `detect_peak_frequency()` if no peaks pass filtering.
pub fn detect_peak_frequencies(
    samples: &[f32],
    sample_rate: u32,
    low_hz: f32,
    high_hz: f32,
    step_hz: f32,
    min_separation_hz: f32,
    max_tones: usize,
) -> Vec<f32> {
    let active = samples;

    let window_size = (sample_rate as f32 * 0.05) as usize; // 50ms Goertzel window
    let window_size = window_size.min(active.len());
    if window_size == 0 {
        return vec![(low_hz + high_hz) / 2.0];
    }

    let goertzel_energy_at = |freq: f32, window: &[f32]| -> f32 {
        let k = freq * window.len() as f32 / sample_rate as f32;
        let coeff = 2.0 * (2.0 * std::f32::consts::PI * k / window.len() as f32).cos();
        let mut s1: f32 = 0.0;
        let mut s2: f32 = 0.0;
        for &sample in window {
            let s0 = sample + coeff * s1 - s2;
            s2 = s1;
            s1 = s0;
        }
        s1 * s1 + s2 * s2 - coeff * s1 * s2
    };

    // Build the frequency bin list
    let mut freq_bins: Vec<f32> = Vec::new();
    let mut f = low_hz;
    while f <= high_hz {
        freq_bins.push(f);
        f += step_hz;
    }
    if freq_bins.is_empty() {
        return vec![(low_hz + high_hz) / 2.0];
    }

    // Chunk parameters: ~5 seconds with 50% overlap (2.5s hop)
    let chunk_samples = (sample_rate as usize) * 5;
    let hop_samples = chunk_samples / 2; // 2.5s hop

    // For very short audio, use single chunk covering everything
    let chunk_samples = chunk_samples.min(active.len());
    let hop_samples = if chunk_samples >= active.len() {
        active.len() // single chunk, no hopping
    } else {
        hop_samples.max(1)
    };

    // Candidate tracking: (freq_bin_index) → (presence_count, max_single_chunk_energy)
    let num_bins = freq_bins.len();
    let mut presence_count: Vec<usize> = vec![0; num_bins];
    let mut max_chunk_energy: Vec<f32> = vec![0.0; num_bins];
    let mut num_chunks = 0usize;

    // Iterate over chunks
    let mut chunk_start = 0usize;
    while chunk_start < active.len() {
        let chunk_end = (chunk_start + chunk_samples).min(active.len());
        let chunk = &active[chunk_start..chunk_end];

        // Number of 50ms Goertzel windows in this chunk
        let num_windows = chunk.len() / window_size;
        if num_windows == 0 {
            chunk_start += hop_samples;
            continue;
        }

        // Compute energy at each frequency bin, accumulated across windows in this chunk
        let mut chunk_energies: Vec<f32> = Vec::with_capacity(num_bins);
        for &freq in &freq_bins {
            let mut total = 0.0f32;
            for w in 0..num_windows {
                let start = w * window_size;
                let window = &chunk[start..start + window_size];
                total += goertzel_energy_at(freq, window);
            }
            // Normalize by number of windows so chunk size doesn't bias energy
            chunk_energies.push(total / num_windows as f32);
        }

        // Find local maxima in this chunk's energy spectrum
        let mut chunk_peaks: Vec<(usize, f32)> = Vec::new(); // (bin_index, energy)
        for i in 1..num_bins.saturating_sub(1) {
            let e = chunk_energies[i];
            if e > chunk_energies[i - 1] && e > chunk_energies[i + 1] {
                chunk_peaks.push((i, e));
            }
        }

        if !chunk_peaks.is_empty() {
            // Chunk noise floor: 10% of strongest peak in this chunk.
            // Filters Goertzel sidelobes (-13 dB ≈ 5% for rectangular windows).
            let max_peak = chunk_peaks.iter().map(|&(_, e)| e).fold(0.0f32, f32::max);
            let noise_floor = max_peak * 0.10;

            for &(bin_idx, energy) in &chunk_peaks {
                if energy > noise_floor {
                    presence_count[bin_idx] += 1;
                    if energy > max_chunk_energy[bin_idx] {
                        max_chunk_energy[bin_idx] = energy;
                    }
                }
            }
        }

        num_chunks += 1;
        chunk_start += hop_samples;
    }

    // Minimum presence threshold: ≥2 chunks, or ≥1 if recording is very short (≤2 chunks)
    let min_presence = if num_chunks <= 2 { 1 } else { 2 };

    // Collect candidates that meet the presence threshold
    let mut candidates: Vec<(f32, usize, f32)> = Vec::new(); // (freq, presence, max_energy)
    for (i, &freq) in freq_bins.iter().enumerate() {
        if presence_count[i] >= min_presence {
            candidates.push((freq, presence_count[i], max_chunk_energy[i]));
        }
    }

    if candidates.is_empty() {
        return vec![detect_peak_frequency(
            samples,
            sample_rate,
            low_hz,
            high_hz,
            step_hz,
        )];
    }

    // Global energy floor: require each candidate's max chunk energy to be
    // at least 10% of the strongest candidate's max energy. In chunks where
    // only noise exists, any noise peak becomes the "strongest" and passes
    // the per-chunk 10% filter. This global filter catches consistently
    // present but very weak noise/sidelobes while preserving real secondary
    // operators. 10% threshold (-10 dB) is generous: a hunter responding
    // to a POTA activator is typically >20% of the activator's energy in
    // their active chunks, since operator activity is time-separated and
    // each dominates their own chunks.
    let global_max_energy = candidates.iter().map(|&(_, _, e)| e).fold(0.0f32, f32::max);
    let energy_floor = global_max_energy * 0.10;
    candidates.retain(|&(_, _, e)| e >= energy_floor);

    if candidates.is_empty() {
        return vec![detect_peak_frequency(
            samples,
            sample_rate,
            low_hz,
            high_hz,
            step_hz,
        )];
    }

    // Sort by presence count descending, break ties by max energy descending
    candidates.sort_by(|a, b| {
        b.1.cmp(&a.1)
            .then_with(|| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal))
    });

    // Enforce minimum separation: keep higher-presence peak when two are close
    let mut selected: Vec<(f32, usize, f32)> = Vec::new();
    for &(freq, pres, energy) in &candidates {
        let too_close = selected
            .iter()
            .any(|&(sf, _, _)| (freq - sf).abs() < min_separation_hz);
        if !too_close {
            selected.push((freq, pres, energy));
        }
    }

    // Cap at max_tones
    selected.truncate(max_tones);

    if selected.is_empty() {
        return vec![detect_peak_frequency(
            samples,
            sample_rate,
            low_hz,
            high_hz,
            step_hz,
        )];
    }

    // Fine-scan each selected peak to 1 Hz resolution using full recording
    let num_windows_full = (active.len() / window_size).min(200);
    let num_windows_full = num_windows_full.max(1);
    let mut refined: Vec<f32> = Vec::new();
    for &(coarse_freq, _, _) in &selected {
        let fine_low = (coarse_freq - step_hz).max(low_hz);
        let fine_high = (coarse_freq + step_hz).min(high_hz);
        let mut best_freq = coarse_freq;
        let mut best_energy = 0.0f32;
        let mut f = fine_low;
        while f <= fine_high {
            let mut total_energy = 0.0f32;
            for w in 0..num_windows_full {
                let start = w * window_size;
                let window = &active[start..start + window_size];
                total_energy += goertzel_energy_at(f, window);
            }
            if total_energy > best_energy {
                best_energy = total_energy;
                best_freq = f;
            }
            f += 1.0;
        }
        refined.push(best_freq);
    }

    // Sort by frequency ascending
    refined.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    tracing::info!(
        tones = refined.len(),
        chunks = num_chunks,
        frequencies = ?refined.iter().map(|f| format!("{:.0}", f)).collect::<Vec<_>>(),
        "Detected CW tone frequencies (chunked)"
    );

    refined
}

/// Find the optimal threshold separating a bimodal distribution using
/// Otsu's method in log space. Input must be sorted ascending.
///
/// CW energies span many orders of magnitude (0.1 to 2000+), so Otsu
/// on raw values is dominated by the high-energy tail. Log transform
/// normalizes the scale for proper bimodal separation.
pub fn otsu_threshold_log(sorted: &[f32]) -> f32 {
    if sorted.len() < 4 {
        return sorted.get(sorted.len() / 2).copied().unwrap_or(0.0);
    }

    let log_values: Vec<f64> = sorted.iter().map(|&e| (e.max(1e-10) as f64).ln()).collect();

    let n = log_values.len() as f64;
    let total_sum: f64 = log_values.iter().sum();

    let mut best_variance = 0.0f64;
    let mut best_idx = sorted.len() / 2;
    let mut sum_below = 0.0f64;

    let step = (sorted.len() / 100).max(1);
    for i in (step..sorted.len() - step).step_by(step) {
        for val in &log_values[i.saturating_sub(step)..i] {
            sum_below += val;
        }

        let w0 = (i as f64) / n;
        let w1 = 1.0 - w0;
        if w0 < 0.05 || w1 < 0.05 {
            continue;
        }

        let mean0 = sum_below / i as f64;
        let mean1 = (total_sum - sum_below) / (n - i as f64);
        let between_var = w0 * w1 * (mean0 - mean1) * (mean0 - mean1);

        if between_var > best_variance {
            best_variance = between_var;
            best_idx = i;
        }
    }

    let threshold =
        ((sorted[best_idx] as f64) * (sorted[best_idx.saturating_sub(1)] as f64)).sqrt();
    threshold as f32
}

/// Compute Goertzel energy for a window of samples at the given frequency.
pub fn goertzel_energy(samples: &[f32], freq: f32, sample_rate: u32) -> f32 {
    let k = freq * samples.len() as f32 / sample_rate as f32;
    let coeff = 2.0 * (2.0 * std::f32::consts::PI * k / samples.len() as f32).cos();
    let mut s1: f32 = 0.0;
    let mut s2: f32 = 0.0;
    for &s in samples {
        let s0 = s + coeff * s1 - s2;
        s2 = s1;
        s1 = s0;
    }
    s1 * s1 + s2 * s2 - coeff * s1 * s2
}

/// Goertzel-based tone detector that converts audio samples into keying events.
///
/// Uses the Goertzel algorithm to compute energy at a target frequency in
/// fixed-size windows. An adaptive threshold (based on the noise floor from
/// the first N windows) and hysteresis prevent chatter at the on/off boundary.
pub struct ToneDetector {
    /// Goertzel coefficient for the target frequency.
    coeff: f32,
    /// Number of samples per analysis window.
    window_size: usize,
    /// Sample rate in Hz.
    sample_rate: u32,

    /// Samples accumulated toward the current window.
    buffer: Vec<f32>,
    /// Total samples processed so far (global offset).
    total_samples: usize,

    /// Whether the tone is currently detected as "on".
    tone_on: bool,

    /// Ring buffer of recent window energies for envelope smoothing.
    /// Using the average of the last N windows reduces false positives
    /// from single-window noise spikes.
    energy_ring: Vec<f32>,
    /// Number of windows to average for envelope smoothing.
    smooth_windows: usize,
    /// Write position in the ring buffer.
    ring_pos: usize,
    /// Number of windows written so far (for initial fill).
    ring_count: usize,

    /// Energy measurements from early windows to compute noise floor.
    calibration_energies: Vec<f32>,
    /// Number of windows used for calibration.
    calibration_windows: usize,
    /// Whether calibration is complete.
    calibrated: bool,

    /// Threshold for tone-on detection (set after calibration).
    on_threshold: f32,
    /// Threshold for tone-off detection (lower, for hysteresis).
    off_threshold: f32,

    /// Consecutive below-threshold windows needed to transition off.
    off_debounce: usize,
    /// Counter of consecutive below-threshold windows.
    below_count: usize,
    /// Sample offset of the first below-threshold window in the current run.
    first_below_offset: usize,

    /// Consecutive above-threshold windows needed to transition on.
    on_debounce: usize,
    /// Counter of consecutive above-threshold windows.
    above_count: usize,
    /// Sample offset of the first above-threshold window in the current run.
    first_above_offset: usize,

    /// Goertzel coefficient for lower off-frequency gate (target - 150 Hz).
    gate_coeff_low: f32,
    /// Goertzel coefficient for upper off-frequency gate (target + 150 Hz).
    gate_coeff_high: f32,
    /// Minimum ratio of target energy to max off-frequency energy for tone-on.
    gate_ratio: f32,

    // --- Adaptive noise floor fields ---
    /// Whether adaptive noise floor tracking is enabled.
    adaptive_enabled: bool,
    /// Current noise floor estimate (Goertzel energy units).
    noise_floor: f32,
    /// Slow EMA rate (~1s time constant at 100 windows/s).
    alpha_slow: f32,
    /// Fast EMA rate for recovery after extended signal (~100ms time constant).
    alpha_fast: f32,
    /// Ratio of on_threshold to noise_floor (linear, ~9 dB).
    on_ratio: f32,
    /// Hysteresis ratio: off_threshold = on_threshold * hysteresis_ratio.
    hysteresis_ratio: f32,
    /// Consecutive ON windows counter for extended-signal detection.
    on_duration_windows: usize,
    /// Threshold for triggering fast recovery (50 windows = 500ms at 10ms).
    extended_on_threshold: usize,
    /// Duration of fast-alpha recovery period (20 windows = 200ms at 10ms).
    fast_recovery_windows: usize,
    /// Countdown of remaining fast-recovery windows.
    fast_recovery_remaining: usize,

    // --- Time-windowed calibration ---
    /// Per-segment calibration thresholds from windowed Otsu. Empty if audio
    /// is too short for windowed calibration (falls back to global Otsu).
    windowed_thresholds: Vec<WindowedThreshold>,
    /// Index of the current windowed threshold segment (avoids re-searching).
    current_windowed_idx: usize,
}

/// Pre-calibrated noise floor and thresholds for a time segment.
/// Computed during `calibrate_from_audio()` using windowed Otsu.
#[derive(Debug, Clone)]
struct WindowedThreshold {
    /// Center sample offset of this segment.
    center_sample: usize,
    /// Noise floor for this segment (median of Otsu noise cluster).
    noise_floor: f32,
    /// On-threshold for this segment.
    on_threshold: f32,
    /// Off-threshold for this segment.
    off_threshold: f32,
}

impl ToneDetector {
    /// Create a new tone detector.
    ///
    /// - `target_freq`: frequency to detect (Hz)
    /// - `sample_rate`: audio sample rate (Hz)
    /// - `window_ms`: analysis window duration (milliseconds)
    pub fn new(target_freq: f32, sample_rate: u32, window_ms: u32) -> Self {
        let window_size = (sample_rate * window_ms / 1000) as usize;

        // Goertzel coefficient: 2*cos(2*pi*k/N) where k = freq*N/sample_rate
        let k = target_freq * window_size as f32 / sample_rate as f32;
        let coeff = 2.0 * (2.0 * std::f32::consts::PI * k / window_size as f32).cos();

        // Off-frequency gate coefficients at ±150 Hz from target.
        // Used for spectral flatness gating: reject broadband noise bursts
        // that have similar energy at target and off-frequencies.
        let gate_offset = 150.0f32;
        let low_freq = (target_freq - gate_offset).max(100.0);
        let high_freq = target_freq + gate_offset;
        let k_low = low_freq * window_size as f32 / sample_rate as f32;
        let gate_coeff_low = 2.0 * (2.0 * std::f32::consts::PI * k_low / window_size as f32).cos();
        let k_high = high_freq * window_size as f32 / sample_rate as f32;
        let gate_coeff_high =
            2.0 * (2.0 * std::f32::consts::PI * k_high / window_size as f32).cos();

        // Use first 500ms of audio for calibration
        let calibration_windows = (500 / window_ms).max(1) as usize;

        // Require 2 consecutive below-threshold windows (20ms) before declaring
        // tone-off. This prevents single-window noise dips from fragmenting CW
        // elements, while still being well below a dit at 20 WPM (~60ms).
        let off_debounce = 2;

        let on_debounce = 1;

        // No envelope smoothing: use per-window energy directly. Smoothing
        // blurs CW element boundaries and can cause the detector to miss
        // short elements. The merge step handles noise fragmentation.
        let smooth_windows = 1;

        Self {
            coeff,
            window_size,
            sample_rate,
            buffer: Vec::with_capacity(window_size),
            total_samples: 0,
            tone_on: false,
            energy_ring: vec![0.0; smooth_windows],
            smooth_windows,
            ring_pos: 0,
            ring_count: 0,
            calibration_energies: Vec::with_capacity(calibration_windows),
            calibration_windows,
            calibrated: false,
            on_threshold: f32::MAX,
            off_threshold: f32::MAX,
            off_debounce,
            below_count: 0,
            first_below_offset: 0,
            on_debounce,
            above_count: 0,
            first_above_offset: 0,
            gate_coeff_low,
            gate_coeff_high,
            gate_ratio: 4.0,
            adaptive_enabled: false,
            noise_floor: 0.0,
            alpha_slow: 0.01,
            alpha_fast: 0.10,
            on_ratio: 8.0,
            hysteresis_ratio: 0.8,
            on_duration_windows: 0,
            extended_on_threshold: 50, // 500ms at 10ms windows
            fast_recovery_windows: 20, // 200ms at 10ms windows
            fast_recovery_remaining: 0,
            windowed_thresholds: Vec::new(),
            current_windowed_idx: 0,
        }
    }

    /// Pre-calibrate thresholds from a full audio buffer.
    ///
    /// Computes Goertzel energy for every window in the buffer, then uses
    /// the 10th percentile as the noise floor. This is more robust than
    /// calibrating on just the first 500ms, especially when the audio
    /// starts directly with CW signal (no leading silence).
    ///
    /// Must be called before `process()`. Marks calibration as complete
    /// so the automatic calibration is skipped.
    pub fn calibrate_from_audio(&mut self, samples: &[f32]) {
        // Compute Goertzel energy for every analysis window, preserving time order.
        let mut energies: Vec<f32> = Vec::new();
        for chunk in samples.chunks(self.window_size) {
            if chunk.len() == self.window_size {
                energies.push(self.goertzel_energy(chunk));
            }
        }

        if energies.is_empty() {
            self.calibrated = true;
            return;
        }

        // --- Global Otsu (fallback, and initial threshold) ---
        let mut sorted = energies.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let threshold = Self::otsu_threshold(&sorted);
        let min_threshold = 0.001;
        self.on_threshold = threshold.max(min_threshold);
        self.off_threshold = (threshold * 0.8).max(min_threshold * 0.75);

        let noise_median = {
            let noise_cluster: Vec<f32> =
                sorted.iter().filter(|&&e| e < threshold).copied().collect();
            if noise_cluster.is_empty() {
                self.on_threshold / self.on_ratio
            } else {
                noise_cluster[noise_cluster.len() / 2]
            }
        };
        self.noise_floor = noise_median.max(1e-10);

        #[cfg(test)]
        eprintln!(
            "Otsu threshold: {:.6}  on_threshold: {:.6}  off_threshold: {:.6}  noise_floor: {:.6}",
            threshold, self.on_threshold, self.off_threshold, self.noise_floor,
        );

        // --- Windowed Otsu (time-local thresholds) ---
        // 3-second segments with 1.5s hop (50% overlap).
        // Each segment gets its own Otsu threshold, allowing the noise floor
        // to track QSB fading and band condition changes.
        let segment_windows = (3.0 * self.sample_rate as f64 / self.window_size as f64) as usize;
        let hop_windows = segment_windows / 2;
        let min_segment_windows = 30; // Need enough for Otsu statistics

        if energies.len() >= min_segment_windows && segment_windows >= min_segment_windows {
            let mut windowed = Vec::new();
            let mut seg_start = 0;

            while seg_start + min_segment_windows <= energies.len() {
                let seg_end = (seg_start + segment_windows).min(energies.len());
                let seg_energies = &energies[seg_start..seg_end];

                let mut seg_sorted: Vec<f32> = seg_energies.to_vec();
                seg_sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

                let seg_threshold = Self::otsu_threshold(&seg_sorted);
                let seg_on = seg_threshold.max(min_threshold);
                let seg_off = (seg_threshold * 0.8).max(min_threshold * 0.75);

                let seg_noise = {
                    let cluster: Vec<f32> = seg_sorted
                        .iter()
                        .filter(|&&e| e < seg_threshold)
                        .copied()
                        .collect();
                    if cluster.is_empty() {
                        seg_on / self.on_ratio
                    } else {
                        cluster[cluster.len() / 2]
                    }
                };

                // Center sample of this segment
                let center_window = seg_start + (seg_end - seg_start) / 2;
                let center_sample = center_window * self.window_size + self.window_size / 2;

                windowed.push(WindowedThreshold {
                    center_sample,
                    noise_floor: seg_noise.max(1e-10),
                    on_threshold: seg_on,
                    off_threshold: seg_off,
                });

                if seg_start + hop_windows >= energies.len() {
                    break;
                }
                seg_start += hop_windows;
            }

            if !windowed.is_empty() {
                tracing::debug!(
                    segments = windowed.len(),
                    first_on = format!("{:.4}", windowed.first().unwrap().on_threshold),
                    last_on = format!("{:.4}", windowed.last().unwrap().on_threshold),
                    "Windowed calibration complete"
                );
                self.windowed_thresholds = windowed;
                self.current_windowed_idx = 0;
            }
        }

        // Log energy distribution for diagnostics
        let p5 = sorted[sorted.len() / 20];
        let p25 = sorted[sorted.len() / 4];
        let p50 = sorted[sorted.len() / 2];
        let p75 = sorted[3 * sorted.len() / 4];
        let p90 = sorted[9 * sorted.len() / 10];
        tracing::info!(
            windows = sorted.len(),
            p5 = format!("{:.4}", p5),
            p25 = format!("{:.4}", p25),
            p50 = format!("{:.4}", p50),
            p75 = format!("{:.4}", p75),
            p90 = format!("{:.4}", p90),
            on_threshold = format!("{:.6}", self.on_threshold),
            off_threshold = format!("{:.6}", self.off_threshold),
            windowed_segments = self.windowed_thresholds.len(),
            "calibrate_from_audio complete (Otsu)"
        );

        self.calibrated = true;
    }

    /// Look up the windowed noise floor and thresholds for a given sample offset.
    ///
    /// Linearly interpolates between adjacent segment centers for smooth
    /// transitions. Returns `None` if no windowed calibration was performed
    /// (short recordings fall back to global Otsu).
    fn windowed_threshold_at(&self, sample_offset: usize) -> Option<(f32, f32, f32)> {
        let wt = &self.windowed_thresholds;
        if wt.is_empty() {
            return None;
        }
        if wt.len() == 1 {
            return Some((wt[0].noise_floor, wt[0].on_threshold, wt[0].off_threshold));
        }

        // Clamp to first/last segment
        if sample_offset <= wt[0].center_sample {
            return Some((wt[0].noise_floor, wt[0].on_threshold, wt[0].off_threshold));
        }
        let last = wt.len() - 1;
        if sample_offset >= wt[last].center_sample {
            return Some((
                wt[last].noise_floor,
                wt[last].on_threshold,
                wt[last].off_threshold,
            ));
        }

        // Find the two bracketing segments and interpolate
        // Start search from current_windowed_idx for efficiency (usually sequential)
        let mut lo = 0;
        for i in 0..last {
            if wt[i].center_sample <= sample_offset && sample_offset < wt[i + 1].center_sample {
                lo = i;
                break;
            }
        }
        let hi = lo + 1;

        let span = (wt[hi].center_sample - wt[lo].center_sample) as f32;
        let t = (sample_offset - wt[lo].center_sample) as f32 / span;

        let noise = wt[lo].noise_floor + t * (wt[hi].noise_floor - wt[lo].noise_floor);
        let on = wt[lo].on_threshold + t * (wt[hi].on_threshold - wt[lo].on_threshold);
        let off = wt[lo].off_threshold + t * (wt[hi].off_threshold - wt[lo].off_threshold);

        Some((noise.max(1e-10), on.max(0.001), off.max(0.00075)))
    }

    /// Process a chunk of audio samples, returning keying events.
    pub fn process(&mut self, samples: &[f32]) -> Vec<KeyingEvent> {
        let mut events = Vec::new();

        for &sample in samples {
            self.buffer.push(sample);

            if self.buffer.len() == self.window_size {
                let window_start = self.total_samples + 1 - self.window_size;

                let energy = self.goertzel_energy(&self.buffer);

                // Update energy ring buffer for smoothing
                self.energy_ring[self.ring_pos] = energy;
                self.ring_pos = (self.ring_pos + 1) % self.smooth_windows;
                self.ring_count += 1;

                // Compute smoothed energy (average of ring buffer)
                let smoothed = if self.ring_count >= self.smooth_windows {
                    self.energy_ring.iter().sum::<f32>() / self.smooth_windows as f32
                } else {
                    // Not enough windows yet — use current energy
                    energy
                };

                if !self.calibrated {
                    self.calibration_energies.push(energy);
                    if self.calibration_energies.len() >= self.calibration_windows {
                        self.finish_calibration();
                    }
                } else {
                    // Use smoothed energy for thresholding. The 3-window
                    // running average suppresses single-window noise spikes
                    // while preserving sustained CW tones.
                    self.detect_transition(smoothed, window_start, &mut events);
                }

                self.buffer.clear();
            }

            self.total_samples += 1;
        }

        events
    }

    /// Finalize detection, emitting a final Off event if the tone is still on.
    pub fn finalize(&mut self) -> Option<KeyingEvent> {
        if self.tone_on {
            self.tone_on = false;
            Some(KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: self.total_samples,
            })
        } else {
            None
        }
    }

    /// Enable adaptive noise floor tracking.
    ///
    /// Must be called after `calibrate_from_audio()`. Uses the noise cluster
    /// median from calibration as the initial noise floor, then tracks changes
    /// via exponential moving average during OFF periods.
    pub fn enable_adaptive(&mut self) {
        self.adaptive_enabled = true;
        // noise_floor was set during calibrate_from_audio; if not calibrated,
        // derive from the static threshold
        if self.noise_floor < 1e-10 {
            self.noise_floor = (self.on_threshold / self.on_ratio).max(1e-10);
        }
    }

    /// Update the adaptive noise floor estimate based on current energy.
    ///
    /// During OFF periods: EMA-tracks the noise floor and recalculates thresholds.
    /// During ON periods: freezes the noise floor (signal energy would inflate it).
    /// After extended ON periods (≥500ms): switches to fast alpha for quick recovery.
    fn update_noise_floor(&mut self, energy: f32) {
        if !self.adaptive_enabled {
            return;
        }

        if self.tone_on {
            self.on_duration_windows += 1;
            return;
        }

        // Only update noise floor when energy is clearly below the ON threshold.
        // Windows with energy near/above the threshold are likely signal, not noise,
        // even if tone_on hasn't triggered yet (pre-debounce).
        if energy >= self.on_threshold {
            return;
        }

        // Transitioning from ON to OFF: check for extended signal
        if self.on_duration_windows >= self.extended_on_threshold {
            self.fast_recovery_remaining = self.fast_recovery_windows;
        }
        self.on_duration_windows = 0;

        // Choose alpha: fast if recovering from extended signal, slow otherwise
        let alpha = if self.fast_recovery_remaining > 0 {
            self.fast_recovery_remaining -= 1;
            self.alpha_fast
        } else {
            self.alpha_slow
        };

        // EMA update, clamped to prevent floor from dropping too low
        self.noise_floor = (alpha * energy + (1.0 - alpha) * self.noise_floor).max(1e-10);

        // Recalculate thresholds from adaptive noise floor
        self.on_threshold = (self.noise_floor * self.on_ratio).max(0.001);
        self.off_threshold = (self.on_threshold * self.hysteresis_ratio).max(0.00075);
    }

    /// Find the optimal threshold separating a bimodal distribution using
    /// Otsu's method in log space. Input must be sorted ascending.
    ///
    /// CW energies span many orders of magnitude (0.1 to 2000+), so Otsu
    /// on raw values is dominated by the high-energy tail. Log transform
    /// normalizes the scale for proper bimodal separation.
    fn otsu_threshold(sorted: &[f32]) -> f32 {
        // Transform to log space (skip zeros/near-zeros)
        let log_values: Vec<f64> = sorted.iter().map(|&e| (e.max(1e-10) as f64).ln()).collect();

        let n = log_values.len() as f64;
        let total_sum: f64 = log_values.iter().sum();

        let mut best_variance = 0.0f64;
        let mut best_idx = sorted.len() / 2;
        let mut sum_below = 0.0f64;

        // Sample every ~1% to keep this fast.
        let step = (sorted.len() / 100).max(1);
        for i in (step..sorted.len() - step).step_by(step) {
            for val in &log_values[i.saturating_sub(step)..i] {
                sum_below += val;
            }

            let w0 = (i as f64) / n;
            let w1 = 1.0 - w0;
            if w0 < 0.05 || w1 < 0.05 {
                continue;
            }

            let mean0 = sum_below / i as f64;
            let mean1 = (total_sum - sum_below) / (n - i as f64);
            let between_var = w0 * w1 * (mean0 - mean1) * (mean0 - mean1);

            if between_var > best_variance {
                best_variance = between_var;
                best_idx = i;
            }
        }

        // Threshold is the geometric mean of the values at the split point
        let threshold =
            ((sorted[best_idx] as f64) * (sorted[best_idx.saturating_sub(1)] as f64)).sqrt();
        threshold as f32
    }

    /// Compute Goertzel energy for a window of samples at the target frequency.
    fn goertzel_energy(&self, samples: &[f32]) -> f32 {
        Self::goertzel_energy_with_coeff(samples, self.coeff)
    }

    /// Compute Goertzel energy for a window using an arbitrary coefficient.
    fn goertzel_energy_with_coeff(samples: &[f32], coeff: f32) -> f32 {
        let mut s1: f32 = 0.0;
        let mut s2: f32 = 0.0;

        for &sample in samples {
            let s0 = sample + coeff * s1 - s2;
            s2 = s1;
            s1 = s0;
        }

        // Energy = s1^2 + s2^2 - coeff*s1*s2
        s1 * s1 + s2 * s2 - coeff * s1 * s2
    }

    /// Set thresholds based on calibration energies using Otsu's method.
    fn finish_calibration(&mut self) {
        if self.calibration_energies.is_empty() {
            let min_threshold = 0.001;
            self.on_threshold = min_threshold;
            self.off_threshold = min_threshold * 0.75;
        } else {
            let mut sorted = self.calibration_energies.clone();
            sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            let threshold = Self::otsu_threshold(&sorted);
            let min_threshold = 0.001;
            self.on_threshold = threshold.max(min_threshold);
            self.off_threshold = (threshold * 0.8).max(min_threshold * 0.75);
        }

        self.calibrated = true;
    }

    /// Check energy against thresholds and emit On/Off events.
    ///
    /// Uses debouncing for off transitions: requires `off_debounce`
    /// consecutive below-threshold windows before emitting Off. This
    /// prevents single-window noise dips from fragmenting CW elements.
    /// Check spectral flatness gate: target energy must exceed off-frequency
    /// energy by `gate_ratio`. Returns true if the gate passes (narrowband tone
    /// detected) or false if the energy looks broadband (noise burst).
    fn passes_spectral_gate(&self) -> bool {
        let off_low = Self::goertzel_energy_with_coeff(&self.buffer, self.gate_coeff_low);
        let off_high = Self::goertzel_energy_with_coeff(&self.buffer, self.gate_coeff_high);
        let max_off = off_low.max(off_high).max(1e-10);
        let target = self.goertzel_energy(&self.buffer);
        target / max_off >= self.gate_ratio
    }

    fn detect_transition(
        &mut self,
        energy: f32,
        sample_offset: usize,
        events: &mut Vec<KeyingEvent>,
    ) {
        // Apply time-windowed calibration: blend noise floor toward the
        // pre-computed windowed Otsu value for this time position. Only the
        // noise_floor is blended — thresholds are derived from it by the
        // adaptive EMA (update_noise_floor), maintaining a single source of truth.
        //
        // The blend rate (5% per 10ms window ≈ 200ms convergence) is fast enough
        // to track QSB fading (10-30s) but slow enough not to override the
        // reactive EMA during rapid noise floor changes.
        if let Some((w_noise, _, _)) = self.windowed_threshold_at(sample_offset) {
            let blend = 0.05;
            self.noise_floor = (self.noise_floor + blend * (w_noise - self.noise_floor)).max(1e-10);
            // Derive thresholds from the blended noise floor so they stay consistent.
            // The EMA in update_noise_floor will further refine these if OFF.
            self.on_threshold = (self.noise_floor * self.on_ratio).max(0.001);
            self.off_threshold = (self.on_threshold * self.hysteresis_ratio).max(0.00075);
        }

        self.update_noise_floor(energy);

        if !self.tone_on {
            if energy >= self.on_threshold {
                // Spectral flatness gate: only count this window toward
                // on-debounce if the energy is narrowband (target >> off-freq).
                // If the gate fails, DON'T reset above_count — just skip this
                // window. This prevents broadband noise from triggering tone-on
                // while allowing real CW tones that occasionally fail the gate
                // (due to noise contamination) to still accumulate enough
                // consecutive windows.
                if !self.passes_spectral_gate() {
                    return;
                }
                if self.above_count == 0 {
                    self.first_above_offset = sample_offset;
                }
                self.above_count += 1;
                if self.above_count >= self.on_debounce {
                    self.tone_on = true;
                    self.below_count = 0;
                    self.above_count = 0;
                    // Emit On at the first above-threshold window
                    events.push(KeyingEvent {
                        kind: KeyingEventKind::On,
                        sample_offset: self.first_above_offset,
                    });
                }
            } else {
                // Energy dropped below threshold — reset on-debounce
                self.above_count = 0;
            }
        } else if energy < self.off_threshold {
            if self.below_count == 0 {
                self.first_below_offset = sample_offset;
            }
            self.below_count += 1;
            if self.below_count >= self.off_debounce {
                self.tone_on = false;
                self.below_count = 0;
                // Emit Off at the first below-threshold window
                events.push(KeyingEvent {
                    kind: KeyingEventKind::Off,
                    sample_offset: self.first_below_offset,
                });
            }
        } else {
            // Energy came back above threshold — reset debounce
            self.below_count = 0;
        }
    }

    /// Get the on-threshold (set after calibration).
    pub fn on_threshold(&self) -> f32 {
        self.on_threshold
    }

    /// Get the sample rate.
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }
}

/// Per-frequency-bin SNR estimate from `estimate_spectral_snr()`.
#[derive(Debug, Clone)]
struct BinSnr {
    /// Frequency bin index.
    bin_idx: usize,
    /// Median energy across all time windows (noise floor at this frequency, diagnostic).
    #[allow(dead_code)]
    median_energy: f32,
    /// Peak percentile energy across all time windows (diagnostic).
    #[allow(dead_code)]
    peak_energy: f32,
    /// SNR: ratio of peak percentile to median. High values indicate a tone stands out.
    snr: f32,
}

/// Estimate per-frequency-bin noise floor and identify signal-bearing bins using
/// cross-bin outlier detection on p99 energy.
///
/// **Why cross-bin?** The old per-bin p99/median ratio fails for broadband noise:
/// noise variance naturally gives p99/median ≈ 3x for ALL bins (chi-squared
/// distribution property). Instead, we compare each bin's p99 against the
/// population of ALL bins' p99 values. In broadband noise, all p99s cluster
/// together (no outliers). With real CW, signal bins have elevated p99 values
/// that stand out as statistical outliers.
///
/// Uses robust statistics (median + MAD) to detect outliers, with `z_threshold`
/// controlling sensitivity (higher = fewer candidates, more conservative).
///
/// Returns `(outlier_bins, global_noise_floor, noise_dominated)`:
/// - `outlier_bins`: bins whose p99 is a statistical outlier, sorted by SNR desc
/// - `global_noise_floor`: median of all per-bin medians
/// - `noise_dominated`: true if no bins stand out (broadband noise scenario)
///
/// `spectrogram` layout: `spectrogram[time_idx][freq_idx]`.
fn estimate_spectral_snr(
    spectrogram: &[Vec<f32>],
    num_bins: usize,
    z_threshold: f32,
) -> (Vec<BinSnr>, f32, bool) {
    if spectrogram.is_empty() || num_bins == 0 {
        return (Vec::new(), 0.0, true);
    }

    let num_windows = spectrogram.len();
    let mut all_medians: Vec<f32> = Vec::with_capacity(num_bins);
    let mut all_peaks: Vec<f32> = Vec::with_capacity(num_bins);
    // (bin_idx, median_energy, p99_energy)
    let mut bin_data: Vec<(usize, f32, f32)> = Vec::with_capacity(num_bins);

    for bin_idx in 0..num_bins {
        let mut energies: Vec<f32> = Vec::with_capacity(num_windows);
        for t in 0..num_windows {
            energies.push(spectrogram[t][bin_idx]);
        }
        energies.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let median = energies[energies.len() / 2];

        // Use p99 to catch brief transmissions (p90 misses hunters active <2% of time)
        let peak_idx = if num_windows >= 100 {
            ((num_windows as f32 * 0.99) as usize).min(num_windows - 1)
        } else {
            ((num_windows as f32 * 0.95) as usize).min(num_windows - 1)
        };
        let peak = energies[peak_idx];

        all_medians.push(median);
        all_peaks.push(peak);
        bin_data.push((bin_idx, median, peak));
    }

    // Global noise floor: median of all per-bin medians
    let mut sorted_medians = all_medians.clone();
    sorted_medians.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let global_noise_floor = sorted_medians[sorted_medians.len() / 2];

    // Cross-bin outlier detection on p99 values
    let mut sorted_peaks = all_peaks.clone();
    sorted_peaks.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let median_peak = sorted_peaks[sorted_peaks.len() / 2];

    // MAD (Median Absolute Deviation) — robust spread estimator
    let mut deviations: Vec<f32> = all_peaks.iter().map(|&p| (p - median_peak).abs()).collect();
    deviations.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mad = deviations[deviations.len() / 2];

    // Scale MAD to approximate std deviation (σ ≈ 1.4826 × MAD for normal dist)
    let sigma = mad * 1.4826;

    // Outlier threshold: bins with p99 > median_peak + z_threshold × σ
    let threshold = if sigma > 1e-10 {
        median_peak + z_threshold * sigma
    } else {
        // All bins have identical p99 (σ=0) — use 10% above median as fallback
        median_peak * 1.10
    };

    let mut candidates: Vec<BinSnr> = Vec::new();
    for &(bin_idx, median, peak) in &bin_data {
        if peak > threshold {
            let snr = if median > 1e-10 {
                peak / median
            } else if peak > 1e-10 {
                100.0
            } else {
                0.0
            };
            candidates.push(BinSnr {
                bin_idx,
                median_energy: median,
                peak_energy: peak,
                snr,
            });
        }
    }

    // Secondary filter: keep only local peak bins among the candidates.
    // Goertzel spectral leakage creates monotonically decreasing energy on
    // both sides of the real signal. A bin on the sidelobe slope will have
    // a neighbor (closer to the real signal) with higher energy — it's NOT
    // a local maximum. Real signals at different frequencies ARE local maxima
    // even if much weaker than the main signal, since their neighbors (in
    // the noise region between signals) have lower energy.
    if candidates.len() > 1 {
        // Step 1: Keep only local maxima
        let pre_sidelobe = candidates.len();
        candidates.retain(|c| {
            let idx = c.bin_idx;
            let left = if idx > 0 { all_peaks[idx - 1] } else { 0.0 };
            let right = if idx + 1 < num_bins {
                all_peaks[idx + 1]
            } else {
                0.0
            };
            c.peak_energy >= left && c.peak_energy >= right
        });

        // Step 2: Remove secondary sidelobe peaks near a stronger peak.
        // Goertzel sidelobes can have secondary "bumps" that look like
        // local peaks. A secondary peak within ±10 bins (~100 Hz) of a
        // much stronger peak (>20× energy difference) is a sidelobe, not
        // a real independent signal.
        if candidates.len() > 1 {
            // Sort by peak energy descending for greedy filtering
            candidates.sort_by(|a, b| {
                b.peak_energy
                    .partial_cmp(&a.peak_energy)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            let mut keep = vec![true; candidates.len()];
            for i in 0..candidates.len() {
                if !keep[i] {
                    continue;
                }
                for j in (i + 1)..candidates.len() {
                    if !keep[j] {
                        continue;
                    }
                    let dist = (candidates[i].bin_idx as isize - candidates[j].bin_idx as isize)
                        .unsigned_abs();
                    // Within 10 bins (100 Hz at 10 Hz step) and >20× weaker
                    if dist <= 10 && candidates[j].peak_energy < candidates[i].peak_energy * 0.05 {
                        keep[j] = false;
                    }
                }
            }
            let mut idx = 0;
            candidates.retain(|_| {
                let k = keep[idx];
                idx += 1;
                k
            });
        }

        if candidates.len() < pre_sidelobe {
            tracing::info!(
                before = pre_sidelobe,
                after = candidates.len(),
                peaks = ?candidates.iter().map(|c| c.bin_idx).collect::<Vec<_>>(),
                "Cross-bin: local peak + proximity sidelobe rejection"
            );
        }
    }

    candidates.sort_by(|a, b| {
        b.snr
            .partial_cmp(&a.snr)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let noise_dominated = candidates.is_empty();

    // Log candidate bins at debug level
    for c in &candidates {
        tracing::debug!(
            bin_idx = c.bin_idx,
            peak = format!("{:.1}", c.peak_energy),
            median = format!("{:.2}", c.median_energy),
            snr = format!("{:.1}", c.snr),
            z_score = format!(
                "{:.1}",
                if sigma > 1e-10 {
                    (c.peak_energy - median_peak) / sigma
                } else {
                    0.0
                }
            ),
            "Cross-bin outlier candidate"
        );
    }

    tracing::info!(
        total_bins = num_bins,
        candidate_bins = candidates.len(),
        noise_dominated = noise_dominated,
        global_noise_floor = format!("{:.4}", global_noise_floor),
        median_peak = format!("{:.6}", median_peak),
        mad = format!("{:.6}", mad),
        sigma = format!("{:.6}", sigma),
        threshold = format!("{:.6}", threshold),
        peak_range = format!(
            "{:.6}..{:.6}",
            sorted_peaks.first().unwrap_or(&0.0),
            sorted_peaks.last().unwrap_or(&0.0)
        ),
        "Spectral SNR: cross-bin outlier detection"
    );

    (candidates, global_noise_floor, noise_dominated)
}

/// A time-frequency activity region detected by `scan_tone_activity()`.
///
/// Represents a frequency that shows independent CW activity in a specific time
/// window. Used to distinguish real operators from Goertzel sidelobes: sidelobes
/// are active at the same times as their source frequency, while real operators
/// transmit at different times.
#[derive(Debug, Clone)]
pub struct ToneActivity {
    /// Tone frequency, refined to 1 Hz resolution.
    pub freq: f32,
    /// First active sample index in the recording.
    pub start_sample: usize,
    /// Last active sample index in the recording.
    pub end_sample: usize,
}

/// Scan audio for CW tone activity regions using time-frequency analysis.
///
/// Instead of just detecting frequencies, this function maps out WHEN each
/// frequency is active. This allows distinguishing Goertzel sidelobes (which
/// are active at the same time as their source) from real operators (who
/// transmit at different times).
///
/// Algorithm:
/// 1. Goertzel spectrogram: 100ms windows, 50ms hop, freq bins at `step_hz`
/// 2. Per-window peak detection with 10% of window-max threshold
/// 3. Merge contiguous active windows into regions (750ms gap tolerance)
/// 4. Global energy floor: drop regions < 10% of global max
/// 5. Sidelobe rejection: for close frequencies, keep both only if they have
///    independent activity (>= 5 windows where one is active and the other is not)
/// 6. Fine-tune surviving frequencies to 1 Hz resolution
///
/// Returns `Vec<ToneActivity>` sorted by `start_sample`.
pub fn scan_tone_activity(
    samples: &[f32],
    sample_rate: u32,
    low_hz: f32,
    high_hz: f32,
    step_hz: f32,
) -> Vec<ToneActivity> {
    // Spectrogram parameters
    let window_ms = 100; // 100ms analysis windows
    let hop_ms = 50; // 50ms hop (50% overlap)
    let window_samples = (sample_rate as usize * window_ms) / 1000;
    let hop_samples = (sample_rate as usize * hop_ms) / 1000;

    if window_samples == 0 || samples.len() < window_samples {
        return Vec::new();
    }

    // Build frequency bin list
    let mut freq_bins: Vec<f32> = Vec::new();
    let mut f = low_hz;
    while f <= high_hz {
        freq_bins.push(f);
        f += step_hz;
    }
    if freq_bins.is_empty() {
        return Vec::new();
    }
    let num_bins = freq_bins.len();

    // Step 1: Goertzel spectrogram
    let num_windows = (samples.len() - window_samples) / hop_samples + 1;
    if num_windows == 0 {
        return Vec::new();
    }

    // Compute energy for all (time, freq) bins
    // spectrogram[time_idx][freq_idx]
    let mut spectrogram: Vec<Vec<f32>> = Vec::with_capacity(num_windows);
    for w in 0..num_windows {
        let start = w * hop_samples;
        let window = &samples[start..start + window_samples];
        let mut energies = Vec::with_capacity(num_bins);
        for &freq in &freq_bins {
            energies.push(goertzel_energy(window, freq, sample_rate));
        }
        spectrogram.push(energies);
    }

    // Step 1.5: Cross-bin outlier detection
    // Compare each bin's p99 energy against the population. In broadband noise,
    // all bins have similar p99 (no outliers). With real CW, signal bins are
    // statistical outliers. z_threshold=3.0 means "3 sigma above median".
    let (snr_candidates, _global_noise_floor, noise_dominated) =
        estimate_spectral_snr(&spectrogram, num_bins, 3.0);

    // Build candidate bin set. If outlier bins were found, only consider those
    // (plus neighbors). If noise-dominated (no outliers), fall back to all bins
    // but with stricter downstream filtering.
    let candidate_bins: std::collections::HashSet<usize> = if snr_candidates.is_empty() {
        tracing::info!(
            total_bins = num_bins,
            "Cross-bin SNR: no outlier bins, noise-dominated — using all bins with strict filters"
        );
        (0..num_bins).collect()
    } else {
        let mut set = std::collections::HashSet::new();
        for c in &snr_candidates {
            if c.bin_idx > 0 {
                set.insert(c.bin_idx - 1);
            }
            set.insert(c.bin_idx);
            if c.bin_idx + 1 < num_bins {
                set.insert(c.bin_idx + 1);
            }
        }
        tracing::info!(
            snr_candidates = snr_candidates.len(),
            candidate_bins = set.len(),
            total_bins = num_bins,
            "Cross-bin SNR: narrowed candidate bins"
        );
        set
    };

    // Step 2: Per-window peak detection
    // For each freq bin, collect which time windows it's active in.
    // Uses SNR pre-filter from step 1.5: only bins in candidate_bins are
    // considered. The candidate set already excludes pure-noise bins, so
    // per-window detection uses only the relative threshold (10% of window
    // max) — no additional per-bin noise floor check, which would reject
    // weak operators whose tone is only slightly above the noise.
    let mut active_windows: Vec<Vec<usize>> = vec![Vec::new(); num_bins];
    let mut global_max_energy: f32 = 0.0;

    for (t, energies) in spectrogram.iter().enumerate() {
        // Find local maxima in this window's spectrum
        let window_max = energies.iter().fold(0.0f32, |a, &b| a.max(b));
        if window_max < 1e-10 {
            continue;
        }
        let relative_threshold = window_max * 0.10;
        global_max_energy = global_max_energy.max(window_max);

        for i in 1..num_bins.saturating_sub(1) {
            if !candidate_bins.contains(&i) {
                continue;
            }
            let e = energies[i];
            if e <= energies[i - 1] || e <= energies[i + 1] {
                continue; // not a local maximum
            }
            if e < relative_threshold {
                continue;
            }
            active_windows[i].push(t);
        }
        // Check edges
        if num_bins >= 2 {
            if candidate_bins.contains(&0)
                && energies[0] > energies[1]
                && energies[0] >= relative_threshold
            {
                active_windows[0].push(t);
            }
            let last = num_bins - 1;
            if candidate_bins.contains(&last)
                && energies[last] > energies[last - 1]
                && energies[last] >= relative_threshold
            {
                active_windows[last].push(t);
            }
        }
    }

    // Step 2.5: Spectral peakiness filter
    // Reject frequency bins where energy isn't concentrated — the hallmark of
    // broadband noise. Real CW tones are spectrally sharp (high peakiness);
    // broadband noise has similar energy across all bins (low peakiness).
    // Threshold is stricter when noise-dominated (no outlier bins found).
    let peakiness_threshold = if noise_dominated { 0.5 } else { 0.3 };
    let mut peakiness_rejected = 0usize;
    for i in 0..num_bins {
        if active_windows[i].is_empty() {
            continue;
        }
        let mut peakiness_values: Vec<f32> = Vec::new();
        for &t in &active_windows[i] {
            let e = spectrogram[t][i];
            if e < 1e-10 {
                continue;
            }
            // Average energy of nearby bins (±2, clamped to bounds)
            let lo = i.saturating_sub(2);
            let hi = (i + 3).min(num_bins); // exclusive
            let mut neighbor_sum = 0.0f32;
            let mut neighbor_count = 0u32;
            for &energy in &spectrogram[t][lo..hi] {
                neighbor_count += 1;
                neighbor_sum += energy;
            }
            // Subtract the center bin (which was included in the range)
            if lo <= i && i < hi {
                neighbor_sum -= spectrogram[t][i];
                neighbor_count -= 1;
            }
            let neighbor_mean = if neighbor_count > 0 {
                neighbor_sum / neighbor_count as f32
            } else {
                0.0
            };
            let peakiness = (e - neighbor_mean) / (e + 1e-10);
            peakiness_values.push(peakiness);
        }
        if !peakiness_values.is_empty() {
            peakiness_values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            let median_peakiness = peakiness_values[peakiness_values.len() / 2];
            if median_peakiness < peakiness_threshold {
                tracing::debug!(
                    freq = format!("{:.0}", freq_bins[i]),
                    median_peakiness = format!("{:.3}", median_peakiness),
                    active_windows = active_windows[i].len(),
                    threshold = format!("{:.2}", peakiness_threshold),
                    "Peakiness filter rejected frequency bin"
                );
                active_windows[i].clear();
                peakiness_rejected += 1;
            }
        }
    }
    if peakiness_rejected > 0 {
        tracing::info!(
            rejected = peakiness_rejected,
            threshold = format!("{:.2}", peakiness_threshold),
            noise_dominated = noise_dominated,
            "Peakiness filter summary"
        );
    }

    // Step 3-4: Merge into activity regions per frequency
    let gap_tolerance = 750; // ms
    let max_gap_windows = gap_tolerance / hop_ms;
    // Relative energy floor: catch truly negligible energy while allowing
    // weak operators through. The peakiness filter (Step 2.5) handles
    // broadband noise, and expanded sidelobe rejection (Step 5) handles
    // Goertzel spectral leakage. This floor is a final backstop.
    // 0.1% = -30 dB: supports operators ~5 S-units weaker than strongest.
    let energy_floor = (global_max_energy * 0.001).max(0.1);

    struct ActivityRegion {
        freq: f32,
        start_window: usize,
        end_window: usize,
        max_energy: f32,
        active_window_set: Vec<usize>, // for sidelobe rejection
    }

    let mut regions: Vec<ActivityRegion> = Vec::new();

    for (bin_idx, windows) in active_windows.iter().enumerate() {
        if windows.is_empty() {
            continue;
        }

        // Merge contiguous windows
        let mut run_start = windows[0];
        let mut run_end = windows[0];
        let mut run_max_energy: f32 = spectrogram[windows[0]][bin_idx];

        let flush_run = |start: usize,
                         end: usize,
                         max_e: f32,
                         active: &[usize],
                         regions: &mut Vec<ActivityRegion>,
                         freq: f32| {
            if max_e >= energy_floor {
                // Collect the actual active windows in this run
                let set: Vec<usize> = active
                    .iter()
                    .filter(|&&w| w >= start && w <= end)
                    .copied()
                    .collect();
                regions.push(ActivityRegion {
                    freq,
                    start_window: start,
                    end_window: end,
                    max_energy: max_e,
                    active_window_set: set,
                });
            }
        };

        for &w in &windows[1..] {
            if w <= run_end + max_gap_windows {
                // Extend current run
                run_end = w;
                let e = spectrogram[w][bin_idx];
                if e > run_max_energy {
                    run_max_energy = e;
                }
            } else {
                // Flush current run, start new one
                flush_run(
                    run_start,
                    run_end,
                    run_max_energy,
                    windows,
                    &mut regions,
                    freq_bins[bin_idx],
                );
                run_start = w;
                run_end = w;
                run_max_energy = spectrogram[w][bin_idx];
            }
        }
        // Flush last run
        flush_run(
            run_start,
            run_end,
            run_max_energy,
            windows,
            &mut regions,
            freq_bins[bin_idx],
        );
    }

    // Step 4.5: Minimum active window count + density filter
    // Reject regions where the frequency shows scattered noise rather than
    // concentrated CW activity. Uses two criteria (both must pass):
    //
    // Thresholds are stricter when noise-dominated (no outlier bins found
    // in cross-bin analysis), since all surviving regions are suspect.
    //
    // Normal mode: min_absolute=8, min_density=15%
    //   8 windows ≈ 400ms of keying — catches brief CW responses (e.g., a
    //   quiet station's 1-second callsign). Cross-bin SNR pre-filter already
    //   validated that candidate bins have real signal, peakiness filter
    //   removed broadband noise, and sidelobe rejection (step 5) handles
    //   spectral leakage. This floor just filters truly trivial fragments.
    //
    // Noise-dominated mode: min_absolute=40, min_density=25%
    //   Requires stronger evidence of real CW activity to reduce false positives.
    //   40 windows ≈ 2 seconds of keying (still catches brief responses).
    let (min_absolute, min_density) = if noise_dominated {
        let abs = if num_windows > 100 { 40 } else { 5 };
        (abs, 0.25f32)
    } else {
        let abs = if num_windows > 100 { 8 } else { 3 };
        (abs, 0.15f32)
    };
    let pre_filter_count = regions.len();
    regions.retain(|r| {
        let count = r.active_window_set.len();
        let span = (r.end_window - r.start_window + 1).max(1);
        let density = count as f32 / span as f32;
        let pass = count >= min_absolute && density >= min_density;
        if !pass {
            tracing::debug!(
                freq = format!("{:.0}", r.freq),
                active = count,
                span = span,
                density = format!("{:.1}%", density * 100.0),
                reason = if count < min_absolute {
                    "too_few"
                } else {
                    "low_density"
                },
                "Step 4.5 rejected region"
            );
        }
        pass
    });
    if regions.len() < pre_filter_count {
        tracing::info!(
            before = pre_filter_count,
            after = regions.len(),
            min_absolute = min_absolute,
            min_density = format!("{:.0}%", min_density * 100.0),
            noise_dominated = noise_dominated,
            "Filtered regions by active count + density"
        );
    }

    if regions.is_empty() {
        return Vec::new();
    }

    // Step 5: Sidelobe rejection via time independence
    // Sort regions by max_energy descending so stronger ones are checked first.
    // A weaker region is rejected as a sidelobe if it lacks sufficient
    // independent time activity vs ANY stronger region. No frequency distance
    // limit: Goertzel spectral leakage at 100ms windows extends 200+ Hz, and
    // real half-duplex operators always have independent active windows.
    regions.sort_by(|a, b| {
        b.max_energy
            .partial_cmp(&a.max_energy)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // A real half-duplex operator must have substantial time periods where ONLY
    // they are active (not the stronger station). Require at least 20% of the
    // weaker region's active windows to be independent, with a floor of 10.
    // This catches sidelobes that have a few random "independent" windows from
    // noise fluctuations, while keeping real operators who transmit for seconds
    // when the other station is silent.
    let mut keep = vec![true; regions.len()];
    for i in 0..regions.len() {
        if !keep[i] {
            continue;
        }
        let a_set: std::collections::HashSet<usize> =
            regions[i].active_window_set.iter().copied().collect();
        for j in (i + 1)..regions.len() {
            if !keep[j] {
                continue;
            }

            // Count windows where B is active but A is not
            let independent_count = regions[j]
                .active_window_set
                .iter()
                .filter(|w| !a_set.contains(w))
                .count();

            // Require 20% of B's windows to be independent, at least 10
            let min_independent = (regions[j].active_window_set.len() / 5).max(10);

            if independent_count < min_independent {
                // B has insufficient independent activity — likely a sidelobe
                keep[j] = false;
            }
        }
    }

    let surviving: Vec<ActivityRegion> = regions
        .into_iter()
        .zip(keep.iter())
        .filter(|(_, &k)| k)
        .map(|(r, _)| r)
        .collect();

    // Step 6: Fine-tune frequencies to 1 Hz resolution
    let mut activities: Vec<ToneActivity> = Vec::new();
    for region in &surviving {
        // Collect samples from active windows for fine-tuning
        let start_sample = region.start_window * hop_samples;
        let end_sample =
            ((region.end_window + 1) * hop_samples + window_samples).min(samples.len());

        // Fine scan: 1 Hz steps around the coarse frequency
        let fine_low = (region.freq - step_hz).max(low_hz);
        let fine_high = (region.freq + step_hz).min(high_hz);
        let mut best_freq = region.freq;
        let mut best_energy = 0.0f32;

        // Use active windows only for fine-tuning
        let fine_window_size = (sample_rate as f32 * 0.05) as usize; // 50ms
        if fine_window_size > 0 {
            let mut f = fine_low;
            while f <= fine_high {
                let mut total_energy = 0.0f32;
                let mut window_count = 0;
                for &w in &region.active_window_set {
                    let ws = w * hop_samples;
                    if ws + fine_window_size <= samples.len() {
                        total_energy +=
                            goertzel_energy(&samples[ws..ws + fine_window_size], f, sample_rate);
                        window_count += 1;
                    }
                }
                if window_count > 0 && total_energy > best_energy {
                    best_energy = total_energy;
                    best_freq = f;
                }
                f += 1.0;
            }
        }

        activities.push(ToneActivity {
            freq: best_freq,
            start_sample,
            end_sample,
        });
    }

    // Sort by start_sample
    activities.sort_by_key(|a| a.start_sample);

    tracing::info!(
        activities = activities.len(),
        frequencies = ?activities.iter().map(|a| format!("{:.0}Hz@{:.1}-{:.1}s",
            a.freq,
            a.start_sample as f64 / sample_rate as f64,
            a.end_sample as f64 / sample_rate as f64,
        )).collect::<Vec<_>>(),
        "Tone activity scan complete"
    );

    activities
}

/// Refine tone activity frequencies to ~1 Hz resolution using longer Goertzel windows.
///
/// Takes coarse activities from `scan_tone_activity()` (which uses 100ms windows at
/// 10 Hz step) and re-scans each with 1 Hz steps in a ±15 Hz window using 200ms
/// Goertzel windows. This enables distinguishing operators only 22-24 Hz apart
/// (e.g., 527 Hz vs 549 Hz) that would otherwise merge in coarse scanning.
pub fn refine_tone_frequencies(
    samples: &[f32],
    sample_rate: u32,
    activities: Vec<ToneActivity>,
) -> Vec<ToneActivity> {
    if activities.is_empty() {
        return activities;
    }

    let fine_window_size = (sample_rate as usize * 200) / 1000; // 200ms windows
    if fine_window_size == 0 || samples.len() < fine_window_size {
        return activities;
    }

    let mut refined = Vec::with_capacity(activities.len());

    for activity in activities {
        let scan_low = (activity.freq - 15.0).max(400.0);
        let scan_high = (activity.freq + 15.0).min(900.0);

        // Use only the active time region for fine-tuning
        let region_start = activity.start_sample;
        let region_end = activity.end_sample.min(samples.len());
        let region = &samples[region_start..region_end];

        if region.len() < fine_window_size {
            refined.push(activity);
            continue;
        }

        // Select best windows for fine-tuning. For weak operators, most
        // windows in the activity region are noise — only a few contain
        // actual CW signal. Rank windows by energy at the coarse frequency
        // and use only the top 50% (at least 3), so fine-tuning is driven
        // by actual signal windows rather than noise.
        let all_windows = region.len() / fine_window_size;
        if all_windows == 0 {
            refined.push(activity);
            continue;
        }

        // Score each window by energy at the coarse frequency
        let mut window_scores: Vec<(usize, f32)> = (0..all_windows)
            .map(|w| {
                let start = w * fine_window_size;
                let e = goertzel_energy(
                    &region[start..start + fine_window_size],
                    activity.freq,
                    sample_rate,
                );
                (w, e)
            })
            .collect();
        window_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // Take top 50% of windows (at least 3, at most 50)
        let num_windows = (all_windows / 2).max(3).min(50).min(all_windows);
        let best_windows: Vec<usize> = window_scores[..num_windows]
            .iter()
            .map(|&(w, _)| w)
            .collect();

        let mut best_freq = activity.freq;
        let mut best_energy = 0.0f32;

        let mut f = scan_low;
        while f <= scan_high {
            let mut total_energy = 0.0f32;
            for &w in &best_windows {
                let start = w * fine_window_size;
                let window = &region[start..start + fine_window_size];
                total_energy += goertzel_energy(window, f, sample_rate);
            }
            if total_energy > best_energy {
                best_energy = total_energy;
                best_freq = f;
            }
            f += 1.0;
        }

        tracing::debug!(
            coarse_hz = format!("{:.0}", activity.freq),
            refined_hz = format!("{:.0}", best_freq),
            "Refined tone frequency"
        );

        refined.push(ToneActivity {
            freq: best_freq,
            start_sample: activity.start_sample,
            end_sample: activity.end_sample,
        });
    }

    refined
}

/// Merge keying events to consolidate fragments caused by noise dips within
/// CW elements. Any Off-On pair where the Off gap is shorter than
/// `max_gap_samples` is removed, effectively joining the two On regions.
///
/// Also removes On-Off pairs where the On duration is shorter than
/// `min_on_samples` (noise spikes that survived thresholding).
///
/// Call this on the output of `ToneDetector::process()` + `finalize()`
/// before feeding events to the morse decoder.
pub fn merge_keying_events(
    events: &[KeyingEvent],
    max_gap_samples: usize,
    min_on_samples: usize,
) -> Vec<KeyingEvent> {
    if events.is_empty() {
        return Vec::new();
    }

    // Step 1: Merge short off-gaps.
    // Walk the event stream and remove Off-On pairs where the gap is short.
    let mut merged: Vec<KeyingEvent> = Vec::with_capacity(events.len());

    let mut i = 0;
    while i < events.len() {
        // Look for Off followed by On with a short gap
        if i + 1 < events.len()
            && events[i].kind == KeyingEventKind::Off
            && events[i + 1].kind == KeyingEventKind::On
        {
            let gap = events[i + 1]
                .sample_offset
                .saturating_sub(events[i].sample_offset);
            if gap < max_gap_samples {
                // Skip both the Off and the On — they merge the surrounding On regions
                i += 2;
                continue;
            }
        }
        merged.push(events[i]);
        i += 1;
    }

    // Step 2: Remove short on-events (noise spikes).
    let mut filtered: Vec<KeyingEvent> = Vec::with_capacity(merged.len());
    let mut j = 0;
    while j < merged.len() {
        if j + 1 < merged.len()
            && merged[j].kind == KeyingEventKind::On
            && merged[j + 1].kind == KeyingEventKind::Off
        {
            let dur = merged[j + 1]
                .sample_offset
                .saturating_sub(merged[j].sample_offset);
            if dur < min_on_samples {
                // Skip both On and Off — too short to be a real element
                j += 2;
                continue;
            }
        }
        filtered.push(merged[j]);
        j += 1;
    }

    filtered
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Generate a sine wave at the given frequency for the given duration.
    fn sine_wave(freq: f32, sample_rate: u32, duration_secs: f32, amplitude: f32) -> Vec<f32> {
        let num_samples = (sample_rate as f32 * duration_secs) as usize;
        (0..num_samples)
            .map(|i| {
                let t = i as f32 / sample_rate as f32;
                (2.0 * std::f32::consts::PI * freq * t).sin() * amplitude
            })
            .collect()
    }

    /// Generate silence for the given duration.
    fn silence(sample_rate: u32, duration_secs: f32) -> Vec<f32> {
        vec![0.0; (sample_rate as f32 * duration_secs) as usize]
    }

    /// Generate broadband noise with energy spread across 400-900 Hz.
    /// Uses a sum of many sine waves at random-ish phases to simulate
    /// noise that has spectral content but no tonal peaks.
    fn broadband_noise(sample_rate: u32, duration_secs: f32, amplitude: f32) -> Vec<f32> {
        let num_samples = (sample_rate as f32 * duration_secs) as usize;
        let mut samples = vec![0.0f32; num_samples];
        // Sum many closely-spaced sine waves across 400-900 Hz
        // with varied phases so no single frequency dominates
        let mut freq = 400.0f32;
        while freq <= 900.0 {
            let phase = freq * 1.618; // golden ratio phase scramble
            for (i, s) in samples.iter_mut().enumerate() {
                let t = i as f32 / sample_rate as f32;
                *s += (2.0 * std::f32::consts::PI * freq * t + phase).sin();
            }
            freq += 5.0; // 5 Hz steps = 100 tones
        }
        // Normalize to target amplitude
        let peak = samples.iter().fold(0.0f32, |a, &b| a.max(b.abs()));
        if peak > 0.0 {
            let scale = amplitude / peak;
            for s in &mut samples {
                *s *= scale;
            }
        }
        samples
    }

    #[test]
    fn detects_tone_onset_and_offset() {
        let sr = 12_000;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        // 600ms silence (calibration + some quiet)
        let mut audio = silence(sr, 0.6);
        // 200ms tone
        audio.extend(sine_wave(650.0, sr, 0.2, 0.5));
        // 200ms silence
        audio.extend(silence(sr, 0.2));

        let events = detector.process(&audio);
        let final_event = detector.finalize();

        let mut all_events: Vec<KeyingEvent> = events;
        if let Some(e) = final_event {
            all_events.push(e);
        }

        // Should have at least one On and one Off
        let on_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();
        let off_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::Off)
            .count();

        assert!(
            on_count >= 1,
            "expected at least 1 On event, got {on_count}"
        );
        assert!(
            off_count >= 1,
            "expected at least 1 Off event, got {off_count}"
        );

        // On should come before Off
        let first_on = all_events
            .iter()
            .find(|e| e.kind == KeyingEventKind::On)
            .unwrap();
        let first_off = all_events
            .iter()
            .find(|e| e.kind == KeyingEventKind::Off)
            .unwrap();
        assert!(first_on.sample_offset < first_off.sample_offset);
    }

    #[test]
    fn no_events_during_silence() {
        let sr = 12_000;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        let audio = silence(sr, 2.0);
        let events = detector.process(&audio);
        let final_event = detector.finalize();

        assert!(events.is_empty(), "no events expected for pure silence");
        assert!(final_event.is_none());
    }

    #[test]
    fn multiple_tones_produce_multiple_events() {
        let sr = 12_000;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        // Calibration silence
        let mut audio = silence(sr, 0.6);
        // Three tone bursts separated by silence
        for _ in 0..3 {
            audio.extend(sine_wave(650.0, sr, 0.1, 0.5));
            audio.extend(silence(sr, 0.2));
        }
        // Trailing silence
        audio.extend(silence(sr, 0.3));

        let events = detector.process(&audio);
        let final_event = detector.finalize();

        let mut all_events: Vec<KeyingEvent> = events;
        if let Some(e) = final_event {
            all_events.push(e);
        }

        let on_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();
        let off_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::Off)
            .count();

        assert!(
            on_count >= 3,
            "expected at least 3 On events, got {on_count}"
        );
        assert!(
            off_count >= 3,
            "expected at least 3 Off events, got {off_count}"
        );
    }

    #[test]
    fn finalize_emits_off_when_tone_active() {
        let sr = 12_000;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        // Calibration silence then tone that doesn't end
        let mut audio = silence(sr, 0.6);
        audio.extend(sine_wave(650.0, sr, 0.5, 0.5));

        let _events = detector.process(&audio);
        let final_event = detector.finalize();

        assert!(final_event.is_some(), "finalize should emit Off event");
        assert_eq!(final_event.unwrap().kind, KeyingEventKind::Off);
    }

    #[test]
    fn detect_peak_frequency_finds_tone() {
        let sr = 12_000;
        // Generate 2s of audio with a tone at 720 Hz (not 650!)
        let mut audio = silence(sr, 0.5);
        audio.extend(sine_wave(720.0, sr, 1.5, 0.5));

        let detected = detect_peak_frequency(&audio, sr, 400.0, 900.0, 10.0);
        assert!(
            (detected - 720.0).abs() < 5.0,
            "expected ~720 Hz, got {detected} Hz"
        );
    }

    #[test]
    fn detect_peak_frequency_finds_low_tone() {
        let sr = 12_000;
        let mut audio = silence(sr, 0.3);
        audio.extend(sine_wave(480.0, sr, 1.5, 0.5));

        let detected = detect_peak_frequency(&audio, sr, 400.0, 900.0, 10.0);
        assert!(
            (detected - 480.0).abs() < 5.0,
            "expected ~480 Hz, got {detected} Hz"
        );
    }

    #[test]
    fn merge_consolidates_short_gaps() {
        // On(0) Off(100) On(120) Off(500) — gap of 20 should be merged
        let events = vec![
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: 0,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 100,
            },
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: 120,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 500,
            },
        ];
        let merged = merge_keying_events(&events, 50, 10); // max_gap=50, min_on=10
                                                           // Should merge into On(0) Off(500)
        assert_eq!(
            merged.len(),
            2,
            "expected 2 events after merge, got {}",
            merged.len()
        );
        assert_eq!(merged[0].kind, KeyingEventKind::On);
        assert_eq!(merged[0].sample_offset, 0);
        assert_eq!(merged[1].kind, KeyingEventKind::Off);
        assert_eq!(merged[1].sample_offset, 500);
    }

    #[test]
    fn merge_preserves_real_gaps() {
        // On(0) Off(100) On(300) Off(500) — gap of 200 should be preserved
        let events = vec![
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: 0,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 100,
            },
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: 300,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 500,
            },
        ];
        let merged = merge_keying_events(&events, 50, 10);
        assert_eq!(
            merged.len(),
            4,
            "expected 4 events preserved, got {}",
            merged.len()
        );
    }

    #[test]
    fn merge_removes_short_on_events() {
        // On(0) Off(5) On(100) Off(500) — first On is only 5 samples, should be removed
        let events = vec![
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: 0,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 5,
            },
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: 100,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 500,
            },
        ];
        let merged = merge_keying_events(&events, 50, 10); // min_on=10
        assert_eq!(
            merged.len(),
            2,
            "expected 2 events after filtering, got {}",
            merged.len()
        );
        assert_eq!(merged[0].kind, KeyingEventKind::On);
        assert_eq!(merged[0].sample_offset, 100);
    }

    #[test]
    fn goertzel_energy_peaks_at_target_frequency() {
        let sr = 12_000;
        let detector = ToneDetector::new(650.0, sr, 10);
        let window_size = (sr * 10 / 1000) as usize; // 120 samples

        // Energy at target frequency
        let target_signal: Vec<f32> = (0..window_size)
            .map(|i| {
                let t = i as f32 / sr as f32;
                (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5
            })
            .collect();

        // Energy at a different frequency
        let other_signal: Vec<f32> = (0..window_size)
            .map(|i| {
                let t = i as f32 / sr as f32;
                (2.0 * std::f32::consts::PI * 1500.0 * t).sin() * 0.5
            })
            .collect();

        let target_energy = detector.goertzel_energy(&target_signal);
        let other_energy = detector.goertzel_energy(&other_signal);

        assert!(
            target_energy > other_energy * 5.0,
            "target energy ({target_energy}) should be much larger than off-frequency ({other_energy})"
        );
    }

    #[test]
    fn spectral_gate_rejects_broadband_noise() {
        let sr = 12_000;

        // Generate broadband noise burst (white-ish noise via many frequencies)
        let noise: Vec<f32> = (0..12000)
            .map(|i| {
                let t = i as f32 / sr as f32;
                // Sum of many frequencies to simulate broadband noise
                (0..20)
                    .map(|k| {
                        let f = 300.0 + k as f32 * 50.0; // 300 to 1250 Hz
                        (2.0 * std::f32::consts::PI * f * t + k as f32 * 1.7).sin() * 0.1
                    })
                    .sum::<f32>()
            })
            .collect();

        // Calibrate with silence so thresholds are low
        let mut detector = ToneDetector::new(650.0, sr, 10);
        let cal_audio = silence(sr, 0.6);
        detector.calibrate_from_audio(&cal_audio);

        // Process the broadband noise
        let events = detector.process(&noise);
        let final_event = detector.finalize();

        let mut all_events: Vec<KeyingEvent> = events;
        if let Some(e) = final_event {
            all_events.push(e);
        }

        // Spectral gate should reject most/all of the broadband noise
        let on_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();
        assert!(
            on_count <= 2,
            "broadband noise should produce few or no On events with gating, got {on_count}"
        );
    }

    #[test]
    fn spectral_gate_passes_narrowband_tone() {
        let sr = 12_000;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        // Calibration silence + narrowband tone
        let mut audio = silence(sr, 0.6);
        audio.extend(sine_wave(650.0, sr, 0.5, 0.5));
        audio.extend(silence(sr, 0.3));

        let events = detector.process(&audio);
        let final_event = detector.finalize();

        let mut all_events: Vec<KeyingEvent> = events;
        if let Some(e) = final_event {
            all_events.push(e);
        }

        let on_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();
        assert!(
            on_count >= 1,
            "narrowband tone should pass spectral gate, got {on_count} On events"
        );
    }

    #[test]
    fn detect_peak_frequencies_single_tone() {
        let sr = 12_000;
        let mut audio = silence(sr, 0.3);
        audio.extend(sine_wave(650.0, sr, 2.0, 0.5));

        let freqs = detect_peak_frequencies(&audio, sr, 400.0, 900.0, 10.0, 120.0, 4);
        assert_eq!(freqs.len(), 1, "expected 1 tone, got {}", freqs.len());
        assert!(
            (freqs[0] - 650.0).abs() < 15.0,
            "expected ~650 Hz, got {:.0} Hz",
            freqs[0]
        );
    }

    #[test]
    fn detect_peak_frequencies_two_tones() {
        let sr = 12_000;
        let duration = 2.0;
        let num_samples = (sr as f32 * duration) as usize;

        // Two tones at 550 Hz and 750 Hz, both strong
        let audio: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone1 = (2.0 * std::f32::consts::PI * 550.0 * t).sin() * 0.4;
                let tone2 = (2.0 * std::f32::consts::PI * 750.0 * t).sin() * 0.4;
                tone1 + tone2
            })
            .collect();

        let freqs = detect_peak_frequencies(&audio, sr, 400.0, 900.0, 10.0, 120.0, 4);
        assert!(
            freqs.len() >= 2,
            "expected at least 2 tones, got {}: {:?}",
            freqs.len(),
            freqs
        );
        // First tone near 550 Hz
        assert!(
            (freqs[0] - 550.0).abs() < 20.0,
            "expected ~550 Hz, got {:.0} Hz",
            freqs[0]
        );
        // Second tone near 750 Hz
        assert!(
            (freqs[1] - 750.0).abs() < 20.0,
            "expected ~750 Hz, got {:.0} Hz",
            freqs[1]
        );
    }

    #[test]
    fn detect_peak_frequencies_weak_tone_filtered() {
        let sr = 12_000;
        let duration = 2.0;
        let num_samples = (sr as f32 * duration) as usize;

        // Strong tone at 600 Hz, weak tone at 750 Hz (10× lower amplitude)
        let audio: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let strong = (2.0 * std::f32::consts::PI * 600.0 * t).sin() * 0.5;
                let weak = (2.0 * std::f32::consts::PI * 750.0 * t).sin() * 0.05;
                strong + weak
            })
            .collect();

        let freqs = detect_peak_frequencies(&audio, sr, 400.0, 900.0, 10.0, 120.0, 4);
        // The weak tone should be filtered by the 1.5× median threshold
        assert_eq!(
            freqs.len(),
            1,
            "expected 1 tone (weak filtered), got {}: {:?}",
            freqs.len(),
            freqs
        );
        assert!(
            (freqs[0] - 600.0).abs() < 15.0,
            "expected ~600 Hz, got {:.0} Hz",
            freqs[0]
        );
    }

    // --- Adaptive noise floor tests ---

    #[test]
    fn adaptive_tracks_rising_noise() {
        let sr = 12_000;
        let window_ms = 10;
        let tone_freq = 650.0;

        // Build audio: 1s low noise, then 1s high noise (2× amplitude),
        // with periodic tone bursts throughout.
        let mut audio = Vec::new();
        let low_noise_amp = 0.001;
        let high_noise_amp = 0.005;
        let tone_amp = 0.5;

        for i in 0..(sr * 2) {
            let t = i as f32 / sr as f32;
            let time_s = i as f32 / sr as f32;
            let noise_amp = if time_s < 1.0 {
                low_noise_amp
            } else {
                high_noise_amp
            };
            // Tone bursts: 100ms on every 300ms
            let in_burst = (i % (sr as usize / 3)) < (sr as usize / 10);
            let tone = if in_burst {
                (2.0 * std::f32::consts::PI * tone_freq * t).sin() * tone_amp
            } else {
                0.0
            };
            // Background noise (deterministic pseudo-noise)
            let noise = ((i as f32 * 0.73).sin() + (i as f32 * 2.31).sin()) * noise_amp;
            audio.push(tone + noise);
        }

        let mut detector = ToneDetector::new(tone_freq, sr as u32, window_ms);
        detector.calibrate_from_audio(&audio);
        detector.enable_adaptive();

        let events = detector.process(&audio);
        let final_event = detector.finalize();
        let mut all_events: Vec<KeyingEvent> = events;
        if let Some(e) = final_event {
            all_events.push(e);
        }

        // Should detect tone bursts in both halves (adaptive threshold follows noise)
        let on_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();
        assert!(
            on_count >= 4,
            "should detect tone bursts across rising noise, got {on_count} On events"
        );
    }

    #[test]
    fn adaptive_tracks_falling_noise() {
        let sr = 12_000;
        let window_ms = 10;
        let tone_freq = 650.0;

        // Build audio: 1s high noise with strong tones, then 2s low noise with
        // moderate tones. The key test: the moderate tones would be below the
        // Otsu threshold calibrated on the full (noisy) recording, but the
        // adaptive floor should track the falling noise and lower the threshold.
        let mut audio = Vec::new();

        for i in 0..(sr * 3) {
            let t = i as f32 / sr as f32;
            let time_s = i as f32 / sr as f32;
            let noise_amp = if time_s < 1.0 { 0.01 } else { 0.001 };
            let tone_amp = if time_s < 1.0 { 0.5 } else { 0.2 };
            let in_burst = (i % (sr as usize / 3)) < (sr as usize / 10);
            let tone = if in_burst {
                (2.0 * std::f32::consts::PI * tone_freq * t).sin() * tone_amp
            } else {
                0.0
            };
            let noise = ((i as f32 * 0.73).sin() + (i as f32 * 2.31).sin()) * noise_amp;
            audio.push(tone + noise);
        }

        let mut detector = ToneDetector::new(tone_freq, sr as u32, window_ms);
        detector.calibrate_from_audio(&audio);
        detector.enable_adaptive();

        let events = detector.process(&audio);
        let final_event = detector.finalize();
        let mut all_events: Vec<KeyingEvent> = events;
        if let Some(e) = final_event {
            all_events.push(e);
        }

        // Should detect tone bursts in both halves
        let on_count = all_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();
        assert!(
            on_count >= 5,
            "should detect tone bursts across falling noise, got {on_count} On events"
        );
    }

    #[test]
    fn adaptive_gate_during_signal() {
        // Verify noise_floor doesn't change during ON periods
        let sr = 12_000u32;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        // Calibrate with silence
        let cal = silence(sr, 0.6);
        detector.calibrate_from_audio(&cal);
        detector.enable_adaptive();

        let floor_before = detector.noise_floor;

        // Process a long tone burst (500ms)
        let tone = sine_wave(650.0, sr, 0.5, 0.5);
        let _events = detector.process(&tone);

        // Noise floor should be unchanged (gated during ON)
        let floor_after = detector.noise_floor;
        assert!(
            (floor_before - floor_after).abs() < floor_before * 0.1,
            "noise floor should not change during signal: before={floor_before:.6}, after={floor_after:.6}"
        );
    }

    #[test]
    fn adaptive_fast_recovery() {
        // After a 1s tone, noise floor should converge quickly via fast alpha
        let sr = 12_000u32;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        // Calibrate with low noise
        let cal_noise: Vec<f32> = (0..sr as usize)
            .map(|i| (i as f32 * 0.73).sin() * 0.001)
            .collect();
        detector.calibrate_from_audio(&cal_noise);
        detector.enable_adaptive();

        let floor_initial = detector.noise_floor;

        // 1s tone (> extended_on_threshold of 500ms)
        let tone = sine_wave(650.0, sr, 1.0, 0.5);
        let _events1 = detector.process(&tone);

        // 300ms of higher noise (new noise floor)
        let high_noise: Vec<f32> = (0..(sr as usize * 3 / 10))
            .map(|i| (i as f32 * 0.73).sin() * 0.01)
            .collect();
        let _events2 = detector.process(&high_noise);

        // Fast recovery should have kicked in — noise floor should have moved
        // toward the new noise level
        let floor_after = detector.noise_floor;
        assert!(
            floor_after > floor_initial * 1.5,
            "noise floor should track higher noise via fast recovery: initial={floor_initial:.6}, after={floor_after:.6}"
        );
    }

    #[test]
    fn adaptive_disabled_by_default() {
        // Without enable_adaptive(), behavior should be identical to original
        let sr = 12_000u32;

        let mut audio = silence(sr, 0.6);
        audio.extend(sine_wave(650.0, sr, 0.2, 0.5));
        audio.extend(silence(sr, 0.2));

        // Non-adaptive detector
        let mut det1 = ToneDetector::new(650.0, sr, 10);
        det1.calibrate_from_audio(&audio);
        let events1 = det1.process(&audio);
        let final1 = det1.finalize();

        // Adaptive detector (but NOT enabled)
        let mut det2 = ToneDetector::new(650.0, sr, 10);
        det2.calibrate_from_audio(&audio);
        // Note: NOT calling det2.enable_adaptive()
        let events2 = det2.process(&audio);
        let final2 = det2.finalize();

        // Thresholds should be identical
        assert_eq!(det1.on_threshold, det2.on_threshold);
        assert_eq!(det1.off_threshold, det2.off_threshold);

        // Event counts should match
        let on1 = events1
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count()
            + final1.map_or(0, |_| 0);
        let on2 = events2
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count()
            + final2.map_or(0, |_| 0);
        assert_eq!(
            on1, on2,
            "non-adaptive and disabled-adaptive should produce same events"
        );
    }

    #[test]
    fn adaptive_noise_floor_clamped() {
        // Verify noise floor never drops below 1e-10
        let sr = 12_000u32;
        let mut detector = ToneDetector::new(650.0, sr, 10);

        // Calibrate with near-silence
        let cal = vec![0.0f32; sr as usize];
        detector.calibrate_from_audio(&cal);
        detector.enable_adaptive();

        // Process pure silence for 1s
        let silence_buf = vec![0.0f32; sr as usize];
        let _events = detector.process(&silence_buf);

        assert!(
            detector.noise_floor >= 1e-10,
            "noise floor should be clamped to 1e-10, got {}",
            detector.noise_floor
        );
    }

    #[test]
    fn detect_peak_frequencies_respects_min_separation() {
        let sr = 12_000;
        let duration = 2.0;
        let num_samples = (sr as f32 * duration) as usize;

        // Two tones only 60 Hz apart (below 100 Hz min separation)
        let audio: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone1 = (2.0 * std::f32::consts::PI * 650.0 * t).sin() * 0.5;
                let tone2 = (2.0 * std::f32::consts::PI * 710.0 * t).sin() * 0.4;
                tone1 + tone2
            })
            .collect();

        let freqs = detect_peak_frequencies(&audio, sr, 400.0, 900.0, 10.0, 120.0, 4);
        // Should keep only the stronger peak
        assert_eq!(
            freqs.len(),
            1,
            "expected 1 tone (too close), got {}: {:?}",
            freqs.len(),
            freqs
        );
    }

    #[test]
    fn detect_peak_frequencies_time_separated_tones() {
        // Simulate two operators transmitting at different times (like a POTA exchange).
        // Tone A (550 Hz) in first half, silence gap, tone B (750 Hz) in second half.
        // The old algorithm (averaging first 40 windows) would only see tone A.
        // Chunked detection should find both.
        let sr = 12_000;
        let mut audio = Vec::new();

        // Operator A: 5 seconds of 550 Hz tone
        audio.extend(sine_wave(550.0, sr, 5.0, 0.4));
        // 2 second pause between operators
        audio.extend(silence(sr, 2.0));
        // Operator B: 5 seconds of 750 Hz tone
        audio.extend(sine_wave(750.0, sr, 5.0, 0.4));
        // Trailing silence
        audio.extend(silence(sr, 1.0));

        let freqs = detect_peak_frequencies(&audio, sr, 400.0, 900.0, 10.0, 120.0, 4);
        assert!(
            freqs.len() >= 2,
            "expected at least 2 tones from time-separated operators, got {}: {:?}",
            freqs.len(),
            freqs
        );
        // First tone near 550 Hz
        assert!(
            (freqs[0] - 550.0).abs() < 15.0,
            "expected ~550 Hz, got {:.0} Hz",
            freqs[0]
        );
        // Second tone near 750 Hz
        assert!(
            (freqs[1] - 750.0).abs() < 15.0,
            "expected ~750 Hz, got {:.0} Hz",
            freqs[1]
        );
    }

    // --- scan_tone_activity tests ---

    #[test]
    fn scan_tone_activity_single_tone() {
        let sr = 12_000;
        // 3s of continuous tone at 650 Hz
        let audio = sine_wave(650.0, sr, 3.0, 0.5);

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        assert_eq!(
            activities.len(),
            1,
            "expected 1 activity region, got {}",
            activities.len()
        );
        assert!(
            (activities[0].freq - 650.0).abs() < 15.0,
            "expected ~650 Hz, got {:.0} Hz",
            activities[0].freq
        );
        // Should span most of the recording
        assert!(activities[0].start_sample < sr as usize / 2); // starts near beginning
        assert!(activities[0].end_sample > sr as usize * 2); // extends past 2s
    }

    #[test]
    fn scan_tone_activity_time_separated() {
        let sr = 12_000;
        let mut audio = Vec::new();

        // Operator A: 3s of 550 Hz tone
        audio.extend(sine_wave(550.0, sr, 3.0, 0.4));
        // 2s silence
        audio.extend(silence(sr, 2.0));
        // Operator B: 3s of 750 Hz tone
        audio.extend(sine_wave(750.0, sr, 3.0, 0.4));
        // Trailing silence
        audio.extend(silence(sr, 1.0));

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        assert!(
            activities.len() >= 2,
            "expected at least 2 activity regions, got {}: {:?}",
            activities.len(),
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );

        // Check frequencies (sorted by start_sample)
        let freq_a = activities[0].freq;
        let freq_b = activities[1].freq;
        assert!(
            (freq_a - 550.0).abs() < 15.0,
            "expected first activity ~550 Hz, got {:.0} Hz",
            freq_a
        );
        assert!(
            (freq_b - 750.0).abs() < 15.0,
            "expected second activity ~750 Hz, got {:.0} Hz",
            freq_b
        );

        // Time ranges should not significantly overlap
        assert!(
            activities[0].end_sample < activities[1].start_sample + sr as usize,
            "activity regions should not significantly overlap in time"
        );
    }

    #[test]
    fn scan_tone_activity_sidelobe_rejected() {
        let sr = 12_000;
        // 3s of strong tone at 650 Hz. The Goertzel sidelobe will appear
        // at nearby frequencies but only during the same time windows.
        let audio = sine_wave(650.0, sr, 3.0, 0.8);

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        // Should have exactly 1 activity region — sidelobes filtered
        assert_eq!(
            activities.len(),
            1,
            "expected 1 activity (sidelobes rejected), got {}: {:?}",
            activities.len(),
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
        assert!(
            (activities[0].freq - 650.0).abs() < 15.0,
            "expected ~650 Hz, got {:.0} Hz",
            activities[0].freq
        );
    }

    #[test]
    fn scan_tone_activity_real_operator_kept() {
        let sr = 12_000;
        let mut audio = Vec::new();

        // Operator A: 3s of 600 Hz (close to B, only 80 Hz apart)
        audio.extend(sine_wave(600.0, sr, 3.0, 0.5));
        // 1.5s silence
        audio.extend(silence(sr, 1.5));
        // Operator B: 3s of 680 Hz (within 120 Hz of A, but different times)
        audio.extend(sine_wave(680.0, sr, 3.0, 0.5));
        // Trailing silence
        audio.extend(silence(sr, 1.0));

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        // Both should be kept because they have independent activity
        assert!(
            activities.len() >= 2,
            "expected at least 2 activities (close freqs but independent times), got {}: {:?}",
            activities.len(),
            activities
                .iter()
                .map(|a| format!(
                    "{:.0}Hz@{:.1}-{:.1}s",
                    a.freq,
                    a.start_sample as f64 / sr as f64,
                    a.end_sample as f64 / sr as f64,
                ))
                .collect::<Vec<_>>()
        );

        // Verify both frequencies are present
        let has_low = activities.iter().any(|a| (a.freq - 600.0).abs() < 20.0);
        let has_high = activities.iter().any(|a| (a.freq - 680.0).abs() < 20.0);
        assert!(has_low, "expected activity near 600 Hz");
        assert!(has_high, "expected activity near 680 Hz");
    }

    #[test]
    fn scan_tone_activity_rejects_broadband_noise() {
        let sr = 12_000;
        // 10s of broadband noise with no tonal content
        let audio = broadband_noise(sr, 10.0, 0.5);

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        // Should detect very few or no activities — noise has no spectral peaks
        assert!(
            activities.len() <= 2,
            "expected <=2 activities from broadband noise, got {}: {:?}",
            activities.len(),
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn scan_tone_activity_weak_tone_survives() {
        let sr = 12_000;
        let mut audio = Vec::new();

        // Strong operator A: 3s of 650 Hz at amplitude 0.5
        audio.extend(sine_wave(650.0, sr, 3.0, 0.5));
        // 2s silence
        audio.extend(silence(sr, 2.0));
        // Weak operator B: 3s of 500 Hz at amplitude 0.05 (20 dB quieter, ~0.25% energy)
        audio.extend(sine_wave(500.0, sr, 3.0, 0.05));
        // Trailing silence
        audio.extend(silence(sr, 1.0));

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        // Both should be detected — the 1% energy floor should pass a 0.25% energy tone
        // since Goertzel energy scales with amplitude^2 and 0.05^2/0.5^2 = 1%
        let has_strong = activities.iter().any(|a| (a.freq - 650.0).abs() < 15.0);
        let has_weak = activities.iter().any(|a| (a.freq - 500.0).abs() < 15.0);
        assert!(
            has_strong,
            "expected activity near 650 Hz (strong): {:?}",
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
        assert!(
            has_weak,
            "expected activity near 500 Hz (weak, -20dB): {:?}",
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn scan_tone_activity_very_weak_tone_survives() {
        let sr = 12_000;
        let mut audio = Vec::new();

        // Strong operator: 3s of 650 Hz at amplitude 0.5
        audio.extend(sine_wave(650.0, sr, 3.0, 0.5));
        // 2s silence
        audio.extend(silence(sr, 2.0));
        // Very weak operator: 3s of 450 Hz at amplitude 0.02 (28 dB quieter)
        // Energy ratio: 0.02^2 / 0.5^2 = 0.0016 = 0.16% of strong
        audio.extend(sine_wave(450.0, sr, 3.0, 0.02));
        // Trailing silence
        audio.extend(silence(sr, 1.0));

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        let has_strong = activities.iter().any(|a| (a.freq - 650.0).abs() < 15.0);
        let has_weak = activities.iter().any(|a| (a.freq - 450.0).abs() < 15.0);
        assert!(
            has_strong,
            "expected activity near 650 Hz (strong): {:?}",
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
        // Even at 0.16% of global max energy, a clean tone with high peakiness
        // should survive the 1% floor because Goertzel concentrates all energy
        // at the exact frequency while the per-window peak detection threshold
        // is relative to window_max (which is this tone's own energy when it's
        // the only thing active in its time window).
        assert!(
            has_weak,
            "expected activity near 450 Hz (very weak, -28dB): {:?}",
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn windowed_calibration_handles_noise_change() {
        // Simulate band conditions changing: CW tone at constant amplitude,
        // but noise floor jumps 10× at the midpoint (interference appears).
        // Global Otsu averages across both halves, producing a threshold that's
        // wrong for both: too high for the clean half, possibly too low for
        // the noisy half. Windowed Otsu adapts per-segment.
        let sr = 12_000u32;
        let freq = 650.0f64;
        let window_ms = 10u32;
        let duration_s = 10.0;
        let total_samples = (sr as f64 * duration_s) as usize;
        let midpoint = total_samples / 2;

        let dit_samples = (sr as f64 * 0.060) as usize; // 60ms, ~20 WPM
        let tone_amp = 0.3f64;
        let noise_low = 0.01f64; // First half: low noise
        let noise_high = 0.15f64; // Second half: high noise (close to tone)

        let noise_at = |i: usize, amp: f64| -> f32 {
            let phi = 1.618033988749895f64;
            ((i as f64 * phi * 7.3).sin() * amp) as f32
        };

        let mut audio = Vec::with_capacity(total_samples);
        let mut sample_idx = 0usize;
        while sample_idx < total_samples {
            let noise_amp = if sample_idx < midpoint {
                noise_low
            } else {
                noise_high
            };

            // ON period
            let base = audio.len();
            for i in 0..dit_samples {
                if base + i >= total_samples {
                    break;
                }
                let t = (base + i) as f64 / sr as f64;
                let tone = (2.0 * std::f64::consts::PI * freq * t).sin() as f32 * tone_amp as f32;
                audio.push(tone + noise_at(base + i, noise_amp));
            }
            sample_idx += dit_samples;

            // OFF period (noise only)
            let base = audio.len();
            for i in 0..dit_samples {
                if base + i >= total_samples {
                    break;
                }
                let noise_amp_here = if base + i < midpoint {
                    noise_low
                } else {
                    noise_high
                };
                audio.push(noise_at(base + i, noise_amp_here));
            }
            sample_idx += dit_samples;
        }
        audio.truncate(total_samples);

        // Run detector WITH windowed calibration
        let mut detector = ToneDetector::new(freq as f32, sr, window_ms);
        detector.calibrate_from_audio(&audio);
        detector.enable_adaptive();
        assert!(
            !detector.windowed_thresholds.is_empty(),
            "10s audio should produce windowed thresholds"
        );
        let events = detector.process(&audio);
        let windowed_on_count = events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();

        // Run detector WITHOUT windowed calibration
        let mut detector_global = ToneDetector::new(freq as f32, sr, window_ms);
        detector_global.calibrate_from_audio(&audio);
        detector_global.enable_adaptive();
        detector_global.windowed_thresholds.clear();
        let events_global = detector_global.process(&audio);
        let global_on_count = events_global
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count();

        // Both should detect events, but windowed should detect more.
        // ~83 dits total. The global Otsu threshold is a compromise between
        // the low-noise and high-noise halves — too high for the clean half,
        // causing missed detections. Windowed Otsu adapts per-segment.
        assert!(
            windowed_on_count >= 60,
            "windowed detector should find most ON events, got {}",
            windowed_on_count,
        );
        assert!(
            windowed_on_count > global_on_count,
            "windowed ({}) should detect more events than global ({}) with noise change",
            windowed_on_count,
            global_on_count,
        );
    }

    // --- spectral SNR pre-filter tests ---

    #[test]
    fn snr_prefilter_tone_in_high_noise_floor() {
        // Simulate a high constant noise floor with a CW tone peeking above it.
        // The noise floor is broadband (equal energy at all frequencies) and the
        // tone is only ~6 dB above the noise at its frequency. Without the SNR
        // pre-filter, per-window peak detection treats noise peaks as candidates.
        let sr = 12_000u32;
        let duration = 5.0;
        let num_samples = (sr as f32 * duration) as usize;
        let tone_freq = 650.0f32;
        let tone_amp = 0.15f32; // Tone amplitude
        let noise_amp = 0.10f32; // High noise amplitude (close to tone)

        // Keyed CW: tone on for 50% of the time (alternating 200ms on/off)
        let key_period_samples = (sr as f32 * 0.200) as usize;
        let audio: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr as f32;
                // Keyed tone: on during even periods, off during odd
                let in_key_on = (i / key_period_samples) % 2 == 0;
                let tone = if in_key_on {
                    (2.0 * std::f32::consts::PI * tone_freq * t).sin() * tone_amp
                } else {
                    0.0
                };
                // Deterministic broadband noise (constant level, varies across time)
                let phi = 1.618033988749895f32;
                let noise = ((i as f32 * phi * 7.3).sin()
                    + (i as f32 * phi * 3.1).sin()
                    + (i as f32 * phi * 11.7).sin())
                    / 3.0
                    * noise_amp;
                tone + noise
            })
            .collect();

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);

        // Should detect the tone near 650 Hz
        let has_tone = activities.iter().any(|a| (a.freq - tone_freq).abs() < 15.0);
        assert!(
            has_tone,
            "expected activity near {:.0} Hz in high noise, got: {:?}",
            tone_freq,
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
        // Should not have many false positives from noise
        assert!(
            activities.len() <= 3,
            "expected few activities (tone + maybe 1-2 noise), got {}: {:?}",
            activities.len(),
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn snr_prefilter_rejects_flat_noise() {
        // Pure broadband noise with no tonal content should produce no
        // SNR candidates (all bins have similar median and p90).
        let sr = 12_000u32;
        let duration = 5.0;
        let num_samples = (sr as f32 * duration) as usize;

        let audio: Vec<f32> = (0..num_samples)
            .map(|i| {
                let phi = 1.618033988749895f32;
                ((i as f32 * phi * 7.3).sin()
                    + (i as f32 * phi * 3.1).sin()
                    + (i as f32 * phi * 11.7).sin())
                    / 3.0
                    * 0.3 // high noise level
            })
            .collect();

        let activities = scan_tone_activity(&audio, sr, 400.0, 900.0, 10.0);
        assert!(
            activities.len() <= 2,
            "broadband noise should produce few/no activities, got {}: {:?}",
            activities.len(),
            activities
                .iter()
                .map(|a| format!("{:.0}Hz", a.freq))
                .collect::<Vec<_>>()
        );
    }
}
