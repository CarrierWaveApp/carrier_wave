# Sync Model Redesign

## Overview

Redesign FullDuplex's sync model to:
- Store all QSOs in a single local database as the source of truth
- Track which services have each QSO via a new `ServicePresence` model
- Derive all dashboard counts from the database (no incremental counters)
- Sync by downloading from ALL sources first, then uploading

## Services

| Service | Direction | Notes |
|---------|-----------|-------|
| QRZ | Bidirectional | Download via FETCH API, upload via INSERT API |
| POTA | Bidirectional | Download via user/activations + user/logbook API, upload via multipart ADIF |
| LoFi | Download-only | Via Ham2K LoFi API |

## Data Model Changes

### New: `ServicePresence` (replaces `SyncRecord`)

```swift
@Model
final class ServicePresence {
    var id: UUID
    var serviceType: ServiceType  // .qrz, .pota, .lofi
    var isPresent: Bool           // QSO exists in this service
    var needsUpload: Bool         // Needs to be pushed to this service
    var lastConfirmedAt: Date?    // When we last confirmed presence

    var qso: QSO?
}
```

### New: `ServiceType` enum (replaces `DestinationType`)

```swift
enum ServiceType: String, Codable, CaseIterable {
    case qrz
    case pota
    case lofi

    var displayName: String {
        switch self {
        case .qrz: return "QRZ"
        case .pota: return "POTA"
        case .lofi: return "LoFi"
        }
    }

    var supportsUpload: Bool {
        switch self {
        case .qrz, .pota: return true
        case .lofi: return false
        }
    }
}
```

### QSO Changes

- Keep `importSource` to track original source
- Replace `syncRecords: [SyncRecord]` relationship with `servicePresence: [ServicePresence]`
- Keep existing QRZ-specific fields (`qrzLogId`, `qrzConfirmed`, `lotwConfirmedDate`)

### Removals

- `SyncRecord` model
- `SyncStatus` enum
- `DestinationType` enum
- Keychain-based counters (`qrzTotalUploaded`, `qrzTotalDownloaded`, etc.)

## Sync Flow

```
1. DOWNLOAD PHASE (parallel)
   ├── QRZ: fetchQSOs() → [QRZFetchedQSO]
   ├── POTA: fetchActivations() + fetchQSOs() → [POTAFetchedQSO]
   └── LoFi: fetchAllQsosSinceLastSync() → [LoFiFetchedQSO]

2. PROCESS PHASE (sequential)
   ├── Convert all fetched QSOs to a common intermediate format
   ├── Group by deduplicationKey
   ├── For each group:
   │   ├── Find existing QSO in DB by deduplicationKey
   │   ├── If exists: merge fields (richest data wins), update ServicePresence
   │   └── If new: create QSO, create ServicePresence for each source
   └── Mark needsUpload=true for services missing this QSO (if service supports upload)

3. UPLOAD PHASE (parallel)
   ├── QRZ: upload QSOs where servicePresence[.qrz].needsUpload == true
   └── POTA: upload QSOs where servicePresence[.pota].needsUpload == true

4. CONFIRM PHASE
   └── For successful uploads, set isPresent=true, needsUpload=false, lastConfirmedAt=now
```

### Key Behaviors

- Downloads happen concurrently using Swift's `async let` or `TaskGroup`
- DB writes happen on main actor after all downloads complete
- Uploads happen concurrently after DB is updated
- Each phase completes fully before the next begins

## Dashboard Counts

All counts derived from database queries, never stored or incremented:

```swift
func downloadedCount(for service: ServiceType) -> Int {
    // QSOs where this service was the original source
    qsos.filter { $0.importSource == service.toImportSource }.count
}

func uploadedCount(for service: ServiceType) -> Int {
    // QSOs that exist in this service (regardless of origin)
    // This is the union of: downloaded from service + uploaded to service
    qsos.filter { qso in
        qso.servicePresence.contains {
            $0.serviceType == service && $0.isPresent
        }
    }.count
}

func pendingCount(for service: ServiceType) -> Int {
    // QSOs that need to be uploaded to this service
    qsos.filter { qso in
        qso.servicePresence.contains {
            $0.serviceType == service && $0.needsUpload
        }
    }.count
}
```

### Dashboard Display Per Service

- **Downloaded**: "X downloaded" — QSOs originally from this service
- **Uploaded/Synced**: "X in [service]" — all QSOs present in service
- **Pending**: "X pending" — QSOs needing upload

### Total QSOs

`qsos.count` is the single source of truth for total QSO count.

## Field-by-Field Merge Strategy

When the same QSO exists in multiple sources, merge to keep richest data:

```swift
func mergeQSO(existing: QSO, incoming: FetchedQSO, source: ServiceType) {
    // For each optional field, prefer non-nil/non-empty value
    existing.frequency = existing.frequency ?? incoming.frequency
    existing.rstSent = existing.rstSent.nonEmpty ?? incoming.rstSent
    existing.rstReceived = existing.rstReceived.nonEmpty ?? incoming.rstReceived
    existing.myGrid = existing.myGrid.nonEmpty ?? incoming.myGrid
    existing.theirGrid = existing.theirGrid.nonEmpty ?? incoming.theirGrid
    existing.parkReference = existing.parkReference.nonEmpty ?? incoming.parkReference
    existing.notes = existing.notes.nonEmpty ?? incoming.notes

    // QRZ-specific: only update from QRZ source
    if source == .qrz {
        existing.qrzLogId = existing.qrzLogId ?? incoming.qrzLogId
        existing.qrzConfirmed = existing.qrzConfirmed || incoming.qrzConfirmed
        existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? incoming.lotwConfirmedDate
    }

    // Update ServicePresence for this source
    markPresent(qso: existing, service: source)
}
```

### For New QSOs from Multiple Sources in Same Sync

1. Process all downloads into intermediate structs first
2. Group by `deduplicationKey`
3. If multiple sources have same key, merge all into one QSO
4. Create `ServicePresence` for each source that had it

## Migration Strategy

### Data Migration Steps

1. **For each existing QSO with SyncRecords:**
   - Create `ServicePresence` records based on existing `SyncRecord` data
   - If `syncRecord.status == .uploaded` → `isPresent: true, needsUpload: false`
   - If `syncRecord.status == .pending` → `isPresent: false, needsUpload: true`

2. **For QSOs imported from LoFi:**
   - `importSource == .lofi` → create `.lofi` presence with `isPresent: true, needsUpload: false`

3. **For QSOs imported from QRZ:**
   - `importSource == .qrz` → create `.qrz` presence with `isPresent: true, needsUpload: false`

4. **Delete old data:**
   - Remove all `SyncRecord` entries
   - Clear Keychain counter keys

### SwiftData Migration

- Use a versioned schema migration
- Run migration logic on first launch after update

## Files to Modify

| File | Changes |
|------|---------|
| `Types.swift` | Add `ServiceType`, remove `DestinationType`, `SyncStatus` |
| `SyncRecord.swift` | Rename to `ServicePresence.swift`, update fields |
| `QSO.swift` | Update relationship from `syncRecords` to `servicePresence` |
| `SyncService.swift` | Rewrite sync logic with parallel download/upload phases |
| `ImportService.swift` | Update to create `ServicePresence` instead of `SyncRecord` |
| `DashboardView.swift` | Derive counts from queries, remove Keychain counter reads |
| `QRZClient.swift` | Remove Keychain counter methods |
| `POTAClient.swift` | Add download methods (activations + QSOs) |
| `LoFiClient.swift` | No changes needed |
| `KeychainHelper.swift` | Remove counter-related keys |

## New Files

| File | Purpose |
|------|---------|
| `ServicePresence.swift` | New model (or rename from SyncRecord) |
| `SyncCoordinator.swift` | Optional: separate class to orchestrate the sync phases |
| `FetchedQSO.swift` | Optional: common intermediate format for downloaded QSOs |
