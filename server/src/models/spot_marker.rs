use serde::{Deserialize, Serialize};

/// Database row for spot_markers table.
#[derive(Debug, sqlx::FromRow)]
pub struct SpotMarkerRow {
    pub id: uuid::Uuid,
    pub marker: String,
    pub callsign: String,
    pub participant_id: uuid::Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// API response after creating a spot marker.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotMarkerResponse {
    pub marker: String,
    pub callsign: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// Twilio sends SMS webhooks as application/x-www-form-urlencoded.
#[derive(Deserialize)]
#[allow(dead_code)]
pub struct TwilioSmsWebhook {
    #[serde(rename = "Body")]
    pub body: String,
    #[serde(rename = "From")]
    pub from: String,
    #[serde(rename = "To")]
    pub to: Option<String>,
    #[serde(rename = "MessageSid")]
    pub message_sid: Option<String>,
}

/// The type of spot determined by reference format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpotType {
    Pota,
    Sota,
}

/// Parsed SMS spot message.
#[derive(Debug)]
pub struct ParsedSpotMessage {
    pub marker: String,
    pub reference: String,
    pub frequency: String,
    pub mode: String,
    pub comments: Option<String>,
    pub spot_type: SpotType,
}
