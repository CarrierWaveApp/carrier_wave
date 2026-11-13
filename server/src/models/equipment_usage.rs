use serde::{Deserialize, Serialize};

/// Single equipment usage event in a session.
#[derive(Debug, Deserialize)]
pub struct EquipmentUsageEntry {
    pub catalog_id: String,
    pub category: String,
    #[serde(default)]
    pub is_custom: bool,
    pub custom_name: Option<String>,
    pub custom_manufacturer: Option<String>,
    #[serde(default)]
    pub custom_bands: Vec<String>,
    #[serde(default)]
    pub custom_modes: Vec<String>,
    pub custom_max_power_watts: Option<i32>,
    pub custom_portability: Option<String>,
    pub session_mode: Option<String>,
    pub session_band: Option<String>,
    pub session_program: Option<String>,
    #[serde(default)]
    pub paired_with: Vec<String>,
}

/// Metadata included with each usage report.
#[derive(Debug, Deserialize)]
pub struct UsageMetadata {
    pub app_version: Option<String>,
    pub os_version: Option<String>,
}

/// Request body for POST /v1/telemetry/equipment-usage
#[derive(Debug, Deserialize)]
pub struct ReportEquipmentUsageRequest {
    pub metadata: UsageMetadata,
    pub usage: Vec<EquipmentUsageEntry>,
}

/// Response for the usage telemetry endpoint.
#[derive(Debug, Serialize)]
pub struct ReportEquipmentUsageResponse {
    pub accepted: usize,
}
