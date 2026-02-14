# Investigation: Social Activity Gaps — End-to-End Analysis

**Date:** 2026-02-14
**Status:** Resolved
**Outcome:** Identified critical gap where live-logged QSOs never trigger activity detection or upload, plus feed sync only happening on manual refresh. Proposed and implemented a social data model informed by a three-persona debate.

## Problem Statement

User reports:
1. Friends not seeing friend requests
2. Activity from friend N9HO (who is accepted) not appearing in feed
3. Social activity feels "random" — sometimes things show up, sometimes they don't

## Current Architecture (As-Is)

### Activity Upload Trigger Points

Activity detection and upload to `POST /v1/activities` happens ONLY through `SyncService.processActivities(newQSOs:)`, which is called from:

| Trigger | File | Line | Description |
|---------|------|------|-------------|
| QRZ download | `SyncService.swift` | 102 | After QSOs created from QRZ fetch |
| POTA download | `SyncService.swift` | 164 | After QSOs created from POTA fetch |
| LoFi download | `SyncService.swift` | 233 | After QSOs created from LoFi fetch |
| LoTW download | `SyncService.swift` | 307 | After QSOs created from LoTW fetch |
| HAMRS download | `SyncService.swift` | 344 | After QSOs created from HAMRS fetch |
| ADIF import | `SyncService.swift` | 381 | After QSOs created from external ADIF file import |
| Orphan repair | `SyncService+Helpers.swift` | 54 | After creating QSOs from orphan repair |

### What's NOT a trigger (the gap):

**Live logging via `LoggingSessionManager`** — when a user logs a QSO in real-time during an activation, `LoggingSessionManager.logQSO()` creates the QSO record but NEVER calls `processActivities()`. This means:

- A live POTA activation with 20 QSOs generates zero activity items
- Working a friend live generates no "Worked Friend" activity
- A new band/mode/DXCC contact logged live is invisible to the social feed
- The activity only appears *if and when* the user syncs with an external service and those QSOs come back through the sync flow (often hours or days later, if ever)

### Feed Sync Behavior

The activity feed (`GET /v1/feed`) is fetched ONLY:
1. On manual refresh (pull-to-refresh on Activity tab) — `ActivityView.refresh()`
2. NOT on tab appearance, NOT on a timer, NOT on any background trigger

The friends list is synced (`GET /v1/friends` + `GET /v1/friends/requests/pending`) in two places:
1. On `.task` of `ActivityView` (first appear)
2. On manual refresh

### The `ActivityReporter` Flow

```
SyncService receives newQSOs from sync
  └→ processActivities(newQSOs:)
       ├→ ActivityDetector.detectActivities(for:)    # Locally analyze QSOs
       ├→ ActivityDetector.createActivityItems(from:) # Save to local SwiftData
       └→ ActivityReporter.reportActivities(_, sourceURL:)  # POST to server
            └→ For each detected activity:
                 └→ ActivitiesClient.reportActivity()  # POST /v1/activities
```

The reporter loops through each detected activity **sequentially** using `for activity in activities`. Each one is `await`ed. If one fails, it `catch`es and continues. This is already non-blocking to the UI since `processActivities` is called with `await` in an async context, but it IS blocking to the sync flow — sync waits for all activity reports to finish before proceeding.

---

## Three-Persona Debate

### Persona 1: Engagement Expert (Mia)

> The current system is fundamentally broken for engagement. The #1 most important social moment in amateur radio is **the live QSO itself** — when you work a friend, hit a new DXCC, or complete an activation. We generate zero social signal at that moment.
>
> The activity feed should feel alive. Right now it's dead unless someone happens to sync. Here's what I'd want:
>
> 1. **Real-time activity generation on QSO log** — the moment you log a QSO, detect activities immediately
> 2. **"On air now" presence** — show when friends are actively operating (session started)
> 3. **Activation progress** — share "N9HO is at 7/10 QSOs for US-1234" live
> 4. **Reactions/congrats** — let friends react to achievements (streak, new DXCC)
> 5. **Push notifications** — "Your friend N9HO just worked you!" or "N9HO completed an activation"
> 6. **Auto-refresh feed** — poll every 30-60 seconds when the Activity tab is visible
>
> The friend request issue is likely a sync timing problem — user sends request, friend opens app, but friends list hasn't synced. We need the friend request state to refresh on tab appear AND have push notification for new requests.

### Persona 2: Responsible Data Usage Expert (Raj)

> I appreciate the enthusiasm, but let me push back on several points from a privacy and data-minimization standpoint:
>
> 1. **"On air now" presence is sensitive.** Broadcasting your real-time location (grid square) and operating status to a server creates a surveillance vector. Amateur radio already has QRZ.com address lookup — we shouldn't add real-time tracking on top. This should be **strictly opt-in with a per-session toggle**, not a default.
>
> 2. **Activation progress sharing** leaks operational patterns. I'm ok with sharing *completed* activations but not in-progress ones. Someone could use live progress data to identify when a ham is away from home (operating at a park). Share after completion.
>
> 3. **Reactions are fine** — low privacy impact, high social value.
>
> 4. **What we upload should be aggregated, not raw QSOs.** The server should never receive individual QSO records — only aggregate events: "new DXCC", "completed activation (N QSOs)", "streak milestone". The current `ReportActivityDetails` already follows this pattern, which is good. Never send the other station's full callsign in a way that creates a contact graph — oh wait, we already do for `workedCallsign` in DX contacts and worked-friend events. That's a third-party data concern.
>
> 5. **Data we send today:**
>    - `workedCallsign` for DX contacts — this publishes the other station's callsign to our server without their consent
>    - `workedCallsign` for worked-friend events — acceptable since both are users
>    - Band, mode, distance — fine, aggregate operational data
>    - Park references — fine, public POTA data
>
> 6. **Push notifications** require APNs device tokens on our server — additional PII. But the engagement benefit is high enough to justify it with proper consent.
>
> **My recommendation:** Keep the aggregate-event model. Add live detection at QSO-log time but only upload events that don't expose third-party PII without consent. `workedCallsign` for DX contacts should be replaced with anonymized data (e.g., just the DXCC entity and distance).

### Persona 3: Developer (Sam)

> Let me ground this in what's actually feasible given the codebase:
>
> **The core fix is straightforward.** `LoggingSessionManager.logQSO()` needs to trigger `ActivityDetector.detectActivities()` + `ActivityReporter.reportActivities()`. The challenge is doing this without blocking QSO logging.
>
> Here's how I'd structure it:
>
> **Fix 1: Live QSO activity detection (the critical bug)**
> After `LoggingSessionManager` creates a QSO, fire off activity detection in a detached Task. The QSO is already saved to SwiftData — the activity detection is supplementary and MUST NOT block the logger returning to ready state.
>
> ```swift
> // In LoggingSessionManager.logQSO(), after modelContext.save():
> Task.detached { [qso, container] in
>     await ActivityPipeline.process(qsos: [qso], container: container)
> }
> ```
>
> **Fix 2: Feed auto-refresh**
> Add a timer in `ActivityView` that polls `GET /v1/feed` every 60 seconds while the tab is visible. Use `.task` with a `while !Task.isCancelled` loop — SwiftUI will cancel it on disappear.
>
> **Fix 3: Friend sync on tab appear**
> This already happens in `.task` on `ActivityView`. But it runs friends sync and feed sync in the wrong order — friends sync THEN feed shows up. The friend requests banner uses `@Query` which updates automatically. The issue might be server-side (friend request not created on the server). We should add a pull-to-refresh on the FriendsListView too.
>
> **On architecture concerns:**
> - `ActivityDetector` is `@MainActor` and does a `FetchDescriptor<QSO>()` with NO fetchLimit when loading historical data. This is a full table scan that will freeze the UI for users with thousands of QSOs. We need to either move this to a background actor or add fetchLimits/optimizations.
> - `ActivityReporter` is also `@MainActor` — should be a regular actor since it just does network calls.
> - The sequential `for activity in activities` upload pattern in `ActivityReporter` is fine for small batches but should use `TaskGroup` for parallelism if we start generating more events.
>
> **On Raj's privacy points:**
> I agree about `workedCallsign` for DX contacts. We can strip it from the upload payload and only include it in the local `ActivityItem` for the user's own display. The server doesn't need it — it can show "Worked a station in Japan (8,200 km)" instead of "Worked JA1XYZ".
>
> **On Mia's "on air now":**
> This would require a WebSocket or periodic heartbeat endpoint. It's a significant server-side addition. I'd defer this to a future release and focus on fixing what's broken first.

### Consensus

After debate, the three personas agree on:

1. **P0 (Fix now):** Live QSO activity detection — `LoggingSessionManager` must trigger detection async
2. **P0 (Fix now):** Feed auto-refresh when Activity tab is visible
3. **P1 (Fix now):** Strip `workedCallsign` from DX contact uploads (keep locally)
4. **P1 (Fix now):** Move `ActivityDetector` historical data loading off main thread
5. **P2 (Next release):** "On air now" presence with opt-in toggle
6. **P2 (Next release):** Push notifications for friend requests and friend activity
7. **P3 (Future):** Reactions on activity items

---

## Proposed Social Data Model

### Interaction Points (Where Activity Gets Generated)

| Interaction Point | Trigger | Activity Types | Upload? | Async? |
|-------------------|---------|---------------|---------|--------|
| **Live QSO logged** | `LoggingSessionManager.logQSO()` | All types (DXCC, band, mode, DX, friend, activation, streak) | Yes | `Task.detached` — non-blocking |
| **Sync download creates QSOs** | `SyncService.processActivities()` | All types | Yes | Already async in sync flow |
| **Challenge progress** | `ChallengeProgressEngine.evaluateQSO()` | `challengeTierUnlock`, `challengeCompletion` | Yes | Already async |
| **Session end** | `LoggingSessionManager.endSession()` | `potaActivation`, `sotaActivation` (summary) | Yes | `Task.detached` — non-blocking |
| **Friend request sent/received** | `FriendsSyncService` | (Not an ActivityType — uses Friendship model) | Server-side | N/A |
| **Feed refresh** | Tab appear + 60s timer | (Download only) | No (read-only) | `.task` with cancellation |
| **Friends sync** | Tab appear + manual refresh | (Download only) | No (read-only) | Already async |

### Data Flow Diagram

```
                    ┌─────────────────────────────────────────────────┐
                    │                  APP (Client)                    │
                    │                                                  │
   Logger ─── logQSO() ──→ SwiftData ──→ Task.detached {             │
                    │                      ActivityDetector.detect()   │
                    │                      ActivityDetector.save()     │
                    │                      ActivityReporter.report() ──┼──→ POST /v1/activities
                    │                    }                             │
                    │                                                  │
   SyncService ─── processActivities() ─→ Same pipeline above ───────┼──→ POST /v1/activities
                    │                                                  │
   ActivityView ── .task / timer ─────────────────────────────────────┼──→ GET /v1/feed
                    │                    ↓                             │
                    │              ActivityFeedSyncService             │
                    │              updateLocalActivities()             │
                    │                    ↓                             │
                    │              SwiftData (ActivityItem)            │
                    │                    ↓                             │
                    │              ActivityItemRow display             │
                    └─────────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────────┐
                    │                  SERVER                          │
                    │                                                  │
                    │  POST /v1/activities ──→ Store activity          │
                    │                          Fan out to friends      │
                    │                                                  │
                    │  GET /v1/feed ──→ Return activities from         │
                    │                   friends + clubs                │
                    │                                                  │
                    │  GET /v1/friends ──→ Return friend list          │
                    │  POST /v1/friends/requests ──→ Create request    │
                    │  GET /v1/friends/requests/pending ──→ Pending    │
                    └─────────────────────────────────────────────────┘
```

### Upload Payload (What We Send to Server)

```json
{
  "type": "potaActivation",
  "timestamp": "2026-02-14T15:30:00Z",
  "details": {
    "parkReference": "US-1234",
    "parkName": "Yellowstone NP",
    "qsoCount": 15,
    "band": "20m",
    "mode": "CW"
  }
}
```

**Privacy rules for uploads:**
- `workedCallsign` included ONLY for `workedFriend` type (both parties are users)
- `workedCallsign` STRIPPED from `dxContact` uploads (replaced with entity/distance only)
- No raw QSO data ever sent
- No location/grid data sent (only derived distance)

### Async Contract (Non-Blocking Guarantee)

All activity detection and upload MUST satisfy:

1. **QSO logging returns immediately** — activity pipeline runs in `Task.detached`
2. **Network failures are silently logged** — never surface to user, never retry
3. **Historical data loading uses background ModelContext** — not the main thread context
4. **Feed refresh uses cooperative cancellation** — cancelled on tab disappear

## Root Cause of Reported Issues

1. **"Not seeing friend requests"** — Friend sync only runs on ActivityView `.task` (first appear). If the user opens the Friends list directly or the Activity tab was already loaded, pending requests won't refresh. Fix: sync friends on FriendsListView appear.

2. **"Not seeing N9HO activity"** — N9HO's activities only appear in the feed if:
   - N9HO has the Activities server auth token (registered)
   - N9HO's app triggered activity detection (only happens on sync, not live logging)
   - The user manually refreshed the Activity tab to pull the feed

   Any break in this chain means silence.

3. **"Activity feels random"** — Because detection only fires on sync events (which happen at unpredictable times), and feed fetch only happens on manual refresh, the feed appears to update randomly.

## Resolution

Implementing fixes P0 and P1 from the consensus:
1. Add activity detection to `LoggingSessionManager.logQSO()` via `Task.detached`
2. Add auto-refresh timer for feed when Activity tab is visible
3. Strip `workedCallsign` from DX contact server uploads
4. Move historical data loading to background actor for activity detection

## Files Modified

| File | Change |
|------|--------|
| `LoggingSessionManager.swift` | Add async activity detection after QSO save |
| `ActivityView.swift` | Add periodic feed refresh timer |
| `ActivityReporter.swift` | Strip workedCallsign from DX uploads |
| `ActivityDetector+Detection.swift` | Add fetchLimit to historical data query |
