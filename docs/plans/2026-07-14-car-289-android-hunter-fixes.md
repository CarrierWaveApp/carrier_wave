# CAR-289 — Android Hunter tab: inline QSO edit + spot filters

**Issue:** [CAR-289] "Android Hunt page/log seems buggy" — two asks:
1. Tap the "Hunter Log" summary card and edit logged QSOs.
2. Filter the feed by mode, band, etc. (today only source chips: All/POTA/RBN/SOTA/WWFF).

Both are **iOS→Android parity gaps**, not bugs. iOS already does both on the same
screen (`RecentQSOsSection` + `QSOEditSheet`, and `SpotFilters`/`SpotFilterBar`/
`SpotFilterSheet`). The shared Rust core already exposes everything needed —
**no Rust/FFI changes required.**

Scope decisions (confirmed with user):
- Ask #1 → **inline edit on the Hunter tab** (not "navigate to Logbook").
- Ask #2 → **full iOS filter parity** (band + mode + source + hideWorked + needsOnly).

---

## Part A — Inline recent-QSO list + editor (ask #1)

Today's logged QSOs are **already fetched** into `HunterUiState.recent` via
`api.recentQsos(logId, 20)` but never displayed — the Hunter body shows the spot
feed instead. iOS shows them in `RecentQSOsSection` under the header, tappable to
edit via `QSOEditSheet`, swipe/long-press to delete.

Android has **no QSO editor at all** (Logbook is read-only; `QsoCard` is
display-only). So the editor is net-new. `FieldStore.upsertQso(FfiQso)` /
`deleteQso(id)` are the proven write path (already used by `LogbookRepository`).

### A1. Reveal recent QSOs by tapping the header
Make `TodayHeader` in `HunterLogScreen.kt` tappable to expand/collapse a
"Recent QSOs" list beneath it (directly answers "click my hunter log at the top").
- Add a `rememberSaveable` expanded flag + a chevron affordance on the card.
- When expanded, render `ui.recent` as rows (time UTC · callsign · band/mode ·
  their-park · RST) mirroring iOS `recentQSORow`. Each row `onClick` → open editor.
- Empty state: "No QSOs logged today".

### A2. New `QsoEditSheet.kt` (Compose `ModalBottomSheet`)
Pragmatic editor over the **common** `FfiQso` fields (not the full picker-heavy
iOS sheet — pickers like DXCC/park/summit are a follow-up):
- Contact: callsign, band, mode, frequency (kHz↔MHz via existing formatters),
  rstSent, rstRcvd, name.
- Their location: theirGrid, qth, state, country, theirPark.
- Notes.
- Validation mirrors iOS `isValid`: non-empty callsign + myCallsign + band + mode.
- **Save**: copy the `FfiQso` with edited fields, set `modifiedAt`, call
  `vm.updateQso(qso)`.
- **Delete**: confirm dialog → `vm.deleteQso(qso.id)`.

Keep the file under the shared style; reuse `ModePill`/`BandPill`/`formatFreq`
from `ui.common` where useful.

### A3. `HunterLogViewModel` additions
- `fun updateQso(qso: FfiQso)` → `withContext(IO) { store.upsertQso(qso) }` then
  `refresh()` (reloads `recent` + `today`). Catch `CwException` → `error`.
- `fun deleteQso(id: String)` → `withContext(IO) { store.deleteQso(id) }` then
  `refresh()`.
- Both marshalled off-main per the UniFFI-dispatcher rule (store writes fsync).

**Files:** `HunterLogScreen.kt` (edit), new `ui/hunter/QsoEditSheet.kt`,
`HunterLogViewModel.kt` (edit).

---

## Part B — Full filter parity on the spot feed (ask #2)

`SpotsScreen`/`SpotsViewModel` is shared by the **Hunter tab and the Sessions
logger**. Filter state stays in each screen's own `SpotsViewModel` instance so the
two don't cross-contaminate. `SpotsViewModel.filterFor()` already builds an
`FfiSpotFilter` but hard-codes `bands`/`modes`/`hideWorked`/`needsOnly` empty.

### B1. Filter state in `SpotsViewModel`
Replace the single `sourceFilter` + hidden `modeFilter` with one
`MutableStateFlow<SpotFilterState>`:
```
data class SpotFilterState(
  val sources: Set<SpotSource> = emptySet(),   // empty = all
  val bands: Set<String> = emptySet(),         // "20m", …
  val modes: Set<String> = emptySet(),         // "CW","SSB","FT8", …
  val hideWorked: Boolean = false,
  val needsOnly: Boolean = false,
)
```
- Keep `applyModeFilter(FfiSpotModeFilter)` working for the HUNT command (seed
  `modes`/family) — map it onto the new state so nothing regresses.
- `filterFor` populates `bands`, `modes`, `hideWorked`, `needsOnly` from state.
- The existing `combine(generation, filterState)` reactive rebuild stays.

### B2. Filter UI on `SpotsScreen`
- Keep the source quick-chips row (`SourceSelector`) as-is (it's the iOS
  `SpotFilterBar` analog) but drive it from `state.sources`.
- Add a **filter button** (funnel icon, tinted when active) that opens a new
  `SpotFilterSheet.kt` (`ModalBottomSheet`) with:
  - Band multi-select chips (common HF/VHF bands).
  - Mode multi-select chips (CW/SSB/FT8/FT4/RTTY/…).
  - "Hide worked" + "Needs only" switches.
  - "Clear all" action.
- Band/mode option lists: reuse whatever constant Android already has for bands/
  modes if present; otherwise a local ordered list matching iOS.

**Files:** `SpotsViewModel.kt` (edit), `SpotsScreen.kt` (edit),
new `ui/spots/SpotFilterSheet.kt`.

---

## Out of scope (call out, don't silently drop)
- Picker-driven fields in the editor (DXCC/park/summit/WWFF/contest) — iOS has
  them; Android editor ships common fields first.
- Continent/region/text/max-age filters (iOS has continents) — deferred; the
  FFI supports them so they're a cheap follow-up.
- Filter persistence across launches (iOS uses `@AppStorage`) — MVP holds state
  in the viewmodel; add DataStore later if desired.
- No upload pipeline on Android yet, so edits don't re-queue uploads (matches
  existing `logQso` behavior).

## Verification
- `cd android && ./gradlew :app:assembleDebug` (buildRustCore regenerates
  bindings; no Rust change so it's a straight Kotlin compile).
- Manual: tap header → recent QSOs expand → tap one → edit a field → save →
  count/badges update. Open filter sheet → pick 20m + CW → feed narrows.
- Changelog: add entries under `# Android` in root `CHANGELOG.md` +
  `website/changelog.html` Android track.
- Comment on CAR-289 after commit.
