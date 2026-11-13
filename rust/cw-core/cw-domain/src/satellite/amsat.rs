//! AMSAT community-status domain logic. Port of the pure parts of
//! `AmsatStatusService.swift` (`AmsatSatelliteStatus.capabilityTag`,
//! `AmsatStatusClient.freshest`), plus the activity-grid bucket model behind
//! the hosts' community-activity view (the colour logic of amsat.org's
//! status grid). Fetching lives in `cw-net::amsat`.

use chrono::{DateTime, Duration, Utc};

/// One AMSAT status row from the activities server aggregate. Names like
/// `SO-50_[FM]` carry a per-capability bracket tag.
#[derive(Debug, Clone, PartialEq)]
pub struct AmsatStatus {
    pub name: String,
    pub norad_id: Option<u32>,
    pub last_heard_at: Option<DateTime<Utc>>,
    pub last_reported_at: Option<DateTime<Utc>>,
    pub last_report: Option<String>,
    pub last_callsign: Option<String>,
    pub last_grid: Option<String>,
    pub heard_reports_24h: i32,
    pub total_reports_24h: i32,
}

impl AmsatStatus {
    /// The bracket capability tag out of the AMSAT name: `AO-7_[B]` → `B`.
    pub fn capability_tag(&self) -> Option<String> {
        capability_tag(&self.name)
    }
}

/// The bracket capability tag out of an AMSAT name: `AO-7_[B]` → `B`.
pub fn capability_tag(name: &str) -> Option<String> {
    let start = name.find("_[")? + 2;
    let end = name[start..].find(']')? + start;
    let tag = name[start..end].trim();
    if tag.is_empty() {
        None
    } else {
        Some(tag.to_string())
    }
}

/// The satellite part of an AMSAT name: `AO-7_[B]` → `AO-7`. Names without
/// a tag come back whole.
pub fn base_name(name: &str) -> &str {
    name.split("_[").next().unwrap_or(name).trim()
}

/// One time slice of a satellite's community reports (one hour on the wire;
/// hosts may merge slices into coarser cells with [`ActivityBucket::merge`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ActivityBucket {
    pub start: DateTime<Utc>,
    pub heard: i32,
    pub not_heard: i32,
    pub telemetry: i32,
    pub crew: i32,
    pub other: i32,
}

/// The colour amsat.org paints a cell: the status page's legend
/// ("Sat/Mode Active", "TLM/Beacon only", "Not Heard", "Conflicting
/// reports"), plus `Quiet` for an empty cell.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActivityStatus {
    Quiet,
    Heard,
    TelemetryOnly,
    NotHeard,
    Conflicting,
}

impl ActivityBucket {
    pub fn empty(start: DateTime<Utc>) -> Self {
        ActivityBucket { start, heard: 0, not_heard: 0, telemetry: 0, crew: 0, other: 0 }
    }

    /// Every report in the slice, whatever the verdict.
    pub fn total(&self) -> i32 {
        self.heard + self.not_heard + self.telemetry + self.crew + self.other
    }

    /// Reports that vouch for the bird transmitting at all (heard, crew
    /// active, or telemetry).
    pub fn positive(&self) -> i32 {
        self.heard + self.crew + self.telemetry
    }

    /// Fold another slice into this one (the earlier `start` wins) — how a
    /// host builds 3 h / 6 h / daily cells from hourly wire rows.
    pub fn merge(&mut self, other: &ActivityBucket) {
        self.start = self.start.min(other.start);
        self.heard += other.heard;
        self.not_heard += other.not_heard;
        self.telemetry += other.telemetry;
        self.crew += other.crew;
        self.other += other.other;
    }

    /// Classify the slice the way AMSAT's grid colours it: any positive
    /// report alongside a "Not Heard" is conflicting; otherwise a heard/crew
    /// report beats telemetry-only beats not-heard; unrecognized verdicts
    /// alone count as heard (they came from someone who copied the bird).
    pub fn status(&self) -> ActivityStatus {
        let positive = self.positive() + self.other;
        if positive > 0 && self.not_heard > 0 {
            ActivityStatus::Conflicting
        } else if self.heard > 0 || self.crew > 0 || self.other > 0 {
            ActivityStatus::Heard
        } else if self.telemetry > 0 {
            ActivityStatus::TelemetryOnly
        } else if self.not_heard > 0 {
            ActivityStatus::NotHeard
        } else {
            ActivityStatus::Quiet
        }
    }
}

/// AMSAT's verdict vocabulary, classified the way the server does.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReportKind {
    Heard,
    NotHeard,
    TelemetryOnly,
    CrewActive,
    Other,
}

impl ReportKind {
    pub fn classify(report: &str) -> Self {
        let normalized = report.split_whitespace().collect::<Vec<_>>().join(" ").to_ascii_lowercase();
        match normalized.as_str() {
            "heard" => ReportKind::Heard,
            "not heard" => ReportKind::NotHeard,
            "telemetry only" | "telemetry" | "tlm only" => ReportKind::TelemetryOnly,
            "crew active" | "crew" => ReportKind::CrewActive,
            _ => ReportKind::Other,
        }
    }

    /// The legend colour one report paints on its own.
    pub fn status(self) -> ActivityStatus {
        match self {
            ReportKind::Heard | ReportKind::CrewActive | ReportKind::Other => ActivityStatus::Heard,
            ReportKind::TelemetryOnly => ActivityStatus::TelemetryOnly,
            ReportKind::NotHeard => ActivityStatus::NotHeard,
        }
    }
}

/// One community report (the server's raw `amsat_report` row).
#[derive(Debug, Clone, PartialEq)]
pub struct AmsatReport {
    pub name: String,
    pub time: DateTime<Utc>,
    pub callsign: String,
    pub kind: ReportKind,
    pub grid: Option<String>,
}

/// What the community saw on the bird's most recent orbit — the single
/// most predictive thing to know before your own pass: a LEO bird crosses
/// Europe roughly one period before it reaches North America.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrbitSummary {
    pub window_start: DateTime<Utc>,
    pub heard: u32,
    pub telemetry: u32,
    pub not_heard: u32,
    /// Distinct callsigns that heard it, newest first (capped by the caller).
    pub heard_callsigns: Vec<String>,
}

impl OrbitSummary {
    pub fn status(&self) -> ActivityStatus {
        let positive = self.heard + self.telemetry;
        if positive > 0 && self.not_heard > 0 {
            ActivityStatus::Conflicting
        } else if self.heard > 0 {
            ActivityStatus::Heard
        } else if self.telemetry > 0 {
            ActivityStatus::TelemetryOnly
        } else if self.not_heard > 0 {
            ActivityStatus::NotHeard
        } else {
            ActivityStatus::Quiet
        }
    }
}

/// Summarize the reports from the last orbital period. AMSAT stamps a
/// report at the half-hour of the hour it was filed in, so the window
/// opens half an hour before one period ago to keep the whole hour.
pub fn previous_orbit(
    reports: &[AmsatReport],
    now: DateTime<Utc>,
    period_minutes: f64,
    max_callsigns: usize,
) -> OrbitSummary {
    let window_start = now - Duration::seconds((period_minutes * 60.0) as i64 + 1_800);
    let mut summary = OrbitSummary {
        window_start,
        heard: 0,
        telemetry: 0,
        not_heard: 0,
        heard_callsigns: Vec::new(),
    };
    let mut sorted: Vec<&AmsatReport> =
        reports.iter().filter(|r| r.time >= window_start && r.time <= now).collect();
    sorted.sort_by_key(|report| std::cmp::Reverse(report.time));
    for report in sorted {
        match report.kind {
            ReportKind::Heard | ReportKind::CrewActive | ReportKind::Other => {
                summary.heard += 1;
                let call = report.callsign.trim().to_uppercase();
                if !call.is_empty()
                    && !summary.heard_callsigns.contains(&call)
                    && summary.heard_callsigns.len() < max_callsigns
                {
                    summary.heard_callsigns.push(call);
                }
            }
            ReportKind::TelemetryOnly => summary.telemetry += 1,
            ReportKind::NotHeard => summary.not_heard += 1,
        }
    }
    summary
}

/// Re-bucket hourly slices into cells `cell_secs` wide aligned to
/// `window_start`, one cell per occupied span, ascending. Slices before the
/// window are dropped; `cell_secs` is clamped to at least one hour.
pub fn merge_buckets(
    buckets: &[ActivityBucket],
    window_start: DateTime<Utc>,
    cell_secs: i64,
) -> Vec<ActivityBucket> {
    let cell_secs = cell_secs.max(3_600);
    let mut cells: Vec<ActivityBucket> = Vec::new();
    let mut sorted: Vec<&ActivityBucket> = buckets.iter().collect();
    sorted.sort_by_key(|bucket| bucket.start);
    for bucket in sorted {
        let offset = bucket.start.timestamp() - window_start.timestamp();
        if offset < 0 {
            continue;
        }
        let cell_start_epoch = window_start.timestamp() + (offset / cell_secs) * cell_secs;
        let Some(cell_start) = DateTime::from_timestamp(cell_start_epoch, 0) else {
            continue;
        };
        match cells.last_mut() {
            Some(last) if last.start == cell_start => {
                let mut merged = *bucket;
                merged.start = cell_start;
                last.merge(&merged);
            }
            _ => {
                let mut cell = *bucket;
                cell.start = cell_start;
                cells.push(cell);
            }
        }
    }
    cells
}

/// The most recently heard row of a satellite's capability rows (rows with
/// no heard date sort as distant past). Port of `AmsatStatusClient.freshest`.
pub fn freshest(rows: &[AmsatStatus]) -> Option<&AmsatStatus> {
    rows.iter().max_by_key(|row| row.last_heard_at.map(|d| d.timestamp()).unwrap_or(i64::MIN))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn row(name: &str, heard_epoch: Option<i64>) -> AmsatStatus {
        AmsatStatus {
            name: name.to_string(),
            norad_id: Some(1),
            last_heard_at: heard_epoch.map(|e| Utc.timestamp_opt(e, 0).unwrap()),
            last_reported_at: None,
            last_report: None,
            last_callsign: None,
            last_grid: None,
            heard_reports_24h: 0,
            total_reports_24h: 0,
        }
    }

    #[test]
    fn capability_tag_parses_bracket() {
        assert_eq!(row("SO-50_[FM]", None).capability_tag().as_deref(), Some("FM"));
        assert_eq!(row("AO-7_[B]", None).capability_tag().as_deref(), Some("B"));
        assert_eq!(row("SO-50", None).capability_tag(), None);
        assert_eq!(row("X_[]", None).capability_tag(), None);
    }

    #[test]
    fn freshest_prefers_latest_heard() {
        let rows =
            [row("A_[FM]", Some(100)), row("A_[CW]", Some(300)), row("A_[DIGI]", None)];
        assert_eq!(freshest(&rows).map(|r| r.name.as_str()), Some("A_[CW]"));
        assert!(freshest(&[]).is_none());
    }

    #[test]
    fn base_name_strips_tag() {
        assert_eq!(base_name("AO-7_[U/v]"), "AO-7");
        assert_eq!(base_name("SO-50"), "SO-50");
        assert_eq!(capability_tag("NO-44_[VHF_Digi]").as_deref(), Some("VHF_Digi"));
    }

    fn bucket(epoch: i64, heard: i32, not_heard: i32, telemetry: i32) -> ActivityBucket {
        ActivityBucket {
            start: Utc.timestamp_opt(epoch, 0).unwrap(),
            heard,
            not_heard,
            telemetry,
            crew: 0,
            other: 0,
        }
    }

    #[test]
    fn bucket_status_follows_amsat_legend() {
        assert_eq!(bucket(0, 0, 0, 0).status(), ActivityStatus::Quiet);
        assert_eq!(bucket(0, 2, 0, 0).status(), ActivityStatus::Heard);
        assert_eq!(bucket(0, 0, 0, 1).status(), ActivityStatus::TelemetryOnly);
        assert_eq!(bucket(0, 0, 3, 0).status(), ActivityStatus::NotHeard);
        assert_eq!(bucket(0, 1, 1, 0).status(), ActivityStatus::Conflicting);
        assert_eq!(bucket(0, 0, 1, 1).status(), ActivityStatus::Conflicting);
        let mut crew = bucket(0, 0, 0, 0);
        crew.crew = 1;
        assert_eq!(crew.status(), ActivityStatus::Heard);
        assert_eq!(crew.total(), 1);
    }

    fn report(epoch: i64, call: &str, verdict: &str) -> AmsatReport {
        AmsatReport {
            name: "SO-50_[FM]".to_string(),
            time: Utc.timestamp_opt(epoch, 0).unwrap(),
            callsign: call.to_string(),
            kind: ReportKind::classify(verdict),
            grid: None,
        }
    }

    #[test]
    fn previous_orbit_windows_one_period_plus_half_hour() {
        let now = Utc.timestamp_opt(100_000, 0).unwrap();
        // 95-minute orbit → window opens 95 min + 30 min = 7500 s ago.
        let reports = [
            report(100_000 - 7_000, "ei6fz", "Heard"),
            report(100_000 - 7_400, "EI6FZ", "Heard"), // duplicate callsign
            report(100_000 - 3_000, "WO3U", "Telemetry Only"),
            report(100_000 - 1_000, "K1ABC", "Not Heard"),
            report(100_000 - 8_000, "DL6AP", "Heard"), // before the window
            report(100_000 + 60, "N0FUT", "Heard"),    // after now
        ];
        let orbit = previous_orbit(&reports, now, 95.0, 6);
        assert_eq!(orbit.window_start.timestamp(), 100_000 - 7_500);
        assert_eq!((orbit.heard, orbit.telemetry, orbit.not_heard), (2, 1, 1));
        assert_eq!(orbit.heard_callsigns, vec!["EI6FZ".to_string()]);
        assert_eq!(orbit.status(), ActivityStatus::Conflicting);
        let quiet = previous_orbit(&[], now, 95.0, 6);
        assert_eq!(quiet.status(), ActivityStatus::Quiet);
    }

    #[test]
    fn report_kind_classifies_and_colours() {
        assert_eq!(ReportKind::classify(" not  heard"), ReportKind::NotHeard);
        assert_eq!(ReportKind::classify("Crew Active").status(), ActivityStatus::Heard);
        assert_eq!(ReportKind::classify("Telemetry Only").status(), ActivityStatus::TelemetryOnly);
    }

    #[test]
    fn merge_buckets_realigns_to_cells() {
        let window_start = Utc.timestamp_opt(3_600 * 24, 0).unwrap();
        let hourly = [
            bucket(3_600 * 23, 9, 0, 0), // before the window: dropped
            bucket(3_600 * 24, 1, 0, 0),
            bucket(3_600 * 26, 0, 1, 0), // same 3 h cell as the one above
            bucket(3_600 * 27, 0, 0, 2), // next cell
        ];
        let cells = merge_buckets(&hourly, window_start, 3 * 3_600);
        assert_eq!(cells.len(), 2);
        assert_eq!(cells[0].start, window_start);
        assert_eq!((cells[0].heard, cells[0].not_heard), (1, 1));
        assert_eq!(cells[0].status(), ActivityStatus::Conflicting);
        assert_eq!(cells[1].start.timestamp(), 3_600 * 27);
        assert_eq!(cells[1].telemetry, 2);
        // Sub-hour cells clamp to one hour: nothing merges.
        assert_eq!(merge_buckets(&hourly, window_start, 60).len(), 3);
    }
}
