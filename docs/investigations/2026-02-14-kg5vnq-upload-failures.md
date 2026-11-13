# Investigation: KG5VNQ Upload Failures (QRZ + POTA)

**Date:** 2026-02-14
**Status:** Resolved
**Outcome:** Three bugs found: (1) HAMRS supportsUpload=true with no handler creates phantom upload records, (2) QRZ upload clears needsUpload without confirmation creating dead-state QSOs, (3) trailing-space POTA hypothesis disproved. Fixed with supportsUpload correction, isSubmitted tracking, and two new data repair steps.
**User:** KG5VNQ (roothog)
**App Version:** v1.29.0+ (latest upload attempts), v1.20.0 (earliest attempts)
**Database:** `CarrierWave_QSO_Export_2026-02-14_140204.sqlite`

## Problem Statement

User reports QSOs not being uploaded properly. Multiple issues discovered across QRZ and POTA sync.

## Database Summary

| Metric | Value |
|--------|-------|
| Total QSOs | 432 (all CW, all KG5VNQ) |
| Hidden QSOs | 4 |
| Date range | 2025-11-06 to 2026-02-14 |
| Import sources | lofi: 398, logger: 16, pota: 15, qrz: 3 |

### ServicePresence State

| Service | Total | needsUpload | submitted | present | rejected |
|---------|-------|-------------|-----------|---------|----------|
| hamrs | 416 | **416** | 0 | 0 | 0 |
| lofi | 416 | 0 | 0 | 399 | 0 |
| lotw | 416 | 0 | 0 | 0 | 0 |
| pota | 443 | 0 | 0 | 423 | 1 |
| qrz | 432 | 0 | 0 | 360 | 0 |

### Key Anomalies

1. **72 QSOs not present on QRZ** — no QRZ log ID, `needsUpload=0` (should be 1)
   - 41 from lofi import, 16 from logger, 15 from pota import
   - Spans full date range (2025-11 to 2026-02)
2. **416 bogus `hamrs` ServicePresence** records with `needsUpload=1` — HAMRS is NOT an upload destination
3. **All 7 POTA upload attempts returned `{"adif_files": []}`** despite HTTP 200
   - v1.20.0 uploads used wrong location US-TX (known bug, fixed in v1.25.2)
   - v1.29.0 uploads use correct location US-AR — **still rejected**
4. **ADIF has trailing spaces in callsigns**: `F5MQU `, `IK1LBL `, `G4TDX `
5. **Band case inconsistency**: POTA imports use uppercase (15M), lofi/logger use lowercase (15m)
6. **Duplicate QSOs**: Same contact appears twice from different import sources (e.g., F5MQU from both pota and logger at same timestamp)

### Sync Log Evidence (from screenshots)

- "Found 417 QSO(s) with pending uploads" — inflated by hamrs records
- "POTA upload candidates: 0 need upload, 0 have park ref" — POTA thinks everything synced
- "QRZ upload complete: 1 uploaded, 0 skipped" — only new logger QSOs upload to QRZ
- "Downloaded 0 QSOs from QRZ" — incremental download found nothing new
- POTA reconciliation: 33 completed jobs, 506 total QSOs, 427 inserted — reconciliation marks QSOs present from POTA's existing jobs (uploaded via other tools)

## Agent Debate: Hypotheses and Consensus

Three agents investigated competing hypotheses, cross-examining each other's evidence. The debate produced clear consensus on two confirmed bugs and disproved one hypothesis.

### Hypothesis A: QRZ upload clears needsUpload optimistically (CONFIRMED — Agent A)

**Confidence:** MEDIUM-HIGH

**Theory:** `uploadToQRZ()` optimistically clears `needsUpload` after batch upload without per-QSO verification from QRZ. If the batch upload partially fails or QRZ doesn't process all QSOs, they enter a "dead state" where `isPresent=0` AND `needsUpload=0` — no recovery path exists.

**Evidence:**
- 72 QSOs stuck in dead state (`isPresent=0, needsUpload=0`) for QRZ
- `uploadToQRZ()` in `SyncService+Upload.swift` clears needsUpload after HTTP 200 response
- QRZ API returns success for the batch but doesn't guarantee all individual QSOs were accepted
- Orphan repair in `QSOProcessingActor+OrphanRepair.swift` only catches QSOs with NO presence record at all — it doesn't detect the dead state (isPresent=0, needsUpload=0)

**Agent B's challenge:** Could be an import path issue — maybe these QSOs never had needsUpload=1 for QRZ in the first place. However, Agent A showed that `ImportService.createServicePresenceRecords` DOES create QRZ records with `needsUpload=1` for imported QSOs (when `supportsUpload` is true).

**Agent C's challenge:** Import sources include 16 logger QSOs — those use `LoggingSessionManager.markForUpload` which has explicit service checks. Agent A noted that `markForUpload` only creates for `.qrz`, `.pota`, `.lofi` — NOT hamrs — explaining why 416 hamrs records exist (432 total - 16 logger = 416 from import paths).

**Proposed fix:**
- Don't clear `needsUpload` after upload; wait for QRZ download reconciliation to confirm via `markPresent`
- Add orphan repair for QSOs in dead state (isPresent=0, needsUpload=0, no qrzLogId)

### Hypothesis B: HAMRS `supportsUpload` creates bogus records (CONFIRMED — All 3 agents)

**Confidence:** HIGH (unanimous consensus)

**Theory:** `ServiceType.hamrs.supportsUpload` returns `true` in `ServiceType.swift` (~line 28), but no upload handler exists in the sync pipeline. This creates permanent `needsUpload=1` records that can never be fulfilled.

**Evidence:**
- 416 hamrs ServicePresence records, ALL with `needsUpload=1`, none ever progressing
- `ServiceType.swift`: `case .hamrs: true` in `supportsUpload` computed property
- `SyncService+Upload.uploadToAllDestinations()` only handles `.qrz` and `.pota` — no `.hamrs` case
- Sync log shows "Found 417 QSO(s) with pending uploads" — the 417 = 416 hamrs + 1 real pending QSO

**Four independent code paths create these bogus records:**
1. `QSOProcessingActor.createNewQSOFromGroup` (lines 273-300) — iterates `ServiceType.allCases` where `supportsUpload` is true
2. `ImportService.createServicePresenceRecords` (lines 149-185) — same pattern
3. `QSOProcessingActor+OrphanRepair.repairOrphanedQSOs` — creates missing records for `supportsUpload` services
4. `LoggingSessionManager.markForUpload` — uses explicit service checks (qrz, pota, lofi), NOT `supportsUpload`, which is why logger QSOs (16) DON'T get hamrs records (432 - 16 = 416)

**All agents agreed** this is a clear bug with no contention. The fix is straightforward.

**Proposed fix:**
- Set `supportsUpload` to `false` for `.hamrs` in `ServiceType.swift`
- Add data repair step to clear all existing hamrs `needsUpload` records

### Hypothesis C: POTA trailing spaces cause rejection (DISPROVED — Agent C)

**Confidence:** LOW (disproved)

**Theory:** Trailing spaces in callsign fields (`F5MQU `, `IK1LBL `) cause POTA to silently reject ADIF uploads.

**Evidence against:**
- `ADIFParser` trims whitespace on input at line ~240 — callsigns are cleaned before storage
- The trailing spaces exist in the raw database export but would be trimmed when building ADIF for upload
- The same POTA rejection (`{"adif_files": []}`) occurs for QSOs with AND without trailing spaces
- Prior investigation (2026-02-07) confirmed the rejection pattern is location-based, not data-quality

**Agent A's support for disproval:** The 7 POTA upload attempts used correct US-AR location (post v1.25.2 fix), yet still returned empty. If trailing spaces were the cause, at least some uploads should succeed (ones without trailing spaces).

**Remaining POTA question:** The v1.29.0 uploads with correct US-AR location still returning empty `adif_files` may indicate a new issue — possibly the user's POTA account, or a different field mismatch. This needs further investigation with a test upload or POTA API debugging.

### Additional Finding: Missing primary callsign filter (Agent C)

**Confidence:** MEDIUM

`QSOProcessingActor.createNewQSOFromGroup` (lines 273-300) doesn't filter by primary callsign when creating upload markers, unlike `ImportService.createServicePresenceRecords` which does filter. This could cause QSOs from non-primary callsigns to get upload markers they shouldn't have. Not directly related to KG5VNQ's issue (all QSOs are KG5VNQ) but is a latent bug.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `ServiceType.swift` | Service type definitions | **BUG:** `hamrs.supportsUpload` returns `true` with no upload handler |
| `SyncService+Upload.swift` | Upload orchestration | `uploadToAllDestinations` only handles qrz/pota; `uploadToQRZ` clears needsUpload optimistically |
| `QSOProcessingActor.swift` | QSO creation from imports | `createNewQSOFromGroup` creates hamrs records; missing primary callsign filter |
| `ImportService.swift` | Service presence creation | Same `supportsUpload` pattern creates hamrs records |
| `LoggingSessionManager.swift` | Logger QSO creation | Uses explicit service list (qrz/pota/lofi), NOT `supportsUpload` — explains 416 vs 432 |
| `QSOProcessingActor+OrphanRepair.swift` | Orphan repair | Only catches missing records, not dead-state (isPresent=0, needsUpload=0) |
| `DashboardView+Services.swift` | Dashboard display | Shows misleading hamrs pending count to user |
| `POTAClient+Upload.swift` | POTA upload building | `parseSuccessResponse` treats empty adif_files as "queued" (correct post-v1.25.1) |
| `ADIFParser.swift` | ADIF parsing | Trims whitespace on input (~line 240), disproving trailing-space hypothesis |

## Confirmed Bugs (Prioritized)

### Bug 1: HAMRS `supportsUpload` returns `true` (HIGH priority)

**Impact:** 416 permanent phantom "pending upload" records, inflated sync counts, misleading UI.
**Root cause:** `ServiceType.hamrs.supportsUpload` is `true` but no upload handler exists.
**Fix:** Set to `false`; add data repair to clear existing records.

### Bug 2: QRZ upload clears needsUpload without confirmation (MEDIUM-HIGH priority)

**Impact:** 72 QSOs stuck in dead state, never uploaded to QRZ, no recovery path.
**Root cause:** `uploadToQRZ()` clears needsUpload after HTTP 200 without per-QSO verification.
**Fix:** Don't clear needsUpload after upload; rely on QRZ download reconciliation to `markPresent`. Add repair for stuck QSOs.

### Bug 3: Missing primary callsign filter in QSOProcessingActor (LOW priority for this user)

**Impact:** Latent bug — could create upload markers for non-primary callsigns.
**Root cause:** `createNewQSOFromGroup` doesn't filter by primary callsign.
**Fix:** Add callsign filter matching `ImportService.createServicePresenceRecords`.

## Resolution

### Fix 1: HAMRS supportsUpload set to false
**File:** `CarrierWaveCore/Sources/CarrierWaveCore/ServiceType.swift`
Changed `case .hamrs` from `true` to `false` in the `supportsUpload` computed property.

### Fix 2: Data repair for bogus HAMRS upload flags
**File:** `CarrierWave/Services/QSOProcessingActor+OrphanRepair.swift`
Added `clearBogusHamrsUploadFlags()` method. Called from `performDataRepairs()` during every sync to clean up existing HAMRS `needsUpload=true` records.

### Fix 3: QRZ upload now tracks isSubmitted
**File:** `CarrierWave/Services/SyncService+Upload.swift`
`uploadToQRZ()` now sets `isSubmitted = true` when clearing `needsUpload`, enabling future reconciliation to distinguish "uploaded and waiting for confirmation" from "never uploaded."

### Fix 4: Data repair for QRZ dead-state QSOs
**File:** `CarrierWave/Services/QSOProcessingActor+OrphanRepair.swift`
Added `repairQRZDeadStateQSOs()` method. Finds QRZ ServicePresence records in dead state (isPresent=false, needsUpload=false, not submitted, not rejected) and resets them to `needsUpload=true` for re-upload.

## Lessons Learned

- **`supportsUpload` should be the single source of truth**, and code paths should not use both `supportsUpload` iteration AND explicit service lists — one pattern or the other.
- **Never optimistically clear upload flags** — wait for confirmation from the destination service. This is the same principle as "don't mark as shipped until the carrier confirms pickup."
- **Orphan repair must cover all terminal states**, not just "missing record." The dead state (isPresent=0, needsUpload=0) is equally unrecoverable.
- **Multi-agent debate is effective** for cross-examining hypotheses — Agent C's disproval of the trailing-space theory saved time that would have been spent on a red herring.
