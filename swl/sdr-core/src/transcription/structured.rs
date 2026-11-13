//! Structured transcript types matching the iOS `SDRRecordingTranscript` Codable model.
//!
//! All types use `#[serde(rename_all = "camelCase")]` to match Swift Codable defaults.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::beam::is_callsign_pattern;

/// Top-level structured transcript.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StructuredTranscript {
    pub recording_id: Uuid,
    pub lines: Vec<TranscriptLine>,
    #[serde(rename = "detectedQSORanges")]
    pub detected_qso_ranges: Vec<DetectedQSORange>,
    /// ISO 8601 timestamp.
    pub generated_at: String,
    pub decoder_version: String,
    /// Name of the decoder that produced this transcript (e.g., "legacy", "decoder-a").
    #[serde(default)]
    pub decoder_name: String,
    #[serde(rename = "averageWPM")]
    pub average_wpm: u32,
    pub average_confidence: f64,
}

/// A line of transcript text (typically one tone segment).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptLine {
    pub id: Uuid,
    pub start_offset: f64,
    pub end_offset: f64,
    pub words: Vec<TranscriptWord>,
    pub speaker_callsign: Option<String>,
    /// Frequency-based operator index (0, 1, 2, ...) for distinguishing transmitters.
    /// Lines with the same operator_id come from the same tone frequency.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub operator_id: Option<u32>,
    /// Detected tone frequency in Hz for this line's operator.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tone_freq_hz: Option<f32>,
}

/// A single decoded word with timing.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptWord {
    pub id: Uuid,
    pub start_offset: f64,
    pub end_offset: f64,
    pub text: String,
    pub is_callsign: bool,
    pub confidence: f64,
}

/// A detected QSO range (conversation with a specific callsign).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DetectedQSORange {
    pub callsign: String,
    pub start_offset: f64,
    pub end_offset: f64,
    #[serde(rename = "loggedQSOId")]
    pub logged_qso_id: Option<Uuid>,
}

/// Detect QSO ranges from transcript lines by scanning for CQ/DE/73/SK patterns.
///
/// A QSO is opened when "DE {callsign}" is found and closed when "73" or "SK"
/// is encountered (or the transcript ends).
pub fn detect_qso_ranges(lines: &[TranscriptLine]) -> Vec<DetectedQSORange> {
    let mut ranges = Vec::new();
    let mut current_callsign: Option<String> = None;
    let mut current_start: f64 = 0.0;
    let mut current_end: f64 = 0.0;

    for line in lines {
        let words: Vec<&str> = line.words.iter().map(|w| w.text.as_str()).collect();

        for (i, &word) in words.iter().enumerate() {
            let upper = word.to_uppercase();

            // Look for "DE {callsign}"
            if upper == "DE" {
                if let Some(next) = words.get(i + 1) {
                    let next_upper = next.to_uppercase();
                    if is_callsign_pattern(&next_upper) {
                        // Close previous QSO if open
                        if let Some(cs) = current_callsign.take() {
                            ranges.push(DetectedQSORange {
                                callsign: cs,
                                start_offset: current_start,
                                end_offset: current_end,
                                logged_qso_id: None,
                            });
                        }
                        // Open new QSO
                        current_callsign = Some(next_upper);
                        current_start = line.start_offset;
                    }
                }
            }

            // Close QSO on 73 or SK
            if (upper == "73" || upper == "SK") && current_callsign.is_some() {
                if let Some(cs) = current_callsign.take() {
                    ranges.push(DetectedQSORange {
                        callsign: cs,
                        start_offset: current_start,
                        end_offset: line.end_offset,
                        logged_qso_id: None,
                    });
                }
            }
        }

        if current_callsign.is_some() {
            current_end = line.end_offset;
        }
    }

    // Close any open QSO at end of transcript
    if let Some(cs) = current_callsign.take() {
        ranges.push(DetectedQSORange {
            callsign: cs,
            start_offset: current_start,
            end_offset: current_end,
            logged_qso_id: None,
        });
    }

    ranges
}

/// Detect speaker callsign from a line's words by looking for "DE {callsign}" pattern.
pub fn detect_speaker(words: &[TranscriptWord]) -> Option<String> {
    for (i, word) in words.iter().enumerate() {
        if word.text.to_uppercase() == "DE" {
            if let Some(next) = words.get(i + 1) {
                let upper = next.text.to_uppercase();
                if is_callsign_pattern(&upper) {
                    return Some(upper);
                }
            }
        }
    }
    None
}

/// Known CW prosigns and short noise words that appear when decoding random noise.
/// Noise fragments that never appear in real CW.
///
/// IMPORTANT: Do NOT include real CW words here. AR (end of message),
/// ES (and), EN (common exchange), AN, HI (laughter) are legitimate.
/// Only include 2-letter combos that are pure single-element Morse noise.
const NOISE_WORDS: &[&str] = &[
    "EE", "ET", "TE", "TT", "EI", "IE", "IT", "TI", "II", "AE", "EA", "AI", "IA", "AA", "NN",
];

/// Returns true if a line looks like decoded noise rather than real CW content.
///
/// A line is noise if ALL its words are known noise fragments and none look
/// like a callsign. Works for any line length, even 1-2 word lines.
pub fn is_noise_line(words: &[TranscriptWord]) -> bool {
    if words.is_empty() {
        return true;
    }

    let has_callsign = words.iter().any(|w| {
        let upper = w.text.to_uppercase();
        is_callsign_pattern(&upper)
    });
    if has_callsign {
        return false;
    }

    words.iter().all(|w| {
        let upper = w.text.to_uppercase();
        NOISE_WORDS.contains(&upper.as_str())
    })
}

/// Filter out noise lines from a transcript.
///
/// Removes lines that are likely decoded noise (repetitive short prosigns)
/// rather than real CW transmissions.
pub fn filter_noise_lines(lines: Vec<TranscriptLine>) -> Vec<TranscriptLine> {
    let before = lines.len();
    let filtered: Vec<TranscriptLine> = lines
        .into_iter()
        .filter(|line| !is_noise_line(&line.words))
        .collect();
    let removed = before - filtered.len();
    if removed > 0 {
        tracing::debug!(
            before,
            after = filtered.len(),
            removed,
            "Filtered noise lines"
        );
    }
    filtered
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_word(text: &str, start: f64, end: f64) -> TranscriptWord {
        TranscriptWord {
            id: Uuid::new_v4(),
            start_offset: start,
            end_offset: end,
            text: text.to_string(),
            is_callsign: is_callsign_pattern(&text.to_uppercase()),
            confidence: 0.9,
        }
    }

    fn make_line(words: Vec<TranscriptWord>) -> TranscriptLine {
        let start = words.first().map(|w| w.start_offset).unwrap_or(0.0);
        let end = words.last().map(|w| w.end_offset).unwrap_or(0.0);
        TranscriptLine {
            id: Uuid::new_v4(),
            start_offset: start,
            end_offset: end,
            words,
            speaker_callsign: None,
            operator_id: None,
            tone_freq_hz: None,
        }
    }

    #[test]
    fn detect_qso_cq_de_73() {
        let lines = vec![
            make_line(vec![
                make_word("CQ", 0.0, 0.5),
                make_word("CQ", 0.6, 1.0),
                make_word("DE", 1.1, 1.5),
                make_word("W1AW", 1.6, 2.5),
            ]),
            make_line(vec![
                make_word("RST", 3.0, 3.5),
                make_word("599", 3.6, 4.0),
                make_word("73", 4.1, 4.5),
            ]),
        ];

        let ranges = detect_qso_ranges(&lines);
        assert_eq!(ranges.len(), 1);
        assert_eq!(ranges[0].callsign, "W1AW");
        assert!((ranges[0].start_offset - 0.0).abs() < 0.01);
        assert!((ranges[0].end_offset - 4.5).abs() < 0.01);
    }

    #[test]
    fn detect_qso_multiple_stations() {
        let lines = vec![
            make_line(vec![
                make_word("DE", 0.0, 0.3),
                make_word("K1ABC", 0.4, 1.0),
            ]),
            make_line(vec![make_word("73", 2.0, 2.5)]),
            make_line(vec![make_word("DE", 3.0, 3.3), make_word("N7XY", 3.4, 4.0)]),
        ];

        let ranges = detect_qso_ranges(&lines);
        assert_eq!(ranges.len(), 2);
        assert_eq!(ranges[0].callsign, "K1ABC");
        assert_eq!(ranges[1].callsign, "N7XY");
    }

    #[test]
    fn detect_qso_unclosed_at_end() {
        let lines = vec![make_line(vec![
            make_word("DE", 0.0, 0.3),
            make_word("W9ABC", 0.4, 1.0),
            make_word("RST", 1.5, 2.0),
        ])];

        let ranges = detect_qso_ranges(&lines);
        assert_eq!(ranges.len(), 1);
        assert_eq!(ranges[0].callsign, "W9ABC");
    }

    #[test]
    fn detect_speaker_finds_callsign() {
        let words = vec![
            make_word("CQ", 0.0, 0.5),
            make_word("DE", 0.6, 1.0),
            make_word("WA9AGG", 1.1, 2.0),
        ];
        assert_eq!(detect_speaker(&words), Some("WA9AGG".into()));
    }

    #[test]
    fn detect_speaker_no_callsign() {
        let words = vec![make_word("CQ", 0.0, 0.5), make_word("CQ", 0.6, 1.0)];
        assert_eq!(detect_speaker(&words), None);
    }

    #[test]
    fn camel_case_serialization() {
        let transcript = StructuredTranscript {
            recording_id: Uuid::nil(),
            lines: vec![],
            detected_qso_ranges: vec![],
            generated_at: "2026-02-21T00:00:00Z".into(),
            decoder_version: "0.1.0".into(),
            decoder_name: "legacy".into(),
            average_wpm: 15,
            average_confidence: 0.85,
        };

        let json = serde_json::to_string(&transcript).unwrap();
        assert!(json.contains("recordingId"));
        assert!(json.contains("detectedQSORanges"));
        assert!(json.contains("generatedAt"));
        assert!(json.contains("decoderVersion"));
        assert!(json.contains("averageWPM"));
        assert!(json.contains("averageConfidence"));
        // Must NOT contain snake_case
        assert!(!json.contains("recording_id"));
        assert!(!json.contains("detected_qso_ranges"));
        // Must use uppercase acronyms
        assert!(!json.contains("averageWpm"));
        assert!(!json.contains("detectedQsoRanges"));
        // operator_id and tone_freq_hz should be absent when None
        assert!(!json.contains("operatorId"));
        assert!(!json.contains("toneFreqHz"));
    }

    #[test]
    fn operator_id_serialized_when_present() {
        let line = TranscriptLine {
            id: Uuid::nil(),
            start_offset: 0.0,
            end_offset: 1.0,
            words: vec![],
            speaker_callsign: None,
            operator_id: Some(1),
            tone_freq_hz: Some(650.0),
        };
        let json = serde_json::to_string(&line).unwrap();
        assert!(json.contains("operatorId"));
        assert!(json.contains("toneFreqHz"));
    }

    #[test]
    fn noise_line_repetitive_noise() {
        let words: Vec<TranscriptWord> = [
            "EE", "TE", "TT", "EI", "IE", "EE", "TE", "TT", "EI", "EE", "TE",
        ]
        .iter()
        .enumerate()
        .map(|(i, &text)| make_word(text, i as f64 * 0.3, i as f64 * 0.3 + 0.2))
        .collect();
        assert!(is_noise_line(&words));
    }

    #[test]
    fn noise_line_with_callsign_not_filtered() {
        let words = vec![
            make_word("HI", 0.0, 0.2),
            make_word("HI", 0.3, 0.5),
            make_word("HI", 0.6, 0.8),
            make_word("W1AW", 0.9, 1.5),
        ];
        assert!(!is_noise_line(&words));
    }

    #[test]
    fn noise_line_real_cw_not_filtered() {
        let words = vec![
            make_word("CQ", 0.0, 0.5),
            make_word("CQ", 0.6, 1.0),
            make_word("DE", 1.1, 1.5),
            make_word("W6JSV", 1.6, 2.5),
        ];
        assert!(!is_noise_line(&words));
    }

    #[test]
    fn noise_line_short_all_noise_filtered() {
        let words = vec![make_word("EE", 0.0, 0.2), make_word("TT", 0.3, 0.5)];
        assert!(is_noise_line(&words));
    }

    #[test]
    fn noise_line_single_real_word_not_filtered() {
        let words = vec![make_word("CQ", 0.0, 0.5)];
        assert!(!is_noise_line(&words));
    }

    #[test]
    fn filter_noise_lines_removes_noise() {
        let noise = make_line(
            ["EE", "TE", "TT", "EI", "IE", "EE"]
                .iter()
                .enumerate()
                .map(|(i, &t)| make_word(t, i as f64, i as f64 + 0.5))
                .collect(),
        );
        let real = make_line(vec![
            make_word("CQ", 10.0, 10.5),
            make_word("DE", 10.6, 11.0),
            make_word("W1AW", 11.1, 12.0),
        ]);
        let lines = vec![noise, real];
        let filtered = filter_noise_lines(lines);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].words.last().unwrap().text, "W1AW");
    }
}
