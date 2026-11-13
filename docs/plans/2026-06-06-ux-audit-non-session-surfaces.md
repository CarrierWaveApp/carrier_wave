# UX Audit — Non-Session Surfaces

**Date:** 2026-06-06
**Author:** Claude (Opus 4.7) for jsvana
**Status:** Handoff to fresh session

## Why this exists

We just finished a round of critical UX work on the session-start wizard and the dashboard layout. The pattern that worked:

1. **Identify operator types.** Not "users." Specific operating styles — POTA activator, hunter, contester, SOTA activator, new ham, club op, DXer/award chaser, brag-sheet user, travel/portable ham.
2. **For each, list hot path vs cold path.** What do they mutate every time? What do they touch once a quarter?
3. **Find where the UI buries the hot path under cold-path content.** That's friction.
4. **Find where the UI ships a single shape for multiple incompatible workflows.** That's worse than friction — it's a structural mismatch.
5. **Pick the highest-leverage fixes, not a shopping list.** Three good moves beat ten mediocre moves.

This document hands off the *same analytical approach* to the rest of the app. The session-start work is done — don't re-audit it. Everything else is fair game.

## Tone

Be direct. Push back on weak premises. Intellectual honesty over flattery. The user is the developer; he wants critique that helps him ship, not a list of bullet points that sound clever. When a section is fine, say so and move on. When it's bad, name the specific failure.

## What's already shipped (don't re-do)

These are recent landings — assume they're the current state, audit OTHER surfaces:

- **Lean dashboard default** — 4 cards visible (Getting Started, Activity, On Air, Sync Services); the rest are opt-in via Customize. Now has a "Show more cards" footer (`AddCardsFooter` in `DashboardView+Layout.swift`).
- **Session-start wizard rebuild** — loadouts strip, callsign hero, inline gear row, activation-first ordering when activator. Files: `SessionStartSheet*.swift`, `LoadoutEditSheet.swift`.
- **Operating-style preset** — `OperatorRole` enum in `swift/ios/CarrierWave/Models/OperatorRole.swift`. First-launch prompt on Sessions tab. Settings → Logger → Operating Style as the single canonical picker (no duplicate Picker control).
- **Quick-start from last session** — `QuickStartCard` on Sessions tab bypasses the wizard entirely. File: `SessionsIntentView+QuickStart.swift`.
- **Compact callsign hero** — collapses to a thin bar when nothing about identity/location needs attention. File: `SessionStartSheet+Hero.swift`.

If you find yourself critiquing any of the above, stop and re-read the most recent CHANGELOG entries under `[Unreleased]`.

## Operator types (carry over from session work)

Same list as the session-start audit. The leverage point shifts by surface — a hunter doesn't care about the session-start form much, but they live in the Hunter Log and the Logger view; an activator cares deeply about the Map for park finding.

| Operator | Where they live | Hot-path concerns |
|---|---|---|
| Hunter (home) | Logger, Hunter Log, On Air card | Speed of logging; fresh spot list; dupe detection |
| POTA/SOTA activator | Map (planning), Logger (running), Sessions list (uploads) | Park finding; spot self; POTA upload; ending the session cleanly |
| Contester | Logger, contest score sheet, end-session export | Exchange speed; dupe; multipliers; Cabrillo export |
| New ham | Getting Started, Settings, About Me | Onboarding clarity; permission asks; what "POTA" means |
| Club op | About Me, Sessions list (multi-op), Hunter Log (Field Day) | Club station mode; attendees; multi-op exports |
| DXer / award chaser | Stats, Awards, Needs, GridTracker, WAS | "Who do I still need?"; per-entity progress; map of worked |
| Brag-sheet poster | Brag Sheet, share card | One-tap share; visual quality |
| Travel/portable | Map, callsign prefix/suffix | Grid override; prefix/suffix; foreign callsign rules |

## Surfaces to audit (in rough leverage order)

Highest-leverage first. Each section has: entry file, the operator lens to apply, and rough questions to start with.

### 1. Logger view (the in-session surface)

**Entry:** `swift/ios/CarrierWave/Views/Logger/LoggerView.swift` plus the swarm of `LoggerView+*.swift` extensions.

This is where the user spends most of their session time. The 2-3 minutes setting up a session is a *one-time cost*; the 90 minutes running it is the *recurring cost*. If this surface is 5% better it dwarfs everything we just did.

Things to look at:
- **Field entry order.** Callsign → exchange → RST → notes? Or are fields ordered alphabetically / arbitrarily? Hunters vs run-stations want different orders.
- **Spot list integration.** Is the right thing visible at the right time? When running a frequency, the user wants their own spot front-and-center; when hunting, they want a fresh feed.
- **Mode switching cost.** How many taps to QSY from CW to SSB? From 20m to 40m? Are there inline shortcuts or do they have to go through a sheet?
- **Duplicate detection feedback.** Is the dupe warning visible during the callsign entry, or only after submit? Different speeds.
- **The keyboard accessory row.** What's there, what's missing, what's redundant? `LoggerKeyboardAccessory.swift`, `KeyboardAccessoryBuilder*.swift`.
- **iPad two-pane.** `LoggerView+Landscape.swift`. Does the split make sense for hunter vs activator? Probably the spot sidebar matters more for hunters.
- **The "more setup options" / band edit / mode edit sheets.** `LoggerView+Modifiers.swift`. Are these the right granularity?
- **Simple Logging Mode** (recently shipped) hides situational chips. Is the threshold right? Does it hide too much for someone *learning* the chips?

Specifically watch for: too many sheets stacking; banners that move the callsign field while typing; "modal-itis."

### 2. Hunter Log (ActivityLogView)

**Entry:** `swift/ios/CarrierWave/Views/Hunter/ActivityLogView.swift` (or wherever — grep `ActivityLogView`).

For hunters, this *is* the app. They don't start/stop sessions; they sit on a log all day and chase spots. The friction here directly translates to dropped contacts.

- Is there a "what's new since I looked" affordance, or does the user have to scan visually?
- How fast is the path from "saw a spot on the dashboard" to "logged the QSO in Hunter Log"?
- Setup sheet (`ActivityLogSetupSheet`) — is this a one-time cost or does it nag?
- Per-day rollover. What happens at UTC midnight?
- Multi-day chasing (e.g., DXpedition) — is there a session concept inside the log?

### 3. Map / Park search

**Entry:** `swift/ios/CarrierWave/Views/Map/ParkSearchMapView.swift`.

For activators planning their trip *and* hunters discovering activations. Dual-purpose surface — that's a structural risk worth probing.

- Layer controls (recently expanded with grid squares, TOTA tiles, US states + counties, SOTA zones, WWFF). Is the toggle UI scaling with the count, or is it a list of 10 toggles?
- Park boundaries — performance? Tap targets?
- The "start session from here" path. Does it correctly hand off to `SessionStartSheet` with the park reference pre-filled? (Yes — verified in audit, but check the SOTA + WWFF + Mission paths too.)
- Recently added overlays for boundaries — is there a story for the user who wants ALL OF THEM on at once vs ONE specific overlay?
- Search experience. Is search by name vs reference vs grid all in one field, or split?

### 4. Sessions list (SessionsView) and session detail (SessionDetailView)

**Entry:** `swift/ios/CarrierWave/Views/Sessions/SessionsView.swift` and `SessionDetailView*.swift`.

The "review past work" surface. Different operators want completely different views: contester wants Cabrillo + score; activator wants POTA upload status + park; hunter doesn't care about sessions at all (they live in Hunter Log).

- Is the list filterable by activation type? Sortable by anything other than date?
- The session detail page is rich (hero, QSOs, insights). Is the order right? For a POTA upload, the user wants upload status front-and-center; we may bury it under the hero.
- The unified row (`SessionRow.swift`) — is it doing too much, or just enough?
- Sharing flows. `SessionsView+Share.swift`. Brag sheet generation. When does the user actually share, and is the share button where they expect?
- Export flows (ADIF, Cabrillo). `SessionADIFExportSheet*.swift`. How many sheets deep?

### 5. Stats, Awards, Needs, Grid Tracker

**Entries:** `DashboardView+Stats.swift`, the various award detail views, `NeedsSnapshot.swift`.

DXer / award chaser surface. These users are obsessive — they want depth, not lean. Be careful applying the "lean" instinct here; this is the one place where MORE information may be the right answer.

- "Who do I still need?" — is this a single answer or scattered across 5 surfaces?
- Per-entity drill-down. From a stat card, can the user actually get to "show me the 12 states I haven't worked"?
- Smart Spots / Needs card — does it actually integrate with the live spot feed?
- WAS, DXCC, IOTA, POTA Awards — are these consistent in pattern, or does each have its own UI dialect?

### 6. Settings (overgrown)

**Entry:** `swift/ios/CarrierWave/Views/Settings/SettingsView.swift` plus a *very* long list of `*SettingsView.swift` siblings.

The user just shipped a "Simple Logging Mode" toggle under Appearance. That kind of micro-toggle proliferation is the smell. Question to ask: **how does a new user find a thing they vaguely remember seeing?** If the answer is "scroll the whole settings tree until they find it," the IA is broken.

- Search (`SettingsView+Search.swift`) — does it cover all settings, or just headers?
- The `LoggerDetailSettingsView` is 351 lines of toggles. Is that one screen, or should it be split?
- "Experiments" hub vs scattered experimental toggles. Single source of truth?
- "Data & Tools" vs "Sync Services" vs "Backup" vs "iCloud" — are these the right slices? Or do they overlap?
- About Me / profile editing — `AboutMeView*.swift`. How many places set the same fields (callsign, grid)?

### 7. Dashboard cards (individual)

We did the *layout* of the dashboard. Each individual card is still its own UX problem.

**Entries:** `DashboardView+Stats.swift`, `DashboardView+GridTracker.swift`, `DashboardView+BragSheet.swift`, etc.

- Each card title — does it match what's in Customize?
- "Tap for more" — is the affordance visible, or does the user have to guess?
- Stats grid — does it pivot meaningfully on iPad?
- Sync Services card — at a glance, can the user tell *what's wrong* with sync, or just "something's wrong"?

### 8. Tour / Getting Started / onboarding

**Entries:** `LoggerTourOverlay.swift`, `TourState`, `DashboardGettingStartedCard.swift`.

The new-ham journey. This is the one place where lean is the *wrong* default — the user genuinely doesn't know what's possible.

- Does the tour teach the *right* mental model (POTA, QSO, log)? Or does it teach the *app*?
- Is there a "I'm an experienced ham coming from N3FJP" path that skips the basics?
- Permission asks (location, notifications, photos, Bluetooth) — when do they fire? Are they justified at that moment?

### 9. Navigation skeleton (tabs + More)

**Entry:** wherever the root `TabView` lives (search for `TabConfiguration`).

The user just shipped tab-gating for experimental features. Now look at the *static* tab structure:

- 5 tabs? More? What's in More that should be a top-level tab? What's a top-level tab that should be in More?
- The user has Hunter Log, Sessions, Dashboard, Map, Settings — at minimum. Is "Sessions" really one tab or two (start vs review)?
- Activator vs hunter probably want different tab orders. Does anything respond to OperatorRole?

## Methodology to apply

1. **Read the entry file. Don't grep yet.** Get the shape.
2. **Pick the dominant operator for that surface.** Write it down. *"This is the hunter's view."*
3. **List that operator's hot path through the view.** Three to five steps.
4. **Walk the view and count taps / scrolls for the hot path.** Be honest.
5. **Walk the view as a *different* operator.** Where does the UI fight them?
6. **Pick the top 2-3 frictions. Skip the rest.** A long list of medium findings dilutes the high-leverage ones.
7. **For each finding: what's the smallest fix that matters?** Reordering > new feature.

## Constraints (don't violate)

These come from project conventions — read `CLAUDE.md`, `swift/CLAUDE.md`, `swift/ios/CLAUDE.md` if you haven't.

- **File length:** 500 lines per file, 300 lines per type body. Split proactively.
- **No `@Query` for QSO / ServicePresence.** Use `@State` + `FetchDescriptor` in `.task`. See `docs/PERFORMANCE.md`.
- **All logging through `RadioService.shared.addLog` or domain in-app log.** No `print`, `os_log`, `Logger`, `NSLog`.
- **SwiftLint blocks on errors, not warnings.** Hooks run on edit.
- **Update `FILE_INDEX.md`** when adding/removing files.
- **Update `CHANGELOG.md`** under `[Unreleased]`.
- **xc build** locally to verify before committing — the Xcode Cloud build catches what local SourceKit doesn't.
- **Devices:** physical device is `theseus`. `xc deploy` builds + installs + launches.

## File hooks (skip the grep tax)

These are the entry points by area. Drop these straight into Read.

| Area | File |
|---|---|
| Logger main | `swift/ios/CarrierWave/Views/Logger/LoggerView.swift` |
| Logger modifiers | `swift/ios/CarrierWave/Views/Logger/LoggerView+Modifiers.swift` |
| Logger keyboard | `swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift` |
| Logger landscape | `swift/ios/CarrierWave/Views/Logger/LoggerView+Landscape.swift` |
| Sessions list | `swift/ios/CarrierWave/Views/Sessions/SessionsView.swift` |
| Sessions intent (lobby) | `swift/ios/CarrierWave/Views/Sessions/SessionsIntentView.swift` |
| Session detail | `swift/ios/CarrierWave/Views/Sessions/SessionDetailView.swift` |
| Hunter Log | grep for `ActivityLogView` |
| Map / parks | `swift/ios/CarrierWave/Views/Map/ParkSearchMapView.swift` |
| Dashboard | `swift/ios/CarrierWave/Views/Dashboard/DashboardView.swift` |
| Settings root | `swift/ios/CarrierWave/Views/Settings/SettingsView.swift` |
| Logger settings | `swift/ios/CarrierWave/Views/Settings/LoggerDetailSettingsView.swift` |
| About Me | `swift/ios/CarrierWave/Views/Settings/AboutMeView.swift` |
| OperatorRole | `swift/ios/CarrierWave/Models/OperatorRole.swift` |
| File indexes | `swift/ios/FILE_INDEX.md`, `swift/ios/CarrierWave/Views/FILE_INDEX.md` |

## How to start a fresh session on this

Open with: *"Apply the same UX critique pattern from `docs/plans/2026-06-06-ux-audit-non-session-surfaces.md` to the [Logger view / Hunter Log / Map / Settings / etc.]. Don't try to cover everything — pick one surface and go deep."*

Do not try to audit the whole app in one session. Pick **one** surface from the priority list. Spend the budget there.

Output expectation: a critique like the one already in the user's session history for session-start — three to five paragraphs naming specific frictions, two or three concrete recommendations in priority order, ending with "want me to start on any of these?"

If the user says yes, code immediately. Don't re-explore.
