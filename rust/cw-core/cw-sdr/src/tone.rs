//! Synthetic IQ source: CW carriers at fixed absolute frequencies plus white
//! noise. Used by tests and for exercising the waterfall without hardware.

use std::f64::consts::TAU;
use std::time::{Duration, Instant};

use num_complex::Complex32;

use crate::error::SdrError;
use crate::source::IqSource;

const BLOCK_SAMPLES: usize = 8192;
const TONE_AMPLITUDE: f32 = 0.1;
const NOISE_AMPLITUDE: f32 = 0.01;

pub struct ToneSource {
    sample_rate: f64,
    center_hz: f64,
    /// Absolute tone frequencies (Hz).
    tones: Vec<f64>,
    /// Running phase per tone (radians).
    phases: Vec<f64>,
    rng: u64,
    /// Pace output to real time (false in tests for speed).
    realtime: bool,
    next_deadline: Option<Instant>,
}

impl ToneSource {
    pub fn new(sample_rate: u32, center_hz: f64, tones: Vec<f64>, realtime: bool) -> Self {
        let phases = vec![0.0; tones.len()];
        ToneSource { sample_rate: f64::from(sample_rate), center_hz, tones, phases, rng: 0x9E37_79B9_7F4A_7C15, realtime, next_deadline: None }
    }

    /// Uniform noise in [-1, 1) from a xorshift64 generator.
    fn noise(&mut self) -> f32 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 7;
        self.rng ^= self.rng << 17;
        (self.rng >> 40) as f32 / (1u64 << 23) as f32 - 1.0
    }

    fn pace(&mut self) {
        if !self.realtime {
            return;
        }
        let block = Duration::from_secs_f64(BLOCK_SAMPLES as f64 / self.sample_rate);
        let deadline = self.next_deadline.unwrap_or_else(Instant::now) + block;
        if let Some(wait) = deadline.checked_duration_since(Instant::now()) {
            std::thread::sleep(wait);
        }
        self.next_deadline = Some(deadline);
    }
}

impl IqSource for ToneSource {
    fn read_block(&mut self) -> Result<Option<Vec<Complex32>>, SdrError> {
        self.pace();
        let steps: Vec<f64> = self.tones.iter().map(|tone| TAU * (tone - self.center_hz) / self.sample_rate).collect();
        let mut block = Vec::with_capacity(BLOCK_SAMPLES);
        for _ in 0..BLOCK_SAMPLES {
            let mut sample = Complex32::new(self.noise() * NOISE_AMPLITUDE, self.noise() * NOISE_AMPLITUDE);
            for (phase, step) in self.phases.iter_mut().zip(&steps) {
                sample += Complex32::new(phase.cos() as f32, phase.sin() as f32) * TONE_AMPLITUDE;
                *phase = (*phase + step) % TAU;
            }
            block.push(sample);
        }
        Ok(Some(block))
    }

    fn set_center_hz(&mut self, hz: f64) -> Result<(), SdrError> {
        self.center_hz = hz;
        Ok(())
    }

    fn sample_rate(&self) -> f64 {
        self.sample_rate
    }
}
