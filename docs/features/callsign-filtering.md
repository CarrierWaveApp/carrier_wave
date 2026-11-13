# Callsign Filtering Guidelines

Users may have multiple callsigns over their amateur radio career (e.g., upgraded licenses, vanity callsigns, callsigns from different countries). Carrier Wave tracks these via the `CallsignAliasService`.

## Terminology

| Term | Definition |
|------|------------|
| **Primary callsign** | The user's current callsign, stored in Keychain. This is the callsign linked to their QRZ, POTA, and other service accounts. |
| **Previous callsigns** | Historical callsigns the user has held. QSOs logged under these calls are kept for local records but cannot be synced to services. |
| **`myCallsign`** | The `QSO.myCallsign` field indicating which callsign was used when making the contact. |

## Core Rule

**All sync operations (uploads) MUST filter to only include QSOs where `myCallsign` matches the user's primary callsign.**

Services like QRZ and POTA authenticate with the user's current callsign. Attempting to upload QSOs logged under a different callsign will:
- **QRZ**: Silently skip the QSO (callsign mismatch)
- **POTA**: Reject the upload or associate it with the wrong account

## Implementation Requirements

### Sync Uploads

When building upload queues, always filter by primary callsign:

```swift
// CORRECT - filter to primary callsign
let primaryCallsign = CallsignAliasService.shared.getCurrentCallsign()?.uppercased()
let uploadQueue = qsosNeedingUpload.filter { qso in
    let myCall = qso.myCallsign.uppercased()
    return myCall.isEmpty || myCall == primaryCallsign
}

// WRONG - includes QSOs from previous callsigns that will fail to upload
let uploadQueue = qsosNeedingUpload
```

### ServicePresence Records

Only create `ServicePresence` records (which track upload status) for QSOs that match the primary callsign. QSOs from previous callsigns should NOT have pending upload markers.

### Statistics and Local Features

Statistics, maps, and other local-only features MAY include QSOs from all user callsigns (current + previous) since they don't involve external service authentication. Use `CallsignAliasService.getAllUserCallsigns()` when you need to include historical data.

### New Feature Checklist

When implementing features that interact with external services:

1. Does it upload data? Filter to primary callsign only.
2. Does it create upload markers (`ServicePresence`)? Only for primary callsign QSOs.
3. Does it query an authenticated API? Use the primary callsign for lookups.
4. Is it local-only (stats, display)? Can include all user callsigns.

## Related Code

- `CallsignAliasService` (`CarrierWave/Services/CallsignAliasService.swift`): Manages callsign storage and comparison
- `SyncService+Upload` (`CarrierWave/Services/SyncService+Upload.swift`): Upload orchestration
- `CallsignAliasesSettingsView` (`CarrierWave/Views/Settings/CallsignAliasesSettingsView.swift`): User configuration UI

## User-Facing Behavior

Users can configure their callsigns in Settings > Callsign Aliases:
- **Current Callsign**: Auto-populated from QRZ when connecting; used for all syncs
- **Previous Callsigns**: Historical callsigns for local matching only

QSOs logged under previous callsigns are preserved locally but clearly marked as non-syncable.
