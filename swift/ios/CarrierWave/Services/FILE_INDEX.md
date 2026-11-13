## Brag Sheet Services (`swift/ios/CarrierWave/Services/BragSheet/`)
| File | Purpose |
|------|---------|
| `BragSheetSnapshot.swift` | Lightweight Sendable QSO snapshot — now used only to feed the share-card map + statistician section (stat values come from Rust `BragSheetApi`) |
| `ContinentMapper.swift` | DXCC entity number to continent mapping (used by the snapshot) |

> The `BragSheetComputationActor*` compute path was deleted — brag stats now compute in shared Rust via `BragSheetApi` (see `Views/Dashboard/AsyncBragSheetStats.swift`).

## Services (`swift/ios/CarrierWave/Services/`)
| File | Purpose |
|------|---------|
| `DaySummaryDataActor.swift` | Background actor that pages QSOs and overlapping `LoggingSession`s for a UTC day and builds a `DaySummarySnapshot`. Consumed by `DaySummaryView` |
| `WsjtxFieldService.swift` | @MainActor @Observable singleton owning Field's `WsjtxIngestService` (CarrierWaveData, CAR-282): binds `0.0.0.0` by default, `commit` marks upload targets (`uploadTargets` resolver, default = `LoggingSessionManager.markForUpload` rules: QRZ/LoFi/Club Log when configured, POTA only in a POTA session) then `QSOWriteSink.commitUpsertBatch`; `onQSOLogged` appends to `QSOLedger` + posts `.didLogQSO`; `startIfEnabled` gated by the `.wsjtx` experiment. Also `DeviceIPv4.addresses()` (getifaddrs, `en0` first) for the settings screen |
| `SatelliteTrackerModel.swift` | @MainActor @Observable view model over the shared Rust engine (`SatelliteApi`): cache-first `load` (engine `loadCached` renders immediately, `refresh` runs in the background; only a cold cache or a forced Refresh waits on the network), engine-side cache-through refresh + catalog (workability/display names/transmitter ordering all in Rust), positions synced off-main every 5s (map dead-reckons between syncs), observer-relative az/el via `FfiObserver`, per-NORAD transmitters/AMSAT/polarization from cached `FfiSatelliteSummary`s, forward ground track (rebuilt on selection / every 60s, never per tick) |
| `SatelliteTrackerModel+Passes.swift` | Pass/mutual accessors over the engine's async FFI: `passForecast(for:)` (48h/12), `passes(for:from:to:)` (windowed, past or future), `upcomingPasses(withinHours:)`, `mutualPasses(with:modes:)` (24h, mode-category filter), `mutualProfileSamples(for:other:)`; `SatelliteSkySample` + `skyArc(for:from:)` — one above-horizon stretch as 30 s az/el samples from the engine ground track (from a pass AOS), cut at the first horizon crossing, for the pointing screen's pass plot |
| `SatelliteEngine.swift` | Shared `SatelliteApi` over the app's FieldStore (EquipmentProvider pattern: lazily built behind an actor, activities base URL from `ActivitiesClient`) — the same Rust engine Android runs |
| `AntennaMotionService.swift` | @MainActor @Observable CoreMotion attitude publisher (true-north frame, magnetic fallback) for the Satellites sky dome + pointing mode — back-camera pointing elevation (tilt-up trigger) and azimuth (compass tape), element-tilt polarization roll, blended screen heading |
| `SatelliteWorkability.swift` | UI-side pass-quality thresholds only (10° workable floor, 20° recommendation, marginal label, shared filter key) — the actual workability gates live in the Rust engine and are applied before the catalog is built |
| `SatelliteTrackerModel+Community.swift` | `communityActivity(force:cellSeconds:)` — the engine's enriched AMSAT activity grid for the current observer + simulated epoch, bridged to `CommunityActivity`; `loadReports(for:)` fills `selectedReports` (reporter marks for the map, previous-orbit line) and, once, the model's `communityActivity` (3 h cells; `selectedCommunityRows` filters it for the info card) on selection, dropping stale results; `submitCommunityReport` files the operator's own observation with AMSAT through the engine (`FfiCommunityReportSubmission` → `CommunityReportReceipt`) |
| `SatelliteCommunityTypes.swift` | Value types for the community-activity grid bridged from `FfiCommunityActivity`: `CommunityActivity` (window, cell width, `cellStart(newestFirst:)`), `CommunityActivityRow` (AMSAT name/base/capability, catalog identity, matched SatNOGS transmitter, next pass, own QSO count, buckets), `CommunityActivityBucket` (+ `quiet(at:)`), `CommunityActivityStatus` (AMSAT legend + `isPositive`); `CommunityReports`/`CommunityReport`/`ReporterMark`/`PreviousOrbitSummary` (placed reports, prefix list, "Heard by N on the previous orbit" line); `CommunityViewport` (continuous visible slice shared by the strips: `zoomed(by:anchor:)` keeps the date under the pinch fixed, `panned(byFraction:)`, `fraction(of:)`, 6 h minimum span); `SatelliteModeCategory.init(ffi:)`; `CommunityReportReceipt` (AMSAT's acknowledgement of a filed report) |
| `SatelliteTypes.swift` | Shared satellite value types bridged from the engine's FFI records: `SatellitePosition`/`SatelliteLook`/`SatelliteSearchItem`, `SatNOGSTransmitter`, `AmsatSatelliteStatus` (+ `dayStatus` legend colour for the last 24 h), `SatellitePass`/`SatellitePassForecast`/`UpcomingSatellitePass`, `MutualPass`/`MutualPassSample`, `SatelliteModeCategory` (+ `.ffi` mapping) |
| `SatelliteDuplexController.swift` | @MainActor @Observable singleton for two-bridge FM satellite duplex: `uplink`/`downlink` `RadioLink`s (own persisted bridge UUIDs, swap), 1 s tick computing Doppler-corrected downlink/uplink from the selected sat's primary transmitter (`primaryTransmitter`/`dopplerFactor` shared with the pointing screen), `auto` (both radios follow prediction) vs `manualDownlink` (read the downlink knob, slave the uplink to the mirrored, frequency-scaled correction), 10 Hz rounding + 100 Hz deadband (Quansheng writes EEPROM per set), per-NORAD uplink CTCSS (`CT`/`OF` raw CAT, built-in SO-50/ISS/AO-91/AO-92/PO-101 defaults) |
| `SatelliteRotatorService.swift` |   singleton owning the app's `TrackerDiscoveryService` (LAN sweep for CSN S.A.T. / WA4MCM PSR-100 / rotctld) and `RotatorController` (link + explicit follow mode) from CarrierWaveData, plus the 1 s feed loop: while a rotator is linked, `setTarget` from the selected satellite's live az/el when above the horizon, else pre-position to the next pass's rise azimuth at 0° el within 5 min of AOS (per-NORAD `passForecast` cached 60 s); `autoDetect: TrackerAutoDetector` (`startDetection(model:)`/`stopDetection()` while the satellites tab is up, `acceptDetected(model:)` from the detection alert), `desiredTarget`/`desiredTargetSource` computed every second whether or not a rotator is linked (pushed to the rotator only when linked), `connectSavedIfNeeded()` (once per launch), `connect(to:model:)`, `disconnect()`, `isFollowing`, `statusLine` ("S.A.T. · tracking · 214° / 38°"); `TrackerKind.shortLabel` |
| `SessionLateEntryService.swift` | Add a QSO to an already-ended session without reopening it: `parse`/`tokens` (logger quick-entry grammar, bare callsign allowed), `timestamp` (Zulu time resolved on the session's UTC day, else `endedAt`), `log` (shared Rust `SessionApi.logQso` + reflect + `WsjtxFieldService.defaultUploadTargets` marking + ledger/`.didLogQSO`), `enrich` (post-log callsign lookup fill, HUNT-style) |
| `SatelliteQuickLogService.swift` | Post-LOS satellite logging: born-completed session (invisible to `fetch_current_session` — never disturbs an active activation) + per-contact `SessionApi.logQso` with forced `satName`/`propMode="SAT"` and `timestampOverride`; Swift-side upload marking (QRZ/LoFi/ClubLog, never POTA) |
| `FavoriteSatellitesStore.swift` | `@Observable` singleton of favorited NORAD IDs (UserDefaults JSON); `onChange` drives the alert scheduler; first-ever favorite auto-enables alerts + requests notification permission |
| `SatellitePassAlertScheduler.swift` | `@MainActor` singleton scheduling `UNCalendarNotificationTrigger` pass alerts for favorites, headless of `SatelliteTrackerModel`: engine `refresh` (cache-through, stale fallback) + `plan_alerts` (identifiers/fire times/copy all Rust-side, `satpass-` prefix); idempotent identifier reconcile; also auto-starts/ends the pass Live Activity in foreground |
| `SatellitePassBackgroundRefresh.swift` | `BGAppRefreshTask` (`…satellite-pass-refresh`, 6 h cadence) re-running the alert scheduler while the app is closed; gated on alerts-enabled + favorites; same once-only-completion shape as `SyncBackgroundRefresh` |
| `SatellitePassActivityController.swift` | Lifecycle for the pass-countdown Live Activity (`SatellitePassAttributes`): start from notification-tap userInfo or the foreground imminence check, `staleDate=LOS`, end-if-past + stale cleanup |
| `SatellitePassActivityAttributes.swift` | ActivityKit attributes for the pass countdown (mirrored byte-identically in `swift/widgets/`); date-driven ContentState never updates mid-pass |
| `SatellitePassRecording.swift` | Pass-recording model (audio file + tap-mark offsets) + `SatellitePassRecordingStore`: sidecar-JSON persistence in Application Support (backup-excluded), 45-min `latest()` window for the quick log, 7-day prune; injectable dir+clock for tests |
| `SatellitePassRecorder.swift` | `@Observable` mic recorder for P3 capture: voice-grade AAC via `AVAudioRecorder`, tap `mark()` timestamps, permission-denied state; foreground-only (no background-audio mode), stops when pointing mode closes |
| `DaySummarySnapshot.swift` | Sendable snapshot types for the day view: `DaySummarySnapshot`, `SessionCardData`, `DaySummaryQSO`, `SessionFacts`, `ContinuationBadge`, `SessionTypeIcon`, band/mode counts |
| `QRZClient.swift` | QRZ.com API client (session auth) |
| `QRZClient+ADIF.swift` | QRZ ADIF upload extension |
| `QRZClient+Upload.swift` | QRZ upload execution, response logging, PARTIAL result handling |
| `QRZClient+Fetch.swift` | QRZ fetch helpers (request building, pagination, decoding) |
| `QRZClient+Mappings.swift` | QRZ callsign-to-API-key mapping CRUD, migration from single key; `QRZLogbookCallsignMismatch` + `logbookMismatch()` (current callsign has no key → settings notice) |
| `POTAClient.swift` | POTA API client (bearer token auth) |
| `POTAClient+Upload.swift` | POTA multipart ADIF upload |
| `POTAClient+ADIF.swift` | POTA ADIF formatting |
| `SOTACSVExporter.swift` | SOTA database V2 CSV row generator + `ShareableSOTACSV` transferable for session ADIF export pull-up |
| `POTAClient+GridLookup.swift` | POTA grid square lookup |
| `POTAClient+Checkpoint.swift` | POTA resumable download checkpoints and incremental sync state |
| `POTAClient+Adaptive.swift` | POTA adaptive batch processing for rate limiting |
| `POTAClient+Audit.swift` | POTA download audit: per-activation QSO count, mode, timestamp, and dedup checks |
| `POTAClient+Jobs.swift` | POTA upload job status (pages through `/user/jobs?showAll=1&page=&size=`, legacy array tolerated) and job details fetching |
| `POTAClient+ParkDetail.swift` | Public POTA park stats, leaderboard, and activations API models + loader |
| `POTAParksCache.swift` | POTA park in-memory query surface hydrated from the Rust core (`ReferenceDataApi` owns download/parse/storage; name lookup, search, nearby) |
| `SOTASummitsCache.swift` | SOTA summit code to name lookup cache (30-day TTL) |
| `SOTASummitsCache+Parsing.swift` | SOTA CSV parsing, name index building, and distance utilities |
| `SOTAZonesCache.swift` | SOTA activation-zone in-memory polygon surface hydrated from the Rust core (`ReferenceDataApi` owns the chunked download + `sota_zone` storage; decodes stored GeoJSON, surfaces pending-compute count) |
| `WWFFReferencesCache.swift` | WWFF reference directory in-memory query surface hydrated from the Rust core (`ReferenceDataApi` owns download/parse/storage; full-text search, nearby lookup) |
| `WWFFReferencesCache+Parsing.swift` | WWFF name index building for full-text search |
| `ReferenceCacheSupport.swift` | Shared query-side helpers for reference caches: status enum, name index search, haversine (download/parse/persistence moved to Rust `ReferenceDataApi`) |
| `ReferenceDataProvider.swift` | `ReferenceData.api()` holder for the shared Rust `ReferenceDataApi` (External Data downloads over FieldStore; FCC SQLite dir = ApplicationSupport/FCC) |
| `EquipmentProvider.swift` | `Equipment.api()`/`Equipment.loadouts()` holders for the shared Rust `EquipmentApi` + `LoadoutStore`; off-main catalog search + add-item helpers |
| `LoadoutMigration.swift` | One-time non-destructive copy of UserDefaults `SavedSessionTemplate` loadouts into the Rust `loadout` table (keeps the UserDefaults copy) |
| `ProgramCrossReferenceService.swift` | Cross-reference matching between POTA/WWFF/SOTA (number + name matching) |
| `POTAAuthService.swift` | POTA OAuth flow handling (main service) |
| `POTAAuthService+JavaScript.swift` | JavaScript helpers for POTA WebView auth |
| `POTAAuthService+HeadlessAuth.swift` | Headless authentication with stored credentials |
| `LoFiModels+QSOHelpers.swift` | LoFi QSO convenience properties (theirCall, timestamp, etc.) |
| `LoFi/KeychainCredentialStore.swift` | LoFiCredentialStore adapter wrapping KeychainHelper |
| `LoFi/SyncDebugLogAdapter.swift` | LoFiLogger adapter wrapping SyncDebugLog |
| `LoFi/LoFiClient+App.swift` | Convenience LoFiClient.appDefault() factory |
| `LoTWClient.swift` | LoTW API client (download-only, username/password auth) |
| `LoTWClient+Parsing.swift` | LoTW ADIF parsing methods |
| `LoTWClient+Adaptive.swift` | LoTW adaptive date windowing for rate limiting |
| `LoTWClient+Confirmations.swift` | LoTW QSL confirmation fetch (qso_qslsince query) |
| `LoTWError.swift` | LoTW-specific errors |
| `HAMRSClient.swift` | HAMRS sync client |
| `HAMRSModels.swift` | HAMRS API models |
| `HAMRSError.swift` | HAMRS-specific errors |
| `ClubLogClient.swift` | Club Log API client (email/password + API key auth, bidirectional ADIF sync) |
| `ClubLogClient+Helpers.swift` | Club Log ADIF parsing/generation, network helpers, multipart body builder |
| `EQSLClient.swift` | eQSL API client (username/password auth, DownloadInBox/ImportADIF endpoints) |
| `EQSLClient+Helpers.swift` | eQSL ADIF parsing/generation, upload response parsing, network helpers |
| `SCPService.swift` | Super Check Partial database download, cache, and refresh service |
| `CallsignSuggestionProvider.swift` | Merged callsign suggestions from SCP database + active spots |
| `SyncService.swift` | Main sync orchestrator |
| `SyncService+SingleSync.swift` | Per-service sync methods (syncQRZ, syncPOTA, syncLoFi, etc.) |
| `UploadErrorDiagnostic.swift` | Upload error model, ErrorCategory enum for classifying upload failures |
| `UploadErrorClassifier.swift` | Maps service-specific errors to user-facing diagnostics with guidance |
| `UploadDiagnosticStore.swift` | Observable store for upload diagnostics, persisted to UserDefaults |
| `PendingUploadAnalyzer.swift` | Classifies pending QSOs by reason (missing fields, callsign mismatch, etc.) |
| `PendingUploadExporter.swift` | Generates CSV, Markdown, and ADIF exports of pending upload items |
| `SyncService+Upload.swift` | Upload logic for QRZ, POTA, and eQSL services |
| `SyncService+UploadClubLog.swift` | Club Log upload methods (extracted from Upload) |
| `SyncService+UploadEQSL.swift` | eQSL upload orchestration (batch upload with metadata filtering) |
| `SyncService+UploadHelpers.swift` | Shared upload validation and logging helpers |
| `SyncService+POTAUploadDedup.swift` | Pre-upload dedup filter checking QSOs against POTA remote map |
| `SyncService+Download.swift` | Download/import logic |
| `SyncService+ForceRedownload.swift` | Force re-download all QSOs from each service |
| `SyncService+Process.swift` | Async QSO processing during sync (process, reconcile QRZ/POTA presence) |
| `SyncService+ProcessRepairs.swift` | Async repair methods (POTA gaps, orphans, dead state, whitespace, DXCC) |
| `SyncService+ProcessLegacy.swift` | Legacy synchronous QSO processing, merge, and reconciliation |
| `SyncService+Report.swift` | Per-service sync report building |
| `SyncService+Helpers.swift` | Sync helpers (reconciliation, uploads, data repair) |
| `DataRepairService.swift` | One-time data repairs gated by UserDefaults (runs on app launch) |
| `MetadataUploadFlagRepairService.swift` | Clears needsUpload on PoLo metadata pseudo-QSO presence rows; shared by launch repair and per-sync pass (CAR-278) |
| `SyncModels.swift` | Sync result types, progress tracking, per-service sync phase, reports |
| `QSOProcessingActor.swift` | Background actor for QSO processing without blocking UI |
| `QSOProcessingActor+Merge.swift` | QSO merge, creation, and park reference extraction helpers |
| `QSOProcessingActor+DeadStateRepair.swift` | Repair QRZ/POTA dead-state ServicePresence records |
| `QSOProcessingActor+OrphanRepair.swift` | Repair QSOs missing ServicePresence records |
| `QSOProcessingActor+SessionGrouping.swift` | Group orphan POTA QSOs into LoggingSession records |
| `QSOProcessingActor+POTAReconcile.swift` | Reconcile POTA ServicePresence against upload job log |
| `QSOProcessingActor+POTAGapRepair.swift` | Compare local QSOs against POTA remote data, flag missing for re-upload |
| `QSOProcessingActor+DataRepairs.swift` | Callsign whitespace repair and QRZ isSubmitted state repair |
| `BackupService.swift` | Database backup actor (snapshot, manifest, pruning) |
| `BackupService+Restore.swift` | Backup restore, validation, iCloud Drive sync |
| `BackupService+ICloudDownload.swift` | Materialise iCloud Drive backups on new devices before restore (startDownloadingUbiquitousItem + status polling) |
| `StartupProfiler.swift` | Performance profiler: records timestamped milestones during launch and beyond (view renders, tab switches), thread-safe, persists JSON trace |
| `StartupTrace.swift` | Codable trace model (milestones with memory tracking, device info, QSO count, hang stats) and JSON coding helpers |
| `StartupTrace+HangSummary.swift` | Hang summary text generation, phase duration analysis, scaling projection for profiler traces |
| `MainThreadHangDetector.swift` | **Deprecated** — retained for reference; hang detection now handled by MetricKit diagnostics |
| `DeviceMetadata.swift` | Codable device/app metadata struct for MetricKit payload uploads |
| `PerfMetricsSubscriber.swift` | MXMetricManagerSubscriber that receives MetricKit payloads and hands to PerfUploader |
| `PerfUploader.swift` | Actor handling MetricKit payload upload, lifecycle event batching, and offline queue persistence in Caches |
| `SyncDebugLog.swift` | Sync debugging utilities |
| `SyncBackgroundRefresh.swift` | `BGAppRefreshTask` registration + enrollment-gated scheduling for one background server-sync pass (Phase 7.3) |
| `NetworkHealthMonitor.swift` | Tracks network connectivity and degraded states across all services |
| `ImportService.swift` | ADIF parsing, deduplication, QSO creation |
| `ImportService+External.swift` | External file import handling |
| `ImportService+Session.swift` | Session-targeted ADIF import with metadata validation |
| `LogScanning/TextRowGrouper.swift` | Groups Vision OCR observations into text rows by Y-coordinate clustering |
| `LogScanning/TimestampExtractor.swift` | Extracts date/time tokens from scanned log row text |
| `LogScanning/LogPageScanner.swift` | Orchestrator: image → OCR → row grouping → timestamp extraction → quick entry parsing |
| `ADIFParser.swift` | ADIF format parser |
| `ADIFExportService.swift` | Background ADIF generation for activation exports |
| `ADIFExportService+Split.swift` | Split ADIF export: generates multiple files by UTC day, park, and/or operator |
| `ADIFExportService+Session.swift` | Session-aware ADIF export — supports POTA, SOTA, dual POTA+SOTA, and casual sessions (writes MY_SOTA_REF + MY_SIG/MY_POTA_REF) |
| `VideoExport/VideoExportTypes.swift` | Sendable value types for the video export pipeline (config, snapshots, timeline, render state) |
| `VideoExport/VideoEventSequencer.swift` | Builds VideoTimeline from session snapshots with real-time or highlight time compression |
| `VideoExport/VideoLoggerOverlay.swift` | Logger overlay state, corner-region placement scoring, hero-animation timing/interpolation |
| `VideoExport/VideoWriter.swift` | AVAssetWriter wrapper for writing H.264/AAC MP4 from pixel buffers and audio samples |
| `DeduplicationService.swift` | QSO deduplication logic |
| `FetchedQSO.swift` | Intermediate QSO representation during fetch |
| `ActivitiesClient.swift` | Activities API client (auth, register, account management) |
| `ServerSyncHostHooks.swift` | iOS bindings for the shared Carrier Wave Sync code (`CarrierWaveData/ServerSync`): `ServerSyncLog` → `SyncDebugLog`, `SuspensionGuardFactory` → `BackgroundTaskAssertion`, `SyncKeyService.passphraseProvisioner` → `CwStoreKeyRecovery.provision`; installed from `CarrierWaveApp.init`. The key service, OAuth client, secure store, account client, profile types and snapshot coordinator now live in the package |
| `ActivitiesClient+Endpoints.swift` | Activities API endpoints (health check) |
| `ActivitiesError.swift` | Activities-specific errors |
| `BugReportService.swift` | Collects device/app info for bug reports |
| `DiagnosticsCollector.swift` | Diagnostics package builder for recovery-mode "Send Diagnostics" flow |
| `DiagnosticsCollector+Collectors.swift` | Per-area collectors (logs, container failure record, device info) for DiagnosticsCollector |
| `DiagnosticsCollector+Packaging.swift` | Zip/JSON packaging and share-sheet wiring for DiagnosticsCollector |
| `ContestEnrichmentService.swift` | Enriches QSOs with contest metadata (multipliers, exchange, score) for active contest sessions |
| `CWKeyerService.swift` | CW memory keyer slots (1–8) with text storage and bridge keyer command dispatch |
| `PebbleBridgeService.swift` | Localhost HTTP bridge (port 47373) exposing snapshots and POST /v1/qso for the Pebble companion |
| `PebbleBridgeService+HTTP.swift` | Low-level HTTP request/response handling for the Pebble bridge listener |
| `PebbleBridgeService+Routes.swift` | Route handlers for Pebble bridge endpoints (session, solar, spots, log QSO) |
| `SpotFetchLimits.swift` | User-configurable per-source spot fetch caps (Hunt RBN/SOTA, On Air SOTA) with clamped reads from `UserDefaults` |
| `CallsignAliasService.swift` | Manage current and previous callsigns for alias matching |
| `ActivitiesClient+Achievements.swift` | Profile achievements catalog + user awards fetchers + ecosystem-usage signal POST |
| `AchievementSignalService.swift` | Idempotent ecosystem-usage signal dispatcher (watch, pebble, home-screen) |
| `ActivitiesClient+Friends.swift` | Friend API endpoints extension |
| `ActivitiesClient+FriendSuggestions.swift` | Friend suggestion validation API (batch + fallback) |
| `FriendsSyncService.swift` | Friend data synchronization and actions |
| `FriendSuggestionActor.swift` | Background actor for counting QSOs per callsign |
| `FriendSpotNotifier.swift` | Deduped toast + local notification when friends appear in spots |
| `ActivitiesClient+Clubs.swift` | Club API endpoints, DTOs, and member status types |
| `ClubsSyncService.swift` | Club sync (shared singleton), in-memory callsign cache for O(1) lookup |
| `ActivityDetector.swift` | Detect notable activities from QSOs |
| `ActivityDetector+Detection.swift` | Activity detection methods (DXCC, bands, modes, DX, streaks) |
| `ActivitiesClient+Activities.swift` | Activity API endpoints (report, feed) |
| `ActivitiesClient+Programs.swift` | Activity program registry API endpoints |
| `ActivityProgramStore.swift` | Local cache for activity programs with bundled fallback |
| `ActivityReporter.swift` | Report detected activities to server |
| `ActivitiesClient+Telemetry.swift` | Upload error telemetry reporting to activities server |
| `ActivitiesClient+SpotMarkers.swift` | Generate SMS spot markers for off-grid POTA/SOTA spotting via Twilio |
| `SyncService+Activity.swift` | Hook activity detection into sync flow |
| `ActivityFeedSyncService.swift` | Sync activity feed from server |
| `POTAPresenceRepairService.swift` | Detect and fix incorrectly marked POTA service presence (façade over `BatchedRewrite`) |
| `WPMBackfillService.swift` | One-time backfill of average WPM from stored spot comments into ActivationMetadata |
| `ConditionsBackfillService.swift` | One-time backfill parsing text solar/weather into structured ActivationMetadata fields (façade over `BatchedRewrite`) |
| `TwoferDuplicateRepairService.swift` | Detect and merge duplicate QSOs from two-fer park reference mismatches (façade over `CrossBatchMerge`) |
| `CommentParkRefRepairService.swift` | One-time backfill extracting park references from comment/notes into theirParkReference (façade over `BatchedRewrite`) |
| `HuntingParkRefRepairService.swift` | One-time repair moving comment-extracted park refs from parkReference to theirParkReference (façade over `BatchedRewrite`) |
| `DuplicateSpotNoteRepairService.swift` | One-time repair deduplicating repeated spot comments in QSO notes (façade over `BatchedRewrite`) |
| `OPPrefixBackfillService.swift` | One-time backfill stripping legacy `OP: <nickname>` segments from non-user-authored QSO notes (CAR-258, façade over `BatchedRewrite`) |
| `KIndexRepairService.swift` | One-time repair clearing corrupted K-index=0 data from before HamQSL XML fix (façade over `BatchedRewrite`) |
| `ActivityLogQSORepairService.swift` | One-time repair flagging activity log QSOs and fixing misplaced parkReference (façade over `BatchedRewrite`) |
| `PhoneSSBDuplicateRepairService.swift` | One-time repair merging duplicate QSOs from PHONE vs SSB mode mismatch (façade over `CrossBatchMerge`) |
| `ServicePresenceDeduplicationRepairService.swift` | One-time repair deduplicating ServicePresence records from iCloud sync (façade over `CrossBatchMerge`) |
| `POTASplitRepairService.swift` | One-time repair splitting completed POTA sessions that span UTC midnight |
| `CWError.swift` | CW transcription error types |
| `CWAudioCapture.swift` | AVAudioEngine microphone capture for CW decoding |
| `CWSignalProcessorProtocol.swift` | Protocol for signal processors, CWSignalResult struct |
| `GoertzelFilter.swift` | Goertzel algorithm for single-frequency detection |
| `GoertzelThreshold.swift` | Adaptive threshold for key state detection |
| `GoertzelSignalProcessor.swift` | Goertzel-based CW processor with adaptive frequency detection |
| `MorseCode.swift` | Morse code lookup table, timing constants, QSO abbreviations |
| `MorseDecoder.swift` | Timing state machine for dit/dah classification, adaptive WPM |
| `CWTranscriptionService.swift` | CW transcription service: state, properties, public API (start/stop/clear/copy) |
| `CWTranscriptionService+Decoder.swift` | Audio processing, signal decoding, transcript assembly, callsign detection |
| `CWTranscriptionService+SDR.swift` | WebSDR audio input adapter: converts Int16 KiwiSDR frames to CW decoder pipeline |
| `CWConversationTracker.swift` | Track CW conversation turns via frequency and prosign analysis |
| `CallsignChangeGuide.swift` | Pending callsign-change tracking + connected-service checklist builder (QRZ keys/lookup, LoTW, eQSL, Club Log, POTA, LoFi, HamAlert) with keychain-probed auto-verification |
| `CallsignLookupService.swift` | Public API surface: error/result types, in-memory LRU, source helpers (Polo notes, HamDB, FCC), cache management |
| `CallsignLookupService+Lookup.swift` | Lookup orchestration: `lookupWithResult` (single-shot async) + `lookupStream` (cached-first AsyncStream), QRZ-priority merge with HamDB-fill-only-on-nil rule |
| `CallsignLookupService+GridRepair.swift` | Batch grid repair: looks up missing theirGrid via QRZ/HamDB for share cards |
| `CallsignLookupService+QRZ.swift` | QRZ XML callbook API: session auth, callsign lookup, XML parsing |
| `CallsignNotesCache.swift` | Persistent cache for Polo notes (loads from disk, refreshes daily) |
| `CallsignCacheForegroundRefresh.swift` | Foreground staleness re-check for notes/enrichment/QRQ Crew caches |
| `CallsignEnrichmentCache.swift` | Disk-backed cache of server callsign enrichment dataset (CWops + future SKCC); 12h refresh, ETag, sync lookup |
| `ActivitiesClient+CallsignEnrichment.swift` | Activities API endpoints for callsign enrichment dataset + per-callsign lookup |
| `OperatorProfileService.swift` | Local-first operator-profile cache backed by GRDB `operator_profiles`; backfilled from prior QSOs at launch, refreshed by QRZ writebacks (HamDB excluded by design) |
| `Query/QueryStoreBootstrap.swift` | Single shared bring-up site for the GRDB `QueryStore` backing the operator-profile cache |
| `Query/QueryRunnerServices.swift` | `cwquery://` deep-link import shim into the shared saved-query store (query execution moved to the spot engine) |
| `Query/SavedQueryStores.swift` | Factory for the shared `.cwquery` `SavedQueryStore` (iCloud Drive `Documents/Queries`, local fallback) used by the SQL editor, band scope, and spot filter |
| `QRQCrewService.swift` | QRQ Crew membership detection from callsign notes, spot message building |
| `CWSuggestionEngine.swift` | Word suggestion engine with dictionaries and settings |
| `LiveActivityAttributes.swift` | ActivityKit attributes and ContentState for logging session Live Activity |
| `LiveActivityService.swift` | Live Activity lifecycle management (start, update, end, reconnect, cleanup) |
| `LoggingSessionManager.swift` | Session lifecycle management: properties, init, startSession, nextRoveStop |
| `LoggingSessionManager+Helpers.swift` | Internal helpers: save/clear session ID, widget write, notes combine, upload marking |
| `LoggingSessionManager+FrequencyAndMode.swift` | Frequency, mode, title, park reference, and notes updates |
| `LoggingSessionManager+QSOManagement.swift` | Log QSO, hide/unhide, get session QSOs, add/delete photos |
| `LoggingSessionManager+SessionManagement.swift` | End, pause, resume, delete, merge sessions (delegating to `SessionApi` under `.on` via +RustLifecycle) |
| `LoggingSessionManager+SessionQueries.swift` | Fetch active/recent session lists |
| `LoggingSessionManager+RustDelegation.swift` | `.on`-mode `logQSO` delegation to the shared Rust `SessionApi` + reflect |
| `LoggingSessionManager+RustLifecycle.swift` | `.on`-mode lifecycle verb delegation (pause/resume/end/finish/merge/delete) to `SessionApi`: seam pre-flush → Rust verb → mirror-suppressed reflect; end runs split + WPM in Rust |
| `LoggingSessionManager+SeamDelete.swift` | Shared session-delete helpers (hide QSOs, delete spots) + `commitSessionDelete` coordinated multi-entity `SeamWriteBatch` |
| `LoggingSessionManager+Models.swift` | SessionNoteEntry struct, SessionLogEntry enum |
| `LoggingSessionManager+Conditions.swift` | Auto-record solar/weather conditions at POTA session start |
| `LoggingSessionManager+POTASplit.swift` | Split POTA sessions at UTC midnight so each covers one activation date |
| `LoggingSessionManager+UTCDayBoundary.swift` | Real-time UTC midnight monitoring: auto-splits active POTA sessions at day boundary |
| `LoggingSessionManager+LiveActivity.swift` | Live Activity integration hooks (start, update, end, pause, resume) |
| `LoggingSessionManager+SessionActivity.swift` | Report sessionCompleted activity with stats when ending a session |
| `LoggingSessionManager+Spotting.swift` | Spot timer, dispatch, comments polling, QRT spotting (POTA + SOTA) |
| `LoggingSessionManager+SpotDispatch.swift` | Self-spot frequency record (operator's own frequency vs. transient hunt frequency, CAR-296), per-program spot helpers (POTA n-fer, SOTA self-spot), band-plan check, toast presentation |
| `LoggingSessionManager+Continuity.swift` | Auto-continuity: observes CloudKit + LAN active-session notifications, adopts remote-active sessions on most-recent-startedAt rule, broadcasts local changes via `cwLocalActiveSessionChanged` |
| `LoggingSessionManager+SessionLifecycleAPI.swift` | Conformance to the cross-platform `SessionLifecycleAPI` protocol from CarrierWaveData (CAR-276 Sessions unification) |
| `RBNClient.swift` | Vail ReRBN API client for reverse beacon network spots |
| `FreeFrequencyPlanner.swift` | `ActiveSpotsLoader` (loads + dedups live POTA/SOTA/RBN spots) and `FreeFrequencyPlanner` (nestles a free frequency among active stations honoring license + band usage zones). Shared by `FrequencyBandView` and the session wizard's auto-frequency pick |
| `NOAAClient.swift` | NOAA API client for solar conditions and weather |
| `WeatherRadarService.swift` | NWS active-alerts fetcher and NEXRAD CONUS reflectivity tile URL template (Iowa State Mesonet) |
| `POTAClient+Spot.swift` | POTA self-spotting extension |
| `POTAClient+Spots.swift` | POTA spots and spot comments API |
| `TOTAModels.swift` | Tiles on the Air models: errors, spot, activation request/response, activation kind enum |
| `TOTAClient.swift` | Tiles on the Air API client (`x-api-key` auth, shared decoder/encoder, request/response helpers) |
| `TOTAClient+Spots.swift` | TOTA spots fetch (`GET /functions/v1/spots`) — public, optional key for higher rate limit |
| `TOTAClient+Activations.swift` | TOTA activation create (`POST /functions/v1/activations`, JSON) — also acts as self-spot |
| `TOTAClient+Upload.swift` | TOTA ADIF upload (`POST /functions/v1/activations`, multipart `adif` field) |
| `TOTAEnrichmentService.swift` | Bridges LoggingSession → CarrierWaveCore engine: tile recompute, T3 spot snapshot, scoring inputs |
| `TOTAUploadService.swift` | Session-bound TOTA upload helper that persists `totaOfficialPoints` and re-publishes the brag-sheet activity |
| `SpotsService.swift` | Spot model types (`SpotSource`, `UnifiedSpot`) + shared `GridCache`; fetching lives in the Rust engine |
| `SpotCooldownTracker.swift` | Per-callsign cooldown for hunter-initiated "Spot" reposts (with bypass) |
| `P2PService.swift` | Park-to-park discovery via RBN skimmers near user's grid |
| `SpotCommentsService.swift` | Background polling for POTA spot comments |
| `SpotContactValidator.swift` | Spot-vs-QSO callsign mismatch detection (edit distance) |
| `SpotMonitoringService.swift` | Thin adapter over the Rust `SpotEngineApi` (hunter listener + activator per-callsign fetch) |
| `SpotEngine/SpotEngineProvider.swift` | Owns the process-wide `SpotEngineApi`: config, user context, CTY + needs feed, cluster connection, band-scope saved-query filter, lifecycle pause/resume |
| `SpotEngine/SpotQueryQsoMirror.swift` | One-shot batched feed of the newest QSOs into the engine's `qsos` table so editor queries can join the log |
| `SpotEngine/FfiSpotAdapters.swift` | FFI record ↔ app model conversions (`FfiEnrichedSpot` → `UnifiedSpot`/`EnrichedSpot`, `NeedsSnapshot` → FFI) |
| `SpotEngine/FfiSpotAdapters+Legacy.swift` | Engine spot → legacy `POTASpot`/`SOTASpot` reconstruction for OnAirCard/POTASpotsView/S2S rows |
| `WorkedBeforeCache.swift` | Actor-based cache for worked-before spot checking |
| `FT8AudioEngine.swift` | AVAudioEngine actor for FT8 RX/TX audio routing (iOS) |
| `FT8AudioEngine+InputSelection.swift` | Audio input enumeration and selection for FT8 sessions (iOS) |
| `FT8AudioEngine+Interruption.swift` | AVAudioSession interruption observer + recovery (iOS) |
| `FT8AudioEngine+RouteChange.swift` | Route-change observer; re-taps input + resets level metering (iOS) |
| `FT8AudioBandpassFilter.swift` | 200–2900 Hz Butterworth bandpass for FT8 sub-band level measurement |
| `FT8AudioLevel.swift` | Snapshot with wide + band-limited rms/peak and capture timestamp |
| `FT8AudioOverloadTracker.swift` | Detects sustained input overload via band-limited dBFS + watchdog |
| `FT8SessionManager.swift` | FT8 session orchestrator — decoding, auto-sequencing, QSO logging (iOS) |
| `BandPlanService.swift` | Validates frequency/mode against license class privileges |
| `FrequencyActivityService.swift` | Aggregates nearby frequency activity from RBN |
| `HamDBClient.swift` | HamDB.org API client for US callsign license class lookup |
| `UserProfileService.swift` | Persists and retrieves user profile data |
| `QuickEntryParser.swift` | Parses quick entry strings (e.g., "AJ7CM 579 WA US-0189") into structured data |
| `ActivityLogManager.swift` | Activity log lifecycle management (create, activate, log QSO, daily stats) |
| `EnvironmentalSnapshot.swift` | Sendable snapshot struct for environmental conditions charting |
| `EnvironmentalDataActor.swift` | Background actor for loading conditions from LoggingSession, ActivationMetadata, and SolarSnapshot |
| `PhoneSessionDelegate.swift` | WCSessionDelegate for Apple Watch communication (session updates, start requests) |
| `WidgetDataWriter.swift` | Writes pre-computed stats/session/solar/spots data to App Group for widget/Watch consumption |
| `AutoSyncService.swift` | Periodic foreground auto-sync service (configurable interval) |
| `BackgroundTaskAssertion.swift` | UIKit background-task wrapper keeping the process alive through critical writes (0xdead10cc guard) |
| `SolarPollingService.swift` | Background hourly solar conditions polling service |
| `DONKIPollingService.swift` | Background 30-min DONKI space weather polling service |
| `SpaceWeatherNotifier.swift` | Deduped toast + local notification for space weather events |
| `ContestCalendarClient.swift` | WA7BNM Contest Calendar RSS client with conditional GET and rate limiting |
| `ContestDateParser.swift` | Parser for contest date strings (e.g. "2200Z, Feb 27 to 2200Z, Mar 1") |
| `ContestPollingService.swift` | Background 6-hour contest calendar polling service |
| `PollingCoordinator.swift` | Single-tick coordinator that fires all registered periodic polling closures by tick multiplier |
| `PrefixRowService.swift` | Position-local prefix hot-key suggestions via Rust SessionApi (CAR-290) |
| `SettingsSyncService.swift` | iCloud KVS settings sync (pull/push/echo suppression) |
| `SettingsSyncService+Registry.swift` | Allowlist of settings that sync via iCloud KVS |
| `Radio/BLERadioTransport.swift` | CoreBluetooth transport for Nordic UART Service |
| `Radio/BLEDelegate.swift` | CoreBluetooth delegate forwarding scan/connect/data events |
| `Radio/RadioLink.swift` | @MainActor @Observable secondary CW Bridge link: its own `BLERadioTransport` (own CBCentralManager → concurrent with the primary rig), CWBP `BridgeProtocol` + `RadioSession`, detection → Kenwood/CI-V session rebuild, 500 ms freq/mode readback, `setFrequency(hz:)` (10 Hz rounded set-verify), `setMode`, `sendRawCAT`; persists its bridge under a `keyPrefix` so it never touches `RadioService`'s saved device |
| `Radio/RadioLink+Bridge.swift` | `RadioLink` CWBP event handling (handshake → 3 s status poll, USB state, detection → `RigProtocolDetector` → Kenwood/CI-V session rebuild, Yaesu slow polling), session start + 500 ms freq/mode readback |
| `Radio/RadioService.swift` | @MainActor @Observable wrapper for radio (polling, feedback loop prevention, transport picker) |
| `Radio/RadioService+Connection.swift` | Radio service connection management and protocol detection |
| `Radio/RadioService+Bridge.swift` | CW Bridge event monitoring and BridgeProtocol integration for RadioService |
| `Radio/RadioService+Profile.swift` | Parameterized `connect(toItem:)` and `currentProfileSnapshot()` — loads a per-item `RadioConnectionProfile` into the singleton's transport state |
| `Radio/RadioService+SCULAN10.swift` | SCU-LAN10 config (host/port/credentials) + connect path: builds a `RadioSession` over `SCULAN10Transport` + `YaesuProtocolHandler` |
| `Radio/RadioService+Keys.swift` | UserDefaults/Keychain key-name namespace (`RadioService.Keys`) |
| `Radio/RadioConfigMigration.swift` | One-time migration lifting the global `RadioService` UserDefaults/Keychain config onto the matching `EquipmentItem.connectionProfile`; back-fills `LoggingSession.radioItemID` by name match on `myRig` |
| `Radio/BridgeFrame.swift` | CWBP protobuf-style frame builders/parsers, BridgeEvent, capability flags |
| `Radio/BridgeProtocol.swift` | Actor: CWBP framing layer over BLE (handshake, CAT passthrough, CW keyer, set-verify) |
| `Radio/RigProtocol.swift` | Radio command protocol enum (CI-V, Kenwood) for iOS radio connections |
| `Radio/RigProtocolDetector.swift` | Detect CAT protocol (CI-V, Kenwood) from radio responses |
| `LoggingSessionManager+Radio.swift` | Radio session lifecycle integration (connect/disconnect/sync) |
| `CTYService.swift` | Singleton actor downloading and caching CTY.dat for DXCC lookups |
| `NeedsEngine.swift` | Background actor computing operator needs (DXCC, WAS, POTA, WWFF, Custom) from QSO history |
| `SpotNeedsMatcher.swift` | Aggregates engine-matched needs into the on-air summary (matching itself moved to Rust) |
| `NeedsSpotNotifier.swift` | Toast and local notification for spots matching operator needs (10-min cooldown) |
| `HamAlertExporter.swift` | Text and API export of needs as HamAlert trigger configurations |
| `NeedsWidgetWriter.swift` | Writes top needs-matched spots to shared UserDefaults for widget |


## Services - CloudSync (`swift/ios/CarrierWave/Services/CloudSync/`)

The iOS sync surface is now a thin `@MainActor` wrapper around the journal
engine that lives in `CarrierWaveData`. The per-record `CloudSyncEngine` and
`CKRecordMapper` were removed in favor of the journal-only architecture; see
`swift/packages/CarrierWaveData/FILE_INDEX.md` → CloudSync for the engine.

| File | Purpose |
|------|---------|
| `CloudSyncService.swift` | `@MainActor` service owning the `CloudSyncJournalEngine`, publishing sync status / counts / events for UI; observes `ModelContext.didSave`, runs the network-recovery monitor, and conforms to `CloudSyncJournalDelegate` |

## Services - Spotlight (`swift/ios/CarrierWave/Services/Spotlight/`)

| File | Purpose |
|------|---------|
| `SpotlightIndexer.swift` | `@MainActor` wrapper over `CSSearchableIndex` — indexes QSO/Session snapshots, deindexes by ID or domain, parses unique identifiers for tap-back, posts `didOpenSpotlightQSO`/`didOpenSpotlightSession`; also hosts `SpotlightDebugState` (`@Observable` state snapshot consumed by `SpotlightDebugView`) |
| `SpotlightSnapshot.swift` | `Sendable` value snapshots `QSOSpotlightSnapshot` + `SessionSpotlightSnapshot` built from SwiftData models; each produces a `CSSearchableItemAttributeSet` |
| `SpotlightFormatter.swift` | Pure helpers building Spotlight titles, descriptions, and keywords from snapshots (cached `DateFormatter`s, location joining) |
| `SpotlightReindexActor.swift` | Background actor that batches SwiftData fetches (fresh `ModelContext` per 1k batch) and feeds the indexer; runs full rebuild on schema version bump, incremental pass otherwise; coalesces concurrent callers; exposes `forceFullRebuild(container:)` for debug view |

## Services - Video Export (`swift/ios/CarrierWave/Services/VideoExport/`)

| File | Description |
|------|-------------|
| `VideoExportTypes.swift` | Sendable value types: VideoMoment, VideoEvent, snapshots, config |
| `VideoEventSequencer.swift` | Builds VideoTimeline from session data with time compression |
| `VideoOverlayRenderer.swift` | Core Graphics drawing for toast cards, HUD, markers, pulses |
| `VideoOverlayRenderer+HUD.swift` | HUD layer drawing (configurable density, theme presets) split out from VideoOverlayRenderer |
| `VideoOverlayRenderer+Logger.swift` | Logger overlay panel + flying card drawing (scale/opacity/translate hero animation) |
| `VideoOverlayRenderer+Toast.swift` | Toast/popup drawing split out from VideoOverlayRenderer |
| `VideoLoggerOverlay.swift` | Logger overlay state, corner-region placement scoring, hero-animation timing/interpolation |
| `VideoRenderContext.swift` | Shared per-frame render context (theme, layer toggles, HUD density) for the video pipeline |
| `VideoExportActor+SegmentAudio.swift` | Per-segment audio cut/mix logic for highlight-reel export mode |
| `VideoFrameCompositor.swift` | MKMapSnapshotter + Core Graphics layer compositing |
| `VideoWriter.swift` | AVAssetWriter wrapper for H.264 + AAC muxing |
| `VideoAudioMixer.swift` | WebSDR audio segment extraction and silence filling |
| `VideoAudioMixer+Segments.swift` | Segment-based audio writing for highlight reel mode |
| `VideoExportActor+Enrichment.swift` | QSO enrichment with callsign notes, clubs, contact counts |
| `VideoExportActor.swift` | Orchestrator: data loading, snapshot conversion, public API |
| `VideoExportActor+Pipeline.swift` | Frame loop, map snapshot coordination, writer feeding |
| `VideoExportActor+FrameState.swift` | FrameRenderState builder for each video frame |
| `VideoExportActor+Progress.swift` | Progress stream, thermal monitoring, cancellation |

## Services - WebSDR (`swift/ios/CarrierWave/Services/WebSDR/`)

| File | Purpose |
|------|---------|
| `AudioRingBuffer.swift` | Thread-safe circular buffer for audio jitter buffering between network and render threads |
| `KiwiSDRAudioEngine.swift` | AVAudioEngine-based live playback with adaptive rate from ring buffer |
| `SdrApiProvider.swift` | Shared Rust-core `SdrApi` instance (directory cache path, activities base URL) |
| `KiwiSDRClient.swift` | KiwiSDR audio client — thin wrapper over Rust `SdrApi.connect` (protocol, redirects, ADPCM decode in Rust) |
| `KiwiSDRTypes.swift` | KiwiSDRError wrapper errors (mode/passband tables live in Rust; `kiwiModeInfo`) |
| `KiwiSDRStatusFetcher.swift` | /status enrichment — delegates fetch/parse to Rust `SdrApi`, re-parses antenna for UI |
| `WebSDRDirectory.swift` | KiwiSDRReceiver model + directory proximity search — delegates to Rust `SdrApi` |
| `WebSDRRecorder.swift` | Records KiwiSDR audio frames to compressed audio file |
| `SDRReplayEngine.swift` | Rolling history buffer with instant replay of last N seconds of SDR audio |
| `WebSDRSession.swift` | Coordinates WebSDR connection, recording, playback, and resilient reconnects |
| `WebSDRSession+Internals.swift` | Internal helpers: audio stream processing, reconnect logic, recording lifecycle |
| `TuneInManager.swift` | Standalone "Tune In" session manager: strategy picker, cellular warning, spot metadata, CW transcription wiring |
| `TuneInManager+ReceiverSelection.swift` | Strategy-based receiver selection — strategies run in Rust `SdrApi`; park/summit coords resolved locally |
| `TuneInManager+SmartFeatures.swift` | Smart features: QSY + receiver-quality monitors (Rust-side, callback listeners), follow activator persistence |
| `RecordingPlaybackEngine.swift` | @Observable AVAudioPlayer wrapper with seeking, speed control, amplitude envelope, QSO sync, transcript tracking |
| `RecordingClipExporter.swift` | M4A clip export from recordings with AVAssetExportSession and metadata embedding |
| `CWSWLClient.swift` | Actor for cw-swl server communication (upload, transcribe, poll, download transcript) |

## Services - Query Language (`swift/ios/CarrierWave/Services/QueryLanguage/`)

Most Query Language types are now in CarrierWaveCore. Only the compiler remains in the main app.

| File | Purpose |
|------|---------|
| `QueryCompiler.swift` | Core compiler (expression/term dispatch, CompiledQuery struct) |
| `QueryCompiler+StringFields.swift` | String and optional string field matching |
| `QueryCompiler+NumericFields.swift` | Numeric and optional int field matching |
| `QueryCompiler+DateStatusFields.swift` | Date, status (confirmed/synced/pending), source, and bare term matching |
| `QueryCompiler+Predicates.swift` | Predicate extraction for FetchDescriptor optimization and predicate helpers |

## Services - Remote (`swift/ios/CarrierWave/Services/Remote/`)

Live phone-to-Mac remote-control link. Pairs iOS Field with CW Sweep over Bonjour-discovered TCP using shared `RemoteOp` Codable frames from CarrierWaveCore. Gated by the `.remoteSweep` experimental flag.

| File | Purpose |
|------|---------|
| `RemoteSweepDiscovery.swift` | @MainActor @Observable Bonjour browser publishing `DiscoveredSweep` values for the pairing UI |
| `MultipeerSweepBrowser.swift` | @MainActor @Observable MultipeerConnectivity browser for off-LAN Sweeps (BT + AWDL peer Wi-Fi); invites yield a connected `MultipeerTransport` |
| `RemoteSweepClient.swift` | Actor: drives a `RemoteOpTransport` (LAN TCP or MPC), runs hello/pair handshake, framed receive loop, command/ack correlation |
| `RemoteSweepCoordinator+Multipeer.swift` | Off-LAN connect path: wraps the MPC browser's session into the same client pipeline the LAN path uses |
| `RemoteSweepClient+CW.swift` | Actor extension: `sendCWText` / `stopCW` / `setCWSpeed` / `playCWSlot` typed sends |
| `RemoteSweepCoordinator.swift` | @MainActor @Observable hub: connect/disconnect, pair, tune, routes inbound events to typed state including `cwStatus`/`remoteActiveSession`; subscribes to `activeSession` topic on connect |
| `RemoteSweepCoordinator+CW.swift` | CW keyer commands forwarded over RemoteOp (`cwSendText`/`cwStop`/`cwSetSpeed`/`cwPlaySlot`/`cwSetSlot`) plus `recordError` setter helper |
| `RemoteSweepCoordinator+Session.swift` | Active-session continuity: forwards inbound `eventActiveSession` to `LoggingSessionManager` and pushes local-active changes to Sweep via `cwLocalActiveSessionChanged` observer |
| `RemoteSweepCoordinator+Waterfall.swift` | Waterfall topic handling: dequantizes incoming `WaterfallLineEvent` into the rolling buffer, gates subscription to view visibility |
| `RemoteSweepAutoConnect.swift` | Silent auto-reconnect helper: NWBrowser watching for the preferred Sweep on the LAN, restarts on app foreground, fires `coordinator.connect(...)` when a known peer reappears |
| `RemoteSweepKeychain.swift` | Per-host bearer-token persistence (save/load/delete) using Keychain `kSecClassGenericPassword` |
| `RemoteQSOContext.swift` | @MainActor @Observable: callsign + QRZ-resolved name + RST/serial/exchange feeding the Remote-tab keyer macro substitutions; debounces lookups via `CallsignLookupService` |

## Services - Band Scope (`swift/ios/CarrierWave/Services/BandScope/`)

Logic layer for the Band Scope v2 two-lens spot browser (`.bandScope` experimental flag): goal-profile filtering compiled to SQL in Rust (`compile_profile_queries` FFI) and run against the spot engine's `scope.spots` projection; spot data rides the regular engine snapshot.

| File | Purpose |
|------|---------|
| `BandScopeTunables.swift` | Every spec (§18) constant: cluster width, gap threshold, fade/anchor decay curves, dim opacity, time buckets |
| `GoalProfile.swift` | Codable profile (predicate, goals→needed, clubs) + built-ins (Everything/Parks/DXCC/Club skeds) + FFI mapping; `QuickToggles` (WPM ceiling, worked-today, RBN) |
| `GoalProfileStore.swift` | @MainActor @Observable: active profile + toggles (UserDefaults), user-defined profiles (App Support JSON) |
| `BandScopeFilterService.swift` | Compiles profile+toggles → per-lens SQL (Rust), runs via `runQuery` per engine generation, publishes scope-dim / heard-hide / wpm-dim spot-id sets; seeds SKCC roster into `scope.club_members` |
| `BandScopeViewModel.swift` | Shared @Observable for both lenses: snapshot consumption, Scope clustering/gaps per band, Heard batching (pending pill, unseen boundary, band tiles), scrubber↔scroll sync, anchor declarations |
| `SpotTier.swift` | Tier assignment (needed > club > pota > rbn) + profile-filtered needs/chip selection; `NeedCategory.profileKey` mirror of Rust keys |
| `AnchorState.swift` | Dial-by-declaration anchor (§6): trust decay curve, auto-clear, band-change clear (`BandScopeAnchor` + `AnchorStore`) |
| `FreshnessFade.swift` | Scope-only age→opacity curve (1.0 ≤2 min → 0.4 floor at 30 min) |
| `ScopeClustering.swift` | PURE: chained 0.45 kHz pileup clustering, gap dividers, edit-distance-1 busted-copy detection |
| `HeardAggregation.swift` | PURE: per-callsign collapse (latest wins, N×), time buckets, reverse-chron sort |

## Services - RustStore (`swift/ios/CarrierWave/Services/RustStore/`)

> The write seams (`QSOWriteSink`, `EntityWriteSink` + factory, `SeamWriteBatch`, `OffMainStoreSeam`) moved to `CarrierWaveData/RustStore` on 2026-10-05 so CW Sweep shares them.

Write-side seams for the SwiftData→cw-store migration. Each `*WriteSink` routes by `CwStoreQSOMode`: in `on` it writes cw-store FIRST (canonical) then a mirror-suppressed SwiftData save; otherwise the `CwStoreMirror` dual-writes (`shadow`) or nothing happens (`off`).

| File | Purpose |
|------|---------|
| `CwStoreMirror.swift` | Observes `ModelContext` save notifications, dual-writes all 12 entities into cw-store; seam-write echo suppression; serial `CwStoreMirrorActor` |
| `ServicePresenceWriteSink.swift` | Main-actor standalone ServicePresence write authority for sync-upload marking (presence not riding a QSO save) |

