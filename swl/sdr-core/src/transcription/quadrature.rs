//! Quadrature (NCO + moving-average LPF) envelope detector for CW tone detection.
//!
//! Provides improved SNR over Goertzel energy detection by:
//! 1. Shifting the tone to baseband via NCO (Numerically Controlled Oscillator)
//! 2. Applying a moving-average LPF matched to the desired bandwidth
//! 3. Computing envelope magnitude per analysis window
//!
//! The moving-average window length = sample_rate / bandwidth_hz, giving a
//! first-null bandwidth exactly at the specified frequency. A two-pass (cascaded)
//! moving average improves the stopband rejection to ~-25 dB.

/// Quadrature envelope detector for CW tone signals.
///
/// Mixes the input signal to baseband using an NCO at the target frequency,
/// applies a cascaded moving-average low-pass filter with configurable bandwidth,
/// and computes per-window envelope magnitudes.
pub struct QuadratureDetector {
    /// Target tone frequency (Hz).
    tone_freq: f32,
    /// Audio sample rate (Hz).
    sample_rate: u32,
    /// LPF bandwidth (Hz).
    bandwidth_hz: f32,
    /// Analysis window size in samples.
    window_samples: usize,
    /// Moving-average window length in samples (= sample_rate / bandwidth_hz).
    ma_len: usize,
}

impl QuadratureDetector {
    /// Create a new quadrature detector.
    ///
    /// - `tone_freq`: CW tone frequency to detect (Hz)
    /// - `sample_rate`: audio sample rate (Hz)
    /// - `bandwidth_hz`: LPF bandwidth (Hz); narrower = less noise but slower response
    /// - `window_ms`: analysis window duration (ms) for envelope output
    pub fn new(tone_freq: f32, sample_rate: u32, bandwidth_hz: f32, window_ms: u32) -> Self {
        let window_samples = (sample_rate as usize * window_ms as usize) / 1000;
        // MA window length determines the LPF bandwidth:
        // first null at sample_rate / ma_len Hz
        let ma_len = ((sample_rate as f32 / bandwidth_hz) as usize).max(1);

        Self {
            tone_freq,
            sample_rate,
            bandwidth_hz,
            window_samples,
            ma_len,
        }
    }

    /// Compute per-window envelope magnitudes from raw audio.
    ///
    /// Pipeline: NCO mix to baseband → cascaded MA LPF → magnitude → window RMS.
    /// Returns one energy value per `window_ms` window.
    pub fn compute_envelope(&self, samples: &[f32]) -> Vec<f32> {
        let n = samples.len();
        if n == 0 {
            return Vec::new();
        }

        // NCO: mix signal to baseband (complex multiplication by e^{-j 2π f t})
        let phase_inc =
            2.0 * std::f64::consts::PI * self.tone_freq as f64 / self.sample_rate as f64;
        let mut i_baseband = vec![0.0f32; n];
        let mut q_baseband = vec![0.0f32; n];

        for k in 0..n {
            let phase = phase_inc * k as f64;
            let cos_val = phase.cos() as f32;
            let sin_val = phase.sin() as f32;
            i_baseband[k] = samples[k] * cos_val;
            q_baseband[k] = samples[k] * (-sin_val);
        }

        // Cascaded moving-average LPF (two passes for better stopband)
        let i_filtered = moving_average(&moving_average(&i_baseband, self.ma_len), self.ma_len);
        let q_filtered = moving_average(&moving_average(&q_baseband, self.ma_len), self.ma_len);

        // Compute envelope (magnitude RMS) per analysis window
        let num_windows = n / self.window_samples;
        let mut envelope = Vec::with_capacity(num_windows);

        for w in 0..num_windows {
            let start = w * self.window_samples;
            let end = start + self.window_samples;
            let mut sum_sq = 0.0f64;
            for k in start..end {
                let mag_sq = i_filtered[k] as f64 * i_filtered[k] as f64
                    + q_filtered[k] as f64 * q_filtered[k] as f64;
                sum_sq += mag_sq;
            }
            let rms = (sum_sq / self.window_samples as f64).sqrt() as f32;
            envelope.push(rms);
        }

        envelope
    }

    /// Estimate SNR from envelope energies using Otsu split.
    ///
    /// Splits envelope values into ON and OFF clusters, returns the
    /// ratio in dB: `10 × log10(mean_ON / mean_OFF)`.
    pub fn estimate_snr(energies: &[f32]) -> f64 {
        if energies.len() < 4 {
            return 0.0;
        }

        let mut sorted = energies.to_vec();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let threshold = super::tone_detector::otsu_threshold_log(&sorted);

        let mut off_sum = 0.0f64;
        let mut off_count = 0usize;
        let mut on_sum = 0.0f64;
        let mut on_count = 0usize;

        for &e in energies {
            if e < threshold {
                off_sum += e as f64;
                off_count += 1;
            } else {
                on_sum += e as f64;
                on_count += 1;
            }
        }

        if off_count == 0 || on_count == 0 {
            return 0.0;
        }

        let mean_off = off_sum / off_count as f64;
        let mean_on = on_sum / on_count as f64;

        if mean_off < 1e-10 {
            return 30.0; // Cap at 30 dB
        }

        10.0 * (mean_on / mean_off).log10()
    }

    /// Get the configured bandwidth.
    pub fn bandwidth(&self) -> f32 {
        self.bandwidth_hz
    }
}

/// Compute a moving average of the input signal.
///
/// Output[i] = mean(signal[i-len+1 .. i]) using a running sum for O(n) cost.
fn moving_average(signal: &[f32], len: usize) -> Vec<f32> {
    let n = signal.len();
    if n == 0 || len == 0 {
        return signal.to_vec();
    }
    let len = len.min(n);
    let inv_len = 1.0 / len as f64;

    let mut output = vec![0.0f32; n];
    let mut sum = 0.0f64;

    // Build initial window
    for &s in signal.iter().take(len) {
        sum += s as f64;
    }
    output[len - 1] = (sum * inv_len) as f32;

    // Slide the window
    for i in len..n {
        sum += signal[i] as f64 - signal[i - len] as f64;
        output[i] = (sum * inv_len) as f32;
    }

    // Fill the leading samples with partial averages
    let mut partial_sum = 0.0f64;
    for i in 0..len.saturating_sub(1) {
        partial_sum += signal[i] as f64;
        output[i] = (partial_sum / (i + 1) as f64) as f32;
    }

    output
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify that quadrature detection produces a clean envelope on a keyed tone.
    #[test]
    fn quadrature_envelope_separates_on_off() {
        let sr = 12_000u32;
        let tone_freq = 650.0f32;
        let duration_secs = 2.0;
        let num_samples = (sr as f32 * duration_secs) as usize;

        // Generate keyed tone (100ms on, 100ms off) + mild noise
        let noise_amplitude = 0.05;
        let mut rng_state: u32 = 42;
        let samples: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * tone_freq * t).sin() * 0.5;
                let keyed = if (i / 1200) % 2 == 0 { tone } else { 0.0 };
                rng_state = rng_state.wrapping_mul(1103515245).wrapping_add(12345);
                let noise = ((rng_state >> 16) as f32 / 32768.0 - 1.0) * noise_amplitude;
                keyed + noise
            })
            .collect();

        let qd = QuadratureDetector::new(tone_freq, sr, 100.0, 10);
        let envelope = qd.compute_envelope(&samples);
        let snr = QuadratureDetector::estimate_snr(&envelope);

        // Should have good ON/OFF separation
        assert!(
            snr > 10.0,
            "SNR should be >10 dB for clean keyed tone, got {snr:.1} dB"
        );
    }

    /// Verify that narrower bandwidth reduces noise (lower CV on constant tone).
    #[test]
    fn narrower_bandwidth_reduces_noise() {
        let sr = 12_000u32;
        let tone_freq = 650.0f32;
        let duration_secs = 2.0; // Longer for better statistics
        let num_samples = (sr as f32 * duration_secs) as usize;

        // Constant tone + moderate noise
        let noise_amplitude = 0.3;
        let mut rng_state: u32 = 123;
        let samples: Vec<f32> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr as f32;
                let tone = (2.0 * std::f32::consts::PI * tone_freq * t).sin() * 0.5;
                rng_state = rng_state.wrapping_mul(1103515245).wrapping_add(12345);
                let noise = ((rng_state >> 16) as f32 / 32768.0 - 1.0) * noise_amplitude;
                tone + noise
            })
            .collect();

        // Wide bandwidth (200 Hz)
        let wide = QuadratureDetector::new(tone_freq, sr, 200.0, 10);
        let wide_env = wide.compute_envelope(&samples);

        // Narrow bandwidth (60 Hz)
        let narrow = QuadratureDetector::new(tone_freq, sr, 60.0, 10);
        let narrow_env = narrow.compute_envelope(&samples);

        // Skip first 500ms (filter settling time), then compute CV
        let skip = 50; // 50 windows = 500ms

        let cv_wide = coefficient_of_variation(&wide_env[skip..]);
        let cv_narrow = coefficient_of_variation(&narrow_env[skip..]);

        assert!(
            cv_narrow < cv_wide,
            "Narrow BW CV ({cv_narrow:.4}) should be less than wide BW CV ({cv_wide:.4})",
        );
    }

    /// Moving average produces correct output.
    #[test]
    fn moving_average_basic() {
        let signal = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let result = moving_average(&signal, 3);
        // result[2] = mean(1,2,3) = 2.0
        // result[3] = mean(2,3,4) = 3.0
        // result[4] = mean(3,4,5) = 4.0
        assert!((result[2] - 2.0).abs() < 0.001);
        assert!((result[3] - 3.0).abs() < 0.001);
        assert!((result[4] - 4.0).abs() < 0.001);
    }

    fn coefficient_of_variation(data: &[f32]) -> f64 {
        if data.is_empty() {
            return 0.0;
        }
        let mean: f64 = data.iter().map(|&e| e as f64).sum::<f64>() / data.len() as f64;
        if mean.abs() < 1e-10 {
            return 0.0;
        }
        let var: f64 =
            data.iter().map(|&e| (e as f64 - mean).powi(2)).sum::<f64>() / data.len() as f64;
        var.sqrt() / mean
    }
}
