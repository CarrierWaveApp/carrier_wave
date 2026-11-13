# Dashboard Simplification: Design Options

**Date:** 2026-03-08
**Status:** Proposal — seeking user feedback
**Author:** Claude (research + synthesis), jsvana (direction)

---

## Problem Statement

The Carrier Wave dashboard has grown to **5 collapsible sections with 15 cards**. While each card is individually useful, the aggregate experience is overwhelming:

- New users see a wall of information with no guidance on what matters
- Power users scroll past cards they don't care about to find the ones they do
- The customize sheet (show/hide toggles) helps but doesn't address ordering or defaults
- The tab bar is hard-capped at 4 + More, pushing features into a hard-to-discover overflow

This doc proposes a hybrid approach that addresses all of these issues.

---

## Research Summary

We researched how 15+ apps handle this problem across fitness (Apple Health, Garmin, Strava), finance (Robinhood, Coinbase), aviation (ForeFlight, Garmin Pilot), astronomy (SkySafari), and ham radio (Ham2K PoLo, HAMRS, N1MM, Log4OM, HamLog). Key findings:

### What works for power-user apps
- **Apple Health's "Summary + Browse" model** — curated favorites at top, browse catalog for everything else. Scales indefinitely as features are added.
- **ForeFlight's customizable tab bar** — users reorder tabs, Most recently used overflow item gets a "dynamic tab" slot. More menu opens as a side panel, not a full-screen push.
- **SkySafari's "Tonight" panel** — auto-curated view of what's relevant *right now*. Zero configuration needed.
- **Role-based presets** (Garmin Connect) — ship sensible defaults per user archetype, then let users customize from there.

### What doesn't work
- Kitchen-sink flat menus (features get buried)
- Custom UI paradigms that ignore iOS conventions (steeper learning curve)
- Forcing all users through the same interface regardless of use case
- More than two levels of progressive disclosure (users get lost)

### Apple guidance
- **3-5 tabs on iPhone** is the hard recommendation. More triggers the "More" anti-pattern.
- **iOS 18 `sidebarAdaptable`** is the modern solution — show 4-5 tabs on iPhone, full sidebar on iPad with unlimited sections.
- **WWDC22 explicitly warns against "Home" tabs** that try to summarize everything — they "create a dissociation between understanding content and how to act on it."

---

## Proposed Design: Summary + Browse + Customizable Tabs

A hybrid of Apple Health's Summary/Browse model, ForeFlight's tab customization, and SkySafari's contextual intelligence.

### The Three Layers

#### 1. Smart Highlights (auto-curated, top of dashboard)

Contextual cards that appear and disappear based on what's relevant *right now*. No user configuration needed. Maximum 2-3 shown at once, most relevant first.

| Highlight | Trigger | Example |
|-----------|---------|---------|
| Award Progress | Within 5 of completing an award | "3 states from WAS! Need: WY, ND, VT" |
| Band Conditions | Conditions are notably good/bad | "20m is open to EU right now!" |
| Social Activity | A friend is spotted on air | "W1AW spotted at K-1234 (Shenandoah NP)" |
| Milestone | User crosses a round number | "You hit 100 unique parks!" |
| Streak Alert | Active streak + no QSO today yet | "12-day streak! Make a QSO today" |
| Sync Attention | Upload failed or items pending | "12 QSOs pending upload to QRZ" |

**Behavior:**
- Always-on (not opt-in) — this is the dashboard's "intelligence"
- Each highlight has a dismiss gesture (swipe or X) to snooze for 24h
- Highlights are tappable — they deep-link to the relevant detail view
- When nothing is notable, the section simply doesn't appear

#### 2. Pinned Cards (user-curated, main dashboard area)

The user's chosen favorite cards, reorderable. These are the existing dashboard cards (Activity Grid, Conditions, Friends On Air, etc.) but only the ones the user explicitly pins.

**Edit mode** (tap "Edit" in nav bar):
- Two sections: **Pinned** (with drag handles and minus buttons) and **Available** (with plus buttons)
- Drag to reorder pinned cards
- Tap + to pin, tap - to unpin
- Changes are live (no save button needed)

**Default state** for new users: set by the chosen preset (see below). If no preset chosen, ship a sensible default of ~5 cards: Statistics, Conditions, Streaks, Sync Services, and one social card.

**"+ Add Card" button** at the bottom of the dashboard — opens Edit mode directly. Provides a clear affordance that more cards exist.

#### 3. More Tab (overflow + tools + settings)

The More tab becomes the organizational hub for everything not on the dashboard or tab bar:

```
HIDDEN TABS
  Activity Feed
  [any other tabs the user hid]

TOOLS
  Callsign Lookup
  Contests
  DXpeditions

SETTINGS
  Settings
  Customize Tabs
  Dashboard Presets
  About
```

**Key change from current:** Tools like Callsign Lookup, Contests, and DXpeditions work better as standalone screens than as dashboard cards. They can still be pinned to the dashboard *if the user wants*, but their primary home is in the More tab's Tools section.

### Presets

One-tap configurations that set both dashboard pins AND tab bar simultaneously. Offered at first launch and accessible anytime from More > Dashboard Presets.

#### Casual Operator
- **Dashboard pins:** QSO Statistics, Streaks, Conditions, Sync Services (4 cards)
- **Tab bar:** Home, Sessions, Logs, Map
- **For:** Weekend operators, ragchewers, people who log occasionally

#### POTA Activator
- **Dashboard pins:** Activity Grid, POTA Awards, Friends On Air, Conditions, Streaks, Sync Services (6 cards)
- **Tab bar:** Home, Sessions, Logs, Activity
- **For:** Park activators, chasers, portable operators

#### DXer / Contester
- **Dashboard pins:** QSO Statistics, WAS Progress, Brag Sheet, Conditions, DXpeditions, Contests, Equipment (7 cards)
- **Tab bar:** Home, Sessions, Logs, Map
- **For:** Award chasers, DXers, contest operators

Presets are a starting point — the user can customize freely after applying one. Applying a preset doesn't delete any data; it only changes which cards are pinned and which tabs are visible.

### iPad: Sidebar Adaptable

Adopt iOS 18's `TabView(.sidebarAdaptable)`:

- **iPhone (compact):** Standard bottom tab bar with 4 tabs + More
- **iPad (regular):** Full sidebar with all sections — no More tab needed
  - Fixed section: Home, Sessions, Logs, Map
  - Social section: Activity
  - Tools section: Callsign Lookup, Contests, DXpeditions
  - Settings section: Settings, About
- Users can customize which sidebar items appear in the tab bar (iOS 18 built-in)
- System handles the compact/regular transition automatically

---

## Migration from Current Design

### What stays the same
- All 15 existing cards still exist and are available
- Collapsible sections concept carries over (available cards are grouped by section in Edit mode)
- Tab bar still has Home, Sessions, Logs, Map, More as defaults
- Customize sheet concept evolves into the new Edit mode

### What changes
- Dashboard default goes from "all cards visible" to "preset-based subset visible"
- Show/hide toggles become pin/unpin with reordering
- Smart Highlights section is new (added above pinned cards)
- Tools (Lookup, Contests, DXpeditions) get a dedicated More section
- First-launch flow asks user to pick a preset (or skip for default)

### Migration path for existing users
- Existing hidden-cards preferences map directly to "unpinned" state
- Existing visible cards become "pinned" in their current section order
- Smart Highlights appear automatically — no migration needed
- A one-time prompt could offer presets: "We've added dashboard presets! Your current layout is preserved. Want to try a preset instead?"

---

## Open Questions for User Feedback

### 1. Smart Highlights: Always-on or opt-out?

**Option A:** Always-on, individual highlights can be snoozed/dismissed
**Option B:** Whole section can be turned off in Settings
**Option C:** Opt-in — user enables specific highlight types

Recommendation: **A** — the value of highlights is that they surface things you wouldn't think to look for. Opt-in defeats the purpose.

### 2. Should tools be dashboard cards, More items, or both?

**Option A:** Tools (Lookup, Contests, DXpeditions) live *only* in More tab
**Option B:** Tools can be pinned to dashboard *or* accessed via More (user's choice)
**Option C:** Tools are always in More, but their key data appears as dashboard cards (e.g., "2 active contests" card that links to the full Contests view)

Recommendation: **B** — maximum flexibility. Some users want Conditions and Contests always visible; others never look at them.

### 3. Preset selection timing

**Option A:** First launch only — preset picker in onboarding flow
**Option B:** First launch + accessible anytime from Settings
**Option C:** Prominent on first launch, then tucked into More > Dashboard Presets

Recommendation: **C** — presets are most valuable at first launch but should remain accessible for users who change their operating style.

### 4. How many pinned cards before it gets unwieldy?

**Option A:** No limit — user's choice
**Option B:** Soft limit with a warning ("Your dashboard has 10+ cards. Consider unpinning some for a cleaner experience.")
**Option C:** Hard limit of 8 cards (forces prioritization)

Recommendation: **A** — trust the user. The Edit mode with pin/unpin makes it easy to manage. Power users who want 12 cards should be able to have them.

### 5. Card sizes

**Option A:** All cards are the same size (current behavior)
**Option B:** Cards come in small (metric only) and large (with chart/detail) variants
**Option C:** Some cards are half-width (stats, streaks) and some are full-width (conditions, friends)

Recommendation: **A for now**, consider **C later**. Variable card sizes add complexity and the current uniform size works well. Revisit if users request it.

---

## Implementation Phases

### Phase 1: Foundation
- Add pin/unpin + reorder to dashboard cards (replace current show/hide toggles)
- Move tools to More tab's Tools section
- Add "+ Add Card" affordance at bottom of dashboard
- Migrate existing user preferences

### Phase 2: Intelligence
- Build Smart Highlights engine
- Start with 2-3 highlight types (award progress, streak alert, sync attention)
- Add dismiss/snooze gesture

### Phase 3: Presets + Onboarding
- Define 3 presets (Casual, POTA, DXer)
- Add preset picker to first-launch flow
- Add "Dashboard Presets" to More tab

### Phase 4: iPad + sidebarAdaptable
- Adopt `TabView(.sidebarAdaptable)`
- Define sidebar sections
- Handle compact/regular transitions

---

## Appendix: Current Dashboard Inventory

### Sections and Cards (current state)

| Section | Cards | Notes |
|---------|-------|-------|
| My Station | Activity Grid, Activity Log | Personal activity tracking |
| Social | Friends On Air, Friend Activity | Social features |
| Stats & Awards | Streaks, Statistics, POTA Awards, WAS, Brag Sheet, Favorites, Equipment | 7 cards — largest section |
| Tools | Conditions, Contests, DXpeditions, Callsign Lookup | Reference tools |
| Services | Sync Services | Sync status |

### Current Tab Bar

| Tab | Description |
|-----|-------------|
| Dashboard | All 15 cards in 5 sections |
| Sessions | Logging sessions |
| Logs | QSO search and browse |
| Map | QSO locations |
| More | Activity, Settings, hidden tabs |

---

## References

- [Apple HIG: Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [WWDC22: Explore Navigation Design for iOS](https://developer.apple.com/videos/play/wwdc2022/10001/)
- [WWDC24: Elevate Your Tab and Sidebar Experience in iPadOS](https://developer.apple.com/videos/play/wwdc2024/10147/)
- [ForeFlight More Menu & Tab Bar Changes](https://foreflight.com/enhancements/more-menu-tab-bar-changes)
- [Apple Health Summary customization](https://support.apple.com/en-us/104997)
- [Progressive Disclosure — NNGroup](https://www.nngroup.com/articles/progressive-disclosure/)
