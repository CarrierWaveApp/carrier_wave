use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

// ==================== Enums ====================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, sqlx::Type)]
#[sqlx(type_name = "text", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum EquipmentCategory {
    Radio,
    Antenna,
    Key,
    Microphone,
    Accessory,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, sqlx::Type)]
#[sqlx(type_name = "text", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum Portability {
    Pocket,
    Backpack,
    Portable,
    Mobile,
    Base,
}

// ==================== Database Row ====================

#[derive(Debug, Clone, FromRow)]
pub struct EquipmentRow {
    pub id: String,
    pub name: String,
    pub manufacturer: String,
    pub category: String,
    pub bands: Vec<String>,
    pub modes: Vec<String>,
    pub max_power_watts: Option<i32>,
    pub portability: String,
    pub weight_grams: Option<i32>,
    pub description: Option<String>,
    pub aliases: Vec<String>,
    pub image_url: Option<String>,
    pub antenna_connector: Option<String>,
    pub power_connector: Option<String>,
    pub key_jack: Option<String>,
    pub mic_jack: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ==================== API Response ====================

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct EquipmentEntryResponse {
    pub id: String,
    pub name: String,
    pub manufacturer: String,
    pub category: String,
    pub bands: Vec<String>,
    pub modes: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_power_watts: Option<i32>,
    pub portability: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weight_grams: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub aliases: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub antenna_connector: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub power_connector: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_jack: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mic_jack: Option<String>,
}

impl From<EquipmentRow> for EquipmentEntryResponse {
    fn from(r: EquipmentRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            manufacturer: r.manufacturer,
            category: r.category,
            bands: r.bands,
            modes: r.modes,
            max_power_watts: r.max_power_watts,
            portability: r.portability,
            weight_grams: r.weight_grams,
            description: r.description,
            aliases: r.aliases,
            image_url: r.image_url,
            antenna_connector: r.antenna_connector,
            power_connector: r.power_connector,
            key_jack: r.key_jack,
            mic_jack: r.mic_jack,
        }
    }
}

// ==================== Catalog Response ====================

#[derive(Debug, Serialize)]
pub struct CatalogResponse {
    pub version: i64,
    pub updated_at: DateTime<Utc>,
    pub entries: Vec<EquipmentEntryResponse>,
}

// ==================== Search Response ====================

#[derive(Debug, Serialize)]
pub struct SearchResultEntry {
    pub entry: EquipmentEntryResponse,
    pub confidence: f64,
    pub matched_field: String,
}

#[derive(Debug, Serialize)]
pub struct SearchResponse {
    pub results: Vec<SearchResultEntry>,
}

// ==================== Search Row (from DB) ====================

#[derive(Debug, Clone, FromRow)]
pub struct EquipmentSearchRow {
    pub id: String,
    pub name: String,
    pub manufacturer: String,
    pub category: String,
    pub bands: Vec<String>,
    pub modes: Vec<String>,
    pub max_power_watts: Option<i32>,
    pub portability: String,
    pub weight_grams: Option<i32>,
    pub description: Option<String>,
    pub aliases: Vec<String>,
    pub image_url: Option<String>,
    pub antenna_connector: Option<String>,
    pub power_connector: Option<String>,
    pub key_jack: Option<String>,
    pub mic_jack: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub score: Option<f64>,
    pub matched_field: Option<String>,
}

// ==================== Query Parameters ====================

#[derive(Debug, Deserialize)]
pub struct CatalogQuery {
    pub since: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub q: String,
    pub category: Option<String>,
    pub limit: Option<i64>,
}

// ==================== Admin Request ====================

#[derive(Debug, Deserialize)]
pub struct CreateEquipmentRequest {
    pub id: String,
    pub name: String,
    pub manufacturer: String,
    pub category: String,
    #[serde(default)]
    pub bands: Vec<String>,
    #[serde(default)]
    pub modes: Vec<String>,
    pub max_power_watts: Option<i32>,
    #[serde(default = "default_portability")]
    pub portability: String,
    pub weight_grams: Option<i32>,
    pub description: Option<String>,
    #[serde(default)]
    pub aliases: Vec<String>,
    pub image_url: Option<String>,
    pub antenna_connector: Option<String>,
    pub power_connector: Option<String>,
    pub key_jack: Option<String>,
    pub mic_jack: Option<String>,
}

fn default_portability() -> String {
    "portable".to_string()
}

// ==================== Submissions ====================

#[derive(Debug, Clone, FromRow)]
pub struct EquipmentSubmissionRow {
    pub id: uuid::Uuid,
    pub name: String,
    pub manufacturer: String,
    pub category: String,
    pub bands: Vec<String>,
    pub modes: Vec<String>,
    pub max_power_watts: Option<i32>,
    pub portability: String,
    pub weight_grams: Option<i32>,
    pub status: String,
    pub catalog_id: Option<String>,
    pub app_version: Option<String>,
    pub created_at: DateTime<Utc>,
    pub reviewed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
pub struct SubmissionResponse {
    pub id: uuid::Uuid,
    pub status: String,
}

#[derive(Debug, Deserialize)]
pub struct CreateSubmissionRequest {
    pub name: String,
    #[serde(default)]
    pub manufacturer: String,
    pub category: String,
    #[serde(default)]
    pub bands: Vec<String>,
    #[serde(default)]
    pub modes: Vec<String>,
    pub max_power_watts: Option<i32>,
    #[serde(default = "default_portability")]
    pub portability: String,
    pub weight_grams: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct ReviewSubmissionRequest {
    pub action: String,
    pub catalog_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SubmissionListQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateEquipmentRequest {
    pub name: Option<String>,
    pub manufacturer: Option<String>,
    pub category: Option<String>,
    pub bands: Option<Vec<String>>,
    pub modes: Option<Vec<String>>,
    pub max_power_watts: Option<Option<i32>>,
    pub portability: Option<String>,
    pub weight_grams: Option<Option<i32>>,
    pub description: Option<Option<String>>,
    pub aliases: Option<Vec<String>>,
    pub image_url: Option<Option<String>>,
    pub antenna_connector: Option<Option<String>>,
    pub power_connector: Option<Option<String>>,
    pub key_jack: Option<Option<String>>,
    pub mic_jack: Option<Option<String>>,
}
