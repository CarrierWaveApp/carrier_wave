//! Callsign enrichment aggregator.
//!
//! Polls each enabled source in `callsign_enrichment_sources` once per
//! `cycle_hours`, parses the response according to the source's `format`
//! column, and replaces all rows for that source in one transaction. Stale
//! rows are removed on each refresh, so callsigns dropped from upstream
//! lists vanish cleanly.
//!
//! Format support:
//!   - `polo`  Ham2K PoLo callsign-notes format. One callsign per line:
//!             `CALL ⟨emoji?⟩ Operator Name <text...> #NNNN`
//!             Hash followed by digits is the member number; everything
//!             between the emoji (or callsign) and the `#NNNN` is the name.

use std::time::Duration;

use sqlx::PgPool;

use crate::db::callsign_enrichment;
use crate::metrics as app_metrics;

pub struct CallsignEnrichmentConfig {
    pub cycle_hours: u64,
}

pub async fn poll_loop(pool: PgPool, client: reqwest::Client, config: CallsignEnrichmentConfig) {
    let cycle = Duration::from_secs(config.cycle_hours.saturating_mul(3600).max(60));
    // First refresh fires almost immediately so a fresh deploy has data.
    let mut next_sleep = Duration::from_secs(30);

    loop {
        tokio::time::sleep(next_sleep).await;
        next_sleep = cycle;

        let sources = match callsign_enrichment::list_enabled_sources(&pool).await {
            Ok(s) => s,
            Err(e) => {
                tracing::error!("callsign-enrichment: list sources failed: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "callsign_enrichment").increment(1);
                continue;
            }
        };

        for source in sources {
            if let Err(e) = refresh_source(&pool, &client, &source).await {
                tracing::error!(
                    "callsign-enrichment[{}]: refresh failed: {}",
                    source.slug,
                    e
                );
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "callsign_enrichment").increment(1);
                let _ = callsign_enrichment::record_source_failure(
                    &pool,
                    &source.slug,
                    &e.to_string(),
                )
                .await;
            }
        }
    }
}

type AggregatorError = Box<dyn std::error::Error + Send + Sync>;

async fn refresh_source(
    pool: &PgPool,
    client: &reqwest::Client,
    source: &callsign_enrichment::EnrichmentSource,
) -> Result<(), AggregatorError> {
    let mut req = client
        .get(&source.url)
        .timeout(Duration::from_secs(60))
        .header("User-Agent", "carrier-wave-server/callsign-enrichment");
    if let Some(etag) = &source.last_etag {
        req = req.header(reqwest::header::IF_NONE_MATCH, etag);
    }

    let resp = req.send().await?;
    let status = resp.status();
    if status.as_u16() == 304 {
        callsign_enrichment::record_source_success(
            pool,
            &source.slug,
            source.last_etag.as_deref(),
            "http-304",
        )
        .await?;
        tracing::debug!("callsign-enrichment[{}]: 304 not modified", source.slug);
        return Ok(());
    }
    if !status.is_success() {
        return Err(format!("HTTP {}", status).into());
    }

    let etag = resp
        .headers()
        .get(reqwest::header::ETAG)
        .and_then(|h| h.to_str().ok())
        .map(|s| s.to_string());

    let body = resp.text().await?;

    let entries = match source.format.as_str() {
        "polo" => parse_polo(&body),
        other => return Err(format!("unsupported format '{}'", other).into()),
    };

    let count = entries.len();
    callsign_enrichment::replace_source_rows(pool, &source.slug, &entries).await?;
    callsign_enrichment::record_source_success(pool, &source.slug, etag.as_deref(), "ok").await?;

    tracing::info!(
        "callsign-enrichment[{}]: refreshed {} entries",
        source.slug,
        count
    );
    Ok(())
}

/// Parse the Ham2K PoLo callsign-notes format.
///
/// Each non-comment line is `CALL [emoji?] [name tokens...] [#NNNN] [trailing
/// text]`. Comments start with `#`. The first whitespace-separated token is
/// the callsign (uppercased). After that we look for the first `#NNNN`
/// substring as the member number; everything between the callsign and that
/// `#NNNN` (excluding any leading emoji) becomes the operator name.
pub fn parse_polo(body: &str) -> Vec<callsign_enrichment::ParsedEntry> {
    let mut out = Vec::new();
    for line in body.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        let Some((callsign_tok, rest)) = trimmed.split_once(char::is_whitespace) else {
            continue;
        };
        let callsign = callsign_tok.trim().to_uppercase();
        if callsign.is_empty() {
            continue;
        }
        let rest = rest.trim();

        // Find a "#NNNN" run anywhere in the rest of the line.
        let (member_number, before_hash, after_hash) = match find_member_number(rest) {
            Some((num, before, after)) => (Some(num), before, after),
            None => (None, rest.to_string(), String::new()),
        };

        // Pull off a leading emoji if present.
        let (emoji, name_text) = split_leading_emoji(&before_hash);

        let name = clean_name(&name_text, &callsign);
        let note = clean_note(&after_hash);

        out.push(callsign_enrichment::ParsedEntry {
            callsign,
            name,
            member_number,
            emoji,
            note,
        });
    }
    out
}

/// Locate `#NNNN` in `s`. Returns `(number, before, after)` slices.
fn find_member_number(s: &str) -> Option<(String, String, String)> {
    let bytes = s.as_bytes();
    let mut idx = 0;
    while idx < bytes.len() {
        if bytes[idx] == b'#' {
            let start = idx + 1;
            let mut end = start;
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                end += 1;
            }
            if end > start {
                let number = s[start..end].to_string();
                let before = s[..idx].trim().to_string();
                let after = s[end..].trim().to_string();
                return Some((number, before, after));
            }
        }
        idx += 1;
    }
    None
}

/// If the string starts with a single emoji-like character (or short emoji
/// cluster) followed by whitespace, split it off. We only treat the leading
/// run of non-ASCII characters up to the first whitespace as the emoji,
/// which is enough for the formats we ingest today.
fn split_leading_emoji(s: &str) -> (Option<String>, String) {
    let s = s.trim_start();
    let Some((first, rest)) = s.split_once(char::is_whitespace) else {
        if !s.is_empty() && !s.chars().next().is_some_and(|c| c.is_ascii_alphanumeric()) {
            return (Some(s.to_string()), String::new());
        }
        return (None, s.to_string());
    };
    if first.is_empty() {
        return (None, rest.to_string());
    }
    // Treat as emoji if no ASCII alphanumerics in the token.
    if !first.chars().any(|c| c.is_ascii_alphanumeric()) {
        (Some(first.to_string()), rest.trim().to_string())
    } else {
        (None, s.to_string())
    }
}

fn clean_name(raw: &str, callsign: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    // Strip a stray "CWops" / "SKCC" tail token that the formats sometimes leave.
    let upper = trimmed.to_uppercase();
    let stripped = ["CWOPS", "SKCC", "FISTS", "NAQCC", "BKG"]
        .iter()
        .find(|tag| upper.ends_with(*tag))
        .map(|tag| &trimmed[..trimmed.len() - tag.len()])
        .unwrap_or(trimmed);
    let cleaned = stripped.trim();
    if cleaned.is_empty() || cleaned.eq_ignore_ascii_case(callsign) {
        return None;
    }
    Some(cleaned.to_string())
}

fn clean_note(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() { None } else { Some(trimmed.to_string()) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_cwops_polo_lines() {
        let body = "# CWops Callsign Notes for Ham2K PoLo\n\
                    # Generated: 2026-04-03 15:45:15 UTC\n\
                    \n\
                    AA0FO 🎹 MARSHALL R CWops #1532\n\
                    AA1V 🎹 DONALD F CWops #53\n\
                    W6JY 🎹 Jay V CWops #9999\n";
        let entries = parse_polo(body);
        assert_eq!(entries.len(), 3);

        let aa0fo = &entries[0];
        assert_eq!(aa0fo.callsign, "AA0FO");
        assert_eq!(aa0fo.emoji.as_deref(), Some("🎹"));
        assert_eq!(aa0fo.name.as_deref(), Some("MARSHALL R"));
        assert_eq!(aa0fo.member_number.as_deref(), Some("1532"));

        let aa1v = &entries[1];
        assert_eq!(aa1v.callsign, "AA1V");
        assert_eq!(aa1v.member_number.as_deref(), Some("53"));

        let w6jy = &entries[2];
        assert_eq!(w6jy.callsign, "W6JY");
        assert_eq!(w6jy.name.as_deref(), Some("Jay V"));
        assert_eq!(w6jy.member_number.as_deref(), Some("9999"));
    }

    #[test]
    fn skips_comments_and_blank_lines() {
        let body = "\n# header\n   \nW1AW 🎹 Hiram CWops #1\n";
        let entries = parse_polo(body);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].callsign, "W1AW");
    }

    #[test]
    fn parses_bkg_polo_lines() {
        let body = "# BKG Callsign Notes for Ham2K PoLo\n\
                    # Generated: 2026-05-06 18:35:04 UTC\n\
                    AA6XV 🤜 Dave W BKG #29\n\
                    W6JY 🤜 Jay V BKG #16\n";
        let entries = parse_polo(body);
        assert_eq!(entries.len(), 2);

        let aa6xv = &entries[0];
        assert_eq!(aa6xv.callsign, "AA6XV");
        assert_eq!(aa6xv.emoji.as_deref(), Some("🤜"));
        assert_eq!(aa6xv.name.as_deref(), Some("Dave W"));
        assert_eq!(aa6xv.member_number.as_deref(), Some("29"));

        let w6jy = &entries[1];
        assert_eq!(w6jy.callsign, "W6JY");
        assert_eq!(w6jy.name.as_deref(), Some("Jay V"));
        assert_eq!(w6jy.member_number.as_deref(), Some("16"));
    }

    #[test]
    fn handles_missing_member_number() {
        let body = "K6XYZ 🎹 Some Op";
        let entries = parse_polo(body);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].callsign, "K6XYZ");
        assert_eq!(entries[0].member_number, None);
        assert_eq!(entries[0].name.as_deref(), Some("Some Op"));
    }
}
