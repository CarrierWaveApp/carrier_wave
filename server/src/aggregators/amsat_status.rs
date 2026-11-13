//! AMSAT community satellite status aggregator.
//!
//! Aggregates AMSAT's satellite status API (https://status.amsat.org/api/v1)
//! centrally so clients hit our endpoint instead of AMSAT (their status page
//! is a small volunteer-run service; one poller is politer than a fleet of
//! phones — and their usage guidelines ask for exactly that: one client
//! fetching everything in one request, server-side aggregation, polling no
//! more than every 5 minutes, a descriptive User-Agent).
//!
//! Each cycle:
//!   1. `GET catalog.php` — every satellite AMSAT tracks (names look like
//!      `SO-50_[FM]`, `AO-7_[U/v]`; one row per transmitter).
//!   2. `GET reports.php?since=…&limit=500` — every report newer than our
//!      cursor (the newest stored report minus a two-hour overlap), across
//!      all satellites in one request. If that page is full the window is
//!      re-read per satellite (first run after a deploy, or a long outage).
//!   3. Accumulate the raw reports in `amsat_report` (deduplicated on
//!      satellite/hour/callsign/verdict; a re-filed report replaces the
//!      verdict the same callsign gave for that 15-minute period).
//!   4. Summarize per satellite from the stored window (last Heard, last
//!      report, 24 h counts), attach curated NORAD ids, and replace the
//!      `amsat_status` table. Reports older than the window are pruned.
//!
//! Until AMSAT's data migration (2026-11-04) the new host answers with an
//! empty catalog, so an empty catalog falls back to the legacy host, which
//! already serves the same API and redirects to the new one afterwards.

use std::time::Duration;

use chrono::{DateTime, DurationRound, Utc};
use reqwest::header::USER_AGENT;
use serde::Deserialize;
use sqlx::PgPool;

use crate::db::amsat_status::{self, AmsatReportRow, AmsatStatusRow};
use crate::metrics as app_metrics;

/// AMSAT's status API (the host it moves to on 2026-11-04).
pub const DEFAULT_API_BASE: &str = "https://status.amsat.org/api/v1";
/// The same API on the old host; serves live data until the migration and
/// redirects afterwards.
const LEGACY_API_BASE: &str = "https://www.amsat.org/status/api/v1";
/// AMSAT asks API clients to identify themselves with a name, version, URL
/// and contact (generic library agents may be rate-limited or blocked).
const AMSAT_USER_AGENT: &str = concat!(
    "CarrierWave-ActivitiesServer/",
    env!("CARGO_PKG_VERSION"),
    " (+https://carrierwave.app; jaysvana@gmail.com)"
);
/// Largest page `reports.php` serves.
const PAGE_LIMIT: usize = 500;
/// Pause between per-satellite report queries (overflow path only).
const QUERY_PACING: Duration = Duration::from_millis(1000);
/// Report window served: 7 days, so `last_heard_at` can drive client-side
/// workability (a linear bird can have a quiet 24 h). The `*_24h` counts
/// are still computed against a 24 h cutoff.
const REPORT_WINDOW: chrono::Duration = chrono::Duration::hours(168);
/// How far behind the newest stored report the incremental poll starts.
/// AMSAT's `since` compares against the hour-quantised `hh:30Z` stamp, so
/// a cursor inside the current hour would skip that whole bucket; two
/// hours also re-reads replaced verdicts from the last cycle.
const CURSOR_OVERLAP: chrono::Duration = chrono::Duration::hours(2);
/// How long raw reports are kept — one day past the served window so the
/// oldest bucket of a 7-day grid is never half-pruned mid-cycle.
const REPORT_RETENTION: chrono::Duration = chrono::Duration::hours(168 + 24);

pub struct AmsatStatusConfig {
    pub cycle_minutes: u64,
    /// API base URL (`…/api/v1`); `None` means [`DEFAULT_API_BASE`].
    pub api_base: Option<String>,
}

pub async fn poll_loop(pool: PgPool, client: reqwest::Client, config: AmsatStatusConfig) {
    // AMSAT's floor is one poll every 5 minutes; ours stays at 10.
    let cycle = Duration::from_secs(config.cycle_minutes.saturating_mul(60).max(600));
    let api_base = config
        .api_base
        .as_deref()
        .map(|base| base.trim_end_matches('/').to_string())
        .unwrap_or_else(|| DEFAULT_API_BASE.to_string());
    // First refresh fires almost immediately so a fresh deploy has data.
    let mut next_sleep = Duration::from_secs(30);

    loop {
        tokio::time::sleep(next_sleep).await;
        next_sleep = cycle;

        if let Err(e) = refresh(&pool, &client, &api_base).await {
            tracing::error!("amsat-status: refresh failed: {}", e);
            metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "amsat_status")
                .increment(1);
        }
    }
}

type AggregatorError = Box<dyn std::error::Error + Send + Sync>;

/// AMSAT's JSON envelope: `data` plus optional `meta`/`links`.
#[derive(Debug, Deserialize)]
struct Envelope<T> {
    data: T,
}

/// One `catalog.php` row. `name` is the API name (`SO-50_[FM]`);
/// `display_name` is the human form (`SO-50 [FM]`).
#[derive(Debug, Deserialize)]
struct CatalogEntry {
    name: String,
}

/// One report row from `reports.php` (also the shape of `sat_info.php`
/// minus `period`).
#[derive(Debug, Deserialize)]
struct AmsatReport {
    name: String,
    reported_time: String,
    callsign: String,
    report: String,
    grid_square: Option<String>,
    /// 15-minute slot within the hour, 0–3.
    #[serde(default)]
    period: Option<i16>,
}

async fn refresh(
    pool: &PgPool,
    client: &reqwest::Client,
    api_base: &str,
) -> Result<(), AggregatorError> {
    let (base, names) = fetch_catalog(client, api_base).await?;
    if names.is_empty() {
        return Err("empty satellite catalog from AMSAT".into());
    }

    let now = Utc::now();
    let latest = match amsat_status::latest_reported_at(pool).await {
        Ok(latest) => latest,
        Err(e) => {
            tracing::warn!(
                "amsat-status: cursor read failed, refetching the window: {}",
                e
            );
            None
        }
    };
    let since = cursor(latest, now);
    let fetched = fetch_reports(client, &base, &names, since).await?;
    let parsed = parse_reports(&fetched);
    let fetched_count = parsed.len();

    let rows: Vec<AmsatReportRow> = parsed
        .iter()
        .map(|r| AmsatReportRow {
            name: r.name.clone(),
            reported_at: r.time,
            callsign: r.callsign.clone(),
            report: r.report.clone(),
            grid: r.grid.clone(),
            period: r.period,
        })
        .collect();
    let new_reports = match amsat_status::insert_reports(pool, &rows).await {
        Ok(inserted) => inserted,
        Err(e) => {
            tracing::warn!("amsat-status: report store failed: {}", e);
            0
        }
    };

    // Summarize every catalogued satellite from the stored window. A store
    // read failure falls back to what this cycle fetched so the summary is
    // never worse than before.
    let window_start = now - REPORT_WINDOW;
    let mut summaries = Vec::with_capacity(names.len());
    for name in &names {
        let window: Vec<ParsedReport> =
            match amsat_status::fetch_reports_since(pool, name, window_start).await {
                Ok(stored) => stored
                    .into_iter()
                    .map(|r| ParsedReport {
                        name: r.name,
                        time: r.reported_at,
                        callsign: r.callsign,
                        report: r.report,
                        grid: r.grid,
                        period: r.period,
                    })
                    .collect(),
                Err(e) => {
                    tracing::warn!("amsat-status[{}]: window read failed: {}", name, e);
                    parsed.iter().filter(|r| &r.name == name).cloned().collect()
                }
            };
        summaries.push(summarize(name, &window, now));
    }

    let count = summaries.len();
    amsat_status::replace_all(pool, &summaries).await?;
    match amsat_status::prune_reports_before(pool, now - REPORT_RETENTION).await {
        Ok(pruned) => tracing::info!(
            "amsat-status: refreshed {} satellites via {} ({} reports fetched since {}, {} new, {} pruned)",
            count,
            base,
            fetched_count,
            since_param(since),
            new_reports,
            pruned
        ),
        Err(e) => tracing::warn!("amsat-status: prune failed: {}", e),
    }
    Ok(())
}

/// Where the incremental poll starts: two hours behind the newest stored
/// report, never further back than the served window, aligned to the hour.
fn cursor(latest_stored: Option<DateTime<Utc>>, now: DateTime<Utc>) -> DateTime<Utc> {
    let floor = now - REPORT_WINDOW;
    let since = latest_stored
        .map(|latest| (latest - CURSOR_OVERLAP).max(floor))
        .unwrap_or(floor);
    since
        .duration_trunc(chrono::Duration::hours(1))
        .unwrap_or(since)
}

/// AMSAT's `since` is compared textually against `YYYY-MM-DDThh:30:00Z`
/// stamps, so it must be sent in exactly that layout (no fractions).
fn since_param(since: DateTime<Utc>) -> String {
    since.format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

async fn get_json<T: serde::de::DeserializeOwned>(
    client: &reqwest::Client,
    url: &str,
    query: &[(&str, String)],
) -> Result<T, AggregatorError> {
    let resp = client
        .get(url)
        .header(USER_AGENT, AMSAT_USER_AGENT)
        .query(query)
        .send()
        .await?
        .error_for_status()?;
    Ok(resp.json().await?)
}

/// The satellite list, with the API base it came from. An empty catalog on
/// the configured host (the new host before AMSAT's data migration) falls
/// back to the legacy host.
async fn fetch_catalog(
    client: &reqwest::Client,
    api_base: &str,
) -> Result<(String, Vec<String>), AggregatorError> {
    let names = fetch_catalog_names(client, api_base).await?;
    if !names.is_empty() || api_base == LEGACY_API_BASE {
        return Ok((api_base.to_string(), names));
    }
    tracing::info!(
        "amsat-status: empty catalog at {}, falling back to {}",
        api_base,
        LEGACY_API_BASE
    );
    let legacy = fetch_catalog_names(client, LEGACY_API_BASE).await?;
    Ok((LEGACY_API_BASE.to_string(), legacy))
}

async fn fetch_catalog_names(
    client: &reqwest::Client,
    api_base: &str,
) -> Result<Vec<String>, AggregatorError> {
    let envelope: Envelope<Vec<CatalogEntry>> =
        get_json(client, &format!("{api_base}/catalog.php"), &[]).await?;
    Ok(envelope.data.into_iter().map(|entry| entry.name).collect())
}

/// Every report since `since`: one request across all satellites, or — when
/// that page is full (first run, long outage) — one paced request per
/// satellite so nothing older than the page is lost.
async fn fetch_reports(
    client: &reqwest::Client,
    api_base: &str,
    names: &[String],
    since: DateTime<Utc>,
) -> Result<Vec<AmsatReport>, AggregatorError> {
    let url = format!("{api_base}/reports.php");
    let since = since_param(since);
    let page: Envelope<Vec<AmsatReport>> = get_json(
        client,
        &url,
        &[("since", since.clone()), ("limit", PAGE_LIMIT.to_string())],
    )
    .await?;
    if page.data.len() < PAGE_LIMIT {
        return Ok(page.data);
    }

    tracing::info!(
        "amsat-status: {} reports since {} fill a page, re-reading per satellite",
        page.data.len(),
        since
    );
    let mut all = Vec::new();
    for name in names {
        match get_json::<Envelope<Vec<AmsatReport>>>(
            client,
            &url,
            &[
                ("name", name.clone()),
                ("since", since.clone()),
                ("limit", PAGE_LIMIT.to_string()),
            ],
        )
        .await
        {
            Ok(page) => {
                if page.data.len() >= PAGE_LIMIT {
                    tracing::warn!(
                        "amsat-status[{}]: {} reports since {} truncated at the page limit",
                        name,
                        page.data.len(),
                        since
                    );
                }
                all.extend(page.data);
            }
            Err(e) => tracing::warn!("amsat-status[{}]: report fetch failed: {}", name, e),
        }
        tokio::time::sleep(QUERY_PACING).await;
    }
    if all.is_empty() {
        return Err("every per-satellite report query failed".into());
    }
    Ok(all)
}

/// One report with its timestamp parsed — the shape both the fresh API
/// response and the stored window reduce to.
#[derive(Debug, Clone, PartialEq)]
struct ParsedReport {
    name: String,
    time: DateTime<Utc>,
    callsign: String,
    report: String,
    grid: Option<String>,
    period: Option<i16>,
}

/// Parse the wire rows, dropping any with an unparseable timestamp.
fn parse_reports(reports: &[AmsatReport]) -> Vec<ParsedReport> {
    reports
        .iter()
        .filter_map(|report| {
            let time = match DateTime::parse_from_rfc3339(&report.reported_time) {
                Ok(time) => time.with_timezone(&Utc),
                Err(e) => {
                    tracing::debug!(
                        "amsat-status[{}]: skipping report with bad time {:?}: {}",
                        report.name,
                        report.reported_time,
                        e
                    );
                    return None;
                }
            };
            Some(ParsedReport {
                name: report.name.clone(),
                time,
                callsign: report.callsign.clone(),
                report: report.report.clone(),
                grid: report.grid_square.clone(),
                period: report.period,
            })
        })
        .collect()
}

/// Collapse a satellite's report window into one row: `last_*` fields span
/// the whole 7-day window, the `*_24h` counts use a 24 h cutoff. Input
/// order is irrelevant; maxima are computed explicitly.
fn summarize(name: &str, reports: &[ParsedReport], now: DateTime<Utc>) -> AmsatStatusRow {
    let cutoff_24h = now - chrono::Duration::hours(24);
    let mut last_heard_at: Option<DateTime<Utc>> = None;
    let mut latest: Option<(DateTime<Utc>, &ParsedReport)> = None;
    let mut heard_24h = 0;
    let mut total_24h = 0;

    for report in reports {
        let time = report.time;
        let heard = report.report.eq_ignore_ascii_case("heard");
        if time >= cutoff_24h {
            total_24h += 1;
            if heard {
                heard_24h += 1;
            }
        }
        if heard && last_heard_at.is_none_or(|t| time > t) {
            last_heard_at = Some(time);
        }
        if latest.as_ref().is_none_or(|(t, _)| time > *t) {
            latest = Some((time, report));
        }
    }

    AmsatStatusRow {
        name: name.to_string(),
        norad_id: norad_id(name),
        last_heard_at,
        last_reported_at: latest.map(|(t, _)| t),
        last_report: latest.map(|(_, r)| r.report.clone()),
        last_callsign: latest.map(|(_, r)| r.callsign.clone()),
        last_grid: latest.and_then(|(_, r)| r.grid.clone()),
        heard_reports_24h: heard_24h,
        total_reports_24h: total_24h,
        updated_at: now,
    }
}

/// Curated AMSAT-name → NORAD id mapping for well-known birds. AMSAT names
/// carry a transmitter suffix (`AO-7_[A]`, `AO-7_[B]`), so we key on the
/// base. Unknown satellites keep a NULL norad_id; clients fall back to the
/// bare name.
fn norad_id(name: &str) -> Option<i64> {
    let base = name.split("_[").next().unwrap_or(name);
    let id = match base {
        "ISS" => 25544,
        "SO-50" => 27607,
        "AO-7" => 7530,
        "AO-27" => 22825,
        "AO-73" => 39444,
        "AO-91" => 43017,
        "AO-92" => 43137,
        "FO-29" => 24278,
        "RS-44" => 44909,
        "QO-100" => 43700,
        "PO-101" => 43678,
        "IO-117" => 52017,
        "JO-97" => 43803,
        "EO-88" => 42017,
        "CAS-4A" => 42761,
        "CAS-4B" => 42759,
        "AO-123" => 61781, // ASRTU-1
        "CO-128" => 98272, // MARMOTSat (SatNOGS temporary id)
        "CroCube" => 62394,
        "GRBBeta" => 60237,
        "IO-86" => 40931, // LAPAN-A2
        "KNACKSAT-2" => 67683,
        "LASARsat" => 62391,
        "Luca" => 98449,   // SatNOGS temporary id
        "Marina" => 98293, // SatNOGS temporary id
        "NO-44" => 26931,  // PCSAT
        "OTP-2" => 63235,
        "Replicator-2" => 98267, // SatNOGS temporary id
        "RS18S" => 67290,        // SakhaCube-Cholbon
        "RS27S" => 57203,        // UTMN2
        "RS38S" => 57189,        // VIZARD-meteo
        "RS40S" => 57172,        // UmKA-1
        "RS57S" => 57182,        // Monitor-4
        "RS58S" => 57180,        // Monitor-3
        "RS61S" => 64881,        // 239Alferov
        "RS92S2" => 64890,       // Geoscan-2
        "RS92S4" => 64892,       // Geoscan-4
        "RS92S5" => 64891,       // Geoscan-5
        "RS95S" => 67291,        // QMR-KWT 2
        "SO-127" => 68446,       // HADES-SA (SpinnyONE)
        "SONATE-2" => 59112,
        "TEVEL2-7" => 63238,
        "TEVEL2-8" => 63239,
        "UO-11" => 14781,  // UoSAT-2
        "TO-108" => 44881, // CAS-6
        "TEVEL2-3" => 63218,
        "FO-126" => 68795,       // OrigamiSat-2
        "HC1PX" => 67279,        // GALAPAGOS-UTE-SWSU
        "KOSTKA" => 98395,       // SatNOGS temporary id
        "ARICA-2" => 98329,      // SatNOGS temporary id
        "BY70-4" => 98247,       // SatNOGS temporary id
        "RS83S" => 98429,        // Lobachevsky (SatNOGS temporary id)
        "RS90S" => 98449,        // Luca (SatNOGS temporary id)
        "OPTISAT" => 98370,      // SatNOGS temporary id
        "T.Microsat-1" => 98515, // SatNOGS temporary id
        "JAMX01" => 98248,       // SatNOGS temporary id
        _ => return None,
    };
    Some(id)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(rfc3339: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(rfc3339)
            .unwrap()
            .with_timezone(&Utc)
    }

    fn wire(
        name: &str,
        time: &str,
        callsign: &str,
        report: &str,
        grid: Option<&str>,
    ) -> AmsatReport {
        AmsatReport {
            name: name.into(),
            reported_time: time.into(),
            callsign: callsign.into(),
            report: report.into(),
            grid_square: grid.map(str::to_string),
            period: Some(2),
        }
    }

    #[test]
    fn decodes_catalog_and_reports_envelopes() {
        let catalog: Envelope<Vec<CatalogEntry>> = serde_json::from_str(
            r#"{"data":[
                {"id":153,"name":"AO-123_[FM]","display_name":"AO-123 [FM]",
                 "website":"https://www.amsat.org/live-fm-satellites/",
                 "links":{"self":"x","reports":"y"},
                 "report_count":2241,"latest_reported_time":"2026-10-31T13:30:00Z"},
                {"id":2,"name":"AO-7_[U/v]","display_name":"AO-7 [U/v]","website":""}
            ],"meta":{"count":2}}"#,
        )
        .unwrap();
        let names: Vec<_> = catalog.data.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, ["AO-123_[FM]", "AO-7_[U/v]"]);

        let reports: Envelope<Vec<AmsatReport>> = serde_json::from_str(
            r#"{"data":[
                {"id":1370577,"name":"ISS_[UHF_Digi]","satellite_display_name":"ISS [UHF Digi]",
                 "reported_time":"2026-10-31T13:30:00Z","callsign":"JF6BCC/437825",
                 "report":"Heard","grid_square":"PM53jv","period":2},
                {"id":1,"name":"SO-50_[FM]","reported_time":"2026-10-31T12:30:00Z",
                 "callsign":"K1ABC","report":"Not Heard","grid_square":null}
            ],"meta":{"count":2,"limit":500,"since":"2026-10-30T13:00:00Z","hours":72}}"#,
        )
        .unwrap();
        let parsed = parse_reports(&reports.data);
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].name, "ISS_[UHF_Digi]");
        assert_eq!(parsed[0].period, Some(2));
        assert_eq!(parsed[0].grid.as_deref(), Some("PM53jv"));
        assert_eq!(parsed[1].period, None);
        assert_eq!(parsed[1].time, at("2026-10-31T12:30:00Z"));
    }

    #[test]
    fn cursor_overlaps_two_hours_and_aligns_to_the_hour() {
        let now = at("2026-10-31T14:12:08Z");
        // Newest stored report at 13:30 → 11:30 → truncated to 11:00, so the
        // 11:30 bucket is re-read (AMSAT's since is a textual >= on hh:30Z).
        assert_eq!(
            cursor(Some(at("2026-10-31T13:30:00Z")), now),
            at("2026-10-31T11:00:00Z")
        );
        // Nothing stored: the whole served window.
        assert_eq!(cursor(None, now), at("2026-10-24T14:00:00Z"));
        // A stale store never asks for more than the window.
        assert_eq!(
            cursor(Some(at("2026-09-01T00:30:00Z")), now),
            at("2026-10-24T14:00:00Z")
        );
        assert_eq!(since_param(cursor(None, now)), "2026-10-24T14:00:00Z");
    }

    #[test]
    fn summarize_windows_counts_and_finds_last_heard() {
        let reports = vec![
            // Inside the 7-day window but older than 24h: feeds last_heard_at
            // without counting toward the 24h totals.
            wire(
                "SO-50_[FM]",
                "2026-09-16T10:30:00Z",
                "EA7LKM",
                "Heard",
                Some("IM87"),
            ),
            wire(
                "SO-50_[FM]",
                "2026-09-20T13:30:00Z",
                "ON7VQ",
                "Heard",
                Some("JO20gv"),
            ),
            wire(
                "SO-50_[FM]",
                "2026-09-20T14:30:00Z",
                "K1ABC",
                "Not Heard",
                None,
            ),
        ];
        let now = at("2026-09-20T15:00:00Z");
        let parsed = parse_reports(&reports);
        assert_eq!(parsed.len(), 3);
        let row = summarize("SO-50_[FM]", &parsed, now);
        assert_eq!(row.norad_id, Some(27607));
        assert_eq!(row.heard_reports_24h, 1);
        assert_eq!(row.total_reports_24h, 2);
        assert_eq!(row.last_report.as_deref(), Some("Not Heard"));
        assert_eq!(row.last_callsign.as_deref(), Some("K1ABC"));
        assert_eq!(
            row.last_heard_at.unwrap().to_rfc3339(),
            "2026-09-20T13:30:00+00:00"
        );
    }

    #[test]
    fn parse_reports_drops_unparseable_timestamps() {
        let reports = vec![
            wire("SO-50_[FM]", "not a time", "K1ABC", "Heard", None),
            wire(
                "SO-50_[FM]",
                "2026-09-20T13:30:00Z",
                "ON7VQ",
                "Heard",
                Some("JO20gv"),
            ),
        ];
        let parsed = parse_reports(&reports);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].callsign, "ON7VQ");
        assert_eq!(parsed[0].grid.as_deref(), Some("JO20gv"));
    }

    #[test]
    fn user_agent_identifies_the_client() {
        assert!(AMSAT_USER_AGENT.starts_with("CarrierWave-ActivitiesServer/"));
        assert!(AMSAT_USER_AGENT.contains("+https://carrierwave.app"));
    }

    #[test]
    fn norad_mapping_strips_transmitter_suffix() {
        assert_eq!(norad_id("AO-7_[A]"), Some(7530));
        assert_eq!(norad_id("AO-7_[B]"), Some(7530));
        assert_eq!(norad_id("AO-123_[FM]"), Some(61781));
        assert_eq!(norad_id("NO-44_[VHF_Digi]"), Some(26931));
        assert_eq!(norad_id("SO-127_[CODEC2]"), Some(68446));
        assert_eq!(norad_id("TEVEL2-7_[FM]"), Some(63238));
        assert_eq!(norad_id("TO-108_[U/v]"), Some(44881));
        assert_eq!(norad_id("T.Microsat-1_[Music]"), Some(98515));
        assert_eq!(norad_id("MYSTERY-1_[FM]"), None);
    }
}
