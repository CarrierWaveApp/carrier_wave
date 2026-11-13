# Investigation: CAR-245 — Edited callsign still uploaded as old to POTA

**Date:** 2026-04-26
**Status:** Root cause identified — fix design needed (POTA API constraints)
**Linear:** [CAR-245](https://linear.app/carrierwave/issue/CAR-245)
**Worktree branch:** `investigate/CAR-245-pota-callsign-edit`

## Problem Statement

User report (their first POTA activation):

> I chose not to do automatic upload to POTA.app. I edited a callsign after
> ending session. Edit worked however it still uploaded wrong callsign to POTA
> when I chose to upload.

So: (1) ended session, declined auto-upload, (2) edited a callsign in the
session, the edit appeared correctly in the app, (3) manually triggered POTA
upload, (4) the *old* callsign reached POTA.

The report is ambiguous about *which* callsign was edited:

- **Operator** call (`QSO.myCallsign` / `LoggingSession.myCallsign`) — the
  activator's own call.
- **Contact** call (`QSO.callsign`) — a station they worked.
- **Station** call (`QSO.stationCallsign`) — club/alternate over-the-air call.

Each maps to a different ADIF field and a different upload pathway, so the
likely root cause depends on which one.

## Code Map (POTA upload pipeline)

| Concern | Read site | Notes |
|---|---|---|
| ADIF `CALL` (contact) | `POTAClient+ADIF.swift:59` | `qso.callsign` — live |
| ADIF `STATION_CALLSIGN` | `POTAClient+ADIF.swift:89` | `qso.stationCallsign ?? qso.myCallsign ?? activatorCallsign` |
| ADIF `OPERATOR` | `POTAClient+ADIF.swift:94` | `qso.myCallsign ?? activatorCallsign` |
| Form field `callsign` (POTA's "activator") | `POTAClient+Upload.swift:51` | `parkQSOs.first(where: { !$0.myCallsign.isEmpty })?.myCallsign` |
| Filename (`<call>@<park>-<date>.adi`) | `POTAClient+Upload.swift:219` | Same — first non-empty `myCallsign` |
| ADIF header `activator` | `POTAClient+ADIF.swift:32` | `qsos.first?.myCallsign` |

The QSO model (`packages/CarrierWaveData/.../Models/QSO.swift`) is a SwiftData
`@Model` class. `callsign`, `myCallsign`, and `stationCallsign` are direct
persistent properties — edits propagate live to anyone holding a reference.

## Edit pathways

| Edit UI | What it writes | Scope |
|---|---|---|
| `QSOEditSheet+Save.swift:39, 48, 49` | `qso.callsign`, `qso.myCallsign`, `qso.stationCallsign` | One QSO |
| `SessionMetadataEditSheet` → `SessionDetailView+QSOs.swift:308-310` | `session.myCallsign` + every QSO's `myCallsign` (via predicate fetch) | Whole session |
| `ActivationMetadataEditSheet` → `SessionsView+Actions.swift:449-460` and `POTAActivationsView+Helpers.swift:9-21` | `session.myCallsign` + every QSO's `myCallsign` | Whole session |
| `LoggerView+EditSheets.swift:237` (in-session quick edit) | `qso.callsign` | One QSO |

**Important asymmetry:** The session-level edit sheets only update
`myCallsign`. They do **not** touch `qso.stationCallsign`. The QSO-level edit
sheet updates both.

## Hypotheses

### H1: User edited operator call via session sheet, but `stationCallsign` overrode it on upload

**Evidence for:**
- `QSOEditSheet+Save.swift:48-49` writes both `myCallsign` and
  `stationCallsign`, but `SessionMetadataEditSheet` (used from session detail
  → "Edit Session") only writes `myCallsign`.
- ADIF generation in `POTAClient+ADIF.swift:89` prefers `qso.stationCallsign`
  over `qso.myCallsign` for the `STATION_CALLSIGN` field. POTA credits
  activations against `STATION_CALLSIGN`, so if it's stale the activation goes
  to the old call even though the form `callsign` and OPERATOR fields are
  correct.

**Evidence against:**
- `qso.stationCallsign` is only populated when the session was started in
  *club station* mode (`SessionStartSheet.swift:323-335`,
  `LoggingSessionManager+QSOManagement.swift:68`). A first-time solo POTA
  activator almost certainly did not check that.
- For solo sessions, `qso.stationCallsign` is `nil`, so the
  `?? qso.myCallsign` fallback would give the corrected value.

**Tested:** Static read only.
**Result:** Plausible but unlikely for a *first-time* activator.

### H2: User edited a contact callsign on a single QSO, dedup against POTA's previously-accepted bust

**Evidence for:**
- `SyncService+UploadPOTA.swift:24` — `filterAlreadyUploadedPOTAQSOs` uses
  `potaRemoteQSOMap` keyed on the OLD callsign. If the user re-uploaded after
  editing, the corrected QSO might still match the old upload's key and
  silently get skipped (or, if duplicate detection fails, the OLD record on
  POTA's side would not be touched).

**Evidence against:**
- User says this was their *first* activation, so there should be no prior
  upload to dedup against.
- The bug here would be a *missing* upload, not a *wrong* one.

**Tested:** No.
**Result:** Doesn't fit the symptom shape.

### H3: Background auto-upload ran despite user "declining" auto-upload at end of session

**Evidence for:**
- The auto-upload toggle (`potaUploadPromptDisabled` /
  `pota auto-upload`) is a separate setting from the per-session "Upload
  Now / Later" prompt. "Declining" the prompt does not disable auto-upload.
- `SyncService.uploadToPOTA(qsos:)` runs as part of the periodic sync. It's
  driven off `needsUpload(to: .pota)` — which is true after end-of-session
  regardless of what the user clicked on the prompt.
- If the periodic sync fires between session-end and the user's edit, POTA
  receives the OLD call. The user then edits, taps "Upload now" — but
  `markParkQSOsSubmitted` already cleared `needsUpload`, so the explicit
  upload is a no-op (no new request goes out). The user *thinks* their edit
  uploaded; in reality POTA already has the bad copy and the new call never
  left the device.

**Evidence against:**
- Need to verify auto-upload behaviour vs. the end-of-session prompt — they
  may share a flag I haven't fully traced.

**Tested:** No.
**Result:** **Strongest candidate so far.** Matches every part of the symptom
description: edit appears local, no error on "upload", POTA shows old call.

### H4: Stale snapshot somewhere in the upload chain

Ruled out by reading: every callsign read in the upload path goes through a
live SwiftData `@Model` reference. `POTAActivation` is a struct with a
`callsign` field captured at grouping time, but that field is only used for
`id`/grouping — the upload itself reads from `activation.qsos`, which holds
live QSO refs. ADIF is regenerated per upload (`POTAUploadAttempt.adifContent`
is stored *after* generation, never read back as input).

## Files Examined

| File | Finding |
|---|---|
| `swift/ios/CarrierWave/Services/POTAClient+Upload.swift` | Form `callsign` field uses first non-empty `myCallsign` from the live array |
| `swift/ios/CarrierWave/Services/POTAClient+ADIF.swift` | STATION_CALLSIGN prefers `qso.stationCallsign` over `myCallsign` |
| `swift/ios/CarrierWave/Services/SyncService+UploadPOTA.swift` | `uploadToPOTA(qsos:)` is called by periodic sync, not gated by the end-of-session prompt |
| `swift/ios/CarrierWave/Views/Logs/QSOEditSheet+Save.swift` | Per-QSO edit updates both `myCallsign` and `stationCallsign` |
| `swift/ios/CarrierWave/Views/Sessions/SessionDetailView+QSOs.swift` (`applyEditResult`) | Session-level edit only updates `myCallsign`, never `stationCallsign` |
| `swift/ios/CarrierWave/Views/Sessions/SessionsView+Actions.swift` (`applySessionEdits`) | Same omission |
| `swift/ios/CarrierWave/Views/POTAActivations/POTAActivationsView+Helpers.swift` | Same omission |
| `swift/ios/CarrierWave/Services/LoggingSessionManager+QSOManagement.swift:68` | `stationCallsign` is captured at QSO-creation time from session |
| `swift/ios/CarrierWave/Views/Logger/SessionStartSheet.swift:323-335` | `stationCallsign` only set in club-station mode |
| `swift/ios/CarrierWave/Models/POTAActivation.swift` | Struct, but `qsos` array holds live `@Model` refs — not a stale snapshot |

## User Clarifications (Discord + follow-up, 2026-04-26)

W2ELS confirmed via Discord:
1. Edited a **hunter's** (contact) callsign — `qso.callsign`, not their own.
2. **A few hours** between end-of-activation and the edit-then-upload sequence.
3. Sync service enabled, POTA automatic upload off. Don't know whether a sync
   ran between the two events.
4. **Tapped Save in the QSO edit sheet** (confirmed via follow-up question).
5. **Did NOT initiate a first upload at end of session.** This contradicts my
   earlier reading of "I cliked auto update" in the Discord transcript. They
   declined the prompt, hours passed, then they edited and uploaded. The
   "wrong call uploaded" is from the first real upload they did, not a no-op
   re-upload.

This invalidates the earlier H3 hypothesis (no prior upload means
`submittedToPark` was never set, so `pendingQSOs` includes the edited QSO and
ADIF is regenerated fresh from `qso.callsign`). The bug must be upstream of
the upload — the data layer is putting the wrong value into ADIF.

## Agent-Team Synthesis (3 parallel investigations, 2026-04-26)

Three subagents investigated independent layers. Convergent findings:

### Agent 3 — Upload data path: CLEAN

Verdict: "no plausible root cause found in this layer (high confidence)."

`QSO` is `nonisolated public final class @Model`. `POTAClient` is `@MainActor`.
`QSOEditSheet` and the upload share the view-tree's `@Environment(\.modelContext)`.
Every read of `qso.callsign` from tap to network bytes goes through the same
`@Model` reference on the same `@MainActor` ModelContext — no snapshot, no
boundary crossing, no `rawADIF` read, `POTAUploadAttempt.adifContent` is
write-only.

The bug is in the data layer between edit and upload.

### Agent 2 — Duplicate QSOs from QRZ/LoTW download path: STRONG CANDIDATE

`QSOProcessingActor.fetchExistingQSOKeys` (`swift/ios/CarrierWave/Services/QSOProcessingActor.swift:155-199`)
keys existing QSOs by `deduplicationKey` from
`swift/packages/CarrierWaveData/Sources/CarrierWaveData/Models/QSO+Dedup.swift`,
which **includes the contact callsign**:

```
"\(callsign.uppercased())|\(band.uppercased())|\(canonicalMode)|\(rounded_120s_timestamp)"
```

Sequence that reproduces the bug:

1. User logs QSO with callsign `K1ABC`. If QRZ auto-upload is on (separate
   from POTA setting), the QSO gets pushed to QRZ.
2. User edits to `K1ABZ` (saved). Local QSO now has dedup key `K1ABZ|...`.
3. Periodic QRZ/LoTW download runs. Pulls back the original under `K1ABC`.
   `processDownloadedQSOsAsync` → `QSOProcessingActor.swift:122-130`
   computes incoming dedup key `K1ABC|...`.
4. `existingByKey` (built from current local data, including the edit) does
   NOT have that key.
5. `createNewQSOFromGroup` (`QSOProcessingActor.swift:128`) inserts a fresh
   QSO with `callsign = "K1ABC"` and a NEW UUID, plus
   `ServicePresence.needsUpload(to: .pota)` if POTA is configured
   (`QSOProcessingActor+Merge.swift:121-153`).
6. Sessions list fetches by `loggingSessionId` only
   (`SessionsView+Actions.swift:23-31`) — `loggingSessionId` survives the
   merge (`pickOptional`), so the duplicate joins the same session.
7. `POTAActivation.groupQSOs` (`POTAActivation.swift:258-296`) does NOT dedup
   per-instance; both QSOs land in `activation.qsos`.
8. `SyncService+UploadPOTA.uploadToPOTA` and
   `filterAlreadyUploadedPOTAQSOs` (`SyncService+POTAUploadDedup.swift:65-74`)
   do NOT dedup the local input array. Both ADIF records get sent. POTA
   accepts both; user sees the original `K1ABC` on POTA's site.

Why the user only saw one row in the session detail:
`SessionDetailView+QSOs.fetchSessionQSOs` (`SessionDetailView+QSOs.swift:344-380`)
DOES dedup by `deduplicationKey` — but the two QSOs have *different* keys
(callsigns differ), so dedup keeps both. So either (a) the duplicate was
created *after* the user looked at the detail view, or (b) the duplicate has
`loggingSessionId == nil` and is invisible to the by-session fetch but still
uploadable via the orphan-activation path (`loadOrphanActivations`
`SessionsView+Actions.swift:53-76`).

### Agent 1 — iCloud journal race: SECONDARY CANDIDATE

Two sub-paths in `swift/packages/CarrierWaveData/Sources/CarrierWaveData/CloudSync/`:

- **Path C — outbound dirty-flag clobber:** `CloudSyncJournalEngine+Outbound.clearDirtyFlagsForJournal`
  (`CloudSyncJournalEngine+Outbound.swift:195-218`) clears `cloudDirtyFlag` *by
  ID* after the CKRecord save returns, regardless of whether the user edited
  between the snapshot and the confirmation. The 500ms debounce in
  `CloudSyncService.swift:335` makes it very easy to fire when the edit
  follows shortly after creation. Net effect: the edit's `cloudDirtyFlag = true`
  gets wiped, the edit never goes up to iCloud, any later re-bootstrap or
  sibling device returns the old callsign.
- **Path A — sibling/restore overwrite:** `currentDeviceId()` is a per-install
  UUID. After uninstall/reinstall, the device's own old journal entries
  appear "remote" and can win the merge if `payload.timestamp >
  local.modifiedAt` (which it will be — payload timestamps are set at
  outbound batch construction, not data-change time, so a sibling that fell
  behind always wins).

Less likely than the QSOProcessingActor path for a first-time activator on a
single device, but still real and worth fixing.

## Confirmed Root Cause

**Most likely:** Candidate 2 (QSOProcessingActor duplicate insert via QRZ/LoTW
download). Fits the "few hours" gap, "sync service enabled" detail, and the
user-visible single-row view in session detail (if the duplicate has
`loggingSessionId == nil`).

The CloudSync race is a real secondary bug worth fixing in the same patch —
either could fire under different user setups.

## Fix Plan (this branch)

| # | Fix | File(s) | Priority |
|---|---|---|---|
| 1 | Change `fetchExistingQSOKeys` dedup key to NOT include contact callsign — use `(myCallsign, band, mode, rounded_timestamp)` plus permanent service IDs (`qrzLogId`, `lotwConfirmedDate`) when available | `swift/ios/CarrierWave/Services/QSOProcessingActor.swift` lines 155-199 + `QSO+Dedup.swift` (add a separate `mergeKey`) | Primary fix |
| 2 | Defence-in-depth: dedup QSO instances inside `filterQSOsForPark` before generating ADIF | `swift/ios/CarrierWave/Services/POTAClient+Upload.swift` lines 93-102 | Backstop |
| 3 | Skip `cloudDirtyFlag` clear when local `modifiedAt` is newer than payload's | `swift/packages/CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncJournalEngine+Outbound.swift` lines 195-218 | Secondary fix |
| 4 | Log a warning in `createNewQSOFromGroup` when there's a logically-similar local QSO with a different contact callsign — diagnostic for catching the bug in the wild | `swift/ios/CarrierWave/Services/QSOProcessingActor+Merge.swift` lines 121-153 | Observability |

## Next Steps

1. Implement fixes 1-4 in this worktree.
2. Run `xc quality` to verify build/lint/tests pass.
3. Add a unit test that reproduces the QSOProcessingActor duplicate-insert
   path: pre-existing edited QSO + downloaded QSO with old callsign for the
   same logical contact → should merge into the existing local QSO, not
   insert a new one.
4. Comment on CAR-245 with the root cause and fix summary.

## Earlier (Now-Invalidated) Hypothesis Notes

The "first-upload-then-no-op-re-upload" hypothesis (formerly H3 above) was
based on misreading the Discord transcript's "I cliked auto update so did
not export" as "I clicked the upload button." Follow-up clarification
established no first upload happened. Leaving the H3 trace above for
historical context, but it is NOT the actual cause.
