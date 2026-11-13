//! FT8 protocol logic, plus safe Rust wrappers around the vendored `ft8_lib`
//! C library (KISS FFT + LDPC, MIT). Mirrors `FT8Decoder.swift`,
//! `FT8Encoder.swift`, `FT8Message.swift`, and `FT8Constants.swift`.
//!
//! The C sources live in `swift/packages/CarrierWaveCore/Sources/CFT8/` and
//! are compiled in by `build.rs` via the `cc` crate; bindings come from
//! `bindgen` over the same headers the Swift module map exports.

mod ffi;

pub mod constants;
pub mod decoder;
pub mod encoder;
pub mod message;
pub mod wav;

pub use constants::Ft8Constants;
pub use decoder::{decode, decode_default, Ft8DecodeResult};
pub use encoder::{encode, encode_with_sample_rate, Ft8EncodeError};
pub use message::Ft8Message;
pub use wav::{load as load_wav, load_from_bytes as load_wav_from_bytes, WavError};
