# Activation Map Pane — Design Spec

## Summary

Add a live map pane to the CW Sweep POTA activator layout showing QSO locations, geodesic arcs during callsign entry, and a toggleable RBN propagation overlay showing which skimmers are hearing the user.

## Layout

The `ActivatorLayout.operatingLayout` changes from a single `VSplitView` to a full-width header above an `HSplitView`:

```
VStack {
  ActivationHeader              ← full width (unchanged)
  Divider
  HSplitView {
    VSplitView {                ← ~2/3 width
      VStack {
        ParsedEntryView
        QSOLogTableView
      }
      SpotListView
    }
    ActivationMapPane           ← ~1/3 width (new)
  }
}
```

The HSplitView is user-resizable. The map pane has `minWidth: 250` to prevent collapsing too small.

## Map States

The map has three states, represented as a computed `ActivationMapState` enum derived from `SelectionState` properties:

```swift
enum ActivationMapState {
    case idle                           // no entry in progress
    case lookupPending                  // entry in progress, no grid yet
    case geodesicFocus(grid: String)    // grid resolved
}
```

The state is derived as:
- `entryInProgress == false` → `.idle`
- `entryInProgress == true && entryCallsignGrid == nil` → `.lookupPending`
- `entryInProgress == true && entryCallsignGrid != nil` → `.geodesicFocus(grid:)`

When `sessionId` is nil (no active session), the map renders empty (no QSO dots, no arc) regardless of state.

### 1. Idle (no entry in progress)

- Shows all QSOs from the current activation session as band-colored dot annotations
- Shows user QTH marker (house icon, like existing QSOMapView)
- Camera fits all QSO locations + user QTH
- **Zero QSOs (start of activation):** center on user QTH at a continental zoom level (~3000km visible radius). If `myGrid` is also empty, show a default world view
- This is the default view when not typing a callsign

### 2. Lookup Pending (callsign being typed, no grid yet)

- Identical to idle view
- A subtle "Looking up..." text appears in the toolbar between the map title and RBN controls (e.g., `🗺 Activation Map · Looking up... [RBN toggle]`)
- Map does not move or change — stays stable until grid data arrives

### 3. Geodesic Focus (grid resolved for entry callsign)

- **Requires valid `myGrid`:** if `@AppStorage("myGrid")` is empty or `MaidenheadConverter.coordinate(from:)` returns nil, stay in idle view (no arc rendered, no camera change)
- Camera animates to frame the great circle arc between user QTH and the other station's resolved grid
- The arc is drawn as `MapPolyline`. Path computation: `AzimuthalProjection.greatCirclePath(fromLat:fromLon:toLat:toLon:segments: 50)` returns `[(lat: Double, lon: Double)]` tuples, converted to `[CLLocationCoordinate2D]` via `CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon)`
- **Antimeridian handling:** store arc as `[[CLLocationCoordinate2D]]` (1 or 2 segments). Detect antimeridian crossing by checking if adjacent points have longitude delta >180°; if so, split at that index into two sub-arrays. Render with `ForEach(arcSegments.indices, id: \.self) { i in MapPolyline(coordinates: arcSegments[i]) }`
- Camera region: compute bounding rect of the arc points, add 20% padding
- QSO dots remain visible but camera is zoomed to the arc path
- When entry is cleared (logged or escaped), animates back to idle overview

## Data Flow

### Entry callsign grid

`ParsedEntryView` already performs a debounced (300ms) `CallsignInfoCache.lookup` that returns a `CallsignInfo` with a `.grid` property (from QRZ or HamDB).

Two new properties are added to `SelectionState`:

```swift
var entryCallsignGrid: String?   // grid from CallsignInfoCache lookup
var entryInProgress: Bool = false // true when entry text is non-empty
```

Required changes to `ParsedEntryView`:
- `parseEntry()`: add `selectionState.entryInProgress = !text.isEmpty` and clear `selectionState.entryCallsignGrid = nil` when text changes (new callsign = new lookup needed)
- `clearEntry()`: add `selectionState.entryInProgress = false` and `selectionState.entryCallsignGrid = nil`

Required changes to `ParsedEntryView+CallsignLookup`:
- `lookupCallsignInfo()`: after the `CallsignInfoCache.lookup` resolves successfully, guard that the callsign still matches the current entry text (check `Task.isCancelled` — the existing cancellation via `callsignLookupTask?.cancel()` in `lookupCallsignInfo` already handles this, since each new keystroke cancels the prior task). Only then set `selectionState.entryCallsignGrid = info.grid` (where `info` is the CWSweep `CallsignInfo` whose `.grid` comes from `qrzResult?.grid ?? license?.grid`)
- `clearCallsignLookup()`: add `selectionState.entryCallsignGrid = nil`

**Stale lookup guard:** The existing pattern in `lookupCallsignInfo()` already cancels the previous task and checks `Task.isCancelled` after the debounce sleep and after the async lookup. This prevents stale results from overwriting `entryCallsignGrid` after the user has typed a new callsign.

`ActivationMapPane` reads these via `@Environment(SelectionState.self)` to compute `ActivationMapState`.

### Session QSOs

`ActivationMapPane` takes the session ID as a parameter: `let sessionId: UUID?` (passed from `ActivatorLayout` which holds `activeSession`). When `sessionId` is nil, no QSOs are fetched and the map is empty.

It fetches QSOs using `BoundedDescriptor<QSO>` filtered by `loggingSessionId == sessionId`, in a `.task` modifier. To react to log mutations, use a `@State private var refreshToken = 0` counter, incremented by `.onChange(of:)` handlers on the three signals below, and pass it as `.task(id: refreshToken)`:
- `selectionState.logInsertedQSORow` — new QSO logged
- `selectionState.logRemovedQSOId` — QSO deleted
- `selectionState.logUpdatedQSORow` — QSO edited or enriched (may gain `theirGrid` via background QRZ enrichment). This may fire for non-geometry changes too; acceptable since activation QSO counts are small and re-fetch is cheap

Only QSOs with a valid `theirGrid` (checked via `MaidenheadConverter.isValid`) are plotted. The user's QTH comes from `@AppStorage("myGrid")` (same pattern as existing `QSOMapView`).

### RBN spots

`ActivationMapPane` receives `SpotAggregator` via `@Environment` (already injected at the WorkspaceView level via `.environment(spotAggregator)`).

It filters `spotAggregator.spots` (which are `[EnrichedSpot]`) for:
- `enrichedSpot.spot.source == .rbn`
- `enrichedSpot.spot.isSelfSpot(userCallsign: myCallsign)` — uses `UnifiedSpot.isSelfSpot(userCallsign:)` which normalizes portable prefixes (e.g., `W1AW/4` → `W1AW`)
- `enrichedSpot.spot.spotterGrid != nil` — skip spots without spotter location
- `MaidenheadConverter.coordinate(from: enrichedSpot.spot.spotterGrid!)` returns non-nil — skip invalid grids

The user's callsign comes from `@AppStorage("myCallsign")` (same source used by `SpotAggregator.userCallsign`, set from the same AppStorage value in WorkspaceView).

Each matching spot represents a skimmer that heard the user. The skimmer's location comes from `enrichedSpot.spot.spotterGrid`. SNR is `enrichedSpot.spot.snr`.

No new polling or API calls are needed — SpotAggregator's existing 30-second poll cycle provides the data. Spots older than 30 minutes are already pruned by SpotAggregator.

## RBN Overlay

### Visual design

- Each skimmer is a small circle annotation at the spotter's grid coordinate (via `MaidenheadConverter.coordinate(from:)` returning `Coordinate`, then `CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)`)
- Circle size scales with SNR (larger = stronger signal): base 8pt, +1pt per 5dB above 5dB, capped at 16pt
- Consistent translucent cyan color (`Color.cyan.opacity(0.7)`) to distinguish from band-colored QSO dots
- Tiny SNR label on each marker (e.g., "15 dB")
- Visible in all three map states (idle, pending, geodesic focus)

### Toolbar

A compact bar at the top of the map pane:

```
🗺 Activation Map  [· Looking up...]  RBN [toggle] · 12 spots
```

- Left: map title (with optional "Looking up..." status during `.lookupPending` state)
- Right: RBN toggle button with spot count
- Toggle state persists via `@AppStorage("activationMapShowRBN")`
- When toggled off, skimmer markers are hidden; only QSO dots show

## File Structure

To stay within the 500-line file limit, split into two files:

### New Files

| File | Purpose |
|------|---------|
| `CWSweep/CWSweep/Views/Map/ActivationMapPane.swift` | Map view with toolbar, state management, QSO annotations, camera logic (~250 lines) |
| `CWSweep/CWSweep/Views/Map/ActivationMapPane+Overlays.swift` | Extension: RBN skimmer filtering/annotations, geodesic arc computation/rendering (~150 lines) |

### Modified Files

| File | Change |
|------|--------|
| `CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift` | Restructure `operatingLayout`: wrap in HSplitView, add `ActivationMapPane(sessionId: activeSession?.id)` as right pane |
| `CWSweep/CWSweep/Models/SelectionState.swift` | Add `entryCallsignGrid: String?` and `entryInProgress: Bool` |
| `CWSweep/CWSweep/Views/Logger/ParsedEntryView.swift` | In `parseEntry()`: set `selectionState.entryInProgress`, clear `entryCallsignGrid`. In `clearEntry()`: clear both properties |
| `CWSweep/CWSweep/Views/Logger/ParsedEntryView+CallsignLookup.swift` | In `lookupCallsignInfo()`: set `selectionState.entryCallsignGrid = info.grid`. In `clearCallsignLookup()`: clear `entryCallsignGrid` |
| `CWSweep/FILE_INDEX.md` | Add ActivationMapPane and ActivationMapPane+Overlays entries |

## Dependencies

No new dependencies. All required frameworks are already in use:
- `MapKit` — used by existing `QSOMapView`
- `CarrierWaveCore.MaidenheadConverter` — grid↔coordinate conversion (returns `Coordinate`, convert to `CLLocationCoordinate2D`)
- `CarrierWaveCore.AzimuthalProjection` — `greatCirclePath(fromLat:fromLon:toLat:toLon:segments:)` for geodesic arc interpolation (50 segments, returns `[(lat: Double, lon: Double)]`, convert to `[CLLocationCoordinate2D]`)

## Performance Considerations

- QSO fetch for the map is bounded by session — activations rarely exceed ~100 QSOs, well within safe limits
- RBN filtering is a simple array filter on SpotAggregator's existing in-memory spot list — O(n) where n is total spots (typically <500)
- MapKit handles annotation rendering efficiently for these counts
- No `@Query` used — follows the `@State` + `FetchDescriptor` in `.task(id:)` pattern
- Great circle path uses 50 segments — negligible computation cost
