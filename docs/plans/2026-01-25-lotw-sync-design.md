# LoTW Sync Design

## Overview

Add ARRL Logbook of the World (LoTW) as a sync destination for downloading QSOs and QSL confirmations. LoTW is download-only (uploads require TQSL application).

## Goals

- Import QSOs from LoTW, deduplicated against existing records
- Track LoTW confirmation status on QSOs
- Enable challenges to require confirmed contacts

## Data Model Changes

### QSO Model

Add two fields to track confirmation status:

```swift
var lotwConfirmed: Bool = false
var lotwConfirmedDate: Date?
```

Updated when:
- A LoTW QSO with `QSL_RCVD=Y` deduplicates against an existing QSO
- A new QSO is created from LoTW data that has confirmation

### UploadDestination

Add LoTW case. Store timestamps from LoTW response headers for incremental sync:
- `lastQSL` - from `APP_LoTW_LASTQSL`, used for `qso_qslsince` parameter
- `lastQSORx` - from `APP_LoTW_LASTQSORX`, used for `qso_qsorxsince` parameter

### Keychain Keys

- `lotw_username`
- `lotw_password`

## LoTWClient

New actor at `CarrierWave/Services/LoTWClient.swift`.

### API Details

- **Endpoint:** `https://lotw.arrl.org/lotwuser/lotwreport.adi`
- **Auth:** Username/password via query parameters
- **Response:** ADIF format

### Query Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `login` | username | Authentication |
| `password` | password | Authentication |
| `qso_query` | `1` | Required for QSO records |
| `qso_qsl` | `yes` | Fetch confirmed QSLs |
| `qso_qslsince` | `YYYY-MM-DD` | Incremental sync filter |
| `qso_qsorxsince` | `YYYY-MM-DD` | Incremental sync filter |
| `qso_mydetail` | `yes` | Include station location data |
| `qso_qsldetail` | `yes` | Include QSLing station location |

### Response Handling

Check for `<EOH>` tag to verify success. LoTW returns HTTP 200 with HTML error pages on failure.

Parse response headers:
- `APP_LoTW_LASTQSL` - store for next sync
- `APP_LoTW_LASTQSORX` - store for next sync
- `APP_LoTW_NUMREC` - record count

### Key Method

```swift
func fetchQSOs(
    username: String,
    password: String,
    qslSince: Date? = nil,
    qsoRxSince: Date? = nil
) async throws -> LoTWResponse
```

### LoTWResponse Structure

```swift
struct LoTWResponse {
    let qsos: [FetchedQSO]
    let lastQSL: Date?
    let lastQSORx: Date?
    let recordCount: Int
}
```

### Error Types

```swift
enum LoTWError: Error {
    case authenticationFailed
    case serviceError(String)
    case invalidResponse
}
```

## Sync Integration

### SyncService+Download

Add `syncLoTW()` method:

1. Check if LoTW destination is enabled
2. Retrieve credentials from Keychain
3. Fetch stored timestamps from UploadDestination
4. Call `LoTWClient.fetchQSOs()` (nil timestamps for first sync = full download)
5. Pass results to ImportService
6. Update UploadDestination with new timestamps from response

Called during general sync alongside other services.

### ImportService Changes

Handle LoTW-sourced QSOs:

- Process through existing ADIF parser and deduplication
- On dedup match with existing QSO:
  - If LoTW record has `QSL_RCVD=Y`, set `lotwConfirmed = true`
  - Set `lotwConfirmedDate` from `QSLRDATE` field
- On new QSO creation from LoTW:
  - Set confirmation fields if confirmed

### No SyncRecord

LoTW is download-only, so no SyncRecords are created. Sync state lives in UploadDestination timestamps.

## Settings UI

### LoTWSettingsView

New view at `CarrierWave/Views/Settings/LoTWSettingsView.swift`:

- Toggle to enable/disable LoTW sync
- Username text field
- Password secure field
- "Test Connection" button (fetches recent records to verify credentials)
- Status indicator showing last sync time or error

### SettingsView

Add LoTW row alongside QRZ, POTA, and LoFi entries.

## Dashboard Status

### ServicePresence

Add LoTW to dashboard service cards:

| State | Display |
|-------|---------|
| Not configured | No credentials stored |
| OK | Last sync succeeded, shows timestamp |
| Auth failed | Credentials rejected, needs user action |
| Sync failed | Transient error, will retry |

Distinguish errors:
- `LoTWError.authenticationFailed` → "Auth failed" status
- `LoTWError.serviceError` → "Sync failed" status

## Challenge Integration

The `lotwConfirmed` field enables challenge rules to require confirmed contacts.

### ChallengeQSOMatcher

Can filter by `qso.lotwConfirmed == true` for challenges requiring confirmation.

### Use Cases

- DXCC challenges requiring confirmed contacts per entity
- Award tracking (WAS, VUCC) where confirmation matters
- "Confirmed countries" dashboard statistics

## File Changes Summary

| File | Change |
|------|--------|
| `CarrierWave/Models/QSO.swift` | Add `lotwConfirmed`, `lotwConfirmedDate` |
| `CarrierWave/Models/UploadDestination.swift` | Add LoTW case, timestamp storage |
| `CarrierWave/Services/LoTWClient.swift` | New file |
| `CarrierWave/Services/LoTWError.swift` | New file |
| `CarrierWave/Services/SyncService+Download.swift` | Add `syncLoTW()` |
| `CarrierWave/Services/ImportService.swift` | Handle LoTW source, confirmation updates |
| `CarrierWave/Views/Settings/LoTWSettingsView.swift` | New file |
| `CarrierWave/Views/Settings/SettingsView.swift` | Add LoTW navigation row |
| `CarrierWave/Utilities/KeychainHelper.swift` | Add LoTW key constants |
| Dashboard service cards | Add LoTW status |
