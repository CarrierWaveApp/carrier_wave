use super::morse;
use super::tone_detector::{KeyingEvent, KeyingEventKind};

/// A decoded character with its morse pattern and position in the audio.
#[derive(Debug, Clone)]
pub struct DecodedChar {
    pub character: char,
    pub pattern: String,
    pub sample_offset: usize,
}

/// Morse decoder that converts keying events into characters.
///
/// Ported from CWDecoder.swift. Uses adaptive WPM estimation based on
/// recent dit durations, with timing thresholds for dit/dah classification
/// and gap detection.
pub struct MorseDecoder {
    /// Current estimated WPM.
    estimated_wpm: u32,
    /// Audio sample rate (for duration calculations).
    sample_rate: u32,
    /// Whether to adapt WPM from incoming events.
    adaptive: bool,

    /// Current morse pattern being built (e.g. ".-").
    current_pattern: String,
    /// Sample offset where the current pattern started.
    pattern_start_offset: usize,

    /// Sample offset of the last key-on event.
    key_on_offset: Option<usize>,
    /// Sample offset of the last key-off event.
    key_off_offset: Option<usize>,

    /// Whether we're waiting to check for a word gap after decoding a character.
    pending_word_space: bool,

    /// Recent dit durations (in seconds) for adaptive timing.
    recent_dit_durations: Vec<f64>,
    /// Maximum number of timing samples to keep.
    max_timing_samples: usize,

    /// Minimum tone duration in seconds to filter noise.
    min_tone_secs: f64,
    /// Minimum gap duration in seconds to filter noise.
    min_gap_secs: f64,

    /// Custom character gap threshold (seconds), overrides the WPM-derived value.
    custom_char_gap: Option<f64>,
    /// Custom word gap threshold (seconds), overrides the WPM-derived value.
    custom_word_gap: Option<f64>,

    /// Whether the decoder is buffering initial events for startup estimation.
    buffering: bool,
    /// Target number of on-events to buffer before estimating WPM/gaps.
    buffer_target: usize,
    /// Buffered events collected during startup.
    event_buffer: Vec<KeyingEvent>,
    /// Count of on-events in the buffer.
    buffer_on_count: usize,
}

impl MorseDecoder {
    /// Create a new decoder with the given initial WPM and sample rate.
    /// WPM will adapt from incoming events.
    pub fn new(initial_wpm: u32, sample_rate: u32) -> Self {
        Self {
            estimated_wpm: initial_wpm.clamp(5, 50),
            sample_rate,
            adaptive: true,
            current_pattern: String::new(),
            pattern_start_offset: 0,
            key_on_offset: None,
            key_off_offset: None,
            pending_word_space: false,
            recent_dit_durations: Vec::new(),
            max_timing_samples: 10,
            min_tone_secs: 0.025,
            min_gap_secs: 0.020,
            custom_char_gap: None,
            custom_word_gap: None,
            buffering: false,
            buffer_target: 0,
            event_buffer: Vec::new(),
            buffer_on_count: 0,
        }
    }

    /// Create a new decoder with fixed WPM (no adaptation).
    /// Use when WPM has been pre-estimated from the event distribution.
    pub fn new_fixed(wpm: u32, sample_rate: u32) -> Self {
        Self {
            estimated_wpm: wpm.clamp(5, 50),
            sample_rate,
            adaptive: false,
            current_pattern: String::new(),
            pattern_start_offset: 0,
            key_on_offset: None,
            key_off_offset: None,
            pending_word_space: false,
            recent_dit_durations: Vec::new(),
            max_timing_samples: 10,
            min_tone_secs: 0.025,
            min_gap_secs: 0.020,
            custom_char_gap: None,
            custom_word_gap: None,
            buffering: false,
            buffer_target: 0,
            event_buffer: Vec::new(),
            buffer_on_count: 0,
        }
    }

    /// Create a new decoder with fixed WPM and custom gap thresholds.
    /// Use when gap thresholds have been estimated from the off-duration histogram.
    pub fn new_fixed_with_gaps(
        wpm: u32,
        sample_rate: u32,
        char_gap_secs: f64,
        word_gap_secs: f64,
    ) -> Self {
        Self {
            estimated_wpm: wpm.clamp(5, 50),
            sample_rate,
            adaptive: false,
            current_pattern: String::new(),
            pattern_start_offset: 0,
            key_on_offset: None,
            key_off_offset: None,
            pending_word_space: false,
            recent_dit_durations: Vec::new(),
            max_timing_samples: 10,
            min_tone_secs: 0.025,
            min_gap_secs: 0.020,
            custom_char_gap: Some(char_gap_secs),
            custom_word_gap: Some(word_gap_secs),
            buffering: false,
            buffer_target: 0,
            event_buffer: Vec::new(),
            buffer_on_count: 0,
        }
    }

    /// Create a buffered decoder that collects the first `buffer_target` on-events,
    /// estimates WPM and gap thresholds from them, then retroactively decodes the
    /// buffer before continuing with normal fixed-mode decoding.
    ///
    /// This produces more accurate startup decoding since it has a full
    /// sample of timing information before making any classification decisions.
    pub fn new_buffered(buffer_target: usize, sample_rate: u32) -> Self {
        Self {
            estimated_wpm: 15, // placeholder until buffer fills
            sample_rate,
            adaptive: false,
            current_pattern: String::new(),
            pattern_start_offset: 0,
            key_on_offset: None,
            key_off_offset: None,
            pending_word_space: false,
            recent_dit_durations: Vec::new(),
            max_timing_samples: 10,
            min_tone_secs: 0.025,
            min_gap_secs: 0.020,
            custom_char_gap: None,
            custom_word_gap: None,
            buffering: true,
            buffer_target,
            event_buffer: Vec::with_capacity(buffer_target * 3),
            buffer_on_count: 0,
        }
    }

    /// Process a single keying event, returning any decoded characters.
    pub fn process_event(&mut self, event: KeyingEvent) -> Vec<DecodedChar> {
        if self.buffering {
            if event.kind == KeyingEventKind::On {
                self.buffer_on_count += 1;
            }
            self.event_buffer.push(event);

            if self.buffer_on_count >= self.buffer_target {
                return self.flush_buffer();
            }
            return Vec::new();
        }

        match event.kind {
            KeyingEventKind::On => self.handle_key_on(event.sample_offset),
            KeyingEventKind::Off => self.handle_key_off(event.sample_offset),
        }
    }

    /// Finalize decoding, flushing any pending pattern.
    pub fn finalize(&mut self) -> Vec<DecodedChar> {
        // If still buffering (fewer events than target), flush now
        if self.buffering {
            let mut result = self.flush_buffer();
            // After flushing, finalize the pattern
            if !self.current_pattern.is_empty() {
                let pattern = std::mem::take(&mut self.current_pattern);
                let offset = self.pattern_start_offset;
                result.extend(Self::decode_or_split(&pattern, offset, "finalize"));
            }
            return result;
        }

        if self.current_pattern.is_empty() {
            tracing::debug!("Finalize: no pending pattern");
            return Vec::new();
        }

        let pattern = std::mem::take(&mut self.current_pattern);
        let offset = self.pattern_start_offset;
        Self::decode_or_split(&pattern, offset, "finalize")
    }

    /// Flush the startup buffer: estimate WPM and gaps from buffered events,
    /// then replay all buffered events through normal decode.
    fn flush_buffer(&mut self) -> Vec<DecodedChar> {
        use super::{estimate_gap_thresholds, estimate_wpm_histogram};

        self.buffering = false;
        let events = std::mem::take(&mut self.event_buffer);

        if events.is_empty() {
            return Vec::new();
        }

        // Extract on-durations from buffer
        let mut on_ms = Vec::new();
        let mut off_ms = Vec::new();
        let evts: Vec<_> = events.iter().collect();
        for i in 0..evts.len().saturating_sub(1) {
            let dur = (evts[i + 1].sample_offset as f64 - evts[i].sample_offset as f64)
                / self.sample_rate as f64
                * 1000.0;
            match evts[i].kind {
                KeyingEventKind::On => on_ms.push(dur),
                KeyingEventKind::Off => off_ms.push(dur),
            }
        }

        // Estimate WPM from buffer
        let (wpm, dit_ms) = estimate_wpm_histogram(&on_ms);
        self.estimated_wpm = wpm;

        // Estimate gap thresholds from buffer
        let (char_gap_ms, word_gap_ms) = estimate_gap_thresholds(&off_ms, dit_ms);
        self.custom_char_gap = Some(char_gap_ms / 1000.0);
        self.custom_word_gap = Some(word_gap_ms / 1000.0);

        tracing::info!(
            buffer_events = events.len(),
            estimated_wpm = wpm,
            dit_ms = format!("{:.0}", dit_ms),
            char_gap_ms = format!("{:.0}", char_gap_ms),
            word_gap_ms = format!("{:.0}", word_gap_ms),
            "Buffered startup: estimated parameters, replaying"
        );

        // Replay all buffered events through normal decode
        let mut result = Vec::new();
        for event in events {
            match event.kind {
                KeyingEventKind::On => result.extend(self.handle_key_on(event.sample_offset)),
                KeyingEventKind::Off => result.extend(self.handle_key_off(event.sample_offset)),
            }
        }
        result
    }

    /// Get the current estimated WPM.
    pub fn estimated_wpm(&self) -> u32 {
        self.estimated_wpm
    }

    /// Try to decode a pattern as a single character, falling back to
    /// splitting it into multiple characters if unrecognized.
    fn decode_or_split(pattern: &str, offset: usize, context: &str) -> Vec<DecodedChar> {
        if let Some(ch) = morse::decode_pattern(pattern) {
            #[cfg(test)]
            if std::env::var("CW_DEBUG_PATTERNS").is_ok() {
                eprintln!("  [{}] '{}' → {}", context, pattern, ch);
            }
            vec![DecodedChar {
                character: ch,
                pattern: pattern.to_string(),
                sample_offset: offset,
            }]
        } else if let Some(chars) = morse::split_pattern(pattern) {
            let split_str: String = chars.iter().collect();
            #[cfg(test)]
            if std::env::var("CW_DEBUG_PATTERNS").is_ok() {
                eprintln!("  [{}] '{}' → SPLIT: {}", context, pattern, split_str);
            }
            tracing::debug!(
                pattern = %pattern,
                split = %split_str,
                count = chars.len(),
                context,
                "Split unrecognized pattern"
            );
            chars
                .into_iter()
                .map(|ch| DecodedChar {
                    character: ch,
                    pattern: String::new(), // individual patterns not tracked for splits
                    sample_offset: offset,
                })
                .collect()
        } else {
            tracing::debug!(pattern = %pattern, context, "Unrecognized pattern (no split found)");
            Vec::new()
        }
    }

    // --- Timing calculations ---

    /// Dit duration in seconds at current WPM.
    fn dit_duration(&self) -> f64 {
        1.2 / self.estimated_wpm as f64
    }

    /// Threshold between dit and dah (2x dit).
    fn dit_dah_threshold(&self) -> f64 {
        self.dit_duration() * 2.0
    }

    /// Threshold for character gap.
    ///
    /// Uses custom threshold from histogram analysis when available,
    /// otherwise falls back to 1.5x dit (compressed from standard 3x dit
    /// for noisy multi-receiver combines).
    fn char_gap_threshold(&self) -> f64 {
        self.custom_char_gap.unwrap_or(self.dit_duration() * 1.5)
    }

    /// Threshold for word gap.
    ///
    /// Uses custom threshold from histogram analysis when available,
    /// otherwise falls back to 3.5x dit (compressed from standard 7x dit
    /// for noisy audio).
    fn word_gap_threshold(&self) -> f64 {
        self.custom_word_gap.unwrap_or(self.dit_duration() * 3.5)
    }

    /// Convert sample count to seconds.
    fn samples_to_secs(&self, samples: usize) -> f64 {
        samples as f64 / self.sample_rate as f64
    }

    // --- Event handlers ---

    fn handle_key_on(&mut self, offset: usize) -> Vec<DecodedChar> {
        let mut result = Vec::new();

        // Check gap since last key off
        if let Some(last_off) = self.key_off_offset {
            let gap_secs = self.samples_to_secs(offset.saturating_sub(last_off));

            if gap_secs >= self.min_gap_secs {
                // Word gap: finalize current pattern and add space
                if gap_secs >= self.word_gap_threshold() {
                    if !self.current_pattern.is_empty() {
                        let pattern = std::mem::take(&mut self.current_pattern);
                        let pat_offset = self.pattern_start_offset;
                        result.extend(Self::decode_or_split(&pattern, pat_offset, "word gap"));
                    }
                    // Emit word space
                    result.push(DecodedChar {
                        character: ' ',
                        pattern: String::new(),
                        sample_offset: offset,
                    });
                    self.pending_word_space = false;
                }
                // Character gap: finalize current pattern
                else if gap_secs >= self.char_gap_threshold() && !self.current_pattern.is_empty()
                {
                    let pattern = std::mem::take(&mut self.current_pattern);
                    let pat_offset = self.pattern_start_offset;
                    let decoded = Self::decode_or_split(&pattern, pat_offset, "char gap");
                    if !decoded.is_empty() {
                        self.pending_word_space = true;
                    }
                    result.extend(decoded);
                }
            }
        }

        self.key_on_offset = Some(offset);
        result
    }

    fn handle_key_off(&mut self, offset: usize) -> Vec<DecodedChar> {
        let on_offset = match self.key_on_offset {
            Some(o) => o,
            None => {
                self.key_off_offset = Some(offset);
                return Vec::new();
            }
        };

        let duration_secs = self.samples_to_secs(offset.saturating_sub(on_offset));
        self.key_off_offset = Some(offset);

        // Filter noise
        if duration_secs < self.min_tone_secs {
            tracing::trace!(
                dur_ms = format!("{:.1}", duration_secs * 1000.0),
                "Filtered noise tone"
            );
            return Vec::new();
        }

        // Classify as dit or dah
        let element = if duration_secs < self.dit_dah_threshold() {
            '.'
        } else {
            '-'
        };
        tracing::trace!(
            dur_ms = format!("{:.1}", duration_secs * 1000.0),
            element = %element,
            threshold_ms = format!("{:.1}", self.dit_dah_threshold() * 1000.0),
            wpm = self.estimated_wpm,
            "Classified element"
        );

        // Start new pattern if empty
        if self.current_pattern.is_empty() {
            self.pattern_start_offset = on_offset;
        }
        self.current_pattern.push(element);

        // Update timing estimate
        self.update_timing(duration_secs, element);

        Vec::new()
    }

    fn update_timing(&mut self, duration_secs: f64, element: char) {
        if !self.adaptive {
            return;
        }

        if element == '.' {
            self.recent_dit_durations.push(duration_secs);
            if self.recent_dit_durations.len() > self.max_timing_samples {
                self.recent_dit_durations.remove(0);
            }
        }

        // Estimate WPM from median dit duration
        if self.recent_dit_durations.len() >= 3 {
            let mut sorted = self.recent_dit_durations.clone();
            sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            let median = sorted[sorted.len() / 2];

            let new_wpm = (1.2 / median) as u32;
            let clamped = new_wpm.clamp(5, 50);

            // Smooth the estimate (3:1 ratio with existing)
            self.estimated_wpm = (self.estimated_wpm * 3 + clamped) / 4;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transcription::tone_detector::{KeyingEvent, KeyingEventKind};

    /// Generate keying events for a morse pattern at a given WPM.
    fn pattern_to_events(pattern: &str, wpm: u32, sample_rate: u32) -> Vec<KeyingEvent> {
        let dit_secs = 1.2 / wpm as f64;
        let dit_samples = (dit_secs * sample_rate as f64) as usize;
        let dah_samples = dit_samples * 3;
        let element_gap = dit_samples; // 1 unit gap between elements

        let mut events = Vec::new();
        let mut offset = 0usize;

        for (i, ch) in pattern.chars().enumerate() {
            let tone_len = if ch == '.' { dit_samples } else { dah_samples };

            events.push(KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: offset,
            });
            offset += tone_len;
            events.push(KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: offset,
            });

            // Add element gap (except after last element)
            if i < pattern.len() - 1 {
                offset += element_gap;
            }
        }

        events
    }

    /// Generate keying events for a word (multiple characters) at a given WPM.
    fn word_to_events(word: &str, wpm: u32, sample_rate: u32) -> Vec<KeyingEvent> {
        let dit_secs = 1.2 / wpm as f64;
        let dit_samples = (dit_secs * sample_rate as f64) as usize;
        let char_gap = dit_samples * 3;

        let mut events = Vec::new();
        let mut offset = 0usize;

        for (ci, ch) in word.chars().enumerate() {
            let pattern = morse::encode_char(ch).unwrap();

            for (i, elem) in pattern.chars().enumerate() {
                let tone_len = if elem == '.' {
                    dit_samples
                } else {
                    dit_samples * 3
                };

                events.push(KeyingEvent {
                    kind: KeyingEventKind::On,
                    sample_offset: offset,
                });
                offset += tone_len;
                events.push(KeyingEvent {
                    kind: KeyingEventKind::Off,
                    sample_offset: offset,
                });

                // Element gap within character
                if i < pattern.len() - 1 {
                    offset += dit_samples;
                }
            }

            // Character gap between characters
            if ci < word.len() - 1 {
                offset += char_gap;
            }
        }

        events
    }

    #[test]
    fn decode_single_letter_e() {
        let sr = 12_000;
        let wpm = 15;
        let events = pattern_to_events(".", wpm, sr);

        let mut decoder = MorseDecoder::new(wpm, sr);
        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        assert!(!decoded.is_empty(), "should decode at least one character");
        assert_eq!(decoded[0].character, 'E');
    }

    #[test]
    fn decode_single_letter_t() {
        let sr = 12_000;
        let wpm = 15;
        let events = pattern_to_events("-", wpm, sr);

        let mut decoder = MorseDecoder::new(wpm, sr);
        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        assert!(!decoded.is_empty(), "should decode at least one character");
        assert_eq!(decoded[0].character, 'T');
    }

    #[test]
    fn decode_sos() {
        let sr = 12_000;
        let wpm = 15;
        let events = word_to_events("SOS", wpm, sr);

        let mut decoder = MorseDecoder::new(wpm, sr);
        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        let text: String = decoded.iter().map(|d| d.character).collect();
        assert_eq!(text, "SOS", "expected SOS, got {text}");
    }

    #[test]
    fn decode_cq() {
        let sr = 12_000;
        let wpm = 15;
        let events = word_to_events("CQ", wpm, sr);

        let mut decoder = MorseDecoder::new(wpm, sr);
        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        let text: String = decoded.iter().map(|d| d.character).collect();
        assert_eq!(text, "CQ", "expected CQ, got {text}");
    }

    #[test]
    fn decode_word_with_space() {
        let sr = 12_000;
        let wpm = 15;
        let dit_secs = 1.2 / wpm as f64;
        let dit_samples = (dit_secs * sr as f64) as usize;
        let word_gap = dit_samples * 7;

        let mut events = word_to_events("HI", wpm, sr);
        // Add word gap
        let last_offset = events.last().unwrap().sample_offset + word_gap;
        // Add another word
        let mut events2 = word_to_events("HI", wpm, sr);
        for e in &mut events2 {
            e.sample_offset += last_offset;
        }
        events.extend(events2);

        let mut decoder = MorseDecoder::new(wpm, sr);
        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        let text: String = decoded.iter().map(|d| d.character).collect();
        assert_eq!(text, "HI HI", "expected 'HI HI', got '{text}'");
    }

    #[test]
    fn noise_filtered() {
        let sr = 12_000;
        let wpm = 15;
        let mut decoder = MorseDecoder::new(wpm, sr);

        // Very short tone (1ms) should be filtered as noise
        let events = vec![
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: 0,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 12, // 1ms at 12kHz
            },
        ];

        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        assert!(decoded.is_empty(), "noise should be filtered");
    }

    #[test]
    fn wpm_adapts() {
        let sr = 12_000;
        let target_wpm: u32 = 20;

        // Generate many dits at 20 WPM so the decoder can adapt
        let dit_secs = 1.2 / target_wpm as f64;
        let dit_samples = (dit_secs * sr as f64) as usize;
        let gap_samples = dit_samples; // element gap

        let mut decoder = MorseDecoder::new(15, sr); // start at 15

        let mut offset = 0usize;
        for _ in 0..20 {
            let events = vec![
                KeyingEvent {
                    kind: KeyingEventKind::On,
                    sample_offset: offset,
                },
                KeyingEvent {
                    kind: KeyingEventKind::Off,
                    sample_offset: offset + dit_samples,
                },
            ];
            for event in events {
                decoder.process_event(event);
            }
            offset += dit_samples + gap_samples;
        }

        // WPM should have adapted toward 20
        let wpm = decoder.estimated_wpm();
        assert!(wpm >= 17 && wpm <= 23, "expected WPM near 20, got {wpm}");
    }

    #[test]
    fn buffered_decodes_cq() {
        let sr = 12_000;
        let wpm = 20;

        // Generate "CQ POTA DE N4T" — enough events for the buffer
        let dit_secs = 1.2 / wpm as f64;
        let dit_samples = (dit_secs * sr as f64) as usize;
        let char_gap = dit_samples * 3;
        let word_gap = dit_samples * 7;

        let mut events = Vec::new();
        let mut offset = 0usize;
        let words = ["CQ", "POTA", "DE", "N4T"];
        for (wi, word) in words.iter().enumerate() {
            for (ci, ch) in word.chars().enumerate() {
                if let Some(pattern) = morse::encode_char(ch) {
                    for (i, elem) in pattern.chars().enumerate() {
                        let tone_len = if elem == '.' {
                            dit_samples
                        } else {
                            dit_samples * 3
                        };
                        events.push(KeyingEvent {
                            kind: KeyingEventKind::On,
                            sample_offset: offset,
                        });
                        offset += tone_len;
                        events.push(KeyingEvent {
                            kind: KeyingEventKind::Off,
                            sample_offset: offset,
                        });
                        if i < pattern.len() - 1 {
                            offset += dit_samples;
                        }
                    }
                }
                if ci < word.len() - 1 {
                    offset += char_gap;
                }
            }
            if wi < words.len() - 1 {
                offset += word_gap;
            }
        }

        let mut decoder = MorseDecoder::new_buffered(40, sr);
        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        let text: String = decoded.iter().map(|d| d.character).collect();
        // Should decode at least "CQ" from the start
        assert!(
            text.contains("CQ"),
            "buffered decoder should decode CQ, got '{text}'"
        );
    }

    #[test]
    fn buffered_decodes_few_events() {
        let sr = 12_000;
        let wpm = 15;

        // Only generate "SOS" — fewer than 40 on-events, should still decode
        let events = word_to_events("SOS", wpm, sr);

        let mut decoder = MorseDecoder::new_buffered(40, sr);
        let mut decoded = Vec::new();
        for event in events {
            decoded.extend(decoder.process_event(event));
        }
        decoded.extend(decoder.finalize());

        let text: String = decoded.iter().map(|d| d.character).collect();
        assert_eq!(text, "SOS", "expected SOS, got '{text}'");
    }
}
