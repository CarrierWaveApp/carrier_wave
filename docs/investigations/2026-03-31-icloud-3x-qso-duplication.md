# Investigation: iCloud Sync Creating 3x Copies of Every QSO

**Date:** 2026-03-31
**Status:** Resolved
**Outcome:** Two bugs found — dedup key mismatch (primary) and unconditional dirty flags after conflict resolution (amplifier). Both fixed.

## Problem Statement

Users with large libraries report that iCloud sync creates ~3x copies of every QSO, making sync impractical for large libraries. Observed when syncing between two devices that both have QSO data (e.g., imported from ADIF on both, or synced from QRZ/POTA independently).

## Root Cause 1: Dedup Key Mismatch (Primary)

### The Bug

`QSO.deduplicationKey` and `QSOFields.deduplicationKey` use **different mode normalization functions**, producing different keys for the same QSO:

| Location | Function | USB → | LSB → | AM → |
|----------|----------|-------|-------|------|
| `QSO+Dedup.swift` (model) | `canonicalNameForDedup` | **SSB** | **SSB** | **SSB** |
| `CKRecordMapper+Fields.swift` (CKRecord) | `canonicalName().uppercased()` | **USB** | **LSB** | **AM** |

`canonicalNameForDedup` normalizes all phone modes (USB, LSB, AM, FM, DV) to "SSB".
`canonicalName` only normalizes "PHONE" → "SSB", leaving specific modes as-is.

### How It Causes Duplication

When Device B receives a QSO from Device A:
1. UUID lookup fails (different UUIDs from independent imports)
2. Falls through to `mergeOrCreateQSO` dedup check
3. Compares `fields.deduplicationKey` (uses CKRecord normalization → "USB") against `existing.deduplicationKey` (uses model normalization → "SSB")
4. **Mismatch → inserts as new QSO instead of merging**
5. Both devices end up with duplicate QSOs
6. Each duplicate uploads to CloudKit with a different record name, creating more inbound copies

### Fix

Changed `CKRecordMapper+Fields.swift:132` to use `canonicalNameForDedup` instead of `canonicalName().uppercased()`.

## Root Cause 2: Unconditional Dirty Flags After Conflict Resolution (Amplifier)

### The Bug

`CloudSyncEngine+ConflictResolution.swift` sets `cloudDirtyFlag = true` unconditionally after every conflict resolution, regardless of whether the merged result differs from the server version. This violates the documented safety constraint in `icloud-sync.md`:

> "Never set `cloudDirtyFlag = true` after accepting a server version."

### How It Amplifies Duplication

1. Conflict resolved → dirty flag set → merged result re-uploaded
2. Other device receives it → potentially triggers another conflict
3. Wastes CloudKit API quota and bandwidth, especially at scale
4. With 100K QSOs, unnecessary re-uploads can overwhelm the sync pipeline

### Fix

Changed all conflict resolvers to conditionally set dirty flags:
- **QSO:** Only re-dirty when `preferRemote=true` AND OR/concat fields diverged, or when local is newer
- **ServicePresence:** Only re-dirty when union merge produced values different from server
- **LoggingSession:** Only re-dirty when local is newer or qsoCount/status diverged
- **ActivityLog:** Only re-dirty when local is newer (pure LWW)

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `CKRecordMapper+Fields.swift` | QSOFields dedup key | Uses wrong normalization function |
| `QSO+Dedup.swift` | QSO model dedup key | Uses correct `canonicalNameForDedup` |
| `ModeEquivalence.swift` | Mode normalization | Two functions with different behavior |
| `CloudSyncEngine+ConflictResolution.swift` | Conflict handling | Always sets dirty=true |
| `CloudSyncEngine+Outbound.swift` | Outbound flow | Re-collects ALL dirty after conflicts |
| `CloudSyncEngine+Inbound.swift` | Inbound flow | Dedup fallback broken by key mismatch |
| `CloudSyncEngine.swift` | Main engine | `rescheduleOrphanedDirtyRecords` amplifies |

## Lessons Learned

1. **Dedup keys must use identical normalization everywhere.** The model and the CKRecord fields struct independently implemented the same algorithm but called different functions. A shared function or compile-time guarantee would prevent this.

2. **Dirty flags after conflict resolution need justification.** The default should be "don't re-dirty" with explicit checks for when the merge produced novel data. The icloud-sync.md doc already had the right constraint but it wasn't enforced in code.

3. **Consider sqlite-level sync as a future alternative.** The current per-record CKSyncEngine approach has inherent complexity (dedup keys, conflict resolution, dirty flags). Syncing the sqlite database file directly (via SQLiteData/GRDB's CloudKit integration or a custom solution) eliminates the entire mapping layer.

## SQLiteData Migration Analysis

Updated from the February 2026 investigation (`2026-02-20-icloud-database-sync-options.md`).

### Current State (March 2026)

SQLiteData is at v1.6.1 (released 2026-03-23). 1.0 shipped September 2025. The CloudKit sync layer uses `CKSyncEngine` internally, same as our current implementation. Key improvements over our hand-rolled approach:

| Concern | Our CKSyncEngine | SQLiteData |
|---------|-------------------|------------|
| Conflict granularity | Per-record LWW | **Per-field LWW** (automatic) |
| Mapping code | ~1500 lines manual | Zero (generated from `@Table`) |
| Dedup | Manual key computation (bug-prone) | **Automatic via primary keys** |
| Dirty tracking | Manual `cloudDirtyFlag` | **Automatic via GRDB change tracking** |
| CloudKit sharing | Not implemented | **Built-in** |
| Model types | `@Model class` (reference) | `@Table struct` (value, Sendable) |

### What SQLiteData Fixes Structurally

The two bugs found today **cannot exist** in SQLiteData:
1. **Dedup key mismatch** — impossible because identity is the SQLite primary key, not a computed key
2. **Dirty flag ping-pong** — impossible because change tracking is automatic, not manual

### Known Risks

- **Conflict resolution bug #354**: Pending local edits can incorrectly win over newer server timestamps. No custom resolution API yet (Discussion #272).
- **Still hardening**: v1.5.x–1.6.x releases show active CloudKit sync bug fixes (NULL defaults, date precision, database locking). Normal for 6 months post-1.0 but indicates edge cases are still being found.
- **No large-scale production evidence**: No documented apps shipping 100K+ records through SQLiteData's sync layer.
- **CKSyncEngine ceiling still applies**: Rate limits (400 records/push, 200/fetch) are Apple constraints. Initial sync of 100K QSOs will be slow regardless of the local persistence layer.

### Migration Cost

- Rewrite 18 `@Model` classes → `@Table` structs
- Rewrite all `@Query`/`FetchDescriptor` → `@FetchAll` / explicit queries
- Rewrite all relationship traversals (implicit → explicit foreign keys)
- Run UUID primary key migration on first launch (`SyncEngine.migratePrimaryKeys`)
- Re-test all sync flows, backup/restore, service sync interactions

### Recommendation

**Ship the dedup/dirty-flag fixes now.** Monitor how sync behaves at scale. If the mapping layer continues to produce bugs, begin a gradual migration starting with QSO + ServicePresence (the models that hit all the performance limits and have the most mapping code). SQLiteData's per-field conflict resolution and automatic change tracking would eliminate our largest class of sync bugs.
