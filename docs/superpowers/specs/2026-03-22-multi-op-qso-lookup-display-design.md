# Multi-Operator QSO Lookup & Display

**Date:** 2026-03-22
**Status:** Draft

## Problem

When a user enters multiple callsigns in the quick entry field (e.g., `KD2UHR N3FJP 559`), the parser correctly detects multiple callsigns and `logMultiQuickEntry` creates one QSO per callsign. However:

1. **Only the first callsign gets a lookup** — `resolveCallsignForLookup` returns only the first callsign for QRZ/cache lookup, so only one `LoggerCallsignCard` is shown.
2. **No multi-card display** — the UI only supports showing a single `lookupResult` / `LoggerCallsignCard`.

Users working multi-op contacts (multiple operators at the other end) can't see lookup info for all contacted operators before logging.

## Solution

### 1. Multi-callsign lookup

When `quickEntryMultiResults` has 2+ results, trigger lookups for all callsigns (not just the first). Store results in a new `@State var multiLookupResults: [MultiCallsignLookupState]` array on `LoggerView`.

**Lookup state enum:**

```swift
enum MultiCallsignLookupState {
    case loading(callsign: String)
    case found(info: CallsignInfo, previousQSOCount: Int)
    case notFound(callsign: String)
    case error(callsign: String, error: CallsignLookupError)

    var callsign: String { /* extract from each case */ }
}
```

**Lookup flow:**
- `resolveCallsignForLookup` already populates `quickEntryMultiResults` when multiple callsigns are detected
- When `onCallsignChanged` detects `quickEntryMultiResults` is non-nil with 2+ results, it takes the **multi-lookup path instead of the single-lookup path** (not both — avoids race condition on the first callsign)
- Multi-lookup cancels any existing `lookupTask`, then starts a new `Task` that:
  - Immediately populates `multiLookupResults` with `.loading` entries for all callsigns
  - Applies the same 300ms debounce as the single path
  - Only proceeds if every callsign in `quickEntryMultiResults` has primary length >= 3 characters
  - Uses `TaskGroup` to look up all callsigns concurrently via `CallsignLookupService` + `extractPrimaryCallsign`
  - Updates `multiLookupResults` entries as each lookup completes (swap `.loading` -> `.found`/`.notFound`/`.error`)
  - Sets `lookupResult` to the first `.found` result for backward compatibility (form field population)
- Store the multi-lookup `Task` in the existing `lookupTask` property so it is cancelled on input change

**When input changes back to single callsign:** Clear `multiLookupResults` and fall back to the normal single-lookup path in `onCallsignChanged`.

### 2. Multi-card display component

Update `callsignLookupDisplay` in `LoggerView+Layout.swift` to conditionally show:
- **Single callsign** (no `quickEntryMultiResults`): existing `LoggerCallsignCard` unchanged
- **Multiple callsigns**: `MultiCallsignLookupView`

**Visibility when typing:** The existing single-card guard (`!callsignFieldFocused || callsignInput.isEmpty`) suppresses the card while typing. For multi-callsign display, this guard is **relaxed** — `MultiCallsignLookupView` is shown while `callsignFieldFocused` is true, because the user needs to see lookup results for all callsigns as they compose the entry. The `compactFieldFocus` guard still applies (hide when editing RST/grid/etc fields).

**Both references to `callsignLookupDisplay` must be updated:**
1. Main scroll body (line ~16 in `LoggerView+Layout.swift`)
2. Pinned command bar overlay (line ~175 in `LoggerView+Layout.swift`)

Since `callsignLookupDisplay` is a single computed property, the conditional logic inside it handles both sites automatically.

**`MultiCallsignLookupView` design (compact chips + expandable card):**

- **Chip row:** Horizontal wrapping row of callsign chips. Each chip shows:
  - Callsign (monospaced, bold)
  - Country flag (if lookup completed with result)
  - `ProgressView()` spinner if state is `.loading`
  - Highlighted border/background when selected
  - Tappable — sets `selectedMultiLookupIndex`
  - `.accessibilityLabel("callsign, country, tap to expand details")`
- **Expanded card:** Below the chip row, show a full `LoggerCallsignCard` for the currently selected chip (when state is `.found`). For `.notFound` / `.error` states, show a lightweight fallback view with callsign and status message (do not extend `LoggerCallsignCard` with error handling). For `.loading`, show a skeleton/placeholder.
- **Transitions:** Chip selection change animates the card swap (opacity crossfade).
- **Index safety:** When `quickEntryMultiResults` changes count, reset `selectedMultiLookupIndex` to `0`.

### 3. Previous QSO counts

Each callsign's previous QSO count is stored inside its `MultiCallsignLookupState.found` case. Fetched alongside the lookup in the `TaskGroup`.

### 4. QSO logging

`logMultiQuickEntry` currently passes `nil` for `name`, `country`, `qth`, `theirLicenseClass`. Update it to match each `QuickEntryResult.callsign` against `multiLookupResults` and apply lookup data when available (state is `.found`). If a lookup is still `.loading` or failed, proceed with `nil` — logging is never blocked by pending lookups.

### 5. Form reset

`resetFormAfterLog` must also:
- Clear `multiLookupResults` to `[]` (not subject to `keepLookupAfterLog` — multi-lookup cards are always cleared after logging, since multiple cards persisting would be confusing)
- Reset `selectedMultiLookupIndex` to `0`
- Cancel any in-flight multi-lookup task (already handled by clearing `lookupTask`)

### 6. Landscape layout

The landscape logger layout also shows the callsign card. The same conditional (single card vs `MultiCallsignLookupView`) applies there via `callsignLookupDisplay`.

## Files to modify

| File | Change |
|------|--------|
| `LoggerView.swift` | Add `@State var multiLookupResults: [MultiCallsignLookupState]`, `@State var selectedMultiLookupIndex: Int` |
| `LoggerView+Data.swift` | Add multi-callsign lookup path in `onCallsignChanged`; existing single-lookup path only runs when `quickEntryMultiResults` is nil |
| `LoggerView+Layout.swift` | Update `callsignLookupDisplay` to conditionally show `MultiCallsignLookupView`; relax focus guard for multi path |
| `LoggerView+QSOLogging.swift` | Apply matched lookup data in `logMultiQuickEntry`; clear `multiLookupResults` in `resetFormAfterLog` |
| **New:** `MultiCallsignLookupView.swift` | Chip row + expandable card component |
| **New:** `MultiCallsignLookupState.swift` | Enum for loading/found/notFound/error states |
| `LoggerView+Landscape.swift` | Uses `callsignLookupDisplay` — no direct changes needed if the computed property handles the conditional |

## Out of scope

- Changes to QSO model (no new fields needed)
- Changes to ADIF export
- Changes to session operator tracking
- Changes to quick entry parser
- Operator switching / active operator selection

## Edge cases

- **Lookup failure for one callsign:** Chip shows callsign without flag; expanded view shows lightweight "Not found" or error message. Other lookups unaffected.
- **User removes a callsign while lookups in flight:** `lookupTask` is cancelled and re-triggered via `onCallsignChanged`. New `multiLookupResults` array is built from scratch.
- **Single callsign after multi:** Clear `multiLookupResults`, reset `selectedMultiLookupIndex`, fall back to normal single-card display.
- **Many callsigns (5+):** Chip row wraps to multiple lines. Expandable card keeps vertical space bounded.
- **Partial callsigns (< 3 chars):** Multi-lookup only triggers when all callsigns in `quickEntryMultiResults` have primary length >= 3. Until then, no lookup results are shown (chips remain in `.loading` state or are not shown).
- **Log while lookups in progress:** Logging proceeds immediately. QSOs for callsigns with completed lookups get metadata; others get `nil`. Lookups are never blocking.
