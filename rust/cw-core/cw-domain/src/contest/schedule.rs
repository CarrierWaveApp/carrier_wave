//! Concrete occurrence computation for contest schedules. Port of
//! `Services/Contest/ContestScheduleEvaluator.swift` +
//! `ContestAnnualResolver.swift`.
//!
//! All calendar math is Gregorian UTC, matching the Swift evaluator.

use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc, Weekday};

use super::model::{ContestAnnualSchedule, ContestFixedOccurrence, ContestSchedule,
    ContestWeeklySession};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ContestOccurrence {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

impl ContestOccurrence {
    pub fn duration_seconds(&self) -> i64 {
        (self.end - self.start).num_seconds()
    }

    pub fn contains(&self, date: DateTime<Utc>) -> bool {
        date >= self.start && date < self.end
    }
}

/// The currently-active occurrence (if any) at `now`.
pub fn active_occurrence(schedule: &ContestSchedule, now: DateTime<Utc>) -> Option<ContestOccurrence> {
    occurrences(schedule, now).into_iter().find(|occurrence| occurrence.contains(now))
}

/// The next upcoming occurrence after `now`, if any.
pub fn next_occurrence(schedule: &ContestSchedule, now: DateTime<Utc>) -> Option<ContestOccurrence> {
    occurrences(schedule, now).into_iter().find(|occurrence| occurrence.start > now)
}

/// Candidate occurrences around `now` (up to ~1 year before + after).
pub fn occurrences(schedule: &ContestSchedule, now: DateTime<Utc>) -> Vec<ContestOccurrence> {
    match schedule {
        ContestSchedule::FixedDates { occurrences } => {
            let mut result: Vec<ContestOccurrence> =
                occurrences.iter().filter_map(occurrence_from_fixed).collect();
            result.sort_by_key(|occurrence| occurrence.start);
            result
        }
        ContestSchedule::RecurringWeekly { sessions, .. } => weekly_occurrences(sessions, now),
        ContestSchedule::Annual(schedule) => annual_occurrences(schedule, now),
    }
}

fn occurrence_from_fixed(fixed: &ContestFixedOccurrence) -> Option<ContestOccurrence> {
    // Swift's ISO8601DateFormatter is configured with fractional seconds;
    // RFC 3339 parsing here accepts both with and without them.
    let start = DateTime::parse_from_rfc3339(&fixed.start).ok()?.with_timezone(&Utc);
    Some(ContestOccurrence { start, end: start + hours_duration(fixed.duration_hours) })
}

fn weekly_occurrences(sessions: &[ContestWeeklySession], now: DateTime<Utc>) -> Vec<ContestOccurrence> {
    let mut results: Vec<ContestOccurrence> = Vec::new();
    // Look back/forward ±14 days so the current + next session is always
    // present.
    for offset in -14..=14 {
        let day = (now + Duration::days(offset)).date_naive();
        for session in sessions {
            if let Some(occurrence) = build_weekly_occurrence(session, day) {
                results.push(occurrence);
            }
        }
    }
    results.sort_by_key(|occurrence| occurrence.start);
    results.dedup_by_key(|occurrence| occurrence.start);
    results
}

fn build_weekly_occurrence(session: &ContestWeeklySession, day: NaiveDate) -> Option<ContestOccurrence> {
    let target = weekday_value(&session.day)?;
    if day.weekday() != target {
        return None;
    }
    let (hour, minute) = parse_hhmm(&session.start_utc)?;
    let start = day.and_hms_opt(hour, minute, 0)?.and_utc();
    let end = start + Duration::seconds(session.duration_minutes * 60);
    Some(ContestOccurrence { start, end })
}

fn annual_occurrences(schedule: &ContestAnnualSchedule, now: DateTime<Utc>) -> Vec<ContestOccurrence> {
    let year = now.year();
    let mut candidates: Vec<ContestOccurrence> = [-1, 0, 1]
        .iter()
        .filter_map(|offset| {
            let start = resolve_annual_start(&schedule.rule, year + offset, &schedule.start_utc)?;
            Some(ContestOccurrence { start, end: start + hours_duration(schedule.duration_hours) })
        })
        .collect();
    candidates.sort_by_key(|occurrence| occurrence.start);
    candidates
}

fn resolve_annual_start(rule: &str, year: i32, start_utc: &str) -> Option<DateTime<Utc>> {
    let (hour, minute) = parse_hhmm(start_utc)?;
    let day = annual_rule_date(rule, year)?;
    Some(day.and_hms_opt(hour, minute, 0)?.and_utc())
}

fn parse_hhmm(value: &str) -> Option<(u32, u32)> {
    let parts: Vec<&str> = value.split(':').collect();
    if parts.len() != 2 {
        return None;
    }
    let hour = parts[0].parse().ok()?;
    let minute = parts[1].parse().ok()?;
    Some((hour, minute))
}

fn weekday_value(day: &str) -> Option<Weekday> {
    match day.to_lowercase().as_str() {
        "sunday" => Some(Weekday::Sun),
        "monday" => Some(Weekday::Mon),
        "tuesday" => Some(Weekday::Tue),
        "wednesday" => Some(Weekday::Wed),
        "thursday" => Some(Weekday::Thu),
        "friday" => Some(Weekday::Fri),
        "saturday" => Some(Weekday::Sat),
        _ => None,
    }
}

fn hours_duration(hours: f64) -> Duration {
    Duration::milliseconds((hours * 3_600_000.0) as i64)
}

// ---- Annual rule resolution (port of ContestAnnualResolver.swift) --------

/// Resolve a named annual recurrence rule to the concrete start day.
/// Covers the subset shipped in contest-definitions v0.3; unknown rules
/// return `None`.
pub fn annual_rule_date(rule: &str, year: i32) -> Option<NaiveDate> {
    match rule {
        "last_full_weekend_november" => last_full_weekend(11, year),
        "last_full_weekend_october" => last_full_weekend(10, year),
        "last_full_weekend_may" => last_full_weekend(5, year),
        "last_full_weekend_march" => last_full_weekend(3, year),
        "fourth_weekend_october" => nth_weekend(10, 4, year),
        "fourth_weekend_february" => nth_weekend(2, 4, year),
        "second_full_weekend_september" => nth_full_weekend(9, 2, year),
        "third_full_weekend_july" => nth_full_weekend(7, 3, year),
        "first_full_weekend_august" => nth_full_weekend(8, 1, year),
        "first_full_weekend_december" => nth_full_weekend(12, 1, year),
        "arrl_dx_first_weekend" => nth_full_weekend(2, 3, year),
        _ => None,
    }
}

/// Find the last Saturday of the month such that the following Sunday is
/// also within the month (i.e. weekend is "full").
fn last_full_weekend(month: u32, year: i32) -> Option<NaiveDate> {
    let mut cursor = last_day_of_month(month, year)?;
    for _ in 0..10 {
        if cursor.weekday() == Weekday::Sat {
            let sunday = cursor + Duration::days(1);
            if sunday.month() == month {
                return Some(cursor);
            }
        }
        cursor -= Duration::days(1);
    }
    None
}

/// Nth Saturday of the month.
fn nth_weekend(month: u32, nth: usize, year: i32) -> Option<NaiveDate> {
    let mut cursor = NaiveDate::from_ymd_opt(year, month, 1)?;
    let mut count = 0;
    for _ in 0..40 {
        if cursor.weekday() == Weekday::Sat {
            count += 1;
            if count == nth {
                return Some(cursor);
            }
        }
        cursor += Duration::days(1);
    }
    None
}

/// Nth "full" weekend (Saturday + Sunday both in the same month).
fn nth_full_weekend(month: u32, nth: usize, year: i32) -> Option<NaiveDate> {
    let mut cursor = NaiveDate::from_ymd_opt(year, month, 1)?;
    let mut count = 0;
    for _ in 0..40 {
        if cursor.weekday() == Weekday::Sat && (cursor + Duration::days(1)).month() == month {
            count += 1;
            if count == nth {
                return Some(cursor);
            }
        }
        cursor += Duration::days(1);
    }
    None
}

fn last_day_of_month(month: u32, year: i32) -> Option<NaiveDate> {
    let (next_year, next_month) = if month == 12 { (year + 1, 1) } else { (year, month + 1) };
    Some(NaiveDate::from_ymd_opt(next_year, next_month, 1)? - Duration::days(1))
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;
    use crate::contest::model::ContestSessionScoring;

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 4, 18, 0, 0).unwrap()
    }

    #[test]
    fn weekly_session_produces_next_occurrence() {
        // Mirror of `scheduleEvaluatorFindsWeeklySession`.
        let schedule = ContestSchedule::RecurringWeekly {
            sessions: vec![ContestWeeklySession {
                day: "monday".to_string(),
                start_utc: "00:00".to_string(),
                duration_minutes: 60,
            }],
            scoring: ContestSessionScoring::Independent,
        };
        let next = next_occurrence(&schedule, now()).expect("occurrence");
        // 2026-07-04 is a Saturday; the next Monday 00:00 UTC is 2026-07-06.
        assert_eq!(next.start, Utc.with_ymd_and_hms(2026, 7, 6, 0, 0, 0).unwrap());
        assert_eq!(next.duration_seconds(), 3_600);
    }

    #[test]
    fn annual_rules_resolve() {
        // Mirror of `scheduleEvaluatorResolvesWpxWeekends`.
        for rule in ["last_full_weekend_may", "last_full_weekend_march"] {
            let schedule = ContestSchedule::Annual(ContestAnnualSchedule {
                rule: rule.to_string(),
                start_utc: "00:00".to_string(),
                start_day: "saturday".to_string(),
                duration_hours: 48.0,
            });
            assert!(next_occurrence(&schedule, now()).is_some(), "rule {rule}");
        }
    }

    #[test]
    fn annual_rule_dates_are_full_weekends() {
        // CQ WW CW 2026: last full weekend of November → Nov 28 (Sat 29th is
        // followed by Sun the 29th... verify directly instead of asserting
        // folklore: the resolved day must be a Saturday whose Sunday is in
        // the same month, and the *last* such Saturday.
        let day = annual_rule_date("last_full_weekend_november", 2026).expect("date");
        assert_eq!(day.weekday(), Weekday::Sat);
        assert_eq!((day + Duration::days(1)).month(), 11);
        assert!((day + Duration::days(7) + Duration::days(1)).month() != 11
            || (day + Duration::days(7)).month() != 11);

        // ARRL DX (third full weekend of February).
        let arrl = annual_rule_date("arrl_dx_first_weekend", 2026).expect("date");
        assert_eq!(arrl.weekday(), Weekday::Sat);
        assert_eq!(arrl.month(), 2);

        assert_eq!(annual_rule_date("mystery_rule", 2026), None);
    }

    #[test]
    fn fixed_dates_parse_and_sort() {
        let schedule = ContestSchedule::FixedDates {
            occurrences: vec![
                ContestFixedOccurrence {
                    start: "2026-09-01T12:00:00.000Z".to_string(),
                    duration_hours: 24.0,
                },
                ContestFixedOccurrence {
                    start: "2026-08-01T12:00:00.000Z".to_string(),
                    duration_hours: 24.0,
                },
                ContestFixedOccurrence { start: "garbage".to_string(), duration_hours: 1.0 },
            ],
        };
        let all = occurrences(&schedule, now());
        assert_eq!(all.len(), 2);
        assert!(all[0].start < all[1].start);
        let next = next_occurrence(&schedule, now()).expect("occurrence");
        assert_eq!(next.start, Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap());
    }

    #[test]
    fn active_occurrence_contains_now() {
        let schedule = ContestSchedule::FixedDates {
            occurrences: vec![ContestFixedOccurrence {
                start: "2026-07-04T00:00:00.000Z".to_string(),
                duration_hours: 48.0,
            }],
        };
        let active = active_occurrence(&schedule, now()).expect("active");
        assert!(active.contains(now()));
        assert!(active_occurrence(&schedule, Utc.with_ymd_and_hms(2026, 7, 7, 0, 0, 0).unwrap())
            .is_none());
    }

    #[test]
    fn weekly_dedupes_and_covers_two_weeks() {
        let schedule = ContestSchedule::RecurringWeekly {
            sessions: vec![ContestWeeklySession {
                day: "friday".to_string(),
                start_utc: "20:00".to_string(),
                duration_minutes: 60,
            }],
            scoring: ContestSessionScoring::Independent,
        };
        let all = occurrences(&schedule, now());
        // ±14 days around a Saturday spans 4-5 Fridays, all unique.
        assert!(all.len() >= 4);
        let mut starts: Vec<_> = all.iter().map(|occurrence| occurrence.start).collect();
        starts.dedup();
        assert_eq!(starts.len(), all.len());
    }
}
