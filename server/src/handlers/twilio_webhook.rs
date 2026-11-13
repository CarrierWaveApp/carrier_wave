use axum::{
    extract::State,
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    Extension,
};
use sqlx::PgPool;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::spot_marker::{
    ParsedSpotMessage, SpotMarkerResponse, SpotType, TwilioSmsWebhook,
};

use super::DataResponse;

/// POST /v1/spot-markers — generate a spot marker for SMS spotting (auth required).
pub async fn create_spot_marker(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
) -> Result<(StatusCode, Json<DataResponse<SpotMarkerResponse>>), AppError> {
    let row = db::spot_markers::create_spot_marker(&pool, &auth.callsign, auth.participant_id)
        .await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: SpotMarkerResponse {
                marker: row.marker,
                callsign: row.callsign,
                created_at: row.created_at,
            },
        }),
    ))
}

/// POST /v1/twilio/sms — Twilio webhook for incoming SMS spot messages.
///
/// SMS format: `MARKER REFERENCE FREQUENCY MODE [COMMENTS]`
/// Example POTA: `ABC123 K-1234 14.062 CW calling cq`
/// Example SOTA: `ABC123 W7W/KI-001 14.062 CW summit spot`
///
/// POTA references (no slash in reference) → posts to POTA.app v1 API.
/// SOTA references (contains slash) → posts to SOTA v2 API.
pub async fn twilio_sms_webhook(
    State(pool): State<PgPool>,
    axum::Form(form): axum::Form<TwilioSmsWebhook>,
) -> Response {
    match handle_sms(&pool, &form).await {
        Ok(reply) => twiml_response(&reply),
        Err(e) => {
            tracing::error!("Twilio webhook error: {e}");
            twiml_response("Error processing your spot. Check your message format: MARKER REFERENCE FREQ MODE [COMMENTS]")
        }
    }
}

async fn handle_sms(pool: &PgPool, form: &TwilioSmsWebhook) -> Result<String, AppError> {
    let parsed = parse_spot_message(&form.body)?;

    let marker_row = db::spot_markers::get_spot_marker(pool, &parsed.marker)
        .await?
        .ok_or_else(|| AppError::Validation {
            message: "Unknown marker code".to_string(),
        })?;

    let client = reqwest::Client::new();

    match parsed.spot_type {
        SpotType::Pota => {
            post_pota_spot(&client, &marker_row.callsign, &parsed).await?;
        }
        SpotType::Sota => {
            // SOTA kill-switch: the SOTAwatch v2 API shuts down 2026-08-31
            // and its replacement requires prior approval before use.
            // Restore the post_sota_spot call once the migration lands.
            return Ok(
                "SOTA spotting is temporarily disabled while Carrier Wave migrates to \
                 the new SOTA API. POTA spots still work."
                    .to_string(),
            );
        }
    }

    let type_label = match parsed.spot_type {
        SpotType::Pota => "POTA",
        SpotType::Sota => "SOTA",
    };

    Ok(format!(
        "Spot posted! {} {} on {} {} by {}",
        type_label, parsed.reference, parsed.frequency, parsed.mode, marker_row.callsign
    ))
}

/// Parse an SMS body into structured spot data.
///
/// Expected format: `MARKER REFERENCE FREQUENCY MODE [COMMENTS]`
fn parse_spot_message(body: &str) -> Result<ParsedSpotMessage, AppError> {
    let parts: Vec<&str> = body.trim().splitn(5, char::is_whitespace).collect();

    if parts.len() < 4 {
        return Err(AppError::Validation {
            message: "Expected format: MARKER REFERENCE FREQUENCY MODE [COMMENTS]".to_string(),
        });
    }

    let marker = parts[0].to_uppercase();
    let reference = parts[1].to_uppercase();
    let frequency = parts[2].to_string();
    let mode = parts[3].to_uppercase();
    let comments = if parts.len() > 4 {
        Some(parts[4].to_string())
    } else {
        None
    };

    // SOTA references contain a slash (e.g. W7W/KI-001), POTA do not (e.g. K-1234)
    let spot_type = if reference.contains('/') {
        SpotType::Sota
    } else {
        SpotType::Pota
    };

    Ok(ParsedSpotMessage {
        marker,
        reference,
        frequency,
        mode,
        comments,
        spot_type,
    })
}

/// Post a spot to the POTA.app v1 API.
async fn post_pota_spot(
    client: &reqwest::Client,
    callsign: &str,
    parsed: &ParsedSpotMessage,
) -> Result<(), AppError> {
    let body = serde_json::json!({
        "activator": callsign,
        "spotter": callsign,
        "frequency": parsed.frequency,
        "reference": parsed.reference,
        "mode": parsed.mode,
        "source": "Carrier Wave SMS",
        "comments": parsed.comments.as_deref().unwrap_or(""),
    });

    let resp = client
        .post("https://api.pota.app/spot")
        .json(&body)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("POTA API request failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp
            .text()
            .await
            .unwrap_or_else(|_| "unknown".to_string());
        tracing::error!("POTA API error: {status} {text}");
        return Err(AppError::Internal(format!("POTA API error: {status}")));
    }

    tracing::info!(
        callsign,
        reference = %parsed.reference,
        frequency = %parsed.frequency,
        mode = %parsed.mode,
        "POTA spot posted via SMS"
    );

    Ok(())
}

/// Post a spot to the SOTA v2 API.
/// Currently unreachable — SOTA spotting is disabled (see `handle_sms`).
#[allow(dead_code)]
async fn post_sota_spot(
    client: &reqwest::Client,
    callsign: &str,
    parsed: &ParsedSpotMessage,
) -> Result<(), AppError> {
    let body = serde_json::json!({
        "activatorCallsign": callsign,
        "spotterCallsign": callsign,
        "associationCode": parsed.reference,
        "frequency": parsed.frequency,
        "mode": parsed.mode,
        "comments": parsed.comments.as_deref().unwrap_or(""),
    });

    let resp = client
        .post("https://api2.sota.org.uk/api/spots")
        .json(&body)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("SOTA API request failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp
            .text()
            .await
            .unwrap_or_else(|_| "unknown".to_string());
        tracing::error!("SOTA API error: {status} {text}");
        return Err(AppError::Internal(format!("SOTA API error: {status}")));
    }

    tracing::info!(
        callsign,
        reference = %parsed.reference,
        frequency = %parsed.frequency,
        mode = %parsed.mode,
        "SOTA spot posted via SMS"
    );

    Ok(())
}

/// Wrap a reply string in TwiML XML for Twilio.
fn twiml_response(message: &str) -> Response {
    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?><Response><Message>{}</Message></Response>"#,
        quick_xml_escape(message)
    );

    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/xml")],
        xml,
    )
        .into_response()
}

/// Minimal XML escaping for TwiML message body.
fn quick_xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
