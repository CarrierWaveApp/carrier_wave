use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

/// Database row for the `contest_definitions` table.
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct ContestDefinitionRow {
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub sponsor_name: Option<String>,
    pub sponsor_url: Option<String>,
    pub format_version: String,
    pub definition: serde_json::Value,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// API response for a single contest definition.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ContestDefinitionResponse {
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub sponsor_name: Option<String>,
    pub sponsor_url: Option<String>,
    pub format_version: String,
    pub definition: serde_json::Value,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl From<ContestDefinitionRow> for ContestDefinitionResponse {
    fn from(r: ContestDefinitionRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            short_name: r.short_name,
            sponsor_name: r.sponsor_name,
            sponsor_url: r.sponsor_url,
            format_version: r.format_version,
            definition: r.definition,
            is_active: r.is_active,
            created_at: r.created_at,
            updated_at: r.updated_at,
        }
    }
}

/// API response for the contest definition list endpoint.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ContestDefinitionListItem {
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub sponsor_name: Option<String>,
    pub format_version: String,
    pub is_active: bool,
    pub updated_at: DateTime<Utc>,
}

impl From<ContestDefinitionRow> for ContestDefinitionListItem {
    fn from(r: ContestDefinitionRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            short_name: r.short_name,
            sponsor_name: r.sponsor_name,
            format_version: r.format_version,
            is_active: r.is_active,
            updated_at: r.updated_at,
        }
    }
}

/// Query params for the public list endpoint.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListContestsQuery {
    #[serde(default)]
    pub include_inactive: bool,
}

/// Request body for the validate-only admin endpoint.
#[derive(Debug, Deserialize)]
pub struct ValidateContestsRequest {
    /// Either a full ContestDefinition file, or just a single Contest object.
    pub definition: serde_json::Value,
}

/// Validation problem returned by the validate endpoint.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ValidationProblem {
    pub severity: &'static str,
    pub contest_id: Option<String>,
    pub path: String,
    pub message: String,
}

/// Response body for the validate-only admin endpoint.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ValidateContestsResponse {
    pub valid: bool,
    pub problems: Vec<ValidationProblem>,
    pub contest_count: usize,
}
