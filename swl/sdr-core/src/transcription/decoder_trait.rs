//! Decoder abstraction for pluggable CW decoding strategies.
//!
//! The `CwDecoder` trait defines the interface that all decoder implementations
//! must satisfy. This enables A/B comparison, ensemble decoding, and incremental
//! evolution of the decoding pipeline.

use uuid::Uuid;

use super::beam::WordSpan;
use super::structured::StructuredTranscript;

/// Output from a CW decoder.
#[derive(Debug, Clone)]
pub struct DecoderOutput {
    /// Decoded plain text.
    pub text: String,
    /// Estimated words per minute, if determinable.
    pub wpm: Option<f64>,
    /// Overall confidence score (0.0–1.0).
    pub confidence: f64,
    /// Per-word timing spans.
    pub word_spans: Vec<WordSpan>,
    /// Name of the decoder that produced this output.
    pub decoder_name: String,
}

/// Trait for CW decoder implementations.
///
/// Implementations must be `Send + Sync` to allow `Arc<dyn CwDecoder>` usage
/// across async boundaries.
pub trait CwDecoder: Send + Sync {
    /// Human-readable decoder name (e.g., "legacy", "decoder-a").
    fn name(&self) -> &str;

    /// Decode raw audio samples into text.
    ///
    /// This is the simple interface returning `(text, wpm)` — used by
    /// `TranscriptionEngine::transcribe_recording()` for DB-backed recordings.
    fn decode(&self, samples: &[f32], sample_rate: u32) -> DecoderOutput;

    /// Decode raw audio samples into a structured transcript with word-level timing.
    ///
    /// Used by `TranscriptionEngine::start_transcription_async()` for uploaded recordings.
    /// The `progress` atomic is updated 0–100 as decoding proceeds.
    fn decode_structured(
        &self,
        samples: &[f32],
        sample_rate: u32,
        recording_id: Uuid,
        progress: &std::sync::atomic::AtomicU8,
    ) -> StructuredTranscript;
}
