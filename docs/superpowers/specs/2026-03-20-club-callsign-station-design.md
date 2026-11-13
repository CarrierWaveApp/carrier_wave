# CAR-169: Club Callsign as Station

**Date:** 2026-03-20
**Status:** Approved
**Linear:** CAR-169

## Problem

When operating from a club station, the operator uses the club's callsign over the air but their personal callsign identifies who was at the controls. Carrier Wave currently treats these as the same value (`myCallsign`), with no way to distinguish station from operator. This prevents correct ADIF export and makes club operation awkward.

## Design

### Data Model

Add one optional field to each model:

**`LoggingSession`:**
- `stationCallsign: String?` — the club/alternate callsign used over the air (with prefix/suffix applied). Nil means the operator is the station (current behavior).

**`QSO`:**
- `stationCallsign: String?` — copied from the active session at QSO creation time.

`myCallsign` retains its current meaning: the operator's personal callsign (from settings, unmodified).

**Schema migration:** Add `stationCallsign` to the next `VersionedSchema`. Since the field is optional with nil default, this is a lightweight migration — no data transformation needed.

### Session Start UI

In `SessionStartSheet`, add a toggle in the callsign section:

- **"Operating as club station"** toggle (default off)
- When on, reveals a text field for the club callsign base (uppercased, trimmed)
- The existing prefix/suffix controls apply to the club callsign (the call used over the air). The `fullCallsign` computed property switches its base from `defaultCallsign` to the club callsign text field value.
- The operator callsign (from settings, `defaultCallsign`) is displayed as a read-only label below the club call field, labeled "Operator"
- When off, existing behavior — prefix/suffix apply to `myCallsign` as today
- Toggling off clears the club callsign text field. Toggling on clears prefix/suffix (since they likely don't apply to the club call).
- **Validation:** The "Start" button is disabled when the club station toggle is on and the club callsign field is empty.

**State flow:**
- Toggle off: `myCallsign` = prefix + `defaultCallsign` + suffix, `stationCallsign` = nil
- Toggle on: `myCallsign` = `defaultCallsign` (no prefix/suffix), `stationCallsign` = prefix + clubCallInput + suffix

**`TourSessionStartSheet`:** No changes. The onboarding tour uses a simplified session start flow — club callsign is not included in the tour.

### QSO Detail View

When a QSO has a non-nil `stationCallsign`, display it in `QSODetailView` as "Station" with the operator callsign (`myCallsign`) shown separately as "Operator". When `stationCallsign` is nil, display `myCallsign` as "My Callsign" (current behavior).

### ADIF Export

All export paths (QRZ, POTA, LoFi, ClubLog, eQSL, manual ADIF):

- `STATION_CALLSIGN` = `qso.stationCallsign ?? qso.myCallsign`
- `OPERATOR` = `qso.myCallsign`

When `stationCallsign` is nil, both fields emit `myCallsign` (preserving current behavior).

**Cabrillo export:** `CabrilloExportService` should use `session.stationCallsign ?? session.contestOperator ?? session.myCallsign` for the `CALLSIGN:` header. The `OPERATORS:` line should list `session.myCallsign` (the operator). When `stationCallsign` is nil, both lines use the same value as today.

### Upload Filtering

In `SyncService+Upload.fetchQSOsNeedingUpload`: add an unconditional skip for QSOs where `stationCallsign != nil`, **before** the existing `myCallsign` matching filter. This is necessary because club QSOs retain the operator's personal call as `myCallsign`, which would pass the existing callsign match — the `stationCallsign` guard prevents this.

Applies to all auto-upload destinations: QRZ, POTA, LoFi, ClubLog, eQSL. (LoTW is download-only in this codebase, so no upload path exists to block.)

The user can still manually export ADIF for the club's logs.

### POTA Spotting

`LoggingSessionManager+Spotting.swift`: use `session.stationCallsign ?? session.myCallsign` for:
- `postSpot(callsign:)` — the spot should show the call used over the air
- `startSpotCommentsPolling()` — poll for comments on the correct callsign
- `startSpotMonitoring()` — monitor spots for the correct callsign

### PSKReporter

`PSKReporterSenderSection`: use `session.stationCallsign ?? session.myCallsign` as the sender callsign. PSKReporter should reflect the call used over the air.

### Activities Server

`LoggingSessionManager+SessionActivity.swift`: use `session.stationCallsign ?? session.myCallsign` for the `ActivityItem.callsign` field. The shared activity should show the station call.

### Watch / Handoff

`HandoffConstants` payload: include `stationCallsign` in the serialized session data. The Watch `ActiveSessionView` should display `stationCallsign ?? myCallsign` as the active call, with the operator call shown separately if different.

### iCloud Sync

- Include `stationCallsign` in CKRecord mapping for both `LoggingSession` and `QSO`
- Add `stationCallsign` to `CloudSyncConflictResolver` field-level merge logic using newer-wins strategy (not non-nil-wins, since a user may intentionally clear the club call by toggling off)

### Statistics

No changes. Stats key off `myCallsign` (the operator), so club station QSOs still count in the user's personal stats.

### ADIF Import

Field mapping for all cases:

| ADIF Fields Present | `myCallsign` | `stationCallsign` |
|---|---|---|
| Both `STATION_CALLSIGN` and `OPERATOR` | `OPERATOR` | `STATION_CALLSIGN` (if different from `OPERATOR`) |
| Only `STATION_CALLSIGN` | `STATION_CALLSIGN` | nil (current behavior) |
| Only `OPERATOR` | `OPERATOR` | nil |
| Neither | fallback to import parameter | nil |

When `STATION_CALLSIGN` equals `OPERATOR`, set `stationCallsign` to nil (not a club operation).

## Changes Summary

| Area | Change |
|------|--------|
| `LoggingSession` model | Add `stationCallsign: String?` |
| `QSO` model | Add `stationCallsign: String?` |
| Schema migration | New `VersionedSchema` with lightweight migration |
| `SessionStartSheet` | Add toggle + club call text field; prefix/suffix applies to club call when active; disable Start when toggle on but field empty |
| `TourSessionStartSheet` | No changes (simplified onboarding flow) |
| `QSODetailView` | Show station vs operator callsigns when `stationCallsign` is set |
| `LoggingSessionManager` | Pass `stationCallsign` through to session creation and QSO logging |
| ADIF export (all paths) | `STATION_CALLSIGN` = `stationCallsign ?? myCallsign`; `OPERATOR` = `myCallsign` |
| Cabrillo export | `CALLSIGN:` uses `stationCallsign ?? contestOperator ?? myCallsign`; `OPERATORS:` lists `myCallsign` |
| `SyncService+Upload` | Unconditional skip for QSOs where `stationCallsign != nil` (before callsign match filter) |
| POTA spotting | Use `stationCallsign ?? myCallsign` for spot/poll/monitor |
| PSKReporter | Use `stationCallsign ?? myCallsign` as sender |
| Activities server | Use `stationCallsign ?? myCallsign` for activity callsign |
| Watch / Handoff | Include `stationCallsign` in payload, display appropriately |
| iCloud sync | Include in CKRecord mapping + conflict resolver (newer-wins) |
| ADIF import | Map `STATION_CALLSIGN`/`OPERATOR` to new fields per matrix |
| Stats | No changes needed |

## Out of Scope

- Station profiles (preconfigured club calls in Settings) — future enhancement
- Per-destination upload control for club sessions — rely on blanket skip
- Contest multi-op integration (existing `contestOperator` field is separate)
