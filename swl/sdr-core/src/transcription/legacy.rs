//! Legacy decoder — wraps the existing `transcribe_audio()` / `transcribe_audio_structured()`
//! pipeline behind the `CwDecoder` trait with zero functional change.

use uuid::Uuid;

use super::decoder_trait::{CwDecoder, DecoderOutput};
use super::structured::StructuredTranscript;
use super::{transcribe_audio, transcribe_audio_structured};

/// Legacy decoder wrapping the original transcription pipeline.
///
/// This produces identical output to calling `transcribe_audio()` directly.
/// Confidence is hardcoded to 0.85 (matching the existing pipeline).
pub struct LegacyDecoder;

impl CwDecoder for LegacyDecoder {
    fn name(&self) -> &str {
        "legacy"
    }

    fn decode(&self, samples: &[f32], sample_rate: u32) -> DecoderOutput {
        let (text, wpm) = transcribe_audio(samples, sample_rate);
        DecoderOutput {
            text,
            wpm,
            confidence: 0.85,
            word_spans: Vec::new(),
            decoder_name: "legacy".into(),
        }
    }

    fn decode_structured(
        &self,
        samples: &[f32],
        sample_rate: u32,
        recording_id: Uuid,
        progress: &std::sync::atomic::AtomicU8,
    ) -> StructuredTranscript {
        transcribe_audio_structured(samples, sample_rate, recording_id, progress)
    }
}
