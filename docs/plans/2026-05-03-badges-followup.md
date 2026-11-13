# Profile Badge System — Follow-Up Roadmap

> Companion to the badge system shipped on `claude/badge-system-design-fE1h0`. **Phases 1–5 of this roadmap have now been implemented on the same branch** — see "Implementation status" below. Remaining items kept here as a punch-list for the long tail.

## Implementation status (as of 2026-05-03)

- **Phase 1 — auto badges:** `server/src/achievements/` engine with inline + batch dispatchers; evaluators for firsts/counts/coverage/streaks/anniversary/quirky; `report_activity` hooks the inline path; `aggregators::achievements` runs the batch sweep every 15 min over recently-active callsigns; `POST /v1/admin/achievements/backfill` runs a one-shot full backfill.
- **Phase 2 — signal badges:** `POST /v1/users/me/achievements/signal` validates `award_method = 'signal'` before granting; `cross-platform` is awarded automatically once both an iOS-flavored signal and `sweep-user` arrive within 7 days. iOS `AchievementSignalService` is idempotent (UserDefaults-cached). Wired emit sites: `watch-operator` (PhoneSessionDelegate.startSessionRequest), `pebble-pioneer` (PebbleBridgeService POST /v1/qso), `home-screen` (CarrierWaveApp `WidgetCenter.currentConfigurations` on .active scene). Deferred: `sweep-user` (no auth client on Sweep yet), `swl` (separate app), `rbn-spotter` (iOS doesn't submit RBN spots).
- **Phase 3 — profile polish:** AboutMe Badges row shows "N earned"; AchievementShowcaseContainer surfaces an unlock toast for newly-earned badges (UserDefaults-tracked seen-set per callsign).
- **Phase 4 — admin tooling:** New `server/web/src/pages/AchievementsAdmin.tsx` with catalog viewer, award/revoke per callsign, batch-award (paste callsigns), and one-click backfill. Wired into Layout nav.
- **Phase 5 — macOS:** Sweep gets a "Badges" Window scene (auto-listed in macOS Window menu), backed by `AchievementsFetcher` (URLSession against the public read-only endpoints).

## Original phase plan (kept for reference and remaining items)


## Status (as of 2026-05-03)

**Shipped on the merge branch:**

- Server: `migrations/034_achievements.sql` adds `achievements` (catalog) + `user_achievements` (awards). ~30 seeded badges across `creator / community / activity / ecosystem / streak / quirky` categories. Pre-awarded `creator` to W6JY and N9HO.
- Server: `models/achievement.rs`, `db/achievements.rs`, `handlers/achievements.rs`. Routes: public `GET /v1/achievements`, `GET /v1/users/:callsign/achievements`; admin `POST /v1/admin/achievements/:id/award`, `DELETE /v1/admin/achievements/:id/award/:callsign`.
- Swift: `CarrierWaveData/Models/Achievement.swift` — `Achievement`, `UserAchievement`, response envelopes (Codable + Sendable, with `unknown`-fallback enums for forward compatibility).
- iOS: `Views/Achievements/AchievementBadgeView.swift` (single tile with locked + secret state), `AchievementShowcaseView.swift` (category grid), `AchievementShowcaseContainer.swift` (loader with refreshable + parallel catalog/award fetch).
- iOS: `Services/ActivitiesClient+Achievements.swift` — `fetchAchievementCatalog`, `fetchUserAchievements`.
- iOS: `AboutMeView` has an "Achievements" section with a Badges row pushing the showcase.

**Catalog declares but doesn't grant yet:** all `award_method = 'auto'` and `'signal'` badges. The system has the slot for them; nothing fills it.

---

## Phase 1 — Make `auto` badges actually award

The single biggest gap. Today the server has the table and the catalog declares 20+ auto badges, but no code grants them. Without this, only the manually-curated badges (creator, beta tester, contributor, etc.) ever appear.

### 1.1 Pick the trigger architecture

Two viable approaches:

- **(a) Inline in activity ingest.** When `POST /v1/activities` accepts a new activity, run a per-user evaluator synchronously and award any newly-met criteria.
- **(b) Periodic batch job.** Background task sweeps users with recent activity and recomputes their progress.

Recommend **(a) for first-of-kind events** (first-qso, first-cw, first-ft8, first-ssb, eyeball) and **(b) for cumulative thresholds** (qso-100, dxcc-100, was, streak-7). Inline keeps "first" badges instant; batch avoids hot-path scans of the activities table for the cumulative ones.

### 1.2 Evaluator catalog

New module `server/src/achievements/` with one file per evaluator family:

- `firsts.rs` — first-qso / first-cw / first-ssb / first-ft8 / mode-polyglot. Inline path. Reads the new activity + a count predicate against `activities` filtered by callsign + mode.
- `counts.rs` — qso-100 / qso-1000 / qso-10000 / dxcc-10 / dxcc-100 / grid-50. Batch path. SQL aggregates against `activities`.
- `coverage.rs` — was, wac, all-hf. Batch path. Joins activity to a state/continent/band derivation.
- `streaks.rs` — streak-7 / streak-30 / streak-365 / anniversary / field-day. Batch path. Day-bucket window query.
- `propagation.rs` — solar-storm. Inline path against the activity timestamp + the existing space-weather feed.
- `quirky.rs` — night-owl, qrp-dx, eyeball. Mostly inline.

Each evaluator implements:

```rust
trait AchievementEvaluator {
    fn ids(&self) -> &[&'static str];
    async fn evaluate(&self, ctx: &EvalCtx) -> Result<Vec<Award>, AppError>;
}
```

`EvalCtx` carries `callsign`, optional `triggering_activity`, and a `&PgPool`. `Award { achievement_id, evidence: serde_json::Value }`. Caller writes via existing `db::achievements::award_achievement`.

### 1.3 Wire into activity ingest

`server/src/handlers/activity_feed.rs::report_activity` (or wherever the inline write lives — the file index points at `activity_feed.rs`). After the row is committed:

```rust
let inline = AchievementEngine::inline_evaluators();
for ev in inline {
    if let Ok(awards) = ev.evaluate(&ctx).await {
        for award in awards { /* db::award_achievement(...) */ }
    }
}
```

Failures must NOT fail the activity write. Log + swallow.

### 1.4 Batch sweeper

New `server/src/aggregators/achievements.rs`. Spawned from `aggregators/mod.rs` behind `config.achievement_evaluator_enabled`. Sweep cadence: every 15 min, only callsigns with activity in the last 24h. Pull from `activities.callsign DISTINCT WHERE created_at > now() - interval '1 day'`.

For each callsign, run all batch evaluators and call `award_achievement` (which is idempotent thanks to the unique constraint).

### 1.5 Backfill migration

Once evaluators land, add `migrations/035_backfill_achievements.sql` (or a one-off binary in `server/src/bin/`) that runs all batch evaluators against every callsign in `activities` so existing users wake up with their earned badges. Mark which one — migration is simpler if it's pure SQL where possible.

### 1.6 Tests

- Unit per evaluator: synthetic `EvalCtx`, expected `Vec<Award>`.
- Integration: insert N activities, hit the activity endpoint, assert `user_achievements` rows.

---

## Phase 2 — `signal` badges (ecosystem usage)

Catalog declares: `sweep-user`, `watch-operator`, `home-screen`, `pebble-pioneer`, `swl`, `rbn-spotter`. None are awardable yet.

### 2.1 Server endpoint

```
POST /v1/users/me/achievements/signal
Authorization: Bearer <device-token>
{ "id": "watch-operator", "evidence": { "watchOS": "11.2", ... } }
```

Handler in `server/src/handlers/achievements.rs::report_signal`. Uses `AuthContext` (already extracts callsign from device token). Validates `id` exists, `award_method == 'signal'`, then calls `db::award_achievement`.

Reject signals for non-signal achievements with `400 VALIDATION_ERROR` so a compromised client can't claim `creator`.

### 2.2 Client signal dispatcher

Swift: new `AchievementSignalService` (`@MainActor` actor under `swift/ios/CarrierWave/Services/`). API:

```swift
func reportSignal(_ id: AchievementSignalID) async
```

Idempotent on the client side: keep a `Set<String>` in `UserDefaults` of already-reported signals so we don't re-POST every launch. Failures are best-effort — never block the user surface.

### 2.3 Signal emit sites (one per badge)

| Badge | Trigger site |
|-------|--------------|
| `sweep-user` | macOS app reports first successful CloudKit sync from a different platform — easier: iOS detects when AboutMe sees a `LoggingSession.devicePlatform == "macOS"` row arrive via CloudSync. Or simpler: macOS posts on first launch. |
| `watch-operator` | watchOS extension on first QSO logged via WCSession. iOS receives the message, posts the signal. |
| `home-screen` | Widget extension can't make network calls; instead, iOS app polls `WidgetCenter.shared.getCurrentConfigurations` on launch — if any timeline is active, post. |
| `pebble-pioneer` | `PebbleBridgeService` on successful handshake. |
| `swl` | CW SWL server reports back to activities server when a recording session ends — or piggyback on iOS app, which connects to the SWL endpoint. |
| `rbn-spotter` | `RBNClient` on first spot acceptance. |

Each site is a one-line `await AchievementSignalService.shared.reportSignal(.watchOperator)`.

### 2.4 Cross-platform-week (`cross-platform`)

Currently catalog says `award_method = 'auto'`. Implementation: when a signal arrives, check if there's a complementary signal in the last 7 days from the other platform — if so, also award `cross-platform`. Or move it to a batch evaluator that scans `user_achievements.evidence` for both `sweep-user` and any iOS marker.

---

## Phase 3 — Profile surface polish

### 3.1 Earned-only summary on AboutMe

Today the row says "Badges" with no count. Fetch `fetchUserAchievements` on `AboutMeView.onAppear`, show "12 earned" trailing text. Store in a `@State` on the view.

### 3.2 Unlock animation + What's New entry

When the showcase loader detects newly-earned badges (compare to the persisted `Set<String>` of last-seen IDs in `UserDefaults`), animate the new tiles with a confetti / scale pulse on first appearance. Persist the seen set to suppress repeats.

Optionally surface a one-time toast "You earned: Centurion" the next time the user opens the app — wire into `WhatsNewService`-style cadence but keyed to award rather than version.

### 3.3 Share card

Add a "Share" button on `AchievementBadgeView` for earned badges. Render a `ShareLink`-compatible `Image` via `ImageRenderer` showing the badge icon, name, callsign, awarded date, and "Carrier Wave" branding. Reuse the brag-sheet renderer pattern at `swift/ios/CarrierWave/Services/BragSheet/`.

### 3.4 Public profile page

Currently the showcase only shows the user's own badges. Add a public lookup: from any callsign chip in the app (friends list, club roster, spots feed), tap → push `AchievementShowcaseContainer(callsign: otherCallsign)`. Already supported by the loader — just needs entry-point wiring.

---

## Phase 4 — Admin tooling

### 4.1 Admin web UI

`server/web/src/pages/AchievementsAdmin.tsx`. List catalog, filter by category, search awards by callsign, manually award/revoke. Hits `POST /v1/admin/achievements/:id/award` and `DELETE /v1/admin/achievements/:id/award/:callsign`.

### 4.2 Beta-tester batch import

CSV import in the admin UI: "paste callsigns, award `beta-tester` to each". Calls the award endpoint in a loop server-side via a new batch endpoint `POST /v1/admin/achievements/:id/award/batch { callsigns: [...] }`.

### 4.3 Catalog editing

Catalog is currently seed-only. If we want non-engineering badge additions (e.g. event-specific commemorative badges), add admin CRUD on `achievements`. Risk: live edits to a row that's been awarded should freeze most fields except `description` / `icon_name` / `accent_hex`. Build with `IF NOT EXISTS` semantics for the safe fields only.

---

## Phase 5 — macOS (Sweep)

CW Sweep can show the same showcase. Steps:

- The model is already in `CarrierWaveData` (cross-platform).
- Port `AchievementBadgeView` / `AchievementShowcaseView` / `AchievementShowcaseContainer` to a place that compiles for macOS — likely move them into `CarrierWaveData` once we confirm they're SwiftUI-friendly there, or duplicate into `swift/macos/CWSweep/Views/`.
- macOS `AboutWindow` or settings sheet gets a Badges section.

---

## Naming clean-up (someday)

The existing challenge `badges` table and the new `achievements` table represent different concepts but share the user-facing word "Badge". Long-term consider:

- Renaming `badges` table → `challenge_badges` for clarity, OR
- Renaming user-facing "Badges" label → "Achievements" everywhere in Swift.

Not urgent — current Swift label is "Badges" and it works.

---

## Open questions

- **Award notifications.** Server currently has no push-notification fan-out. Should new awards send a push? If yes, hook into the existing notification infra (haven't audited yet — check `server/src/handlers/` for any APNs code).
- **Privacy.** Awards are currently public via `GET /v1/users/:callsign/achievements`. Confirm this is desired for secret/quirky badges (e.g. "Night Owl" reveals you operate at 03:00 local). Probably fine — they're opt-in by behavior — but worth a deliberate yes.
- **Tier upgrades.** Today qso-100 and qso-1000 are separate rows. When a user crosses 1000, both are awarded and both show. That's intentional, but the showcase could collapse same-family tiers into a single tile that levels up. Defer until we see how it looks with real data.
