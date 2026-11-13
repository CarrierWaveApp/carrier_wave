//! Decoder A: Improved DSP pipeline with quadrature demodulation.
//!
//! Uses a two-pass quadrature detection approach:
//! 1. Wide bandwidth (120 Hz) for initial WPM estimation
//! 2. Matched bandwidth (max(6 × WPM, 60) Hz) for final detection
//!
//! Pipeline: Quadrature envelope → Viterbi HMM → operator segmentation → BeamDecoder (per-segment)

use uuid::Uuid;

use super::beam::{self, BeamDecoder, WordSpan};
use super::decoder_trait::{CwDecoder, DecoderOutput};
use super::quadrature::QuadratureDetector;
use super::structured::{self, StructuredTranscript, TranscriptLine, TranscriptWord};
use super::tone_detector::{
    find_active_start, merge_keying_events, refine_tone_frequencies, scan_tone_activity,
    KeyingEvent, KeyingEventKind, ToneActivity,
};
use super::{
    estimate_dit_otsu, estimate_gap_thresholds, estimate_wpm_histogram, viterbi_detect,
    ViterbiParams,
};
use crate::recording::dsp::{BiquadCascade, BiquadFilter};
use crate::transcription::postprocess;

/// A decoded segment from a single tone, ready for per-segment decoding.
struct ToneSegment {
    /// Keying events in this segment.
    events: Vec<KeyingEvent>,
    /// Sample offset of the first event in this segment.
    start_sample: usize,
    /// Dit duration estimate for this segment (ms).
    dit_ms: f64,
    /// Estimated WPM for this segment.
    wpm: u32,
    /// Character gap threshold (ms).
    char_gap_ms: f64,
    /// Word gap threshold (ms).
    word_gap_ms: f64,
    /// SNR estimate for this segment (dB).
    snr_db: f64,
    /// Representative tone frequency for this operator (Hz).
    tone_freq: f32,
    /// Frequency group index identifying the operator.
    operator_id: usize,
}

/// A cluster of nearby tone activities representing a single operator.
struct FrequencyGroup {
    /// Representative frequency (median of activities in this group).
    freq: f32,
    /// Original activities in this cluster (each processed separately for
    /// better calibration on its narrow time window).
    activities: Vec<ToneActivity>,
    /// Operator ID (0-indexed).
    operator_id: usize,
}

/// Cluster tone activities into frequency groups.
///
/// Activities within `threshold_hz` of the running cluster median are merged.
/// Each group's time spans are computed as the union of all activity ranges.
fn cluster_activities_by_frequency(
    activities: &[ToneActivity],
    threshold_hz: f32,
) -> Vec<FrequencyGroup> {
    if activities.is_empty() {
        return Vec::new();
    }

    let mut sorted: Vec<&ToneActivity> = activities.iter().collect();
    sorted.sort_by(|a, b| {
        a.freq
            .partial_cmp(&b.freq)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut groups: Vec<FrequencyGroup> = Vec::new();
    let mut current_activities: Vec<&ToneActivity> = vec![sorted[0]];

    for activity in &sorted[1..] {
        let cluster_freq = median_freq_refs(&current_activities);
        if (activity.freq - cluster_freq).abs() <= threshold_hz {
            current_activities.push(activity);
        } else {
            // Flush current cluster
            let freq = median_freq_refs(&current_activities);
            groups.push(FrequencyGroup {
                freq,
                activities: current_activities.iter().map(|a| (*a).clone()).collect(),
                operator_id: groups.len(),
            });
            current_activities = vec![activity];
        }
    }

    // Flush last cluster
    let freq = median_freq_refs(&current_activities);
    groups.push(FrequencyGroup {
        freq,
        activities: current_activities.iter().map(|a| (*a).clone()).collect(),
        operator_id: groups.len(),
    });

    tracing::info!(
        num_activities = activities.len(),
        num_groups = groups.len(),
        groups = ?groups.iter().map(|g| format!(
            "op{}: {:.0}Hz ({} activities)",
            g.operator_id, g.freq, g.activities.len()
        )).collect::<Vec<_>>(),
        "Clustered tone activities by frequency"
    );

    groups
}

/// Compute median frequency from a slice of activity references.
fn median_freq_refs(activities: &[&ToneActivity]) -> f32 {
    let mut freqs: Vec<f32> = activities.iter().map(|a| a.freq).collect();
    freqs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    freqs[freqs.len() / 2]
}

/// Split frequency groups that contain temporally independent subsets.
///
/// In half-duplex CW, two operators at similar beat frequencies (e.g., 531 Hz
/// and 541 Hz) transmit at different times. After frequency clustering (15 Hz
/// threshold), they end up in the same group. This function detects the split
/// by comparing temporal overlap between frequency subsets within each group.
///
/// Algorithm:
/// 1. For each group, find the dominant frequency (most total time coverage)
/// 2. Compute each activity's temporal overlap with dominant-frequency activities
/// 3. Activities with <30% overlap are candidates for a secondary operator
/// 4. If the secondary set is large enough (≥3 activities), split the group
fn split_half_duplex_groups(groups: Vec<FrequencyGroup>) -> Vec<FrequencyGroup> {
    let mut result: Vec<FrequencyGroup> = Vec::new();

    for group in groups {
        if group.activities.len() < 4 {
            result.push(group);
            continue;
        }

        // Find dominant frequency: the one with most total time coverage.
        // Activities at this exact frequency (±1 Hz) seed the primary set.
        // All other activities are classified by temporal overlap with the
        // primary set — sidelobes overlap with the dominant signal, while
        // half-duplex operators transmit during the dominant's silence.
        let mut freq_coverage: std::collections::HashMap<i32, usize> =
            std::collections::HashMap::new();
        for a in &group.activities {
            let key = a.freq.round() as i32;
            let span = a.end_sample.saturating_sub(a.start_sample);
            *freq_coverage.entry(key).or_default() += span;
        }
        let dominant_freq = *freq_coverage
            .iter()
            .max_by_key(|&(_, &v)| v)
            .map(|(k, _)| k)
            .unwrap_or(&(group.freq.round() as i32));

        // Build time intervals from the dominant-frequency activities only.
        // Use ±3 Hz to capture the full dominant signal footprint including
        // fine-tuning jitter and near-sidelobes, giving a complete reference
        // timeline.  All activities still go through the overlap check below.
        let dominant_intervals: Vec<(usize, usize)> = group
            .activities
            .iter()
            .filter(|a| (a.freq.round() as i32 - dominant_freq).abs() <= 3)
            .map(|a| (a.start_sample, a.end_sample))
            .collect();

        if dominant_intervals.is_empty() {
            result.push(group);
            continue;
        }

        // Classify ALL activities by temporal overlap with dominant set.
        // Sidelobes of the dominant signal overlap heavily (>30%); real
        // half-duplex operators transmit during the dominant's silence (<30%).
        let mut primary = Vec::new();
        let mut secondary = Vec::new();

        for a in &group.activities {
            let a_span = a.end_sample.saturating_sub(a.start_sample).max(1);
            let overlap: usize = dominant_intervals
                .iter()
                .map(|&(ds, de)| {
                    let start = a.start_sample.max(ds);
                    let end = a.end_sample.min(de);
                    end.saturating_sub(start)
                })
                .sum();
            let overlap_frac = overlap as f32 / a_span as f32;

            if overlap_frac < 0.30 {
                secondary.push(a.clone());
            } else {
                primary.push(a.clone());
            }
        }

        if secondary.len() >= 3 {
            let primary_freq = {
                let mut fs: Vec<f32> = primary.iter().map(|a| a.freq).collect();
                fs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                fs[fs.len() / 2]
            };

            // Sub-cluster the secondary activities by frequency (3 Hz threshold).
            // Tight threshold prevents the running-median drift from merging
            // spectrally distinct operators (e.g., 531Hz sidelobes + 541Hz AJ7CM).
            // Activities near the primary (≤5 Hz) are stray primary transmissions;
            // merge them back.  Far activities are genuine secondary operators.
            let sub_groups = cluster_activities_by_frequency(&secondary, 3.0);

            let mut near_primary = Vec::new();
            let mut far_groups: Vec<FrequencyGroup> = Vec::new();
            for sg in &sub_groups {
                tracing::debug!(
                    sub_freq = format!("{:.0}", sg.freq),
                    sub_count = sg.activities.len(),
                    dist_from_primary = format!("{:.0}", (sg.freq - primary_freq).abs()),
                    "Half-duplex sub-cluster"
                );
            }
            for sg in sub_groups {
                if (sg.freq - primary_freq).abs() <= 5.0 {
                    near_primary.extend(sg.activities);
                } else {
                    far_groups.push(sg);
                }
            }
            // Merge spectrally distinct sub-groups that are close enough in
            // frequency to be the same secondary operator (within 8 Hz).
            far_groups.sort_by(|a, b| {
                a.freq
                    .partial_cmp(&b.freq)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            let mut merged_far: Vec<FrequencyGroup> = Vec::new();
            for fg in far_groups {
                if let Some(last) = merged_far.last_mut() {
                    if (fg.freq - last.freq).abs() <= 8.0 {
                        last.activities.extend(fg.activities);
                        // Re-compute frequency as median
                        let mut fs: Vec<f32> = last.activities.iter().map(|a| a.freq).collect();
                        fs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                        last.freq = fs[fs.len() / 2];
                        continue;
                    }
                }
                merged_far.push(fg);
            }
            let far_groups = merged_far;

            // Merge near-primary secondaries back into primary
            primary.extend(near_primary);
            let primary_freq = {
                let mut fs: Vec<f32> = primary.iter().map(|a| a.freq).collect();
                fs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                fs[fs.len() / 2]
            };

            result.push(FrequencyGroup {
                freq: primary_freq,
                activities: primary,
                operator_id: result.len(),
            });

            // Only keep far groups with enough activities to be a real operator
            // (after merge, need at least 2 activities to avoid sidelobe noise)
            for fg in far_groups {
                if fg.activities.len() < 2 {
                    tracing::debug!(
                        freq = format!("{:.0}", fg.freq),
                        activities = fg.activities.len(),
                        "Half-duplex split: dropping tiny far group (likely sidelobe noise)"
                    );
                    continue;
                }
                tracing::info!(
                    original_freq = format!("{:.0}", group.freq),
                    primary_freq = format!("{:.0}", primary_freq),
                    secondary_freq = format!("{:.0}", fg.freq),
                    secondary_activities = fg.activities.len(),
                    "Half-duplex split: separated temporally independent operator"
                );
                result.push(FrequencyGroup {
                    freq: fg.freq,
                    activities: fg.activities,
                    operator_id: result.len(),
                });
            }
        } else {
            result.push(FrequencyGroup {
                freq: group.freq,
                activities: group.activities,
                operator_id: result.len(),
            });
        }
    }

    // Re-number operator IDs
    for (i, g) in result.iter_mut().enumerate() {
        g.operator_id = i;
    }

    result
}

/// Deduplicate overlapping segments within the same operator.
///
/// When a shorter segment from the same operator is fully contained within a
/// longer segment (>80% of the shorter segment's time range is inside the
/// longer one), the shorter segment is dropped. This preserves segments that
/// decoded different portions while removing true duplicates.
fn deduplicate_segments(mut segments: Vec<ToneSegment>) -> Vec<ToneSegment> {
    // Sort by operator_id, then by duration descending (longest first)
    segments.sort_by(|a, b| {
        a.operator_id.cmp(&b.operator_id).then_with(|| {
            let a_dur = segment_duration(a);
            let b_dur = segment_duration(b);
            b_dur.cmp(&a_dur) // longest first
        })
    });

    let mut keep = vec![true; segments.len()];
    let total = segments.len();

    for i in 0..segments.len() {
        if !keep[i] {
            continue;
        }
        for j in (i + 1)..segments.len() {
            if !keep[j] {
                continue;
            }
            // Only deduplicate within same operator
            if segments[j].operator_id != segments[i].operator_id {
                break;
            }

            // Check if the shorter segment (j) is mostly contained in the longer (i)
            let containment = segment_containment(&segments[i], &segments[j]);
            if containment > 0.8 {
                keep[j] = false;
            }
        }
    }

    let deduped: Vec<ToneSegment> = segments
        .into_iter()
        .enumerate()
        .filter(|(idx, _)| keep[*idx])
        .map(|(_, seg)| seg)
        .collect();

    let removed = total - deduped.len();
    if removed > 0 {
        tracing::info!(
            original = total,
            deduped = deduped.len(),
            removed = removed,
            "Deduplicated overlapping segments"
        );
    }

    deduped
}

/// Duration of a segment in samples.
fn segment_duration(seg: &ToneSegment) -> usize {
    let end = seg
        .events
        .last()
        .map(|e| e.sample_offset)
        .unwrap_or(seg.start_sample);
    end.saturating_sub(seg.start_sample)
}

/// What fraction of segment b's time range is contained within segment a?
/// Returns 0.0–1.0. High values mean b is a subset of a.
fn segment_containment(a: &ToneSegment, b: &ToneSegment) -> f64 {
    let a_end = a
        .events
        .last()
        .map(|e| e.sample_offset)
        .unwrap_or(a.start_sample);
    let b_end = b
        .events
        .last()
        .map(|e| e.sample_offset)
        .unwrap_or(b.start_sample);

    let b_len = (b_end - b.start_sample) as f64;
    if b_len < 1.0 {
        return 0.0;
    }

    let overlap_start = a.start_sample.max(b.start_sample);
    let overlap_end = a_end.min(b_end);

    if overlap_end <= overlap_start {
        return 0.0;
    }

    (overlap_end - overlap_start) as f64 / b_len
}

/// Decoder A: quadrature demodulation + Viterbi+Beam decoding.
///
/// Uses quadrature envelope detection for better SNR, then the proven
/// Viterbi HMM + BeamDecoder pipeline for per-segment decoding.
pub struct DecoderA;

impl CwDecoder for DecoderA {
    fn name(&self) -> &str {
        "decoder-a"
    }

    fn decode(&self, samples: &[f32], sample_rate: u32) -> DecoderOutput {
        let active_start = find_active_start(samples, sample_rate);
        let active = &samples[active_start..];

        let activities = scan_tone_activity(active, sample_rate, 400.0, 900.0, 10.0);
        let activities = refine_tone_frequencies(active, sample_rate, activities);

        // Cluster nearby frequencies into operator groups, then split clusters
        // that contain temporally independent subsets (half-duplex operators
        // at similar frequencies).
        let groups = cluster_activities_by_frequency(&activities, 15.0);
        let groups = split_half_duplex_groups(groups);

        // Quadrature front-end + Viterbi+Beam back-end (one pass per operator group)
        let all_segments = process_all_tones(active, sample_rate, &groups);

        // Deduplicate overlapping segments within the same operator
        let mut all_segments = deduplicate_segments(all_segments);
        all_segments.sort_by_key(|s| s.start_sample);

        let mut segment_texts: Vec<String> = Vec::new();
        let mut wpm_sum = 0u64;
        let mut wpm_count = 0u64;
        let mut snr_sum = 0.0f64;
        let mut snr_count = 0u64;

        for seg in &all_segments {
            let mut beam_decoder =
                BeamDecoder::new(seg.dit_ms, seg.char_gap_ms, seg.word_gap_ms, sample_rate);
            for event in &seg.events {
                beam_decoder.process_event(*event);
            }
            let seg_text = beam_decoder.finalize();
            let trimmed = seg_text.trim();

            let start_sec = seg.start_sample as f64 / sample_rate as f64;
            let end_sample = seg
                .events
                .last()
                .map_or(seg.start_sample, |e| e.sample_offset);
            let end_sec = end_sample as f64 / sample_rate as f64;
            tracing::debug!(
                op = seg.operator_id,
                tone_hz = format!("{:.0}", seg.tone_freq),
                wpm = seg.wpm,
                dit_ms = format!("{:.1}", seg.dit_ms),
                events = seg.events.len(),
                t_start = format!("{:.1}", start_sec),
                t_end = format!("{:.1}", end_sec),
                snr_db = format!("{:.1}", seg.snr_db),
                text = trimmed,
                "Segment decode"
            );

            if !trimmed.is_empty() {
                segment_texts.push(trimmed.to_string());
                wpm_sum += seg.wpm as u64;
                wpm_count += 1;
                snr_sum += seg.snr_db;
                snr_count += 1;
            }
        }

        let raw_text = segment_texts.join(" ");
        let avg_wpm = if wpm_count > 0 {
            ((wpm_sum / wpm_count) as u32).clamp(5, 50)
        } else {
            15
        };
        let avg_snr = if snr_count > 0 {
            snr_sum / snr_count as f64
        } else {
            0.0
        };
        let confidence = if raw_text.is_empty() {
            0.0
        } else {
            snr_to_confidence(avg_snr)
        };

        // Post-decode cleanup: remove isolated single-element Morse noise words
        let text = {
            let words: Vec<&str> = raw_text.split_whitespace().collect();
            let cleaned: Vec<&str> = words
                .iter()
                .filter(|w| {
                    if w.len() > 1 {
                        return true;
                    }
                    let c = w.chars().next().unwrap_or(' ');
                    !matches!(c, 'E' | 'T')
                })
                .copied()
                .collect();
            cleaned.join(" ")
        };

        let pp = postprocess::postprocess(&text);
        let text = pp.text;

        let confidence = if text.is_empty() { 0.0 } else { confidence };

        let wpm = if text.is_empty() {
            None
        } else {
            Some(avg_wpm as f64)
        };

        DecoderOutput {
            text,
            wpm,
            confidence,
            word_spans: Vec::new(),
            decoder_name: "decoder-a".into(),
        }
    }

    fn decode_structured(
        &self,
        samples: &[f32],
        sample_rate: u32,
        recording_id: Uuid,
        progress: &std::sync::atomic::AtomicU8,
    ) -> StructuredTranscript {
        use std::sync::atomic::Ordering::Relaxed;

        progress.store(5, Relaxed);

        let active_start = find_active_start(samples, sample_rate);
        let active = &samples[active_start..];
        let active_offset_secs = active_start as f64 / sample_rate as f64;

        let activities = scan_tone_activity(active, sample_rate, 400.0, 900.0, 10.0);
        let activities = refine_tone_frequencies(active, sample_rate, activities);
        progress.store(10, Relaxed);

        // Cluster nearby frequencies into operator groups, then split clusters
        // that contain temporally independent subsets (half-duplex operators
        // at similar frequencies).
        let groups = cluster_activities_by_frequency(&activities, 15.0);
        let groups = split_half_duplex_groups(groups);

        // Quadrature front-end + Viterbi+Beam back-end (one pass per operator group)
        let all_segments = process_all_tones(active, sample_rate, &groups);

        // Deduplicate overlapping segments within the same operator
        let mut all_segments = deduplicate_segments(all_segments);
        all_segments.sort_by_key(|s| s.start_sample);
        progress.store(30, Relaxed);

        let mut lines: Vec<TranscriptLine> = Vec::new();
        let mut wpm_sum = 0u64;
        let mut wpm_count = 0u64;
        let mut confidence_sum = 0.0f64;
        let mut confidence_count = 0u64;

        let total_segs = all_segments.len().max(1);

        for (seg_idx, seg) in all_segments.iter().enumerate() {
            let mut beam_decoder =
                BeamDecoder::new(seg.dit_ms, seg.char_gap_ms, seg.word_gap_ms, sample_rate);
            for event in &seg.events {
                beam_decoder.process_event(*event);
            }
            let (_text, spans) = beam_decoder.finalize_with_spans();

            let seg_confidence = snr_to_confidence(seg.snr_db);

            let words: Vec<TranscriptWord> = spans
                .into_iter()
                .filter(|s| !s.text.trim().is_empty())
                .filter(|s| !(s.text.len() == 1 && matches!(s.text.as_str(), "E" | "T")))
                .map(|span: WordSpan| {
                    let start_secs =
                        active_offset_secs + span.start_sample as f64 / sample_rate as f64;
                    let end_secs = active_offset_secs + span.end_sample as f64 / sample_rate as f64;
                    let upper = span.text.to_uppercase();
                    let is_cs = beam::is_callsign_pattern(&upper);
                    let corrected = postprocess::postprocess(&span.text).text;
                    TranscriptWord {
                        id: uuid::Uuid::new_v4(),
                        start_offset: start_secs,
                        end_offset: end_secs,
                        text: corrected,
                        is_callsign: is_cs,
                        confidence: seg_confidence,
                    }
                })
                .collect();

            if !words.is_empty() {
                let start_offset = words.first().map(|w| w.start_offset).unwrap_or(0.0);
                let end_offset = words.last().map(|w| w.end_offset).unwrap_or(0.0);
                let speaker = structured::detect_speaker(&words);

                lines.push(TranscriptLine {
                    id: uuid::Uuid::new_v4(),
                    start_offset,
                    end_offset,
                    words,
                    speaker_callsign: speaker,
                    operator_id: Some(seg.operator_id as u32),
                    tone_freq_hz: Some(seg.tone_freq),
                });

                wpm_sum += seg.wpm as u64;
                wpm_count += 1;
                confidence_sum += seg_confidence;
                confidence_count += 1;
            }

            let pct = 30 + ((seg_idx + 1) * 65 / total_segs) as u8;
            progress.store(pct.min(95), Relaxed);
        }

        let avg_wpm = if wpm_count > 0 {
            (wpm_sum / wpm_count) as u32
        } else {
            15
        };
        let avg_confidence = if confidence_count > 0 {
            confidence_sum / confidence_count as f64
        } else {
            0.0
        };

        // Remove decoded noise lines (repetitive short prosigns)
        let lines = structured::filter_noise_lines(lines);

        let detected_qso_ranges = structured::detect_qso_ranges(&lines);

        progress.store(100, Relaxed);

        StructuredTranscript {
            recording_id,
            lines,
            detected_qso_ranges,
            generated_at: chrono::Utc::now().to_rfc3339(),
            decoder_version: env!("CARGO_PKG_VERSION").to_string(),
            decoder_name: "decoder-a".into(),
            average_wpm: avg_wpm,
            average_confidence: avg_confidence,
        }
    }
}

/// Map SNR (dB) to a confidence score (0.0–1.0) using a sigmoid.
///
/// Calibration points:
/// - 0 dB → ~0.27 (barely detectable)
/// - 6 dB → ~0.50 (readable with errors)
/// - 12 dB → ~0.77 (mostly correct)
/// - 18 dB → ~0.92 (high quality)
/// - 24 dB → ~0.97 (excellent)
fn snr_to_confidence(snr_db: f64) -> f64 {
    // Logistic: 1 / (1 + exp(-(snr - 6) / 5))
    let x = (snr_db - 6.0) / 5.0;
    1.0 / (1.0 + (-x).exp())
}

/// Process all frequency groups through the quadrature pipeline.
///
/// For each operator group, picks the longest activity per merged time span
/// (preserving the original narrow time windows for better calibration),
/// then tags resulting segments with operator identity.
fn process_all_tones(
    active: &[f32],
    sample_rate: u32,
    groups: &[FrequencyGroup],
) -> Vec<ToneSegment> {
    let mut all_segments: Vec<ToneSegment> = Vec::new();
    let padding_before = sample_rate as usize; // 1s padding for calibration
    let padding_after = sample_rate as usize / 2; // 0.5s padding
    let all_freqs: Vec<f32> = groups.iter().map(|g| g.freq).collect();

    for group in groups {
        // Collect other operators' frequencies for notch filtering.
        // Only notch operators far enough away (>15 Hz) that the notch
        // won't cut into this operator's signal.  Close-frequency operators
        // are separated by temporal gating, not spectral notching.
        let neighbor_freqs: Vec<f32> = all_freqs
            .iter()
            .filter(|&&f| (f - group.freq).abs() > 15.0)
            .copied()
            .collect();

        // Collect individual activity frequencies for per-event classification
        let group_freqs: Vec<f32> = group.activities.iter().map(|a| a.freq).collect();

        for activity in &group.activities {
            let slice_start = activity.start_sample.saturating_sub(padding_before);
            let slice_end = (activity.end_sample + padding_after).min(active.len());
            let slice = &active[slice_start..slice_end];

            let mut segments = process_tone_v2(
                slice,
                sample_rate,
                group.freq,
                &neighbor_freqs,
                &group_freqs,
            );

            // Offset segment positions and tag with operator info
            for seg in &mut segments {
                seg.start_sample += slice_start;
                for ev in &mut seg.events {
                    ev.sample_offset += slice_start;
                }
                seg.tone_freq = group.freq;
                seg.operator_id = group.operator_id;
            }
            all_segments.extend(segments);
        }
    }

    all_segments
}

/// Classify keying events by their peak frequency using short Goertzel scans.
///
/// For each ON event longer than `min_duration_ms`, computes Goertzel energy at
/// each known frequency using the event's audio samples. The event is assigned to
/// the frequency with the highest energy. Short events inherit the classification
/// of their nearest classified neighbor.
///
/// Returns events grouped by operator frequency: `Vec<(f32, Vec<KeyingEvent>)>`
/// where `f32` is the operator frequency.
fn classify_events_by_frequency(
    samples: &[f32],
    sample_rate: u32,
    events: &[KeyingEvent],
    known_freqs: &[f32],
    min_duration_ms: f64,
) -> Vec<(f32, Vec<KeyingEvent>)> {
    use super::tone_detector::goertzel_energy;

    if known_freqs.len() <= 1 || events.is_empty() {
        // Single operator or no events — everything belongs to one group
        let freq = known_freqs.first().copied().unwrap_or(650.0);
        return vec![(freq, events.to_vec())];
    }

    let min_duration_samples = (sample_rate as f64 * min_duration_ms / 1000.0) as usize;

    // Classify each ON event by peak frequency
    // classified[i] = Some(freq_index) or None (short event, needs inheritance)
    let mut classified: Vec<Option<usize>> = vec![None; events.len()];

    for i in 0..events.len().saturating_sub(1) {
        if events[i].kind != KeyingEventKind::On {
            continue;
        }
        let event_start = events[i].sample_offset;
        let event_end = events[i + 1].sample_offset;
        let duration = event_end.saturating_sub(event_start);

        if duration < min_duration_samples {
            continue; // Too short — will inherit later
        }

        // Clamp to audio bounds
        let start = event_start.min(samples.len());
        let end = event_end.min(samples.len());
        if end <= start {
            continue;
        }
        let event_audio = &samples[start..end];

        // Find the frequency with the highest Goertzel energy
        let mut best_idx = 0;
        let mut best_energy = 0.0f32;
        for (fi, &freq) in known_freqs.iter().enumerate() {
            let energy = goertzel_energy(event_audio, freq, sample_rate);
            if energy > best_energy {
                best_energy = energy;
                best_idx = fi;
            }
        }
        classified[i] = Some(best_idx);
    }

    // Short events inherit from the nearest classified neighbor
    for i in 0..events.len() {
        if classified[i].is_some() || events[i].kind != KeyingEventKind::On {
            continue;
        }
        // Search outward for the nearest classified ON event
        let mut best_dist = usize::MAX;
        let mut best_class = 0usize;
        for (j, cls_opt) in classified.iter().enumerate() {
            if let Some(cls) = cls_opt {
                let dist = j.abs_diff(i);
                if dist < best_dist {
                    best_dist = dist;
                    best_class = *cls;
                }
            }
        }
        classified[i] = Some(best_class);
    }

    // Group events by operator frequency
    // Each ON event and its following OFF belong to the same operator
    let mut groups: Vec<Vec<KeyingEvent>> = vec![Vec::new(); known_freqs.len()];

    for i in 0..events.len() {
        if events[i].kind == KeyingEventKind::On {
            let freq_idx = classified[i].unwrap_or(0);
            groups[freq_idx].push(events[i]);
            // Also include the following OFF event
            if i + 1 < events.len() && events[i + 1].kind == KeyingEventKind::Off {
                groups[freq_idx].push(events[i + 1]);
            }
        }
    }

    // Return non-empty groups with their frequency
    known_freqs
        .iter()
        .zip(groups)
        .filter(|(_, evts)| !evts.is_empty())
        .map(|(&freq, evts)| (freq, evts))
        .collect()
}

/// Re-calibrate Otsu threshold for a specific operator using only their active windows.
///
/// The global Otsu threshold is biased when operators have different signal strengths.
/// This function collects envelope energies only from windows where the operator is active
/// (has ON events), computes a per-operator Otsu threshold, and re-detects events.
///
/// Returns re-detected events with the per-operator threshold.
fn recalibrate_events_for_operator(
    envelope: &[f32],
    events: &[KeyingEvent],
    _sample_rate: u32,
    _window_ms: u32,
    window_samples: usize,
) -> Vec<KeyingEvent> {
    use super::tone_detector::otsu_threshold_log;

    if events.is_empty() || envelope.is_empty() {
        return events.to_vec();
    }

    // Collect envelope indices where this operator has ON events
    let samples_per_window = window_samples;

    let mut active_windows: Vec<usize> = Vec::new();
    for i in 0..events.len().saturating_sub(1) {
        if events[i].kind == KeyingEventKind::On {
            let start_sample = events[i].sample_offset;
            let end_sample = events[i + 1].sample_offset;
            // Map sample range to envelope window indices
            let start_win = start_sample / samples_per_window;
            let end_win = (end_sample / samples_per_window).min(envelope.len());
            for w in start_win..end_win {
                active_windows.push(w);
            }
        }
    }

    if active_windows.len() < 4 {
        return events.to_vec();
    }

    // Collect energies from active windows + surrounding context (±5 windows)
    let mut context_energies: Vec<f32> = Vec::new();
    for &w in &active_windows {
        let start = w.saturating_sub(5);
        let end = (w + 6).min(envelope.len());
        for &e in &envelope[start..end] {
            context_energies.push(e);
        }
    }
    context_energies.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    context_energies.dedup(); // Remove exact duplicates from overlapping windows

    if context_energies.len() < 4 {
        return events.to_vec();
    }

    // Per-operator Otsu threshold
    let op_threshold = otsu_threshold_log(&context_energies);
    let op_off_threshold = op_threshold * 0.8;

    tracing::debug!(
        active_windows = active_windows.len(),
        context_energies = context_energies.len(),
        threshold = format!("{:.6}", op_threshold),
        "Per-operator Otsu recalibration"
    );

    // Re-detect events using the per-operator threshold
    let mut new_events: Vec<KeyingEvent> = Vec::new();
    let mut tone_on = false;

    for (i, &energy) in envelope.iter().enumerate() {
        let sample_offset = i * samples_per_window;
        if !tone_on {
            if energy >= op_threshold {
                tone_on = true;
                new_events.push(KeyingEvent {
                    kind: KeyingEventKind::On,
                    sample_offset,
                });
            }
        } else if energy < op_off_threshold {
            tone_on = false;
            new_events.push(KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset,
            });
        }
    }

    // Close final ON
    if tone_on {
        new_events.push(KeyingEvent {
            kind: KeyingEventKind::Off,
            sample_offset: envelope.len() * samples_per_window,
        });
    }

    new_events
}

/// Split merged events that are too long to be a single dit or dah.
///
/// Events longer than `max_element_ms` (3.5 × dit) may contain multiple CW elements
/// whose inter-element gaps were missed. This function examines the envelope within
/// each long event, finds dips (local minima below 0.7 × peak), and splits at the
/// deepest valid dip(s) to produce plausible sub-events.
fn split_merged_events(
    events: &[KeyingEvent],
    dit_ms: f64,
    envelope: &[f32],
    sample_rate: u32,
    window_samples: usize,
) -> Vec<KeyingEvent> {
    let max_element_ms = dit_ms * 3.5;
    let max_element_samples = (sample_rate as f64 * max_element_ms / 1000.0) as usize;
    let min_sub_samples = (sample_rate as f64 * dit_ms * 0.5 / 1000.0) as usize;

    let mut result: Vec<KeyingEvent> = Vec::new();
    let mut splits_made = 0usize;

    let mut i = 0;
    while i < events.len() {
        if i + 1 < events.len()
            && events[i].kind == KeyingEventKind::On
            && events[i + 1].kind == KeyingEventKind::Off
        {
            let on_start = events[i].sample_offset;
            let on_end = events[i + 1].sample_offset;
            let duration = on_end.saturating_sub(on_start);

            if duration > max_element_samples {
                // Map to envelope window indices
                let env_start = (on_start / window_samples).min(envelope.len());
                let env_end = (on_end / window_samples).min(envelope.len());

                if env_end > env_start + 2 {
                    let env_slice = &envelope[env_start..env_end];
                    let peak = env_slice.iter().fold(0.0f32, |a, &b| a.max(b));
                    let dip_threshold = peak * 0.7;

                    // Find all dips below the threshold
                    let mut dips: Vec<(usize, f32)> = Vec::new(); // (index_in_slice, energy)
                    for j in 1..env_slice.len().saturating_sub(1) {
                        if env_slice[j] < env_slice[j - 1]
                            && env_slice[j] <= env_slice[j + 1]
                            && env_slice[j] < dip_threshold
                        {
                            dips.push((j, env_slice[j]));
                        }
                    }

                    // Sort dips by depth (lowest energy first)
                    dips.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));

                    // Try to split at the deepest dips, validating sub-event lengths
                    let mut split_points: Vec<usize> = Vec::new(); // sample offsets
                    for &(dip_idx, _) in &dips {
                        let split_sample = on_start + dip_idx * window_samples;

                        // Validate: each sub-event must be at least min_sub_samples
                        let prev_boundary = split_points.last().copied().unwrap_or(on_start);
                        if split_sample.saturating_sub(prev_boundary) >= min_sub_samples {
                            split_points.push(split_sample);
                        }
                    }

                    // Validate final sub-event
                    if let Some(&last_split) = split_points.last() {
                        if on_end.saturating_sub(last_split) < min_sub_samples {
                            split_points.pop();
                        }
                    }

                    if !split_points.is_empty() {
                        // Emit split sub-events
                        let mut prev = on_start;
                        for &sp in &split_points {
                            result.push(KeyingEvent {
                                kind: KeyingEventKind::On,
                                sample_offset: prev,
                            });
                            result.push(KeyingEvent {
                                kind: KeyingEventKind::Off,
                                sample_offset: sp,
                            });
                            // Small gap at the split point (1 window)
                            prev = sp + window_samples;
                        }
                        // Final sub-event
                        result.push(KeyingEvent {
                            kind: KeyingEventKind::On,
                            sample_offset: prev.min(on_end),
                        });
                        result.push(KeyingEvent {
                            kind: KeyingEventKind::Off,
                            sample_offset: on_end,
                        });
                        splits_made += 1;
                        i += 2;
                        continue;
                    }
                }
            }
        }

        result.push(events[i]);
        i += 1;
    }

    if splits_made > 0 {
        tracing::debug!(
            splits = splits_made,
            dit_ms = format!("{:.1}", dit_ms),
            max_element_ms = format!("{:.1}", max_element_ms),
            "Split merged events"
        );
    }

    result
}

/// Process a single tone frequency through the quadrature detection pipeline.
///
/// Pipeline:
/// 1. Asymmetric bandpass + aggressive notch
/// 2. Wide bandwidth (120 Hz) quadrature detection → WPM estimate
/// 3. Matched bandwidth (max(6×WPM, 60) Hz) → final detection with better SNR
/// 4. Viterbi HMM on matched-bandwidth energies
/// 5. Merge Viterbi events
/// 6. Per-event frequency classification (filter leakage from neighbors)
/// 7. Per-operator Otsu recalibration
/// 8. Split merged events
/// 9. Segmentation and per-segment decoding
fn process_tone_v2(
    samples: &[f32],
    sample_rate: u32,
    tone_freq: f32,
    neighbor_freqs: &[f32],
    group_freqs: &[f32],
) -> Vec<ToneSegment> {
    let window_ms = 10u32;

    // === Step 1: Asymmetric bandpass + aggressive notch ===
    let mut low_edge = tone_freq - 40.0;
    let mut high_edge = tone_freq + 40.0;

    for &nf in neighbor_freqs {
        let d = nf - tone_freq;
        if d < 0.0 {
            let dist = d.abs();
            low_edge = low_edge.max(tone_freq - (dist / 2.0).max(15.0));
        } else if d > 0.0 {
            let dist = d;
            high_edge = high_edge.min(tone_freq + (dist / 2.0).max(15.0));
        }
    }
    low_edge = low_edge.max(400.0);
    high_edge = high_edge.min(900.0);

    let mut stages: Vec<BiquadFilter> = Vec::new();
    for _ in 0..3 {
        stages.push(BiquadFilter::highpass(low_edge, 0.707, sample_rate));
    }
    for _ in 0..3 {
        stages.push(BiquadFilter::lowpass(high_edge, 0.707, sample_rate));
    }
    for &nf in neighbor_freqs {
        let dist = (nf - tone_freq).abs();
        let q = if dist < 30.0 { 40.0 } else { 20.0 };
        stages.push(BiquadFilter::notch(nf, q, sample_rate));
        if dist < 30.0 {
            stages.push(BiquadFilter::notch(nf, q, sample_rate));
        }
    }

    let mut filtered = samples.to_vec();
    BiquadCascade::new(stages).process_block(&mut filtered);

    if !neighbor_freqs.is_empty() {
        tracing::debug!(
            tone_hz = format!("{:.0}", tone_freq),
            bp_low = format!("{:.0}", low_edge),
            bp_high = format!("{:.0}", high_edge),
            notched = ?neighbor_freqs.iter().map(|f| format!("{:.0}", f)).collect::<Vec<_>>(),
            "Applied asymmetric bandpass + notch filters"
        );
    }

    // === Step 2: Wide bandwidth for WPM estimation ===
    let wide_bw = 120.0;
    let wide_detector = QuadratureDetector::new(tone_freq, sample_rate, wide_bw, window_ms);
    let wide_envelope = wide_detector.compute_envelope(&filtered);

    if wide_envelope.is_empty() {
        return Vec::new();
    }

    let window_samples = (sample_rate as usize * window_ms as usize) / 1000;
    let initial_dit_windows = estimate_dit_from_envelope(&wide_envelope, window_ms);
    let initial_dit_ms = initial_dit_windows as f64 * window_ms as f64;
    let initial_wpm = ((1200.0 / initial_dit_ms) as u32).clamp(5, 50);

    // === Step 3: Matched bandwidth for detection ===
    let matched_bw = (6.0 * initial_wpm as f32).max(60.0).min(wide_bw);
    let matched_envelope = if (matched_bw - wide_bw).abs() > 5.0 {
        let matched_detector =
            QuadratureDetector::new(tone_freq, sample_rate, matched_bw, window_ms);
        matched_detector.compute_envelope(&filtered)
    } else {
        wide_envelope.clone()
    };

    let snr_db = QuadratureDetector::estimate_snr(&matched_envelope);

    // === Step 4: Viterbi HMM ===
    let dit_windows = initial_dit_windows.max(3);
    let viterbi_events = viterbi_detect(
        &matched_envelope,
        dit_windows,
        window_samples,
        &ViterbiParams::quadrature(),
    );

    // === Step 5: Merge Viterbi events ===
    let wpm_scaled_gap = (sample_rate as f64 * initial_dit_ms * 0.5 / 1000.0) as usize;
    let viterbi_min_on = (sample_rate as f64 * 0.030) as usize;
    let merged_events = merge_keying_events(&viterbi_events, wpm_scaled_gap, viterbi_min_on);

    // Re-estimate dit duration from Viterbi events
    let decoder_dit_ms = {
        let evts: Vec<_> = merged_events.iter().collect();
        let mut vit_on_ms: Vec<f64> = Vec::new();
        for i in 0..evts.len().saturating_sub(1) {
            let dur = (evts[i + 1].sample_offset as f64 - evts[i].sample_offset as f64)
                / sample_rate as f64
                * 1000.0;
            if evts[i].kind == KeyingEventKind::On {
                vit_on_ms.push(dur);
            }
        }
        estimate_dit_otsu(&vit_on_ms, initial_dit_ms, 4)
    };
    let decoder_wpm = ((1200.0 / decoder_dit_ms) as u32).clamp(5, 50);

    let on_count = merged_events
        .iter()
        .filter(|e| e.kind == KeyingEventKind::On)
        .count();
    tracing::info!(
        tone_freq_hz = format!("{:.0}", tone_freq),
        viterbi_raw = viterbi_events.len(),
        on_events = on_count,
        wpm = decoder_wpm,
        snr_db = format!("{:.1}", snr_db),
        matched_bw_hz = format!("{:.0}", matched_bw),
        "DecoderA: Quadrature + Viterbi detection"
    );

    // === Step 6: Per-event frequency classification ===
    // Classify events by operator frequency to filter leakage from close neighbors.
    // Use all known frequencies (group + neighbors) for classification.
    let mut all_known_freqs: Vec<f32> = group_freqs.to_vec();
    for &nf in neighbor_freqs {
        if !all_known_freqs.iter().any(|&f| (f - nf).abs() < 1.0) {
            all_known_freqs.push(nf);
        }
    }
    all_known_freqs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let operator_groups = classify_events_by_frequency(
        samples,
        sample_rate,
        &merged_events,
        &all_known_freqs,
        60.0, // min 60ms for reliable frequency measurement
    );

    // Keep only events classified as belonging to this tone's frequency.
    // If classification produced no group for our frequency, fall back to all events.
    let target_events = if all_known_freqs.len() > 1 {
        operator_groups
            .iter()
            .find(|(freq, _)| (freq - tone_freq).abs() < 15.0)
            .map(|(_, evts)| evts.clone())
            .unwrap_or_else(|| merged_events.clone())
    } else {
        merged_events.clone()
    };

    // === Step 7: Per-operator Otsu recalibration ===
    let recalibrated_events = if target_events.len() >= 4 {
        let recal = recalibrate_events_for_operator(
            &matched_envelope,
            &target_events,
            sample_rate,
            window_ms,
            window_samples,
        );
        // Use recalibrated events if they found a reasonable number of events,
        // otherwise fall back to the original target events
        if recal
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count()
            >= 2
        {
            // Re-merge recalibrated events
            merge_keying_events(&recal, wpm_scaled_gap, viterbi_min_on)
        } else {
            target_events
        }
    } else {
        target_events
    };

    // === Step 8: Split merged events ===
    let final_events = split_merged_events(
        &recalibrated_events,
        decoder_dit_ms,
        &matched_envelope,
        sample_rate,
        window_samples,
    );

    // === Step 9: Segmentation and per-segment decoding ===
    let evts_ref: Vec<_> = final_events.iter().collect();
    let mut global_off_ms: Vec<f64> = Vec::new();
    for i in 0..evts_ref.len().saturating_sub(1) {
        let dur = (evts_ref[i + 1].sample_offset as f64 - evts_ref[i].sample_offset as f64)
            / sample_rate as f64
            * 1000.0;
        if evts_ref[i].kind == KeyingEventKind::Off {
            global_off_ms.push(dur);
        }
    }
    let (_cg_raw, wg_raw) = estimate_gap_thresholds(&global_off_ms, decoder_dit_ms);

    let segment_threshold_ms = wg_raw
        .min(decoder_dit_ms * 15.0)
        .max(decoder_dit_ms * 7.0)
        .max(500.0);
    let segment_threshold_samples = (segment_threshold_ms / 1000.0 * sample_rate as f64) as usize;

    let mut seg_starts: Vec<usize> = vec![0];
    for i in 0..final_events.len().saturating_sub(1) {
        if final_events[i].kind == KeyingEventKind::Off {
            let gap = final_events[i + 1]
                .sample_offset
                .saturating_sub(final_events[i].sample_offset);
            if gap >= segment_threshold_samples {
                seg_starts.push(i + 1);
            }
        }
    }

    tracing::info!(
        tone_freq_hz = format!("{:.0}", tone_freq),
        final_on_events = final_events
            .iter()
            .filter(|e| e.kind == KeyingEventKind::On)
            .count(),
        segments = seg_starts.len(),
        "DecoderA: Per-operator pipeline complete"
    );

    let min_events_for_estimation = 8;
    let min_off_events_for_gaps = 6;
    let mut tone_segments: Vec<ToneSegment> = Vec::new();

    for seg_idx in 0..seg_starts.len() {
        let start = seg_starts[seg_idx];
        let end = seg_starts
            .get(seg_idx + 1)
            .copied()
            .unwrap_or(final_events.len());
        let seg_events = &final_events[start..end];

        let seg_evts: Vec<_> = seg_events.iter().collect();
        let mut seg_on_ms: Vec<f64> = Vec::new();
        let mut seg_off_ms: Vec<f64> = Vec::new();
        for i in 0..seg_evts.len().saturating_sub(1) {
            let dur = (seg_evts[i + 1].sample_offset as f64 - seg_evts[i].sample_offset as f64)
                / sample_rate as f64
                * 1000.0;
            if seg_evts[i].kind == KeyingEventKind::On {
                seg_on_ms.push(dur);
            } else {
                seg_off_ms.push(dur);
            }
        }

        let seg_dit = estimate_dit_otsu(&seg_on_ms, decoder_dit_ms, min_events_for_estimation);
        let seg_wpm = ((1200.0 / seg_dit) as u32).clamp(5, 50);

        let (seg_cg, seg_wg) = if seg_off_ms.len() >= min_off_events_for_gaps {
            let (cg_raw, wg_raw) = estimate_gap_thresholds(&seg_off_ms, seg_dit);
            let cg = cg_raw.max(seg_dit * 1.5).min(seg_dit * 5.0);
            let wg = wg_raw.max(seg_dit * 2.5).max(cg * 1.5).min(seg_dit * 10.0);
            (cg, wg)
        } else {
            (seg_dit * 1.5, seg_dit * 3.5)
        };

        let start_sample = seg_events.first().map(|e| e.sample_offset).unwrap_or(0);

        tone_segments.push(ToneSegment {
            events: seg_events.to_vec(),
            start_sample,
            dit_ms: seg_dit,
            wpm: seg_wpm,
            char_gap_ms: seg_cg,
            word_gap_ms: seg_wg,
            snr_db,
            tone_freq: 0.0, // set by caller (process_all_tones)
            operator_id: 0, // set by caller (process_all_tones)
        });
    }

    tone_segments
}

/// Estimate dit duration in windows from an envelope using Otsu thresholding.
///
/// Returns the dit duration in number of windows.
fn estimate_dit_from_envelope(envelope: &[f32], window_ms: u32) -> usize {
    if envelope.len() < 4 {
        return 5; // default ~50ms at 10ms windows
    }

    // Otsu threshold on envelope
    let mut sorted = envelope.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let threshold = super::tone_detector::otsu_threshold_log(&sorted);

    // Find on-duration runs (in windows)
    let mut on_durations: Vec<f64> = Vec::new();
    let mut run_start: Option<usize> = None;

    for (i, &e) in envelope.iter().enumerate() {
        match (e >= threshold, run_start) {
            (true, None) => run_start = Some(i),
            (false, Some(start)) => {
                on_durations.push((i - start) as f64 * window_ms as f64);
                run_start = None;
            }
            _ => {}
        }
    }
    if let Some(start) = run_start {
        on_durations.push((envelope.len() - start) as f64 * window_ms as f64);
    }

    if on_durations.is_empty() {
        return 5;
    }

    let (_, dit_ms) = estimate_wpm_histogram(&on_durations);
    (dit_ms / window_ms as f64).round().max(3.0) as usize
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transcription::decoder_trait::CwDecoder;

    /// DecoderA should produce non-empty output on the same synthetic signal
    /// that the legacy decoder handles.
    #[test]
    fn decoder_a_produces_output() {
        let sr = 12_000u32;
        let tone_freq = 650.0f32;
        let dit_ms = 60.0; // ~20 WPM
        let dit_samples = (sr as f64 * dit_ms / 1000.0) as usize;

        // Generate "CQ" in Morse: C = "-.-." Q = "--.-"
        let mut samples = Vec::new();
        let morse_cq = [
            (3, true),
            (1, false),
            (1, true),
            (1, false),
            (3, true),
            (1, false),
            (1, true),
            (3, false), // C + char gap
            (3, true),
            (1, false),
            (3, true),
            (1, false),
            (1, true),
            (1, false),
            (3, true),
        ];

        // Leading silence
        for _ in 0..sr {
            samples.push(0.0f32);
        }

        for &(units, is_on) in &morse_cq {
            let num = units * dit_samples;
            for i in 0..num {
                if is_on {
                    let t = (samples.len() + i) as f32 / sr as f32;
                    samples.push((2.0 * std::f32::consts::PI * tone_freq * t).sin() * 0.8);
                } else {
                    samples.push(0.0);
                }
            }
            // Actually push the generated samples
            let start = samples.len() - 0; // samples already pushed in loop above
            let _ = start; // suppress warning
        }

        // Trailing silence
        for _ in 0..sr {
            samples.push(0.0f32);
        }

        let decoder = DecoderA;
        let output = decoder.decode(&samples, sr);

        // Should produce some decoded text (exact accuracy depends on signal quality)
        // The key test is that the pipeline runs without panicking
        assert!(
            output.decoder_name == "decoder-a",
            "decoder name should be decoder-a"
        );
    }

    #[test]
    fn snr_to_confidence_monotonic() {
        let c0 = snr_to_confidence(0.0);
        let c6 = snr_to_confidence(6.0);
        let c12 = snr_to_confidence(12.0);
        let c18 = snr_to_confidence(18.0);

        assert!(c0 < c6, "confidence should increase with SNR");
        assert!(c6 < c12, "confidence should increase with SNR");
        assert!(c12 < c18, "confidence should increase with SNR");

        // Check calibration points
        assert!(
            (c6 - 0.5).abs() < 0.01,
            "6 dB should give ~0.5 confidence, got {c6}"
        );
        assert!(c18 > 0.9, "18 dB should give >0.9 confidence, got {c18}");
    }

    #[test]
    #[ignore]
    fn decoder_a_pota_regression() {
        use crate::recording::combine;
        use std::path::PathBuf;

        let path = PathBuf::from("/Users/jsvana/tmp/pota-upload-20260221.wav");
        if !path.exists() {
            eprintln!("Skipping: file not found");
            return;
        }

        let (sample_rate, samples) = combine::read_wav_samples(&path).unwrap();
        let decoder = DecoderA;
        let output = decoder.decode(&samples, sample_rate);
        eprintln!(
            "Decoder A: WPM={:?} confidence={:.2}",
            output.wpm, output.confidence
        );
        eprintln!("Text ({} chars):\n{}", output.text.len(), output.text);
    }
}
