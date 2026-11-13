# Statistics Drilldown Design

## Overview

Make dashboard statistics tappable to show detailed breakdowns. Tapping a stat box navigates to a detail view showing a list of items (entities, grids, bands, etc.) with QSO counts, expandable to reveal recent QSOs.

## Navigation Flow

| Stat Box | Tap Action |
|----------|------------|
| Total QSOs | Switch to Logs tab (programmatic tab selection) |
| Entities | Push `StatDetailView` showing entity list |
| Grids | Push `StatDetailView` showing grid list |
| Bands | Push `StatDetailView` showing band list |
| Modes | Push `StatDetailView` showing mode list |
| Parks | Push `StatDetailView` showing park list |

Tab switching for "Total QSOs" requires lifting selected tab state to `ContentView`.

## StatDetailView Layout

```
┌─────────────────────────────────┐
│ ← Entities            ↕️ Sort   │  Navigation bar with sort toggle
├─────────────────────────────────┤
│ K                        234    │  Row: identifier + count
│    United States                │  Description line
│ ├─ N0ABC    20m FT8    Jan 15  │  Expanded: recent QSOs
│ ├─ K1XYZ    40m SSB    Jan 14  │
│ ├─ W3DEF    15m CW     Jan 12  │
│ ├─ N5GHI    20m FT8    Jan 10  │
│ ├─ K9JKL    10m SSB    Jan 8   │
│ └─ Show more...                 │  Load next 5
├─────────────────────────────────┤
│ G                         12    │  Collapsed row
│    England                      │
├─────────────────────────────────┤
│ DL                         8    │
│    Germany                      │
└─────────────────────────────────┘
```

### Sort Options
- **By Count** (default) - highest count first
- **A-Z** - alphabetical by identifier

### Progressive Loading
- Show 5 QSOs initially when expanded
- "Show more" button loads next 5

## Data Layer

### StatCategory Enum

```swift
enum StatCategoryType: String, CaseIterable {
    case totalQsos
    case entities
    case grids
    case bands
    case modes
    case parks

    var title: String { ... }
    var icon: String { ... }
}
```

### StatCategoryItem

```swift
struct StatCategoryItem: Identifiable {
    let id: String              // Same as identifier
    let identifier: String      // "K", "20m", "FT8", etc.
    let description: String     // "United States", "14 MHz", etc.
    let count: Int
    let qsos: [QSO]            // All QSOs for this category
}
```

### Description Sources

| Category | Description Source |
|----------|-------------------|
| Entities | Bundled lookup table: prefix → country name |
| Grids | General location from grid square, or omit |
| Bands | Static mapping: "20m" → "14 MHz" |
| Modes | Static mapping: "SSB" → "Single Sideband Voice" |
| Parks | Park name from existing POTA data |

## Files to Create

### New Files
- `Views/Dashboard/StatDetailView.swift` - Detail view for category drilldown
- `Views/Dashboard/StatItemRow.swift` - Expandable row component
- `Models/StatCategoryType.swift` - Enum defining stat categories
- `Services/EntityLookup.swift` - Callsign prefix → country lookup
- `Resources/entities.json` - Bundled entity prefix data

### Modified Files
- `Views/Dashboard/DashboardView.swift` - Make StatBox tappable via NavigationLink
- `Views/ContentView.swift` - Lift tab selection state to enable cross-tab navigation

## Implementation Notes

### Entity Prefix Lookup
Bundle a simplified prefix-to-country mapping. Standard ham radio sources:
- CTY.DAT format (widely used)
- Club Log prefix database

For MVP, a static dictionary covering common prefixes is sufficient.

### Tab State Sharing
Options:
1. `@State` in ContentView with binding passed to DashboardView
2. `@Observable` TabState object in environment

Option 1 is simpler for this use case.

### Expanded State Management
Each `StatItemRow` tracks its own expanded state and loaded QSO count:
```swift
@State private var isExpanded = false
@State private var visibleQSOCount = 5
```
