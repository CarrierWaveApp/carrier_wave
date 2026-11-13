//! SDR panadapter / waterfall over UniFFI (`cw_sdr`).
//!
//! The host (CW Sweep) supplies the SDR source + IF-tap settings, pushes the
//! rig's CAT state on every change, and appends the returned lines to its
//! `WaterfallStore`. Lines are VFO-centered, ascending in RF and normalized
//! to 0..1; they arrive on a Rust worker thread at ~`fps` per second.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use cw_sdr::{DisplayConfig, LineSink, Panadapter, PanadapterConfig, RigTuning, SourceSpec, SpectrumLine, TuningMode};

// ---------------------------------------------------------------------------
// FFI DTOs
// ---------------------------------------------------------------------------

/// Which SDR backend to open.
#[derive(uniffi::Enum, Clone)]
pub enum FfiPanadapterSource {
    /// rtl_tcp-protocol server (`rtl_tcp`, SDRplay `rsp_tcp`).
    RtlTcp { host: String, port: u16 },
    /// SoapySDR device args (e.g. `driver=sdrplay`). macOS only; needs
    /// Homebrew `soapysdr` plus the device's Soapy module.
    Soapy { args: String },
    /// Synthetic carriers at these offsets (Hz) from the SDR center — for
    /// exercising the waterfall without hardware.
    Tone { offsets_hz: Vec<f64> },
}

#[derive(uniffi::Record, Clone)]
pub struct FfiPanadapterDevice {
    pub source: FfiPanadapterSource,
    pub sample_rate: u32,
    /// Manual gain in dB; `None` for AGC.
    pub gain_db: Option<f64>,
    /// rtl_tcp direct sampling: 0 off, 1 I branch, 2 Q branch (HF on RTL-SDR).
    pub direct_sampling: u8,
    /// Added to every hardware tune (e.g. 125 MHz upconverter).
    pub device_offset_hz: f64,
}

/// How SDR frequencies relate to RF.
#[derive(uniffi::Enum, Clone)]
pub enum FfiTuningMode {
    /// SDR on the rig's IF output (K3: `if_hz` 8_215_000, `inverted` true).
    /// `cal_hz_by_mode` keys are uppercase CAT modes or `"*"`.
    IfTap { if_hz: f64, inverted: bool, lo_offset_hz: f64, cal_hz_by_mode: HashMap<String, f64> },
    /// SDR on the antenna; retuned to follow the VFO.
    DirectRf { lo_offset_hz: f64 },
}

#[derive(uniffi::Record, Clone)]
pub struct FfiPanadapterDisplay {
    pub span_hz: f64,
    pub bins: u32,
    pub fps: f64,
    pub auto_floor: bool,
    pub floor_db: f32,
    pub range_db: f32,
}

/// The rig's CAT state; push on every change.
#[derive(uniffi::Record, Clone)]
pub struct FfiRigTuning {
    pub vfo_hz: f64,
    pub mode: String,
    pub rit_hz: f64,
    pub rit_enabled: bool,
    pub transmitting: bool,
}

#[derive(uniffi::Record, Clone)]
pub struct FfiSpectrumLine {
    /// 0..1 per bin, ascending RF.
    pub values: Vec<f32>,
    /// RF (Hz) at the center bin — the rig's receive frequency.
    pub center_hz: f64,
    pub span_hz: f64,
    pub noise_floor_db: f32,
}

/// Result of [`panadapter_enumerate_soapy_devices`].
#[derive(uniffi::Record, Clone)]
pub struct FfiSoapyEnumeration {
    /// False when libSoapySDR could not be loaded (see `error`).
    pub available: bool,
    pub error: Option<String>,
    /// Soapy args strings, usable as `FfiPanadapterSource::Soapy.args`.
    pub devices: Vec<String>,
}

impl From<FfiPanadapterSource> for SourceSpec {
    fn from(source: FfiPanadapterSource) -> Self {
        match source {
            FfiPanadapterSource::RtlTcp { host, port } => SourceSpec::RtlTcp { host, port },
            FfiPanadapterSource::Soapy { args } => SourceSpec::Soapy { args },
            FfiPanadapterSource::Tone { offsets_hz } => SourceSpec::Tone { offsets_hz },
        }
    }
}

impl From<FfiTuningMode> for TuningMode {
    fn from(mode: FfiTuningMode) -> Self {
        match mode {
            FfiTuningMode::IfTap { if_hz, inverted, lo_offset_hz, cal_hz_by_mode } => TuningMode::IfTap {
                if_hz,
                inverted,
                lo_offset_hz,
                cal_hz_by_mode: cal_hz_by_mode.into_iter().map(|(k, v)| (k.trim().to_uppercase(), v)).collect(),
            },
            FfiTuningMode::DirectRf { lo_offset_hz } => TuningMode::DirectRf { lo_offset_hz },
        }
    }
}

impl From<FfiPanadapterDisplay> for DisplayConfig {
    fn from(display: FfiPanadapterDisplay) -> Self {
        DisplayConfig {
            span_hz: display.span_hz,
            bins: display.bins.clamp(1, 4096) as usize,
            fps: display.fps,
            auto_floor: display.auto_floor,
            floor_db: display.floor_db,
            range_db: display.range_db,
        }
    }
}

impl From<FfiRigTuning> for RigTuning {
    fn from(tuning: FfiRigTuning) -> Self {
        RigTuning {
            vfo_hz: tuning.vfo_hz,
            mode: tuning.mode,
            rit_hz: tuning.rit_hz,
            rit_enabled: tuning.rit_enabled,
            transmitting: tuning.transmitting,
        }
    }
}

// ---------------------------------------------------------------------------
// Listener + handle
// ---------------------------------------------------------------------------

/// Host-side sink. Called on a Rust worker thread — hop to the UI actor.
#[uniffi::export(with_foreign)]
pub trait PanadapterListener: Send + Sync {
    fn on_line(&self, line: FfiSpectrumLine);
    /// Device open / stream failure. `on_stopped` follows.
    fn on_error(&self, message: String);
    /// The worker exited; no further callbacks.
    fn on_stopped(&self);
}

struct ListenerSink(Arc<dyn PanadapterListener>);

impl LineSink for ListenerSink {
    fn on_line(&self, line: SpectrumLine) {
        self.0.on_line(FfiSpectrumLine {
            values: line.values,
            center_hz: line.center_hz,
            span_hz: line.span_hz,
            noise_floor_db: line.noise_floor_db,
        });
    }
    fn on_error(&self, message: String) {
        self.0.on_error(message);
    }
    fn on_stopped(&self) {
        self.0.on_stopped();
    }
}

/// A running panadapter. `stop` (or dropping the handle) ends the stream.
#[derive(uniffi::Object)]
pub struct PanadapterHandle {
    inner: Mutex<Option<Panadapter>>,
}

impl PanadapterHandle {
    fn with(&self, action: impl FnOnce(&Panadapter)) {
        let guard = self.inner.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some(panadapter) = guard.as_ref() {
            action(panadapter);
        }
    }
}

#[uniffi::export]
impl PanadapterHandle {
    /// Start streaming on a background thread. Returns immediately; open
    /// failures arrive via `listener.on_error`. Lines begin after the first
    /// `set_tuning`.
    #[uniffi::constructor]
    pub fn start(
        device: FfiPanadapterDevice,
        tuning_mode: FfiTuningMode,
        display: FfiPanadapterDisplay,
        listener: Arc<dyn PanadapterListener>,
    ) -> Arc<Self> {
        let config = PanadapterConfig {
            source: device.source.into(),
            sample_rate: device.sample_rate,
            gain_db: device.gain_db,
            direct_sampling: device.direct_sampling,
            device_offset_hz: device.device_offset_hz,
            tuning_mode: tuning_mode.into(),
            display: display.into(),
        };
        let panadapter = Panadapter::start(config, Arc::new(ListenerSink(listener)));
        Arc::new(PanadapterHandle { inner: Mutex::new(Some(panadapter)) })
    }

    pub fn set_tuning(&self, tuning: FfiRigTuning) {
        self.with(|pan| pan.set_tuning(tuning.into()));
    }

    pub fn set_tuning_mode(&self, tuning_mode: FfiTuningMode) {
        self.with(|pan| pan.set_tuning_mode(tuning_mode.into()));
    }

    pub fn set_display(&self, display: FfiPanadapterDisplay) {
        self.with(|pan| pan.set_display(display.into()));
    }

    /// Stop and join the worker (blocks ≤ ~0.5 s). Idempotent.
    pub fn stop(&self) {
        let taken = self.inner.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).take();
        if let Some(mut panadapter) = taken {
            panadapter.stop();
        }
    }
}

/// List SoapySDR devices (macOS). Reports unavailability instead of failing
/// so the settings UI can explain how to install SoapySDR.
#[uniffi::export]
pub fn panadapter_enumerate_soapy_devices() -> FfiSoapyEnumeration {
    #[cfg(target_os = "macos")]
    {
        match cw_sdr::soapy::enumerate() {
            Ok(devices) => FfiSoapyEnumeration { available: true, error: None, devices },
            Err(err) => FfiSoapyEnumeration { available: false, error: Some(err.to_string()), devices: Vec::new() },
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        FfiSoapyEnumeration {
            available: false,
            error: Some("SoapySDR is only supported on macOS".into()),
            devices: Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::time::{Duration, Instant};

    #[derive(Default)]
    struct CountingListener {
        lines: AtomicUsize,
        stopped: AtomicBool,
    }

    impl PanadapterListener for CountingListener {
        fn on_line(&self, line: FfiSpectrumLine) {
            assert_eq!(line.values.len(), 256);
            self.lines.fetch_add(1, Ordering::SeqCst);
        }
        fn on_error(&self, message: String) {
            panic!("unexpected error: {message}");
        }
        fn on_stopped(&self) {
            self.stopped.store(true, Ordering::SeqCst);
        }
    }

    #[test]
    fn tone_source_streams_lines_until_stopped() {
        let listener = Arc::new(CountingListener::default());
        let handle = PanadapterHandle::start(
            FfiPanadapterDevice {
                source: FfiPanadapterSource::Tone { offsets_hz: vec![-5_000.0] },
                sample_rate: 192_000,
                gain_db: None,
                direct_sampling: 0,
                device_offset_hz: 0.0,
            },
            FfiTuningMode::DirectRf { lo_offset_hz: 10_000.0 },
            FfiPanadapterDisplay { span_hz: 24_000.0, bins: 256, fps: 25.0, auto_floor: true, floor_db: -110.0, range_db: 60.0 },
            listener.clone(),
        );
        handle.set_tuning(FfiRigTuning { vfo_hz: 7_030_000.0, mode: "cw".into(), rit_hz: 0.0, rit_enabled: false, transmitting: false });
        let deadline = Instant::now() + Duration::from_secs(5);
        while listener.lines.load(Ordering::SeqCst) < 2 && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        handle.stop();
        handle.stop();
        assert!(listener.lines.load(Ordering::SeqCst) >= 2);
        assert!(listener.stopped.load(Ordering::SeqCst));
    }

    #[test]
    fn cal_keys_are_normalized() {
        let mode: TuningMode = FfiTuningMode::IfTap {
            if_hz: 8_215_000.0,
            inverted: true,
            lo_offset_hz: 0.0,
            cal_hz_by_mode: HashMap::from([(" cw ".to_string(), 700.0)]),
        }
        .into();
        assert_eq!(mode.cal_hz("CW"), 700.0);
    }
}
