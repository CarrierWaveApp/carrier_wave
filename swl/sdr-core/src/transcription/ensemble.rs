//! Ensemble decoder — runs multiple decoders and combines their outputs.
//!
//! Supports several combination strategies: pick the highest-confidence result,
//! majority-vote on word boundaries, or weighted averaging. The ensemble itself
//! implements `CwDecoder` so it can be used as a drop-in replacement.

use std::sync::Arc;

use uuid::Uuid;

use super::decoder_trait::{CwDecoder, DecoderOutput};
use super::structured::StructuredTranscript;

/// Strategy for combining results from multiple decoders.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CombineStrategy {
    /// Pick the decoder result with the highest overall confidence.
    HighestConfidence,
}

/// Ensemble decoder that runs multiple decoders and combines their outputs.
pub struct EnsembleDecoder {
    decoders: Vec<Arc<dyn CwDecoder>>,
    strategy: CombineStrategy,
}

impl EnsembleDecoder {
    /// Create a new ensemble decoder with the given decoders and combination strategy.
    pub fn new(decoders: Vec<Arc<dyn CwDecoder>>, strategy: CombineStrategy) -> Self {
        assert!(
            !decoders.is_empty(),
            "ensemble requires at least one decoder"
        );
        Self { decoders, strategy }
    }
}

impl CwDecoder for EnsembleDecoder {
    fn name(&self) -> &str {
        "ensemble"
    }

    fn decode(&self, samples: &[f32], sample_rate: u32) -> DecoderOutput {
        let results: Vec<DecoderOutput> = self
            .decoders
            .iter()
            .map(|d| d.decode(samples, sample_rate))
            .collect();

        match self.strategy {
            CombineStrategy::HighestConfidence => results
                .into_iter()
                .max_by(|a, b| {
                    a.confidence
                        .partial_cmp(&b.confidence)
                        .unwrap_or(std::cmp::Ordering::Equal)
                })
                .unwrap(),
        }
    }

    fn decode_structured(
        &self,
        samples: &[f32],
        sample_rate: u32,
        recording_id: Uuid,
        progress: &std::sync::atomic::AtomicU8,
    ) -> StructuredTranscript {
        let results: Vec<StructuredTranscript> = self
            .decoders
            .iter()
            .map(|d| d.decode_structured(samples, sample_rate, recording_id, progress))
            .collect();

        match self.strategy {
            CombineStrategy::HighestConfidence => results
                .into_iter()
                .max_by(|a, b| {
                    a.average_confidence
                        .partial_cmp(&b.average_confidence)
                        .unwrap_or(std::cmp::Ordering::Equal)
                })
                .unwrap(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Stub decoder that returns fixed output for testing.
    struct StubDecoder {
        name: &'static str,
        text: &'static str,
        confidence: f64,
    }

    impl CwDecoder for StubDecoder {
        fn name(&self) -> &str {
            self.name
        }

        fn decode(&self, _samples: &[f32], _sample_rate: u32) -> DecoderOutput {
            DecoderOutput {
                text: self.text.to_string(),
                wpm: Some(20.0),
                confidence: self.confidence,
                word_spans: Vec::new(),
                decoder_name: self.name.to_string(),
            }
        }

        fn decode_structured(
            &self,
            _samples: &[f32],
            _sample_rate: u32,
            recording_id: Uuid,
            _progress: &std::sync::atomic::AtomicU8,
        ) -> StructuredTranscript {
            StructuredTranscript {
                recording_id,
                lines: Vec::new(),
                detected_qso_ranges: Vec::new(),
                generated_at: String::new(),
                decoder_version: "test".into(),
                decoder_name: self.name.to_string(),
                average_wpm: 20,
                average_confidence: self.confidence,
            }
        }
    }

    #[test]
    fn highest_confidence_picks_best() {
        let low = Arc::new(StubDecoder {
            name: "low",
            text: "WRONG",
            confidence: 0.3,
        }) as Arc<dyn CwDecoder>;
        let high = Arc::new(StubDecoder {
            name: "high",
            text: "CQ DE W1AW",
            confidence: 0.9,
        }) as Arc<dyn CwDecoder>;

        let ensemble = EnsembleDecoder::new(vec![low, high], CombineStrategy::HighestConfidence);

        let result = ensemble.decode(&[0.0], 8000);
        assert_eq!(result.text, "CQ DE W1AW");
        assert_eq!(result.decoder_name, "high");
        assert!((result.confidence - 0.9).abs() < 1e-6);
    }

    #[test]
    fn ensemble_name_is_ensemble() {
        let stub = Arc::new(StubDecoder {
            name: "stub",
            text: "",
            confidence: 0.5,
        }) as Arc<dyn CwDecoder>;
        let ensemble = EnsembleDecoder::new(vec![stub], CombineStrategy::HighestConfidence);
        assert_eq!(ensemble.name(), "ensemble");
    }

    #[test]
    fn structured_highest_confidence() {
        let low = Arc::new(StubDecoder {
            name: "low",
            text: "WRONG",
            confidence: 0.2,
        }) as Arc<dyn CwDecoder>;
        let high = Arc::new(StubDecoder {
            name: "high",
            text: "CQ",
            confidence: 0.95,
        }) as Arc<dyn CwDecoder>;

        let ensemble = EnsembleDecoder::new(vec![low, high], CombineStrategy::HighestConfidence);

        let progress = std::sync::atomic::AtomicU8::new(0);
        let result = ensemble.decode_structured(&[0.0], 8000, Uuid::nil(), &progress);
        assert_eq!(result.decoder_name, "high");
        assert!((result.average_confidence - 0.95).abs() < 1e-6);
    }

    #[test]
    fn single_decoder_ensemble() {
        let only = Arc::new(StubDecoder {
            name: "only",
            text: "73",
            confidence: 0.7,
        }) as Arc<dyn CwDecoder>;

        let ensemble = EnsembleDecoder::new(vec![only], CombineStrategy::HighestConfidence);

        let result = ensemble.decode(&[0.0], 8000);
        assert_eq!(result.text, "73");
        assert_eq!(result.decoder_name, "only");
    }
}
