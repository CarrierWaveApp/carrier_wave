# Unified Activator View Design

**Date:** 2026-03-25
**Status:** Draft
**Scope:** CW Sweep macOS app — Activator role layout redesign

## Problem

The activator workflow is split across three disconnected surfaces:

1. **POTA Setup Wizard** (`POTASetupView`) — full-screen form shown when no session is active. The band map dominates vertical space; equipment fields are hidden behind a disclosure group. The layout feels awkward and wastes space.
2. **Sessions List** (`SessionsListView`) — a separate sidebar item showing past sessions in an HSplitView. Disconnected from the activator workflow.
3. **Active Session Layout** (`ActivatorLayout.operatingLayout`) — appears only when a session is active. Header bar + VSplitView (logger on top, spots + map on bottom).

Users must context-switch between sidebar items to see past sessions vs. start a new activation. The setup wizard is overly ceremonial for what is usually a single-field action (pick a park).

## Design Goals

1. **Merge session history and session start** into one view — no separate Sessions sidebar item needed.
2. **Make starting an activation fast** — park reference is the only mandatory input; everything else auto-fills or is deferrable.
3. **Maximize operating screen real estate** — when a session is active, 100% of the content area serves operation.
4. **Add propagation intelligence** — surface band conditions, solar data, and frequency recommendations to help activators choose where to operate.
5. **Support roves as a single session** — park changes happen mid-session via an inline dropdown, not by ending/starting sessions.

## Key Insight: Session Model

A rove is a single activation that visits multiple parks over time. Users do not switch sessions during operation — they change the park reference within the active session. This means:

- Session start happens **once** per operating period (can afford slightly more ceremony)
- Session history is a **between-sessions concern**, not needed during operation
- The high-frequency rove interaction is **changing the park reference**, not starting a new session
- A persistent session sidebar is unnecessary and wastes operating space

## Design

### View States

The unified activator view has two states, driven by whether a session is active:

| State | Content |
|-------|---------|
| **No active session** | Setup row (top) + three-column layout: past activations, propagation/setup, band map |
| **Active session** | Full-screen operating layout (existing `operatingLayout` with park dropdown enhancement) |

### State 1: No Active Session (Cold Start)

Three horizontal zones:

#### Top: Setup Essentials Row

A single horizontal bar across the full width containing:

- **Park search field** — `ParkSearchField` with autocomplete (primary input, gets focus)
- **Frequency picker** — auto-filled from band selection/suggestion, manually overridable
- **Mode toggles** — CW / SSB / FT8 / FT4 buttons
- **Callsign display** — pre-filled from Keychain, with "+suffix" popover for prefix/suffix editing
- **Equipment button** — gear icon, scrolls center panel to the setup section
- **Start button** — enabled when park reference is non-empty and callsign is valid

All fields except park reference auto-fill from last session values (`@AppStorage` persistence).

#### Bottom Left: Past Activations (280px)

A scrollable list of past sessions, replacing the standalone `SessionsListView`. Each row shows:

- Park reference (bold) or "Rove (N parks)" for multi-park sessions
- Qualified indicator: green checkmark (≥10 QSOs) or red X with count
- Date, mode, duration (secondary line)

Clicking a past session opens its detail in the center panel (replacing propagation content temporarily). Right-click context menu includes "Activate This Park" to pre-fill the park reference.

#### Bottom Center: Propagation + Session Setup (scrollable)

A single scrollable column with propagation data at the top and session setup fields below:

**Propagation section (visible without scrolling on most screens):**

1. **Solar indices bar** — SFI, K-index, A-index, sunspot number, estimated MUF. Data from `HamQSLClient` (15-min cache).

2. **Band conditions grid** — 10 tiles (160m through 6m) in a 5×2 grid. Each tile shows:
   - Band name
   - Day / Night condition (Good/Fair/Poor/Closed)
   - Data from `HamQSLClient.bandConditions`
   - **Clickable** — selecting a band tile updates the band map on the right (see Band Selection Interaction below)
   - Best band (from `PropagationEstimator.bestBand()`) gets a star indicator and highlight border

3. **Space weather alerts** — three status cards for geomagnetic activity, solar flares, and CMEs. Data from `DONKIClient`. Color-coded severity (green/yellow/red). Shows "None active" when quiet.

**Session setup section (scroll to reach):**

4. **Equipment grid** — 2×2 grid of dropdown pickers: Radio, Antenna, Key, Mic. Pre-filled from last session.
5. **Power / Grid / Attendees** — three fields in a row. Grid auto-fills from park data.
6. **Additional Operators** — chip input field. Empty by default (solo operation).
7. **Rove toggle** — "This is a rove" switch with description.
8. **Session Notes** — multi-line text field.

All setup fields persist via `@AppStorage` and auto-fill from the previous session's values.

#### Bottom Right: Vertical Band Map (220px)

A vertical band map showing spot activity for the selected band:

- **Header** — selected band name, frequency range, "Last 30 min" label
- **Frequency recommendation** — prominent card at the top showing the suggested frequency with reasoning (see Frequency Suggestion Algorithm)
- **Vertical band map** — frequency on Y-axis (top = low, bottom = high), spot markers as horizontal lines. Band plan regions shown as horizontal bands with sub-band shading.
- **Activity density strip** — thin bar on the left edge showing where spots are concentrated
- **Footer** — spot count and data sources (RBN + POTA + Cluster)

When no band is selected, the band map shows a default state based on `PropagationEstimator.bestBand()`.

### Band Selection Interaction

1. User clicks a band tile in the conditions grid
2. The tile highlights with a blue border and glow
3. The band map on the right updates to show that band's frequency range
4. Spots from `SpotAggregator` (RBN, POTA, cluster, DX web) for the last 30 minutes are rendered
5. The frequency suggestion algorithm runs and displays a recommended frequency
6. The frequency picker in the setup row auto-fills with the suggestion
7. Clicking a different band tile switches everything

### Frequency Suggestion Algorithm

Given the selected band, mode, and recent spot activity:

1. **Determine eligible sub-band:**
   - CW mode → CW sub-band boundaries from `BandPlan.swift`
   - SSB mode → Phone sub-band boundaries
   - FT8/FT4 → return the standard dial frequency for that band (e.g., 14.074 for 20m FT8)
   - **Always use General+ boundaries**, never Extra-only segments, regardless of the user's license class. Activators want maximum hunter reach — General-class hunters cannot tune to Extra-only segments.

2. **Gather recent activity:** Collect all spots within the eligible sub-band from the last 30 minutes via `SpotAggregator`.

3. **Find the largest clear gap:** Within the eligible sub-band, find the widest contiguous range with no spots within ±500 Hz. Pick the center of that gap.

4. **Fallback:** If no clear gap exists (entire sub-band is busy), suggest the standard POTA frequency for that band/mode from `BandPlan+Frequencies.swift` with a note: "Busy — standard POTA freq."

5. **Display:** Show the suggested frequency prominently with a one-line explanation (e.g., "Clear CW window. No RBN activity within ±500 Hz in the last 30 min.").

### State 2: Active Session (Operating Layout)

When a session starts, the cold-start view is completely replaced by the full-screen operating layout. This is the existing `ActivatorLayout.operatingLayout` with one enhancement:

#### Park Dropdown in Activation Header

The `ActivationHeader` gains a clickable park chip that opens a dropdown popover:

- **Current park summary** — park reference, name, QSO count at this park, qualified status. Shown at the top of the dropdown with a green highlight.
- **Park search field** — same `ParkSearchField` component for finding the next park.
- **Parks visited this session** — list of previously-visited parks with per-park QSO counts and qualified indicators. Clicking one switches back to that park.

Changing the park:
- Updates which park reference gets attached to new QSOs
- Does NOT interrupt the session timer, log, or frequency state
- The QSO log table may show a subtle divider or park column to distinguish segments
- The existing `QSOLogTableView` already has a park reference column concept from the session ID

#### Session History Popover

A toolbar icon (clipboard/clock) in the `ActivationHeader` opens a popover showing past activations. Same data as the cold-start left column but in a compact popover. This replaces the need for a separate Sessions sidebar item.

### Transition Flow

1. **App opens, no session:** Cold start view appears. Setup row focused on park search.
2. **User selects a band tile:** Band map updates, frequency suggestion appears, frequency auto-fills.
3. **User types park reference and clicks Start:** Session created. View transitions in-place to the operating layout. Cold start disappears completely.
4. **During operation (rove):** User clicks the park chip in the header → dropdown opens → search for next park → select → continue logging.
5. **User ends session:** Operating layout clears. Cold start view reappears. The just-ended session appears at the top of the past activations list. Setup fields retain their values for the next activation.

### Sidebar Changes

- Remove `SidebarItem.sessions` as a standalone sidebar item
- The activator role layout now includes session history natively
- If session history is needed outside the activator role (e.g., in hunter mode), the Sessions sidebar item can remain but becomes a read-only `SessionsListView` without the new-session form

## Components Affected

### New Views

| View | Purpose |
|------|---------|
| `PropagationPanelView` | Solar indices, band conditions grid, space weather alerts |
| `BandConditionTile` | Individual clickable band tile with day/night conditions |
| `SpaceWeatherView` | DONKI geomagnetic/flare/CME status cards |
| `FrequencySuggestionView` | Recommended frequency card with explanation |
| `VerticalBandMapView` | Vertical-axis band map with spot markers and activity density |
| `ParkChangeDropdown` | Popover for mid-session park changes with search + visited parks |
| `SessionHistoryPopover` | Toolbar popover showing past activations |

### Modified Views

| View | Change |
|------|--------|
| `ActivatorLayout` | Replace wizard/operating toggle with cold-start/operating toggle; add new cold-start layout |
| `ActivationHeader` | Add clickable park chip with `ParkChangeDropdown`; add history popover icon |
| `QSOLogTableView` | Add park reference column for multi-park sessions; optional park-change divider |
| `ContentAreaView` | Remove `.sessions` routing (or make it read-only fallback) |
| `SidebarView` | Remove `.sessions` item (or keep as read-only for non-activator roles) |
| `LayoutConfiguration` | Remove or deprecate `SidebarItem.sessions` |

### Removed Views

| View | Replacement |
|------|-------------|
| `POTASetupView` (top bar, essentials row) | Setup essentials row in cold-start layout |
| `POTASetupView+Essentials` | Inlined into cold-start setup row |
| `POTASetupView+FullSetup` | Inlined into cold-start center scrollable panel |
| `POTASetupView+Actions` | Session start logic moves to `ActivatorLayout` |
| `SessionsListView` | Replaced by past activations list + history popover |
| `NewSessionSheet` | Replaced by inline setup row |

### Data Sources (existing, need wiring)

| Source | Current Status | Integration |
|--------|---------------|-------------|
| `HamQSLClient` | Implemented in CarrierWaveCore, not used in CWSweep | Wire into `PropagationPanelView` |
| `DONKIClient` | Implemented in CarrierWaveCore, not used in CWSweep | Wire into `SpaceWeatherView` |
| `PropagationEstimator` | Implemented in CarrierWaveCore, not used in CWSweep | Wire into band recommendation + `FrequencySuggestionView` |
| `SpotAggregator` | Already used in CWSweep | Feed spot data to `VerticalBandMapView` + frequency suggestion algorithm |
| `BandPlan` | Already in CarrierWaveCore | Sub-band boundaries for frequency suggestion |

## Data Model Changes

### Mid-Session Park Changes

The current model attaches a single `parkReference` to a `LoggingSession`. For rove support:

- Each `QSO` already has a `parkReference` field — this is the per-QSO park assignment (already exists)
- `LoggingSession` keeps its `parkReference` as the "current" park (updated on park change)
- Add a `parkHistory: [(parkReference: String, startedAt: Date)]` to `LoggingSession` (or a lightweight `ParkVisit` array) to track the sequence of parks visited and when each became active
- The session's display in history uses `parkHistory` to show "Rove (N parks)" with the list

### @AppStorage Keys for Auto-Fill

New `@AppStorage` keys to persist between sessions:

- `lastSuffix` — callsign suffix from previous session
- `lastPower` — power output
- `lastGrid` — grid square (overridden by park auto-fill)
- `lastAntenna`, `lastKey`, `lastMic` — equipment selections

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| No persistent sidebar | Session history is a between-sessions concern; operating layout needs 100% of screen |
| Scrollable center vs. tabs | Simpler, more discoverable; setup fields are rarely touched (auto-fill from last session) |
| Band map on the right (220px) | Narrow enough to not dominate, tall enough for useful vertical frequency display |
| General+ frequencies only | Activators want maximum hunter reach; Extra-only segments exclude General-class hunters |
| 30-minute spot window | Recent enough to reflect current activity, wide enough to have meaningful data |
| Park dropdown in header (not modal) | Park changes should feel like changing a filter, not ending/starting something |
| Activity density strip on band map | Quick visual scan of where the band is busy without reading individual spots |

## Resolved Questions

1. **Clicking a past activation:** Replace the center panel inline with session detail (simpler, stays within the cold-start layout). A "Back to Conditions" button or Escape returns to propagation view.
2. **Frequency suggestion updates:** Real-time. `SpotAggregator` is already `@Observable` and publishes changes — the suggestion recalculates when new spots arrive for the selected band.
3. **Return to previous park during rove:** Yes. The park dropdown's "This Session" list already shows previously-visited parks — clicking one switches back. This covers the "forgot to log a QSO at the last park" case.

## Implementation Notes

### parkHistory Persistence

`LoggingSession` is a SwiftData `@Model` synced via CloudKit. The `parkHistory` should be stored as a JSON-encoded `Data` blob (not a relationship) to avoid CloudKit schema migration complexity. Use a `Codable` struct:

```swift
struct ParkVisit: Codable {
    let parkReference: String
    let startedAt: Date
}
```

Stored as `parkHistoryData: Data?` on `LoggingSession` with a computed property for access.

### @AppStorage Key Reconciliation

The existing `@AppStorage("myCallsign")` in `POTASetupView` remains for the base callsign. New keys use the `lastActivation` prefix to avoid collisions:

- `lastActivationSuffix`, `lastActivationPower`, `lastActivationGrid`
- `lastActivationAntenna`, `lastActivationKey`, `lastActivationMic`

### Minimum Window Size

The cold-start layout requires a minimum content area width of ~780px (280 + 280 + 220). The existing `ActivatorLayout` sets `frame(minWidth:)` on split panes — carry this forward. If the window is narrower than the minimum, the past activations column collapses first (it's the least critical during setup).
