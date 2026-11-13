## Privacy & Compliance
| File | Purpose |
|------|---------|
| `CarrierWave/PrivacyInfo.xcprivacy` | Privacy manifest for main app target (UserDefaults, no tracking) |
| `CarrierWaveWidgets/PrivacyInfo.xcprivacy` | Privacy manifest for widget target (UserDefaults, no tracking) |

## Entry Points
| File | Purpose |
|------|---------|
| `CarrierWave/CarrierWaveApp.swift` | App entry point, SwiftData container setup |
| `CarrierWave/AppDelegate.swift` | UIApplicationDelegate: remote notifications, memory-warning cache purge, temporary orientation lock (satellite pointing) |
| `CarrierWave/AppSchema.swift` | Single deduplicated SwiftData model list (shared + iOS-only) for the app container and tests |
| `CarrierWave/CarrierWaveApp+ContainerSetup.swift` | ModelContainer creation, ContainerInitFailureRecord persistence, recovery-mode routing |
| `CarrierWave/CarrierWaveApp+Wsjtx.swift` | Launch hook for the WSJT-X listener (CAR-282): attaches `WsjtxFieldService` to the container and starts it if enabled; the `.active` scene branch re-runs `startIfEnabled` after a background suspend |
| `CarrierWave/ContentView.swift` | Root TabView/NavigationSplitView for programmatic tab switching |
| `CarrierWave/Views/LazyTabContent.swift` | Defers tab content creation until first appearance for lazy loading |
| `CarrierWave/TabConfiguration.swift` | AppTab enum, TabConfiguration manager, SettingsDestination, tab migration |

## Models (`swift/ios/CarrierWave/Models/`)
| File | Purpose |
|------|---------|
| `QSO.swift` | Core contact record (callsign, band, mode, timestamps, grid, park ref) |
| `QSO+Dedup.swift` | QSO deduplication key using ModeEquivalence from CarrierWaveCore |
| `QSO+ServicePresence.swift` | Service presence helpers (mark present, needs upload, rejected) |
| `QSO+POTAPresence.swift` | Per-park POTA presence tracking for two-fer activations |
| `UploadDestination.swift` | Sync target configuration (enabled flag, last sync timestamp) |
| `POTAJob.swift` | POTA job tracking, status, details models (POTAJob, POTAJobsPage — legacy array or paginated `/user/jobs`, POTAJobDetails, POTAJobStatus) |
| `POTALogEntry.swift` | Individual POTA log entries |
| `POTAUploadAttempt.swift` | POTA upload attempt history and status |
| `ServicePresence.swift` | Service connection status tracking |
| `ActivationMetadata.swift` | Activation-level metadata storage |
| `ActivationStatistics.swift` | Pure stats computation for POTA activations (distance, timing, distribution, RST, entities) |
| `StatCategoryItem.swift` | Individual stat item for dashboard display |
| `StatCategoryType.swift` | Stat category enum (band, mode, DXCC, etc.) |
| `StatsReport.swift` | Codable diagnostic bundle for stats accuracy reporting |
| `StatExplanation.swift` | Lightweight stat count breakdown for "explain this number" popovers; also contains `StatMethodology` for structured "What's This?" explanations |
| `NeedTypes.swift` | Smart spot recommendation types: NeedCategory, NeedPriority, MatchedNeed, NeedsSnapshot, DXCCNeeds, WASNeeds, POTAHunterNeeds, WWFFHunterNeeds, CustomNeedPattern |
| `CustomNeed.swift` | SwiftData model for user-defined needs (callsign/state/park patterns) |
| `Types.swift` | Shared type definitions |
| `OperatorRole.swift` | Operator persona enum (activator/hunter/mixed/newcomer) — canonical `operatorRole` key for role-aware defaults; set in onboarding, changeable in Settings → My Profile *or* Settings → Logger → Operating Style; drives Hunter Log landing, On Air card section suppression, session-wizard ordering, and quick-start prominence |
| `ActiveStation.swift` | Unified on-air station model (POTA spots + RBN) |
| `POTAActivation.swift` | POTA activation grouping view model |
| `BragSheetSource.swift` | Program-neutral input for the activation share card — drives POTA, SOTA, dual, and casual brag-sheet renders |
| `POTAActivation+UploadSnapshot.swift` | Pre-computes per-activation upload status from QSO.servicePresence so view body never traverses SwiftData |
| `SavedSessionTemplate.swift` | User-saved session templates with JSON persistence via UserDefaults |
| `POTAAwards.swift` | POTA activator award tier definitions (8 categories: unique parks, DX, rover, etc.) |
| `POTAAwards+Methodology.swift` | Detailed "What's This?" explanations for each POTA award category |
| `POTAAwardsActor.swift` | Background actor for POTA awards computation (fetches QSO snapshots off main thread) |
| `POTAAwardsComputation.swift` | Pure computation logic for POTA award progress from activation data |
| `TourState.swift` | UserDefaults-backed tour progress tracking |
| `StreakInfo.swift` | Streak data model and calculation utilities (`StreakCategory` incl. `.amtPractice`) |
| `AMTStreakInfo.swift` | `AMTService.streakInfo` — the Another Morse Trainer practice streak as a dashboard `StreakInfo` (local-calendar dates) |
| `DashboardMetricType.swift` | Dashboard metric type enum, display properties, MetricDisplayValue |
| `ActivityProgram.swift` | Activity program registry model (ActivityProgram, ProgramCapability, ADIFFieldMapping) |
| `ActivityType.swift` | Activity type enum with icons and display names |
| `Friendship.swift` | Friend connection model with status tracking |
| `FriendSuggestion.swift` | Friend suggestion models (DismissedSuggestion, FriendSuggestion, DTO) |
| `Club.swift` | Club and ClubMember SwiftData models with server sync |
| `ActivityItem.swift` | Activity feed item model |
| `CWConversation.swift` | CW conversation and message models for chat display |
| `CallsignInfo.swift` | Callsign lookup result with name, note, emoji, source |
| `LoggingSession.swift` | Logging session model with activation type, frequency, mode, equipment |
| `LoggingSession+Types.swift` | POTASpotComment and RoveStop types used by LoggingSession |
| `LoggingSession+MultiOp.swift` | Multi-operator computed properties (operatorCallsigns, isMultiOp, allOperatorCallsigns) |
| `LoggingSession+Frequencies.swift` | Static frequency maps, band derivation, computed display properties |
| `RoveStop.swift` | Codable model for individual park stops within a POTA rove session |
| `QSYLogConfirmation.swift` | QSY log confirmation data struct for qsy://log URI review sheet |
| `LoggerCommand.swift` | Command enum for logger input (FREQ, BAND, MODE, SPOT, QRT, RBN, POTA, P2P, SOLAR, WEATHER, MAP, WEBSDR) |
| `LoggerCommand+Parsing.swift` | Command parsing logic (input string to LoggerCommand, SPOT REPEAT/STOP parsing) |
| `LoggerCommand+Suggestions.swift` | Command autocomplete suggestions and CommandSuggestion type |
| `CallsignNotesSource.swift` | SwiftData model for user-configured callsign notes file sources |
| `BandChartData.swift` | Precomputed chart data model for visual band plan display |
| `UserProfile.swift` | User's amateur radio profile (callsign, name, QTH, grid, license) |
| `SessionSpot.swift` | Persisted RBN/POTA spot recorded during a logging session |
| `SpotQSOMatch.swift` | Cross-references session QSOs and spots by callsign+band for display linking |
| `SpotRegion.swift` | Geographic region classification for spots (SpotRegion, EnrichedSpot, SpotSummary) |
| `ActivityLog.swift` | Activity log SwiftData model for persistent hunter workflow |
| `SOTASummit.swift` | SOTA summit data struct (code, name, altitude, points, coordinates) |
| `WWFFReference.swift` | WWFF directory reference data struct (reference, name, coordinates, country) |
| `WWFFActivation.swift` | WWFF activation grouping by reference/date/callsign with 44-QSO progress tracking |
| `WWFFAwards.swift` | WWFF award tier definitions (activator/hunter references, points, DXCC, continents) |
| `WWFFRepresentative.swift` | WWFF national program representative directory with email compose support |
| `LogSubmissionFlavor.swift` | Per-program (POTA / WWFF / SOTA) descriptor used by SessionADIFExportSheet to detect n-fer programs and produce flavored exports (ADIF or SOTA V2 CSV, MY_SIG, MY_*_REF, filename) |
| `SolarSnapshot.swift` | Hourly solar conditions snapshot from background polling |
| `Contest.swift` | Contest model struct (in-memory only, from WA7BNM RSS feed) |
| `StationProfile.swift` | Station profile struct and UserDefaults-backed storage |
| `ParkBoundary.swift` | Park boundary model + shared GeoJSON geometry types (Polygon/MultiPolygon/GeometryCollection, hole preservation) + `BoundaryFeatureProperties` callout decode; builds from `FfiGeoBoundary` (geometry + `propertiesJson`) |
| `ParkBoundary+Geometry.swift` | Skirt buffer with miter clamping, signed area, zoomed-out spike removal |
| `AdminBoundary.swift` | US state/county boundary model; builds from `FfiGeoBoundary` (kind from the FFI `kind` tag, FIPS-length fallback), outline-only rendering |
| `SOTAZone.swift` | SOTA activation-zone model (reuses `GeoJSONGeometry`/`RingBBox`), filled-polygon rendering; builds from `FfiGeoBoundary` |
| `WWFFRenderItem.swift` | WWFF map-render model: borrowed POTA polygon (via `KFF↔US`) or marker fallback (reuses `ZonePolygon`/`RingBBox`) |
| `MultiplierCandidate.swift` | Flagged multiplier location (POTA+SOTA / POTA+WWFF / county-line) + `MultiplierKind` for the overlap finder |
| `TrailBoundary.swift` | Historic trail model, LineString/MultiLineString geometry; builds from `FfiGeoBoundary` (geometry + `propertiesJson` callout metadata) |

## Brag Sheet Models (`swift/ios/CarrierWave/Models/BragSheet/`)

The brag-sheet catalog / config / periods / presets / stat-value enums moved to shared Rust (`cw-domain::brag_sheet`, exposed as `BragSheetApi` + `FfiBrag*` types). The 6 Swift domain enums and the `BragSheetComputationActor*` compute path were deleted; iOS now routes entirely through the FFI. See `Views/BragSheet/` + `Views/Dashboard/AsyncBragSheetStats.swift`.

## Utilities (`swift/ios/CarrierWave/Utilities/`)
| File | Purpose |
|------|---------|
| `BandColors.swift` | Canonical band-to-color mapping (spectral gradient HF→VHF) |
| `BandUtilities.swift` | Band derivation from frequency and band ordering |
| `CallsignParsing.swift` | Primary-callsign extraction from prefixed/suffixed calls (shared logger + band scope) |
| `ModeColors.swift` | Canonical mode-to-color mapping (CW cyan, phone pink, digital indigo) |
| `FieldGuideLinker.swift` | Match radio names to CW Field Guide IDs and open deep links |
| `FrequencyFormatter.swift` | Frequency formatting with sub-kHz precision support |
| `KeychainHelper.swift` | Secure credential storage |
| `MemberLocationCache.swift` | Actor-based 30-day cache for callsign→coordinate lookups (QRZ/HamDB) |
| `GridLocationService.swift` | One-shot GPS → Maidenhead grid square service (precision honours `GridPrecisionPreference`) |
| `GridPrecisionPreference.swift` | User's preferred Maidenhead grid precision (4 / 6 / 8 chars) |
| `LocationProviding.swift` | Protocol abstracting CLLocationManager for testability |
| `LocationSessionService.swift` | Continuous GPS → Maidenhead grid tracking service |
| `LocationSessionService+Environment.swift` | SwiftUI Environment key for shared location service |
| `ActivityLogManager+GridObservation.swift` | Grid observation extension for ActivityLogManager |
| `CompassHeadingService.swift` | Device compass heading provider for antenna pattern orientation |
| `MaidenheadConverter.swift` | Grid square to coordinate conversion (and reverse) |
| `SunlightMode.swift` | Sunlight mode environment key and view modifier for outdoor visibility |
| `EquipmentStorage.swift` | iOS-specific extension for recovering equipment lists from session history (core types in CarrierWaveData) |
| `SessionPhotoManager.swift` | Session photo file save/load/delete (JPEG in Documents/SessionPhotos/) |
| `USStates.swift` | US state abbreviation-to-name lookup for accessibility labels |
| `LandscapeAdaptiveDetents.swift` | ViewModifier that switches sheet detents for landscape (portrait `.medium` → landscape `.large`) |
| `OrientationProfileModifier.swift` | `.orientationProfiled()` modifier — records size class transitions to profiler |
| `ViewProfileModifier.swift` | `.viewProfiled("name")` modifier — records view appear/disappear to profiler |

## Tests (`swift/ios/CarrierWaveTests/`)
| File | Purpose |
|------|---------|
| `CarrierWaveTests.swift` | Main test file placeholder |
| `ADIFParserTests.swift` | ADIF parsing tests |
| `ADIFExportServiceSplitTests.swift` | N-fer ADIF split export tests (5-fer = 5 files, 3-fer = 3 files) |
| `DeduplicationServiceTests.swift` | QSO deduplication logic tests |
| `POTAJobsPageTests.swift` | `/user/jobs` decoding: legacy array vs paginated `{count, entries}` |
| `ImportServiceTests.swift` | Import service tests |
| `WsjtxFieldServiceTests.swift` | Field WSJT-X adapter (CAR-282): upload markers from the injected target resolver, active-session attach + POTA hand-off, re-broadcast adds no markers, experiment gate blocks `startIfEnabled` — no socket |
| `LoFiClientTests.swift` | LoFi client tests |
| `QRZClientTests.swift` | QRZ client tests |
| `QRZLogbookCallsignMismatchTests.swift` | Pure `QRZClient.logbookMismatch` rule behind the "no QRZ logbook for your callsign" notice (primary/secondary/base-callsign match, normalization, empty cases) |
| `SOTAClientTests.swift` | SOTASpot JSON decoding, computed properties (frequency, timestamp, summit reference) |
| `LocationSessionServiceTests.swift` | Unit tests for LocationSessionService with mock provider |
| `LoggingSessionManagerTests.swift` | Session lifecycle, query, and title tests |
| `LoggingSessionManagerTests+QSOLogging.swift` | QSO logging, frequency/mode/park updates, and notes tests |
| `LoggingSessionManagerTests+Spotting.swift` | Self-spot frequency selection: hunt tunes never move the frequency re-spots advertise (CAR-296) |
| `LoggingSessionManagerTests+HiddenQSOs.swift` | Hidden QSO handling tests |
| `LoggingSessionTests.swift` | LoggingSession model tests (init, state, band derivation, duration) |
| `LoggingSessionTests+DisplayAndPersistence.swift` | Display title, activation ref, frequency, suggested frequencies, persistence tests |
| `LoggingSessionRoveTests.swift` | LoggingSession rove accessor and lifecycle tests |
| `SessionsListGroupingTests.swift` | Pure `SessionsListGroupingActor.monthGroups` tests: newest-first order, stable ties, UTC month bucketing, legacy row IDs |
| `RoveStopTests.swift` | RoveStop Codable round-trip and computed property tests |
| `ServicePresenceTests.swift` | Service presence and upload marking edge case tests |
| `MetadataModeTests.swift` | WEATHER/SOLAR/NOTE metadata mode filtering tests |
| `DXCCTests.swift` | DXCC extraction, QRZ import, and repair task tests |
| `QuickEntryParserTests.swift` | Quick entry parser unit tests (callsign, RST, park, grid, state detection) |
| `QuickEntryParserIntegrationTests.swift` | Quick entry parser integration tests (full parsing, token preview) |
| `WebSDRRecordingTests.swift` | WebSDR recording query helper tests |
| `SDRParameterTrackingTests.swift` | SDR parameter change tracking, segment computation, and persistence tests |
| `EquipmentStorageTests.swift` | Equipment storage CRUD and isolation tests |
| `SettingsSyncServiceTests.swift` | iCloud KVS settings sync registry and type encoding tests |
| `UserProfileCallsignChangeTests.swift` | CAR-349: callsign change survives relaunch; QRZ-detected retired callsign is ignored; switch-back leaves previous list |
| `SessionPhotoManagerTests.swift` | Session photo file management tests |
| `Helpers/QSOFactory.swift` | Synthetic QSO generator for testing (duplicates, metadata, edge cases) |
| `Helpers/TestModelContainer.swift` | Shared test infrastructure for SwiftData tests |
| `CommentParkRefRepairServiceTests.swift` | Comment park ref backfill predicate regression and logic tests |
| `OPPrefixBackfillServiceTests.swift` | CAR-258 `OP:` prefix strip logic + backfill end-to-end tests |
| `HuntingParkRefRepairServiceTests.swift` | Hunting park ref repair: rawADIF detection and notes-matching tests |
| `KIndexRepairServiceTests.swift` | K-index repair service tests (cutoff date, field preservation) |
| `BackupServiceTests.swift` | Backup service tests (snapshot, manifest, integrity, restore marker) |
| `BandPlanServiceTests.swift` | Band plan validation tests (license class privileges) |
| `FT8DecodeEnricherTests.swift` | FT8 decode enricher unit tests (entity, distance, dupe, new DXCC, section classification) |
| `FT8IntegrationTests.swift` | FT8 end-to-end integration tests (QSO creation, dB reports, POTA park reference) |
| `PerformanceTests/QSOStatisticsPerformanceTests.swift` | Performance regression tests (50k/500k QSOs) |
| `VideoExport/VideoEventSequencerTests.swift` | Tests for VideoEventSequencer timeline construction and time compression |
| `CloudSyncEventTests.swift` | Tests for CloudSyncEvent Codable and CloudSyncSummary computation |
| `CloudSyncEventLogTests.swift` | Tests for CloudSyncEventLog persistence and pruning |
| `SatNOGSClientTests.swift` | SatNOGS TLE JSON decode + cache Codable round-trip tests |


## Pointers

- Services: `swift/ios/CarrierWave/Services/FILE_INDEX.md`
- Views: `swift/ios/CarrierWave/Views/FILE_INDEX.md`
