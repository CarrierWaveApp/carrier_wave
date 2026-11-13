# Smart Spot Recommendations — Technical Design

## Overview

Cross-reference incoming spots against what the operator still needs for awards and challenges. Surface matches in the Activity Log with priority indicators and optional notifications. All intelligence stays local — no HamAlert API dependency.

See also: [challenges-prd.md](challenges-prd.md) (HamAlert integration deferred to post-v3).

---

## Problem Statement

Carrier Wave already fetches spots from four sources (RBN, POTA, SOTA, WWFF) every 45 seconds and computes award progress for POTA and WWFF. But these systems don't talk to each other. An operator chasing their last 3 WAS states has no way to know when one of those states appears in the spot feed — they have to manually scan the list and remember what they need.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Sync Completes                        │
│         or NeedsEngine.recompute() called                │
└────────────────────────┬─────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────┐
│                     NeedsEngine                          │
│  (actor — background computation from QSO data)          │
│                                                          │
│  Inputs:                                                 │
│  - QSO history (via FetchDescriptor, background context) │
│  - POTA/WWFF award progress                              │
│  - Active challenge participations (v2)                  │
│                                                          │
│  Output: NeedsSnapshot (frozen, Sendable)                │
└────────────────────────┬─────────────────────────────────┘
                         │ cached on @MainActor
                         ▼
┌──────────────────────────────────────────────────────────┐
│               SpotMonitoringService                      │
│  (existing — receives spots every 45s)                   │
│                                                          │
│  New step after enrichment:                              │
│  SpotNeedsMatcher.match(spots, against: needsSnapshot)   │
│  → EnrichedSpot gains .matchedNeeds: [MatchedNeed]       │
└──────────┬───────────────────────────┬───────────────────┘
           │                           │
           ▼                           ▼
┌─────────────────────┐   ┌──────────────────────────────┐
│  ActivityLogSpots   │   │     NeedsSpotNotifier        │
│  (UI — badges,      │   │  (toast + local notification │
│   sort, filter)     │   │   for high-value matches)    │
└─────────────────────┘   └──────────────────────────────┘
```

---

## Phases

### Phase 1 — DXCC + WAS Needs Matching

The highest-value, lowest-complexity slice. Most operators actively chase DXCC entities and Worked All States — these are universal goals with clear "have/need" semantics.

#### Scope

- **NeedsEngine** computes DXCC band-slot needs and WAS state gaps from QSO history
- **SpotNeedsMatcher** tags incoming spots with matched needs
- **Activity Log UI** shows need badges and a "Needs Only" filter
- **NeedsSpotNotifier** fires toasts for need matches (opt-in)

#### Data Models

```
NeedCategory (enum)
├── .dxcc(entity: String, band: String?)    // "VK" on 20m, or "VK" any-band
├── .was(state: String, mode: String?)      // "WY" on CW, or "WY" any-mode

MatchedNeed (struct, Sendable)
├── category: NeedCategory
├── label: String                           // "New DXCC: VK on 20m"
├── priority: NeedPriority                  // .high, .medium, .low

NeedPriority (enum)
├── .high     // Last 5 states for WAS, new all-time DXCC entity
├── .medium   // New band slot for known entity, common missing state
├── .low      // Incremental progress

NeedsSnapshot (struct, Sendable)
├── dxccNeeds: DXCCNeeds
├── wasNeeds: WASNeeds
├── generatedAt: Date
├── isEmpty: Bool

DXCCNeeds (struct, Sendable)
├── allTimeWorked: Set<String>              // Entity prefixes already worked
├── bandSlotWorked: Set<BandSlotKey>        // (entity, band) pairs worked
├── targetEntities: Set<String>?            // User-selected focus (nil = all)

WASNeeds (struct, Sendable)
├── statesWorked: Set<String>               // 2-letter state codes worked
├── statesMissing: Set<String>              // Complement of above (50 - worked)
├── perModeWorked: [String: Set<String>]    // mode → states worked
```

#### NeedsEngine

```swift
actor NeedsEngine {
    func recompute(container: ModelContainer) async -> NeedsSnapshot
    func cachedSnapshot() -> NeedsSnapshot?
}
```

- Creates its own `ModelContext` from container (background actor pattern)
- Fetches all QSOs with `FetchDescriptor` (no `@Query`)
- Filters out metadata modes (`WEATHER`, `SOLAR`, `NOTE`)
- Extracts DXCC entity from callsign prefix (uses existing `CallsignDetector` or DXCC entity lookup)
- Extracts US state from QSO state field or grid square derivation
- Computation is O(n) over QSO count — runs on actor, not main thread
- Recompute triggers: sync completion, manual refresh, app foreground after 1 hour

#### SpotNeedsMatcher

```swift
enum SpotNeedsMatcher {
    static func match(
        _ spots: [EnrichedSpot],
        against snapshot: NeedsSnapshot
    ) -> [EnrichedSpot]  // spots with .matchedNeeds populated
}
```

- For each spot, derive DXCC entity from callsign prefix
- For POTA/SOTA/WWFF spots, derive US state from park reference or grid
- Check against `DXCCNeeds` and `WASNeeds`
- Assign priority: new all-time entity = `.high`, new band slot = `.medium`, etc.
- O(spots × needs) but both sets are small — negligible cost at 45s intervals

#### EnrichedSpot Extension

Add to existing `EnrichedSpot`:

```swift
var matchedNeeds: [MatchedNeed] = []
var hasNeeds: Bool { !matchedNeeds.isEmpty }
var highestNeedPriority: NeedPriority? { matchedNeeds.map(\.priority).max() }
```

#### Activity Log UI Changes

| Change | File | Details |
|--------|------|---------|
| Need badge on spot row | `ActivityLogSpotRow.swift` | Colored chip showing need label (e.g., "DXCC" / "WAS: WY") |
| "Needs Only" filter toggle | `SpotFilterSheet.swift` | New toggle in filter sheet, persisted in `SpotFilters` |
| Sort by priority | `ActivityLogSpotsList.swift` | When "Needs Only" active, sort by `highestNeedPriority` descending |
| Needs summary banner | `NeedsSummaryCard.swift` (new) | "2 new DXCC, 1 WAS state on the air" — shown above spot list when matches exist |

#### NeedsSpotNotifier

Follows the `FriendSpotNotifier` pattern exactly:

```swift
@MainActor @Observable
final class NeedsSpotNotifier {
    func checkSpots(_ spots: [EnrichedSpot])
    // 10-minute cooldown per (callsign + need category)
    // Toast: "New DXCC! VK3ABC on 14.025 MHz CW"
    // Local notification with sound
    // Configurable: UserDefaults "needsSpotNotificationsEnabled"
}
```

Integrated into `SpotMonitoringService` alongside `friendNotifier`.

#### Settings

Add to existing Settings > Notifications section:

- Toggle: "Notify for needed spots" (default: on)
- Picker: Priority threshold (High only / Medium+ / All)

#### Files

| File | Action |
|------|--------|
| `CarrierWave/Models/NeedTypes.swift` | **New** — `NeedCategory`, `MatchedNeed`, `NeedPriority`, `NeedsSnapshot`, `DXCCNeeds`, `WASNeeds` |
| `CarrierWave/Services/NeedsEngine.swift` | **New** — actor computing needs from QSO data |
| `CarrierWave/Services/SpotNeedsMatcher.swift` | **New** — stateless matching function |
| `CarrierWave/Services/NeedsSpotNotifier.swift` | **New** — toast + local notification for need matches |
| `CarrierWave/Services/SpotMonitoringService.swift` | **Modify** — add `needsNotifier`, call matcher after enrichment |
| `CarrierWave/Views/ActivityLog/ActivityLogSpotRow.swift` | **Modify** — add need badge chip |
| `CarrierWave/Views/ActivityLog/SpotFilterSheet.swift` | **Modify** — add "Needs Only" toggle |
| `CarrierWave/Views/ActivityLog/ActivityLogSpotsList.swift` | **Modify** — priority sort, needs filter |
| `CarrierWave/Views/ActivityLog/NeedsSummaryCard.swift` | **New** — banner showing on-air needs count |
| `CarrierWave/Views/Settings/NotificationSettingsView.swift` | **Modify** — add needs notification controls |

#### Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| DXCC entity derivation is non-trivial (prefix → entity mapping) | Start with callsign prefix heuristic; refine with CTY.dat lookup later |
| Large QSO history makes recompute slow | Run on background actor, cache result, recompute only on sync/foreground |
| Too many "needs" floods the UI | Priority system + threshold setting; default to High only for notifications |

---

### Phase 2 — POTA/WWFF Award Targets + Challenge Goals

Extends the needs engine with program-specific award tracking and challenge integration.

#### Scope

- **POTA hunter needs** — parks needed for next Hunter tier
- **POTA activator targets** — states needed for WAS activator award, entities for DX award
- **WWFF hunter needs** — references needed for next Hunter tier
- **Challenge goal matching** — unmet goals from active `ChallengeParticipation` records
- **Needs dashboard card** — summary widget on main Dashboard

#### New Need Categories

```
NeedCategory (extended)
├── .dxcc(...)                              // Phase 1
├── .was(...)                               // Phase 1
├── .potaPark(reference: String, name: String?)   // "K-1234" for hunter tier
├── .potaState(state: String)               // State needed for POTA WAS
├── .potaEntity(entity: String)             // Entity needed for POTA DX
├── .wwffReference(reference: String)       // WWFF ref for hunter tier
├── .challengeGoal(challengeId: UUID, goalId: String, label: String)
```

#### NeedsEngine Extensions

```swift
actor NeedsEngine {
    // Phase 1
    func recompute(container: ModelContainer) async -> NeedsSnapshot

    // Phase 2 additions
    private func computePOTAHunterNeeds(...) -> POTAHunterNeeds
    private func computePOTAActivatorNeeds(...) -> POTAActivatorNeeds
    private func computeWWFFHunterNeeds(...) -> WWFFHunterNeeds
    private func computeChallengeNeeds(...) -> ChallengeNeeds
}
```

**POTA Hunter Needs:**
- Query distinct park references from hunter QSOs
- Compare against next tier threshold from `POTAAwards.hunterTiers`
- Compute parks remaining: `nextTierThreshold - uniqueParksWorked`
- No specific "target parks" list possible (any new park counts) — instead, tag any POTA spot where park ref is NOT in worked set

**POTA Activator Needs:**
- States not yet activated (from `POTAAwardsComputation.statesActivated`)
- DXCC entities not yet activated (from `POTAAwardsComputation.dxEntitiesCount`)
- These match against POTA spots where activator is in needed state/entity

**WWFF Hunter Needs:**
- Same pattern as POTA hunter — references not yet worked
- Tag any WWFF spot where reference is NOT in worked set

**Challenge Goals:**
- Load active `ChallengeParticipation` records
- For each, extract unmet goals via `ChallengeProgressEngine`
- Convert goals to need patterns (e.g., "Work a station in Zone 17" → match callsign zones)
- Uses existing `ChallengeQSOMatcher` qualification criteria to build match rules

#### NeedsSnapshot Extension

```
NeedsSnapshot (extended)
├── dxccNeeds: DXCCNeeds                    // Phase 1
├── wasNeeds: WASNeeds                      // Phase 1
├── potaHunterNeeds: POTAHunterNeeds        // Parks not yet hunted
├── potaActivatorNeeds: POTAActivatorNeeds  // States/entities not activated
├── wwffHunterNeeds: WWFFHunterNeeds        // References not yet hunted
├── challengeNeeds: [ChallengeNeed]         // Unmet challenge goals
├── generatedAt: Date
```

#### SpotNeedsMatcher Extension

Matching logic per source type:

| Spot Source | Checked Against |
|-------------|----------------|
| RBN | DXCC, WAS, challenge goals |
| POTA | DXCC, WAS, POTA hunter (park ref), POTA activator (state/entity), challenge goals |
| SOTA | DXCC, WAS, challenge goals |
| WWFF | DXCC, WAS, WWFF hunter (reference), challenge goals |

For POTA/WWFF hunter needs, the match is on the **park/reference** from the spot — this is reliable since spot data includes the reference directly.

#### Dashboard Integration

New card in Dashboard (alongside existing stats cards):

```
┌──────────────────────────────────────┐
│  📡  Needs On The Air                │
│                                      │
│  2 new DXCC entities                 │
│  1 WAS state (WY)                    │
│  4 new POTA parks                    │
│                                      │
│  Last checked: 30s ago      View →   │
└──────────────────────────────────────┘
```

Tapping navigates to Activity Log with "Needs Only" filter pre-applied.

#### Files

| File | Action |
|------|--------|
| `CarrierWave/Models/NeedTypes.swift` | **Modify** — add POTA/WWFF/challenge need categories |
| `CarrierWave/Services/NeedsEngine.swift` | **Modify** — add POTA/WWFF/challenge computation methods |
| `CarrierWave/Services/SpotNeedsMatcher.swift` | **Modify** — extend matching for new categories |
| `CarrierWave/Views/Dashboard/NeedsDashboardCard.swift` | **New** — summary card for dashboard |
| `CarrierWave/Views/Dashboard/DashboardView.swift` | **Modify** — add needs card |

#### Dependencies

- Phase 1 complete
- Existing `POTAAwardsComputation` and `WWFFAwards` for tier thresholds
- Existing `ChallengeProgressEngine` and `ChallengeQSOMatcher` for challenge needs
- POTA parks cache (already exists) for state derivation from park reference

#### Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| POTA hunter needs list is unbounded (any unworked park matches) | Show count only ("4 new parks"), not individual park names in banner; badge the spot row with "New Park" |
| Challenge goal matching may be complex (arbitrary criteria) | Reuse `ChallengeQSOMatcher` — it already handles all qualification rules |
| NeedsSnapshot grows large with many categories | Snapshot uses Sets for O(1) lookup; total memory is modest (thousands of strings, not millions) |
| Recompute cost increases with POTA/WWFF history | Profile and set budget; if >2s, split into incremental updates per category |

---

### Phase 3 — HamAlert Export + Custom Needs

Adds user-defined needs and a one-shot export path to HamAlert. The app remains the brain; HamAlert is an optional amplifier.

#### Scope

- **Custom needs** — user-defined callsign patterns, entities, or references to watch for
- **HamAlert trigger export** — generate trigger configurations from needs, export as copyable text or direct API push
- **Needs management UI** — view, edit, dismiss, pin needs
- **History** — track when needs were fulfilled (spot appeared, QSO logged)

#### Custom Needs

Users can manually add needs beyond what the engine auto-computes:

```
NeedCategory (extended)
├── ... (all previous categories)
├── .custom(pattern: String, label: String)  // "VK9*" — "Christmas Island"
```

Custom needs are persisted in SwiftData:

```swift
@Model
final class CustomNeed {
    var id: UUID
    var pattern: String          // Callsign glob, entity code, park ref, state
    var patternType: PatternType // .callsign, .entity, .state, .parkRef
    var label: String            // User's description
    var createdAt: Date
    var isActive: Bool
    var fulfilledAt: Date?       // When the need was met (QSO logged)
    var fulfilledBy: UUID?       // QSO that fulfilled it
}
```

Pattern matching in `SpotNeedsMatcher` uses the same glob logic as `ChallengeQSOMatcher` (prefix match, wildcard).

#### Needs Management UI

New section in Activity Log (or standalone tab):

```
┌──────────────────────────────────────┐
│  My Needs                            │
│                                      │
│  Auto-detected                       │
│  ┌────────────────────────────────┐  │
│  │ ☐ DXCC: 23 entities remaining │  │
│  │ ☐ WAS: WY, ND, SD             │  │
│  │ ☐ POTA Hunter: 47 parks to    │  │
│  │   next tier (Sasquatch)        │  │
│  └────────────────────────────────┘  │
│                                      │
│  Custom                              │
│  ┌────────────────────────────────┐  │
│  │ ★ VK9* — Christmas Island     │  │
│  │ ★ ZL7* — Chatham Islands      │  │
│  └────────────────────────────────┘  │
│                                      │
│  + Add Custom Need                   │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  Export to HamAlert →          │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

Actions per need:
- **Dismiss** — hide auto-detected need (persisted as suppression)
- **Pin** — always show even if threshold changes
- **Delete** — remove custom need

#### HamAlert Export

Two export modes, both user-initiated:

**1. Copy as text (no API required)**

Generate a human-readable summary the user can reference when configuring HamAlert manually:

```
=== Carrier Wave Needs Export (2026-03-09) ===

DXCC Entities Needed (any band):
  VK9/C, VK9/X, ZL7, 3D2, ...

WAS States Needed:
  WY, ND, SD

Custom Watches:
  VK9* (Christmas Island)
  ZL7* (Chatham Islands)

Suggested HamAlert Triggers:
  Trigger 1: callsign=VK9C* OR VK9X*, source=RBN+POTA
  Trigger 2: state=WY OR ND OR SD, source=RBN
  ...
```

Shared via standard iOS share sheet.

**2. Direct API push (requires HamAlert API key)**

If the user has configured a HamAlert API key:

```swift
actor HamAlertExporter {
    func exportNeeds(
        _ snapshot: NeedsSnapshot,
        customNeeds: [CustomNeed],
        apiKey: String
    ) async throws -> ExportResult

    // Creates triggers tagged with "CarrierWave" comment
    // for easy identification and cleanup
}
```

- One-shot operation, not ongoing sync
- Tags triggers with `[CW]` prefix in trigger name for identification
- Offers "Clean up previous CW triggers" before creating new ones
- API key stored in Keychain (follows existing credential pattern)
- Confirmation sheet showing exactly what will be created before pushing

#### Fulfillment Tracking

When a QSO is logged that matches a need:

1. `NeedsEngine` marks the need as fulfilled
2. Toast: "Need fulfilled! Worked VK9ABC for new DXCC"
3. Custom needs get `fulfilledAt` and `fulfilledBy` set
4. Auto-detected needs simply disappear on next recompute
5. If HamAlert export was used, offer "Remove fulfilled triggers from HamAlert?"

#### Files

| File | Action |
|------|--------|
| `CarrierWave/Models/NeedTypes.swift` | **Modify** — add `.custom` category |
| `CarrierWave/Models/CustomNeed.swift` | **New** — SwiftData model for user-defined needs |
| `CarrierWave/Services/NeedsEngine.swift` | **Modify** — incorporate custom needs into snapshot |
| `CarrierWave/Services/HamAlertExporter.swift` | **New** — actor for HamAlert API trigger management |
| `CarrierWave/Views/ActivityLog/NeedsManagementView.swift` | **New** — needs list with dismiss/pin/delete |
| `CarrierWave/Views/ActivityLog/AddCustomNeedSheet.swift` | **New** — sheet for adding custom needs |
| `CarrierWave/Views/ActivityLog/HamAlertExportSheet.swift` | **New** — confirmation + export UI |
| `CarrierWave/Views/Settings/HamAlertSettingsView.swift` | **New** — API key configuration |
| `CarrierWaveData/.../ModelContainer+Schema.swift` | **Modify** — add `CustomNeed` to schema |

#### Dependencies

- Phase 2 complete
- HamAlert API documentation (for trigger CRUD endpoints)
- HamAlert API key provisioning (user provides their own key)

#### Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| HamAlert API may change or rate-limit | Export is one-shot, not ongoing; text export works without API |
| Users create too many custom needs | Soft limit (e.g., 50); warn that HamAlert has trigger limits per tier |
| Trigger cleanup is error-prone | Tag all CW-created triggers; only delete tagged triggers; always confirm |
| HamAlert API key security | Keychain storage (existing pattern); never persisted in SwiftData or logs |
| Fulfillment tracking adds complexity to QSO logging path | Lightweight check — snapshot lookup is O(1) per need category; no DB writes on hot path |

---

## Cross-Phase Considerations

### Performance

All computation runs on the `NeedsEngine` actor with its own `ModelContext`. The main thread never touches QSO data for needs computation. Spot matching is O(spots × categories) per polling cycle — with ~100 spots and ~5 categories, this is sub-millisecond.

The `NeedsSnapshot` is a frozen value type passed to the main actor. No shared mutable state between the engine and the UI.

### Metadata Mode Enforcement

`NeedsEngine` filters out `WEATHER`, `SOLAR`, `NOTE` modes when computing worked entities/states/parks — consistent with all other computation sites. Add `NeedsEngine` to the enforcement site list in CLAUDE.md.

### Testing Strategy

- **Unit tests** for `SpotNeedsMatcher` — given a snapshot and spots, verify correct matches
- **Unit tests** for `NeedsEngine` — given QSO arrays, verify correct needs computation
- **Unit tests** for `HamAlertExporter` — verify trigger generation from snapshot
- All tests use in-memory SwiftData containers (existing pattern)

### Migration Path

No SwiftData schema migration needed for Phase 1–2 (all in-memory computation). Phase 3 adds `CustomNeed` model — standard lightweight migration.

### Settings Summary

| Setting | Default | Phase |
|---------|---------|-------|
| Needs spot notifications enabled | `true` | 1 |
| Notification priority threshold | `.high` | 1 |
| DXCC needs tracking | `true` | 1 |
| WAS needs tracking | `true` | 1 |
| POTA hunter needs tracking | `true` | 2 |
| WWFF hunter needs tracking | `true` | 2 |
| Challenge needs tracking | `true` | 2 |
| HamAlert API key | (none) | 3 |

---

## Open Questions

1. **DXCC entity derivation** — Should we use a bundled CTY.dat for accurate prefix→entity mapping, or start with a heuristic and refine? CTY.dat is ~200KB and well-established.
2. **Confirmed vs. worked** — Should needs consider LoTW/QSL confirmation status, or just "worked"? Starting with "worked" is simpler and matches how most operators think about chasing.
3. **Band-specific DXCC** — Full DXCC Challenge tracking (entity × band matrix) is valuable but complex. Phase 1 could start with "any band" DXCC and add band slots as a setting.
4. **Needs widget** — Should there be a home screen widget showing current needs on the air? Natural extension but adds widget target complexity.
