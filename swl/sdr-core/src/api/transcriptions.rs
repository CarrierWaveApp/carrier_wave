use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db::models::TranscriptionRow;
use crate::transcription::TranscriptionEngine;

use super::AppState;

#[derive(Deserialize)]
pub struct CreateTranscriptionRequest {
    pub recording_id: String,
    /// Decoder to use: "legacy", "decoder-a", "ensemble", or "auto" (default).
    /// "auto" currently selects "decoder-a".
    pub decoder: Option<String>,
}

/// Legacy response used for list/create (backward compat with web UI).
#[derive(Serialize)]
pub struct TranscriptionResponse {
    pub id: uuid::Uuid,
    pub recording_id: Option<uuid::Uuid>,
    pub text: String,
    pub status: String,
    pub wpm_estimate: Option<f64>,
    pub char_count: i64,
    pub error_message: Option<String>,
}

impl From<TranscriptionRow> for TranscriptionResponse {
    fn from(row: TranscriptionRow) -> Self {
        Self {
            id: row.id,
            recording_id: row.recording_id,
            text: row.text,
            status: row.status,
            wpm_estimate: row.wpm_estimate,
            char_count: row.char_count,
            error_message: row.error_message,
        }
    }
}

/// Response for GET /api/v1/transcriptions/{id} — matches iOS `TranscriptionStatusResponse`.
///
/// Uses snake_case for the outer envelope (iOS CodingKeys maps explicitly).
/// The nested `transcript` field contains camelCase JSON (from StructuredTranscript serde).
#[derive(Serialize)]
pub struct TranscriptionStatusResponse {
    pub status: String,
    pub progress: Option<f64>,
    /// Structured transcript JSON (camelCase keys inside).
    pub transcript: Option<serde_json::Value>,
    pub error_message: Option<String>,
}

/// Minimal response for async transcription creation.
#[derive(Serialize)]
pub struct AsyncTranscriptionCreated {
    pub id: uuid::Uuid,
}

pub async fn create_transcription(
    State(state): State<Arc<AppState>>,
    Json(req): Json<CreateTranscriptionRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, String)> {
    let recording_id = uuid::Uuid::parse_str(&req.recording_id)
        .map_err(|_| (StatusCode::BAD_REQUEST, "invalid recording_id".into()))?;

    // Check if this is an uploaded recording (async path)
    let is_upload = {
        let db = state.db.lock().await;
        db.get_uploaded_recording(recording_id).is_ok()
    };

    // Resolve decoder from request (default: engine's built-in decoder)
    let decoder_override = req
        .decoder
        .as_deref()
        .map(TranscriptionEngine::resolve_decoder);

    if is_upload {
        // Async path for uploaded recordings
        let tx_id = state
            .transcription_engine
            .start_transcription_async_with_decoder(recording_id, decoder_override)
            .await
            .map_err(|e| {
                let status = match &e {
                    crate::error::TranscriptionError::NotFound(_) => StatusCode::NOT_FOUND,
                    crate::error::TranscriptionError::InvalidRecording(_) => {
                        StatusCode::BAD_REQUEST
                    }
                    _ => StatusCode::INTERNAL_SERVER_ERROR,
                };
                (status, e.to_string())
            })?;

        let resp = AsyncTranscriptionCreated { id: tx_id };
        Ok((
            StatusCode::ACCEPTED,
            Json(serde_json::to_value(resp).unwrap()),
        ))
    } else {
        // Sync path for server recordings (backward compat)
        let result = state
            .transcription_engine
            .transcribe_recording(recording_id)
            .await
            .map_err(|e| {
                let status = match &e {
                    crate::error::TranscriptionError::NotFound(_) => StatusCode::NOT_FOUND,
                    crate::error::TranscriptionError::InvalidRecording(_) => {
                        StatusCode::BAD_REQUEST
                    }
                    _ => StatusCode::INTERNAL_SERVER_ERROR,
                };
                (status, e.to_string())
            })?;

        let db = state.db.lock().await;
        let row = db.get_transcription(result.id).map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("failed to fetch transcription: {e}"),
            )
        })?;

        let resp = TranscriptionResponse::from(row);
        Ok((
            StatusCode::CREATED,
            Json(serde_json::to_value(resp).unwrap()),
        ))
    }
}

pub async fn list_transcriptions(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<TranscriptionResponse>>, StatusCode> {
    let db = state.db.lock().await;
    let rows = db
        .list_transcriptions()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(
        rows.into_iter().map(TranscriptionResponse::from).collect(),
    ))
}

/// GET /api/v1/transcriptions/{id}
///
/// Returns `TranscriptionStatusResponse` matching the iOS client contract.
pub async fn get_transcription(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<TranscriptionStatusResponse>, StatusCode> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|_| StatusCode::BAD_REQUEST)?;

    let db = state.db.lock().await;
    let row = db
        .get_transcription(uuid)
        .map_err(|_| StatusCode::NOT_FOUND)?;

    // Check in-flight progress
    let progress = if row.status == "in_progress" {
        state
            .transcription_engine
            .get_progress(uuid)
            .map(|p| p as f64 / 100.0)
            .or(row.progress)
    } else if row.status == "completed" {
        Some(1.0)
    } else {
        row.progress
    };

    // Parse structured transcript if available
    let transcript = row
        .structured_transcript
        .as_deref()
        .and_then(|s| serde_json::from_str::<serde_json::Value>(s).ok());

    Ok(Json(TranscriptionStatusResponse {
        status: row.status,
        progress,
        transcript,
        error_message: row.error_message,
    }))
}

pub async fn delete_transcription(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    let uuid =
        uuid::Uuid::parse_str(&id).map_err(|_| (StatusCode::BAD_REQUEST, "invalid id".into()))?;
    let db = state.db.lock().await;
    db.delete_transcription(uuid)
        .map_err(|e| (StatusCode::NOT_FOUND, e.to_string()))?;
    Ok(StatusCode::NO_CONTENT)
}
