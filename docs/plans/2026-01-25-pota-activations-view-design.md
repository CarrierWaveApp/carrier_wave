# POTA Activations View Design

## Overview

Replace the existing "POTA Uploads" view with a new "POTA Activations" view that groups QSOs by activation (park + UTC date + callsign) and allows uploading activations to POTA.

## Definitions

**Activation**: A group of QSOs defined by:
- `parkReference` (e.g., "K-1234")
- UTC date (start of day)
- `myCallsign` used during the activation

## Data Model

### POTAActivation (View Model, not persisted)

```swift
struct POTAActivation: Identifiable {
    let parkReference: String
    let utcDate: Date  // Start of UTC day
    let callsign: String
    let qsos: [QSO]
    
    var id: String { "\(parkReference)|\(callsign)|\(utcDateString)" }
}
```

### QSO Upload Status

A QSO is considered "present in POTA" if ANY of these are true:
1. Its `importSource` is `.pota` (downloaded from POTA)
2. It has a `ServicePresence` record for `.pota` with `isPresent = true`
3. It was included in a successful local `POTAUploadAttempt` that correlates with a completed `POTAJob`

### Activation-Level Status

- **Uploaded**: All QSOs are present in POTA
- **Partial**: Some QSOs present, some not
- **Pending**: No QSOs present in POTA

## View Structure

```
POTAActivationsContentView
├── List grouped by parkReference
│   └── Section per park (e.g., "K-1234 - Park Name")
│       └── ActivationRow per (date, callsign)
│           ├── Date + callsign
│           ├── QSO count + status indicator
│           └── Upload button (if has pending QSOs)
```

### Status Indicators

- Green checkmark: All QSOs uploaded
- Orange partial circle: Some QSOs uploaded  
- Gray circle: No QSOs uploaded (pending)

### Upload Button

- Visible only for activations with at least one un-uploaded QSO
- Tapping shows confirmation sheet before uploading

### Confirmation Sheet

Contents:
- Park reference + park name (if available from jobs)
- Activation date (formatted)
- Callsign used
- "X of Y QSOs to upload"
- Upload / Cancel buttons

## Implementation

### Files to Modify

1. **Rename & Rewrite**: `POTAUploadsView.swift` → `POTAActivationsView.swift`
2. **Update**: `LogsContainerView.swift` - change segment enum value
3. **Keep**: `POTALogEntry.swift` - may still be useful for job correlation

### Grouping Logic

```swift
func groupIntoActivations(qsos: [QSO]) -> [String: [POTAActivation]] {
    // 1. Filter QSOs with non-nil parkReference
    // 2. Group by (parkReference, utcDate, myCallsign)
    // 3. Return dictionary keyed by parkReference for sectioning
}
```

### Data Flow

1. Query all QSOs with non-nil `parkReference`
2. Fetch `POTAUploadAttempt` records (local)
3. Fetch `POTAJob` records (remote, on refresh)
4. Group QSOs into activations
5. For each QSO, determine upload status
6. Display grouped by park, sorted by date descending within each park

### Upload Flow

1. User taps "Upload" on an activation
2. Show confirmation sheet with details
3. On confirm: filter to only un-uploaded QSOs
4. Call existing `POTAClient` upload methods
5. On success: update ServicePresence for uploaded QSOs
6. Refresh view to show updated status
