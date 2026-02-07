# Social Activities Plan

> **Status:** Draft — awaiting review
> **Created:** 2026-02-07

## Overview

Expand the activity feed from a passive log of personal achievements into a social experience where friends' activities flow through the system — activations, streaks, interesting contacts, milestones, and more. Add reactions, richer detail views, and new event types that make the feed feel alive.

This plan covers both client (iOS) and server (activities-server) changes, organized into phases that can be shipped independently.

---

## Phase 1: New Event Types

Add event types that make the feed more interesting, especially for friends.

### 1a. "Worked a Friend" Event

**Type:** `workedFriend`

When you log a QSO with someone who is an accepted friend, both sides see a mutual activity in their feed.

**Detection (client):**
- In `ActivityDetector.detectActivities(for:)`, after processing a QSO batch, cross-reference each QSO's callsign against accepted `Friendship` records.
- If a match is found, create a `DetectedActivity` of type `.workedFriend` with the friend's callsign, band, mode, and timestamp.
- Report to server as normal via `ActivityReporter`.

**Server behavior:**
- When the server receives a `workedFriend` activity, it checks if both sides reported it (within a time window). If so, it creates a single merged "mutual QSO" event visible to both users' feeds. If only one side reports, it still shows as a one-sided "worked a friend" event.
- New endpoint or logic in existing `POST /v1/activities`: detect `workedFriend` type, look for matching counter-report within ±5 minutes, merge into mutual event.

**Display:**
- Mutual: "AJ7CM and W1ABC made a QSO on 20m FT8" (globe icon, teal color)
- One-sided: "AJ7CM worked friend W1ABC on 20m FT8"

**Files to change:**
- `ActivityType.swift` — add `workedFriend` case
- `ActivityDetector.swift` — add friend-matching in `detectActivities`
- `ActivityDetector+Detection.swift` — new `detectWorkedFriend` method
- `ActivityItemRow.swift` — add display for new type
- `ActivityDetails` — no new fields needed (uses `workedCallsign`, `band`, `mode`)
- Server: activity creation logic, feed query to merge mutual events

### 1b. Milestone Events

**Type:** `milestone`

Surface round-number milestones for cumulative stats: 100/250/500/1000 DXCC entities, total QSOs, unique grids, parks activated, etc.

**Detection (client):**
- New method `detectMilestones(qsos:historical:)` in `ActivityDetector+Detection.swift`.
- After processing a QSO batch, check if cumulative totals crossed a milestone threshold.
- Milestone thresholds: `[10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]`
- Categories: total QSOs, DXCC entities, unique grids, unique parks, unique modes, unique bands.

**New fields in `ActivityDetails`:**
- `milestoneCategory: String?` — e.g. "dxcc", "totalQSOs", "grids", "parks"
- `milestoneValue: Int?` — the milestone number reached

**Display:**
- "AJ7CM reached 100 DXCC entities!" (star icon, gold color)
- "W1ABC logged their 1,000th QSO!" (star icon, gold color)

**Files to change:**
- `ActivityType.swift` — add `milestone` case
- `ActivityDetails` — add `milestoneCategory`, `milestoneValue` fields + CodingKeys
- `ActivityDetector+Detection.swift` — new `detectMilestones` method
- `HistoricalData` — add `totalQSOCount`, `uniqueGridCount`, `uniqueParkCount`
- `ActivityItemRow.swift` — add display for new type

### 1c. Same Park / Same Summit Coincidence

**Type:** `sameParkActivation`

When a friend activates the same park you've activated (or vice versa), surface it.

**Detection (server-side preferred):**
- This is hard to detect client-side because you'd need to know what parks your friends activated.
- Server approach: when a `potaActivation` activity is reported, the server checks if any friends have a `potaActivation` for the same `parkReference` in the last 30 days.
- If so, the server generates a `sameParkActivation` event for both users' feeds.

**Display:**
- "You and W1ABC both activated US-0189 (Acadia NP) this month!" (leaf + person icon, green)

**New fields in `ActivityDetails`:**
- `friendCallsign: String?` — the friend who also activated

**Files to change:**
- `ActivityType.swift` — add `sameParkActivation` case
- `ActivityDetails` — add `friendCallsign` field
- `ActivityItemRow.swift` — add display
- Server: post-processing hook on `potaActivation` events

---

## Phase 2: Reactions

Let users react to friends' activities with lightweight emoji reactions.

### Data Model

**New SwiftData model: `ActivityReaction`**
```swift
@Model
final class ActivityReaction {
    var id: UUID
    var activityItemId: UUID  // The activity being reacted to
    var callsign: String      // Who reacted
    var emoji: String         // The reaction emoji
    var timestamp: Date
    var isSynced: Bool        // Whether reported to server
}
```

### Reaction Set

Keep it small and ham-radio-flavored:
- 👍 (thumbs up / "FB")
- 🎉 (congrats)  
- 🔥 (fire / impressive)
- 📡 (radio / nice signal)

### Client Flow

1. Long-press or tap a reaction button row below each `ActivityItemRow`.
2. Create local `ActivityReaction` record.
3. Report to server: `POST /v1/activities/{id}/reactions` with `{ emoji: "🎉" }`.
4. When syncing feed, pull reactions: each `FeedItemDTO` includes a `reactions` array with counts per emoji.

### Server API

- `POST /v1/activities/{id}/reactions` — add reaction (auth required)
- `DELETE /v1/activities/{id}/reactions` — remove own reaction
- Feed response includes `reactions: [{ emoji: "🎉", count: 3, userReacted: true }]`

### Display

- Below each `ActivityItemRow`, show a compact row of reaction pills: `🎉 3  🔥 1`
- Own reactions highlighted with accent color background.
- Tap to toggle own reaction on/off.

### Files to change

- New model: `CarrierWave/Models/ActivityReaction.swift`
- `ActivityItemRow.swift` — add reaction row below content
- New view: `ReactionBar.swift` — horizontal pill row
- `ActivitiesClient+Activities.swift` — add reaction endpoints
- `FeedItemDTO` — add `reactions` field
- `ActivityFeedSyncService` — store/update reaction counts
- `ActivityItem` — add `reactionsData: Data` field for cached reaction counts
- Server: reactions table, endpoints, feed aggregation

---

## Phase 3: Richer Detail Views

Make tapping a feed item show a rich detail view instead of just the row.

### Activity Detail Sheet

New view: `ActivityDetailSheet.swift`

When tapping an `ActivityItemRow`, present a sheet with:

**For POTA/SOTA activations:**
- Park/summit name and reference
- QSO count, bands used, modes used
- Mini map showing park location
- If own activation: link to full activation view
- If friend's: show their callsign profile link

**For DX contacts / worked-a-friend:**
- Great circle path on a mini map (reuse `ActivationMapHelpers` geodesic logic)
- Band, mode, RST
- Distance in km/mi

**For streaks:**
- Current streak length
- Activity grid visualization (reuse `ActivityGridView` pattern)
- If friend's: their streak vs yours comparison

**For milestones:**
- The milestone reached and total count
- A "progress bar" showing how far to the next milestone
- Historical progression if data available

**For personal bests:**
- The new record value
- Previous record value if known
- Context (band/mode/callsign for distance records)

### Files to change

- New view: `CarrierWave/Views/Activity/ActivityDetailSheet.swift`
- `ActivityItemRow.swift` — make row tappable, present sheet
- `ActivityView.swift` — add sheet state management
- Reuse: `ActivationMapHelpers.swift`, `ActivityGridView.swift`

---

## Phase 4: Feed Improvements

### 4a. Infinite Scroll / Pagination

Currently the feed fetches 200 items. Add cursor-based pagination.

- `ActivityView` tracks a `nextCursor` from the feed response.
- When scrolling near the bottom, fetch more with `before: nextCursor`.
- Append to `allActivityItems` instead of replacing.

### 4b. "Interesting Contacts" Surfacing

Add a concept of "interesting" to contacts beyond just DX distance. Criteria:

- **Rare DXCC entity** — entity with <50 QSOs in your log
- **New band-entity combo** — first time working that DXCC on that band
- **New mode-entity combo** — first time working that DXCC on that mode
- **Long distance on unexpected band** — e.g., 6m DX beyond 3000km
- **First QSO of the day** after a streak is at risk (streak preservation)

**New type:** `interestingContact`

This would be a lower-priority feed item (maybe shown with less prominence or in a separate "highlights" section) that surfaces contacts worth noting but not quite "milestone" level.

### 4c. Friend Activity Digest / Summary

Periodically (daily or weekly), generate a local summary:
- "Your friends made 47 QSOs this week"
- "W1ABC activated 3 new parks"  
- "K2XYZ hit a 30-day streak"

This could appear as a special card at the top of the feed, or as a push notification (Phase 5).

---

## Phase 5: Push Notifications (Future)

Deferred until user demand warrants the infrastructure investment.

- Friend request received/accepted
- Friend achieved a notable milestone
- Reactions on your activities
- Weekly digest

Requires: APNs integration, server-side push infrastructure, notification preferences UI.

---

## Server Changes Summary

| Phase | Endpoint/Change | Description |
|-------|----------------|-------------|
| 1a | `POST /v1/activities` | Handle `workedFriend` type, merge mutual events |
| 1c | Post-processing hook | Detect same-park coincidences after `potaActivation` |
| 2 | `POST /v1/activities/{id}/reactions` | Add reaction |
| 2 | `DELETE /v1/activities/{id}/reactions` | Remove reaction |
| 2 | Feed response update | Include reaction counts per activity |
| 3 | Feed response update | Include richer details (bands used, etc.) for activations |
| 4a | `GET /v1/feed` | Already supports cursor pagination (verify `before` param) |

---

## Client File Changes Summary

### New Files
| File | Phase | Purpose |
|------|-------|---------|
| `Models/ActivityReaction.swift` | 2 | Reaction data model |
| `Views/Activity/ReactionBar.swift` | 2 | Reaction pill row component |
| `Views/Activity/ActivityDetailSheet.swift` | 3 | Rich detail view for feed items |

### Modified Files
| File | Phase | Change |
|------|-------|--------|
| `Models/ActivityType.swift` | 1 | Add `workedFriend`, `milestone`, `sameParkActivation`, `interestingContact` |
| `Models/ActivityItem.swift` | 2 | Add `reactionsData` for cached counts |
| `Models/ActivityItem.swift` (ActivityDetails) | 1 | Add `milestoneCategory`, `milestoneValue`, `friendCallsign` |
| `Services/ActivityDetector.swift` | 1 | Add friend-matching, milestone detection orchestration |
| `Services/ActivityDetector+Detection.swift` | 1 | New detection methods |
| `Views/Activity/ActivityItemRow.swift` | 1,2,3 | New event displays, reactions, tappability |
| `Views/Activity/ActivityView.swift` | 3,4 | Detail sheet state, pagination |
| `Views/Activity/FilterBar.swift` | 4 | Possible new filter chips |
| `Services/ActivitiesClient+Activities.swift` | 2 | Reaction endpoints, updated DTOs |
| `Services/ActivityFeedSyncService.swift` | 2 | Handle reaction data in feed sync |

---

## Implementation Order Recommendation

1. **Phase 1a: Worked a Friend** — highest social value, immediately makes the feed feel connected
2. **Phase 1b: Milestones** — easy client-only work, makes the feed richer
3. **Phase 3: Detail Views** — makes existing events more engaging before adding more
4. **Phase 2: Reactions** — needs server work, but transforms passive feed into interactive
5. **Phase 1c: Same Park** — needs server-side detection, lower priority
6. **Phase 4: Feed Improvements** — polish and depth
7. **Phase 5: Push** — future

---

## Open Questions

1. **Reaction persistence:** Should reactions be stored locally only (optimistic) or require server confirmation? Recommend optimistic with background sync.
2. **Milestone spam:** How to avoid flooding the feed when bulk-importing QSOs triggers many milestones at once? Recommend: only emit the highest milestone per category in a single detection pass.
3. **Privacy:** Should users be able to control which activity types are shared? Recommend: add a "Sharing preferences" section in Activities settings with toggles per category.
4. **Worked-a-friend dedup window:** ±5 minutes for merging mutual events seems reasonable but may need tuning for slow-mode QSOs.
5. **Detail view vs navigation:** Sheet vs full navigation push for activity details? Recommend sheet for consistency with existing patterns.
