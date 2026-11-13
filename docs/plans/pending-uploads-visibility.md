# Pending Uploads Visibility

## Problem

Users (and us) are confused about why QSOs are stuck as "pending upload." The current system shows:
- **Sync Debug View**: raw counts and logs (developer-oriented, not actionable)
- **Upload Diagnostics View**: errors from the *last sync attempt* (good for failures, silent about QSOs that are pending but haven't been attempted)
- **iCloud Settings**: aggregate dirty record counts (iCloud-specific, not per-service upload status)

**What's missing:** a way to see the *actual list* of QSOs pending upload, understand *why each one is pending*, and export that info for troubleshooting.

## Root Causes a QSO Can Be "Pending"

From the codebase, a QSO with `needsUpload=true` on a `ServicePresence` record may be pending for these reasons:

| # | Reason | Detectable? | Service |
|---|--------|-------------|---------|
| 1 | **Never attempted** — newly logged, hasn't synced yet | Yes: `needsUpload=true`, `lastConfirmedAt=nil`, no error | All |
| 2 | **Missing fields** — no band AND no frequency | Yes: `!hasRequiredFieldsForUpload` | All |
| 3 | **Missing park reference** — POTA QSO without park ref | Yes: `parkReference` nil/empty | POTA |
| 4 | **Invalid park reference** — rejected by POTA | Yes: `uploadRejected=true` | POTA |
| 5 | **Callsign mismatch** — `myCallsign` ≠ primary callsign | Yes: compare with `CallsignAliasService` | All |
| 6 | **Club station** — `stationCallsign` is set | Yes: `stationCallsign != nil` | All |
| 7 | **Service not configured** — no API key / not authenticated | Yes: check auth state | All |
| 8 | **Upload failed (transient)** — network/timeout/maintenance | Yes: `UploadDiagnosticStore` has error | All |
| 9 | **Upload failed (permanent)** — auth, subscription, rejected | Yes: `UploadDiagnosticStore` has error | All |
| 10 | **Submitted, awaiting confirmation** (POTA only) | Yes: `isSubmitted=true` | POTA |
| 11 | **Metadata pseudo-mode** — should never have `needsUpload` | Yes: `QSOMode.isMetadata` (data repair bug) | All |
| 12 | **Hidden/soft-deleted** — filtered out at upload time | Yes: `isHidden` | All |

## Design

### New View: "Pending Uploads" (accessible from Sync Settings)

A `NavigationLink` in the existing sync service settings (per-service, not iCloud) that opens a **PendingUploadsView**.

#### Structure

```
┌─────────────────────────────────────────┐
│ Pending Uploads                    ⋯ ▼  │  ← toolbar: export menu
├─────────────────────────────────────────┤
│                                         │
│ ┌ Summary Card ───────────────────────┐ │
│ │  12 QSOs pending across 3 services  │ │
│ │  ● 3 need attention  ● 9 will retry │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌ Filter Chips ───────────────────────┐ │
│ │ [All] [QRZ] [POTA] [Club Log] ...  │ │
│ │ [All Reasons] [Missing Fields] ...  │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ── Needs Attention (3) ──────────────── │
│ │ W1AW  20m FT8  2026-03-20 14:32     │ │
│ │ ⚠ Missing frequency                 │ │
│ │ → QRZ, POTA                         │ │
│ ├──────────────────────────────────────┤ │
│ │ K3ABC 40m SSB  2026-03-19 21:15     │ │
│ │ ⚠ Invalid park ref: US-99999        │ │
│ │ → POTA (rejected)                   │ │
│ ├──────────────────────────────────────┤ │
│ │ N5DEF 15m CW   2026-03-18 03:44     │ │
│ │ ⚠ No park reference                 │ │
│ │ → POTA                              │ │
│                                         │
│ ── Will Retry (9) ───────────────────── │
│ │ KA1BB 20m FT8  2026-03-22 01:12     │ │
│ │ ↻ Not yet attempted                  │ │
│ │ → QRZ, POTA                         │ │
│ │ ...                                  │ │
│                                         │
│ ── Excluded from Upload (2) ─────────── │
│ │ VE3XYZ 40m SSB  2026-03-21 ...      │ │
│ │ ✕ Callsign mismatch (VE3XYZ ≠ W1AW)│ │
│ │ → All services                       │ │
│ └──────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

#### Pending Reason Enum

New enum `PendingUploadReason` that classifies each QSO × service combination:

```swift
enum PendingUploadReason: String, CaseIterable {
    case notYetAttempted      // Fresh QSO, will upload next sync
    case missingFields        // No band AND no frequency
    case missingParkReference // POTA: no park ref
    case invalidParkReference // POTA: uploadRejected=true
    case callsignMismatch    // myCallsign ≠ primary
    case clubStation         // stationCallsign set
    case serviceNotConfigured // Service auth missing
    case uploadFailed        // Transient error from last attempt
    case awaitingConfirmation // POTA: isSubmitted=true
    case metadataMode        // Bug: metadata QSO has needsUpload
    case hidden              // Soft-deleted QSO
}
```

Properties: `title`, `explanation`, `iconName`, `isActionable` (user can fix), `isTransient` (will auto-resolve).

#### Data Loading

New `PendingUploadAnalyzer` (non-actor, `@MainActor` service):

```swift
@MainActor
final class PendingUploadAnalyzer {
    struct PendingQSO: Identifiable {
        let qso: QSO
        let services: [ServiceType]
        let reason: PendingUploadReason
        let detail: String  // e.g. "park ref US-99999"
    }

    func analyze(context: ModelContext) -> [PendingQSO]
}
```

**Query strategy** (respects performance rules):
1. Fetch `ServicePresence` where `needsUpload == true`, with `fetchLimit` (batched, max 500)
2. For each, resolve the QSO and classify the reason
3. Group by QSO (dedup via `PersistentIdentifier`), merge services
4. Sort: actionable first, then by timestamp descending

#### Export

Toolbar menu with:
- **Copy to Clipboard** — markdown table
- **Share as CSV** — via share sheet, columns: `Callsign, Date, Band, Mode, Services, Reason, Detail`
- **Share as ADIF** — just the pending QSOs as ADIF (useful for manual upload)

Export header includes filter criteria so the recipient knows what they're looking at:
```
# Carrier Wave — Pending Uploads Export
# Generated: 2026-03-22 14:30 UTC
# Filter: POTA only, Missing Park Reference
# Primary callsign: W1AW
# Total: 3 QSOs
```

#### Navigation Entry Point

Add to each service's settings section (QRZ, POTA, Club Log, eQSL) and to the main Sync Settings:

```swift
NavigationLink {
    PendingUploadsView(filterService: .pota)
} label: {
    Label("Pending Uploads", systemImage: "arrow.up.circle.badge.clock")
    // Badge with count
}
```

Also accessible from the Sync Debug View as a new tab (replacing or alongside "Stats").

## Files to Create/Modify

### New Files
| File | Purpose | Package |
|------|---------|---------|
| `CarrierWave/Services/PendingUploadAnalyzer.swift` | Classify pending QSOs by reason | App |
| `CarrierWave/Views/Settings/PendingUploadsView.swift` | Main list view | App |
| `CarrierWave/Views/Settings/PendingUploadRow.swift` | Row component | App |
| `CarrierWaveData/.../PendingUploadReason.swift` | Reason enum (shared) | Data |

### Modified Files
| File | Change |
|------|--------|
| `SyncDebugView.swift` | Add "Pending" tab |
| Service settings views | Add NavigationLink with badge count |
| `docs/FILE_INDEX.md` | Register new files |

## Implementation Phases

### Phase 1: Core Analysis + View (MVP)
- `PendingUploadReason` enum
- `PendingUploadAnalyzer` with classification logic
- `PendingUploadsView` with grouped list, service filter chips
- Entry point from Sync Debug View

### Phase 2: Export
- CSV export with filter header
- Clipboard copy as markdown
- ADIF export of pending QSOs

### Phase 3: Polish
- Badge counts on navigation links
- Entry points from per-service settings
- Tap row to navigate to QSO detail (for editing missing fields)

## Performance Considerations

- Query `ServicePresence` (not QSO) with `fetchLimit`
- Classify in-memory after fetch (no additional queries per QSO)
- No `@Query` — use `@State` + `.task`
- Cap displayed results at 200 with "and N more..." footer
