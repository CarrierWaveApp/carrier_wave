# Plan: Edit QSOs from Session Detail View

## Goal

Allow users to tap a QSO in the session detail QSO list and open the existing `QSOEditSheet` to edit it, with the same callsign lookup behavior (QRZ + HamDB via `CallsignLookupService`) that already exists in the Logs tab and Logger tab edit flows.

## Current State

- **`SessionDetailView`** (`Views/Sessions/SessionDetailView.swift`) shows QSOs in a list using `SessionQSORow`. Rows are expandable (DisclosureGroup) and support swipe-to-delete, but have no edit action.
- **`QSOEditSheet`** (`Views/Logs/QSOEditSheet.swift`) is the full-featured edit sheet used by `QSODetailView` (Logs tab). It edits all fields and triggers `CallsignLookupService.lookup()` when the callsign changes, which runs Polo notes + QRZ XML lookups and backfills name, grid, state, country, QTH, and license class.
- **`LoggerQSOEditSheet`** (`Views/Logger/LoggerView+EditSheets.swift`) is a lighter edit sheet used in the active logger. It also does the same `CallsignLookupService` lookup on callsign change.

## Approach

Reuse `QSOEditSheet` (the full-featured one from Logs) since session detail is a review context where users should have access to all fields. This already has the QRZ/HamDB lookup built in.

## Changes

### 1. Add edit state to `SessionDetailView` (~5 lines)

**File:** `CarrierWave/Views/Sessions/SessionDetailView.swift`

Add a `@State private var qsoToEdit: QSO?` property alongside the existing `qsoToDelete` state. Add a `.sheet` modifier for QSOEditSheet, gated on `qsoToEdit`:

```swift
@State private var qsoToEdit: QSO?
```

```swift
.sheet(item: $qsoToEdit) { qso in
    QSOEditSheet(qso: qso) {
        Task { await loadQSOs() }
    }
    .landscapeAdaptiveDetents(portrait: [.large])
}
```

### 2. Make QSO rows tappable to open edit sheet (~6 lines each, 2 places)

**File:** `CarrierWave/Views/Sessions/SessionDetailView.swift`

In both `flatQSOSection` and `roveQSOSections`, wrap each `SessionQSORow` in a `Button` that sets `qsoToEdit`:

```swift
Button {
    qsoToEdit = qso
} label: {
    SessionQSORow(qso: qso)
}
.tint(.primary)
```

### 2b. Simplify SessionQSORow (~remove DisclosureGroup)

**File:** `CarrierWave/Views/Sessions/SessionQSORow.swift`

Remove the `DisclosureGroup` and `isExpanded` state. The row body becomes just the compact HStack label with `.contentShape(Rectangle())` for full-row tap hit testing.

### 3. Refresh QSO list after edit save

The `onSave` callback in the sheet (step 1) already calls `loadQSOs()` to refresh the list, which will pick up any field changes. The `CallsignLookupService` runs asynchronously after save inside `QSOEditSheet.save()` — once it writes back to the model context, the next list refresh will show updated data.

## What we get for free

- **QRZ + Polo notes lookup** — `QSOEditSheet.save()` already creates a `CallsignLookupService` and calls `lookup()` when the callsign changes, which goes through the full two-tier pipeline (Polo notes local → QRZ XML API remote). QRZ internally calls HamDB for license class.
- **All editable fields** — callsign, band, mode, frequency, timestamp, RST, name, grids, parks, SOTA ref, power, QTH, state, country, notes.
- **Cloud sync dirty flag** — `QSOEditSheet.save()` sets `cloudDirtyFlag = true` and `modifiedAt = Date()`.
- **Haptic feedback** on save.

## Files Modified

| File | Change |
|------|--------|
| `CarrierWave/Views/Sessions/SessionDetailView.swift` | Add `qsoToEdit` state, `.sheet` modifier, wrap QSO rows in Button |
| `CarrierWave/Views/Sessions/SessionQSORow.swift` | Remove DisclosureGroup, simplify to plain tappable row |

## Not Changed

- `QSOEditSheet` — no modifications needed, it already does everything we need.
- No new files created.

## Testing

- Open a completed session from Sessions tab
- Tap a QSO row → `QSOEditSheet` opens with all fields populated
- Change callsign → save → verify lookup runs and backfills name/grid/location
- Edit other fields → save → verify changes persist
- Verify the QSO list refreshes after save
