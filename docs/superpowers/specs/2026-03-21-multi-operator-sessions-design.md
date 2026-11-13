# Multi-Operator Session Support

**Date:** 2026-03-21
**Status:** Draft
**Pattern:** Ham2K PoLo style — operator list at session level, split on export

## Overview

Allow users to create multi-operator logging sessions where multiple operators share a single log. On export, the log is split into per-operator ADIF files. On import, multi-op ADIF files are filtered to the user's callsign.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Operator tracking granularity | Session-level | Matches PoLo pattern; all operators credited for all QSOs |
| Import filtering | Match user's configured callsign | Automatic, no user intervention needed |
| Sync behavior | Upload under primary user's account | Keeps sync simple; other operators export manually |
| Operator list UI | Session start + session settings | Accessible but not intrusive |
| Export options | All operators + single operator picker | Flexible for different workflows |

## 1. Data Model

### LoggingSession Changes

Add one stored property:

```swift
var operatorCallsignsRawValue: String  // JSON-encoded [String], default "[]"
```

Computed wrapper (following existing `programsRawValue`/`programs` pattern):

```swift
var operatorCallsigns: [String]  // get/set over raw value
var isMultiOp: Bool              // operatorCallsigns.count > 1
```

The `operatorCallsigns` array stores **only additional operators** beyond the session owner. The session's `myCallsign` is always implicitly the primary operator. An empty array means single-op. `isMultiOp` checks `!operatorCallsigns.isEmpty`.

The computed setter must set `cloudDirtyFlag = true` to trigger iCloud sync when the operator list changes.

**No QSO model changes.** No new models. No migration beyond the additive column.

### iCloud Sync

The new field is a `String` column on an already-synced entity. Syncs automatically via the existing CKSyncEngine setup. No new entity types, sync logic, or conflict resolution changes. The `cloudDirtyFlag` is set by the computed setter to ensure edits propagate.

## 2. Import Behavior

### Prerequisites

The current `ADIFParser` collapses `OPERATOR` and `STATION_CALLSIGN` into a single `myCallsign` field on `ADIFRecord`. To support multi-op import:

1. **Add `operator` field to `ADIFRecord`** — preserve the ADIF `OPERATOR` value separately
2. **Add `stationCallsign` field to `ADIFRecord`** — preserve the ADIF `STATION_CALLSIGN` value separately
3. **Update `ImportService.createQSO`** — populate `QSO.stationCallsign` from the record's `stationCallsign` field

### Filtering Logic

When importing ADIF files:

1. **If the file contains `OPERATOR` or `STATION_CALLSIGN` fields with values differing from the user's callsign:** activate multi-op filtering — import only QSOs where either field matches the user's configured callsign (case-insensitive, ignoring portable suffixes like `/P`, `/4`)
2. **If the file has no `OPERATOR`/`STATION_CALLSIGN` fields, or all values match the user's callsign:** import all QSOs as today (no filtering). This preserves backward compatibility for all existing single-op ADIF import workflows.
3. Store `STATION_CALLSIGN` → `QSO.stationCallsign`
4. Store `OPERATOR` → `QSO.myCallsign`

### Callsign Matching

Matching is case-insensitive and strips portable suffixes before comparison (e.g., `K1ABC/P` matches configured callsign `K1ABC`).

## 3. Session Creation & Editing

### Session Start Screen

Add an optional "Operators" field below existing callsign fields:
- Comma-separated callsigns or chip-style input
- User's own callsign is always implicitly included (not stored in the array)

### Session Settings Sheet

Same operators field, editable at any time during the session. Changes apply to session metadata only — the operator list represents the final intended set of operators for export.

### Validation

- Callsigns uppercased and trimmed automatically
- Duplicates silently removed
- User's own callsign silently removed if entered (it's implicit)
- Empty input = single-op session

### Visual Indicator

When a session has additional operators, show a badge/subtitle on the active session header (e.g., "2 ops").

## 4. ADIF Export

### Semantics

All operators at a shared station are credited equally for all QSOs. This matches POTA multi-op rules where each operator at an activation receives credit for the full log. Each per-operator file represents that operator's complete activation record.

### Per-Operator File Generation

Each exported file is a complete copy of the session's QSOs with:
- `STATION_CALLSIGN` set to that operator's callsign
- `OPERATOR` set to that operator's callsign
- All other fields identical across files

The export service needs a new method returning `[(filename: String, content: String)]` for multi-op sessions, alongside the existing single-file export.

### Export UI

- **Single-op session:** Existing export behavior, no changes
- **Multi-op session:** Export sheet with two options:
  - **"Export All Operators"** — generates a zip archive containing one ADIF file per operator
  - **"Export for [callsign]..."** — list of individual operators, each generates a single ADIF file via standard share sheet

### File Naming

`{title}-{callsign}.adi` where `{title}` is the session's `customTitle` if set, otherwise `{date}` (e.g., `2026-03-21`). Examples: `POTA-K-1234-K1ABC.adi`, `2026-03-21-W2XYZ.adi`.

### Sync Behavior

Auto-sync uploads the full log under the primary user's account as normal. QSOs are synced with the session owner's `myCallsign` — other operators' callsigns never appear in auto-synced uploads. Per-operator export is for manually sharing with other operators.

## 5. Scope Exclusions

- No per-QSO operator tracking (session-level only)
- No multi-device networked logging (single device per session)
- No automatic upload to other operators' accounts
- No operator-specific statistics views (future enhancement)
- Mid-session operator list changes are not versioned — the list at export time is what's used
