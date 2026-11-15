//! POTA log-upload jobs (`/user/jobs`) and the self-delete window.
//!
//! Since November 2026 an activator can delete a log they uploaded for 24
//! hours after the upload. Each job in `/user/jobs` carries
//! `selfDeleteSecondsRemaining`, and `POST /admin/jobs/remove/{jobId}` (the
//! same route log managers use) removes it. That is what makes an "edit" of
//! an uploaded log possible: remove the job, then upload the corrected ADIF.
//!
//! Models mirror the Swift `POTAJob` / `POTAJobsPage`; [`plan_log_replace`]
//! is the shared rule for whether an activation's upload can be replaced.

use chrono::{DateTime, NaiveDate, NaiveDateTime, Utc};
use serde::{Deserialize, Deserializer};
use serde_json::Value;

/// One upload job from `/user/jobs`. JSON keys are camelCase; the QSO counts
/// are `total` / `inserted`.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct PotaJob {
    #[serde(rename = "jobId")]
    pub job_id: i64,
    pub status: i64,
    /// ISO-8601 without a timezone suffix (UTC), e.g. "2026-02-04T17:06:41".
    #[serde(default)]
    pub submitted: Option<String>,
    #[serde(default)]
    pub processed: Option<String>,
    #[serde(default)]
    pub reference: Option<String>,
    #[serde(rename = "parkName", default)]
    pub park_name: Option<String>,
    #[serde(default)]
    pub location: Option<String>,
    #[serde(default)]
    pub total: Option<i64>,
    #[serde(default)]
    pub inserted: Option<i64>,
    #[serde(rename = "callsignUsed", default)]
    pub callsign_used: Option<String>,
    #[serde(rename = "userComment", default)]
    pub user_comment: Option<String>,
    #[serde(rename = "firstQSO", default)]
    pub first_qso: Option<String>,
    #[serde(rename = "lastQSO", default)]
    pub last_qso: Option<String>,
    /// Seconds left in the uploader's self-delete window when the response
    /// was produced; `0` once the window has closed (or on a backend that
    /// predates the feature). The site reads it as `Number(x) || 0`, so a
    /// number, a numeric string, `null` and a missing key are all accepted.
    #[serde(rename = "selfDeleteSecondsRemaining", default, deserialize_with = "lenient_seconds")]
    pub self_delete_seconds_remaining: f64,
}

fn lenient_seconds<'de, D: Deserializer<'de>>(deserializer: D) -> Result<f64, D::Error> {
    let seconds = match Value::deserialize(deserializer)? {
        Value::Number(number) => number.as_f64().unwrap_or(0.0),
        Value::String(text) => text.trim().parse::<f64>().unwrap_or(0.0),
        _ => 0.0,
    };
    Ok(if seconds.is_finite() && seconds > 0.0 { seconds } else { 0.0 })
}

impl PotaJob {
    /// The site shows both `-1` and `-10` as "Removed".
    pub fn is_removed(&self) -> bool {
        is_removed_status(self.status)
    }

    /// Pending (0), processing (1) or completed (2): the job's QSOs are, or
    /// are about to be, in the POTA database.
    pub fn holds_qsos(&self) -> bool {
        holds_qsos_status(self.status)
    }

    /// Seconds left to self-delete, `elapsed_seconds` after the job list was
    /// fetched. Never negative.
    pub fn self_delete_seconds_left(&self, elapsed_seconds: f64) -> f64 {
        seconds_left(self.self_delete_seconds_remaining, elapsed_seconds)
    }

    /// UTC calendar day of the first QSO, used to match a job to an
    /// activation. `None` when the job has no `firstQSO` or it is unparseable.
    pub fn first_qso_utc_date(&self) -> Option<NaiveDate> {
        let text = self.first_qso.as_deref()?.trim();
        if let Ok(parsed) = DateTime::parse_from_rfc3339(text) {
            return Some(parsed.with_timezone(&Utc).date_naive());
        }
        NaiveDateTime::parse_from_str(text, "%Y-%m-%dT%H:%M:%S%.f")
            .ok()
            .map(|parsed| parsed.date())
    }
}

fn is_removed_status(status: i64) -> bool {
    status == -1 || status == -10
}

fn holds_qsos_status(status: i64) -> bool {
    (0..=2).contains(&status)
}

fn seconds_left(remaining: f64, elapsed_seconds: f64) -> f64 {
    (remaining - elapsed_seconds.max(0.0)).max(0.0)
}

/// One page of `/user/jobs`. The rebuilt site paginates the endpoint as
/// `{count, pending, entries}`; older deployments answer with a bare array.
#[derive(Debug, Clone, PartialEq)]
pub struct PotaJobsPage {
    /// Total jobs across all pages (`entries.len()` for the legacy array).
    pub count: i64,
    /// Jobs still queued or processing, when the server reports it.
    pub pending: i64,
    pub entries: Vec<PotaJob>,
    /// True when the server answered with the unpaginated legacy array.
    pub is_legacy_array: bool,
}

impl PotaJobsPage {
    /// Parse either response shape. `None` when the body is neither.
    pub fn parse(json: &str) -> Option<Self> {
        #[derive(Deserialize)]
        struct Paginated {
            #[serde(default)]
            count: Option<i64>,
            #[serde(default)]
            pending: Option<i64>,
            entries: Vec<PotaJob>,
        }
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Shape {
            Legacy(Vec<PotaJob>),
            Paginated(Paginated),
        }
        Some(match serde_json::from_str::<Shape>(json).ok()? {
            Shape::Legacy(entries) => Self {
                count: entries.len() as i64,
                pending: 0,
                entries,
                is_legacy_array: true,
            },
            Shape::Paginated(page) => Self {
                count: page.count.unwrap_or(page.entries.len() as i64),
                pending: page.pending.unwrap_or(0),
                entries: page.entries,
                is_legacy_array: false,
            },
        })
    }
}

/// The part of a job [`plan_log_replace`] needs.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PotaJobWindow {
    pub job_id: i64,
    pub status: i64,
    pub self_delete_seconds_remaining: f64,
}

impl From<&PotaJob> for PotaJobWindow {
    fn from(job: &PotaJob) -> Self {
        Self {
            job_id: job.job_id,
            status: job.status,
            self_delete_seconds_remaining: job.self_delete_seconds_remaining,
        }
    }
}

/// Why an activation's upload cannot be replaced.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PotaLogReplaceBlocker {
    /// No job to remove: nothing was uploaded, or every job is already removed.
    NothingToRemove,
    /// A job that holds QSOs is past its 24-hour self-delete window. Removing
    /// only the others and uploading again would leave the stale log in place.
    WindowExpired,
}

/// What replacing an activation's upload involves.
#[derive(Debug, Clone, PartialEq)]
pub struct PotaLogReplacePlan {
    /// Jobs to remove before uploading the corrected log, in input order.
    /// Includes failed uploads still inside their window, which POTA asks
    /// activators to clean up. Empty when `blocker` is set.
    pub remove_job_ids: Vec<i64>,
    /// Seconds until the first of those jobs can no longer be removed.
    pub seconds_left: f64,
    pub blocker: Option<PotaLogReplaceBlocker>,
}

impl PotaLogReplacePlan {
    pub fn can_replace(&self) -> bool {
        self.blocker.is_none()
    }

    fn blocked(blocker: PotaLogReplaceBlocker) -> Self {
        Self { remove_job_ids: Vec::new(), seconds_left: 0.0, blocker: Some(blocker) }
    }
}

/// Decide whether the upload behind one activation can be replaced.
///
/// `jobs` are the jobs already matched to the activation (park, callsign,
/// UTC day); `elapsed_seconds` is how long ago they were fetched, since the
/// server reports the window as a countdown rather than a deadline.
pub fn plan_log_replace(jobs: &[PotaJobWindow], elapsed_seconds: f64) -> PotaLogReplacePlan {
    let live = jobs.iter().filter(|job| !is_removed_status(job.status));
    let mut remove_job_ids = Vec::new();
    let mut seconds_left_min = f64::INFINITY;
    for job in live {
        let left = seconds_left(job.self_delete_seconds_remaining, elapsed_seconds);
        if left > 0.0 {
            remove_job_ids.push(job.job_id);
            seconds_left_min = seconds_left_min.min(left);
        } else if holds_qsos_status(job.status) {
            return PotaLogReplacePlan::blocked(PotaLogReplaceBlocker::WindowExpired);
        }
    }
    if remove_job_ids.is_empty() {
        return PotaLogReplacePlan::blocked(PotaLogReplaceBlocker::NothingToRemove);
    }
    PotaLogReplacePlan { remove_job_ids, seconds_left: seconds_left_min, blocker: None }
}

/// Path (relative to the API base) that removes an upload job. Sent as an
/// authenticated `POST` with an empty JSON object body.
pub fn remove_job_path(job_id: i64) -> String {
    format!("/admin/jobs/remove/{job_id}")
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGINATED: &str = r#"{
        "count": 41, "pending": 1,
        "entries": [
            {"jobId": 9001, "status": 2, "submitted": "2026-11-15T05:10:00",
             "processed": "2026-11-15T05:10:09", "reference": "US-1234",
             "parkName": "Test Park", "location": "US-CA", "total": 12, "inserted": 12,
             "callsignUsed": "W6JSV", "userComment": null,
             "firstQSO": "2026-11-14T23:58:00", "lastQSO": "2026-11-15T00:40:00",
             "userId": 77, "selfDeleteSecondsRemaining": 82800},
            {"jobId": 9000, "status": -1, "submitted": "2026-11-14T05:10:00",
             "reference": "US-1234", "selfDeleteSecondsRemaining": 0}
        ]
    }"#;

    fn window(job_id: i64, status: i64, remaining: f64) -> PotaJobWindow {
        PotaJobWindow { job_id, status, self_delete_seconds_remaining: remaining }
    }

    #[test]
    fn parses_paginated_page() {
        let page = PotaJobsPage::parse(PAGINATED).unwrap();
        assert!(!page.is_legacy_array);
        assert_eq!((page.count, page.pending, page.entries.len()), (41, 1, 2));
        let job = &page.entries[0];
        assert_eq!(job.job_id, 9001);
        assert_eq!(job.self_delete_seconds_remaining, 82_800.0);
        assert_eq!(job.total, Some(12));
        assert!(job.holds_qsos() && !job.is_removed());
        assert_eq!(job.first_qso_utc_date(), NaiveDate::from_ymd_opt(2026, 11, 14));
        assert!(page.entries[1].is_removed());
    }

    #[test]
    fn parses_legacy_array_without_window() {
        let json = r#"[{"jobId": 5, "status": 2, "submitted": "2026-02-04T17:06:41",
                        "reference": "K-0001", "total": 3, "inserted": 3}]"#;
        let page = PotaJobsPage::parse(json).unwrap();
        assert!(page.is_legacy_array);
        assert_eq!(page.count, 1);
        assert_eq!(page.entries[0].self_delete_seconds_remaining, 0.0);
        assert_eq!(page.entries[0].first_qso_utc_date(), None);
    }

    #[test]
    fn rejects_other_shapes() {
        assert!(PotaJobsPage::parse("{\"message\":\"Unauthorized\"}").is_none());
        assert!(PotaJobsPage::parse("not json").is_none());
    }

    #[test]
    fn window_field_is_lenient() {
        let seconds = |raw: &str| {
            let json = format!(
                r#"[{{"jobId": 1, "status": 2, "selfDeleteSecondsRemaining": {raw}}}]"#
            );
            PotaJobsPage::parse(&json).unwrap().entries[0].self_delete_seconds_remaining
        };
        assert_eq!(seconds("120.5"), 120.5);
        assert_eq!(seconds("\"90\""), 90.0);
        assert_eq!(seconds("null"), 0.0);
        assert_eq!(seconds("-4"), 0.0);
        assert_eq!(seconds("\"soon\""), 0.0);
    }

    #[test]
    fn first_qso_date_converts_offsets_to_utc() {
        let mut job = PotaJobsPage::parse(PAGINATED).unwrap().entries.remove(0);
        job.first_qso = Some("2026-11-14T20:30:00-05:00".into());
        assert_eq!(job.first_qso_utc_date(), NaiveDate::from_ymd_opt(2026, 11, 15));
    }

    #[test]
    fn seconds_left_counts_down_from_fetch() {
        let job = PotaJobsPage::parse(PAGINATED).unwrap().entries.remove(0);
        assert_eq!(job.self_delete_seconds_left(800.0), 82_000.0);
        assert_eq!(job.self_delete_seconds_left(90_000.0), 0.0);
        assert_eq!(job.self_delete_seconds_left(-5.0), 82_800.0);
    }

    #[test]
    fn plan_removes_every_job_inside_the_window() {
        // A completed upload, an earlier failed attempt, and a removed job.
        let jobs = [window(3, 2, 3_600.0), window(2, 3, 7_000.0), window(1, -1, 9_000.0)];
        let plan = plan_log_replace(&jobs, 600.0);
        assert!(plan.can_replace());
        assert_eq!(plan.remove_job_ids, vec![3, 2]);
        assert_eq!(plan.seconds_left, 3_000.0);
    }

    #[test]
    fn plan_blocks_when_a_live_upload_is_past_the_window() {
        let jobs = [window(3, 2, 3_600.0), window(2, 2, 0.0)];
        let plan = plan_log_replace(&jobs, 0.0);
        assert_eq!(plan.blocker, Some(PotaLogReplaceBlocker::WindowExpired));
        assert!(plan.remove_job_ids.is_empty());
    }

    #[test]
    fn plan_blocks_once_the_countdown_runs_out_locally() {
        let plan = plan_log_replace(&[window(3, 2, 300.0)], 301.0);
        assert_eq!(plan.blocker, Some(PotaLogReplaceBlocker::WindowExpired));
    }

    #[test]
    fn expired_failed_jobs_do_not_block() {
        let jobs = [window(3, 2, 3_600.0), window(2, 3, 0.0), window(1, 7, 0.0)];
        let plan = plan_log_replace(&jobs, 0.0);
        assert_eq!(plan.remove_job_ids, vec![3]);
    }

    #[test]
    fn plan_has_nothing_to_remove() {
        for jobs in [vec![], vec![window(1, -10, 500.0)], vec![window(2, 3, 0.0)]] {
            let plan = plan_log_replace(&jobs, 0.0);
            assert_eq!(plan.blocker, Some(PotaLogReplaceBlocker::NothingToRemove));
        }
    }

    #[test]
    fn remove_path() {
        assert_eq!(remove_job_path(123_456), "/admin/jobs/remove/123456");
    }
}
