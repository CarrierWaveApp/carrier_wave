//! Wire types for the AMSAT community satellite status endpoint.

use chrono::{DateTime, Utc};
use serde::Serialize;

/// One satellite's aggregated community status.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatSatelliteStatus {
    /// AMSAT's internal name, e.g. `SO-50_[FM]` or `AO-7_[B]`.
    pub name: String,
    /// Curated NORAD catalog id, when we know the mapping.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub norad_id: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_heard_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_reported_at: Option<DateTime<Utc>>,
    /// Most recent report verbatim ("Heard", "Not Heard", "Telemetry Only", …).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_report: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_callsign: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_grid: Option<String>,
    pub heard_reports_24h: i32,
    pub total_reports_24h: i32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatStatusResponse {
    pub satellites: Vec<AmsatSatelliteStatus>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<DateTime<Utc>>,
}

// MARK: - Activity grid

/// How a raw AMSAT verdict string is bucketed in the activity grid.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AmsatReportKind {
    Heard,
    NotHeard,
    TelemetryOnly,
    CrewActive,
    Other,
}

impl AmsatReportKind {
    /// AMSAT's verdict vocabulary: "Heard", "Not Heard", "Telemetry Only",
    /// and "Crew Active" (ISS). Case- and whitespace-insensitive; anything
    /// else lands in `Other` so a new verdict is counted, not dropped.
    pub fn classify(report: &str) -> Self {
        let normalized: String = report
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .to_ascii_lowercase();
        match normalized.as_str() {
            "heard" => Self::Heard,
            "not heard" => Self::NotHeard,
            "telemetry only" | "telemetry" | "tlm only" => Self::TelemetryOnly,
            "crew active" | "crew" => Self::CrewActive,
            _ => Self::Other,
        }
    }
}

/// One time slice of a satellite's community reports.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatActivityBucket {
    pub start: DateTime<Utc>,
    pub heard: i32,
    pub not_heard: i32,
    pub telemetry: i32,
    pub crew: i32,
    pub other: i32,
}

impl AmsatActivityBucket {
    pub fn add(&mut self, kind: AmsatReportKind, count: i32) {
        match kind {
            AmsatReportKind::Heard => self.heard += count,
            AmsatReportKind::NotHeard => self.not_heard += count,
            AmsatReportKind::TelemetryOnly => self.telemetry += count,
            AmsatReportKind::CrewActive => self.crew += count,
            AmsatReportKind::Other => self.other += count,
        }
    }
}

/// One AMSAT-tracked transmitter with its sparse bucket list (buckets with
/// no reports are omitted; `start` is the bucket's inclusive start).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatActivitySatellite {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub norad_id: Option<i64>,
    pub buckets: Vec<AmsatActivityBucket>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatActivityResponse {
    /// Bucket width — always one hour today (AMSAT quantizes reports to the
    /// hour); clients may merge buckets for coarser grids.
    pub bucket_seconds: i64,
    pub window_start: DateTime<Utc>,
    pub window_end: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<DateTime<Utc>>,
    pub satellites: Vec<AmsatActivitySatellite>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_amsat_verdicts() {
        assert_eq!(AmsatReportKind::classify("Heard"), AmsatReportKind::Heard);
        assert_eq!(AmsatReportKind::classify("  not   HEARD "), AmsatReportKind::NotHeard);
        assert_eq!(AmsatReportKind::classify("Telemetry Only"), AmsatReportKind::TelemetryOnly);
        assert_eq!(AmsatReportKind::classify("Crew Active"), AmsatReportKind::CrewActive);
        assert_eq!(AmsatReportKind::classify("Something New"), AmsatReportKind::Other);
    }
}

// MARK: - Raw reports feed

/// One community report as AMSAT recorded it.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatReportWire {
    /// AMSAT internal name the report was filed under (`SO-50_[FM]`).
    pub name: String,
    pub reported_at: DateTime<Utc>,
    pub callsign: String,
    /// Verdict verbatim ("Heard", "Not Heard", "Telemetry Only", "Crew Active").
    pub report: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grid: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AmsatReportsResponse {
    pub window_start: DateTime<Utc>,
    pub window_end: DateTime<Utc>,
    /// The AMSAT names the query resolved to (every capability row of a
    /// NORAD id, or the one `name` asked for).
    pub names: Vec<String>,
    /// Newest first.
    pub reports: Vec<AmsatReportWire>,
}
