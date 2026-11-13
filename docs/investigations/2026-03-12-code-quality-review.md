# Code Quality Review: DRY Violations & Unused Code

**Date:** 2026-03-12
**Status:** Complete

## Executive Summary

Comprehensive analysis of both Carrier Wave (iOS) and CW Sweep (macOS), plus their shared SPM packages. Findings: **~5,500+ lines of duplicated code** across **~90 files**, plus **~15 dead/deprecated artifacts**.

The codebase is well-structured overall, but repeated patterns have accumulated as features were added for each new service/program. The biggest structural issue is insufficient code sharing between the two apps — many models and services that belong in CarrierWaveCore or CarrierWaveData are duplicated in each app target.

---

# Part 1: Carrier Wave (iOS)

## 1.1 DRY Violations — Critical

### Metadata Mode Filtering (4+ files)

The `metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]` constant and its filtering logic is independently defined in:
- `SyncService.swift:36`
- `NeedsEngine.swift:73`
- `FriendSuggestionActor.swift:45`
- `BragSheetComputationActor.swift:132`

**Risk:** If modes change, 4+ files must be updated in sync. Bug waiting to happen.
**Fix:** Extract to a single shared constant.

### ADIF Field Parsing (3 clients, ~150 lines)

Identical regex-based ADIF parsing duplicated across:
- `QRZClient+ADIF.swift:92-126`
- `ClubLogClient+Helpers.swift:159-193`
- `EQSLClient+Helpers.swift:107-145`

Also duplicates: timestamp parsing (~45 lines) and record splitting (~30 lines).
**Fix:** Consolidate into a shared `ADIFFieldParser` utility.

### Entry Field Triplication (3 files, ~760 lines)

`ParkEntryField`, `SummitEntryField`, and `WWFFReferenceEntryField` are near-identical:
- Chip components (31-40 lines each, only color differs)
- Input row layout, text handling, validation — all copy-pasted
- ~200+ lines of duplicated logic

**Fix:** Generic `ReferenceEntryField<Cache>` with a color/icon parameter.

### Panel vs Sidebar Duplication (4 files, ~600 lines)

Both POTA and RBN spots have separate panel and sidebar implementations:
- `POTASpotsView.swift` (328 lines) vs `SidebarPOTASpotsView.swift` (293 lines)
- `RBNPanelView.swift` (335 lines) vs `SidebarRBNSpotsView.swift` (316 lines)
- Their `+Clubs.swift` extensions are nearly character-for-character identical

**Fix:** Consolidate each pair using a `displayMode: .panel | .sidebar` parameter.

### Stats Loader Actor Triplication (3 files, ~170 lines)

`ParkStatsLoader`, `SummitStatsLoader`, `WWFFRefStatsLoader` are structurally identical — same batch loop, same DateFormatter, same metadata filtering. Only the predicate field differs.

**Fix:** Generic `ReferenceStatsLoader<T>` parameterized on the predicate.

## 1.2 DRY Violations — High

### Batch Upload Orchestration (4 services, ~100 lines)

Upload state management (`syncPhase → uploading → complete/error`) is copy-pasted across QRZ, POTA, Club Log, and eQSL upload methods in `SyncService+Upload*.swift`.

### Download Phase Transitions (7 services, ~350 lines)

Download methods in `SyncService+Download.swift` repeat identical state transition boilerplate for each of the 7 sync services.

### Cache Service Boilerplate (3 caches, ~300 lines)

`POTAParksCache`, `SOTASummitsCache`, `WWFFReferencesCache` duplicate:
- `CacheMetadata` struct (Codable, identical)
- `CacheStatus` enum (identical cases)
- `ensureLoaded()`, `refreshIfNeeded()`, `forceRefresh()` methods

**Fix:** Generic `CacheService<T>` actor base.

### Repair Service Boilerplate (11 services, ~500+ lines)

11 `*RepairService` actors all follow an identical pattern: init with ModelContainer, batch-fetch with offset, process, save. Only the predicate and mutation differ.

**Fix:** Generic `BatchedRepairService<T>` with a closure for the mutation.

### Radio Protocol `extractResponses()` (2 files)

`KenwoodProtocol.swift:127-145` and `YaesuProtocol.swift:199-217` contain identical semicolon-delimited response extraction logic.

## 1.3 DRY Violations — Medium

| Area | Files | Lines | Notes |
|------|-------|-------|-------|
| Spot row badges (dupe/worked) | `POTASpotRow`, `SOTASpotRow` | ~60 | Identical badge views |
| Badge pill modifier | 15+ view files | ~467 occurrences | `.padding/.background/.clipShape(Capsule())` repeated everywhere |
| Chip view pattern | 9 files | ~270 | Nearly identical chip implementations |
| Edit distance algorithm | `CallsignEditDistance`, `MorseEditDistance` | ~50 | Same Levenshtein core |
| Award tier patterns | `POTAAwards`, `WWFFAwards` | ~100 | Same struct shape, different data |
| Dashboard portrait/landscape | `DashboardView+Layout.swift` | ~30 | Duplicated `isCardVisible()` checks |
| Error enum definitions | 4 API clients | ~120 | Structurally identical error types |

## 1.4 Unused / Dead Code

### Confirmed Dead Code

| Item | Location | Status |
|------|----------|--------|
| `LicenseWarningBanner` (deprecated) | `FrequencyWarningBanner.swift:152-171` | No external references |
| `LicenseWarningModifier` (deprecated) | `FrequencyWarningBanner.swift:238-256` | No external references |
| `.licenseWarning()` extension (deprecated) | `FrequencyWarningBanner.swift:276-288` | No external references |
| `MorseDecoderDelegate` protocol | `MorseDecoder.swift:419-428` | Zero conformers in codebase |
| `LoggerSettingsView` | `LoggerSettingsView.swift` | Only referenced in its own `#Preview`; replaced by `LoggerDetailSettingsView` |

### Potentially Unused Views (Verify Before Removing)

These views have no references found outside their own files:
1. `FriendSearchView.swift`
2. `FriendProfileView.swift`
3. `FriendsListView+Rows.swift`
4. `TuneInCellularAlert.swift`
5. `TuneInStrategySheet.swift`
6. `ChallengeDetailHelperViews.swift`
7. `ActivityShareCardView.swift`
8. `ExternalDataView+SOTASection.swift`
9. `ExternalDataView+WWFFSection.swift`
10. `POTAAuthWebView.swift`

> Note: Some may be referenced via SwiftUI's type-based navigation or view modifiers that don't show up in simple text searches. Manual verification recommended.

### Legacy Code

- `SyncService+ProcessLegacy.swift` — marked "prefer processDownloadedQSOsAsync" but still contains active reconciliation logic

---

# Part 2: CW Sweep (macOS)

## 2.1 DRY Violations — Critical

### HTTP Spot Client Boilerplate (5 clients)

All spot clients in `CWSweep/Services/Spots/` duplicate identical patterns:

**Timeout + URLRequest setup** (duplicated 5x):
- `RBNClient.swift:37-40`, `POTASpotsClient.swift:34-35`, `SOTAClient.swift:35-37`, `WWFFClient.swift:34-36`, `Ham365Client.swift:39-46`
- All use 15s timeout + `URLSession.shared`

**HTTP status validation** (duplicated 5x):
- All throw `.invalidResponse` / `.httpError(statusCode)` on non-200

**JSONDecoder instantiation** (duplicated 5x):
- All create fresh `JSONDecoder()` per call

**Callsign filtering** (duplicated 3x):
- `POTASpotsClient.swift:52-56`, `SOTAClient.swift:52-56`, `WWFFClient.swift:51-55`
- All fetch-all then filter by uppercased callsign

**Fix:** Extract `HTTPSpotClient` base actor handling timeout, status, and JSON decoding.

### Spot Color/Status Functions (3 duplicates)

`sourceColor()` duplicated between:
- `SpotListView.swift:406-414`
- `BandMapView.swift:382-390`

`neededColor()` duplicated in:
- `SpotListView.swift:380-388`
- `BandMapView.swift:361-369`
- `SpotDetailInspector.swift:246-254`

With inconsistent implementations (direct `Color` vs `Color(nsColor:)`).

**Fix:** Extract `SpotColorScheme` utility.

### Tune & Radio Command Logic (3 copies)

XIT-aware tune-and-log logic duplicated verbatim across:
- `SpotListView.swift:416-430`
- `BandMapView.swift:127-135` (inline)
- `ClusterView.swift:447-459`

All three: tuneToFrequency → setMode → conditional XIT offset/enable.

**Fix:** Extract `TuneAndLogHelper` on RadioManager.

## 2.2 DRY Violations — High

### Cluster Table Column Definitions (1 file, ~70 lines)

`ClusterView.swift` defines the same `TableColumn` structure twice:
- `smartSpotTableView` (lines 293-359)
- `spotTableView` (lines 394-442)

Time, Callsign, Freq, Mode, Spotter, Comment columns are identical in both.

### Filter Bar / Band Picker Patterns (2 views)

`SpotListView.swift:108-173` and `ClusterView.swift:222-278` duplicate:
- Identical `commonBands` array
- Same band Picker with `.segmented` style
- Same mode filter using `SpotModeFilter`

### Role Layout Scaffolds (5 layouts)

All five role layouts (`ContesterLayout`, `HunterLayout`, `ActivatorLayout`, `DXerLayout`, `CasualLayout`) repeat the `ParsedEntryView + Divider + QSOLogTableView` scaffold with minor arrangement differences.

## 2.3 Unused Code

| Item | Location | Notes |
|------|----------|-------|
| `defaultBaudRate` on FlexRadio profiles | `RadioProfile.swift:26-40` | Network radios don't use baud rate; parameter is dead for these entries |

---

# Part 3: Cross-App Duplication (iOS ↔ CWSweep)

CWSweep and CarrierWave share code via CarrierWaveCore and CarrierWaveData SPM packages. However, significant duplication remains outside those packages.

## 3.1 Spot Models — Identical Copies (5 models, ~750 lines)

All spot model types exist independently in both apps with near-identical implementations:

| Model | iOS Location | macOS Location | iOS Lines | macOS Lines |
|-------|-------------|----------------|-----------|-------------|
| `SpotRegion` + `EnrichedSpot` + `SpotSummary` | `CarrierWave/Models/SpotRegion.swift` | `CWSweep/Models/Spots/SpotRegion.swift` | 360 | 313 |
| `SOTASpot` | `CarrierWave/Models/SOTASpot.swift` | `CWSweep/Models/Spots/SOTASpot.swift` | 114 | 103 |
| `WWFFSpot` | `CarrierWave/Models/WWFFSpot.swift` | `CWSweep/Models/Spots/WWFFSpot.swift` | 68 | 60 |
| `RBNSpot` | `CarrierWave/Services/RBNClient.swift` (inline) | `CWSweep/Models/Spots/RBNSpot.swift` | ~30 | 71 |
| `POTASpot` | `CarrierWave/Services/POTAClient+Spots.swift` | `CWSweep/Models/Spots/POTASpot.swift` | 134 | 111 |

**Fix:** Move all spot models to CarrierWaveData. `EnrichedSpot` has minor divergence (iOS has `matchedNeeds`, macOS has DXCC fields) — unify with superset of fields.

## 3.2 Spot API Clients — Virtually Identical (4 clients, ~450 lines)

| Client | iOS Lines | macOS Lines | Similarity |
|--------|-----------|-------------|------------|
| `SOTAClient` | 70 | 61 | ~95% identical |
| `WWFFClient` | 78 | 60 | ~95% identical |
| `Ham365Client` | 67 | 67 | Identical |
| `HamDBClient` | 226 | 118 | ~70% (iOS has more methods) |

`RBNClient` and `POTAClient+Spots` differ more substantially (iOS versions are 2-4x larger with extra features).

**Fix:** Move SOTAClient, WWFFClient, Ham365Client to CarrierWaveCore (they're pure network + parsing, no SwiftData dependency). HamDBClient could follow with iOS extensions for extra methods.

## 3.3 SDRTranscriptModels — Identical (148 lines each)

- iOS: `CarrierWave/Models/SDRTranscriptModels.swift` (150 lines)
- macOS: `CWSweep/Models/SDRTranscriptModels.swift` (148 lines)

Contains `SDRTranscriptWord`, `SDRTranscriptLine`, `DetectedQSORange`, `SDRRecordingTranscript`. Character-for-character identical.

**Fix:** Move to CarrierWaveData.

## 3.4 UnitFormatter — Divergent Implementations

- iOS: `CarrierWave/Utilities/UnitFormatter.swift` (180 lines, 9+ methods)
- macOS: `CWSweep/Utilities/UnitFormatter.swift` (28 lines, 2 methods)

CWSweep only has `distance()` and `distanceFromMeters()`. iOS has the full suite including temperature, wind speed, watts-per-distance, cardinal directions, and distance-with-bearing.

**Fix:** Move the full iOS UnitFormatter to CarrierWaveCore (pure logic, no platform deps). Delete the CWSweep stub.

## 3.5 FullADIFExportActor — Near-Identical (444 vs 464 lines)

- iOS: `CarrierWave/Services/FullADIFExportActor.swift` (444 lines)
- macOS: `CWSweep/Services/Export/FullADIFExportActor.swift` (464 lines)

Same `FullExportQSOSnapshot`, same batch processing, same ADIF formatting, same metadata mode filtering.

**Fix:** Move to CarrierWaveData (already depends on SwiftData models).

## 3.6 DXCC/CTY Lookup — Same Purpose, Different Architecture

- iOS: `CTYService.swift` — `actor` singleton with background refresh
- macOS: `DXCCLookupService.swift` — `@MainActor @Observable` with UI binding

Both wrap CarrierWaveCore's `CTYParser`/`CTYDatabase` with download, caching, and lookup. Different concurrency models but identical business logic.

**Fix:** Create a shared `CTYCacheActor` in CarrierWaveData for download/cache/lookup. Each app keeps a thin platform-specific wrapper for UI binding.

## 3.7 ADIF Import — Parallel Implementations

- iOS: `ImportService.swift` — large service with multiple responsibilities
- macOS: `ADIFImportActor.swift` — focused background actor using `ADIFParser`

Both parse ADIF, deduplicate, and create QSO + ServicePresence records, but with different architectural patterns.

## 3.8 UnifiedSpot — CWSweep-Only (iOS Gap)

CWSweep has `UnifiedSpot.swift` (209 lines) — a unified representation with factory methods `from(rbn:)`, `from(pota:)`, `from(sota:)`, `from(wwff:)`. iOS handles spot types individually with no unified wrapper.

**Fix:** If iOS adopts UnifiedSpot, move to CarrierWaveData. Otherwise, CWSweep-only is fine.

## 3.9 What's Already Properly Shared

These are correctly in shared packages (no duplication):
- `KeychainHelper` — in CarrierWaveData
- `QSO`, `ServicePresence`, `LoggingSession` models — in CarrierWaveData
- `CTYParser`, `CTYDatabase` — in CarrierWaveCore
- `MaidenheadConverter`, `BandUtilities` — in CarrierWaveCore
- FT8 codec (`FT8Decoder`, `FT8Encoder`) — in CarrierWaveCore
- `CallsignDetector` — in CarrierWaveCore
- CloudSync infrastructure — in CarrierWaveData

---

# Impact Summary

## iOS-Internal Duplication

| Category | Duplicated Lines | Files Affected | Refactor Effort |
|----------|-----------------|----------------|-----------------|
| Metadata modes constant | ~20 | 4 | Trivial |
| ADIF parsing | ~150 | 3 | Low |
| Entry fields | ~200 | 3 | Medium |
| Panel/Sidebar views | ~600 | 4+2 | Medium |
| Stats loaders | ~170 | 3 | Low |
| Upload orchestration | ~100 | 4 | Medium |
| Download transitions | ~350 | 1 (7 methods) | Medium |
| Cache boilerplate | ~300 | 3 | Medium |
| Repair services | ~500 | 11 | High |
| Spot row badges | ~60 | 2 | Low |
| Badge pill modifier | scattered | 15+ | Low |
| **Subtotal** | **~2,500+** | **55+** | |

## CWSweep-Internal Duplication

| Category | Duplicated Lines | Files Affected | Refactor Effort |
|----------|-----------------|----------------|-----------------|
| HTTP spot client boilerplate | ~150 | 5 | Low |
| Color/status functions | ~60 | 3 | Trivial |
| Tune & radio commands | ~60 | 3 | Low |
| Cluster table columns | ~70 | 1 | Low |
| Filter bar patterns | ~60 | 2 | Low |
| Role layout scaffolds | ~100 | 5 | Medium |
| **Subtotal** | **~500+** | **19** | |

## Cross-App Duplication (iOS ↔ CWSweep)

| Category | Duplicated Lines | Files Affected | Refactor Effort |
|----------|-----------------|----------------|-----------------|
| Spot models (5 types) | ~750 | 10 (5 pairs) | Medium |
| Spot API clients (4) | ~450 | 8 (4 pairs) | Medium |
| SDRTranscriptModels | ~150 | 2 | Low |
| UnitFormatter | ~28 | 2 | Low |
| FullADIFExportActor | ~460 | 2 | Medium |
| DXCC/CTY lookup | ~200 | 2 | Medium |
| **Subtotal** | **~2,000+** | **26** | |

### **Grand Total: ~5,000+ duplicated lines across ~100 files**

---

# Recommended Priority Order

## Quick wins (< 1 hour each)
- Extract shared `metadataModes` constant
- Extract shared `ADIFFieldParser` utility
- Add `.badgePill(color:)` view modifier (iOS)
- Extract `SpotColorScheme` utility (CWSweep)
- Extract `TuneAndLogHelper` on RadioManager (CWSweep)
- Remove confirmed dead code (deprecated views, `MorseDecoderDelegate`, `LoggerSettingsView`)
- Move `SDRTranscriptModels` to CarrierWaveData
- Move `UnitFormatter` (full iOS version) to CarrierWaveCore

## Medium effort (half-day each)
- Move spot models (SpotRegion, SOTASpot, WWFFSpot, RBNSpot, POTASpot) to CarrierWaveData
- Move spot API clients (SOTAClient, WWFFClient, Ham365Client) to CarrierWaveCore
- Move `FullADIFExportActor` to CarrierWaveData
- Extract `HTTPSpotClient` base actor (CWSweep)
- Generic `ReferenceEntryField` replacing 3 entry fields (iOS)
- Generic `ReferenceStatsLoader` replacing 3 stats actors (iOS)
- Consolidate panel/sidebar view pairs with display mode parameter (iOS)
- Extract radio protocol `extractResponses()` to shared utility

## Larger refactors (1+ day each)
- Unified `CTYCacheActor` in CarrierWaveData with platform-specific wrappers
- Generic `CacheService<T>` base actor (iOS)
- Generic `BatchedRepairService<T>` base actor (iOS)
- Generic upload/download orchestration in SyncService (iOS)
- Evaluate adopting CWSweep's `UnifiedSpot` pattern in iOS
