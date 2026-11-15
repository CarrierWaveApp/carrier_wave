//! UniFFI surface for POTA upload jobs and the 24-hour self-delete window
//! (`cw_net::pota_jobs`).
//!
//! The host owns auth and the HTTP calls; this decodes `/user/jobs`, names
//! the removal route, and decides whether an activation's upload can be
//! replaced so every platform applies the same rule.

use cw_net::pota_jobs::{
    plan_log_replace, remove_job_path, PotaJob, PotaJobWindow, PotaJobsPage,
    PotaLogReplaceBlocker, PotaLogReplacePlan,
};

/// One upload job from `/user/jobs`.
#[derive(uniffi::Record)]
pub struct FfiPotaJob {
    pub job_id: i64,
    /// 0 pending, 1 processing, 2 completed, 3+ failure states, 7 duplicate,
    /// -1 / -10 removed.
    pub status: i64,
    /// ISO-8601 without a timezone suffix (UTC).
    pub submitted: Option<String>,
    pub processed: Option<String>,
    pub reference: Option<String>,
    pub park_name: Option<String>,
    pub location: Option<String>,
    pub total_qsos: Option<i64>,
    pub inserted_qsos: Option<i64>,
    pub callsign_used: Option<String>,
    pub user_comment: Option<String>,
    pub first_qso: Option<String>,
    pub last_qso: Option<String>,
    /// UTC day of the first QSO as `yyyy-MM-dd`, for activation matching.
    pub first_qso_utc_date: Option<String>,
    /// Seconds left in the self-delete window when the list was fetched.
    pub self_delete_seconds_remaining: f64,
    pub is_removed: bool,
}

impl From<PotaJob> for FfiPotaJob {
    fn from(job: PotaJob) -> Self {
        let first_qso_utc_date =
            job.first_qso_utc_date().map(|date| date.format("%Y-%m-%d").to_string());
        let is_removed = job.is_removed();
        FfiPotaJob {
            job_id: job.job_id,
            status: job.status,
            submitted: job.submitted,
            processed: job.processed,
            reference: job.reference,
            park_name: job.park_name,
            location: job.location,
            total_qsos: job.total,
            inserted_qsos: job.inserted,
            callsign_used: job.callsign_used,
            user_comment: job.user_comment,
            first_qso: job.first_qso,
            last_qso: job.last_qso,
            first_qso_utc_date,
            self_delete_seconds_remaining: job.self_delete_seconds_remaining,
            is_removed,
        }
    }
}

/// One page of `/user/jobs` (paginated object or legacy bare array).
#[derive(uniffi::Record)]
pub struct FfiPotaJobsPage {
    pub count: i64,
    pub pending: i64,
    pub entries: Vec<FfiPotaJob>,
    pub is_legacy_array: bool,
}

/// The part of a job the replace rule needs.
#[derive(uniffi::Record)]
pub struct FfiPotaJobWindow {
    pub job_id: i64,
    pub status: i64,
    pub self_delete_seconds_remaining: f64,
}

/// Why an activation's upload cannot be replaced.
#[derive(uniffi::Enum, Debug, PartialEq, Eq)]
pub enum FfiPotaLogReplaceBlocker {
    /// Nothing was uploaded, or every job is already removed.
    NothingToRemove,
    /// A job that holds QSOs is past its 24-hour self-delete window.
    WindowExpired,
}

/// What replacing an activation's upload involves.
#[derive(uniffi::Record)]
pub struct FfiPotaLogReplacePlan {
    /// Jobs to remove before uploading the corrected log. Empty when blocked.
    pub remove_job_ids: Vec<i64>,
    /// Seconds until the first of those jobs can no longer be removed.
    pub seconds_left: f64,
    pub blocker: Option<FfiPotaLogReplaceBlocker>,
}

impl From<PotaLogReplacePlan> for FfiPotaLogReplacePlan {
    fn from(plan: PotaLogReplacePlan) -> Self {
        FfiPotaLogReplacePlan {
            remove_job_ids: plan.remove_job_ids,
            seconds_left: plan.seconds_left,
            blocker: plan.blocker.map(|blocker| match blocker {
                PotaLogReplaceBlocker::NothingToRemove => FfiPotaLogReplaceBlocker::NothingToRemove,
                PotaLogReplaceBlocker::WindowExpired => FfiPotaLogReplaceBlocker::WindowExpired,
            }),
        }
    }
}

/// Decode a `/user/jobs` response body. Returns `None` if the body is
/// neither the paginated object nor the legacy array.
#[uniffi::export]
pub fn decode_pota_jobs_page(json: String) -> Option<FfiPotaJobsPage> {
    PotaJobsPage::parse(&json).map(|page| FfiPotaJobsPage {
        count: page.count,
        pending: page.pending,
        entries: page.entries.into_iter().map(Into::into).collect(),
        is_legacy_array: page.is_legacy_array,
    })
}

/// Decide whether the upload behind one activation can be replaced (removed
/// and uploaded again). `jobs` are the jobs matched to that activation;
/// `elapsed_seconds` is how long ago the job list was fetched.
#[uniffi::export]
pub fn pota_log_replace_plan(
    jobs: Vec<FfiPotaJobWindow>,
    elapsed_seconds: f64,
) -> FfiPotaLogReplacePlan {
    let windows: Vec<PotaJobWindow> = jobs
        .into_iter()
        .map(|job| PotaJobWindow {
            job_id: job.job_id,
            status: job.status,
            self_delete_seconds_remaining: job.self_delete_seconds_remaining,
        })
        .collect();
    plan_log_replace(&windows, elapsed_seconds).into()
}

/// Path (relative to `https://api.pota.app`) that removes an upload job.
/// Send an authenticated `POST` with an empty JSON object body.
#[uniffi::export]
pub fn pota_remove_job_path(job_id: i64) -> String {
    remove_job_path(job_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_page_with_derived_fields() {
        let json = r#"{"count": 1, "pending": 0, "entries": [
            {"jobId": 9, "status": 2, "reference": "US-1234", "total": 4, "inserted": 4,
             "firstQSO": "2026-11-14T23:58:00", "selfDeleteSecondsRemaining": 600}]}"#;
        let page = decode_pota_jobs_page(json.into()).unwrap();
        let job = &page.entries[0];
        assert_eq!(job.first_qso_utc_date.as_deref(), Some("2026-11-14"));
        assert_eq!(job.self_delete_seconds_remaining, 600.0);
        assert!(!job.is_removed);
        assert!(decode_pota_jobs_page("{}".into()).is_none());
    }

    #[test]
    fn plan_round_trips() {
        let job = |job_id, status, remaining| FfiPotaJobWindow {
            job_id,
            status,
            self_delete_seconds_remaining: remaining,
        };
        let plan = pota_log_replace_plan(vec![job(2, 2, 900.0), job(1, 3, 0.0)], 100.0);
        assert_eq!(plan.remove_job_ids, vec![2]);
        assert_eq!(plan.seconds_left, 800.0);
        assert!(plan.blocker.is_none());

        let blocked = pota_log_replace_plan(vec![job(2, 2, 0.0)], 0.0);
        assert_eq!(blocked.blocker, Some(FfiPotaLogReplaceBlocker::WindowExpired));
        assert_eq!(pota_remove_job_path(42), "/admin/jobs/remove/42");
    }
}
