//! Models for the callsign enrichment subsystem.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// A single per-callsign membership row, scoped to one source.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentMembership {
    pub source_slug: String,
    pub source_name: String,
    pub emoji: Option<String>,
    pub name: Option<String>,
    pub member_number: Option<String>,
    pub note: Option<String>,
}

/// Response for `GET /api/v1/callsign-enrichment/{callsign}`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentResponse {
    pub callsign: String,
    pub memberships: Vec<EnrichmentMembership>,
}

/// Response for `GET /api/v1/callsign-enrichment/dataset` — the full dump
/// the client downloads and caches. Compact field names because this can
/// run to a few megabytes uncompressed for a popular list like CWops.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentDataset {
    /// Per-source metadata (slug, display name, emoji).
    pub sources: Vec<EnrichmentDatasetSource>,
    /// One entry per callsign that appears in *any* source.
    pub callsigns: Vec<EnrichmentDatasetEntry>,
    /// When the server last refreshed each source, ISO-8601.
    pub generated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentDatasetSource {
    pub slug: String,
    pub name: String,
    pub emoji: Option<String>,
    pub last_fetched_at: Option<DateTime<Utc>>,
}

/// One row in the dataset, flattened across sources for compactness.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentDatasetEntry {
    /// Uppercase callsign.
    #[serde(rename = "c")]
    pub callsign: String,
    /// Per-source membership entries.
    #[serde(rename = "m")]
    pub memberships: Vec<EnrichmentDatasetMembership>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentDatasetMembership {
    /// Source slug (e.g. "cwops").
    #[serde(rename = "s")]
    pub source_slug: String,
    /// Operator name from the source (already title-cased upstream when possible).
    #[serde(rename = "n", skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Member number, digits only.
    #[serde(rename = "#", skip_serializing_if = "Option::is_none")]
    pub member_number: Option<String>,
    /// Per-row emoji override (rare; falls back to source emoji).
    #[serde(rename = "e", skip_serializing_if = "Option::is_none")]
    pub emoji: Option<String>,
    /// Free-form note left over after stripping name/number.
    #[serde(rename = "t", skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}
