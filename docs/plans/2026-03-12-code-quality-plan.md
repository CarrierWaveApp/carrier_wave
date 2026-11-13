# Code Quality Remediation Plan

**Date:** 2026-03-12
**Based on:** [Code Quality Review](../investigations/2026-03-12-code-quality-review.md)
**Scope:** ~5,500 duplicated lines across ~100 files, ~15 dead artifacts

---

## Phase 1: Quick Wins — Constants, Dead Code, and Shared Models ✅

**Status:** Complete (commit `28c6c6a`)
**Goal:** Eliminate low-hanging fruit with minimal risk. Each item is independently shippable.

### 1A. Shared `metadataModes` Constant ✅
- Created `QSOMode` enum in `CarrierWaveData/Utilities/QSOMode.swift` with `metadataModes` and `isMetadata()`
- Replaced **26** independent definitions (investigation estimated 4) across both apps
- Updated CLAUDE.md and CWSweep/CLAUDE.md to reference QSOMode

### 1B. Remove Confirmed Dead Code ✅
- Deleted `LicenseWarningBanner`, `LicenseWarningModifier`, `.licenseWarning()` from `FrequencyWarningBanner.swift`
- Deleted `MorseDecoderDelegate` protocol from `MorseDecoder.swift`
- Deleted `LoggerSettingsView.swift` (replaced by `LoggerDetailSettingsView`)

### 1C. Move `SDRTranscriptModels` to CarrierWaveData ✅
- Moved to `CarrierWaveData/Models/SDRTranscriptModels.swift` with public access
- Deleted both app-local copies

### 1D. Move `UnitFormatter` to CarrierWaveCore ✅
- Moved full iOS `UnitFormatter` to `CarrierWaveCore/UnitFormatter.swift`
- Deleted both app-local copies
- Added `import CarrierWaveCore` to 5 consumer files

### 1E. Extract `.badgePill(color:)` View Modifier (iOS) ✅
- Created `BadgePillModifier` in `CarrierWave/Views/Components/BadgePillModifier.swift`
- Applied to 10 representative view files (16 instances); remaining can be converted incrementally

**Phase 1 actual: ~400+ duplicated lines removed, 15 dead artifacts cleaned up**

---

## Phase 2: Shared Utilities — Parsers, Helpers, Colors ✅

**Status:** Complete (commit `2bf8f40`)
**Goal:** Extract shared utility code used across multiple services or apps.

### 2A. Extract `ADIFFieldParser` Utility ✅
- Added `ADIFParser.extractFields()` and `ADIFParser.parseTimestamp()` public static methods
- Removed local `parseADIFFields`/`parseTimestamp` from `EQSLClient+Helpers.swift`
- QRZ and Club Log clients already used ADIFParser; eQSL was the remaining holdout

### 2B. Extract `SpotColorScheme` Utility (CWSweep) ✅
- Created `CWSweep/Utilities/SpotColorScheme.swift` with `sourceColor()`/`neededColor()`
- Removed duplicated color functions from `SpotListView`, `BandMapView`, `SpotDetailInspector`

### 2C. Extract `TuneAndLogHelper` (CWSweep) ✅
- Created `RadioManager+Tune.swift` extension with `tuneToSpot()` method
- Updated `SpotListView`, `BandMapView`, `ClusterView` to use shared method

### 2D. Extract Radio Protocol `extractResponses()` ✅
- Created `TextProtocolParser.swift` in CarrierWaveCore
- `KenwoodProtocol` and `YaesuProtocol` now delegate to shared implementation

**Phase 2 actual: ~300+ duplicated lines removed**

---

## Phase 3: Cross-App Model Unification ✅

**Status:** Complete (commits `9ef337a`, `7438ee4`, `c646063`)
**Goal:** Move duplicated models and API clients into shared SPM packages so both apps reference a single source of truth.

### 3A. Move Spot Models to CarrierWaveCore ✅
- Moved `SOTASpot`, `WWFFSpot`, `WWFFAgendaItem`, `POTASpot`, `RBNSpot` to CarrierWaveCore
- Placed in CarrierWaveCore (not CarrierWaveData) — pure Codable structs with no SwiftData dependency
- `RBNSpot` standardized on `BandUtilities.deriveBand()` instead of `LoggingSession.bandForFrequency()`
- `POTASpot.ageColor` (SwiftUI) kept as iOS app extension
- Deleted all app-local copies; added `import CarrierWaveCore` to 12 consumer files
- **Deferred:** `SpotRegion`, `EnrichedSpot`, `SpotSummary` — app-specific type dependencies

### 3B. Move Spot API Clients to CarrierWaveCore ✅
- Moved `SOTAClient`, `WWFFClient`, `Ham365Client` to CarrierWaveCore
- `WWFFClient` is superset including agenda methods from iOS
- **Deferred:** `HamDBClient` — has app-specific extensions

### 3C. Move `FullADIFExportActor` to CarrierWaveData ✅
- Created `ADIFExportConfig` struct for app-specific branding (appName, filenamePrefix, appFieldPrefix)
- Moved unified implementation to CarrierWaveData
- Updated callsites in both apps to pass config

**Phase 3 actual: ~2,100 lines removed (net -1,262 lines in main commit)**

---

## Phase 4: Generic iOS Refactors — Entry Fields, Stats, Views ✅

**Status:** Complete
**Goal:** Replace copy-paste patterns in iOS with generic/parameterized implementations.

### 4A. Generic `SingleReferenceEntryField` and `ReferenceChip` ✅
- Created `SingleReferenceEntryField<PickerContent>` with `ReferenceEntryConfig` for label, placeholder, color, cache closures
- Created `ReferenceChip` generic component replacing identical `SummitChip` and `WWFFChip`
- `SummitEntryField` and `WWFFReferenceEntryField` become thin wrappers (~50 lines each vs ~230)
- `ParkEntryField` kept separate (multi-value is fundamentally different architecture)
- ~200 duplicated lines eliminated

### 4B. Generic `ReferenceStatsLoader` ✅
- Created `ReferenceStatsLoader` actor in CarrierWaveData with `ReferenceField` enum
- Created shared `ReferenceStats` struct replacing `ParkStats`, `SummitStats`, `WWFFRefStats`
- Single `loadStats(container:field:)` method replaces three identical private actors
- ~170 duplicated lines eliminated

### 4C. Consolidate Panel/Sidebar Spot Views ✅
- Merged `POTASpotsView` + `SidebarPOTASpotsView` into single view with `POTASpotsDisplayMode` (.panel/.sidebar)
- Merged `RBNPanelView` + `SidebarRBNSpotsView` into single view with `RBNDisplayMode` (.panel/.sidebar)
- Merged `POTASpotsView+Clubs.swift` + `SidebarPOTASpotsView+Clubs.swift` into single extension
- Deleted `SidebarPOTASpotsView.swift`, `SidebarPOTASpotsView+Clubs.swift`, `SidebarRBNSpotsView.swift`
- Updated call sites in `LoggerSpotsSidebarView` to pass `displayMode: .sidebar`
- ~600 duplicated lines eliminated

### 4D. Consolidate Spot Row Badges ✅
- Extracted `WorkedBeforeBadges` shared view component taking band, mode, and workedResult
- `POTASpotRow` and `SOTASpotRow` now delegate to shared component
- ~60 duplicated lines eliminated

**Phase 4 actual: ~1,030 duplicated lines removed**

---

## Phase 5: CWSweep Internal & Layout Refactors ✅

**Status:** Complete
**Goal:** Clean up CWSweep-internal duplication.

### 5A. Extract `HTTPSpotClient` Base Actor — Deferred ⏭️
- **Evaluated and deferred**: POTASpotsClient (62 lines), RBNClient (149 lines with unique rate limiting), HamDBClient (119 lines, license lookup not spot client) are too different for a meaningful base class. SOTA/WWFF clients already moved to CarrierWaveCore in Phase 3. Shared boilerplate is only ~15 lines across 3 very different clients — extraction would add complexity for minimal dedup.

### 5B. Consolidate Cluster Table Columns — Deferred ⏭️
- **Evaluated and deferred**: `smartSpotTableView` (8 columns) and `spotTableView` (6 columns) share 6 identical column definitions. However, SwiftUI's `@TableColumnBuilder` doesn't support conditional column inclusion — tables with different column counts produce different static types. Consolidation would require type erasure (`AnyView`), which is worse than the duplication.

### 5C. Extract Filter Bar / Band Picker Component ✅
- Created `SpotFilterComponents.swift` in CWSweep/Utilities with:
  - `SpotFilterConstants.commonBands` — shared band list (was duplicated in SpotListView and ClusterView)
  - `BandFilterPicker` — reusable band filter picker with "All" option
  - `ModeFilterPicker` — reusable mode filter picker (segmented CW/Phone/Digital/All)
  - `SpotSearchField` — reusable search field with magnifying glass icon, optional clear button
- Updated SpotListView and ClusterView to use shared components
- ~50 duplicated lines eliminated

### 5D. Evaluate Role Layout Scaffold Extraction — Deferred ⏭️
- **Evaluated and deferred**: Casual (21 lines), Hunter (32), DXer (31) are already minimal compositions. Contester (214 lines) and Activator (162 lines) have complex unique logic (contest state, activation header). Abstracting a common scaffold would not reduce meaningful duplication.

**Phase 5 actual: ~50 duplicated lines removed; 3 sub-tasks deferred after evaluation (insufficient ROI)**

---

## Phase 6: Structural Refactors — Generic Services ✅

**Status:** Complete (6A implemented; 6B-6D deferred after evaluation)
**Goal:** The largest refactors — generic base types for services with significant boilerplate.

### 6A. Shared `ReferenceCacheSupport` Infrastructure ✅
- Created `ReferenceCacheSupport.swift` with shared types:
  - `ReferenceCacheStatus` enum (replaced 3 per-cache status enums)
  - `ReferenceCacheMetadata` + `ReferenceCacheConfig` structs
  - `ReferenceCacheDiskIO` (disk load/save, download, staleness check)
  - `NameIndexSearch` (binary search prefix matching for name indexes)
  - `CSVLineParser` (quoted-field CSV line parser)
  - `HaversineDistance` (great-circle distance calculation)
- All three caches now use config-driven lifecycle
- Updated 3 ExternalDataView sections to use shared status enum
- ~300 duplicated lines eliminated

### 6B. Generic `BatchedRepairService<T>` Base Actor — Deferred ⏭️
- **Evaluated and deferred**: 8 standalone repair actors share identical batching boilerplate (~40-50 lines each). However, the remaining 8 files are QSOProcessingActor extensions (different async pattern with fresh context per batch + Task.checkCancellation), utility enums, and delegation wrappers. A generic base would save ~120-250 net lines but adds abstraction over critical data-mutation code. The risk/complexity outweighs the moderate dedup gains.

### 6C. Generic Upload/Download Orchestration — Deferred ⏭️
- **Evaluated and deferred**: Upload/download phases across sync services have similar structure but highly service-specific error handling, retry logic, and state transitions. Abstracting would obscure the per-service behavior that's critical for debugging sync issues. High risk for moderate gain.

### 6D. Unified `CTYCacheActor` in CarrierWaveData — Deferred ⏭️
- **Evaluated and deferred**: CTYService (iOS, 147 lines) and DXCCLookupService (macOS, 105 lines) have different concurrency models (actor vs @MainActor @Observable), different loading strategies (download-first vs bundle-first), different cache policies (7-day vs 30-day), and different cache directories. Unifying would add more complexity than it removes from 252 total lines.

**Phase 6 actual: ~300 duplicated lines removed; 3 sub-tasks deferred after evaluation (insufficient ROI or excessive risk)**

---

## Execution Notes

### Phasing Rationale
- **Phases 1-2** are low-risk, independently shippable changes that build confidence
- **Phase 3** is the highest-value work — cross-app dedup prevents divergence going forward
- **Phase 4** tackles iOS view-layer duplication that's most likely to grow as programs are added
- **Phase 5** cleans up CWSweep before it accumulates more technical debt
- **Phase 6** is the most complex but addresses systemic patterns across many services

### Quality Gates
Each phase should:
1. Pass `xc quality` (format + lint + build) after completion
2. Run unit tests (`xc test-unit`, `xc test-core`) with no regressions
3. Be committed as a logical unit (one commit per sub-task or per phase)

### Risk Mitigation
- **Phase 3** (cross-app models): Test both iOS and CWSweep builds after each model migration
- **Phase 4C** (panel/sidebar consolidation): Visually verify both display modes
- **Phase 6B** (repair services): The 11 repair services are critical infrastructure — refactor one first as a template, then apply to the rest
- **Phase 6C** (sync orchestration): Most risk — sync bugs are hard to diagnose. Extra testing around upload/download flows

### Overall Results
- **Phases 1-6:** ~2,480+ duplicated lines removed across 6 phases
- **10 sub-tasks completed**, 7 sub-tasks deferred after evaluation (insufficient ROI)
- **New shared infrastructure:** ReferenceCacheSupport, ReferenceStatsLoader, SingleReferenceEntryField, WorkedBeforeBadges, SpotFilterComponents, SpotColorScheme, TextProtocolParser, BadgePillModifier, QSOMode, ADIFExportConfig
- **Models unified:** SOTASpot, WWFFSpot, POTASpot, RBNSpot, SDRTranscriptModels, FullADIFExportActor all moved to shared packages

### What's Explicitly Out of Scope
- `SyncService+ProcessLegacy.swift` — still contains active reconciliation logic, leave until legacy sync is fully retired
- `UnifiedSpot` adoption in iOS — only worth doing if iOS spot handling is refactored (evaluate after Phase 4C)
- The 10 potentially unused views — verify manually before removing; some may be referenced via SwiftUI's type-based navigation
