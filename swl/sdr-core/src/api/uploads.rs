use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::{Multipart, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::Utc;
use serde::Serialize;
use uuid::Uuid;

use crate::db::models::UploadedRecordingRow;
use crate::recording::audio_decode;

use super::AppState;

#[derive(Serialize)]
pub struct UploadResponse {
    pub id: Uuid,
}

/// POST /api/v1/recordings/upload
///
/// Accepts a multipart/form-data upload with a `file` field.
/// Decodes the audio to WAV and stores metadata in the database.
pub async fn upload_recording(
    State(state): State<Arc<AppState>>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<UploadResponse>), (StatusCode, String)> {
    // Extract the file field from multipart
    let mut file_data: Option<(String, Vec<u8>)> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("multipart error: {e}")))?
    {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" {
            let filename = field.file_name().unwrap_or("recording.wav").to_string();
            let data = field
                .bytes()
                .await
                .map_err(|e| (StatusCode::BAD_REQUEST, format!("read error: {e}")))?;
            file_data = Some((filename, data.to_vec()));
            break;
        }
    }

    let (filename, data) =
        file_data.ok_or_else(|| (StatusCode::BAD_REQUEST, "no file field in upload".into()))?;

    // Determine format from extension
    let ext = std::path::Path::new(&filename)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("wav")
        .to_lowercase();

    let supported = ["wav", "caf", "m4a", "aac", "aiff", "aif"];
    if !supported.contains(&ext.as_str()) {
        return Err((
            StatusCode::BAD_REQUEST,
            format!("unsupported format: {ext}"),
        ));
    }

    let upload_id = Uuid::new_v4();
    let data_dir = state.data_dir();
    let upload_dir = data_dir.join("uploads").join(upload_id.to_string());

    // Create upload directory
    tokio::fs::create_dir_all(&upload_dir).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("failed to create upload dir: {e}"),
        )
    })?;

    // Save original file
    let original_path = upload_dir.join(format!("original.{ext}"));
    tokio::fs::write(&original_path, &data).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("failed to save file: {e}"),
        )
    })?;

    // Decode to PCM (blocking — run in spawn_blocking)
    let orig_path_clone = original_path.clone();
    let (sample_rate, samples) =
        tokio::task::spawn_blocking(move || audio_decode::decode_to_pcm(&orig_path_clone))
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("decode task panicked: {e}"),
                )
            })?
            .map_err(|e| {
                (
                    StatusCode::UNPROCESSABLE_ENTITY,
                    format!("failed to decode audio: {e}"),
                )
            })?;

    let duration_secs = samples.len() as f64 / sample_rate as f64;

    // Write decoded WAV
    let decoded_path = upload_dir.join("decoded.wav");
    let decoded_path_clone = decoded_path.clone();
    let samples_clone = samples;
    tokio::task::spawn_blocking(move || {
        audio_decode::write_wav(&decoded_path_clone, sample_rate, &samples_clone)
    })
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("wav write task panicked: {e}"),
        )
    })?
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("failed to write decoded wav: {e}"),
        )
    })?;

    // Insert into database
    let row = UploadedRecordingRow {
        id: upload_id,
        original_filename: filename,
        original_format: ext,
        sample_rate: Some(sample_rate as i64),
        duration_secs: Some(duration_secs),
        status: "decoded".to_string(),
        error_message: None,
        created_at: Utc::now(),
    };

    let db = state.db.lock().await;
    db.insert_uploaded_recording(&row)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("db error: {e}")))?;

    tracing::info!(
        id = %upload_id,
        filename = %row.original_filename,
        sample_rate = sample_rate,
        duration_secs = format!("{:.1}", duration_secs),
        "Upload complete"
    );

    Ok((StatusCode::CREATED, Json(UploadResponse { id: upload_id })))
}

/// Helper to get the uploads directory for a given upload ID.
pub fn upload_dir(data_dir: &std::path::Path, upload_id: Uuid) -> PathBuf {
    data_dir.join("uploads").join(upload_id.to_string())
}
