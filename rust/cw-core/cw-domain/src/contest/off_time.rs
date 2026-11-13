//! Off-time compliance summary. Port of
//! `Services/Contest/OffTimeTracker.swift`.
//!
//! Pure function — the Swift `sessionEnd ?? Date()` default is the caller's
//! responsibility here (pass the current time as `session_end`).

use chrono::{DateTime, Utc};

use super::model::ContestOffTimeRules;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct OffTimeSummary {
    pub total_on_air_seconds: f64,
    pub total_off_seconds: f64,
    pub off_periods: Vec<OffPeriod>,
    pub violations: Vec<OffTimeViolation>,
    /// How much on-air time remains under the selected category's cap, if any.
    pub remaining_on_air_seconds: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OffPeriod {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

impl OffPeriod {
    pub fn duration_seconds(&self) -> f64 {
        (self.end - self.start).num_milliseconds() as f64 / 1_000.0
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum OffTimeViolation {
    OffPeriodTooShort { start: DateTime<Utc>, duration_seconds: f64, minimum_seconds: f64 },
    ExceededMaxOnAirTime { actual_seconds: f64, allowed_seconds: f64 },
}

/// Evaluate session-long off-time compliance against a contest's
/// `operating_constraints.off_time` rules.
pub fn summarize(
    qso_timestamps: &[DateTime<Utc>],
    session_start: DateTime<Utc>,
    session_end: DateTime<Utc>,
    category_id: Option<&str>,
    rules: Option<&ContestOffTimeRules>,
) -> OffTimeSummary {
    let mut sorted = qso_timestamps.to_vec();
    sorted.sort();
    let min_off_seconds =
        (rules.and_then(|rules| rules.minimum_off_minutes).unwrap_or(30) * 60) as f64;

    let mut off_periods: Vec<OffPeriod> = Vec::new();
    let mut violations: Vec<OffTimeViolation> = Vec::new();

    // Collect gaps between consecutive QSOs (plus opening/closing brackets).
    let mut cursor = session_start;
    for stamp in sorted {
        let gap = seconds_between(cursor, stamp);
        if gap >= min_off_seconds {
            off_periods.push(OffPeriod { start: cursor, end: stamp });
        } else if gap > 0.0 {
            violations.push(OffTimeViolation::OffPeriodTooShort {
                start: cursor,
                duration_seconds: gap,
                minimum_seconds: min_off_seconds,
            });
        }
        cursor = stamp;
    }
    let tail_gap = seconds_between(cursor, session_end);
    if tail_gap >= min_off_seconds {
        off_periods.push(OffPeriod { start: cursor, end: session_end });
    }

    let total_off: f64 = off_periods.iter().map(OffPeriod::duration_seconds).sum();
    let total_on = (seconds_between(session_start, session_end) - total_off).max(0.0);

    let max_on_air = maximum_on_air_seconds(category_id, rules);
    if let Some(limit) = max_on_air {
        if total_on > limit {
            violations.push(OffTimeViolation::ExceededMaxOnAirTime {
                actual_seconds: total_on,
                allowed_seconds: limit,
            });
        }
    }

    OffTimeSummary {
        total_on_air_seconds: total_on,
        total_off_seconds: total_off,
        off_periods,
        violations,
        remaining_on_air_seconds: max_on_air.map(|limit| (limit - total_on).max(0.0)),
    }
}

fn maximum_on_air_seconds(
    category_id: Option<&str>,
    rules: Option<&ContestOffTimeRules>,
) -> Option<f64> {
    let rules = rules?;
    let category_id = category_id?;
    rules
        .maximum_on_hours_by_category
        .get(category_id)
        .map(|hours| hours * 3_600.0)
}

fn seconds_between(start: DateTime<Utc>, end: DateTime<Utc>) -> f64 {
    (end - start).num_milliseconds() as f64 / 1_000.0
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use chrono::{Duration, TimeZone};

    use super::*;

    fn base() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 4, 0, 0, 0).unwrap()
    }

    fn at(minutes: i64) -> DateTime<Utc> {
        base() + Duration::minutes(minutes)
    }

    #[test]
    fn gaps_split_into_off_periods_and_violations() {
        // Gap of 45 min (≥30 default) → off period; gap of 10 min → too short.
        let stamps = vec![at(45), at(55)];
        let summary = summarize(&stamps, base(), at(60), None, None);

        assert_eq!(summary.off_periods.len(), 1);
        assert_eq!(summary.off_periods[0].start, base());
        assert_eq!(summary.off_periods[0].end, at(45));
        assert_eq!(summary.violations.len(), 1);
        assert!(matches!(
            summary.violations[0],
            OffTimeViolation::OffPeriodTooShort { duration_seconds, .. } if duration_seconds == 600.0
        ));
        assert_eq!(summary.total_off_seconds, 2_700.0);
        assert_eq!(summary.total_on_air_seconds, 900.0);
    }

    #[test]
    fn tail_gap_counts_as_off_period() {
        let stamps = vec![at(5)];
        let summary = summarize(&stamps, base(), at(60), None, None);
        // 5-min opening gap violates; 55-min tail gap is an off period.
        assert_eq!(summary.off_periods.len(), 1);
        assert_eq!(summary.off_periods[0].end, at(60));
    }

    #[test]
    fn category_cap_produces_violation_and_remaining() {
        let rules = ContestOffTimeRules {
            minimum_off_minutes: Some(30),
            maximum_on_hours_by_category: HashMap::from([("SO".to_string(), 0.5)]),
        };
        // No gaps: 60 minutes fully on-air vs a 30-minute cap.
        let stamps = vec![at(20), at(40)];
        let summary = summarize(&stamps, base(), at(60), Some("SO"), Some(&rules));
        assert!(summary
            .violations
            .iter()
            .any(|violation| matches!(violation, OffTimeViolation::ExceededMaxOnAirTime { .. })));
        assert_eq!(summary.remaining_on_air_seconds, Some(0.0));

        // Unknown category → no cap.
        let uncapped = summarize(&stamps, base(), at(60), Some("MO"), Some(&rules));
        assert_eq!(uncapped.remaining_on_air_seconds, None);
    }

    #[test]
    fn custom_minimum_off_minutes() {
        let rules = ContestOffTimeRules {
            minimum_off_minutes: Some(10),
            maximum_on_hours_by_category: HashMap::new(),
        };
        let stamps = vec![at(15), at(20)];
        let summary = summarize(&stamps, base(), at(20), None, Some(&rules));
        // 15-min gap ≥ 10-min rule → off period; 5-min gap → violation.
        assert_eq!(summary.off_periods.len(), 1);
        assert_eq!(summary.violations.len(), 1);
    }
}
