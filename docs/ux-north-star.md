# UX North Star

How Carrier Wave: Field stays simple while its feature surface grows. This is
the decision framework for **where new features live, how they're named, and
how users discover them**. Read it before adding any user-facing surface.

> Context: by mid-2026 the app had ~15 dashboard cards, ~80 settings screens,
> an 18-flag Experiments hub, and marquee features (Tune In, FT8, brag sheets,
> session replay) that most users never found. The fixes weren't visual —
> they were structural: organize around **user intent**, not feature
> inventory. This doc encodes those rules so the problem doesn't regrow.

## 1. The Three Jobs

Every user opens the app with one of three intents. Every screen belongs to
exactly one:

| Job | "I want to…" | Primary surfaces |
|-----|--------------|------------------|
| **Get on the air** | activate, hunt, ragchew, contest | Sessions tab (intent grid, logger, Hunter Log) |
| **What's happening now?** | spots, friends, conditions, DXpeditions | Home (On Air card), Hunter Log, Friends tab |
| **Look at what I've done** | logs, stats, awards, brag sheets | Logbook tab, Home stats cards, session detail |

When designing a new feature, name its job first. If it serves none of the
three, question the feature. If it serves two, split the surfaces.

## 2. Naming Glossary (use these words, never synonyms)

| Term | Means | Never call it |
|------|-------|---------------|
| **Home** | The dashboard/launchpad tab | Dashboard (in UI copy) |
| **Session** | One outing/operating period | Activation (except POTA-specific), Activity |
| **Logbook** | Every QSO ever, searchable | Logs, QSO list |
| **Hunter Log** | The live-spots + quick-log surface | Activity Log (legacy name in code only) |
| **Friends** | The social feed tab | Activity, Feed, Community |
| **On Air Now** | Live conditions + DXpeditions + contests | — |
| **Explore** | The feature gallery | Feature list, What's possible |

`AppTab` raw values, `@AppStorage` keys, and notification names keep their
legacy identifiers (`dashboard`, `logs`, `activity`) — those are storage, not
copy. Only display strings follow the glossary.

## 3. The Home-Slot Rule

A card earns a default slot on Home **only if it's actionable today**.
Historical stats never are.

- Default (lean) set: Getting Started, Activity grid, On Air Now, Sync
  Services — see `DashboardCardID.essentialDefaults`.
- Everything else is opt-in via Customize. New cards ship **opt-in** unless
  they displace an existing essential (argue it in the PR).
- State-driven content beats static content: active session ➝ resume card
  first; friends on air ➝ surface it; nothing happening ➝ at most one
  suggestion. `HomeHeroCard` implements this: it's pinned first,
  non-toggleable, and renders resume / start / hunt by state and role.
- Cards are glance surfaces: counts and one-line summaries on Home, full
  rows one tap deeper (the On Air card's spot summary is the pattern).

## 4. The Front Door Rule

Every marquee feature gets exactly one **Explore card**
(`Views/Explore/ExploreFeature.swift`) with a 5-second pitch and a "find it"
hint. Explore is reachable from the More tab and the Getting Started card.

- Keep the catalog curated (~10–15 cards). If everything is in Explore,
  nothing is discoverable. Adding a card? Consider removing a weaker one.
- Hidden experiments worth advertising go in the **opt-in section** with an
  inline enable toggle — users should never need to find Settings →
  Experiments to try a flagship feature.
- Prefer **contextual surfacing over launch-time tours**: offer Tune In after
  the user taps spots a few times, the brag sheet after their first upload.
  Use milestone triggers, not first-appearance triggers.

## 5. Experiment Graduation Policy

Shipping good work permanently behind a flag is a discoverability bug.

- Every new `ExperimentalFeature` case records a **target graduation review**
  (next minor release, by convention).
- Review all experiments **every release**. A beta feature that has been
  stable for 2+ releases with no open data-loss or crash issues **graduates
  by default** — the burden of proof is on keeping the flag.
- Graduation checklist: remove the enum case + all guards/badges, update the
  `swift/ios/CLAUDE.md` table, keep/promote the Explore card, announce via
  What's New with a deep link.
- Alphas that haven't progressed in 3+ releases get a decision: promote to
  beta, keep with a written reason, or delete. No zombie flags.

## 6. Persona System (`OperatorRole`)

The onboarding role step ("How do you operate?") writes `OperatorRole`
(`Models/OperatorRole.swift`, key `operatorRole`; changeable in Settings →
My Profile). Roles **bias defaults, never hide functionality**:

- `.hunter` — Sessions tab lands on Hunter Log (relabelled "Hunter Log");
  On Air card suppresses duplicate spot sections.
- `.activator` — intent grid first; future: bias session start + references.
- `.newcomer` — future: listening-first onboarding (Tune In, band plan)
  so the first win doesn't require transmitting.
- `.mixed` / unset — neutral defaults.

When adding role-aware behavior: read the key via
`@AppStorage(OperatorRole.storageKey)`, document the behavior in the
`OperatorRole` doc comment, and always leave the non-default path one tap
away (the hunter's intent grid stays behind a toolbar button — that's the
pattern).

## 7. Onboarding Is a First Win, Not Configuration

Onboarding = callsign ➝ profile ➝ role. **Nothing else.** Service
connections, community opt-in, and region live on the Getting Started card,
framed as rewards ("auto-upload confirmations"), all optional and
dismissible. Resist every urge to add a screen; add a Getting Started row
instead. Target metric: **time to first logged QSO**, not setup completion.

## 8. Flows Open Light

The session start wizard shows four essential sections; everything else is
behind "More setup options". This is the template for every flow:

- Defaults from last time beat questions ("Quick Start" templates).
- Every decision that can be made *during* the activity (equipment, parks,
  title) must be editable from the active surface — never force it up front.
- One primary button per sheet. If you need two, it's two steps.

## 9. Screen Hierarchy & Badge Budget

See "Visual Hierarchy" in [design-language.md](design-language.md):

- **One hero element per screen** (the session detail's hero/QSOs/insights
  three-tier layout is the reference implementation).
- **Max two badge types per row.** Worked-before, NEW DXCC, club, friend,
  dupe, age, experimental… pick the two highest-value for the surface and
  drop the rest behind the detail view.
- Panels are mutually exclusive — opening one closes others (see logger
  `present(_:)`).

## 10. Measure It

When touching discovery or journey surfaces, check (and extend) the
lightweight counters:

- **Time to first logged QSO** for new installs.
- **Reach** of the 5 marquee features (did the user *ever* open it?).
- Tab-switch frequency (a proxy for "I can't find it").

`PerfEvent` / `StartupProfiler` already record tab switches; prefer adding
events there over new infrastructure.

## New-Feature Checklist

Before merging any user-facing feature:

- [ ] Which of the **three jobs** does it serve? One screen, one job.
- [ ] Names follow the **glossary**; no new synonyms.
- [ ] Entry point decided deliberately — not "another dashboard card"
      (Home-slot rule) and not "somewhere in Settings".
- [ ] If marquee: **Explore card** added (and a weaker one considered for
      removal).
- [ ] If experimental: registered in `ExperimentalFeature` **with a target
      graduation review**, badge at entry points, CLAUDE.md table updated.
- [ ] If role-relevant: behavior documented in `OperatorRole`, non-default
      path stays one tap away.
- [ ] Flow opens light: essentials visible, the rest behind one expander.
- [ ] Badge budget respected (≤2 per row); one hero per screen.
- [ ] What's New entry queued for the release that ships it.
