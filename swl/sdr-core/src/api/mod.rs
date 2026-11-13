pub mod captures;
pub mod health;
pub mod recordings;
pub mod sdrs;
pub mod transcriptions;
pub mod uploads;

use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::DefaultBodyLimit;
use axum::response::{Html, IntoResponse};
use axum::routing::{get, post};
use axum::Router;
use tokio::sync::Mutex;
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::ServeDir;

use crate::db::Database;
use crate::mux::CaptureMultiplexer;
use crate::recording::RecordingEngine;
use crate::sdr::discovery::SdrRegistry;
use crate::transcription::TranscriptionEngine;

/// Shared application state for all API handlers.
pub struct AppState {
    pub registry: Arc<SdrRegistry>,
    pub mux: Arc<CaptureMultiplexer>,
    pub recording_engine: Arc<RecordingEngine>,
    pub transcription_engine: Arc<TranscriptionEngine>,
    pub db: Arc<Mutex<Database>>,
    pub web_dir: Option<PathBuf>,
    /// Base directory for data storage (recordings, uploads, etc.).
    data_dir: PathBuf,
}

impl AppState {
    pub fn new(
        registry: Arc<SdrRegistry>,
        mux: Arc<CaptureMultiplexer>,
        recording_engine: Arc<RecordingEngine>,
        transcription_engine: Arc<TranscriptionEngine>,
        db: Arc<Mutex<Database>>,
        web_dir: Option<PathBuf>,
        data_dir: PathBuf,
    ) -> Self {
        Self {
            registry,
            mux,
            recording_engine,
            transcription_engine,
            db,
            web_dir,
            data_dir,
        }
    }

    pub fn data_dir(&self) -> &PathBuf {
        &self.data_dir
    }
}

/// Build the axum router with all M0 endpoints.
pub fn router(state: Arc<AppState>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let mut app = Router::new()
        // Health
        .route("/api/v1/health", get(health::health))
        // SDRs
        .route("/api/v1/sdrs", get(sdrs::list_sdrs))
        .route("/api/v1/sdrs/search", get(sdrs::search_sdrs))
        .route("/api/v1/sdrs/{id}", get(sdrs::get_sdr))
        .route("/api/v1/sdrs/scan", post(sdrs::scan_sdrs))
        // Captures
        .route("/api/v1/captures", get(captures::list_captures))
        .route("/api/v1/captures/{id}", get(captures::get_capture))
        // Recordings
        .route(
            "/api/v1/recordings",
            get(recordings::list_recordings).post(recordings::create_recording),
        )
        .route(
            "/api/v1/recordings/combine",
            post(recordings::combine_recordings),
        )
        .route(
            "/api/v1/recordings/{id}",
            get(recordings::get_recording).delete(recordings::delete_recording),
        )
        .route(
            "/api/v1/recordings/{id}/stop",
            post(recordings::stop_recording),
        )
        .route(
            "/api/v1/recordings/{id}/retune",
            post(recordings::retune_recording),
        )
        .route(
            "/api/v1/recordings/{id}/segments/{num}/audio",
            get(recordings::get_segment_audio),
        )
        // Uploads (500 MB limit for audio files)
        .route(
            "/api/v1/recordings/upload",
            post(uploads::upload_recording).layer(DefaultBodyLimit::max(500 * 1024 * 1024)),
        )
        // Transcriptions
        .route(
            "/api/v1/transcriptions",
            get(transcriptions::list_transcriptions).post(transcriptions::create_transcription),
        )
        .route(
            "/api/v1/transcriptions/{id}",
            get(transcriptions::get_transcription).delete(transcriptions::delete_transcription),
        )
        .with_state(state.clone())
        .layer(cors);

    // Serve SPA static files if web dir exists
    if let Some(ref web_dir) = state.web_dir {
        let dist_dir = web_dir.join("dist");
        if dist_dir.exists() {
            let index_path = dist_dir.join("index.html");
            app = app
                .nest_service("/assets", ServeDir::new(dist_dir.join("assets")))
                .fallback(move |req: axum::http::Request<axum::body::Body>| {
                    spa_fallback(req, index_path)
                });
        }
    }

    app
}

async fn spa_fallback(
    req: axum::http::Request<axum::body::Body>,
    index_path: std::path::PathBuf,
) -> impl IntoResponse {
    // Don't intercept /api requests — return 404 for unknown API paths
    if req.uri().path().starts_with("/api/") {
        return (axum::http::StatusCode::NOT_FOUND, Html(String::new())).into_response();
    }

    if let Ok(html) = tokio::fs::read_to_string(&index_path).await {
        return Html(html).into_response();
    }

    (
        axum::http::StatusCode::NOT_FOUND,
        Html("Not found".to_string()),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::DiscoverySection;
    use crate::recording::audio_decode;

    /// Build a test AppState with an in-memory DB and temp data directory.
    fn test_state(tmp_dir: &std::path::Path) -> Arc<AppState> {
        let db = crate::db::Database::open_in_memory().unwrap();
        let db = Arc::new(Mutex::new(db));
        let registry = Arc::new(crate::sdr::discovery::SdrRegistry::new(
            DiscoverySection::default(),
        ));
        let mux = Arc::new(crate::mux::CaptureMultiplexer::new(
            Arc::clone(&registry),
            30,
        ));
        let recording_engine = Arc::new(crate::recording::RecordingEngine::new(
            Arc::clone(&mux),
            Arc::clone(&db),
            tmp_dir.to_path_buf(),
            300.0,
        ));
        let transcription_engine =
            Arc::new(crate::transcription::TranscriptionEngine::with_data_dir(
                Arc::clone(&db),
                tmp_dir.to_path_buf(),
            ));
        Arc::new(AppState::new(
            registry,
            mux,
            recording_engine,
            transcription_engine,
            db,
            None,
            tmp_dir.to_path_buf(),
        ))
    }

    /// Generate a small WAV file in memory (1 second of 600 Hz tone).
    fn test_wav_bytes() -> Vec<u8> {
        let sample_rate = 8000u32;
        let samples: Vec<f32> = (0..8000)
            .map(|i| (2.0 * std::f32::consts::PI * 600.0 * i as f32 / sample_rate as f32).sin())
            .collect();
        let tmp = tempfile::NamedTempFile::new().unwrap();
        audio_decode::write_wav(tmp.path(), sample_rate, &samples).unwrap();
        std::fs::read(tmp.path()).unwrap()
    }

    #[tokio::test]
    async fn upload_wav_returns_201() {
        let tmp = tempfile::tempdir().unwrap();
        let state = test_state(tmp.path());
        let app = router(state);
        let server = axum_test::TestServer::new(app).expect("failed to create test server");

        let wav_bytes = test_wav_bytes();
        let part = axum_test::multipart::Part::bytes(wav_bytes).file_name("test.wav");
        let form = axum_test::multipart::MultipartForm::new().add_part("file", part);

        let resp = server
            .post("/api/v1/recordings/upload")
            .multipart(form)
            .await;
        resp.assert_status(axum::http::StatusCode::CREATED);

        let body: serde_json::Value = resp.json();
        assert!(body.get("id").is_some(), "response should contain id");
    }

    #[tokio::test]
    async fn upload_no_file_returns_400() {
        let tmp = tempfile::tempdir().unwrap();
        let state = test_state(tmp.path());
        let app = router(state);
        let server = axum_test::TestServer::new(app).expect("failed to create test server");

        let form = axum_test::multipart::MultipartForm::new();
        let resp = server
            .post("/api/v1/recordings/upload")
            .multipart(form)
            .await;
        resp.assert_status(axum::http::StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn transcription_async_flow() {
        let tmp = tempfile::tempdir().unwrap();
        let state = test_state(tmp.path());
        let app = router(state);
        let server = axum_test::TestServer::new(app).expect("failed to create test server");

        // 1. Upload a WAV file
        let wav_bytes = test_wav_bytes();
        let part = axum_test::multipart::Part::bytes(wav_bytes).file_name("test.wav");
        let form = axum_test::multipart::MultipartForm::new().add_part("file", part);

        let upload_resp = server
            .post("/api/v1/recordings/upload")
            .multipart(form)
            .await;
        upload_resp.assert_status(axum::http::StatusCode::CREATED);
        let upload_body: serde_json::Value = upload_resp.json();
        let recording_id = upload_body["id"].as_str().unwrap();

        // 2. Start transcription → 202
        let tx_resp = server
            .post("/api/v1/transcriptions")
            .json(&serde_json::json!({ "recording_id": recording_id }))
            .await;
        tx_resp.assert_status(axum::http::StatusCode::ACCEPTED);
        let tx_body: serde_json::Value = tx_resp.json();
        let tx_id = tx_body["id"].as_str().unwrap();

        // 3. Poll until completed (with timeout)
        let mut completed = false;
        for _ in 0..50 {
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;

            let poll = server.get(&format!("/api/v1/transcriptions/{tx_id}")).await;
            poll.assert_status(axum::http::StatusCode::OK);
            let poll_body: serde_json::Value = poll.json();

            let status = poll_body["status"].as_str().unwrap_or("");
            if status == "completed" {
                // Verify response shape
                assert!(poll_body.get("progress").is_some());
                assert!(poll_body.get("transcript").is_some());
                assert!(poll_body.get("error_message").is_some());

                // Verify transcript has camelCase keys
                if let Some(transcript) = poll_body.get("transcript") {
                    assert!(
                        transcript.get("recordingId").is_some(),
                        "transcript should have recordingId"
                    );
                    assert!(
                        transcript.get("lines").is_some(),
                        "transcript should have lines"
                    );
                    assert!(
                        transcript.get("detectedQSORanges").is_some(),
                        "transcript should have detectedQSORanges"
                    );
                    assert!(
                        transcript.get("averageWPM").is_some(),
                        "transcript should have averageWPM"
                    );
                }

                completed = true;
                break;
            } else if status == "failed" {
                panic!(
                    "transcription failed: {}",
                    poll_body["error_message"].as_str().unwrap_or("unknown")
                );
            }
        }
        assert!(completed, "transcription should complete within 10 seconds");
    }
}
