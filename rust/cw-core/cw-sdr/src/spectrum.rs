//! Windowed-FFT power spectrum with block averaging.
//!
//! Output spectra are DC-centered (fft-shifted): bin `i` covers baseband
//! offset `(i - n/2) * sample_rate / n` Hz. Values are dB relative to full
//! scale, with the DC spike (LO leakage) notched out.

use std::sync::Arc;

use num_complex::Complex32;
use rustfft::{Fft, FftPlanner};

const MIN_FFT_SIZE: usize = 256;
const MAX_FFT_SIZE: usize = 65_536;
/// Bins on each side of DC replaced by the notch (the Blackman-Harris main
/// lobe spans ±4 bins).
const DC_NOTCH_HALF_WIDTH: usize = 4;

pub struct SpectrumEngine {
    fft: Arc<dyn Fft<f32>>,
    size: usize,
    window: Vec<f32>,
    /// dB offset normalizing power to full scale for this window and size.
    scale_db: f32,
    avg_count: usize,
    accum: Vec<f32>,
    averaged: usize,
    frame: Vec<Complex32>,
    sample_rate: f64,
}

impl SpectrumEngine {
    /// Pick an FFT size so one FFT bin is no wider than one display bin, and
    /// the number of FFTs averaged per line to land near `fps` lines/second.
    pub fn plan(sample_rate: f64, span_hz: f64, bins: usize, fps: f64) -> (usize, usize) {
        let display_bin_hz = (span_hz / bins.max(1) as f64).max(1.0);
        let wanted = (sample_rate / display_bin_hz).ceil().max(1.0) as usize;
        let size = wanted.next_power_of_two().clamp(MIN_FFT_SIZE, MAX_FFT_SIZE);
        let avg = (sample_rate / (size as f64 * fps.max(1.0))).round().max(1.0) as usize;
        (size, avg)
    }

    pub fn new(sample_rate: f64, fft_size: usize, avg_count: usize) -> Self {
        let size = fft_size.max(MIN_FFT_SIZE);
        let window = blackman_harris(size);
        let coherent_gain: f32 = window.iter().sum();
        let scale_db = -20.0 * coherent_gain.log10();
        SpectrumEngine {
            fft: FftPlanner::new().plan_fft_forward(size),
            size,
            window,
            scale_db,
            avg_count: avg_count.max(1),
            accum: vec![0.0; size],
            averaged: 0,
            frame: Vec::with_capacity(size),
            sample_rate,
        }
    }

    pub fn for_display(sample_rate: f64, span_hz: f64, bins: usize, fps: f64) -> Self {
        let (size, avg) = Self::plan(sample_rate, span_hz, bins, fps);
        Self::new(sample_rate, size, avg)
    }

    pub fn fft_size(&self) -> usize {
        self.size
    }

    pub fn bin_hz(&self) -> f64 {
        self.sample_rate / self.size as f64
    }

    /// Drop any partially accumulated data (e.g. after a retune).
    pub fn reset(&mut self) {
        self.frame.clear();
        self.accum.iter_mut().for_each(|acc| *acc = 0.0);
        self.averaged = 0;
    }

    /// Feed samples; returns every completed averaged spectrum (dB).
    pub fn push(&mut self, samples: &[Complex32]) -> Vec<Vec<f32>> {
        let mut completed = Vec::new();
        let mut rest = samples;
        while !rest.is_empty() {
            let take = (self.size - self.frame.len()).min(rest.len());
            self.frame.extend_from_slice(&rest[..take]);
            rest = &rest[take..];
            if self.frame.len() == self.size {
                self.accumulate_frame();
                if self.averaged == self.avg_count {
                    completed.push(self.finish_line());
                }
            }
        }
        completed
    }

    fn accumulate_frame(&mut self) {
        for (sample, weight) in self.frame.iter_mut().zip(&self.window) {
            *sample *= *weight;
        }
        self.fft.process(&mut self.frame);
        let half = self.size / 2;
        for (i, acc) in self.accum.iter_mut().enumerate() {
            *acc += self.frame[(i + half) % self.size].norm_sqr();
        }
        self.frame.clear();
        self.averaged += 1;
    }

    fn finish_line(&mut self) -> Vec<f32> {
        let count = self.averaged as f32;
        let mut line: Vec<f32> = self
            .accum
            .iter()
            .map(|power| 10.0 * (power / count + 1e-20).log10() + self.scale_db)
            .collect();
        notch_dc(&mut line);
        self.accum.iter_mut().for_each(|acc| *acc = 0.0);
        self.averaged = 0;
        line
    }
}

/// 4-term Blackman-Harris window (~92 dB sidelobes).
fn blackman_harris(size: usize) -> Vec<f32> {
    let denom = (size - 1) as f64;
    (0..size)
        .map(|i| {
            let x = std::f64::consts::TAU * i as f64 / denom;
            (0.35875 - 0.48829 * x.cos() + 0.14128 * (2.0 * x).cos() - 0.01168 * (3.0 * x).cos()) as f32
        })
        .collect()
}

/// Replace the bins around DC with the mean of their outer neighbors.
fn notch_dc(line: &mut [f32]) {
    let mid = line.len() / 2;
    let width = DC_NOTCH_HALF_WIDTH;
    if mid < width + 1 || mid + width + 1 >= line.len() {
        return;
    }
    let fill = (line[mid - width - 1] + line[mid + width + 1]) / 2.0;
    line[mid - width..=mid + width].iter_mut().for_each(|value| *value = fill);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source::IqSource;
    use crate::tone::ToneSource;

    fn argmax(line: &[f32]) -> usize {
        line.iter().enumerate().fold(0, |best, (i, v)| if *v > line[best] { i } else { best })
    }

    #[test]
    fn plans_fft_size_and_averaging() {
        // 2 MS/s, 96 kHz over 1024 bins → ≤ 93.75 Hz bins → 32768-point FFT.
        let (size, avg) = SpectrumEngine::plan(2_000_000.0, 96_000.0, 1024, 25.0);
        assert_eq!(size, 32_768);
        assert_eq!(avg, 2);
        // Low rates never average below one FFT per line.
        assert_eq!(SpectrumEngine::plan(48_000.0, 48_000.0, 1024, 25.0), (1024, 2));
    }

    #[test]
    fn tone_lands_in_expected_bin() {
        let rate = 48_000u32;
        let mut source = ToneSource::new(rate, 0.0, vec![3_200.0], false);
        let mut engine = SpectrumEngine::new(f64::from(rate), 4096, 2);
        let mut lines = Vec::new();
        while lines.is_empty() {
            lines = engine.push(&source.read_block().unwrap().unwrap());
        }
        let expected = 2048 + (3_200.0 / engine.bin_hz()).round() as usize;
        let peak = argmax(&lines[0]);
        assert!(peak.abs_diff(expected) <= 1, "peak {peak} expected {expected}");
        // Tone ≈ -20 dBFS (amplitude 0.1); noise far below.
        assert!(lines[0][peak] > -26.0 && lines[0][peak] < -14.0, "tone level {}", lines[0][peak]);
        assert!(lines[0][100] < -60.0);
    }

    #[test]
    fn notches_dc_spike() {
        let mut engine = SpectrumEngine::new(48_000.0, 1024, 1);
        let dc = vec![Complex32::new(0.5, 0.0); 1024];
        let line = engine.push(&dc).remove(0);
        assert!(line[512] < line[500] + 1.0);
    }
}
