//! Band-change compliance summary. Port of
//! `Services/Contest/BandChangeTracker.swift`.
//!
//! Caller is responsible for determining whether the rule applies to the
//! selected category (the tracker checks `applies_to` itself, same as Swift).

use std::collections::HashMap;

use chrono::{DateTime, Timelike, Utc};

use super::model::ContestBandChangeRules;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct BandChangeSummary {
    pub total_changes: i64,
    /// Count of band changes bucketed by clock-hour (start-of-hour in UTC).
    pub changes_per_hour: HashMap<DateTime<Utc>, i64>,
    pub violations: Vec<BandChangeViolation>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BandChangeViolation {
    TooManyChangesInClockHour { hour_start: DateTime<Utc>, count: i64, limit: i64 },
    LeftBandTooEarly {
        band: String,
        start: DateTime<Utc>,
        duration_seconds: f64,
        minimum_seconds: f64,
    },
}

/// Evaluate `operating_constraints.band_changes` against a chronological
/// list of QSOs.
pub fn summarize(
    qsos: &[(String, DateTime<Utc>)],
    category_id: Option<&str>,
    rules: Option<&ContestBandChangeRules>,
) -> BandChangeSummary {
    let Some(rules) = rules else {
        return BandChangeSummary::default();
    };
    if !applies_to(category_id, rules) {
        return BandChangeSummary::default();
    }

    let mut sorted: Vec<&(String, DateTime<Utc>)> = qsos.iter().collect();
    sorted.sort_by_key(|(_, timestamp)| *timestamp);

    let mut summary = BandChangeSummary::default();
    let mut previous: Option<&(String, DateTime<Utc>)> = None;

    for entry in sorted {
        if let Some(prev) = previous {
            if prev.0 != entry.0 {
                summary.total_changes += 1;
                record_hour_bucket(&mut summary, entry.1);
                record_min_on_band(&mut summary, prev, entry, rules);
            }
        }
        previous = Some(entry);
    }

    if let Some(limit) = rules.max_changes_per_clock_hour {
        // Deterministic violation order (HashMap iteration isn't).
        let mut over: Vec<(DateTime<Utc>, i64)> = summary
            .changes_per_hour
            .iter()
            .filter(|(_, count)| **count > limit)
            .map(|(hour, count)| (*hour, *count))
            .collect();
        over.sort_by_key(|(hour, _)| *hour);
        for (hour_start, count) in over {
            summary.violations.push(BandChangeViolation::TooManyChangesInClockHour {
                hour_start,
                count,
                limit,
            });
        }
    }

    summary
}

fn applies_to(category_id: Option<&str>, rules: &ContestBandChangeRules) -> bool {
    if rules.applies_to.is_empty() {
        return true;
    }
    let Some(category_id) = category_id else {
        return false;
    };
    rules.applies_to.iter().any(|applies| applies == category_id)
}

fn record_hour_bucket(summary: &mut BandChangeSummary, timestamp: DateTime<Utc>) {
    let hour_start = timestamp
        .with_minute(0)
        .and_then(|hour| hour.with_second(0))
        .and_then(|hour| hour.with_nanosecond(0))
        .unwrap_or(timestamp);
    *summary.changes_per_hour.entry(hour_start).or_insert(0) += 1;
}

fn record_min_on_band(
    summary: &mut BandChangeSummary,
    previous: &(String, DateTime<Utc>),
    current: &(String, DateTime<Utc>),
    rules: &ContestBandChangeRules,
) {
    let Some(min_on) = rules.min_minutes_on_band else {
        return;
    };
    let elapsed = (current.1 - previous.1).num_milliseconds() as f64 / 1_000.0;
    let minimum = (min_on * 60) as f64;
    if elapsed < minimum {
        summary.violations.push(BandChangeViolation::LeftBandTooEarly {
            band: previous.0.clone(),
            start: previous.1,
            duration_seconds: elapsed,
            minimum_seconds: minimum,
        });
    }
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, TimeZone};

    use super::*;

    fn base() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 4, 0, 0, 0).unwrap()
    }

    fn qso(band: &str, minutes: i64) -> (String, DateTime<Utc>) {
        (band.to_string(), base() + Duration::minutes(minutes))
    }

    #[test]
    fn counts_changes_and_hour_buckets() {
        let rules = ContestBandChangeRules {
            applies_to: vec![],
            min_minutes_on_band: None,
            max_changes_per_clock_hour: Some(2),
        };
        let qsos = vec![
            qso("20m", 0),
            qso("40m", 10),
            qso("20m", 20),
            qso("40m", 30),
            qso("40m", 40),
            qso("20m", 70),
        ];
        let summary = summarize(&qsos, None, Some(&rules));
        assert_eq!(summary.total_changes, 4);
        assert_eq!(summary.changes_per_hour.get(&base()), Some(&3));
        assert_eq!(
            summary.changes_per_hour.get(&(base() + Duration::hours(1))),
            Some(&1)
        );
        assert_eq!(summary.violations.len(), 1);
        assert!(matches!(
            summary.violations[0],
            BandChangeViolation::TooManyChangesInClockHour { count: 3, limit: 2, .. }
        ));
    }

    #[test]
    fn min_minutes_on_band_violation() {
        let rules = ContestBandChangeRules {
            applies_to: vec![],
            min_minutes_on_band: Some(10),
            max_changes_per_clock_hour: None,
        };
        let qsos = vec![qso("20m", 0), qso("40m", 5)];
        let summary = summarize(&qsos, None, Some(&rules));
        assert_eq!(summary.violations.len(), 1);
        assert!(matches!(
            &summary.violations[0],
            BandChangeViolation::LeftBandTooEarly { band, .. } if band == "20m"
        ));
    }

    #[test]
    fn applies_to_gates_by_category() {
        let rules = ContestBandChangeRules {
            applies_to: vec!["MULTI".to_string()],
            min_minutes_on_band: None,
            max_changes_per_clock_hour: Some(1),
        };
        let qsos = vec![qso("20m", 0), qso("40m", 5)];
        assert_eq!(summarize(&qsos, Some("SO"), Some(&rules)), BandChangeSummary::default());
        assert_eq!(summarize(&qsos, None, Some(&rules)), BandChangeSummary::default());
        assert_eq!(summarize(&qsos, Some("MULTI"), Some(&rules)).total_changes, 1);
    }

    #[test]
    fn no_rules_means_empty_summary() {
        let qsos = vec![qso("20m", 0), qso("40m", 5)];
        assert_eq!(summarize(&qsos, None, None), BandChangeSummary::default());
    }
}
