use std::f32::consts::PI;

use num_complex::Complex;

use crate::types::DemodMode;

/// Narrowband extractor: shifts a target frequency to baseband, applies
/// a low-pass FIR filter, and decimates.
pub struct NarrowbandExtractor {
    /// NCO phase accumulator.
    nco_phase: f64,
    /// NCO phase increment per sample (radians).
    nco_phase_inc: f64,
    /// FIR filter coefficients.
    fir_coeffs: Vec<f32>,
    /// FIR delay line.
    delay_line: Vec<Complex<f32>>,
    /// Current position in the delay line.
    delay_pos: usize,
    /// Decimation factor.
    decimation: u32,
    /// Decimation counter.
    decim_count: u32,
}

impl NarrowbandExtractor {
    /// Create a new narrowband extractor.
    ///
    /// - `input_sample_rate`: the sample rate of incoming IQ data
    /// - `center_offset`: frequency offset from IQ center to desired signal (Hz)
    /// - `output_bandwidth`: desired output bandwidth (Hz)
    /// - `output_sample_rate`: desired output sample rate (Hz)
    pub fn new(
        input_sample_rate: u32,
        center_offset: f64,
        output_bandwidth: u32,
        output_sample_rate: u32,
    ) -> Self {
        let decimation = input_sample_rate / output_sample_rate;
        let nco_phase_inc = -2.0 * std::f64::consts::PI * center_offset / input_sample_rate as f64;

        // Design a simple low-pass FIR filter
        let cutoff = output_bandwidth as f32 / input_sample_rate as f32;
        let num_taps = 63; // Reasonable for M0 — more taps = sharper rolloff
        let fir_coeffs = design_lpf(num_taps, cutoff);

        Self {
            nco_phase: 0.0,
            nco_phase_inc,
            fir_coeffs: fir_coeffs.clone(),
            delay_line: vec![Complex::new(0.0, 0.0); fir_coeffs.len()],
            delay_pos: 0,
            decimation,
            decim_count: 0,
        }
    }

    /// Process a block of IQ samples. Returns decimated, filtered output.
    pub fn process(&mut self, input: &[Complex<f32>]) -> Vec<Complex<f32>> {
        let mut output = Vec::with_capacity(input.len() / self.decimation as usize + 1);

        for &sample in input {
            // NCO: shift to baseband
            let nco = Complex::new(self.nco_phase.cos() as f32, self.nco_phase.sin() as f32);
            let shifted = sample * nco;
            self.nco_phase += self.nco_phase_inc;
            // Keep phase in [-PI, PI] to avoid precision loss
            if self.nco_phase > std::f64::consts::PI {
                self.nco_phase -= 2.0 * std::f64::consts::PI;
            } else if self.nco_phase < -std::f64::consts::PI {
                self.nco_phase += 2.0 * std::f64::consts::PI;
            }

            // FIR filter
            self.delay_line[self.delay_pos] = shifted;
            self.delay_pos = (self.delay_pos + 1) % self.delay_line.len();

            // Decimation
            self.decim_count += 1;
            if self.decim_count >= self.decimation {
                self.decim_count = 0;

                // Compute FIR output
                let mut acc = Complex::new(0.0f32, 0.0);
                let n = self.fir_coeffs.len();
                for k in 0..n {
                    let idx = (self.delay_pos + n - 1 - k) % n;
                    acc += self.delay_line[idx] * self.fir_coeffs[k];
                }
                output.push(acc);
            }
        }

        output
    }
}

/// Design a windowed-sinc low-pass FIR filter.
pub(crate) fn design_lpf(num_taps: usize, cutoff: f32) -> Vec<f32> {
    let mut coeffs = vec![0.0f32; num_taps];
    let m = (num_taps - 1) as f32;

    for (i, coeff) in coeffs.iter_mut().enumerate() {
        let n = i as f32 - m / 2.0;
        // Sinc
        let sinc = if n.abs() < 1e-6 {
            2.0 * cutoff
        } else {
            (2.0 * PI * cutoff * n).sin() / (PI * n)
        };
        // Hamming window
        let window = 0.54 - 0.46 * (2.0 * PI * i as f32 / m).cos();
        *coeff = sinc * window;
    }

    // Normalize
    let sum: f32 = coeffs.iter().sum();
    if sum.abs() > 1e-10 {
        for c in &mut coeffs {
            *c /= sum;
        }
    }

    coeffs
}

/// Second-order IIR (biquad) filter using Direct Form I.
///
/// Coefficients are designed using the Audio EQ Cookbook (Bristow-Johnson).
pub struct BiquadFilter {
    // Normalized coefficients (divided by a0)
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    // Delay elements
    x1: f32,
    x2: f32,
    y1: f32,
    y2: f32,
}

impl BiquadFilter {
    /// Create a second-order low-pass filter (Butterworth-style when Q=0.707).
    pub fn lowpass(freq: f32, q: f32, sample_rate: u32) -> Self {
        let w0 = 2.0 * PI * freq / sample_rate as f32;
        let alpha = w0.sin() / (2.0 * q);
        let cos_w0 = w0.cos();
        let a0 = 1.0 + alpha;

        Self {
            b0: ((1.0 - cos_w0) / 2.0) / a0,
            b1: (1.0 - cos_w0) / a0,
            b2: ((1.0 - cos_w0) / 2.0) / a0,
            a1: (-2.0 * cos_w0) / a0,
            a2: (1.0 - alpha) / a0,
            x1: 0.0,
            x2: 0.0,
            y1: 0.0,
            y2: 0.0,
        }
    }

    /// Create a second-order high-pass filter (Butterworth-style when Q=0.707).
    pub fn highpass(freq: f32, q: f32, sample_rate: u32) -> Self {
        let w0 = 2.0 * PI * freq / sample_rate as f32;
        let alpha = w0.sin() / (2.0 * q);
        let cos_w0 = w0.cos();
        let a0 = 1.0 + alpha;

        Self {
            b0: ((1.0 + cos_w0) / 2.0) / a0,
            b1: (-(1.0 + cos_w0)) / a0,
            b2: ((1.0 + cos_w0) / 2.0) / a0,
            a1: (-2.0 * cos_w0) / a0,
            a2: (1.0 - alpha) / a0,
            x1: 0.0,
            x2: 0.0,
            y1: 0.0,
            y2: 0.0,
        }
    }

    /// Create a bandpass filter.
    ///
    /// - `center_freq`: center frequency in Hz
    /// - `q`: quality factor (higher = narrower passband)
    /// - `sample_rate`: audio sample rate in Hz
    pub fn bandpass(center_freq: f32, q: f32, sample_rate: u32) -> Self {
        let w0 = 2.0 * PI * center_freq / sample_rate as f32;
        let alpha = w0.sin() / (2.0 * q);
        let a0 = 1.0 + alpha;

        Self {
            b0: alpha / a0,
            b1: 0.0,
            b2: -alpha / a0,
            a1: -2.0 * w0.cos() / a0,
            a2: (1.0 - alpha) / a0,
            x1: 0.0,
            x2: 0.0,
            y1: 0.0,
            y2: 0.0,
        }
    }

    /// Create a notch (band-reject) filter.
    ///
    /// - `freq`: notch center frequency in Hz
    /// - `q`: quality factor (higher = narrower notch; Q=20 → width ≈ freq/20 Hz)
    /// - `sample_rate`: audio sample rate in Hz
    pub fn notch(freq: f32, q: f32, sample_rate: u32) -> Self {
        let w0 = 2.0 * PI * freq / sample_rate as f32;
        let alpha = w0.sin() / (2.0 * q);
        let cos_w0 = w0.cos();
        let a0 = 1.0 + alpha;

        Self {
            b0: 1.0 / a0,
            b1: (-2.0 * cos_w0) / a0,
            b2: 1.0 / a0,
            a1: (-2.0 * cos_w0) / a0,
            a2: (1.0 - alpha) / a0,
            x1: 0.0,
            x2: 0.0,
            y1: 0.0,
            y2: 0.0,
        }
    }

    /// Process a single sample through the filter (Direct Form I).
    pub fn process_sample(&mut self, x: f32) -> f32 {
        let y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2
            - self.a1 * self.y1
            - self.a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = x;
        self.y2 = self.y1;
        self.y1 = y;
        y
    }

    /// Process a block of samples in-place.
    pub fn process_block(&mut self, samples: &mut [f32]) {
        for s in samples.iter_mut() {
            *s = self.process_sample(*s);
        }
    }
}

/// Cascaded biquad filter: chains multiple second-order sections for steeper
/// rolloff than a single biquad (6 dB/oct per stage → N*6 dB/oct total).
pub struct BiquadCascade {
    stages: Vec<BiquadFilter>,
}

impl BiquadCascade {
    /// Create a cascade from pre-built filter stages.
    ///
    /// Use this to build custom filter chains (e.g., asymmetric bandpass + notch).
    pub fn new(stages: Vec<BiquadFilter>) -> Self {
        Self { stages }
    }

    /// Create a steep bandpass filter from cascaded high-pass + low-pass sections.
    ///
    /// - `low_freq`: lower cutoff in Hz
    /// - `high_freq`: upper cutoff in Hz
    /// - `order`: number of second-order sections per edge (total stages = 2*order).
    ///   3 gives 18 dB/oct rolloff per edge — good balance of sharpness vs latency.
    /// - `sample_rate`: audio sample rate in Hz
    pub fn bandpass(low_freq: f32, high_freq: f32, order: usize, sample_rate: u32) -> Self {
        let mut stages = Vec::with_capacity(order * 2);

        // High-pass sections (reject below low_freq)
        for _ in 0..order {
            stages.push(BiquadFilter::highpass(low_freq, 0.707, sample_rate));
        }
        // Low-pass sections (reject above high_freq)
        for _ in 0..order {
            stages.push(BiquadFilter::lowpass(high_freq, 0.707, sample_rate));
        }

        Self { stages }
    }

    /// Process a block of samples through all stages in sequence.
    pub fn process_block(&mut self, samples: &mut [f32]) {
        for stage in &mut self.stages {
            stage.process_block(samples);
        }
    }
}

/// CW bandpass filter edges (Hz).
const CW_BPF_LOW_HZ: f32 = 400.0;
const CW_BPF_HIGH_HZ: f32 = 900.0;
/// Number of biquad sections per edge (3 = 18 dB/oct rolloff per edge).
const CW_BPF_ORDER: usize = 3;
/// CW BFO (Beat Frequency Oscillator) frequency in Hz.
/// Set to the center of the CW bandpass so the beat note passes cleanly.
const CW_BFO_HZ: f64 = 650.0;

/// Demodulator: converts complex IQ to real audio samples.
pub struct Demodulator {
    mode: DemodMode,
    /// Previous sample (reserved for future FM-style derivative).
    _prev_sample: Complex<f32>,
    /// Steep cascaded bandpass filter for CW mode (400-900 Hz).
    cw_filter: Option<BiquadCascade>,
    /// BFO phase accumulator for CW mode (radians).
    bfo_phase: f64,
    /// BFO phase increment per sample (radians).
    bfo_phase_inc: f64,
}

impl Demodulator {
    pub fn new(mode: DemodMode, sample_rate: u32) -> Self {
        let cw_filter = match mode {
            DemodMode::Cw => Some(BiquadCascade::bandpass(
                CW_BPF_LOW_HZ,
                CW_BPF_HIGH_HZ,
                CW_BPF_ORDER,
                sample_rate,
            )),
            _ => None,
        };
        let bfo_phase_inc = match mode {
            DemodMode::Cw => 2.0 * std::f64::consts::PI * CW_BFO_HZ / sample_rate as f64,
            _ => 0.0,
        };
        Self {
            mode,
            _prev_sample: Complex::new(0.0, 0.0),
            cw_filter,
            bfo_phase: 0.0,
            bfo_phase_inc,
        }
    }

    /// Demodulate a block of IQ samples to audio.
    pub fn process(&mut self, input: &[Complex<f32>]) -> Vec<f32> {
        match self.mode {
            DemodMode::Cw => self.demod_cw(input),
            DemodMode::Usb => self.demod_usb(input),
            DemodMode::Lsb => self.demod_lsb(input),
            DemodMode::Am => self.demod_am(input),
        }
    }

    /// CW demodulation: BFO mixing + bandpass filter to produce audible beat note.
    ///
    /// The IQ signal is centered at DC (the SDR is tuned to the CW frequency).
    /// The BFO shifts it to 650 Hz so CW keying produces an audible tone that
    /// passes through the 400-900 Hz bandpass filter.
    fn demod_cw(&mut self, input: &[Complex<f32>]) -> Vec<f32> {
        let mut audio: Vec<f32> = input
            .iter()
            .map(|s| {
                let bfo = self.bfo_phase.cos() as f32;
                self.bfo_phase += self.bfo_phase_inc;
                if self.bfo_phase > std::f64::consts::PI {
                    self.bfo_phase -= 2.0 * std::f64::consts::PI;
                }
                s.re * bfo
            })
            .collect();
        if let Some(ref mut filter) = self.cw_filter {
            filter.process_block(&mut audio);
        }
        audio
    }

    /// USB demodulation: take the real part of the analytic signal.
    fn demod_usb(&mut self, input: &[Complex<f32>]) -> Vec<f32> {
        input.iter().map(|s| s.re).collect()
    }

    /// LSB demodulation: conjugate then take real part.
    fn demod_lsb(&mut self, input: &[Complex<f32>]) -> Vec<f32> {
        input.iter().map(|s| s.re + s.im).collect()
    }

    /// AM envelope detection.
    fn demod_am(&mut self, input: &[Complex<f32>]) -> Vec<f32> {
        input.iter().map(|s| s.norm()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extractor_decimates_correctly() {
        let input_rate = 48_000;
        let output_rate = 12_000;
        let extractor = NarrowbandExtractor::new(input_rate, 0.0, 6_000, output_rate);

        // 48000 input samples → should produce ~12000 output samples
        let input: Vec<Complex<f32>> = (0..input_rate as usize)
            .map(|i| {
                let t = i as f32 / input_rate as f32;
                Complex::new((2.0 * PI * 1000.0 * t).cos(), 0.0)
            })
            .collect();

        let mut ext = extractor;
        let output = ext.process(&input);

        assert_eq!(output.len(), output_rate as usize);
    }

    #[test]
    fn extractor_shifts_frequency() {
        let input_rate = 48_000u32;
        let tone_offset = 5000.0; // 5kHz tone offset from center
        let output_rate = 12_000u32;

        // Generate a tone at the offset frequency
        let n = input_rate as usize;
        let input: Vec<Complex<f32>> = (0..n)
            .map(|i| {
                let t = i as f64 / input_rate as f64;
                let phase = 2.0 * std::f64::consts::PI * tone_offset * t;
                Complex::new(phase.cos() as f32, phase.sin() as f32)
            })
            .collect();

        let mut ext = NarrowbandExtractor::new(input_rate, tone_offset, 6_000, output_rate);
        let output = ext.process(&input);

        // After shifting, the tone should be at DC.
        // The output should have a large DC component (mean magnitude).
        let mean_mag: f32 = output.iter().map(|s| s.norm()).sum::<f32>() / output.len() as f32;

        // With a clean tone shifted to DC through a LPF, mean magnitude should be high
        assert!(
            mean_mag > 0.3,
            "Mean magnitude {mean_mag} too low — frequency shift may not be working"
        );
    }

    #[test]
    fn demodulator_usb_extracts_real() {
        let mut demod = Demodulator::new(DemodMode::Usb, 12_000);
        let input = vec![
            Complex::new(1.0, 0.5),
            Complex::new(-0.5, 0.3),
            Complex::new(0.0, -1.0),
        ];
        let output = demod.process(&input);
        assert_eq!(output, vec![1.0, -0.5, 0.0]);
    }

    #[test]
    fn demodulator_am_extracts_envelope() {
        let mut demod = Demodulator::new(DemodMode::Am, 12_000);
        let input = vec![
            Complex::new(3.0, 4.0), // norm = 5.0
            Complex::new(0.0, 1.0), // norm = 1.0
        ];
        let output = demod.process(&input);
        assert!((output[0] - 5.0).abs() < 0.001);
        assert!((output[1] - 1.0).abs() < 0.001);
    }

    #[test]
    fn fir_coefficients_normalized() {
        let coeffs = design_lpf(63, 0.1);
        let sum: f32 = coeffs.iter().sum();
        assert!((sum - 1.0).abs() < 0.001, "FIR sum = {sum}");
    }

    /// Helper: generate a mono tone as f32 samples.
    fn generate_tone(freq: f32, sample_rate: u32, num_samples: usize, amplitude: f32) -> Vec<f32> {
        (0..num_samples)
            .map(|i| {
                let t = i as f32 / sample_rate as f32;
                amplitude * (2.0 * PI * freq * t).sin()
            })
            .collect()
    }

    /// Helper: compute RMS of a signal.
    fn rms(signal: &[f32]) -> f32 {
        (signal.iter().map(|s| s * s).sum::<f32>() / signal.len() as f32).sqrt()
    }

    #[test]
    fn biquad_bandpass_passes_center_frequency() {
        let sample_rate = 12_000;
        let mut filter = BiquadFilter::bandpass(650.0, 1.3, sample_rate);

        // Generate a 650 Hz tone (center of the passband)
        let input = generate_tone(650.0, sample_rate, sample_rate as usize, 1.0);
        let mut output = input.clone();
        filter.process_block(&mut output);

        // Skip first 1000 samples for filter settling
        let input_rms = rms(&input[1000..]);
        let output_rms = rms(&output[1000..]);
        let gain_db = 20.0 * (output_rms / input_rms).log10();

        assert!(
            gain_db.abs() < 1.0,
            "Center frequency gain should be ~0 dB, got {gain_db:.2} dB"
        );
    }

    #[test]
    fn biquad_bandpass_attenuates_out_of_band() {
        let sample_rate = 12_000;

        // Test 100 Hz (well below passband)
        let mut filter_low = BiquadFilter::bandpass(650.0, 1.3, sample_rate);
        let input_low = generate_tone(100.0, sample_rate, sample_rate as usize, 1.0);
        let mut output_low = input_low.clone();
        filter_low.process_block(&mut output_low);
        let gain_low_db = 20.0 * (rms(&output_low[1000..]) / rms(&input_low[1000..])).log10();

        assert!(
            gain_low_db < -6.0,
            "100 Hz should be attenuated >6 dB, got {gain_low_db:.2} dB"
        );

        // Test 3000 Hz (well above passband)
        let mut filter_high = BiquadFilter::bandpass(650.0, 1.3, sample_rate);
        let input_high = generate_tone(3000.0, sample_rate, sample_rate as usize, 1.0);
        let mut output_high = input_high.clone();
        filter_high.process_block(&mut output_high);
        let gain_high_db = 20.0 * (rms(&output_high[1000..]) / rms(&input_high[1000..])).log10();

        assert!(
            gain_high_db < -6.0,
            "3000 Hz should be attenuated >6 dB, got {gain_high_db:.2} dB"
        );
    }

    #[test]
    fn demodulator_cw_produces_beat_note() {
        let sample_rate = 12_000u32;
        let n = sample_rate as usize;

        // Simulate a CW carrier at baseband (DC): constant amplitude in IQ.
        // This is what the SDR produces when tuned exactly to the CW signal.
        let input: Vec<Complex<f32>> = vec![Complex::new(1.0, 0.0); n];

        let mut demod = Demodulator::new(DemodMode::Cw, sample_rate);
        let output = demod.process(&input);

        // The BFO should produce a 650 Hz tone. Measure its energy via DFT.
        let bin_650 = (650.0 / sample_rate as f32 * n as f32) as usize;
        let mut real_sum = 0.0f64;
        let mut imag_sum = 0.0f64;
        // Skip first 1000 samples for filter settling
        for (i, &s) in output.iter().enumerate().skip(1000) {
            let angle = 2.0 * std::f64::consts::PI * bin_650 as f64 * i as f64 / n as f64;
            real_sum += s as f64 * angle.cos();
            imag_sum += s as f64 * angle.sin();
        }
        let mag_650 =
            ((real_sum * real_sum + imag_sum * imag_sum).sqrt() / (n - 1000) as f64) as f32;

        assert!(
            mag_650 > 0.1,
            "CW demod should produce a strong 650 Hz beat note, got magnitude {mag_650:.4}"
        );

        // DC component should be suppressed by the bandpass
        let dc_energy: f32 = output[1000..].iter().sum::<f32>() / (n - 1000) as f32;
        assert!(
            dc_energy.abs() < 0.05,
            "DC should be suppressed by bandpass, got {dc_energy:.4}"
        );
    }

    #[test]
    fn demodulator_usb_does_not_filter() {
        let sample_rate = 12_000u32;
        let n = sample_rate as usize;

        // Composite signal with 650 Hz + 3000 Hz
        let input: Vec<Complex<f32>> = (0..n)
            .map(|i| {
                let t = i as f32 / sample_rate as f32;
                let a = (2.0 * PI * 650.0 * t).sin();
                let b = (2.0 * PI * 3000.0 * t).sin();
                Complex::new(a + b, 0.0)
            })
            .collect();

        let mut demod = Demodulator::new(DemodMode::Usb, sample_rate);
        let output = demod.process(&input);

        // USB should pass through unchanged (pure real-part extraction)
        for (i, (&out, inp)) in output.iter().zip(input.iter()).enumerate() {
            assert!(
                (out - inp.re).abs() < 1e-6,
                "USB output should equal input real part at sample {i}"
            );
        }
    }

    #[test]
    fn biquad_filter_is_stable() {
        let sample_rate = 12_000u32;
        let mut filter = BiquadFilter::bandpass(650.0, 1.3, sample_rate);

        // Process 10 seconds of a 650 Hz tone
        let num_samples = sample_rate as usize * 10;
        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            let x = (2.0 * PI * 650.0 * t).sin();
            let y = filter.process_sample(x);
            assert!(
                y.is_finite(),
                "Filter output is not finite at sample {i}: {y}"
            );
        }
    }

    #[test]
    fn biquad_notch_rejects_target_preserves_neighbor() {
        let sample_rate = 12_000u32;
        let n = sample_rate as usize * 2; // 2 seconds for good frequency resolution

        // Two tones at equal amplitude: 525 Hz (target) + 551 Hz (interferer)
        let mut signal: Vec<f32> = (0..n)
            .map(|i| {
                let t = i as f32 / sample_rate as f32;
                0.5 * (2.0 * PI * 525.0 * t).sin() + 0.5 * (2.0 * PI * 551.0 * t).sin()
            })
            .collect();

        // Measure energy before notch
        let energy_525_before = goertzel_energy(&signal, 525.0, sample_rate);
        let energy_551_before = goertzel_energy(&signal, 551.0, sample_rate);

        // Apply notch at 551 Hz with Q=20
        BiquadFilter::notch(551.0, 20.0, sample_rate).process_block(&mut signal);

        // Measure energy after notch (skip first 1000 samples for settling)
        let energy_525_after = goertzel_energy(&signal[1000..], 525.0, sample_rate);
        let energy_551_after = goertzel_energy(&signal[1000..], 551.0, sample_rate);

        // 525 Hz should be preserved (within -3 dB)
        let gain_525_db = 10.0 * (energy_525_after / energy_525_before).log10();
        assert!(
            gain_525_db > -3.0,
            "525 Hz should be preserved (within -3 dB), got {gain_525_db:.1} dB"
        );

        // 551 Hz should be heavily attenuated (>30 dB)
        let rejection_551_db = 10.0 * (energy_551_before / energy_551_after).log10();
        assert!(
            rejection_551_db > 30.0,
            "551 Hz should be rejected by >30 dB, got {rejection_551_db:.1} dB"
        );
    }

    /// Goertzel energy measurement at a specific frequency.
    fn goertzel_energy(samples: &[f32], freq: f32, sample_rate: u32) -> f32 {
        let k = (freq * samples.len() as f32 / sample_rate as f32).round();
        let w = 2.0 * PI * k / samples.len() as f32;
        let coeff = 2.0 * w.cos();
        let mut s1 = 0.0f64;
        let mut s2 = 0.0f64;
        for &x in samples {
            let s0 = x as f64 + coeff as f64 * s1 - s2;
            s2 = s1;
            s1 = s0;
        }
        let power = s1 * s1 + s2 * s2 - coeff as f64 * s1 * s2;
        (power / (samples.len() as f64 * samples.len() as f64)) as f32
    }
}
