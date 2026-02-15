# Design: Configurable Dashboard Metrics Card

**Date:** 2026-02-14
**Status:** Approved

## Problem

The current "Streaks" dashboard card shows two hardcoded metrics — "Daily QSOs" and "POTA Activations" — with unclear names. Users can't customize what appears on the card, and hunter-style metrics are missing entirely.

## Solution

Replace the hardcoded streaks card with a configurable metrics card. Users pick up to 2 metrics from a catalog of streak and count metrics via Settings. Names are rewritten for clarity.

## Metric Catalog

### Streak Metrics (consecutive UTC days)

Card display: large number = current streak, small text = "Best: N"

| ID | Name | Subtitle | Logic |
|---|---|---|---|
| `onAir` | On-Air Streak | Days in a row with any contact | Consecutive UTC days with >= 1 non-metadata QSO |
| `activation` | Activation Streak | Days in a row with a valid activation | Consecutive UTC days with a 10+ QSO POTA activation |
| `hunter` | Hunter Streak | Days in a row hunting a park | Consecutive UTC days with >= 1 hunter QSO (their park ref populated OR imported as hunter) |
| `cw` | CW Streak | Consecutive days on CW | Days with >= 1 CW-family QSO |
| `phone` | Phone Streak | Consecutive days on voice | Days with >= 1 SSB/FM/AM QSO |
| `digital` | Digital Streak | Consecutive days on digital | Days with >= 1 FT8/FT4/JS8/RTTY/etc. QSO |

### Count Metrics (totals over a time window)

Card display: large number = count, small text = time period

| ID | Name | Logic |
|---|---|---|
| `qsosWeek` | QSOs This Week | Non-metadata QSOs in last 7 rolling days |
| `qsosMonth` | QSOs This Month | Non-metadata QSOs since 1st of current month |
| `qsosYear` | QSOs This Year | Non-metadata QSOs since Jan 1 |
| `activationsMonth` | Activations This Month | Valid activations (10+ QSO) this calendar month |
| `activationsYear` | Activations This Year | Valid activations this calendar year |
| `huntsWeek` | Parks Hunted This Week | Distinct parks hunted in last 7 days |
| `huntsMonth` | Parks Hunted This Month | Distinct parks hunted this calendar month |
| `newDXCCYear` | New DXCC This Year | DXCC entities first worked this year (requires LoTW) |

## Settings UI

- Location: Settings > Dashboard > "Dashboard Metrics"
- User picks up to 2 metrics from the full catalog
- Catalog grouped into "Streaks" and "Counts" sections
- Default selection: On-Air Streak + Activation Streak (matches current behavior with better names)
- Stored in UserDefaults (UI preference, not SwiftData)

## Dashboard Card Behavior

- Card title: "Metrics" (or "Streaks" if both selections are streak-type)
- Shows 1 or 2 columns depending on selection count
- Streak metrics: large number = current streak, small text = "Best: N"
- Count metrics: large number = count, small text = time window label
- Card taps navigate to full streak detail view (shows all metrics, not just selected)
- Metrics with no data show "0" rather than hiding

## Computation

- Streak metrics: computed via `QSOStatistics+Streaks.swift` (extend existing infrastructure)
- Count metrics: new `QSOStatistics+Counts.swift` — filtered counts with date predicates
- Hunter QSO detection: check `sigInfo` field for park reference OR check if QSO came from POTA/LoFi import tagged as hunter
- Mode family grouping: reuse `ModeEquivalence` from CarrierWaveCore
- All computation happens on background actor (existing `StatsComputationActor` pattern)

## Data Model

### DashboardMetricType enum

```swift
enum DashboardMetricType: String, CaseIterable, Codable {
    // Streaks
    case onAir, activation, hunter, cw, phone, digital
    // Counts
    case qsosWeek, qsosMonth, qsosYear
    case activationsMonth, activationsYear
    case huntsWeek, huntsMonth
    case newDXCCYear
}
```

### Storage

Two UserDefaults keys:
- `dashboardMetric1`: `DashboardMetricType` (default: `.onAir`)
- `dashboardMetric2`: `DashboardMetricType?` (default: `.activation`, nullable to allow single-metric display)

## Files Affected

### New files
- `QSOStatistics+Counts.swift` — count metric computation
- `DashboardMetricType.swift` — metric type enum, display properties, UserDefaults keys
- `DashboardMetricsSettingsView.swift` — settings picker UI

### Modified files
- `DashboardHelperViews.swift` — replace `StreaksCard` with new `MetricsCard`
- `DashboardView.swift` — wire up new card
- `QSOStatistics+Streaks.swift` — add hunter/mode-family streak computation
- `StreakInfo.swift` — extend `StreakCategory` with new cases
- `AsyncQSOStatistics.swift` — expose new metrics
- `StreakDetailView.swift` — add hunter section
- `SettingsView.swift` — add Dashboard Metrics navigation link
