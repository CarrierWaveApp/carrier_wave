//! Panadapter pipeline: one worker thread reads IQ, averages FFTs, projects
//! the spectrum onto RF around the rig's receive frequency and hands
//! normalized lines to a [`LineSink`].

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
use std::time::Duration;

use crate::error::SdrError;
use crate::mapping::{project, RigTuning, TuningMode};
use crate::normalize::Normalizer;
use crate::source::{self, IqSource, SourceConfig, SourceSpec};
use crate::spectrum::SpectrumEngine;

/// How often the worker checks for CAT state before the first tuning arrives.
const TUNING_WAIT_POLL: Duration = Duration::from_millis(50);

#[derive(Debug, Clone, PartialEq)]
pub struct DisplayConfig {
    pub span_hz: f64,
    pub bins: usize,
    pub fps: f64,
    pub auto_floor: bool,
    pub floor_db: f32,
    pub range_db: f32,
}

impl Default for DisplayConfig {
    fn default() -> Self {
        DisplayConfig { span_hz: 96_000.0, bins: 1024, fps: 25.0, auto_floor: true, floor_db: -110.0, range_db: 60.0 }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct PanadapterConfig {
    pub source: SourceSpec,
    pub sample_rate: u32,
    pub gain_db: Option<f64>,
    pub direct_sampling: u8,
    /// Added to every hardware tune (e.g. +125 MHz for an upconverter).
    pub device_offset_hz: f64,
    pub tuning_mode: TuningMode,
    pub display: DisplayConfig,
}

/// One normalized waterfall line, ascending in RF.
#[derive(Debug, Clone, PartialEq)]
pub struct SpectrumLine {
    /// 0..1 per display bin.
    pub values: Vec<f32>,
    /// RF at the center bin — the rig's receive frequency.
    pub center_hz: f64,
    pub span_hz: f64,
    pub noise_floor_db: f32,
}

/// Receives pipeline output. Called on the worker thread.
pub trait LineSink: Send + Sync {
    fn on_line(&self, line: SpectrumLine);
    fn on_error(&self, message: String);
    /// Always the final call, after the worker exits for any reason.
    fn on_stopped(&self);
}

type SourceOpener = Box<dyn FnOnce(&SourceConfig) -> Result<Box<dyn IqSource>, SdrError> + Send>;

struct Settings {
    tuning_mode: TuningMode,
    display: DisplayConfig,
    generation: u64,
}

struct Shared {
    stop: AtomicBool,
    tuning: Mutex<Option<RigTuning>>,
    settings: Mutex<Settings>,
}

/// Lock, recovering from poisoning (a panicked holder can't corrupt these
/// plain-data snapshots).
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub struct Panadapter {
    shared: Arc<Shared>,
    worker: Option<JoinHandle<()>>,
}

impl Panadapter {
    /// Start streaming. Opening the device happens on the worker thread;
    /// failures arrive through [`LineSink::on_error`]. No lines are produced
    /// until the first [`Panadapter::set_tuning`].
    pub fn start(config: PanadapterConfig, sink: Arc<dyn LineSink>) -> Self {
        let spec = config.source.clone();
        Self::start_with_opener(config, Box::new(move |cfg| source::open(&spec, cfg)), sink)
    }

    fn start_with_opener(config: PanadapterConfig, opener: SourceOpener, sink: Arc<dyn LineSink>) -> Self {
        let shared = Arc::new(Shared {
            stop: AtomicBool::new(false),
            tuning: Mutex::new(None),
            settings: Mutex::new(Settings {
                tuning_mode: config.tuning_mode.clone(),
                display: config.display.clone(),
                generation: 0,
            }),
        });
        let worker_shared = Arc::clone(&shared);
        let worker = std::thread::Builder::new()
            .name("cw-sdr-panadapter".into())
            .spawn(move || {
                if let Err(err) = run(&config, opener, &worker_shared, sink.as_ref()) {
                    sink.on_error(err.to_string());
                }
                sink.on_stopped();
            })
            .ok();
        Panadapter { shared, worker }
    }

    pub fn set_tuning(&self, tuning: RigTuning) {
        *lock(&self.shared.tuning) = Some(tuning);
    }

    pub fn set_display(&self, display: DisplayConfig) {
        let mut settings = lock(&self.shared.settings);
        settings.display = display;
        settings.generation += 1;
    }

    pub fn set_tuning_mode(&self, tuning_mode: TuningMode) {
        let mut settings = lock(&self.shared.settings);
        settings.tuning_mode = tuning_mode;
        settings.generation += 1;
    }

    /// Stop the worker and wait for it to exit (≤ one source read timeout).
    pub fn stop(&mut self) {
        self.shared.stop.store(true, Ordering::SeqCst);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

impl Drop for Panadapter {
    fn drop(&mut self) {
        self.stop();
    }
}

fn run(config: &PanadapterConfig, opener: SourceOpener, shared: &Shared, sink: &dyn LineSink) -> Result<(), SdrError> {
    let Some(first_tuning) = wait_for_tuning(shared) else {
        return Ok(());
    };
    let (mut tuning_mode, mut display, mut generation) = {
        let settings = lock(&shared.settings);
        (settings.tuning_mode.clone(), settings.display.clone(), settings.generation)
    };
    let mut center = tuning_mode.ideal_sdr_center(&first_tuning);
    let mut source = opener(&SourceConfig {
        sample_rate: config.sample_rate,
        center_hz: center + config.device_offset_hz,
        gain_db: config.gain_db,
        direct_sampling: config.direct_sampling,
    })?;
    let rate = source.sample_rate();
    let mut engine = SpectrumEngine::for_display(rate, display.span_hz, display.bins, display.fps);
    let mut normalizer = Normalizer::new(display.auto_floor, display.floor_db, display.range_db);

    while !shared.stop.load(Ordering::SeqCst) {
        {
            let settings = lock(&shared.settings);
            if settings.generation != generation {
                tuning_mode = settings.tuning_mode.clone();
                display = settings.display.clone();
                generation = settings.generation;
                engine = SpectrumEngine::for_display(rate, display.span_hz, display.bins, display.fps);
                normalizer = Normalizer::new(display.auto_floor, display.floor_db, display.range_db);
            }
        }
        let tuning = lock(&shared.tuning).clone().unwrap_or_else(|| first_tuning.clone());
        if let Some(target) = tuning_mode.retune_target(&tuning, center, rate, display.span_hz) {
            source.set_center_hz(target + config.device_offset_hz)?;
            center = target;
            engine.reset();
        }
        let Some(samples) = source.read_block()? else {
            return Ok(());
        };
        for spectrum in engine.push(&samples) {
            let tuning = lock(&shared.tuning).clone().unwrap_or_else(|| first_tuning.clone());
            if tuning.transmitting {
                continue;
            }
            let map = tuning_mode.frequency_map(&tuning);
            let receive = tuning.receive_hz();
            let projected = project(&spectrum, rate, center, &map, receive, display.span_hz, display.bins);
            let (values, noise_floor_db) = normalizer.process(&projected);
            sink.on_line(SpectrumLine { values, center_hz: receive, span_hz: display.span_hz, noise_floor_db });
        }
    }
    Ok(())
}

/// Block until the host pushes the first CAT state (or a stop is requested).
fn wait_for_tuning(shared: &Shared) -> Option<RigTuning> {
    loop {
        if shared.stop.load(Ordering::SeqCst) {
            return None;
        }
        if let Some(tuning) = lock(&shared.tuning).clone() {
            return Some(tuning);
        }
        std::thread::sleep(TUNING_WAIT_POLL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tone::ToneSource;
    use std::collections::HashMap;
    use std::time::Instant;

    const K3_IF: f64 = 8_215_000.0;

    #[derive(Default)]
    struct CollectingSink {
        lines: Mutex<Vec<SpectrumLine>>,
        errors: Mutex<Vec<String>>,
        stopped: AtomicBool,
    }

    impl LineSink for CollectingSink {
        fn on_line(&self, line: SpectrumLine) {
            lock(&self.lines).push(line);
        }
        fn on_error(&self, message: String) {
            lock(&self.errors).push(message);
        }
        fn on_stopped(&self) {
            self.stopped.store(true, Ordering::SeqCst);
        }
    }

    fn wait_until(timeout: Duration, condition: impl Fn() -> bool) -> bool {
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if condition() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        condition()
    }

    fn config() -> PanadapterConfig {
        PanadapterConfig {
            source: SourceSpec::Tone { offsets_hz: vec![] },
            sample_rate: 192_000,
            gain_db: None,
            direct_sampling: 0,
            device_offset_hz: 0.0,
            tuning_mode: TuningMode::IfTap { if_hz: K3_IF, inverted: true, lo_offset_hz: 20_000.0, cal_hz_by_mode: HashMap::new() },
            display: DisplayConfig { span_hz: 48_000.0, bins: 480, ..DisplayConfig::default() },
        }
    }

    /// Opener for a non-paced tone at an absolute SDR frequency.
    fn tone_opener(tone_hz: f64) -> SourceOpener {
        Box::new(move |cfg: &SourceConfig| {
            Ok(Box::new(ToneSource::new(cfg.sample_rate, cfg.center_hz, vec![tone_hz], false)) as Box<dyn IqSource>)
        })
    }

    fn rig(transmitting: bool) -> RigTuning {
        RigTuning { vfo_hz: 14_030_000.0, mode: "CW".into(), rit_hz: 0.0, rit_enabled: false, transmitting }
    }

    #[test]
    fn if_tap_line_is_vfo_centered_and_inverted() {
        let sink = Arc::new(CollectingSink::default());
        let mut pan = Panadapter::start_with_opener(config(), tone_opener(K3_IF - 1_500.0), sink.clone());
        pan.set_tuning(rig(false));
        assert!(wait_until(Duration::from_secs(5), || lock(&sink.lines).len() >= 3));
        pan.stop();

        let lines = lock(&sink.lines);
        let line = &lines[2];
        assert_eq!(line.center_hz, 14_030_000.0);
        assert_eq!(line.values.len(), 480);
        let peak = line.values.iter().enumerate().fold(0, |best, (i, v)| if *v > line.values[best] { i } else { best });
        // Inverted: 1.5 kHz below the IF → 1.5 kHz above the VFO → bin 255 of 480.
        assert!(peak.abs_diff(255) <= 1, "peak at {peak}");
        assert!(sink.stopped.load(Ordering::SeqCst));
    }

    #[test]
    fn transmitting_suppresses_lines() {
        let sink = Arc::new(CollectingSink::default());
        let mut pan = Panadapter::start_with_opener(config(), tone_opener(K3_IF), sink.clone());
        pan.set_tuning(rig(true));
        std::thread::sleep(Duration::from_millis(200));
        assert!(lock(&sink.lines).is_empty());
        pan.set_tuning(rig(false));
        assert!(wait_until(Duration::from_secs(5), || !lock(&sink.lines).is_empty()));
        pan.stop();
    }

    #[test]
    fn open_failure_reports_error_then_stopped() {
        let sink = Arc::new(CollectingSink::default());
        let opener: SourceOpener = Box::new(|_| Err(SdrError::Device("no such device".into())));
        let pan = Panadapter::start_with_opener(config(), opener, sink.clone());
        pan.set_tuning(rig(false));
        assert!(wait_until(Duration::from_secs(5), || sink.stopped.load(Ordering::SeqCst)));
        assert_eq!(lock(&sink.errors).as_slice(), ["SDR device error: no such device"]);
    }

    #[test]
    fn stop_before_tuning_exits_cleanly() {
        let sink = Arc::new(CollectingSink::default());
        let mut pan = Panadapter::start_with_opener(config(), tone_opener(K3_IF), sink.clone());
        pan.stop();
        assert!(sink.stopped.load(Ordering::SeqCst));
        assert!(lock(&sink.errors).is_empty());
    }
}
