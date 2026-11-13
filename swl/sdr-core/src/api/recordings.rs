use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio_util::io::ReaderStream;

use crate::db::models::{RecordingRow, SegmentRow};
use crate::recording::RecordingParams;
use crate::types::{DemodMode, SdrId};

use super::AppState;

#[derive(Deserialize)]
pub struct CreateRecordingRequest {
    pub frequency: u64,
    #[serde(default = "default_bandwidth")]
    pub bandwidth: u32,
    pub mode: DemodMode,
    #[serde(default)]
    pub sdr_id: Option<String>,
    #[serde(default = "default_output_sample_rate")]
    pub output_sample_rate: u32,
    #[serde(default = "default_retention")]
    pub retention_days: u32,
    /// Optional reference time for multi-SDR alignment (ISO 8601).
    #[serde(default)]
    pub reference_time: Option<DateTime<Utc>>,
}

fn default_bandwidth() -> u32 {
    500
}
fn default_output_sample_rate() -> u32 {
    12_000
}
fn default_retention() -> u32 {
    30
}

#[derive(Serialize)]
pub struct CreateRecordingResponse {
    pub id: uuid::Uuid,
}

pub async fn create_recording(
    State(state): State<Arc<AppState>>,
    Json(req): Json<CreateRecordingRequest>,
) -> Result<(StatusCode, Json<CreateRecordingResponse>), (StatusCode, String)> {
    let params = RecordingParams {
        sdr_id: req.sdr_id.map(|s| SdrId::from(s.as_str())),
        frequency: req.frequency,
        bandwidth: req.bandwidth,
        mode: req.mode,
        output_sample_rate: req.output_sample_rate,
        retention_days: req.retention_days,
        reference_time: req.reference_time,
    };

    match state.recording_engine.start_recording(params).await {
        Ok(id) => Ok((StatusCode::CREATED, Json(CreateRecordingResponse { id }))),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

#[derive(Serialize)]
pub struct RecordingResponse {
    #[serde(flatten)]
    pub recording: RecordingRow,
    pub segments: Vec<SegmentRow>,
}

pub async fn get_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<RecordingResponse>, StatusCode> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|_| StatusCode::BAD_REQUEST)?;
    let db = state.db.lock().await;

    let recording = db.get_recording(uuid).map_err(|_| StatusCode::NOT_FOUND)?;
    let segments = db.list_segments(uuid).unwrap_or_default();

    Ok(Json(RecordingResponse {
        recording,
        segments,
    }))
}

pub async fn list_recordings(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<RecordingRow>>, StatusCode> {
    let db = state.db.lock().await;
    let recordings = db
        .list_recordings(None)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(recordings))
}

pub async fn stop_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    let uuid = uuid::Uuid::parse_str(&id)
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid recording ID".into()))?;

    state
        .recording_engine
        .stop_recording(uuid)
        .await
        .map_err(|e| (StatusCode::NOT_FOUND, e.to_string()))?;

    Ok(StatusCode::NO_CONTENT)
}

pub async fn delete_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    let uuid =
        uuid::Uuid::parse_str(&id).map_err(|_| (StatusCode::BAD_REQUEST, "invalid id".into()))?;

    // Stop the recording if active
    let _ = state.recording_engine.stop_recording(uuid).await;

    // Delete from DB
    let db = state.db.lock().await;
    db.delete_recording(uuid)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct CombineRecordingsRequest {
    pub source_recording_ids: Vec<String>,
    #[serde(default = "default_retention")]
    pub retention_days: u32,
    /// Skip quality filtering (dead receiver / correlation checks).
    #[serde(default)]
    pub skip_quality_filter: bool,
}

#[derive(Serialize)]
pub struct ExcludedRecording {
    pub id: uuid::Uuid,
    pub reason: String,
}

#[derive(Serialize)]
pub struct CombineRecordingsResponse {
    pub id: uuid::Uuid,
    pub source_count: usize,
    pub included_count: usize,
    pub segments: usize,
    pub excluded: Vec<ExcludedRecording>,
}

pub async fn combine_recordings(
    State(state): State<Arc<AppState>>,
    Json(req): Json<CombineRecordingsRequest>,
) -> Result<(StatusCode, Json<CombineRecordingsResponse>), (StatusCode, String)> {
    let source_count = req.source_recording_ids.len();
    let source_ids: Vec<uuid::Uuid> = req
        .source_recording_ids
        .iter()
        .map(|s| {
            uuid::Uuid::parse_str(s)
                .map_err(|_| (StatusCode::BAD_REQUEST, format!("invalid UUID: {s}")))
        })
        .collect::<Result<Vec<_>, _>>()?;

    let result = state
        .recording_engine
        .combine_recordings(source_ids, req.retention_days, req.skip_quality_filter)
        .await
        .map_err(|e| {
            let status = match &e {
                crate::error::RecordingError::NotFound(_) => StatusCode::NOT_FOUND,
                crate::error::RecordingError::Incompatible(_) => StatusCode::BAD_REQUEST,
                _ => StatusCode::INTERNAL_SERVER_ERROR,
            };
            (status, e.to_string())
        })?;

    let segment_count = {
        let db = state.db.lock().await;
        db.list_segments(result.combined_id)
            .unwrap_or_default()
            .len()
    };

    let excluded: Vec<ExcludedRecording> = result
        .excluded
        .into_iter()
        .map(|(id, reason)| ExcludedRecording { id, reason })
        .collect();

    Ok((
        StatusCode::CREATED,
        Json(CombineRecordingsResponse {
            id: result.combined_id,
            source_count,
            included_count: result.included_ids.len(),
            segments: segment_count,
            excluded,
        }),
    ))
}

#[derive(Deserialize)]
pub struct RetuneRecordingRequest {
    pub frequency: u64,
    #[serde(default)]
    pub bandwidth: Option<u32>,
}

pub async fn retune_recording(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Json(req): Json<RetuneRecordingRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let uuid = uuid::Uuid::parse_str(&id)
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid recording ID".into()))?;

    state
        .recording_engine
        .retune_recording(uuid, req.frequency, req.bandwidth)
        .await
        .map_err(|e| {
            let status = match &e {
                crate::error::RecordingError::NotFound(_) => StatusCode::NOT_FOUND,
                _ => StatusCode::INTERNAL_SERVER_ERROR,
            };
            (status, e.to_string())
        })?;

    Ok(StatusCode::NO_CONTENT)
}

pub async fn get_segment_audio(
    State(state): State<Arc<AppState>>,
    Path((rec_id, seg_num)): Path<(String, i64)>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    let uuid = uuid::Uuid::parse_str(&rec_id).map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            format!("invalid recording id: {rec_id}"),
        )
    })?;
    let db = state.db.lock().await;

    let segment = db.get_segment(uuid, seg_num).map_err(|_| {
        (
            StatusCode::NOT_FOUND,
            format!("segment {seg_num} not found in database for recording {uuid}"),
        )
    })?;

    let path = std::path::Path::new(&segment.file_path);
    if !path.exists() {
        return Err((
            StatusCode::NOT_FOUND,
            format!("segment file missing from disk: {}", segment.file_path),
        ));
    }

    let file = tokio::fs::File::open(path).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("failed to open segment file: {e}"),
        )
    })?;

    let stream = ReaderStream::new(file);
    let body = Body::from_stream(stream);

    Ok((
        [
            (header::CONTENT_TYPE, "audio/wav"),
            (header::CONTENT_DISPOSITION, "inline"),
        ],
        body,
    ))
}
