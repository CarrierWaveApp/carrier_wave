# Investigation: Multi-Device QSO Sync Discrepancy

**Date:** 2026-02-15
**Status:** Resolved
**Outcome:** Two bugs found: (1) QRZ upload sets `isSubmitted` instead of `isPresent`, leaving 67-68 QSOs per device in limbo; (2) Logger saves callsigns with trailing whitespace, creating duplicate QSOs that fail deduplication.

## Problem Statement

User reports that QSOs are not fully syncing between iPhone and iPad via QRZ. One device has a full set, the other is missing some. QRZ itself reportedly has all QSOs.

## Raw Data Summary

### QSO Counts
- DB1 (device A, export 180415): 430 QSOs (429 non-hidden, 1 hidden)
- DB2 (device B, export 180437): 434 QSOs (430 non-hidden, 4 hidden)

### Import Source Distribution (dramatically different)
- DB1: pota=362, lofi=50, logger=15, qrz=3
- DB2: lofi=398, logger=17, pota=15, qrz=4

### ServicePresence (QRZ)
- DB1: isPresent=361, isSubmitted=67, needsUpload=1, dead-state=1
- DB2: isPresent=362, isSubmitted=68, needsUpload=0, dead-state=4

### ServicePresence (POTA)
- DB1: isPresent=446
- DB2: isPresent=423

### QSOs With QRZ Log IDs
- DB1: 361
- DB2: 362

### Non-Hidden QSOs Unique to Each Device
**DB2 only (4 QSOs):**
- `F5MQU ` (trailing space!) - Feb 4, logger
- `IK1LBL ` (trailing space!) - Feb 4, logger
- `G4TDX ` (trailing space!) - Feb 4, logger
- `K0BUF ` (trailing space!) - Feb 14, logger

**DB1 only (3 QSOs):**
- `KI7QCF ` (trailing space!) - Feb 13, logger
- `KE2MT` (no trailing space) - Feb 14, logger
- `W6JSV` (no trailing space) - Feb 15, logger

### Logging Sessions
Completely different between devices — each device has its own sessions.

## Root Causes

### Bug #1 (CRITICAL): QRZ Upload Sets Wrong State Flag

**Location:** `SyncService+Upload.swift:337`

After successful QRZ upload, code sets `isSubmitted = true` instead of `isPresent = true`:

```swift
// WRONG (line 337)
presence.needsUpload = false
presence.isSubmitted = true  // Should be isPresent = true

// CORRECT (Club Log, line 553)
presence.needsUpload = false
presence.isPresent = true
presence.lastConfirmedAt = Date()
```

**Compounding factors:**
- `reconcileQRZPresence` only examines `isPresent=true` records, skipping `isSubmitted` (`QSOProcessingActor.swift:232-237`)
- Dead-state repair explicitly excludes `isSubmitted=true` records (`QSOProcessingActor+OrphanRepair.swift:418-420`)
- `markPresent` doesn't clear `isSubmitted` flag (`QSO.swift:276-286`)
- No QRZ equivalent of POTA's comprehensive `isSubmitted` → `isPresent` reconciliation

**Impact:** 67-68 QSOs per device in limbo — uploaded to QRZ but never confirmed as present locally.

### Bug #2 (HIGH): Trailing Whitespace in Callsigns

**Location:** `LoggerView.swift:2145` (create path) and `LoggingSessionManager.swift:471`

Logger passes raw text field input without trimming. Editing flow (line 2180) correctly trims — inconsistency between create and update paths.

`deduplicationKey` in `QSO.swift:130` and `normalizedCallsign` in `QSOSnapshot.swift:136` both use `callsign.uppercased()` without trimming, so "F5MQU " and "F5MQU" produce different keys.

**Combined effect with Bug #1:** Trailing-space QSO uploaded to QRZ → QRZ strips space → download returns clean callsign → different dedup key → creates NEW QSO instead of merging → original stays permanently stuck in `isSubmitted=true`.

### Contributing Factors

- **2-minute time bucket edge case:** 3 QSOs have mismatched QRZ log IDs between devices, consistent with timestamps crossing bucket boundaries (Investigator 3)
- **Service config caching:** Config cached at session start; QSOs logged before config change miss upload flags (Investigator 5)

## Fixes Applied

### Immediate Fixes (all implemented)

1. **`SyncService+Upload.swift:337`** — Changed `isSubmitted = true` to `isPresent = true; lastConfirmedAt = Date()`
2. **`LoggingSessionManager.swift:471`** — Added `.trimmingCharacters(in: .whitespaces)` before `.uppercased()`
3. **`QSO.swift:markPresent`** — Added `isSubmitted = false` to clear stale flag

### Defense-in-Depth (all implemented)

4. **`QSO.swift:130` (deduplicationKey)** — Added `.trimmingCharacters(in: .whitespaces)` to callsign
5. **`QSOSnapshot.swift:136` (normalizedCallsign)** — Added `.trimmingCharacters(in: .whitespaces)`

### Data Repair (implemented, runs on every sync)

6. **`QSOProcessingActor+DataRepairs.swift:repairQRZSubmittedState`** — Fixes existing isSubmitted QRZ records → sets isPresent=true, isSubmitted=false
7. **`QSOProcessingActor+DataRepairs.swift:repairCallsignWhitespace`** — Trims trailing whitespace from existing callsigns and merges resulting duplicates
8. Both repairs wired into `performDataRepairs()` in `SyncService+Helpers.swift`

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `SyncService+Upload.swift:337` | QRZ upload marking | Sets `isSubmitted = true` instead of `isPresent = true` |
| `SyncService+Upload.swift:553` | Club Log upload | Correctly sets `isPresent = true` |
| `SyncService+Process.swift:511` | QRZ reconciliation | Only checks `isPresent=true`, skips `isSubmitted` |
| `QSOProcessingActor.swift:232-237` | Background reconciliation | Same — only fetches `isPresent=true` records |
| `QSOProcessingActor+OrphanRepair.swift:418` | Dead-state repair | Explicitly excludes `isSubmitted=true` |
| `QSO.swift:127-131` | Dedup key generation | No whitespace trimming |
| `QSO.swift:276-286` | markPresent | Doesn't clear isSubmitted |
| `QSOSnapshot.swift:136` | normalizedCallsign | No whitespace trimming |
| `LoggerView.swift:2145` | QSO creation | Passes raw callsignInput without trimming |
| `LoggerView.swift:2180` | QSO editing | Correctly trims (inconsistency) |
| `LoggingSessionManager.swift:471` | QSO init | Only uppercases, doesn't trim |
| `ImportService+External.swift` | QRZ import | Matches by QRZ log ID first, then dedup key |
| `DeduplicationMatcher.swift` | Duplicate detection | normalizedCallsign doesn't trim |

## Lessons Learned

1. **State management for upload services must be consistent.** QRZ used `isSubmitted` (POTA-only concept) instead of `isPresent`. When adding new upload services, copy the correct pattern (Club Log).
2. **Always trim user input at the model boundary.** The QSO initializer should defensively trim callsigns regardless of what the UI does.
3. **Deduplication keys should normalize aggressively.** Whitespace, casing, and other formatting differences should be stripped from all key components.
4. **Reconciliation must handle ALL state combinations.** The QRZ reconciliation was blind to `isSubmitted` records, and the dead-state repair explicitly excluded them.
