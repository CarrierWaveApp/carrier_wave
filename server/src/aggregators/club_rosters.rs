//! Club roster aggregator.
//!
//! Every club with a `notes_url` (a Ham2K PoLo callsign-notes file such as
//! `https://www.bkg.club/members.txt`) has its roster reconciled against that
//! file once per `cycle_hours`. Callsigns new to the file are added as
//! `member`; `member`-role rows that have left the file are removed; `admin`
//! rows are never touched. The same routine backs the admin
//! `POST /v1/admin/clubs/:id/import-notes` endpoint so a manual import and a
//! scheduled pass behave identically.
//!
//! Before this existed the roster was a one-time snapshot: the import was
//! add-only and only ran when an admin pressed the button, so a club's
//! roster silently fell behind its published list (BKG sat at ~30 members
//! while the list grew past 500).

use std::collections::HashSet;
use std::time::Duration;

use sqlx::PgPool;

use crate::db::clubs::{self, RosterReconcile};
use crate::metrics as app_metrics;
use crate::models::club::Club;

pub struct ClubRostersConfig {
    pub cycle_hours: u64,
}

pub type AggregatorError = Box<dyn std::error::Error + Send + Sync>;

pub async fn poll_loop(pool: PgPool, client: reqwest::Client, config: ClubRostersConfig) {
    let cycle = Duration::from_secs(config.cycle_hours.saturating_mul(3600).max(60));
    // First pass fires shortly after boot so a stale roster heals on deploy.
    let mut next_sleep = Duration::from_secs(60);

    loop {
        tokio::time::sleep(next_sleep).await;
        next_sleep = cycle;

        let clubs = match clubs::list_clubs_with_notes_url(&pool).await {
            Ok(c) => c,
            Err(e) => {
                tracing::error!("club-rosters: list clubs failed: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "club_rosters")
                    .increment(1);
                continue;
            }
        };

        for club in clubs {
            match sync_club_roster(&pool, &client, &club).await {
                Ok(outcome) => {
                    if !outcome.added.is_empty() || !outcome.removed.is_empty() {
                        tracing::info!(
                            club = %club.name,
                            added = outcome.added.len(),
                            removed = outcome.removed.len(),
                            unchanged = outcome.unchanged,
                            "club-rosters: roster updated"
                        );
                    } else {
                        tracing::debug!(club = %club.name, "club-rosters: roster unchanged");
                    }
                }
                Err(e) => {
                    tracing::error!(club = %club.name, "club-rosters: sync failed: {}", e);
                    metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "club_rosters")
                        .increment(1);
                }
            }
        }
    }
}

/// Fetch the club's notes file and reconcile the roster against it. Records
/// the outcome (`ok` / `error: …`) on the club row either way.
pub async fn sync_club_roster(
    pool: &PgPool,
    client: &reqwest::Client,
    club: &Club,
) -> Result<RosterReconcile, AggregatorError> {
    let result = fetch_and_reconcile(pool, client, club).await;
    let status = match &result {
        Ok(_) => "ok".to_string(),
        Err(e) => format!("error: {}", e),
    };
    if let Err(e) = clubs::record_roster_sync(pool, club.id, &status).await {
        tracing::warn!(club = %club.name, "club-rosters: record status failed: {}", e);
    }
    result
}

async fn fetch_and_reconcile(
    pool: &PgPool,
    client: &reqwest::Client,
    club: &Club,
) -> Result<RosterReconcile, AggregatorError> {
    let notes_url = club
        .notes_url
        .as_deref()
        .filter(|u| !u.trim().is_empty())
        .ok_or("club has no notes URL configured")?;

    let resp = client
        .get(notes_url)
        .timeout(Duration::from_secs(60))
        .send()
        .await
        .map_err(|e| format!("fetch failed: {}", e))?;
    let status = resp.status();
    if !status.is_success() {
        return Err(format!("HTTP {}", status).into());
    }
    let body = resp
        .text()
        .await
        .map_err(|e| format!("read failed: {}", e))?;

    let callsigns = parse_notes_callsigns(&body);
    // An empty list is far more likely to be an upstream outage (blank page,
    // moved file, HTML error body) than a club that really has no members.
    // Refuse rather than delete everyone.
    if callsigns.is_empty() {
        return Err("notes file contained no callsigns; roster left untouched".into());
    }

    Ok(clubs::reconcile_roster(pool, club.id, &callsigns).await?)
}

/// Extract the roster from a Ham2K PoLo callsign-notes file: one callsign per
/// line as the first whitespace-separated token, `#` comment lines and blank
/// lines ignored. Callsigns are uppercased and deduplicated, preserving first
/// appearance order.
pub fn parse_notes_callsigns(body: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for line in body.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let Some(tok) = trimmed.split_whitespace().next() else {
            continue;
        };
        let callsign = tok.to_uppercase();
        if seen.insert(callsign.clone()) {
            out.push(callsign);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_bkg_notes_file() {
        let body = "# BKG Callsign Notes for Ham2K PoLo\n\
                    # Generated: 2026-09-26 15:39:39 UTC\n\
                    \n\
                    9A2NB 🤜 Aldo S BKG #538 (Croatia OG)\n\
                    aa6xv 🤜 Dave W BKG #29\n\
                    W6JY 🤜 Jay V BKG #16\n";
        assert_eq!(parse_notes_callsigns(body), vec!["9A2NB", "AA6XV", "W6JY"]);
    }

    #[test]
    fn dedupes_and_skips_junk() {
        let body = "W1AW note\n\n   \n# comment\nw1aw again\nK6ARK\n";
        assert_eq!(parse_notes_callsigns(body), vec!["W1AW", "K6ARK"]);
    }

    #[test]
    fn empty_body_yields_no_callsigns() {
        assert!(parse_notes_callsigns("# only a header\n\n").is_empty());
    }
}
