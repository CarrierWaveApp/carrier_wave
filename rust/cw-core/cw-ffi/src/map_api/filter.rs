use chrono::{TimeZone, Utc};

use super::records::FfiMapFilter;

/// Build a logbook-DSL query string from the structured map filter.
/// `confirmed_only` intentionally excluded — it is applied as SQL by
/// `qso_map_rows`, not via the DSL.
pub(crate) fn filter_query_string(f: &FfiMapFilter) -> String {
    let mut parts: Vec<String> = Vec::new();
    if let Some(band) = &f.band {
        parts.push(format!("band:{band}"));
    }
    if let Some(mode) = &f.mode {
        parts.push(format!("mode:{mode}"));
    }
    if let Some(park) = &f.park {
        parts.push(format!("park:{park}"));
    }
    if let Some(start) = f.start_date {
        parts.push(format!("after:{}", day_string(start)));
    }
    if let Some(end) = f.end_date {
        parts.push(format!("before:{}", day_string(end)));
    }
    parts.join(" ")
}

fn day_string(unix: i64) -> String {
    Utc.timestamp_opt(unix, 0)
        .single()
        .map(|dt| dt.format("%Y-%m-%d").to_string())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::map_api::records::FfiMapFilter;

    fn base() -> FfiMapFilter {
        FfiMapFilter {
            band: None,
            mode: None,
            park: None,
            start_date: None,
            end_date: None,
            confirmed_only: false,
            show_individual: false,
            show_paths: false,
            max_qsos: Some(500),
        }
    }

    #[test]
    fn empty_filter_is_empty_query() {
        assert_eq!(filter_query_string(&base()), "");
    }

    #[test]
    fn full_filter_builds_dsl() {
        let f = FfiMapFilter {
            band: Some("20m".into()),
            mode: Some("CW".into()),
            park: Some("US-0001".into()),
            start_date: Some(1_767_225_600), // 2026-01-01 UTC
            end_date: Some(1_769_904_000),   // 2026-02-01 UTC
            ..base()
        };
        assert_eq!(
            filter_query_string(&f),
            "band:20m mode:CW park:US-0001 after:2026-01-01 before:2026-02-01"
        );
    }

    // The built string must round-trip through the real DSL parser.
    #[test]
    fn built_query_parses() {
        let f = FfiMapFilter {
            band: Some("40m".into()),
            ..base()
        };
        assert!(cw_domain::query::parse(&filter_query_string(&f)).is_ok());
    }
}
