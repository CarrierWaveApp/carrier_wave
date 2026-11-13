//! SDR IQ capture + spectrum pipeline for the CW Sweep waterfall.
//!
//! An [`IqSource`] (rtl_tcp, SoapySDR, or a synthetic tone generator) feeds a
//! [`SpectrumEngine`] (windowed FFT + averaging, dB). [`mapping`] projects the
//! SDR spectrum onto RF using the rig's CAT state — either an IF tap (e.g. the
//! Elecraft K3's 8.215 MHz IF OUT) or an SDR tuned directly to RF — and the
//! [`Panadapter`] pipeline delivers VFO-centered, normalized lines to a
//! [`LineSink`]. The UniFFI surface lives in `cw-ffi::panadapter_api`.

pub mod error;
pub mod mapping;
pub mod normalize;
pub mod pipeline;
pub mod rtl_tcp;
#[cfg(target_os = "macos")]
pub mod soapy;
pub mod source;
pub mod spectrum;
pub mod tone;

pub use error::SdrError;
pub use mapping::{RigTuning, TuningMode};
pub use pipeline::{DisplayConfig, LineSink, Panadapter, PanadapterConfig, SpectrumLine};
pub use source::{IqSource, SourceConfig, SourceSpec};
pub use spectrum::SpectrumEngine;
