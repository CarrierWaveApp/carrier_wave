# POTA P2P Enrichment During Activations

**Date:** 2026-03-23
**Status:** Approved

## Problem

During POTA activations, the app fetches active POTA spots but doesn't cross-reference them against stations being logged. When working another activator, the operator must manually type the other station's park reference. There's no visual indicator that a QSO is park-to-park.

## Solution

Build a callsign-indexed lookup table from the existing `cachedPOTASpots` in `LoggerView`. When a callsign is entered, cross-reference it to show P2P park chips in the callsign lookup card and auto-populate `theirParkReference`.

## Design

### Data Layer: Lookup Table in LoggerView

Add a computed or lazily-built lookup dictionary in `LoggerView+Data.swift`:

```swift
/// Callsign -> [POTASpot] lookup built from cachedPOTASpots
var potaSpotLookup: [String: [POTASpot]]
```

- Built from the existing `cachedPOTASpots: [POTASpot]` (already fetched via `refreshPOTASpots()`)
- Keyed by normalized callsign (uppercased, portable suffix stripped)
- Multiple spots per callsign preserved (two-fer/three-fer activations)
- **No new API calls** — indexes data already being fetched
- **No changes to SpotMonitoringService** — the data source is `LoggerView.cachedPOTASpots`

For callsign normalization: add a simple `internal static` helper on `POTASpot` (promote the existing `private static normalizeCallsign` to `internal`), or add a local helper in `LoggerView+Data.swift`.

### Lookup Flow

In `onCallsignChanged` (in `LoggerView+Data.swift`), after `resolveCallsignForLookup` and `populateFieldsFromQuickEntry` complete:

1. Check if this is a POTA session (`sessionManager?.activeSession?.parkReference != nil`)
2. Look up `potaSpotLookup[normalizedCallsign]`
3. Store result as `@State var potaSpotMatches: [POTASpot]?` on `LoggerView`
4. If matches found AND `theirPark` is empty (not manually filled, not set by quick entry), auto-populate `theirPark` with comma-separated park references

**Ordering matters:** `populateFieldsFromQuickEntry` clears `theirPark` to `""` on every callsign change (unless quick entry parsed a park). The P2P lookup must run *after* this, so it fills `theirPark` only when quick entry didn't provide one. This avoids the auto-fill being immediately overwritten.

### Card UI: LoggerCallsignCard

Add optional parameter: `potaSpots: [POTASpot]?`

When non-nil and non-empty, render a **new row between the detail chips and footer** with its own conditional (independent of `hasDetails`):

- Horizontal `ScrollView(.horizontal, showsIndicators: false)`
- Leading "P2P" label pill: green background, tree icon
- One chip per park: "K-1234 Park Name" with green tint, fixed size
- **No wrapping** — parks scroll horizontally to avoid content compression

`LoggerCallsignCard` already imports `CarrierWaveCore` (for `MaidenheadConverter`, `CallsignFlagHelper`), so accepting `[POTASpot]?` adds no new module dependency.

### Auto-populate theirPark

When P2P matches are found during callsign lookup:

- Set `theirPark` to comma-separated park references (e.g., "K-1234,K-5678")
- Only auto-fill if `theirPark` is currently empty after `populateFieldsFromQuickEntry`
- If user typed an explicit park in quick entry (e.g., "W1AW K-9999"), that takes priority

### Fix handleSpotSelection

When selecting a `.pota` spot from the sidebar:

- Set `theirPark = spot.reference` (currently only goes to `notes`)
- Set it *after* the callsign assignment to survive the `onChange` clear cycle, or set a flag to preserve it

When selecting a `.p2p` opportunity:

- Set `theirPark = opportunity.parkRef` (currently only goes to `notes`)

## Scope Boundaries

- Only active during POTA sessions (checked via `activeSession?.parkReference`)
- No new API calls — reuses existing `cachedPOTASpots` fetch
- No changes to QSO model, sync, or ADIF export (`theirParkReference` already exists)
- No changes to hunter mode (`SpotLogSheet` already handles park refs correctly)
- No changes to `SpotMonitoringService`

## Files to Modify

1. `CarrierWave/Views/Logger/LoggerCallsignCard.swift` — add `potaSpots` param, render P2P horizontal scroll row
2. `CarrierWave/Views/Logger/LoggerView.swift` — add `@State var potaSpotMatches: [POTASpot]?`
3. `CarrierWave/Views/Logger/LoggerView+Data.swift` — build lookup table from `cachedPOTASpots`, query in `onCallsignChanged` after `populateFieldsFromQuickEntry`
4. `CarrierWave/Views/Logger/LoggerView+Commands.swift` — set `theirPark` in `handleSpotSelection` for `.pota` and `.p2p` cases
5. `CarrierWave/Views/Logger/LoggerView+Layout.swift` — pass `potaSpotMatches` to `LoggerCallsignCard`
6. `CarrierWaveCore/Sources/CarrierWaveCore/POTASpot.swift` — promote `normalizeCallsign` to `internal` (or add local helper instead)
