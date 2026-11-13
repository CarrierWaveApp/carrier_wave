//! Streak calculation over a set of active calendar days. Port of
//! `StreakCalculator.swift`.
//!
//! Swift's port takes a `Set<Date>` plus a `Calendar` (and an optional `useUTC`
//! flag) and reduces dates to day boundaries. In Rust we work with
//! `chrono::NaiveDate` directly — the caller is responsible for resolving the
//! timezone to a calendar day, which is a platform concern.

use std::collections::BTreeSet;

use chrono::NaiveDate;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StreakResult {
    pub current: u32,
    pub longest: u32,
    pub current_start: Option<NaiveDate>,
    pub longest_start: Option<NaiveDate>,
    pub longest_end: Option<NaiveDate>,
    pub last_active: Option<NaiveDate>,
}

impl StreakResult {
    pub const EMPTY: Self = Self {
        current: 0,
        longest: 0,
        current_start: None,
        longest_start: None,
        longest_end: None,
        last_active: None,
    };
}

#[derive(Debug, Clone, Copy)]
struct Segment {
    start: NaiveDate,
    end: NaiveDate,
    length: u32,
}

/// Calculate the streak result given a set of active dates and "today".
pub fn calculate_streak<I>(active_dates: I, today: NaiveDate) -> StreakResult
where
    I: IntoIterator<Item = NaiveDate>,
{
    let mut sorted: BTreeSet<NaiveDate> = active_dates.into_iter().collect();
    if sorted.is_empty() {
        return StreakResult::EMPTY;
    }

    let segments = find_all_streaks(&sorted);
    let longest = segments.iter().max_by_key(|s| s.length).copied();
    let yesterday = today.pred_opt();

    let current = segments
        .iter()
        .find(|s| s.end == today || Some(s.end) == yesterday)
        .copied();

    let last_active = sorted.iter().next_back().copied();
    sorted.clear();

    StreakResult {
        current: current.map(|s| s.length).unwrap_or(0),
        longest: longest.map(|s| s.length).unwrap_or(0),
        current_start: current.map(|s| s.start),
        longest_start: longest.map(|s| s.start),
        longest_end: longest.map(|s| s.end),
        last_active,
    }
}

fn find_all_streaks(sorted: &BTreeSet<NaiveDate>) -> Vec<Segment> {
    let mut iter = sorted.iter();
    let Some(&first) = iter.next() else {
        return Vec::new();
    };
    let mut current_start = first;
    let mut previous = first;
    let mut length: u32 = 1;
    let mut segments = Vec::new();

    for &date in iter {
        let day_diff = (date - previous).num_days();
        if day_diff == 1 {
            length += 1;
        } else if day_diff > 1 {
            segments.push(Segment {
                start: current_start,
                end: previous,
                length,
            });
            current_start = date;
            length = 1;
        }
        previous = date;
    }
    segments.push(Segment {
        start: current_start,
        end: previous,
        length,
    });
    segments
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(s: &str) -> NaiveDate {
        NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
    }

    #[test]
    fn empty_set_returns_empty() {
        let result = calculate_streak(Vec::new(), d("2026-06-13"));
        assert_eq!(result, StreakResult::EMPTY);
    }

    #[test]
    fn single_day_today_is_current_one() {
        let result = calculate_streak(vec![d("2026-06-13")], d("2026-06-13"));
        assert_eq!(result.current, 1);
        assert_eq!(result.longest, 1);
        assert_eq!(result.current_start, Some(d("2026-06-13")));
    }

    #[test]
    fn consecutive_days_count_together() {
        let dates = vec![
            d("2026-06-10"),
            d("2026-06-11"),
            d("2026-06-12"),
            d("2026-06-13"),
        ];
        let result = calculate_streak(dates, d("2026-06-13"));
        assert_eq!(result.current, 4);
        assert_eq!(result.longest, 4);
        assert_eq!(result.current_start, Some(d("2026-06-10")));
        assert_eq!(result.longest_end, Some(d("2026-06-13")));
    }

    #[test]
    fn current_streak_ending_yesterday_still_counts() {
        let dates = vec![d("2026-06-11"), d("2026-06-12")];
        let result = calculate_streak(dates, d("2026-06-13"));
        assert_eq!(result.current, 2);
    }

    #[test]
    fn current_streak_ending_two_days_ago_does_not_count() {
        let dates = vec![d("2026-06-10"), d("2026-06-11")];
        let result = calculate_streak(dates, d("2026-06-13"));
        assert_eq!(result.current, 0);
        assert_eq!(result.longest, 2);
    }

    #[test]
    fn multiple_segments_pick_longest() {
        let dates = vec![
            d("2026-01-01"),
            d("2026-01-02"),
            d("2026-01-03"),
            d("2026-01-04"), // 4-day streak
            d("2026-03-10"),
            d("2026-03-11"), // 2-day streak
            d("2026-06-12"),
            d("2026-06-13"), // 2-day current
        ];
        let result = calculate_streak(dates, d("2026-06-13"));
        assert_eq!(result.current, 2);
        assert_eq!(result.longest, 4);
        assert_eq!(result.longest_start, Some(d("2026-01-01")));
        assert_eq!(result.longest_end, Some(d("2026-01-04")));
        assert_eq!(result.last_active, Some(d("2026-06-13")));
    }

    #[test]
    fn duplicates_dedup_via_btreeset() {
        let dates = vec![d("2026-06-12"), d("2026-06-12"), d("2026-06-13")];
        let result = calculate_streak(dates, d("2026-06-13"));
        assert_eq!(result.current, 2);
    }
}
