# Activation Metadata Design

Store WEATHER and SOLAR conditions as activation metadata, not as QSO modes.

## Problem

Ham2K PoLo exports WEATHER and SOLAR as pseudo-modes in ADIF/LoFi sync. These are metadata about activation conditions, not actual radio contacts. Currently they either:
- Fail import validation (no callsign)
- Get stored as QSOs with invalid modes
- Get uploaded to POTA.app incorrectly

## Solution

### 1. New ActivationMetadata Model

Lightweight SwiftData entity for storing per-activation metadata:

```swift
@Model
final class ActivationMetadata {
    var parkReference: String      // e.g., "K-1234"
    var date: Date                 // Start of day (UTC)
    var weather: String?           // e.g., "SUNNY", "CLOUDY"
    var solarConditions: String?   // e.g., "GOOD", "POOR"
}
```

No relationship to QSO - just a lookup table by park+date.

### 2. Import Service Changes

In `importFromLoFi`, before processing QSOs:

1. Separate metadata entries (mode = WEATHER/SOLAR) from real QSOs
2. Extract and store metadata in `ActivationMetadata`
3. Process only real QSOs through existing import logic

```swift
let metadataModes = Set(["WEATHER", "SOLAR"])

let metadataEntries = qsos.filter { lofiQso, _ in
    metadataModes.contains(lofiQso.mode?.uppercased() ?? "")
}

let realQsos = qsos.filter { lofiQso, _ in
    !metadataModes.contains(lofiQso.mode?.uppercased() ?? "")
}
```

### 3. POTA Upload Safety

In `POTAClient.generateADIF`, filter out metadata modes:

```swift
let metadataModes = Set(["WEATHER", "SOLAR"])
let realQsos = qsos.filter { !metadataModes.contains($0.mode.uppercased()) }
```

### 4. Dashboard Simplification

Remove attempted activations count. Show only successful activations (10+ QSOs).

Before: `3/5 Activations`
After: `3 Activations`

## Files to Modify

- `Models/ActivationMetadata.swift` (new)
- `FullDuplexApp.swift` (add to schema)
- `Services/ImportService.swift`
- `Services/POTAClient.swift`
- `Views/Dashboard/DashboardView.swift`

## Testing

- Import LoFi data with WEATHER/SOLAR entries
- Verify metadata stored in ActivationMetadata
- Verify WEATHER/SOLAR not counted as modes
- Verify POTA uploads exclude these entries
- Verify dashboard shows only successful activations
