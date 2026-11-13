pub mod audio_decode;
pub mod combine;
pub mod dsp;
pub mod flac;
pub mod segment;

use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{error, info};
use uuid::Uuid;

use chrono::{DateTime, Utc};

use crate::db::models::{RecordingRow, SegmentRow};
use crate::db::Database;
use crate::error::RecordingError;
use crate::mux::request::CaptureRequest;
use crate::mux::session::ConsumerHandle;
use crate::mux::CaptureMultiplexer;
use crate::types::{CapturePriority, DemodMode, SdrId};
use tracing::warn;

use dsp::{Demodulator, NarrowbandExtractor};
use segment::SegmentWriter;

/// Maximum number of reconnect attempts before giving up.
const MAX_RECONNECT_ATTEMPTS: u32 = 10;
/// Initial backoff delay in milliseconds.
const INITIAL_BACKOFF_MS: u64 = 2_000;
/// Maximum backoff delay in milliseconds.
const MAX_BACKOFF_MS: u64 = 30_000;
/// Backoff multiplier per attempt.
const BACKOFF_MULTIPLIER: f64 = 2.0;

/// Result of combining multiple recordings.
#[derive(Debug)]
pub struct CombineResult {
    pub combined_id: Uuid,
    /// Source recording IDs that were included in the average.
    pub included_ids: Vec<Uuid>,
    /// Source recording IDs that were excluded, with reasons.
    pub excluded: Vec<(Uuid, String)>,
}

/// Manages active recordings.
pub struct RecordingEngine {
    mux: Arc<CaptureMultiplexer>,
    db: Arc<Mutex<Database>>,
    data_dir: PathBuf,
    segment_duration_secs: f64,
    active_tasks: Arc<Mutex<Vec<ActiveRecording>>>,
}

/// Request to retune an active recording to a new frequency.
#[derive(Debug, Clone)]
pub struct RetuneRequest {
    pub frequency: u64,
    pub bandwidth: Option<u32>,
}

struct ActiveRecording {
    id: Uuid,
    session_id: Uuid,
    cancel: tokio::sync::oneshot::Sender<()>,
    retune_tx: tokio::sync::mpsc::Sender<RetuneRequest>,
    handle: tokio::task::JoinHandle<()>,
}

/// Parameters for starting a new recording.
#[derive(Debug, Clone)]
pub struct RecordingParams {
    pub sdr_id: Option<SdrId>,
    pub frequency: u64,
    pub bandwidth: u32,
    pub mode: DemodMode,
    pub output_sample_rate: u32,
    pub retention_days: u32,
    /// Optional reference time for multi-SDR alignment. When set, the recording
    /// task pads silence from this time until the first IQ buffer arrives, so
    /// all recordings sharing the same reference_time produce time-aligned WAVs.
    pub reference_time: Option<DateTime<Utc>>,
}

impl Default for RecordingParams {
    fn default() -> Self {
        Self {
            sdr_id: None,
            frequency: 7_030_000,
            bandwidth: 500,
            mode: DemodMode::Cw,
            output_sample_rate: 12_000,
            retention_days: 30,
            reference_time: None,
        }
    }
}

impl RecordingEngine {
    pub fn new(
        mux: Arc<CaptureMultiplexer>,
        db: Arc<Mutex<Database>>,
        data_dir: PathBuf,
        segment_duration_secs: f64,
    ) -> Self {
        Self {
            mux,
            db,
            data_dir,
            segment_duration_secs,
            active_tasks: Arc::new(Mutex::new(Vec::new())),
        }
    }

    /// Start a new recording. Returns the recording UUID.
    pub async fn start_recording(&self, params: RecordingParams) -> Result<Uuid, RecordingError> {
        let recording_id = Uuid::new_v4();

        // Request a capture from the multiplexer
        let request = CaptureRequest {
            sdr_id: params.sdr_id.clone(),
            frequency: params.frequency,
            bandwidth: params.bandwidth,
            priority: CapturePriority::Recording,
            mode: params.mode,
        };

        let capture_request = request.clone();
        let consumer = self
            .mux
            .request_capture(request)
            .await
            .map_err(|e| RecordingError::DspError(e.to_string()))?;

        // Insert recording row in DB
        let sdr_id_str = params
            .sdr_id
            .as_ref()
            .map(|s| s.0.clone())
            .unwrap_or_else(|| "auto".into());

        let now = chrono::Utc::now();
        let rec_row = RecordingRow {
            id: recording_id,
            capture_id: None,
            sdr_id: sdr_id_str.clone(),
            frequency: params.frequency as i64,
            bandwidth: params.bandwidth as i64,
            mode: format!("{}", params.mode).to_lowercase(),
            status: "active".into(),
            started_at: now,
            stopped_at: None,
            retention_days: params.retention_days as i64,
            created_at: now,
        };

        {
            let db = self.db.lock().await;
            db.insert_recording(&rec_row)
                .map_err(|e| RecordingError::DspError(e.to_string()))?;
        }

        // Create recording directory
        let rec_dir = self.data_dir.join(recording_id.to_string());

        // Spawn the recording task
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
        let (retune_tx, retune_rx) = tokio::sync::mpsc::channel(4);
        let db = self.db.clone();
        let segment_duration = self.segment_duration_secs;
        let output_rate = params.output_sample_rate;
        let mode = params.mode;
        let input_bw = params.bandwidth;
        let reference_time = params.reference_time;
        let mux_for_task = self.mux.clone();
        let session_id = consumer.session_id;

        let handle = tokio::spawn(async move {
            if let Err(e) = recording_task(
                recording_id,
                consumer,
                mux_for_task,
                capture_request,
                rec_dir,
                segment_duration,
                output_rate,
                input_bw,
                mode,
                reference_time,
                db,
                cancel_rx,
                retune_rx,
            )
            .await
            {
                error!(recording = %recording_id, error = %e, "Recording task failed");
            }
        });

        let mut tasks = self.active_tasks.lock().await;
        tasks.push(ActiveRecording {
            id: recording_id,
            session_id,
            cancel: cancel_tx,
            retune_tx,
            handle,
        });

        info!(recording = %recording_id, frequency = params.frequency, mode = %params.mode, "Recording started");
        Ok(recording_id)
    }

    /// Stop a recording by ID.
    pub async fn stop_recording(&self, id: Uuid) -> Result<(), RecordingError> {
        let mut tasks = self.active_tasks.lock().await;
        if let Some(pos) = tasks.iter().position(|t| t.id == id) {
            let task = tasks.remove(pos);
            let _ = task.cancel.send(());
            // Wait for the task to finalize segments and insert into DB
            match tokio::time::timeout(std::time::Duration::from_secs(10), task.handle).await {
                Ok(Ok(())) => {}
                Ok(Err(e)) => {
                    error!(recording = %id, error = %e, "Recording task panicked");
                }
                Err(_) => {
                    error!(recording = %id, "Recording task did not finish within 10s");
                }
            }

            // Update DB status
            let db = self.db.lock().await;
            let _ = db.update_recording_status(id, "stopped", Some(chrono::Utc::now()));

            info!(recording = %id, "Recording stopped");
            Ok(())
        } else {
            Err(RecordingError::NotFound(id))
        }
    }

    /// Retune an active recording to a new frequency.
    /// This closes the current WAV segment, retunes the underlying SDR,
    /// rebuilds the DSP chain, and starts a new segment.
    pub async fn retune_recording(
        &self,
        id: Uuid,
        frequency: u64,
        bandwidth: Option<u32>,
    ) -> Result<(), RecordingError> {
        let tasks = self.active_tasks.lock().await;
        if let Some(task) = tasks.iter().find(|t| t.id == id) {
            // First retune the underlying capture session
            self.mux
                .retune_session(task.session_id, frequency)
                .await
                .map_err(|e| RecordingError::DspError(format!("mux retune failed: {e}")))?;

            // Then tell the recording task to close segment and rebuild DSP
            task.retune_tx
                .send(RetuneRequest {
                    frequency,
                    bandwidth,
                })
                .await
                .map_err(|e| RecordingError::DspError(format!("retune send failed: {e}")))?;

            info!(recording = %id, frequency, "Recording retune initiated");
            Ok(())
        } else {
            Err(RecordingError::NotFound(id))
        }
    }

    /// List active recording IDs.
    pub async fn active_recordings(&self) -> Vec<Uuid> {
        let tasks = self.active_tasks.lock().await;
        tasks.iter().map(|t| t.id).collect()
    }

    /// Stop all recordings (for graceful shutdown).
    pub async fn stop_all(&self) {
        let mut tasks = self.active_tasks.lock().await;
        for task in tasks.drain(..) {
            let _ = task.cancel.send(());
            let _ = task.handle.await;
        }
    }

    /// Combine multiple recordings by averaging their audio (noise reduction).
    /// All source recordings must be stopped and share the same mode and frequency.
    ///
    /// When `skip_quality_filter` is false (default), runs a two-phase quality
    /// filter: drops dead receivers (near-zero RMS) and iteratively drops sources
    /// with low leave-one-out correlation (uncorrelated noise/interference).
    pub async fn combine_recordings(
        &self,
        source_ids: Vec<Uuid>,
        retention_days: u32,
        skip_quality_filter: bool,
    ) -> Result<CombineResult, RecordingError> {
        if source_ids.len() < 2 || source_ids.len() > 100 {
            return Err(RecordingError::Incompatible(format!(
                "need 2..100 source recordings, got {}",
                source_ids.len()
            )));
        }

        // Fetch all recordings and their segments
        let (recordings, all_segments) = {
            let db = self.db.lock().await;
            let mut recordings = Vec::with_capacity(source_ids.len());
            let mut all_segments = Vec::with_capacity(source_ids.len());

            for id in &source_ids {
                let rec = db
                    .get_recording(*id)
                    .map_err(|_| RecordingError::NotFound(*id))?;
                let segs = db
                    .list_segments(*id)
                    .map_err(|e| RecordingError::DspError(e.to_string()))?;
                recordings.push(rec);
                all_segments.push(segs);
            }

            (recordings, all_segments)
        };

        // Validate all recordings are stopped
        for rec in &recordings {
            if rec.status != "stopped" {
                return Err(RecordingError::Incompatible(format!(
                    "recording {} has status '{}', expected 'stopped'",
                    rec.id, rec.status
                )));
            }
        }

        // Validate same mode and frequency
        let mode = &recordings[0].mode;
        let freq = recordings[0].frequency;
        for rec in &recordings[1..] {
            if rec.mode != *mode {
                return Err(RecordingError::Incompatible(format!(
                    "mode mismatch: {} vs {}",
                    mode, rec.mode
                )));
            }
            if rec.frequency != freq {
                return Err(RecordingError::Incompatible(format!(
                    "frequency mismatch: {} vs {}",
                    freq, rec.frequency
                )));
            }
        }

        // Exclude recordings with no segments (can't read audio from them)
        let mut pre_excluded: Vec<(Uuid, String)> = Vec::new();
        let mut usable_indices: Vec<usize> = Vec::new();
        for (i, segs) in all_segments.iter().enumerate() {
            if segs.is_empty() {
                pre_excluded.push((source_ids[i], "no segments".into()));
            } else {
                usable_indices.push(i);
            }
        }

        if usable_indices.len() < 2 {
            return Err(RecordingError::Incompatible(format!(
                "only {} recording(s) have segments (need at least 2)",
                usable_indices.len()
            )));
        }

        // Validate usable segments share the same sample rate
        let sample_rate = all_segments[usable_indices[0]][0].sample_rate;
        for &i in &usable_indices {
            for seg in &all_segments[i] {
                if seg.sample_rate != sample_rate {
                    return Err(RecordingError::Incompatible(format!(
                        "sample rate mismatch: expected {}, got {}",
                        sample_rate, seg.sample_rate
                    )));
                }
            }
        }

        // Collect only usable segment lists for the blocking task
        let usable_segments: Vec<Vec<SegmentRow>> = usable_indices
            .iter()
            .map(|&i| all_segments[i].clone())
            .collect();

        let data_dir = self.data_dir.clone();
        let segment_duration = self.segment_duration_secs;
        let sr = sample_rate as u32;
        let combine_mode = mode.clone();

        // Heavy work: read all audio, filter, average, write output
        let (combined_id, seg_metas, kept_indices, audio_excluded) =
            tokio::task::spawn_blocking(move || {
                let combined_id = Uuid::new_v4();

                // Read audio from each usable recording
                let mut sources = Vec::with_capacity(usable_segments.len());
                for segs in &usable_segments {
                    let (_sr, samples) = combine::read_recording_audio(segs)?;
                    sources.push(samples);
                }

                // Apply bandpass filter for CW mode before correlation and averaging.
                // This removes out-of-band noise so both the quality filter and the
                // final average operate on cleaner signal.
                if combine_mode == "cw" {
                    for source in &mut sources {
                        combine::bandpass_filter(source, 400.0, 900.0, sr);
                    }
                }

                // Cross-correlation time alignment: shift each source to
                // compensate for variable SDR latency before quality filtering
                // (misaligned sources have artificially low correlation).
                let (mut sources, alignment_info) = combine::align_sources_with_drift(sources, sr);
                for ai in &alignment_info {
                    if ai.lag_samples != 0 {
                        info!(
                            source = ai.source_index,
                            lag_samples = ai.lag_samples,
                            lag_ms = format!("{:.1}", ai.lag_ms),
                            correlation = format!("{:.4}", ai.correlation_peak),
                            "Aligned source"
                        );
                    }
                    if let Some(ppm) = ai.drift_ppm {
                        info!(
                            source = ai.source_index,
                            drift_ppm = format!("{:.1}", ppm),
                            corrected = ai.drift_corrected,
                            "Clock drift"
                        );
                    }
                }
                let ref_source = alignment_info
                    .iter()
                    .find(|a| a.lag_samples == 0 && a.correlation_peak >= 1.0)
                    .map(|a| a.source_index);
                if let Some(ref_idx) = ref_source {
                    info!(reference_source = ref_idx, "Alignment reference");
                }

                // Quality filter on audio
                let (kept_indices, audio_excluded) = if skip_quality_filter {
                    ((0..sources.len()).collect::<Vec<_>>(), Vec::new())
                } else {
                    let result = combine::filter_sources(&sources, sr);
                    (result.included, result.excluded)
                };

                if kept_indices.len() < 2 {
                    return Err(RecordingError::Incompatible(
                        "fewer than 2 recordings passed quality filter".into(),
                    ));
                }

                // Collect included sources for averaging (move, not copy)
                let filtered: Vec<Vec<f32>> = kept_indices
                    .iter()
                    .map(|&i| std::mem::take(&mut sources[i]))
                    .collect();

                // Find reference in filtered set, compute correlation weights
                let ref_in_filtered = ref_source
                    .and_then(|ref_idx| kept_indices.iter().position(|&i| i == ref_idx))
                    .unwrap_or(0);
                let weights = combine::compute_source_weights(&filtered, ref_in_filtered);
                for (pos, (&kept_idx, &w)) in kept_indices.iter().zip(weights.iter()).enumerate() {
                    info!(
                        source = kept_idx,
                        weight = format!("{:.4}", w),
                        is_reference = (pos == ref_in_filtered),
                        "Combine weight (global)"
                    );
                }

                // Compute per-window quality weights for time-varying source quality
                let windowed_weights =
                    combine::compute_windowed_weights(&filtered, ref_in_filtered, sr);
                // Log per-window weight statistics
                for (pos, &kept_idx) in kept_indices.iter().enumerate() {
                    let nw = windowed_weights.num_windows();
                    if nw > 1 {
                        let min_w = (0..nw)
                            .map(|w| windowed_weights.window_weight(w, pos))
                            .fold(f32::MAX, f32::min);
                        let max_w = (0..nw)
                            .map(|w| windowed_weights.window_weight(w, pos))
                            .fold(f32::MIN, f32::max);
                        info!(
                            source = kept_idx,
                            windows = nw,
                            min_weight = format!("{:.4}", min_w),
                            max_weight = format!("{:.4}", max_w),
                            "Combine weight (windowed)"
                        );
                    }
                }

                // Detect signal onsets on aligned, filtered sources so that
                // silence-padded regions don't dilute the average.
                let onsets: Vec<usize> = filtered
                    .iter()
                    .map(|s| combine::detect_signal_onset(s, sr))
                    .collect();

                // CW mode uses windowed trimmed mean (20% trim) to reject
                // outlier spikes and gate out degraded sources per-window.
                // Other modes use windowed weighted average.
                let mut averaged = if combine_mode == "cw" {
                    combine::windowed_trimmed_mean_samples(
                        &filtered,
                        Some(&onsets),
                        0.20,
                        &windowed_weights,
                        combine::MIN_INCLUDE_WEIGHT,
                    )
                } else {
                    combine::windowed_weighted_average_samples(
                        &filtered,
                        &windowed_weights,
                        Some(&onsets),
                    )
                };

                // For CW mode, normalize the output so the signal is at a good
                // listening level. The bandpass has already isolated 400-900 Hz;
                // normalization amplifies weak signals without clipping.
                if combine_mode == "cw" {
                    combine::normalize_audio(&mut averaged, 0.9);
                }

                // Write via SegmentWriter
                let out_dir = data_dir.join(combined_id.to_string());
                let mut writer = SegmentWriter::new(&out_dir, combined_id, sr, segment_duration)?;
                writer.write_samples(&averaged)?;
                let seg_metas = writer.finalize()?;

                Ok::<_, RecordingError>((combined_id, seg_metas, kept_indices, audio_excluded))
            })
            .await
            .map_err(|e| RecordingError::DspError(format!("combine task panicked: {e}")))??;

        // Map indices back to original source UUIDs:
        // kept_indices/audio_excluded are indices into usable_indices,
        // which are indices into source_ids.
        let included_ids: Vec<Uuid> = kept_indices
            .iter()
            .map(|&i| source_ids[usable_indices[i]])
            .collect();
        let mut excluded = pre_excluded;
        for (i, reason) in &audio_excluded {
            excluded.push((source_ids[usable_indices[*i]], reason.clone()));
        }

        for (id, reason) in &excluded {
            warn!(recording = %id, reason = %reason, "Excluded from combine");
        }

        // Insert the combined recording and segments into DB
        let now = chrono::Utc::now();
        let rec_row = RecordingRow {
            id: combined_id,
            capture_id: None,
            sdr_id: "combined".into(),
            frequency: freq,
            bandwidth: recordings[0].bandwidth,
            mode: mode.clone(),
            status: "stopped".into(),
            started_at: recordings[0].started_at,
            stopped_at: Some(now),
            retention_days: retention_days as i64,
            created_at: now,
        };

        let db = self.db.lock().await;
        db.insert_recording(&rec_row)
            .map_err(|e| RecordingError::DspError(e.to_string()))?;

        for seg in &seg_metas {
            let seg_row = SegmentRow {
                id: Uuid::new_v4(),
                recording_id: combined_id,
                segment_number: seg.segment_number as i64,
                file_path: seg.file_path.to_string_lossy().into_owned(),
                duration_secs: seg.duration_secs,
                file_size_bytes: seg.file_size_bytes as i64,
                sample_rate,
                started_at: seg.started_at,
                ended_at: seg.ended_at,
                created_at: now,
            };
            db.insert_segment(&seg_row)
                .map_err(|e| RecordingError::DspError(e.to_string()))?;
        }

        info!(
            combined = %combined_id,
            included = included_ids.len(),
            excluded = excluded.len(),
            segments = seg_metas.len(),
            "Combined recording created"
        );

        Ok(CombineResult {
            combined_id,
            included_ids,
            excluded,
        })
    }
}

/// The actual recording task that runs in a tokio task.
#[allow(clippy::too_many_arguments)]
async fn recording_task(
    recording_id: Uuid,
    mut consumer: ConsumerHandle,
    mux: Arc<CaptureMultiplexer>,
    mut capture_request: CaptureRequest,
    rec_dir: PathBuf,
    segment_duration_secs: f64,
    output_sample_rate: u32,
    mut input_bandwidth: u32,
    mode: DemodMode,
    reference_time: Option<DateTime<Utc>>,
    db: Arc<Mutex<Database>>,
    mut cancel: tokio::sync::oneshot::Receiver<()>,
    mut retune_rx: tokio::sync::mpsc::Receiver<RetuneRequest>,
) -> Result<(), RecordingError> {
    // We set up the DSP chain lazily on first buffer (need input sample rate)
    let mut extractor: Option<NarrowbandExtractor> = None;
    let mut demodulator = Demodulator::new(mode, output_sample_rate);
    let mut seg_writer: Option<SegmentWriter> = None;
    let mut input_sample_rate: Option<u32> = None;
    /// Helper: flush current segments to DB.
    async fn flush_segments_to_db(
        writer: SegmentWriter,
        recording_id: Uuid,
        output_sample_rate: u32,
        db: &Arc<Mutex<Database>>,
    ) {
        match writer.finalize() {
            Ok(segments) => {
                let db = db.lock().await;
                for seg in &segments {
                    let seg_row = SegmentRow {
                        id: Uuid::new_v4(),
                        recording_id,
                        segment_number: seg.segment_number as i64,
                        file_path: seg.file_path.to_string_lossy().into_owned(),
                        duration_secs: seg.duration_secs,
                        file_size_bytes: seg.file_size_bytes as i64,
                        sample_rate: output_sample_rate as i64,
                        started_at: seg.started_at,
                        ended_at: seg.ended_at,
                        created_at: chrono::Utc::now(),
                    };
                    if let Err(e) = db.insert_segment(&seg_row) {
                        error!(recording = %recording_id, error = %e, "Failed to insert segment row");
                    }
                }
                info!(recording = %recording_id, segments = segments.len(), "Segments flushed to DB");
            }
            Err(e) => {
                error!(recording = %recording_id, error = %e, "Failed to finalize segments");
            }
        }
    }

    loop {
        tokio::select! {
            _ = &mut cancel => {
                info!(recording = %recording_id, "Recording cancelled");
                break;
            }
            retune = retune_rx.recv() => {
                if let Some(req) = retune {
                    info!(
                        recording = %recording_id,
                        new_freq = req.frequency,
                        "Retune: closing current segment and rebuilding DSP"
                    );

                    // Flush current segments to DB
                    if let Some(writer) = seg_writer.take() {
                        flush_segments_to_db(writer, recording_id, output_sample_rate, &db).await;
                    }

                    // Update bandwidth if provided
                    if let Some(bw) = req.bandwidth {
                        input_bandwidth = bw;
                    }

                    // Rebuild the extractor with new parameters
                    if let Some(in_rate) = input_sample_rate {
                        extractor = Some(NarrowbandExtractor::new(
                            in_rate,
                            0.0, // SDR is now retuned to the new frequency
                            input_bandwidth,
                            output_sample_rate,
                        ));
                    } else {
                        // Haven't received any buffers yet — will init lazily
                        extractor = None;
                    }

                    // Reset demodulator for clean filter state
                    demodulator = Demodulator::new(mode, output_sample_rate);

                    // Update capture request for reconnect
                    capture_request.frequency = req.frequency;
                    if let Some(bw) = req.bandwidth {
                        capture_request.bandwidth = bw;
                    }

                    // Update recording row in DB
                    {
                        let db_guard = db.lock().await;
                        let _ = db_guard.update_recording_frequency(
                            recording_id,
                            req.frequency as i64,
                        );
                    }

                    // New SegmentWriter will be created lazily on next buffer
                }
            }
            buf = consumer.recv() => {
                match buf {
                    Some(iq_buf) => {
                        // Lazy init on first buffer
                        if extractor.is_none() {
                            let in_rate = iq_buf.sample_rate;
                            input_sample_rate = Some(in_rate);
                            extractor = Some(NarrowbandExtractor::new(
                                in_rate,
                                0.0, // Already tuned to target frequency
                                input_bandwidth,
                                output_sample_rate,
                            ));
                        }
                        if seg_writer.is_none() {
                            let mut sw = SegmentWriter::new(
                                &rec_dir,
                                recording_id,
                                output_sample_rate,
                                segment_duration_secs,
                            )?;

                            // Pad silence from reference_time to first buffer for alignment
                            if let Some(ref_time) = reference_time {
                                let offset = iq_buf.timestamp.signed_duration_since(ref_time);
                                if offset.num_milliseconds() > 0 {
                                    let silence_samples = (offset
                                        .num_microseconds()
                                        .unwrap_or(0)
                                        as f64
                                        / 1_000_000.0
                                        * output_sample_rate as f64)
                                        as usize;
                                    // Cap at 120s to prevent runaway allocation
                                    let silence_samples =
                                        silence_samples.min(output_sample_rate as usize * 120);
                                    if silence_samples > 0 {
                                        let silence = vec![0.0f32; silence_samples];
                                        sw.write_samples(&silence)?;
                                    }
                                }
                                sw.set_segment_start(ref_time);
                            }

                            seg_writer = Some(sw);
                        }

                        // DSP pipeline: extract narrowband → demodulate → write
                        let ext = extractor.as_mut().unwrap();
                        let narrowband = ext.process(&iq_buf.samples);
                        let audio = demodulator.process(&narrowband);

                        if !audio.is_empty() {
                            seg_writer.as_mut().unwrap().write_samples(&audio)?;
                        }
                    }
                    None => {
                        warn!(recording = %recording_id, "IQ stream ended, attempting reconnect");
                        let mut attempt = 0u32;
                        let mut backoff_ms = INITIAL_BACKOFF_MS;
                        let reconnected = loop {
                            attempt += 1;
                            if attempt > MAX_RECONNECT_ATTEMPTS {
                                error!(recording = %recording_id, attempts = attempt - 1,
                                       "Max reconnect attempts reached, stopping");
                                break false;
                            }
                            info!(recording = %recording_id, attempt, "Reconnect attempt");
                            tokio::select! {
                                _ = &mut cancel => {
                                    info!(recording = %recording_id, "Cancelled during reconnect");
                                    break false;
                                }
                                result = mux.request_capture(capture_request.clone()) => {
                                    match result {
                                        Ok(new_consumer) => {
                                            info!(recording = %recording_id, attempt, "Reconnected");
                                            consumer = new_consumer;
                                            break true;
                                        }
                                        Err(e) => {
                                            warn!(recording = %recording_id, attempt, backoff_ms,
                                                  error = %e, "Reconnect failed, backing off");
                                        }
                                    }
                                }
                            }
                            tokio::select! {
                                _ = &mut cancel => {
                                    info!(recording = %recording_id, "Cancelled during backoff");
                                    break false;
                                }
                                _ = tokio::time::sleep(std::time::Duration::from_millis(backoff_ms)) => {}
                            }
                            backoff_ms = ((backoff_ms as f64) * BACKOFF_MULTIPLIER) as u64;
                            backoff_ms = backoff_ms.min(MAX_BACKOFF_MS);
                        };
                        if !reconnected {
                            break;
                        }
                    }
                }
            }
        }
    }

    // Finalize segments and record in DB
    if let Some(writer) = seg_writer {
        flush_segments_to_db(writer, recording_id, output_sample_rate, &db).await;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::DiscoverySection;
    use crate::sdr::discovery::SdrRegistry;
    use crate::sdr::mock::MockConfig;

    async fn test_engine() -> (RecordingEngine, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        let db = Database::open_in_memory().unwrap();

        // Insert a mock SDR row so foreign keys work
        let now = chrono::Utc::now();
        db.upsert_sdr(&crate::db::models::SdrRow {
            id: "mock-1".into(),
            driver: "mock".into(),
            label: None,
            serial: None,
            url: None,
            sample_rate: None,
            antenna: None,
            last_seen: now,
            created_at: now,
        })
        .unwrap();

        let db = Arc::new(Mutex::new(db));

        let registry = Arc::new(SdrRegistry::new(DiscoverySection::default()));
        registry
            .add_mock(
                "mock-1",
                MockConfig {
                    tones: vec![(800.0, 0.8)],
                    noise_amplitude: 0.01,
                    buffer_size: 4096,
                    buffer_interval_ms: 20,
                },
            )
            .await;

        let mux = Arc::new(CaptureMultiplexer::new(registry, 30));
        let data_dir = dir.path().join("recordings");

        let engine = RecordingEngine::new(mux, db, data_dir, 1.0); // 1-second segments for fast test
        (engine, dir)
    }

    #[tokio::test]
    async fn full_pipeline_start_stop_verify() {
        let (engine, _dir) = test_engine().await;

        let params = RecordingParams {
            sdr_id: Some(SdrId::from("mock-1")),
            frequency: 7_030_000,
            bandwidth: 2_400,
            mode: DemodMode::Cw,
            output_sample_rate: 12_000,
            retention_days: 30,
            reference_time: None,
        };

        let rec_id = engine.start_recording(params).await.unwrap();
        assert_eq!(engine.active_recordings().await.len(), 1);

        // Let it record for a bit (should produce at least 1 segment at 1s duration)
        tokio::time::sleep(std::time::Duration::from_millis(1500)).await;

        engine.stop_recording(rec_id).await.unwrap();
        assert_eq!(engine.active_recordings().await.len(), 0);

        // Check DB has the recording
        let db = engine.db.lock().await;
        let rec = db.get_recording(rec_id).unwrap();
        assert_eq!(rec.status, "stopped");

        // Check segments were written
        let segments = db.list_segments(rec_id).unwrap();
        assert!(!segments.is_empty(), "Expected at least one segment");

        // Verify segment files exist on disk
        for seg in &segments {
            let path = std::path::Path::new(&seg.file_path);
            assert!(
                path.exists(),
                "Segment file should exist: {}",
                seg.file_path
            );
        }
    }

    #[tokio::test]
    async fn recording_retune_creates_new_segment() {
        let (engine, _dir) = test_engine().await;

        let params = RecordingParams {
            sdr_id: Some(SdrId::from("mock-1")),
            frequency: 7_030_000,
            bandwidth: 2_400,
            mode: DemodMode::Cw,
            output_sample_rate: 12_000,
            retention_days: 30,
            reference_time: None,
        };

        let rec_id = engine.start_recording(params).await.unwrap();

        // Let it record long enough to have some audio (segment duration is 1s)
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        // Retune to a different frequency
        engine
            .retune_recording(rec_id, 14_060_000, None)
            .await
            .unwrap();

        // Let it record at the new frequency
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        engine.stop_recording(rec_id).await.unwrap();

        // Check that the recording has segments and the DB frequency updated
        let db = engine.db.lock().await;
        let rec = db.get_recording(rec_id).unwrap();
        assert_eq!(rec.frequency, 14_060_000, "DB frequency should be updated");

        let segments = db.list_segments(rec_id).unwrap();
        assert!(
            !segments.is_empty(),
            "Should have at least one segment after retune"
        );

        // Verify all segment files exist on disk
        for seg in &segments {
            let path = std::path::Path::new(&seg.file_path);
            assert!(
                path.exists(),
                "Segment file should exist: {}",
                seg.file_path
            );
        }
    }

    #[tokio::test]
    async fn retune_nonexistent_recording_fails() {
        let (engine, _dir) = test_engine().await;

        let result = engine
            .retune_recording(Uuid::new_v4(), 14_060_000, None)
            .await;
        assert!(
            result.is_err(),
            "Retune of non-existent recording should fail"
        );
    }
}
