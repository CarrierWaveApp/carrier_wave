use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;

use crate::mux::CaptureSessionInfo;

use super::AppState;

pub async fn list_captures(State(state): State<Arc<AppState>>) -> Json<Vec<CaptureSessionInfo>> {
    let sessions = state.mux.list_sessions().await;
    Json(sessions)
}

pub async fn get_capture(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<CaptureSessionInfo>, StatusCode> {
    let uuid = uuid::Uuid::parse_str(&id).map_err(|_| StatusCode::BAD_REQUEST)?;
    let sessions = state.mux.list_sessions().await;
    sessions
        .into_iter()
        .find(|s| s.id == uuid)
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}
