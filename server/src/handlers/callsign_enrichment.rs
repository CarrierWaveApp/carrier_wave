//! Public read endpoints for callsign enrichment data.
//!
//! Two surfaces:
//!   - `GET /callsign-enrichment/dataset` — full dump of every (callsign,
//!     source) row plus per-source metadata, intended for clients that want
//!     to cache the entire list locally for fast lookup. Supports `If-None-
//!     Match` against the most-recent fetch timestamp baked into the ETag.
//!   - `GET /callsign-enrichment/{callsign}` — single-callsign lookup for
//!     ad-hoc queries / debugging. Always uppercases the input.

use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::Response,
};
use sqlx::PgPool;

use crate::db::callsign_enrichment as db_enrichment;
use crate::error::AppError;
use crate::models::callsign_enrichment::{
    EnrichmentDataset, EnrichmentDatasetEntry, EnrichmentDatasetMembership, EnrichmentDatasetSource,
    EnrichmentMembership, EnrichmentResponse,
};

pub async fn get_callsign_enrichment(
    State(pool): State<PgPool>,
    Path(callsign): Path<String>,
) -> Result<Json<EnrichmentResponse>, AppError> {
    let upper = callsign.to_uppercase();
    let rows = db_enrichment::lookup_callsign(&pool, &upper).await?;

    let memberships = rows
        .into_iter()
        .map(|r| EnrichmentMembership {
            source_slug: r.source_slug,
            source_name: r.source_name,
            emoji: r.emoji.or(r.source_emoji),
            name: r.name,
            member_number: r.member_number,
            note: r.note,
        })
        .collect();

    Ok(Json(EnrichmentResponse {
        callsign: upper,
        memberships,
    }))
}

pub async fn get_callsign_enrichment_dataset(
    State(pool): State<PgPool>,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    let generated_at = db_enrichment::most_recent_fetch(&pool)
        .await?
        .unwrap_or_else(chrono::Utc::now);
    let etag_value = format!("\"cwe-{}\"", generated_at.timestamp_millis());

    if let Some(if_none_match) = headers.get(header::IF_NONE_MATCH) {
        if if_none_match.to_str().ok() == Some(etag_value.as_str()) {
            let mut resp = Response::new(axum::body::Body::empty());
            *resp.status_mut() = StatusCode::NOT_MODIFIED;
            if let Ok(value) = HeaderValue::from_str(&etag_value) {
                resp.headers_mut().insert(header::ETAG, value);
            }
            return Ok(resp);
        }
    }

    let sources = db_enrichment::list_all_sources_for_dataset(&pool)
        .await?
        .into_iter()
        .map(
            |(slug, name, emoji, last_fetched_at)| EnrichmentDatasetSource {
                slug,
                name,
                emoji,
                last_fetched_at,
            },
        )
        .collect::<Vec<_>>();

    let rows = db_enrichment::fetch_full_dataset(&pool).await?;

    // Group rows by callsign in one pass (input is already ordered by callsign).
    let mut callsigns: Vec<EnrichmentDatasetEntry> = Vec::new();
    let mut current: Option<EnrichmentDatasetEntry> = None;
    for row in rows {
        let m = EnrichmentDatasetMembership {
            source_slug: row.source_slug,
            name: row.name,
            member_number: row.member_number,
            emoji: row.emoji,
            note: row.note,
        };
        match current.as_mut() {
            Some(cur) if cur.callsign == row.callsign => {
                cur.memberships.push(m);
            }
            _ => {
                if let Some(prev) = current.take() {
                    callsigns.push(prev);
                }
                current = Some(EnrichmentDatasetEntry {
                    callsign: row.callsign,
                    memberships: vec![m],
                });
            }
        }
    }
    if let Some(last) = current.take() {
        callsigns.push(last);
    }

    let dataset = EnrichmentDataset {
        sources,
        callsigns,
        generated_at,
    };

    let body = serde_json::to_vec(&dataset).map_err(|e| AppError::Internal(e.to_string()))?;
    let mut resp = Response::new(axum::body::Body::from(body));
    resp.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/json"),
    );
    if let Ok(value) = HeaderValue::from_str(&etag_value) {
        resp.headers_mut().insert(header::ETAG, value);
    }
    resp.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=3600"),
    );
    Ok(resp)
}
