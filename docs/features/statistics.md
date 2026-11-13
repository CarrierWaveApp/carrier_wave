# Statistics

The dashboard displays QSO statistics with drilldown capability for detailed exploration.

## Dashboard Stats

`QSOStatistics` struct provides grouped statistics:

| Stat Category | Groups by |
|---------------|-----------|
| Bands | Operating frequency band (20m, 40m, etc.) |
| Modes | Transmission mode (SSB, CW, FT8, etc.) |
| DXCC Entities | Country/entity from callsign prefix |
| Parks | POTA park references |

## Favorites

The dashboard includes a "Favorites" card showing the #1 item in three categories:

| Category | Description |
|----------|-------------|
| Top Frequency | Most used frequency, deduplicated to nearest 100Hz |
| Best Friend | Most frequent QSO partner (callsign you contact most) |
| Best Hunter | Most frequent hunter during POTA activations |

Each row shows the top item with its count and taps through to a full ranked list.

## View Components

### DashboardView

Main entry point showing:
- Activity grid (recent QSO activity)
- Tappable stat cards for each category
- Sync status indicators

### StatDetailView

Drilldown view when tapping a stat card:
- Expandable `StatItemRow` components
- Progressive QSO loading for performance
- Grouped by the selected category

### QSOStatistics

Core struct with `items(for:)` method:
- Takes a `StatCategory` enum
- Returns grouped/counted items
- Used by both dashboard summaries and detail views

## Equipment Usage

The dashboard includes an "Equipment" card computed from `LoggingSession` data (not QSOs). Shows usage patterns for radios, antennas, keys, and microphones.

### Card Rows

| Row | Description |
|-----|-------------|
| Top 3 Favorites | Most-used equipment across all categories by session count |
| QSO Magnet | Equipment with highest average QSOs per session (min 3 sessions) |
| Best Combo | Most common radio + antenna pairing |
| Gathering Dust | Equipment unused for 30+ days with oldest last-used date |

Each row taps through to a sortable detail view with category filtering.

### Architecture

- `EquipmentStatsActor` fetches `LoggingSession` in background, converts to snapshots
- `AsyncEquipmentStats` observable wrapper (same pattern as `AsyncQSOStatistics`)
- `EquipmentUsageCard` dashboard card, `EquipmentDetailView` drilldown
- Card hidden when no sessions have equipment data

## Implementation Notes

- Stats computed on-demand from SwiftData queries
- Large result sets use progressive loading
- `callsignPrefix` extracted for DXCC entity lookup

## Related Plans

- [Statistics Drilldown Design](../plans/2026-01-21-statistics-drilldown-design.md)
- [Statistics Drilldown Implementation](../plans/2026-01-21-statistics-drilldown.md)
