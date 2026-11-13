# Force Re-download Feature Design

## Overview

Add a "Force Re-download All QSOs" button to each service's settings page (visible only in debug mode). When tapped, it fetches all QSOs from that service and updates existing matching QSOs with freshly-parsed field values.

## Use Case

Data repair: when parsing/processing logic changes, re-fetch from the source and re-run through ImportService to update existing QSOs with corrected field values.

## UI Design

Each service settings view gets a new section at the bottom (debug mode only):

```
┌─────────────────────────────────────────┐
│ Debug                                   │
├─────────────────────────────────────────┤
│ [Force Re-download All QSOs]            │
│                                         │
│ Re-fetches all QSOs from [Service] and  │
│ updates existing records with fresh     │
│ parsed values.                          │
└─────────────────────────────────────────┘
```

- Only visible when `SyncDebugLog.shared.isDebugEnabled` is true
- Button shows activity indicator while running
- Shows result: "Updated X QSOs, Created Y QSOs" or error message

## Implementation

### 1. ImportService Changes

Add `reprocessQSOs(from:service:)` method:
- Takes `[FetchedQSO]` array and `ServiceType`
- For each fetched QSO, finds existing QSO by deduplication key
- If found: updates all fields from freshly-parsed data
- If not found: creates new QSO (normal import behavior)
- Returns `(updated: Int, created: Int)` counts

### 2. SyncService Changes

Add public methods per service in `SyncService+Download.swift`:
- `forceRedownloadFromQRZ() async throws -> (updated: Int, created: Int)`
- `forceRedownloadFromPOTA() async throws -> (updated: Int, created: Int)`
- `forceRedownloadFromLoFi() async throws -> (updated: Int, created: Int)`
- `forceRedownloadFromHAMRS() async throws -> (updated: Int, created: Int)`
- `forceRedownloadFromLoTW() async throws -> (updated: Int, created: Int)`

Each method:
1. Calls existing `downloadFrom*` private method to fetch all QSOs
2. Passes results to `ImportService.reprocessQSOs()`
3. Returns counts for UI display

### 3. Settings View Changes

Add debug section to:
- `ServiceSettingsViews.swift` (QRZ, POTA, LoFi settings)
- `HAMRSSettingsView.swift`
- `LoTWSettingsView.swift`

## Files to Modify

| File | Change |
|------|--------|
| `CarrierWave/Services/ImportService.swift` | Add `reprocessQSOs(from:service:)` method |
| `CarrierWave/Services/SyncService+Download.swift` | Add 5 `forceRedownloadFrom*()` public methods |
| `CarrierWave/Views/Settings/ServiceSettingsViews.swift` | Add debug section to QRZ, POTA, LoFi views |
| `CarrierWave/Views/Settings/HAMRSSettingsView.swift` | Add debug section |
| `CarrierWave/Views/Settings/LoTWSettingsView.swift` | Add debug section |
